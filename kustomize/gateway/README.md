---
title: Gateway add-on
description: Gateway API implementation (Envoy Gateway or Cilium) and the cluster's external Gateway.
---

# Gateway

The cluster's external traffic entrypoint, via the Kubernetes Gateway
API. Two driver options.

Envoy Gateway is the default. It's a dedicated control-plane and
data-plane Envoy stack installed by Helm. Heavier than Cilium's
built-in path, but unlocks advanced L7 features
(`HTTPRouteFilter`, ext_authz, rich response shaping). It's used here
for the catch-all 404, and it's the right pick when you need those
knobs.

Cilium is the other option, which uses Cilium's built-in Gateway API
implementation. A single dataplane handles L3/L4 and L7, and
LoadBalancer Services share IPs via Cilium LBIPAM. There's no
separate Helm release. The `cilium/gateway` component on the `cni`
add-on enables `gatewayAPI` on the existing Cilium operator, and this
add-on only contributes the GatewayClass and the LBIPAM-sharing
patch.

The add-on splits across two Kustomization paths so Flux can install
the Gateway API CRDs and the controller workloads before the
`Gateway` CR that targets them. `gateway-base` ships the Gateway API
CRDs plus the operator Helm release (envoy) or just the GatewayClass
(cilium); LB-mode patches and Prometheus monitor go here.
`gateway-resources` ships the `external` `Gateway` CR (named via the
`system-gateway` namespace) plus per-feature patches (catch-all 404,
DNS listeners, fixed LB address, Flux webhook).

## Recipes

The `external` Gateway listens on HTTPS (and HTTP for redirect) with a
cert issued by one of the pki add-on's ClusterIssuers. external-dns
publishes its hostname, and — for the LoadBalancer modes — the LB
controller assigns its external IP.

### Envoy + LoadBalancer (cloud default)

```mermaid
flowchart LR
  client((Client))

  subgraph systemgateway[system-gateway]
    op[Envoy Gateway operator]
    gw[Gateway external<br/>HTTPS + default-404]
    routes[HTTPRoutes from apps]
    svc[Service type=LoadBalancer]
    envoy[Envoy data-plane]
  end

  cloudlb[(Cloud load balancer)]
  lbctrl[(LB controller)]
  cert[(pki Certificate)]
  dns[(external-dns)]
  app[App workloads]

  client ==> cloudlb ==> svc ==> envoy ==> app
  op -. provisions .-> svc & envoy
  gw -. classOf .-> op
  routes -. attach .-> gw
  cert -. TLS .-> gw
  svc -. requests IP .-> lbctrl -. provisions .-> cloudlb
  dns -. publishes hostname .-> cloudlb
```

Bold path is the request flow; dotted is the control wiring that sets
it up. The operator turns the Gateway + HTTPRoutes into a running Envoy
data-plane behind a LoadBalancer Service; the LB controller provisions
the cloud LB and external-dns publishes its hostname.

```yaml
- name: gateway-base
  path: gateway/base
  dependsOn: [pki-install, lb-base]
  components: [envoy, envoy/loadbalancer, envoy/prometheus]

- name: gateway-resources
  path: gateway/resources
  dependsOn: [gateway-base, dns, lb-base]
  components: [envoy/default-404, lb-address, flux-webhook]
  substitutions:
    gateway_class_name: envoy
    gateway_dns_target: 10.5.1.10
    external_domain: example.com
    loadbalancer_start_ip: 10.5.1.10
```

The default driver: a dedicated Envoy control- and data-plane installed
by Helm, with the data-plane Service exposed through the LB controller.

### Envoy + NodePort (local dev / single-host)

```mermaid
flowchart LR
  client((Client / workstation))

  subgraph systemgateway[system-gateway]
    op[Envoy Gateway operator]
    gw[Gateway external<br/>HTTPS]
    routes[HTTPRoutes from apps]
    svc[Service type=NodePort]
    envoy[Envoy data-plane]
  end

  node[(Node host ports<br/>+ NodePorts: DNS 53, Flux webhook 9292)]
  cert[(pki Certificate)]
  app[App workloads]

  client ==> node ==> svc ==> envoy ==> app
  op -. provisions .-> svc & envoy
  gw -. classOf .-> op
  routes -. attach .-> gw
  cert -. TLS .-> gw
```

```yaml
- name: gateway-base
  path: gateway/base
  dependsOn: [pki-install]
  components:
    - envoy
    - envoy/nodeport
    - envoy/nodeport/dns
    - envoy/nodeport/flux-webhook
    - envoy/prometheus
```

NodePort skips the LB controller and forwards via host ports. The
`/dns` and `/flux-webhook` sub-overlays open the additional NodePort
slots needed for in-cluster DNS and Flux push-mode webhooks.

### Envoy on AWS (NLB)

