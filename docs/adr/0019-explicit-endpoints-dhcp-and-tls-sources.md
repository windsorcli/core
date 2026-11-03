---
title: "ADR-0019: Explicit gateway exposure, DHCP control planes, and TLS sources for on-prem clusters"
description: Replace the network.loadbalancer_ips range with an explicit service_type per gateway, each type with exactly one setting of its own, let cluster.vip make cluster.endpoint a Talos-owned VIP, require cluster.endpoint when several control planes take DHCP leases, and define the supported ways a site supplies TLS trust.
---

# ADR-0019: Explicit gateway exposure, DHCP control planes, and TLS sources for on-prem clusters

## Status

Proposed (2026-10-19). Builds on [ADR-0001](0001-internal-external-gateways-and-dns.md),
which split the gateway into `external` and `internal`. Scope is the platforms
where Core runs its own load balancer: `metal`, `vsphere`, `hyperv`,
`incus`, and `proxmox`. Cloud platforms keep their managed load balancers, and
workstation contexts keep generated values.

## Context

### Endpoints are derived from a range

An operator on a plant network knows the addresses they want before they write
`values.yaml`: the API at `10.20.0.5`, the dashboards at `10.20.0.10`, the
public site behind the firewall at `10.30.0.20`. Core asks instead for a pool,
`network.loadbalancer_ips.start` and `.end`, and derives every endpoint from its
first address.

| Consumer | Address today | Source |
|---|---|---|
| `internal` gateway | pool start | `option-gateway.yaml` `gateway_effective.internal_ip` |
| `external` gateway | pool start, or start + 1 when both domains are set | last-octet arithmetic in `option-gateway.yaml` |
| CoreDNS LoadBalancer (Cilium) | pool start, shared with `internal` through `lbipam.cilium.io/sharing-key` | `addon-private-dns.yaml` |
| Workstation DNS forward target and webhook host | pool start | `option-workstation.yaml` |
| Default pool | `cidrhost(cidr_block, 266)` to `cidrhost(cidr_block, 356)` | `platform-base.yaml` |

This model has four problems:

- The operator cannot tell from `values.yaml` which address a gateway will get.
  They have to know the start/start+1 rule.
- The arithmetic leaves the external gateway unassigned when the start ends in
  `.255`, and the schema description has to warn about it.
- The public and private endpoints usually live on different networks. One
  contiguous range cannot express "internal on the plant VLAN, external in the
  DMZ".
- The range doubles as the pool for application LoadBalancer Services. A
  plant network team allocates addresses one at a time, so a 90-address default
  pool is rarely free.

### Exposure method is global

`gateway.service_type` applies to both gateways. A common on-prem layout is a
fixed LoadBalancer IP for the public endpoint and NodePort for the internal
one, where an existing corporate load balancer already fronts the nodes. Core
cannot express that today.

### DHCP leaves the control plane without a stable address

`network.dhcp` is a boolean on Hyper-V, vSphere, and Proxmox. When true, every
node takes a lease, and `cluster.endpoint` falls back to the first control
plane's leased address (`cluster_endpoint_fallback` in `platform-proxmox.yaml`,
or empty until compute reports one on Hyper-V and vSphere). Nothing keeps the
API reachable when that node is down or its lease changes. Cilium needs a fixed
`k8sServiceHost`, so `platform-hyperv.yaml` rejects DHCP with Cilium unless
`cluster.endpoint` is set by hand.

### TLS trust has one on-prem answer

The `internal` gateway takes its certificate from the `private` issuer, backed
by either a generated CA or a CA supplied through `pki.private_ca.cert` and
`.key`. The intended workflow is to give the site the generated root so their
IT can add it to the corporate trust store, usually through Group Policy.

Industrial sites vary widely in how they handle certificates:

- Most already run a corporate CA, usually Microsoft AD CS, whose root every
  managed workstation already trusts. Adding a second root means a change
  request to the team that owns Group Policy, and unmanaged devices such as
  HMIs, tablets, and vendor laptops never get it.
- Some PKI teams sign subordinate CAs for platform teams, often only with name
  constraints. Many refuse outright.
- Many issue only leaf certificates, through a ticket or AD CS web enrollment,
  with one- or two-year validity. They expect to hand over a certificate file
  and key, and they have no automation for renewal.
