---
title: "ADR-0001: Split external and internal gateways, DNS, and endpoints"
description: Replace the single gateway and the global gateway.access flip with two optional gateways (external and internal), each provisioned from its domain and carrying its own load balancer, certificate issuer, and DNS zone, so utility services bind to the internal endpoint and applications choose their gateway per route.
---

# ADR-0001: Split external and internal gateways, DNS, and endpoints

## Status

Proposed (2026-06-25). A prior attempt landed milestones 1-3 on
`feat/gateway-external-internal-split`, but that branch was never merged and
is not an ancestor of `main` — the running code is still exactly the
pre-ADR single-gateway, single-domain, `gateway.access`-driven model
described in Context below. All three milestones remain to be done, either
by rebasing that branch onto current `main` or redoing the work.

## Context

Today the blueprint exposes one Gateway object, named `external`, in
`system-gateway`. A single global knob, `gateway.access: public | private`,
decides what that one gateway is. Setting it to `private` cascades through
several facets at once: the cloud load balancer scheme flips to internal
(`aws-load-balancer-scheme: internal`, `azure-load-balancer-internal: true`),
external-dns publishes to `dns.private_domain` instead of `dns.public_domain`,
and the gateway certificate switches from the `public-acme` issuer to a
`private` self-signed or CA issuer.

Every HTTPRoute attaches to that one gateway. Utility services
(`grafana`, `kibana`, the Flux web UI) attach the same way, with hostnames
resolved from a single `external_domain` substitution that is the public
domain when set and the private domain otherwise.

The model is all-or-nothing. A cluster is either entirely public or entirely
private. There is no way to run both at once, which is the normal production
posture: applications reachable from the internet on `app.example.com`, and
operational surfaces (dashboards, log viewers, the GitOps UI) reachable only
from inside the VPC or the operator's network. The current workaround is to
make the whole cluster private and reach apps some other way, or make it
public and accept that the dashboards inherit the public gateway's domain and
exposure.

Three forces make the single-gateway model wrong as the blueprint grows:

- **Exposure is per-service, not per-cluster.** Whether something faces the
  internet is a property of the individual route, not a cluster-wide setting.
  A global flip cannot express "these routes external, those routes internal."
- **Utility services have a fixed answer.** Operational surfaces should never
  be on an internet-facing endpoint. That intent is currently advisory;
  nothing in the model enforces it, and on a public cluster the dashboards are
  published to the public zone.
- **Local development cannot rehearse the split.** A developer on
  docker-desktop or Talos has one gateway and one domain (`*.test`), so the
  external/internal distinction that matters in production is invisible until
  it reaches a cloud context.

The pieces needed for a split already exist independently. The schema carries
both `dns.public_domain` and `dns.private_domain`. The PKI layer issues from
both a public issuer (`public-acme` or `public-selfsigned`) and a private one
(`private-selfsigned` or `private-ca`). The cloud platform facets already know
how to annotate a load balancer as internal or internet-facing. What is
missing is two endpoints to attach these to at the same time.

This follows the common Kubernetes pattern of running two ingress points split
by audience: an external (internet-facing) one and an internal one, each behind
its own load balancer, with each workload choosing the one it attaches to. The
classic form is two ingress controllers split by `ingressClassName`; the
Gateway API form, which the blueprint already uses, is two `Gateway` objects
chosen through `parentRefs`.

## Decision

Run two optional gateways, distinguished by audience, each provisioned from its
domain, and let each route choose which one it attaches to.

### Two optional gateways

Add a second Gateway object alongside the existing `external` one in
`system-gateway`:

| gateway | audience | provisioned when | domain | issuer | load balancer |
|---------|----------|------------------|--------|--------|---------------|
| **external** | internet | `dns.public_domain` set, or a tunnel driver configured | `dns.public_domain`, wildcard `*.<public_domain>` | `public-acme` or `public-selfsigned` | internet-facing scheme / routable IP |
| **internal** | operators, in-VPC, workstation | `dns.private_domain` set | `dns.private_domain`, wildcard `*.<private_domain>` | `private-ca` or `private-selfsigned` | internal scheme / private IP pool |

Each gateway has the same listener set the single gateway has today (HTTP on
80, HTTPS on 443, plus the conditional DNS and Flux-webhook listeners where
they apply), its own terminating TLS Secret, and its own data plane.

### Both gateways are optional and symmetric

