# Cilium review

A review of how Core runs Cilium, written from the point of view of someone
who operates Cilium and wants the blueprint to follow its recommended
practice. It covers the CNI add-on, the Terraform bootstrap, the Cilium
gateway driver, and the guides under `docs/guides/cni` and
`docs/guides/gateway`. It also explains how the Cilium gateway relates to
Envoy Gateway, which the docs need to say clearly.

Versions reviewed: Cilium 1.20.2 (chart), Talos 1.14.2 and 1.13.11, Gateway API
1.6.2 (vendored CRDs). Reviewed on 2026-10-02.

## How findings are labelled

| Label | Meaning |
|---|---|
| Verified in source | Read in this repo, the Cilium or Talos source, or their docs at the pinned version. |
| Verified by render | Seen in the output of `helm template` for chart 1.20.2 with this repo's values. |
| Inferred | Follows from verified facts but was not observed running. |
| Not verified | A concern I could not confirm. Treat as a question, not a fact. |

No Cilium cluster was available, so nothing here was observed on a running
Cilium node. Where a finding depends on runtime behavior it says so.

## 1. Cilium Gateway and Envoy Gateway are not alternatives to Envoy

The two drivers read as "Cilium or Envoy", and the existing docs encourage
that ("no separate proxy" for Cilium). Both drivers run Envoy. They differ in
who controls it and where it runs.

Three things share the name:

- Envoy is a proxy, the data plane.
- Gateway API is the Kubernetes API for describing north-south traffic.
- Envoy Gateway is one project that implements Gateway API by creating and
  configuring Envoy proxies.

Cilium also implements Gateway API. It has its own control plane: cilium-operator
translates `Gateway` and `HTTPRoute` resources into `CiliumEnvoyConfig`
(the translation package lives in `operator/pkg/model/translation`). Its data
plane is Envoy, run as a `cilium-envoy` DaemonSet. `gateway.driver` therefore
chooses a Gateway API implementation, meaning a controller and a deployment
model, not whether Envoy is involved.

| | `envoy` (Envoy Gateway) | `cilium` |
|---|---|---|
| Controller | Envoy Gateway operator, `system-gateway` | cilium-operator, `kube-system` |
| Where Envoy runs | A Deployment and Service per Gateway, configured by an `EnvoyProxy` | One `cilium-envoy` pod on every node, shared by all Gateways |
| Reaching the proxy | Load balancer or node port, to a Service, to the Envoy pods | A load balancer address announced by one node, then redirected to that node's Envoy |
| Config beyond Gateway API | `EnvoyProxy`, `HTTPRouteFilter` and other Envoy Gateway resources | Gateway API plus Cilium annotations |
| Addresses | Cloud load balancer, MetalLB or kube-vip, or a node port | Cilium LB IPAM and L2 announcements, or a cloud load balancer |
| Works with | Any CNI | Cilium as the CNI only |
| Upgrades with | Its own Helm release | The Cilium release |
| L7 metrics and alerts in this blueprint | Yes | No (finding F2) |
| Network policy identity | none | `CiliumNetworkPolicy` with `fromEntities: ingress` (finding F8) |

The redirect row follows Cilium's documented model and was not re-verified here.
Everything else in the table was read in the repo, the chart render, or the
Cilium source.

Suggested wording for the gateway guide:

> Envoy Gateway runs dedicated Envoy proxies that the Envoy Gateway controller
> manages. The Cilium driver implements the same Gateway API with Cilium's own
> controller and the Envoy that Cilium runs on every node. Both use Envoy. They
> differ in who manages it and where it runs.

Reasons to choose each, for the same page:

- Cilium: no extra controller to run, load balancer addresses without MetalLB or
  kube-vip, and Services such as CoreDNS can share the gateway address.
- Envoy Gateway: Envoy-specific extensions, a proxy per Gateway that scales on
  its own, independence from the CNI, and the metrics, dashboard and alerts the
  blueprint already ships. It is also the only option when the CNI is not Cilium.

## 2. Findings