- A smaller set runs an ACME-capable CA (Smallstep, EJBCA, Venafi, or the PKI
  engine in Vault or OpenBao).

`pki.private_ca.cert` and `.key` already cover a subordinate CA, but only if the
operator hands over the private key. Nothing supports a supplied leaf
certificate or an internal ACME server. The same `private` issuer also signs
every workload certificate, so the gateway's trust cannot change without
changing theirs.

## Decision

### 1. Each gateway declares its exposure

Each gateway states a `service_type`, and each type has exactly one setting of
its own.

```yaml
gateway:
  external:
    service_type: LoadBalancer
    ip: 10.30.0.20
  internal:
    service_type: NodePort
    node_port: 30443
```

| `service_type` | Required | Optional | Not allowed |
|---|---|---|---|
| `LoadBalancer` on `metal`, `vsphere`, `hyperv`, `incus`, `proxmox` | `ip` | none | `node_port` |
| `LoadBalancer` on cloud platforms | none | none | `ip`, `node_port` |
| `NodePort` | none | `node_port` (default `30443` for `internal`, `30444` for `external`) | `ip` |

A single-node site puts both gateways on NodePort and points its own DNS
records at the node IP:

```yaml
gateway:
  external:
    service_type: NodePort
  internal:
    service_type: NodePort
```

- A missing or disallowed setting MUST fail composition with a `requires`
  message. Core MUST NOT fall back from one `service_type` to another.
- `node_port` sets the HTTPS port. The HTTP port is fixed per gateway, `30080`
  for `internal` and `30081` for `external`, and is not configurable.
- `service_type` defaults to `NodePort` on docker-desktop and `LoadBalancer`
  everywhere else. On the on-prem platforms the default still requires `ip`, so
  Core never picks a gateway address.
- Workstation contexts are the one exception. Windsor creates that network, so
  it keeps setting `service_type` and `ip` from `network.cidr_block`.
- The two gateways MUST NOT share an `ip` or a `node_port`.
- `gateway.service_type` moves under each gateway and is deprecated. It still
  sets both gateways when they leave `service_type` unset.

### 2. The CNI decides the Service load balancer

On `metal`, `vsphere`, `hyperv`, `incus`, and `proxmox`, the in-cluster LB for
LoadBalancer Services is on by default, in L2 (ARP) mode. It serves Services
only. The control-plane VIP comes from Talos (§4).

| CNI | Default `network.loadbalancer_driver` | Alternatives |
|---|---|---|
| `cilium` | `cilium` (LB IPAM and L2 announcements) | `none` |
| any other | `kube-vip` | `metallb`, `none` |

`network.loadbalancer_ips` is an optional range of addresses for downstream
LoadBalancer Services that do not pin an IP. Core never assigns a gateway IP
from it.

| Driver | Gateway IPs | `network.loadbalancer_ips` |
|---|---|---|
| `cilium` | A `/32` `CiliumLoadBalancerIPPool` block per gateway IP, pinned through `lbipam.cilium.io/ips` | Optional. When set, appended as a block. |
| `kube-vip` | Pinned through `kube-vip.io/loadbalancerIPs`; no pool needed | Optional. When set, Core installs `kube-vip-cloud-provider` with the range as `range-global`. When unset, downstream Services MUST pin their own IP. |
| `metallb` | A `/32` `IPAddressPool` entry per gateway IP, pinned through `metallb.io/loadBalancerIPs` | Required, and appended to the `IPAddressPool`. |

- Core MUST pin gateway IPs through the driver's annotation, not the
  deprecated `spec.loadBalancerIP`.
- A Cilium cluster runs no second LB component.

### 3. Private DNS shares the internal gateway IP

Private CoreDNS answers on port 53 at `gateway.internal.ip`. With the Cilium
gateway, a CoreDNS LoadBalancer Service shares the address through the LBIPAM
sharing key. With Envoy Gateway, the internal Gateway carries `TCPRoute` and
`UDPRoute` listeners on port 53, so no second Service needs the address. There
is no separate DNS address.

DNS has to answer on port 53, which a NodePort cannot use, and Windows DNS
conditional forwarders only send to port 53. `dns.private.driver: coredns`
therefore MUST require `gateway.internal.service_type: LoadBalancer`.

