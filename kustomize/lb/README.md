---
title: LB add-on
description: LoadBalancer Service implementation (AWS LB Controller, MetalLB, or kube-vip) for non-managed clusters.
---

# LB

The cluster's LoadBalancer-Service provider, gated on
`lb_effective.enabled` and selected by `lb_effective.driver`. Three
drivers ship.

`aws-lb-controller` is used on EKS to provision real AWS NLB / ALB
resources outside the cluster. The controller is here, and the AWS-side
LB lives in the customer's VPC.

`metallb` is a speaker DaemonSet that ARP- or BGP-advertises IPs from
a configured pool. Used on docker / incus / metal clusters.

`kube-vip` is a VIP-style provider for Talos clusters that uses ARP
for L2 advertisement.

The add-on is a `flux:` system entry (`lb`) so Flux can install the
controller before the resources that depend on it being live
(advertisement pools, cloud-provider patches). `install` ships the
controller Helm release for whichever driver is active
(aws-lb-controller, metallb, or kube-vip). `resources` ships the
advertisement / address-pool config that configures it (compiled
name: `lb-install` / `lb-resources`), and implicitly depends on
`install`. All three drivers ship a non-empty `install`, so `resources`
can always assume the controller ran first — no per-driver dependency
gymnastics.

The namespace runs at PSA `privileged` because MetalLB's speaker
needs host networking, and aws-lb-controller shares the namespace
even though it doesn't.

## Recipes

Exactly one driver is wired per cluster, selected by
`lb_effective.driver`. The gateway add-on's data-plane Service gets
its external IP from whichever driver is on.

### AWS (EKS)

```mermaid
flowchart LR
  client((Client))

  subgraph systemlb[system-lb]
    ctrl[aws-lb-controller]
  end

  svc[Service type=LoadBalancer]
  awslb[(AWS NLB / ALB<br/>in customer VPC)]
  pods[Backend pods<br/>e.g. gateway data-plane]

  client ==> awslb ==> svc ==> pods
  svc -. watched by .-> ctrl
  ctrl -. provisions + sets external IP .-> awslb
```

```yaml
flux:
  - name: lb
    dependsOn: [policy-resources]
    install:
      components: [aws-lb-controller]
      substitutions:
        cluster_name: <terraform_output('cluster', 'cluster_name')>
        vpc_id: <terraform_output('network', 'vpc_id')>
        aws_region: us-east-1
```

The controller runs in the cluster and provisions real AWS-side load
balancers in the customer's VPC. There's no `resources` block because
AWS LB Controller handles address management through the cloud API.
`lb_effective.controller_required` is true for this driver, so
gateway-base depends on lb-install.

### MetalLB (docker / incus / metal)

```mermaid
flowchart LR
  client((Client))

  subgraph systemlb[system-lb]
    speaker[metallb controller<br/>+ speaker DaemonSet]
    pool[IPAddressPool + L2Advertisement<br/>from lb-resources]
  end

  net[(Cluster L2 subnet)]
  svc[Service type=LoadBalancer]
  pods[Backend pods]

  pool -. assigns IP to .-> svc
  speaker -. ARP-advertises IP on .-> net
  client ==> net ==> svc ==> pods
```

```yaml
flux:
  - name: lb
    dependsOn: [policy-resources]
    install:
      components: [metallb]
    resources:
      - components: [metallb/arp]
        substitutions:
          loadbalancer_ip_range: 10.5.1.10-10.5.1.30
```

The speaker DaemonSet ARP- or BGP-advertises IPs from the configured
pool on the cluster's L2 subnet. ARP advertisement is the default;
the pool range comes from `network.loadbalancer_ips.{start,end}`.

### Talos (kube-vip)

```mermaid
flowchart LR
  client((Client))

  subgraph systemlb[system-lb]
    kubevip[kube-vip cloud-provider<br/>from lb-install]
  end

  net[(Cluster L2 subnet)]
  svc[Service type=LoadBalancer<br/>VIP]
  pods[Backend pods]

  kubevip -. assigns VIP to .-> svc
  kubevip -. ARP-advertises VIP on .-> net
  client ==> net ==> svc ==> pods
```

```yaml
flux:
  - name: lb
    dependsOn: [policy-resources]
    install:
      components: [kube-vip, kube-vip/arp]
      substitutions:
        loadbalancer_ip_range: 10.5.1.10-10.5.1.30
```