```mermaid
flowchart LR
  client((Client))

  subgraph systemgateway[system-gateway]
    op[Envoy Gateway operator]
    gw[Gateway external<br/>HTTPS]
    routes[HTTPRoutes from apps]
    svc[Service type=LoadBalancer<br/>+ NLB annotations]
    envoy[Envoy data-plane pods]
  end

  nlb[(AWS NLB<br/>target-type=ip)]
  lbc[(AWS LB Controller)]
  cert[(pki Certificate)]
  app[App workloads]

  client ==> nlb ==> envoy ==> app
  op -. provisions .-> svc & envoy
  gw -. classOf .-> op
  routes -. attach .-> gw
  cert -. TLS .-> gw
  svc -. pod IPs registered by .-> lbc -. provisions .-> nlb
```

```yaml
- name: gateway-base
  path: gateway/base
  components:
    - envoy
    - envoy/loadbalancer
    - envoy/loadbalancer/aws-nlb
    - envoy/prometheus
```

The aws-nlb overlay adds AWS LB Controller annotations so the
data-plane Service provisions an NLB with `target-type=ip`, sending
traffic straight to the Envoy pods with source IP preserved.

### Cilium driver

```mermaid
flowchart LR
  client((Client))

  subgraph systemgateway[system-gateway]
    gc[GatewayClass cilium]
    gw[Gateway external<br/>HTTPS · LBIPAM-shared IP]
    routes[HTTPRoutes from apps]
  end

  subgraph kubesystem[kube-system]
    cil[Cilium agents<br/>L3/L4 + L7 dataplane]
  end

  cert[(pki Certificate)]
  app[App workloads]

  client ==> cil ==> app
  gw -. classOf .-> gc -. controller .-> cil
  gw -. programs .-> cil
  routes -. attach .-> gw
  cil -. LBIPAM assigns VIP .-> gw
  cert -. TLS .-> gw
```