With a NodePort gateway, the site owns DNS. Its records point at the node IP on
a single-node cluster, or at the upstream load balancer that forwards to the
node ports. Core publishes no records for a NodePort gateway.

A driver that writes records into the site's existing DNS server through
external-dns's RFC 2136 provider would lift this restriction. It is left to a
follow-up ADR.

### 4. cluster.vip makes cluster.endpoint a Talos VIP

`cluster.endpoint` says where clients reach the API. It cannot say who owns
that address: a control-plane node, Talos, or a load balancer the site already
runs. A boolean `cluster.vip`, default `false`, records that Talos owns it.

```yaml
cluster:
  endpoint: https://10.20.0.5:6443
  vip: true
```

- With `cluster.vip: true`, Core MUST configure the endpoint's host as the
  Talos shared VIP (`machine.network.interfaces[].vip`) on every control
  plane, whatever the CNI or LB driver.
- With `cluster.vip: true`, the endpoint's host MUST be an IPv4 address that
  no control plane uses, and the Talos module MUST fail otherwise.
- With `cluster.vip` unset or `false`, Core configures no VIP. The endpoint is
  a node IP, or an address something else serves.

Core MUST NOT infer a VIP from the endpoint alone. A wrongly claimed address
makes the control planes answer ARP for another system's IP, while a missing
VIP fails bootstrap at the endpoint, where the cause is visible.

Talos announces the VIP itself, with no Kubernetes workload, so it answers
before Flux runs. That matters because the Talos module's bootstrap health
check (`windsor check node-health --k8s-endpoint`) reaches the API through the
kubeconfig, which points at `cluster.endpoint`. Talos elects the VIP holder
through etcd, so the first control plane bootstraps against its own node IP.

- Talos `certSANs` MUST include the VIP.
- Core MUST select the VIP's interface with a `deviceSelector`, since interface
  names differ across platforms.
- The VIP needs a layer-2 segment shared by every control plane. The docs MUST
  say so.
- talosctl keeps the node IPs as its endpoints. The VIP serves the Kubernetes
  API only.

In-cluster components do not use the VIP. Cilium reaches the API through
Talos KubePrism (`k8sServiceHost: localhost`, `k8sServicePort: 7445`), which
load-balances across the control planes on every node. That replaces today's
first-control-plane or CIDR-offset `k8s_service_host`.

### 5. Several DHCP control planes require the VIP

`network.dhcp` stays a boolean. When true, every node takes a lease, and
compute reports the leased addresses that talosctl targets.

- With more than one control plane, `network.dhcp: true` MUST require
  `cluster.endpoint`. It is either a Talos VIP under §4 or an address an
  external load balancer serves. A single control plane MAY keep the fallback
  to its leased address.
- A Talos VIP MUST sit outside the DHCP scope. Core does not know the scope and
  cannot check this, so the docs MUST say so.
- Control planes SHOULD hold DHCP reservations. A control-plane address change
  rewrites the etcd peer address, and the docs MUST say so.

Cilium reaching the API through KubePrism (§4) retires the Hyper-V rejection of
Cilium on DHCP.

### 6. TLS trust follows what the site supplies

`values.yaml` states what the site has: its domains, and optionally a
certificate, a root, an ACME server, or a CA. Core chooses every issuer from
those facts. A user names no issuer, source, or mode in the common case.

Core keeps two trust domains apart:

- The cluster CA signs workload certificates (CoreDNS's etcd, Elasticsearch,
  Filebeat, MinIO) and backs the trust-manager bundle. It is always present.
- Gateway certificates are what browsers, HMIs, and partner systems see. They
  MUST chain to a root those clients already trust, and they are the only part
  that varies by site.

Today `pki.enabled: false` leaves `private` as a `selfSigned` ClusterIssuer.
Each Secret's `ca.crt` is then its own certificate, so etcd rejects CoreDNS's
client certificate (`tls: bad certificate`) and private DNS cannot write
records. A CA-backed issuer passes the same test. The always-present cluster CA
removes that state, and `pki.enabled` is deprecated.

