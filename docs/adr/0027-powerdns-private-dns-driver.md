---
title: "ADR-0027: PowerDNS serves the private zone with the pdns driver"
description: Add pdns to dns.private.driver. PowerDNS Authoritative runs in the cluster with a CloudNativePG database, and external-dns writes records through the PowerDNS REST API with an API key, so no component needs direct access to etcd.
---

# ADR-0027: PowerDNS serves the private zone with the pdns driver

## Status

Proposed (2026-11-14). Builds on [ADR-0018](0018-database-postgres-cloud-split.md)
for the in-cluster database and on [ADR-0020](0020-helm-chart-registry.md) for
the chart registry. `dns.private.driver` came from core#3308. This ADR MUST be
accepted before or with the merge of the `pdns` driver PR. Scope is every
platform, with `vsphere`, `hyperv`, `aws`, `azure`, and `gcp` as the platforms
that MUST work (section 7).

## Context

`dns.private.driver: coredns` runs CoreDNS with an etcd backend. CoreDNS has no
write API, so external-dns writes records straight into etcd. That needs a
dedicated etcd StatefulSet, client certificates for external-dns, and a network
policy for the etcd client port. Every part of it exists only to work around the
missing API.

These facts decide the design:

- The external-dns image that `core` pins is `v0.23.0`, with chart `1.23.0`.
  Its tutorial for the `pdns` provider says the provider needs PowerDNS
  Authoritative 4.1 or later, takes `--pdns-server`, `--pdns-server-id`, and
  `--pdns-api-key`, and does not create zones. The provider is in tree. The
  latest external-dns release is `v0.24.0` (2026-11-14), and it keeps the `pdns`,
  `rfc2136`, and `coredns` providers in tree.
- The `dns` facet already runs one external-dns instance for each zone. The
  `coredns` provider component and the `hetzner` webhook provider component
  are the patterns for a new provider component.
- CloudNativePG is already in `core` as the in-cluster PostgreSQL service. The
  `identity` facet turns it on for Keycloak, and the `keycloak-db` cluster is
  the pattern for a database owned by one add-on.
- `external-dns` has no confirmed leader election at the pinned version. The
  `dns` facet therefore never scales it with `topology: ha`.