Cilium is already the cluster dataplane (it's the CNI), so it
terminates and routes Gateway traffic directly — no Envoy Service in
the path, one hop shorter than the Envoy recipes.

```yaml
- name: gateway-base
  path: gateway/base
  dependsOn: [pki-install]
  components: [cilium]

- name: gateway-resources
  path: gateway/resources
  dependsOn: [gateway-base]
  components: [cilium]
  substitutions:
    loadbalancer_start_ip: 10.5.1.10
```

No separate Helm release: the base entry installs only the
GatewayClass, the Cilium operator (owned by the `cni` add-on) is the
controller, and the resources entry patches the Gateway with Cilium's
LBIPAM annotations so multiple Gateways can share one IP.

<!-- BEGIN_KUSTOMIZE_DOCS -->

## Substitutions

| Name | Required when | Effect |
|---|---|---|
| `gateway_class_name` | always | Name of the `GatewayClass` the cluster Gateway references. Sourced from `gateway.driver` (`envoy` or `cilium`). |
| `gateway_dns_target` | `dns` is enabled and `gateway-resources/dns` is composed | External hostname/IP that external-dns publishes as the gateway target. Resolves to `network.loadbalancer_ips.start` when `lb_effective.enabled`, empty otherwise. |
| `external_domain` | `gateway-resources` is composed | Cert SAN domain. `dns.private_domain` when `gateway.access: private` (and the private domain is set); otherwise `dns.public_domain` if set, falling back to `dns.private_domain`. |
| `loadbalancer_start_ip` | `lb-address` or `cilium` (resources) is composed | Fixed IP the Gateway advertises. Used in the cilium variant's `lbipam.cilium.io/ips` annotation and in the envoy variant's `spec.addresses` patch. |

## Components — `gateway-base`

| Component | Enable when | Effect |
|---|---|---|
| `envoy` | `gateway.driver == 'envoy'` | Helm release of `envoy-gateway` in `system-gateway`. Installs the Envoy Gateway operator (chart CRD install is skipped) and the self-contained `external` `EnvoyProxy` resource that owns the per-gateway data-plane config (digest-pinned proxy image plus the Service patches layered on by the loadbalancer/nodeport components). The EnvoyGateway config keeps no default proxy patch, so the EnvoyProxy each Gateway references via `parametersRef` is authoritative. The Envoy Gateway and shared Gateway API CRDs are vendored under `kustomize/crds/` and applied ahead of the controller via the facet `crds:` section. |
| `envoy/loadbalancer` | envoy driver AND `lb_effective.mode == 'loadbalancer'` | Patches the `external` `EnvoyProxy` so the data-plane Envoy Service is `type: LoadBalancer`. Cloud-specific annotation patches (aws-nlb / azure-lb-internal) merge on top. |
| `envoy/loadbalancer/aws-nlb` | envoy driver AND platform is AWS AND `lb_effective.mode == 'loadbalancer'` | Adds NLB annotations onto the Envoy data-plane Service so the AWS Load Balancer Controller provisions an NLB with target-type=ip. Traffic reaches Envoy pods directly, source IP preserved. |
| `envoy/loadbalancer/azure-lb-internal` | envoy driver AND platform is Azure AND `gateway.access == 'private'` | Adds Azure ILB annotations so the Envoy data-plane Service provisions an internal load balancer (subnet-bound, no public IP). |
| `envoy/nodeport` | envoy driver AND `lb_effective.mode == 'nodeport'` | Patches the `external` `EnvoyProxy` so the data-plane Service is `type: NodePort`. Used on local clusters where no LoadBalancer provider exists. |
| `envoy/nodeport/dns` | envoy/nodeport AND `addons.private_dns.enabled: true` (default in `dev`) | Opens an additional NodePort for the cluster's private DNS resolver (UDP/TCP 53). Lets a workstation point at the host's IP for `*.<dns.private_domain>` resolution. |
| `envoy/nodeport/flux-webhook` | envoy/nodeport AND `gitops.mode == 'push'` | Opens an additional NodePort for the Flux notification-controller webhook (port 9292). Lets the GitOps push pipeline reach in-cluster receivers. |
| `envoy/prometheus` | envoy driver | Adds the Envoy Gateway operator's PodMonitor + the Envoy data-plane's ServiceMonitor. |
| `base/cilium` | `gateway.driver == 'cilium'` | Installs the Gateway API CRDs and a `GatewayClass` referencing the `cilium` controller. The Cilium HelmRelease itself is owned by the `cni` add-on (see option-cni's `cilium/gateway` component). Operator references this as `components: [cilium]` under `gateway-base`. |

## Components — `gateway-resources`

| Component | Enable when | Effect |
|---|---|---|
| `resources/cilium` | `gateway.driver == 'cilium'` | Patches the `external` Gateway with `lbipam.cilium.io/ips: ${loadbalancer_start_ip}` and the LBIPAM sharing annotations so multiple Gateways can share a single IP. Operator references this as `components: [cilium]` under `gateway-resources`. |
| `envoy/parameters` | envoy driver | Patches the `external` Gateway's `spec.infrastructure.parametersRef` to point at the `external` `EnvoyProxy`, so the data-plane Service is configured per gateway rather than through the controller-global EnvoyGateway default. Cilium gateways don't use the `EnvoyProxy` resource. |
| `envoy/default-404` | envoy driver | Catch-all `HTTPRouteFilter` returning a 404 directResponse for any request that doesn't match a real app's HTTPRoute. Cilium clusters don't ship this (the Envoy-specific CRD isn't available there). |
| `envoy/default-404/external-dns` | envoy driver AND (public OR private gateway-managed DNS zone exists) | Adds the `external-dns.alpha.kubernetes.io/hostname` annotation to the 404 catch-all route so external-dns publishes the gateway hostname for the bare domain (not just per-app HTTPRoutes). |
| `dns` | envoy driver AND `addons.private_dns.enabled: true` (default in `dev`) | Patches the `external` Gateway with `external-dns.alpha.kubernetes.io/target: ${gateway_dns_target}` and adds UDPRoute / TCPRoute listeners on port 53 for in-cluster DNS service exposure. |
| `lb-address` | `lb_effective.enabled: true` | Patches the `external` Gateway's `spec.addresses` to pin a fixed IPAddress (`${loadbalancer_start_ip}`). Skipped when no LB is enabled (NodePort mode picks node IP at apply time). |
| `flux-webhook` | `gitops.mode == 'push'` | Adds an HTTP listener on port 9292 to the `external` Gateway for the Flux notification-controller webhook. Paired with `envoy/nodeport/flux-webhook` on nodeport-mode clusters. |

## Dependencies

| Add-on | Required when | Reason |
|---|---|---|
| `pki-install` | always | gateway-base needs cert-manager CRDs reconciling so the `Certificate` for the external Gateway can be issued before the Gateway is admitted. |
| `lb-base` | `lb_effective.controller_required: true` (e.g., metallb-driven clusters; AWS via aws-lb-controller) | The LB controller must be live so the data-plane Service can get an external IP. |
| `dns` | `dns.enabled: true` | external-dns must be reconciling so the gateway hostname is published when the Gateway comes up. |
| `cni` | `gateway.driver == 'cilium'` (declared by option-gateway as a cross-stack merge into option-cni) | Cilium's Gateway controller needs the Gateway API CRDs from gateway-base before its operator starts watching. |

<!-- END_KUSTOMIZE_DOCS -->

## See also

- [contexts/_template/facets/option-gateway.yaml](../../contexts/_template/facets/option-gateway.yaml) for the canonical wiring.
- [contexts/_template/facets/platform-aws.yaml](../../contexts/_template/facets/platform-aws.yaml) for the NLB merge on the AWS path.
- [contexts/_template/facets/platform-azure.yaml](../../contexts/_template/facets/platform-azure.yaml) for the Azure ILB merge on the private-access path.
- Related add-ons: [pki](../pki/) (gateway certificate), [lb](../lb/) (data-plane Service LB), [dns](../dns/) (external-dns publication), [cni](../cni/) (cilium driver).