| What the site has | `values.yaml` | Gateway certificate | Cluster CA |
|---|---|---|---|
| Nothing | domains only | public ACME when a public zone is writable, otherwise the cluster CA | generated |
| A certificate from its PKI team | `gateway.<name>.tls.cert` and `.key`, `pki.trusted_cas` | the supplied certificate | generated |
| An ACME-capable CA | `pki.acme.server`, plus `eab` and `ca_bundle` as needed | enterprise ACME | generated |
| A PKI team that signs a subordinate CA | `pki.ca.cert` (the signed CSR) | the cluster CA, chained to the corporate root | the subordinate |
| A CA it hands over | `pki.ca.cert` and `.key` | the cluster CA | the supplied CA |

`pki.private_ca` becomes `pki.ca`.

#### Gateway issuer inference

| Gateway | Condition | Issuer |
|---|---|---|
| any | `gateway.<name>.tls.cert` is set | none; the supplied certificate |
| `external` | `dns.public_domain` is set and its zone is writable | public ACME |
| `external` | `dns.public_domain` is set, the zone is not writable, and `pki.acme.server` is unset | composition fails outside dev |
| `internal` | `pki.acme.server` is set | enterprise ACME |
| `internal` | `dns.private_domain` is a subdomain of a writable `dns.public_domain` | public ACME, with DNS-01 in the public zone (§7) |
| `internal` | otherwise | the cluster CA |

`gateway.<name>.tls.issuer` (`ca`, `acme`, or `selfsigned`) overrides the
inference and is unset by default. It covers a site that keeps internal
hostnames out of Certificate Transparency logs by forcing `ca`, and testing
with `selfsigned`. `pki.public_issuer` is deprecated in favor of
`gateway.external.tls.issuer`.

#### Supplied certificates

A certificate issued by the site's PKI team is a fact about the site, so it is
an input, not a source.

```yaml
gateway:
  internal:
    tls:
      cert: ${secret("vault", "k8s-wildcard", "chain")}
      key: ${secret("vault", "k8s-wildcard", "key")}
pki:
  trusted_cas:
    - ${secret("vault", "corp-root", "cert")}
```

- `cert` holds the leaf and its intermediates. `cert` and `key` MUST be set
  together, and a `requires` rule enforces it.
- Core places the pair in the gateway's Secret through the facet's `secrets:`
  and creates no cert-manager `Certificate` for that listener.
- The certificate MUST cover `<domain>` and `*.<domain>`, because the listener
  serves every route under the domain. Composition cannot parse X.509, so the
  guides MUST say so.
- Renewal is manual: update the secret value and run `windsor apply`.

`pki.trusted_cas` lists extra roots for the trust-manager bundle and the Talos
apiserver `oidc-ca-file`. Without it, pods that reach the internal gateway by
hostname fail TLS, since a supplied chain usually stops at the intermediate.
The same field covers TLS-inspecting proxies and registries signed by a
corporate root.

#### The CSR workflow

The `pki/ca` module always outputs a CSR built from the cluster CA key, with a
name constraint for `dns.private_domain`. Until `pki.ca.cert` is set, the
cluster CA is self-signed. When the PKI team signs the CSR and the operator sets
`pki.ca.cert` to the chain, the cluster CA moves under the corporate root with
the same key, and cert-manager reissues the leaves. One `windsor apply` works
at every stage. The module MUST reject a `pki.ca.cert` whose public key does
not match the generated key.

A site with an offline root uses the same path, so the root key never reaches
the cluster and the cluster CA rotates without re-trusting devices.

#### Expiry alerting

An x509 exporter watches every `kubernetes.io/tls` Secret and the cluster CA,
and alerts fire 30 days and 7 days before expiry. It covers supplied
certificates, which nothing renews, and the 10-year generated root, which
cert-manager's own metrics do not watch.

#### Encryption behind the gateway

The gateway terminates TLS for clients. Behind it:

- Cilium clusters outside workstation contexts enable WireGuard transparent
  encryption by default, encrypting pod traffic between nodes without
  certificates. `cluster.cni.encryption: false` opts out.
- Each facet that owns a backend speaking TLS (Keycloak, OpenBao,
  Elasticsearch, MinIO) attaches a `BackendTLSPolicy` that verifies the backend
  against the cluster CA. This is never user input.
- `TLSRoute` passthrough stays a per-route choice for a backend that terminates
  its own TLS.

Workload identity mTLS (SPIFFE or a service mesh) is out of scope.

