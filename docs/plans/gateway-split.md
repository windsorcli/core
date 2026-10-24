# Gateway split plan

Replace the single `external` Gateway and the `gateway.access` flip with two
optional Gateways, provisioned from the domains the user sets. Tracked in
#3014. #3013 (Keycloak admin paths) and #2994 (network policy baseline)
depend on it.

## Values

```yaml
dns:
  public_domain: example.com        # provisions the external gateway
  private_domain: example.internal  # provisions the internal gateway
gateway:
  enabled: true                     # master switch
  driver: envoy                     # envoy or cilium
```

A gateway exists when its domain is set. Workstation and dev mode default
`dns.private_domain` to `test`. Nothing else is defaulted, so public exposure
is always opt-in. `gateway.access` is removed.

| Layer | Public side | Private side |
|---|---|---|
| Domain, DNS zone, certificate issuer | public | private |
| Gateway, load balancer, route binding | external | internal |

## Rules

| Topic | Rule |
|---|---|
| Names | Gateways are `external` and `internal`. Routes pick one in `parentRefs`. |
| Utilities | Grafana, Kibana, the Flux UI and webhook, CoreDNS listeners, and demo routes bind to `internal`. |
| Applications | Routes name the gateway they need, or both. Core ships no default. |
| Keycloak | Login binds to external when it exists, otherwise internal. The admin console binds to internal only. |
| No private domain | No internal gateway. Utilities are reachable by `kubectl port-forward`. |
| Certificates | External uses the public issuer (`public-acme` or `public-selfsigned`). Internal uses `private`. |
| Same domain for both | Not supported. The domains MUST differ. |
| Hetzner | Public only. No internal gateway, and `dns.private_domain` is rejected. |

## Local addressing

Pool-based load balancers (MetalLB, kube-vip, Cilium LBIPAM) give the internal
gateway `network.loadbalancer_ips.start` and the external gateway the next
address when both exist. A single gateway always takes `start`, so existing
local URLs and the CoreDNS shared address keep working. No new schema key.

NodePort clusters (docker-desktop, Hyper-V, Talos VMs on nodeport) give the
internal gateway the current ports (30080/30443, DNS 30053, webhook 30292) and
the external gateway 30081/30444. On docker-desktop the host ports are
8443/8080 for internal and 8444/8081 for external. DNS and webhook ports stay
internal only.

## Cloud load balancers

| Platform | Internal gateway | External gateway |
|---|---|---|
| AWS | NLB scheme `internal` | NLB scheme `internet-facing` |
| Azure | ILB annotation | Default public LB |
| GCP | Internal load balancer annotation | Default public LB |
| Hetzner | Not provisioned | Cloud LB with public IPs |

## Slices

Each slice is one PR and leaves every platform composing and passing
`windsor test`.

1. Core split on the Envoy driver. Parameterize `kustomize/gateway` by
   `${gateway_name}`, move the `EnvoyProxy` and its load balancer and nodeport
   variants into the resources tier, provision gateways per domain, repoint all
   in-repo routes, and remove `gateway.access`. Includes the local addressing
   and port rules above, and mechanical per-gateway annotations for the cloud
   platforms.
2. Cloud platforms. Verify AWS, Azure and GCP scheme annotations, issuers and
   zones per gateway. Hetzner provisions the external gateway only.
3. Cilium driver. Per-gateway LBIPAM annotations and sharing keys.
4. DNS. A private-zone external-dns instance, CoreDNS serving both domains
   locally, and the workstation resolver for a second local domain.
5. Keycloak two-route design, guides, and schema docs.

## Open questions

- Public-only clusters stop publishing dashboards until a private domain is
  set. A validation message SHOULD say so.
- Docker-desktop external ports (8444/8081) need `compute/docker` host port
  entries when a public domain is set.