- The ACME `private-acme` ClusterIssuer has no DNS-01 solver
  (core#3318). A solver needs a private zone that the cluster writes.
- ADR-0020 and sdlc ADR 0001 require an `artifact` tag on each chart and image,
  and the CI run in registry mode MUST still pass.

## Decision

### 1. PowerDNS Authoritative, not BIND or Knot through rfc2136

The `pdns` driver runs PowerDNS Authoritative with the `gpgsql` backend.
external-dns writes records through the PowerDNS REST API with the `pdns`
provider.

| | PowerDNS with `pdns` | BIND or Knot with `rfc2136` |
| --- | --- | --- |
| Write path | REST API and one API key | RFC 2136 updates signed with a TSIG key |
| State | PostgreSQL | A zone file or journal on a volume |
| Zone creation | One API call | A change to the server configuration |
| Replicas | Several, over one database | One primary; secondaries need zone transfer |
| New components | A database cluster | None |
| Operator familiarity | A hosted-DNS style API | A classic DNS style |

PowerDNS is the recommendation. Its API matches the model of a hosted DNS, the
zone and the records live in one database that `core` already knows how to
run, and replicas share that database without zone transfer.

These conditions change the choice to `rfc2136`:

- A context MUST NOT run a database, for example the smallest local
  contexts. BIND or Knot then has fewer parts.
- The CloudNativePG operator is unavailable on a platform.
- A user already runs a BIND or Knot primary and wants the cluster to update
  it. That is a user-owned server and needs no driver of its own. A later ADR
  MAY add an `rfc2136` driver.

PowerDNS also accepts RFC 2136 updates when `dnsupdate` is on. A later ADR MAY
use that for a solver without a second server.

### 2. Driver value and fields

- The value is `pdns`. The enum becomes `cloud`, `coredns`, `pdns`, `none`.
  The value names the server, as `coredns` does.
- The zone is `dns.private_domain`. There is no new zone field. The driver
  creates that zone, and a second zone for `dns.public_domain` where CoreDNS
  serves the public zone today (`dns_private_effective.public_zone`). The
  `pdns` driver replaces `coredns` as a whole, so it MUST serve the same
  zones.
- The one new field is `dns.private.pdns.api_key`. It is a secret reference in
  `values.yaml`, written as a SOPS or 1Password secret, and the facet writes
  it into a `Secret` in `system-dns` with the `secrets:` mechanism. The facet
  MUST NOT put the key in a ConfigMap, a substitution, or a rendered value.
- When `dns.private.pdns.api_key` is unset and `dev` is `true`, the facet uses
  a fixed development key. When it is unset and `dev` is not `true`, a
  `requires` rule rejects the context. The message names the field.
- Replicas come from `topology`: one PowerDNS replica for the default topology
  and two for `topology: ha`. The schema has no replica field, because the
  schema states intent and not module settings.
- `dns.private.enabled: true` stays an alias for `coredns`. The default driver
  does not change. A context chooses `pdns` explicitly.

### 3. Database

A CloudNativePG `Cluster` named `pdns-db` runs in `system-dns`. It follows the
`keycloak-db` pattern: `initdb` creates the `pdns` database and the `pdns`
role, CNPG writes the credentials to `pdns-db-app`, and PowerDNS reads them
from that secret. The Postgres image carries a digest and an `artifact` tag.

- The PowerDNS `gpgsql` schema reaches the database through
  `bootstrap.initdb.postInitApplicationSQLRefs`, from a ConfigMap that holds
  the upstream `schema.pgsql` for the pinned PowerDNS release.
- The cluster has one instance by default and three under `topology: ha`, with
  required anti-affinity, as the `keycloak-db` overlay does.
- The `dns` facet turns on `database.postgres.enabled`, as the `identity` facet
  does for Keycloak, and the `dns` kustomization waits for the operator.
  A `healthCheckExprs` check on the `Cluster` `Ready` condition gates the
  PowerDNS tier, because kstatus reports a CNPG `Cluster` as current when it
  is applied.
- Backup: M12 adds no database backup. The records come from Gateway and
  HTTPRoute sources, and external-dns writes them again when the database is
  empty. A record that a person adds by hand is lost if the volume is lost.
  The guide MUST say so. A later change MAY add CNPG backup to the object
  store of ADR-0006.
- `topology: ha`: PowerDNS and the database scale. external-dns stays at one
  replica, as in the `coredns` driver. While its pod is down, PowerDNS keeps
  answering and no record changes. PowerDNS caches answers for a short time
  (`cache-ttl`), so a record change reaches all replicas within that time.

### 4. Component layout

`pdns` ships as manifests in the repository and not as a chart. PowerDNS has
no chart that the PowerDNS project maintains. Manifests need one image
`artifact` tag and no chart tag, and the chart registry has nothing to mirror
for them.

```text
kustomize/dns/install/pdns/
  kustomization.yaml     Deployment, Service, ConfigMap, ServiceAccount
  database/              pdns-db Cluster, schema ConfigMap
  zone-init/             Job that creates the zones through the API
  network-policy/        policies of section 8
  ha/                    two replicas, anti-affinity
  prometheus/            ServiceMonitor on the API metrics endpoint
  loadbalancer/          Service type LoadBalancer (Cilium)
  cilium/                LBIPAM annotation
  gateway/               TCPRoute and UDPRoute on port 53 (Envoy)
kustomize/dns/resources/external-dns/providers/pdns/
  kustomization.yaml     component with a HelmRelease patch
  patches/helm-release.yaml
```

- The components mirror the `coredns` component set, so the Cilium and Envoy
  exposure of port 53 stays the same. Resolvers keep the same address when a
  context switches drivers.
- A new facet, `addon-private-dns-pdns.yaml`, has `when: dns.private.driver ==
  'pdns'`. `addon-private-dns.yaml` keeps its `coredns` condition and is not
  edited. Two facets avoid one file with two sets of conditions.
- The `pdns` provider component sets `provider.name: pdns`,
  `EXTERNAL_DNS_PDNS_SERVER` to the in-cluster API URL, and the API key from
  the `pdns-api` secret. It keeps `registry: txt`, `policy: sync`, and
  `txtOwnerId`, as the `hetzner` component does.
- The zone-init Job calls the API to create each zone with its SOA and NS
  records. It is idempotent. external-dns does not create zones, so without
  this Job the first record write fails.
- The PowerDNS image is `docker.io/powerdns/pdns-auth-<branch>`. The PR picks
  the current stable branch and pins it by tag and digest. This ADR does not
  pin a version, because the choice depends on the release at build time.
- Each image has an `artifact: type=image` tag: PowerDNS, the Postgres image,
  and the zone-init Job image. The Job image MUST be one that the repository
  already pins, for example `docker.io/alpine/k8s`. The `system-dns` namespace
  is under the Kyverno `require-image-digest` policy, so each image has a
  digest.
- The PR MUST run the CI registry-mode job and the `windsor show artifacts`
  check, and both MUST pass.
- The PR MUST confirm the `pdns` provider against external-dns `v0.23.0`
  and chart `1.23.0`: the flag and environment names, the TLS flags, and the
  record types the provider writes. If the provider needs a newer
  external-dns, the PR raises the pin, and that change uses the normal
  upgrade path.

### 5. Migration from coredns

A context MAY switch `dns.private.driver` from `coredns` to `pdns`.

- The `dns` kustomization changes its components. Flux prunes CoreDNS and
  etcd, and creates PowerDNS and the database. The port 53 address does not
  change, so no resolver needs an edit.
- Records that external-dns wrote are written again. The Gateway and HTTPRoute
  sources hold them, and the new instance has a new TXT owner registry.
- Records that a person put into etcd by hand are lost. The etcd volume is
  not read. The migration guide MUST say so.
- The switch is a loss of DNS answers for the time between the CoreDNS prune
  and the first external-dns sync. The guide MUST give that time as measured
  by the CI test, not as a guess.
- A switch back from `pdns` to `coredns` works the same way and loses the
  records in the same way.

### 6. The DNS-01 solver for core#3318

The solver stays out of M12. The `pdns` zone gives the solver these things:

- A zone that the cluster writes through an API. This is the missing piece
  that core#3318 names.
- A choice of solver. The cert-manager PowerDNS webhook solver (for example
  `zachomedia/cert-manager-webhook-pdns`) uses the same API. cert-manager
  also has a built-in `rfc2136` solver, and PowerDNS accepts RFC 2136 updates
  with `dnsupdate` and a TSIG key. The solver ADR chooses between them.
- A requirement on the ACME server. A step-ca or Vault ACME server MUST
  resolve the `_acme-challenge` TXT record from this zone, so it MUST use the
  PowerDNS address as a resolver or have the zone delegated to it.

A solver needs write access to the API. PowerDNS has one API key for each
server, with no per-zone limit, so the solver ADR MUST decide whether it reuses
the key or uses TSIG. M12 stores the API key in a form that another namespace
can read through a copy, and does not decide the copy.

### 7. Platform scope

- `vsphere` and `hyperv` have no cloud private zone. `pdns` is their primary
  target and MUST work, with the Cilium and Envoy exposure of the `coredns`
  driver.
- `aws`, `azure`, and `gcp` default to the `cloud` driver. On them, `pdns` is
  an opt-in alternative. The CI test (section 9) runs on one of them to prove
  it works. Cloud contexts have a managed database option (ADR-0018), and the
  `pdns` driver MUST NOT use it in M12. It uses the in-cluster database on
  every platform.
- `proxmox`, `incus`, `hetzner`, and `metal` use the same manifests. Nothing in
  the driver is platform specific, so they work without extra code. A defect
  on one of them MUST NOT block the release.
- On a workstation context, `coredns` reaches the node port, and `pdns` does
  the same. The `requires` rule of `addon-private-dns.yaml` that rejects a
  NodePort for port 53 applies to `pdns` too.

### 8. Security

- The PowerDNS API and its metrics endpoint listen on a `ClusterIP` Service.
  No Gateway route, load balancer, or node port exposes port 8081.
- The API key is not in git. It comes from a SOPS or 1Password secret, and the
  facet writes it with `secrets:`. The `show blueprint` output MUST NOT print
  it.
- The PowerDNS pods read the key and the database credentials from `Secret`
  volumes or `secretKeyRef`, and never from a ConfigMap.
- Network policy: the API accepts connections only from the external-dns pods
  and the zone-init Job. The database accepts connections only from PowerDNS.
  Port 53 accepts connections from any source, because resolvers need it. The
  policies are `NetworkPolicy` objects. Cilium enforces them. On a CNI that
  does not enforce `NetworkPolicy`, the objects have no effect, and the guide
  MUST say so.
- The development key in section 2 MUST NOT apply when `dev` is not `true`.

### 9. Tests and docs

- A facet test file covers the `pdns` driver in the cases of
  `addon-private-dns.test.yaml`: Cilium and Envoy exposure, `topology: ha`,
  the public zone, and the rejected combinations.
- A CI test context sets `dns.private.driver: pdns`. It creates a record from
  a `Gateway` route and resolves it in the cluster.
- A `docs` guide lists the private DNS drivers and says when to use `pdns`
  instead of `coredns`. It states the loss of hand-made records.

## Upgrade stability

- The default driver does not change. A context that does not set
  `dns.private.driver: pdns` renders the same blueprint as before.
- The new schema field and enum value are additive.
- Switching drivers is the only change that moves records (section 5).

## Consequences

- A context gets a private zone with an API that other tools can use. The
  etcd StatefulSet, its certificates, and its network policy are not needed
  by `pdns`.
- A `pdns` context runs a PostgreSQL cluster in `system-dns`. A context
  that cannot run a database keeps `coredns`.
- The `dns` kustomization depends on the database operator when the driver is
  `pdns`.
- PowerDNS is a new image for each release to track. Renovate MUST cover it.
- `coredns` stays. Removing it is a separate decision after `pdns` ships.

## Open questions

1. Does the user accept PowerDNS over BIND or Knot? This ADR says yes and
   names the conditions that change it (section 1).
2. Does the zone-init Job stay a Job, or does the PowerDNS pod create the zones
   in an init container? This ADR says Job, because the API is the one write
   path.
3. Does the key come from the user or does the cluster generate it? This ADR
   says the user supplies it, with a development default. A generated key
   needs ESO or a Job and a second secret path.
4. Does `pdns` serve the public zone on non-cloud platforms, as `coredns` does?
   This ADR says yes.
5. Which backup does a later change add? This ADR adds none.

## Alternatives considered

- BIND or Knot with `rfc2136`. Rejected as the default in section 1. It is the
  fallback if a context cannot run a database.
- CoreDNS with etcd (the current driver). Kept for existing contexts. It
  needs direct etcd access.
- CoreDNS with the `file` or `auto` plugin and a ConfigMap. Rejected: external-dns
  has no provider that writes a ConfigMap zone, so a custom controller would be
  needed.
- A community PowerDNS chart. Rejected: it adds a chart to pin, tag, and
  mirror, and the manifests are small.
- The managed database of ADR-0018 on cloud platforms. Rejected for M12: it
  adds a Crossplane path to a component that is small.
- The `webhook` provider with a custom bridge. Rejected: the in-tree `pdns`
  provider does the job.