| ID | Finding | Severity | Status |
|---|---|---|---|
| F1 | `cilium-envoy` runs on every node with no resource requests or limits | High | Verified by render |
| F2 | No scraping or alerts for gateway L7 traffic, and no Cilium alerts at all | High | Verified in source |
| F3 | Gateway behavior depends on a chart default for `envoy.enabled` | Medium | Verified by render, risk inferred |
| F4 | L2 announcement settings differ from what Cilium documents | High on metal | Verified in source |
| F5 | The API server address is not KubePrism, and the port is set in two places | Medium | Verified in source |
| F6 | Cilium custom resources ship in the same Kustomization as the HelmRelease | Medium | Verified in source |
| F7 | Three mechanisms set the gateway's shared address, one of them a fail-closed webhook | Medium | Verified in source, necessity not tested |
| F8 | Network policy coverage is thin and depends on the gateway driver | Medium | Verified in source |
| F9 | Cilium copies the gateway's TLS Secret into another namespace | Low | Verified by render |
| F10 | EKS opt-in is documented but not verified | Medium | Not verified |
| F11 | Routing mode and encryption are left at defaults and undocumented | Low | Verified by render |
| F12 | A stale comment names Gateway API 1.5.1 | Low | Verified in source |

### F1. `cilium-envoy` has no resource limits

Today. With `gatewayAPI.enabled`, chart 1.20.2 runs Envoy as a standalone
`cilium-envoy` DaemonSet (the rendered config has `external-envoy-proxy: "true"`).
The repo sets no `envoy.*` values, so chart defaults apply: `resources: {}`,
`hostNetwork: true`, `priorityClassName: system-node-critical`, a toleration of
`operator: Exists`, and the `NET_ADMIN` and `SYS_ADMIN` capabilities.

Concern. The pod runs on every node, control-plane nodes included, at
node-critical priority, with no memory bound. Under traffic it can grow without
limit on a small node, and node-critical priority makes it a poor candidate for
eviction. That is most exposed on single-node and schedulable-control-plane
clusters, which the local default creates. The cost is also paid on
every node even when the gateway carries little traffic. I did not measure
memory, so this is inferred.

Recommendation. Set `envoy.resources` explicitly (requests and limits), and
decide whether Envoy should run on control-plane nodes.

Docs. The gateway guide says no separate proxy is installed. That is wrong
(section 5).

### F2. L7 traffic and Cilium itself are not monitored

Today. `cilium/prometheus` enables ServiceMonitors for the agent and the
operator. The chart has a separate switch for `cilium-envoy`,
`envoy.prometheus.serviceMonitor.enabled`, which defaults to false, and the
repo never sets it. Nothing in the repo mentions `cilium-envoy` or its metrics
port. The Envoy driver, by contrast, ships a PodMonitor, a ServiceMonitor, a
dashboard and alert rules (`prometheus/alerts/envoy`, gated on
`gateway.driver == 'envoy'`). `kustomize/telemetry/resources/prometheus/alerts`
has directories for cert-manager, coredns, database, envoy, flux, identity,
node, postgres-exporter and prometheus, and none for Cilium.

Concern. Under the Cilium driver there are no gateway request rates, no 5xx
counts and no gateway alerts, and no rules written for Cilium itself (agent,
operator, IPAM, datapath). Generic Kubernetes alerts from the monitoring stack
may still fire when a Cilium pod fails, which I did not check. For the component
that carries every pod's traffic, that is the largest operational gap.

Recommendation. Enable the Envoy ServiceMonitor. Add Cilium alert rules (agent
or operator down, endpoint failures, BPF map pressure, IPAM exhaustion, policy
drops) and gateway alerts that match the Envoy driver's.

Docs. The guide claims Cilium's metrics and dashboard cover the gateway. They
do not cover L7.

### F3. `envoy.enabled` is a chart default

Today. Gateway API works because `envoy.enabled` defaults to on "for new
installation" (the chart's own wording). The repo never states it. The
Keycloak and Flux webhook policies use `fromEntities: ingress`, which relies on
the gateway traffic coming through that Envoy.

Concern. A chart bump, or `upgradeCompatibility` set below 1.20, could change
the default and silently change where gateway traffic is handled and whether the
policies match. The Terraform bootstrap uses `reuse_values`, which can carry
earlier values forward, so existing clusters may not match new ones. The
consequence is inferred.

Recommendation. Set `envoy.enabled: true` explicitly in `cilium/gateway`.

### F4. L2 announcements

Today. `cilium/l2` enables `l2announcements` and `externalIPs`, and applies a
`CiliumL2AnnouncementPolicy` with `loadBalancerIPs: true` and interfaces
`^eth[0-9]+` and `^ens[0-9]+`. Cilium's L2 announcement docs (1.20.2 source)
say the following, and the repo differs on each point:

| Cilium documents | Repo |
|---|---|
| Size `k8sClientRateLimit.qps` and `.burst` when enabling the feature, because every announced Service uses a lease and adds API load | Neither is set |
| `externalIPs.enabled` is needed only to announce `.spec.externalIPs` | Enabled, though the policy announces only load balancer IPs |
| The `interfaces` field is optional, and the selector "is NOT a security feature" | Restricted to `eth*` and `ens*`, so NICs named `enp*`, `eno*`, bonds or VLANs are never announced |
| One node answers ARP for an address at any time, chosen first come first serve through a lease named `cilium-l2announce-<namespace>-<service>` in `kube-system`, so load can be uneven | Not mentioned |
| The feature is incompatible with `externalTrafficPolicy: Local` | Not mentioned |