The guides MUST present the options in this order of preference for an on-prem
site: public ACME on a subdomain where the cluster can write the public zone,
then internal ACME, then a subordinate CA signed through the CSR workflow, then
a supplied certificate, then the generated CA. The generated CA stays the
default because it needs nothing from the site, and it suits air-gapped sites
with no corporate PKI as well as pilots and labs.

### 7. Private domains SHOULD be subdomains of the public domain

`dns.private_domain` MAY be any domain, but the guides SHOULD recommend a
subdomain such as `int.example.com` under `example.com`. A subdomain keeps the
public and private zones distinct, so the common case needs no split-horizon
DNS.

It also lets Core infer `acme` with Let's Encrypt for the `internal` gateway
when the cluster can write to the public zone (§6). The DNS-01
challenge record for `int.example.com` lives in the public `example.com` zone,
and no client needs a private root. cert-manager MUST then resolve challenge
zones through public resolvers (`dns01RecursiveNameserversOnly`), since the
in-cluster CoreDNS answers authoritatively for the private subdomain.

## Consequences

- An operator reads every endpoint directly from `values.yaml`: one IP or
  NodePort per gateway, plus `cluster.endpoint`. A plant network team
  allocates exactly the addresses Core uses.
- The start/start+1 arithmetic and its `.255` failure go away.
- On-prem LoadBalancer gateways MUST set an `ip`. Existing contexts that relied
  on the derived range fail composition until they do.
- An internal NodePort gateway behind an existing corporate load balancer
  becomes a supported layout, but it cannot carry private CoreDNS.
- A single-node cluster can run both gateways on NodePort with site-assigned
  DNS records. Its URLs carry the node port unless something in front forwards
  443.
- DHCP-only sites can run Core with one reserved address for a Talos VIP, or
  behind a load balancer they already run.
- Sites that want a Talos VIP set `cluster.vip: true` alongside
  `cluster.endpoint`.
- Sites with a corporate CA get certificates their clients already trust,
  without a Group Policy change, through ACME, a subordinate CA, or a supplied
  certificate.
- Every context runs the `pki/ca` Terraform step, and the cluster CA key lives
  in Terraform state.
- Contexts that set `pki.enabled: false` outside dev move from `selfSigned`
  workload certificates to the cluster CA, and their workload certificates are
  reissued.
- Supplied certificates can expire in production. Expiry alerts reduce that
  risk without removing it.
- On-prem contexts with a public domain and no writable zone fail composition
  outside dev, where they get a selfsigned external certificate today.
- WireGuard adds per-packet overhead and lowers the pod MTU on Cilium clusters.
- A site that NATs a public IP to the external gateway gets the gateway's LAN
  IP published to the public zone. This ADR does not address that layout.

## Alternatives considered

Inferring the exposure from the presence of `ip`, with NodePort when it is
unset, removes `service_type`. It turns a forgotten key into a silent change of
exposure.

A top-level `endpoints:` map keyed by name (`api`, `external`, `internal`,
`dns`) would put every address in one place. It splits a gateway's
configuration across two top-level keys and gives DNS an address of its own.

Keeping the range and adding per-endpoint offsets removes the `.255` failure
but still makes the operator compute addresses, and it cannot place endpoints
on different networks.

Inferring the VIP from `cluster.endpoint`, claiming any IPv4 host that is not a
control-plane IP, needs no extra key. It cannot tell a Talos VIP from an
address an existing load balancer serves, and claiming the latter conflicts
with that load balancer on the network. A `cluster.vip` key holding an address
would duplicate the host in `cluster.endpoint`, so `cluster.vip` is a boolean.

A `network.dhcp` enum with a `workers` mode would keep control planes static
while workers lease. With the VIP serving the API and compute reporting leased
addresses to talosctl, static control planes add only a stable etcd peer
address, which a DHCP reservation also gives. The mode would cost a deprecation
path for the boolean and a third addressing branch in every platform facet.

kube-vip in control-plane mode would serve the VIP on any cluster driver. On
Talos it has to run as a static pod in the machine config to answer before
Flux, and Talos keeps no admin kubeconfig on disk for its leader election.

A Cilium L2-announced LoadBalancer Service in front of the API server would
keep Cilium clusters on one component. Cilium runs as a Kubernetes workload, so
the address does not exist during bootstrap and disappears when Cilium fails.