Neither gateway is mandatory. Each is provisioned only when its domain is set,
the same rule on both sides: the external gateway when `dns.public_domain` is
set (or a tunnel driver is configured, which is the only other way external
traffic reaches the cluster), the internal gateway when `dns.private_domain` is
set. A cluster with neither domain has no ingress at all; a cluster with one
domain has one gateway; a cluster with both has both.

Only workstation/dev mode supplies a default domain: `dns.private_domain`
defaults to `test` there, so a local cluster comes up with an internal gateway
without configuration. In every other mode nothing is defaulted; the prior
fallback of `dns.private_domain` to `dns.domain` is dropped. If neither domain
is set, no gateway, load balancer, certificate, or DNS record is created.
`dns.public_domain` is never auto-filled in any mode, so the external gateway
and its internet-facing load balancer are always opt-in.

### Vocabulary follows each layer's convention

The naming keeps each subsystem's native term rather than forcing one word
across all of them:

- **Gateways and load balancers** use **external / internal**, matching the
  Kubernetes ingress-class convention and the cloud load-balancer scheme words
  (`internet-facing` / `internal`). The existing Gateway is already named
  `external`, so it keeps its name and the new one is `internal`.
- **DNS and certificates** use **public / private**, matching
  `dns.public_domain`, `dns.private_domain`, the public/private hosted zones,
  and the `public-*` / `private-*` issuer names already in the PKI layer.

The two axes map one to one: external gateway ↔ `public_domain` ↔ public zone ↔
public issuer ↔ internet-facing load balancer; internal gateway ↔
`private_domain` ↔ private zone ↔ private issuer ↔ internal load balancer.

### Exposure becomes route binding, not a global flip

A route's audience is the gateway it names in `parentRefs`. This replaces the
global `gateway.access` knob:

- Utility and system routes bind to the **internal** gateway only. This is
  fixed in the kustomize components; it is not an operator choice. An
  internal-only utility therefore needs `dns.private_domain` set: workstation/dev
  mode supplies `test` automatically, and other modes require the operator to
  set it, with no internal gateway and no utilities exposed until they do.
- Application routes name whichever gateway they need. The blueprint does not
  own application routes, so it imposes no global default; the demo routes it
  ships bind to the internal gateway.

`gateway.access` is deprecated. Its old values map onto the new domain-driven
provisioning so existing contexts compose to the same result: a cluster that
set `gateway.access: private` already has only `dns.private_domain`, so it gets
exactly one gateway, the internal one. A cluster that set `gateway.access:
public` with a `dns.public_domain` gets the external gateway, plus an internal
gateway for its utilities, which is the intended change.

### One load balancer per gateway

Each gateway gets its own load balancer, wired by the platform facet:

- **AWS:** two NLBs. The external gateway's service carries
  `aws-load-balancer-scheme: internet-facing`; the internal gateway's carries
  `internal`.
- **Azure:** two Standard load balancers. The internal gateway's service
  carries `azure-load-balancer-internal: true`; the external one does not.
- **metallb / Cilium LBIPAM (Talos, incus, metal):** two addresses, the
  internal one from the cluster pool and the external one from whatever range
  is routable for that environment. On a flat home LAN both may sit on the same
  subnet; "external" is relative to the environment, and that is acceptable.
- **NodePort (docker-desktop, hyperv):** two node-port sets, both published by
  the workstation forwarder, so both domains resolve locally.
- **Tunnel (planned):** a future tunnel driver (cloudflared or equivalent)
  fronts the external gateway only and its service drops to `ClusterIP`; the
  internal gateway is never tunneled.

This is the load-balancer side of the framing: an internal load balancer points
at the internal gateway and an external load balancer points at the external
one, and routing a service is a matter of which gateway it attaches to.

Today the Envoy load-balancer annotations are set once, globally, on the
envoy-gateway HelmRelease (`base/envoy/loadbalancer/patches/helm-release.yaml`
patches the shared `envoyService`). Two gateways with different schemes cannot
share one global service config. Each gateway must reference its own
`EnvoyProxy` resource through `spec.infrastructure.parametersRef`, so the
external and internal data-plane services are provisioned and annotated
independently. The Cilium driver already gives each Gateway its own service
through `infrastructure.annotations`, so the LBIPAM IP and a distinct
sharing-key move onto the per-gateway annotations.

### DNS routes by hostname suffix