Concern. On metal, an address on an unmatched interface is never announced and
nothing says why. The enabled `externalIPs` feature has no use here and widens
what the datapath accepts. The rate limit matters as Services multiply.

Recommendation. Drop `externalIPs.enabled`. Either widen the interface list or
omit `interfaces`. Set a rate limit sized per Cilium's guidance. Document the
leader behavior and the `externalTrafficPolicy: Local` limit.

Docs. The CNI guide lists the two interface patterns without warning, and the
gateway guide describes announcement without the single-node limitation.

### F5. API server address

Today. The Flux HelmRelease sets `k8sServiceHost` from the cluster endpoint and
`k8sServicePort: "6443"` as a literal. Terraform derives the port from the
endpoint instead (and defaults to 6443). Talos's Cilium guide, for
kube-proxy-free installs, uses `k8sServiceHost: localhost` and
`k8sServicePort: 7445`, which is KubePrism.

Concern. With the cluster endpoint, node networking depends on that address
being reachable from every node. With KubePrism it uses a node-local endpoint
that survives control-plane address changes. The port is also defined twice and
can disagree for a non-default endpoint. I did not test an endpoint change.

Recommendation. Use KubePrism on Talos, or at least derive the port once and
share it between Terraform and Flux.

### F6. Custom resources next to the HelmRelease

Today. `kustomize/cni/install/cilium/l2` ships `CiliumLoadBalancerIPPool` and
`CiliumL2AnnouncementPolicy` in the same Kustomization as the HelmRelease. The
add-on README already lists the failure: the HelmRelease reports "no matches for
kind CiliumLoadBalancerIPPool" when Flux reconciles before the chart installs
its CRDs, and the fix is to reconcile again.

Concern. A documented race that needs a manual retry is a design gap. The repo
already solves this elsewhere with install and resources tiers (gateway, pki,
telemetry).

Recommendation. Move the pool and policy into a `cni-resources` tier that
depends on the install tier, with a health check on the HelmRelease.

### F7. Three mechanisms set the gateway address

Today. For the Cilium gateway, the shared address is set through the Gateway's
`spec.infrastructure.annotations`, through a ConfigMap
(`cilium-lbipam-config`) and through a Kyverno `MutatingPolicy`
(`cilium-gateway-lbipam-sharing`). The policy reads that ConfigMap with
`resource.Get`, applies on `CREATE` for Services labelled
`io.cilium/gateway/owning-gateway: external` in `system-gateway`, and has
`failurePolicy: Fail`. Its description says the Cilium controller creates the
Service and then patches annotations, which races with LB IPAM.

Concern. If Kyverno is unavailable, or the ConfigMap is missing, the gateway
Service cannot be created. That makes the gateway depend on an admission
controller at creation time. Whether the policy is still needed on 1.20.2, when
the Gateway's own infrastructure annotations already carry the same values, was
not tested.

Recommendation. Test the gateway with the infrastructure annotations alone on
1.20.2. If it works, delete the policy and the ConfigMap path.

### F8. Network policy

Today. The blueprint ships one standard `NetworkPolicy` (etcd for private DNS)
and three `CiliumNetworkPolicy` objects (Keycloak, the Flux webhook, the Flux
UI). There is no default deny anywhere.

Concern. The Cilium policies use `fromEntities: ingress`, so they exist only
with the Cilium gateway driver. With the Envoy driver, Keycloak and the webhook
accept traffic from anywhere in the cluster. Flannel does not enforce
`NetworkPolicy` at all, so the etcd policy does nothing there. That last point
is a known property of flannel and was not tested here.

Recommendation. Decide on a policy baseline, and make the policies that matter
(Keycloak, the webhook) independent of the gateway driver, for example with
standard `NetworkPolicy` objects that work under any enforcing CNI.

### F9. TLS Secret copied by Cilium

Today. The rendered configuration has `enable-gateway-api-secrets-sync: "true"`
and `gateway-api-secrets-namespace: "cilium-secrets"`, and the chart creates the
`cilium-secrets` namespace. Cilium therefore copies the Gateway's certificate
Secret (`external-web-tls`, a wildcard) into that namespace.

Concern. The private key of the wildcard certificate exists in two namespaces.
It is how Cilium works, but it belongs in the security notes and in any RBAC
review.