kube-vip as the Service LB on every CNI would give one LB path everywhere. On
Cilium clusters it adds a second component alongside a CNI that already
assigns and announces LoadBalancer addresses.

A cert-manager AD CS issuer (the community `adcs-issuer`) would automate
renewal against Microsoft CAs directly. It needs a service account with
enrollment rights on the corporate CA, which most PKI teams will not grant to a
cluster, and the project is community maintained. The subordinate CA and ACME
paths cover the same sites with less access.

A `gateway.<name>.tls.source` enum (`acme`, `ca`, `selfsigned`, `provided`)
would make the user name an issuer for every gateway and copy ACME settings
into the gateway schema. It also kept one `private` issuer for both the
internal gateway and workload certificates, so switching the gateway to ACME
would have moved the workload certificates too.

Bootstrapping the cluster CA in-cluster through cert-manager would keep its key
out of Terraform state. Talos apiserver OIDC trust and the CSR output both need
the CA before the cluster exists, so Terraform generates it.

## Implementation slices

Each slice is one PR and leaves every platform composing and passing
`windsor test`.

1. Cilium on Talos reaches the API through KubePrism.
2. The Talos VIP inferred from `cluster.endpoint`, with the VIP in `certSANs`.
3. The `requires` rule tying DHCP with several control planes to
   `cluster.endpoint`, and the `network.dhcp` and `cluster.endpoint` schema
   descriptions.
4. The LB driver defaulted from the CNI, on by default, with `metallb`
   requiring `network.loadbalancer_ips` and `kube-vip-cloud-provider` only
   when the range is set.
5. `gateway.<name>.service_type`, `ip`, and `node_port`, gateway IPs pinned
   through driver annotations, and the `requires` rules.
6. `cluster.vip` as the opt-in for the Talos VIP, replacing the inference
   from slice 2.
7. Removing the default `network.loadbalancer_ips` range, requiring `ip` on
   on-prem LoadBalancer gateways, and moving the workstation and private DNS
   consumers off the range.
8. The `LoadBalancer` requirement for private CoreDNS.
9. The cluster CA always present, replacing the `selfSigned` `private`
   issuer, with `pki.private_ca` renamed `pki.ca` and `pki.enabled`
   deprecated.
10. Supplied gateway certificates (`gateway.<name>.tls.cert` and `.key`),
    `pki.trusted_cas`, and the x509 exporter with expiry alerts.
11. Gateway issuer inference, the `gateway.<name>.tls.issuer` override,
    `pki.acme` for internal ACME servers, and deprecating `pki.public_issuer`.
12. The CSR output from `pki/ca` and the cert-only `pki.ca`.
13. WireGuard by default on Cilium, and `BackendTLSPolicy` for backends that
    speak TLS.
14. Guide updates across gateway, DNS, PKI, and LB, including the subdomain
    recommendation and the TLS preference order.

## Open questions

- Whether the bootstrap health check passes against the VIP on the first
  control plane, before etcd has elected a VIP holder, or needs to target the
  node IP until the VIP answers.
- Whether Cilium's Gateway supports `BackendTLSPolicy`. Envoy Gateway does.
  Verify before slice 13.
- Whether the Talos apiserver still validates Keycloak's OIDC issuer when the
  internal gateway serves a Let's Encrypt certificate. Verify before slice 11.
- Whether Terraform can check that a supplied certificate covers the gateway
  domain at apply time.
- Whether older embedded clients on plant floors need an RSA cluster CA
  instead of ECDSA P-256.
- Whether `gateway.external.ip` on cloud should later reserve a static address
  (an AWS Elastic IP or an Azure static public IP) instead of being disallowed.

## References

- [ADR-0001](0001-internal-external-gateways-and-dns.md)
- [Talos virtual IP](https://www.talos.dev/latest/talos-guides/network/vip/)
- [cert-manager CA issuer](https://cert-manager.io/docs/configuration/ca/)
- [cert-manager ACME external account binding](https://cert-manager.io/docs/configuration/acme/#external-account-bindings)
- [Cilium WireGuard transparent encryption](https://docs.cilium.io/en/stable/security/network/encryption-wireguard/)
- [Gateway API BackendTLSPolicy](https://gateway-api.sigs.k8s.io/api-types/backendtlspolicy/)
