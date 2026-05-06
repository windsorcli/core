---
title: cluster
description: Picks the Kubernetes control plane variant — managed (EKS / AKS) or self-managed (Talos) — for the active platform.
---

# cluster

Provisions the Kubernetes control plane the rest of the blueprint
runs on top of. Three sibling modules implement the same role for
different platforms; exactly one is wired in per `windsor apply`,
selected by the active facet.

| Module | Platform | Control plane |
|---|---|---|
| [`aws-eks`](aws-eks/) (+ [`additions`](aws-eks/additions/)) | `platform: aws` | Amazon EKS — managed by AWS, IAM via Pod Identity |
| [`azure-aks`](azure-aks/) | `platform: azure` | Azure AKS — managed by Microsoft, IAM via Workload Identity |
| [`talos`](talos/) (+ [`extensions`](talos/extensions/)) | `platform: docker` / `incus` / `metal` | Self-managed Talos, bootstrapped from operator-controlled nodes |

All three emit the same downstream-facing contract:

- A kubeconfig at `<context_path>/.kube/config` (mode 0600), used by `windsor exec --`, `kubectl`, and Flux.
- Outputs that downstream Terraform consumes — most often `cluster_endpoint`, `cluster_name`, IAM/identity ARNs/IDs for cluster-scoped controllers (cert-manager, external-dns, AWS LB Controller).

## Picking a variant

The platform facet picks for you. In `values.yaml`:

- `platform: aws` → [`cluster/aws-eks`](aws-eks/) is wired by [platform-aws.yaml](../../contexts/_template/facets/platform-aws.yaml). [`cluster/aws-eks/additions`](aws-eks/additions/) runs after, providing the Kubernetes-side glue (system-dns namespace, external-dns ConfigMap).
- `platform: azure` → [`cluster/azure-aks`](azure-aks/) is wired by [platform-azure.yaml](../../contexts/_template/facets/platform-azure.yaml). cert-manager + external-dns Workload Identity are inline on the cluster module.
- `platform: docker` / `incus` / `metal` → [`cluster/talos`](talos/) is wired by [option-workstation.yaml](../../contexts/_template/facets/option-workstation.yaml) (workstation runtimes) or the metal facet. Compute (containers/VMs/bare metal) is provisioned separately by [`compute/docker`](../compute/docker/), [`compute/incus`](../compute/incus/), or operator-managed hardware before this module bootstraps the cluster.

`topology` (`single-node` / `multi-node` / `ha`) shapes node-group / pool sizing for managed variants and the controlplane / worker count for Talos. The relevant module's `pools` (EKS / AKS) or `cluster_nodes` (Talos) shape carries the actual sizing.

## Sizing and pools

EKS and AKS share the same portable pool shape (`cluster.pools` in `values.yaml`):

```yaml
cluster:
  pools:
    workers:
      class: general    # one of system | general | compute | memory | storage | gpu | arm64
      count: 3
      lifecycle: on-demand   # or "spot"
```

The two variants apply it slightly differently:

- **EKS** — `cluster.pools` replaces the cluster's node groups. When unset, the module falls back to its `var.node_groups` default (a single `t3.xlarge` on-demand group).
- **AKS** — `cluster.pools` is additive. The cluster's inline default (`system`) pool is always present; `cluster.pools` adds user pools alongside it.

Each module maps `class` to a per-cloud VM/instance-type list via its
`class_instance_types` variable. EKS accepts a multi-type list per
node group (rides out single-instance-type capacity shortages); AKS
accepts only one VM SKU per pool, so only the first entry is
consumed. See each leaf for the per-cloud defaults.

Talos doesn't share this shape — `cluster_nodes` on the compute
modules carries Talos-specific sizing (image, CPU, memory,
volumes, hostports). `topology` is what generally drives counts.

## Add-ons that depend on this category

- IAM / Workload Identity / Pod Identity — created here per controller (cert-manager, external-dns, AWS LB Controller) so the in-cluster Helm releases under [`kustomize/`](../../kustomize/) can consume the resulting role/identity ARNs by ServiceAccount annotation.
- [`gitops/flux`](../gitops/flux/) — depends on whichever variant ran. Same module both ways.
- [`cni/cilium`](../cni/cilium/) — optional; bootstraps Cilium on Talos clusters.

## See also

- [cluster/aws-eks](aws-eks/) — managed control plane on AWS.
- [cluster/azure-aks](azure-aks/) — managed control plane on Azure.
- [cluster/talos](talos/) — self-managed Talos on Docker / Incus / metal.
- [`network/`](../network/) — VPC / VNet that managed clusters attach to.
- [`compute/`](../compute/) — node provisioning for Talos.