external-dns runs with both `dns.public_domain` and `dns.private_domain` in its
domain filters. External-gateway routes use `*.<public_domain>` hostnames and
publish to the public zone; internal-gateway routes use `*.<private_domain>`
hostnames and publish to the private zone. Because the two domains are distinct,
the suffix selects the zone with no per-gateway external-dns instance. The
existing cloud zone-id filters continue to scope each zone to its hosted-zone or
Azure resource id.

Suffix routing assumes the two domains differ, which is the cloud default. When
they are equal (a single-domain or split-horizon setup), the suffix no longer
tells the zones apart and each hostname must be unique to one gateway; see Local
development and the split-horizon alternative.

### Local development

Workstation mode supplies `dns.private_domain: test` by default, so a plain
local cluster comes up with a single internal gateway at `*.test` and no
external exposure.

To rehearse both gateways locally, also set `dns.public_domain`. Two
arrangements work:

- **Distinct domains (recommended):** `dns.private_domain: private.test`,
  `dns.public_domain: public.test`. The workstation resolver resolves both
  `*.private.test` and `*.public.test` to the cluster ingress, so
  `grafana.private.test` lands on the internal gateway and `app.public.test` on
  the external one. This mirrors the cloud distinct-domain model exactly,
  including external-dns suffix routing.
- **Single domain:** the same value, e.g. `local.test`, for both. Both gateways
  are still provisioned, each from its own domain field. Because the workstation
  runs one CoreDNS, every unique hostname gets one record pointing at whichever
  gateway its route binds to (`grafana.local.test` internal, `app.local.test`
  external). This exercises the single-domain data path that the cloud
  split-horizon work will later build on.

A single local resolver cannot faithfully reproduce true split-horizon: the
same FQDN answering with the internal load balancer to in-network clients and
the external one to outside clients. That depends on two vantage points and two
zones, which exist only on a cloud platform. Locally, either each hostname lives
on one gateway (single domain) or the two gateways use distinct domains; the
same-name-two-answers case is validated in a cloud context.

## Consequences

Operational surfaces are internal by construction. Utility routes name the
internal gateway in the kustomize component, so a public cluster no longer
publishes its dashboards to the public zone. This is the central goal.

Operators gain a coherent two-endpoint model and lose the single
`gateway.access` flip. The migration is quiet: existing private clusters keep
exactly one gateway (now named `internal` rather than `external`), and existing
public clusters gain an internal gateway they did not have, which is additive.

In-repo routes that hardcode `name: external` are repointed as part of the
migration: utility routes to `internal`, demo routes likewise. A private-only
cluster no longer has a Gateway named `external`, so any out-of-repo route that
hardcoded that name must move to `internal`. The Gateway name `external` is not
renamed, but its meaning narrows to internet-facing only.

The Envoy driver needs per-gateway `EnvoyProxy` resources rather than the one
global `envoyService` patch. This is the largest piece of implementation work
and touches the `base/envoy/loadbalancer` and `nodeport` patch trees. The
Cilium driver needs the LBIPAM annotations moved onto each gateway's
`infrastructure.annotations`, with a distinct sharing-key per gateway.

Up to two certificates are issued, one per provisioned gateway, from two
issuers. The internal gateway's wildcard comes from the private issuer and the
external one from the public issuer, which is already how the issuers are
selected today, now applied once per gateway rather than once per cluster.

The blueprint runs two data planes where it ran one whenever both domains are
set, which costs additional load-balancer resources on cloud platforms and an
additional address from the metallb pool. A cluster with only one domain pays
for only one, since the other gateway is not provisioned.

Application exposure moves into the application's own route definition. This is
more explicit than a cluster setting and is the correct altitude, since the
blueprint does not own application routes. A future per-service `expose:
external | internal | both` field could desugar into the right `parentRefs` if
authoring sugar proves worthwhile; it is deferred until there is demand.

## Alternatives considered

**Keep one gateway, add per-route external/internal listeners (rejected).** A
single Gateway can carry both an external and an internal listener, with routes
attaching to one section. This fails at the load balancer: one Gateway maps to
one data-plane service and one load balancer, so a single internet-facing LB
would still front the "internal" listener. The split has to exist at the
load-balancer boundary, which means two services, which means two gateways.

**Keep `gateway.access` and add a second, parallel knob (rejected).** Adding
`gateway.internal_access` or similar doubles the global flips without making
exposure a per-route property. It still cannot express a mix of external and
internal routes on one cluster, which is the requirement.