Unlike AWS and MetalLB, kube-vip's advertisement mode (`kube-vip/arp`)
is a patch on its own HelmRelease rather than a separate CR, so it
ships alongside the HelmRelease in `install` instead of `resources` —
`resources` is empty for this driver. Advertises a VIP over ARP.

<!-- BEGIN_KUSTOMIZE_DOCS -->

## Substitutions

| Name | Required when | Effect |
|---|---|---|
| `cluster_name` | `aws-lb-controller` is enabled | AWS-side cluster name (LBC tag). Sourced from `terraform_output('cluster', 'cluster_name')`. No fallback — LBC tags every AWS resource it owns with this and filters reconciliation by it, so a generic default would let a second cluster in the same account race the tags. |
| `vpc_id` | `aws-lb-controller` is enabled | VPC ID the LBC operates against. Sourced from `terraform_output('network', 'vpc_id')`. |
| `aws_region` | `aws-lb-controller` is enabled | AWS region for LBC API calls. Sourced from top-level `aws.region`. |
| `loadbalancer_ip_range` | `metallb/*` or `kube-vip` component is enabled | IP range the driver advertises (CIDR-style `start-end`). Read by MetalLB's `IPAddressPool` (in `resources`) and by kube-vip's cloud-provider HelmRelease directly (in `install`). Sourced from `network.loadbalancer_ips.start + '-' + network.loadbalancer_ips.end`. |

## Components — `lb-install`

| Component | Enable when | Effect |
|---|---|---|
| `aws-lb-controller` | platform is AWS | Helm release of the AWS Load Balancer Controller in `system-lb`. Watches `Service type=LoadBalancer` (NLB) and `Ingress` (ALB) resources and provisions AWS-side LBs against the cluster's VPC. Talks to AWS via the IAM role + Pod Identity the cluster Terraform module provisioned. The chart's `crds/` directory is install-only (Helm never upgrades it); the CRDs are vendored under `kustomize/crds/` and applied via the facet `crds:` section so they stay current. |
| `metallb` | `lb_effective.driver == 'metallb'` | Helm release of MetalLB in `system-lb`. Installs the controller and speaker DaemonSet. The address pool and advertisement mode come from `lb-resources` (`metallb/arp` or `metallb/layer2`). |
| `kube-vip` | `lb_effective.driver == 'kube-vip'` (Talos clusters) | Helm release of the kube-vip cloud-provider in `system-lb`. Provides VIP-based LoadBalancer Services for Talos clusters where MetalLB is not used; pairs with `kube-vip/arp` for L2 advertisement. |
| `kube-vip/arp` | kube-vip driver AND `network.loadbalancer_mode == 'arp'` (default) | Patches the kube-vip cloud-provider HelmRelease to enable ARP-based VIP advertisement (Layer 2). |

## Components — `lb-resources`

| Component | Enable when | Effect |
|---|---|---|
| `metallb/arp` | metallb driver AND `network.loadbalancer_mode == 'arp'` (default) | MetalLB `IPAddressPool` (range = `${loadbalancer_ip_range}`) plus an `L2Advertisement` selecting it. Use this for flat L2 networks where speakers can ARP-respond on the cluster subnet. |
| `metallb/layer2` | metallb driver AND `network.loadbalancer_mode == 'layer2'` | MetalLB layer2 advertisement variant. (See `MOVED.md` in this component's directory — kept for compatibility while the canonical entry is consolidating.) |

## Dependencies

| Add-on | Required when | Reason |
|---|---|---|
| `policy-resources` | `policies.enabled: true` | lb-install depends on Kyverno's baseline policies being active before LB controller pods (which run privileged in `system-lb`) are admitted. |

<!-- END_KUSTOMIZE_DOCS -->

## See also

- [contexts/_template/facets/platform-aws.yaml](../../contexts/_template/facets/platform-aws.yaml) for aws-lb-controller wiring.
- [contexts/_template/facets/platform-docker.yaml](../../contexts/_template/facets/platform-docker.yaml) for MetalLB wiring on docker hosts.
- [contexts/_template/facets/platform-incus.yaml](../../contexts/_template/facets/platform-incus.yaml) for MetalLB wiring on incus hosts.
- Related add-ons: [gateway](../gateway/) (data-plane Service consumes lb), [cni](../cni/) (Cilium's L2 announcer is an alternative to lb on Talos, see `cilium/l2`), [policy](../policy/).