### F10. EKS opt-in

Today. The Terraform module describes `ipam.mode: kubernetes` as working for
"Talos and standard EKS", and the CNI guide says EKS can opt in to Cilium.

Concern. Kubernetes IPAM mode relies on node pod CIDRs. I believe EKS does not
assign them by default, and Cilium on EKS normally uses ENI or cluster-pool
IPAM. I did not confirm this, and I did not test the EKS path.

Recommendation. Test it or remove the claim from the module description and the
guide.

### F11. Routing and encryption

Today. The chart's `routingMode` and `tunnelProtocol` are empty, so Cilium's own
defaults apply, and `encryption.enabled` is false. The docs say nothing about
either.

Concern. Pod-to-pod traffic is unencrypted and uses whatever default routing
mode Cilium picks. Those may be fine choices, but a reader cannot tell. I did
not check the effective routing mode on a running agent.

Recommendation. State the defaults in the CNI guide, or set them explicitly.

### F12. Stale comment

`kustomize/cni/install/cilium/gateway/patches/helm-release.yaml` names
`gateway-api-experimental-1.5.1`. The vendored CRDs are 1.6.2. Fix or remove the
comment.

## 3. What is already right

- The agent runs without privileged mode and with the capability set from
  Talos's own Cilium guide, with `SYS_MODULE` omitted.
- The cgroup settings match that guide (`autoMount` off, `hostRoot` at
  `/sys/fs/cgroup`).
- Gateway API CRDs are aligned: Cilium 1.20.2 is built against Gateway API
  1.6.1, and the repo vendors 1.6.2. `enableAlpn` is on, as Talos's guide
  advises for gRPC.
- Hubble certificates rotate through a CronJob, so Hubble does not need
  cert-manager.
- The HelmRelease install strategy retries and never uninstalls on failure,
  which matters because Cilium is the CNI.
- Both Cilium version pins (Terraform and Flux) carry the same Renovate
  annotation, so they move together.

## 4. How the docs need to change

| Doc | Current statement | Finding | Change |
|---|---|---|---|
| `gateway/cilium.md` (lead and description) | No separate proxy is installed | F1, section 1 | Say L7 runs in Cilium's per-node Envoy, with no separate controller or Deployment |
| `gateway/cilium.md` ("What differs from Envoy") | Cilium's metrics and dashboard cover the gateway | F2 | Say there are no gateway L7 metrics or alerts yet |
| `gateway/cilium.md` (Addresses) | Cilium announces the address over L2 | F4 | Add one node at a time, first come first serve, and the `externalTrafficPolicy: Local` limit |
| `gateway/index.md` | Driver table only | Section 1 | Add "How the two drivers relate" with the wording above |
| `cni/cilium.md` (Load balancer addresses) | Announced on `eth*` or `ens*` interfaces | F4 | Warn that other interface names are not announced |
| `cni/cilium.md` (Turn it on) | EKS can opt in | F10 | Mark unverified or remove |
| `cni/cilium.md` (Security) | Capabilities and kube-proxy notes | F8, F9 | Add that Cilium copies the gateway TLS Secret to `cilium-secrets` and that there is no default deny |
| `cni/index.md` (comparison table) | Four rows | F8 | Add a row for NetworkPolicy enforcement (Cilium enforces, flannel does not) |
| `cni/cilium.md` (Under the hood or Configuration) | Routing and encryption unstated | F11 | State the defaults |

One adjacent point that is not about Cilium: the private CoreDNS on port 53 is
reachable through the gateway address and forwards unknown names to 1.1.1.1 and
8.8.8.8, so it behaves as an open resolver for anything that can reach that
address. That belongs in the DNS review.

## 5. Suggested order

1. Docs only, no behavior change: the changes in section 4 that do not depend on
   an implementation fix, plus F12.
2. Small implementation changes: set `envoy.enabled: true` (F3), set
   `envoy.resources` (F1), drop `externalIPs.enabled` and rework the interface
   list and rate limit (F4).
3. Observability: the Envoy ServiceMonitor and Cilium alert rules (F2).
4. Structural: the Flux install and resources split (F6), KubePrism (F5), and the
   Kyverno policy question (F7).
5. Things to test before documenting as fact: EKS (F10), Envoy memory under
   load (F1), L2 leader failover and interface behavior (F4), the effective
   routing mode (F11).

## 6. Open questions

- Should `cilium-envoy` run on control-plane nodes?
- Is the target a default-deny baseline, and should it work under any CNI?
- Is Cilium on EKS a supported path, or only a possible one?
- Does the blueprint want parity of gateway alerts between the two drivers?