**Always provision the internal gateway (rejected).** An earlier draft made the
internal gateway mandatory and the external one opt-in. Keying both to their
domains is simpler and symmetric, follows the common convention where neither
endpoint is special, and lets a public-only cluster exist without an unused
internal gateway. Because `dns.private_domain` still defaults to `test` in
workstation/dev mode, the internal gateway is present locally without
configuration; other modes opt in by setting the domain, the same as the
external side.

**Force one vocabulary across all layers (rejected).** Renaming
`dns.public_domain` to `external_domain`, or the Gateway to `public`, would make
one word span DNS, gateways, and load balancers. Each subsystem already has an
entrenched convention (public/private hosted zones and issuers; internal/
external ingress classes and LB schemes), and aligning to those reads more
naturally to operators than a single coined term. The one-to-one mapping is
stated once and is easy to follow.

**Split-horizon on a single domain (deferred).** Serving the same domain from
both a public and a private zone, with the private view resolving to the
internal gateway, avoids a second domain. It needs per-gateway external-dns
instances scoped to each zone and careful resolver precedence, and it muddies
certificate issuance because one name maps to two issuers. Distinct public and
private domains keep zone routing to a hostname-suffix match and keep one issuer
per name. Split-horizon can be layered later for operators who require a single
domain.

**A per-service `expose:` schema field now (deferred).** Cleaner for
application authors than hand-writing `parentRefs`, but it is sugar over the
route binding this ADR establishes, and the binding has to exist first. Deferred
until the two-gateway model is in place and demand is clear.

## Implementation milestones

Each milestone is one PR. The work is core-only; no cli api or composer change
is needed, since the split is expressed entirely in kustomize routes and facet
wiring.

1. **core — per-gateway data-plane plumbing.** Refactor the load-balancer
   wiring so each Gateway carries its own service configuration: a per-gateway
   `EnvoyProxy` referenced through `spec.infrastructure.parametersRef` for the
   Envoy driver, and per-gateway `infrastructure.annotations` (with a distinct
   LBIPAM sharing-key) for Cilium, replacing the global `envoyService` patch.
   The EnvoyProxy must be self-contained — it carries the Kyverno digest-pin
   `envoyDeployment` patch as well as the `envoyService` config, and the
   EnvoyGateway helm config keeps no default `envoyProxy` patch. Attaching an
   EnvoyProxy makes the controller merge it against the EnvoyGateway defaults,
   and on 1.8.1 a patch-bearing default breaks that merge (`mergeType:
   StrategicMerge` errors on the opaque `patch.value.spec`; `JSONMerge`
   duplicates listener ports). Emptying the default and letting the EnvoyProxy
   be authoritative renders the same data plane. Verified end-to-end on a live
   cluster: Gateway `Programmed=True`, ports unchanged, digest pin preserved.

2. **core — split into external and internal gateways.** Turn the single
   gateway resource into two domain-gated Gateways with their per-platform load
   balancer schemes, per-gateway issuer and certificate, and the external-dns
   suffix routing. Deprecate `gateway.access`, mapping its values onto the
   domain-driven provisioning. Repoint every in-repo route atomically in the
   same PR (utilities and the DNS and Flux-webhook listeners to `internal`, demo
   routes likewise), so no commit leaves a route pointing at a gateway that does
   not exist. Depends on (1). Landable per-driver (envoy, then cilium) or
   per-platform if review size warrants.

3. **core — local rehearsal and docs.** Extend the workstation resolver to
   resolve both `*.<private_domain>` and `*.<public_domain>` locally, set
   `private.test` and `public.test` in the local context values, update the
   gateway and dns stack READMEs, and move this ADR to Accepted. Depends on (2).

## References

- Current single gateway: `kustomize/gateway/resources/gateway.yaml`,
  `kustomize/gateway/resources/certificate.yaml`.
- Global Envoy LB config to be made per-gateway:
  `kustomize/gateway/base/envoy/loadbalancer/patches/helm-release.yaml`,
  `kustomize/gateway/base/envoy/nodeport/patches/helm-release.yaml`.
- Cilium per-gateway annotations:
  `kustomize/gateway/resources/cilium/patches/gateway.yaml`.
- Domain, issuer, and access resolution:
  `contexts/_template/facets/option-gateway.yaml`,
  `contexts/_template/facets/platform-aws.yaml`,
  `contexts/_template/facets/platform-azure.yaml`.
- Utility route to repoint to the internal gateway:
  `kustomize/observability/grafana/gateway/httproute.yaml`.
- Schema fields: `dns.public_domain`, `dns.private_domain`, `gateway.access`
  in `contexts/_template/schema.yaml`.
</content>
