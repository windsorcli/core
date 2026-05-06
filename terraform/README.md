---
title: Terraform layer
description: Index of the modules that ship with the Windsor Core blueprint — state backend, cloud network, cluster control plane, workstation runtime, and bootstrap of Flux / CNI.
---

# Terraform

The Terraform layer of the Windsor Core blueprint. Each subdirectory
under here is a **category** (`backend`, `network`, `cluster`, ...);
inside each category, sibling modules implement the same role on
different platforms (e.g. `network/aws-vpc` and `network/azure-vnet`).
At apply time, exactly one sibling per category is wired in by the
active facet.

Modules are not applied directly. Facets in
[contexts/_template/facets/](../contexts/_template/facets/) emit
`terraform:` entries that reference these directories (`path:`) and
pass per-context inputs from `values.yaml`. The Windsor harness
materializes the entries into a per-context tree under
`.windsor/contexts/<context>/terraform/` and runs them in
dependency order.

See [STYLE.md](STYLE.md) for the code style each module follows
(naming, submodule policy, sensitive values).

## Categories

### Foundation (run first, per-platform)

| Category | Owns | Wired by |
|---|---|---|
| [backend](backend/) | Cloud-native Terraform state backend — S3 + KMS on AWS, storage account + container on Azure. Generates `backend.tfvars` for downstream modules. | `platform-aws`, `platform-azure` |
| [network](network/) | Cloud network foundation — VPC + subnets + NAT (AWS), Resource Group + VNet + subnets + NAT (Azure). Optional VPC- / VNet-attached private DNS zone. | `platform-aws`, `platform-azure` |

### Cluster

| Category | Owns | Wired by |
|---|---|---|
| [cluster](cluster/) | Kubernetes control plane — managed (EKS / AKS) or self-managed (Talos). IAM / Workload Identity / Pod Identity for cluster-scoped controllers. Writes a kubeconfig at `<context_path>/.kube/config`. | `platform-aws`, `platform-azure`, `option-workstation`, `platform-metal` |

### Workstation runtime (Talos only)

| Category | Owns | Wired by |
|---|---|---|
| [workstation](workstation/) | Local network plus supporting services — CoreDNS, git-livereload, registry mirrors. Carves a `/24` of LAN with a predictable IP layout consumed by `compute`. | `option-workstation` |
| [compute](compute/) | Talos node provisioning — containers (Docker) or VMs (Incus). Outputs `controlplanes` / `workers` / `instances` for `cluster/talos` to apply machine config and bootstrap etcd. | `option-workstation` |

### Bootstrap and add-ons (post-cluster)

| Category | Owns | Wired by |
|---|---|---|
| [cni/cilium](cni/cilium/) | Cilium install on Talos — Helm release that the Flux Cilium release later adopts. Singleton; no category index. | `option-cni` |
| [gitops/flux](gitops/flux/) | Flux controllers Helm release plus the git-auth and webhook-token Secrets. The cluster's root `GitRepository` and `Kustomization` are created by the Windsor CLI after the Terraform apply finishes — not by this module. Singleton; no category index. | `platform-base` |
| [dns/zone](dns/zone/) | Public DNS zone for ACME and external-dns — Route53 (AWS) or Azure DNS. Gated on `dns.public_domain` in `values.yaml`. | `platform-aws`, `platform-azure` (when `dns.public_domain` is set) |

## How facets compose

A given category name (e.g. `cluster`, `network`) typically appears
in exactly one platform facet's `terraform:` list, with the path
selecting the per-cloud or per-runtime variant. The same name can
also appear in a path-less follow-up entry that adds a `dependsOn`
edge — for example, [platform-aws.yaml](../contexts/_template/facets/platform-aws.yaml)
emits a second `cluster` entry without a `path` so that, when ACME is
on, the cluster waits for `dns-zone` before applying.

The Windsor harness merges these entries additively: `dependsOn`
lists are unioned, `path` and `inputs` must agree. This is how
optional concerns like ACME, Cilium, and DNS-zone delegation get
woven into the apply graph without duplicating the module wiring.

## Lifecycle order

Per-platform apply order (the dependency edges declared by the
shipped facets):

- **AWS** — `backend` → `network` → `cluster` (+ optional `dns-zone`) → `cluster-additions` → optional `cni` → `gitops`
- **Azure** — `backend` → `network` → `cluster` (+ optional `dns-zone`) → `gitops`
- **Workstation (Talos)** — `workstation` → `compute` → `cluster` → optional `cni` → `gitops`

Teardown reverses this. Modules with `destroy: false` (e.g.
`gitops`, `cluster-additions`) are skipped on teardown — the cluster
delete takes them.

## See also

- [STYLE.md](STYLE.md) — code style and naming conventions for modules.
- [contexts/_template/facets/](../contexts/_template/facets/) — the facets that wire these modules into a blueprint.
- [contexts/_template/schema.yaml](../contexts/_template/schema.yaml) — user-facing `values.yaml` schema.
- [kustomize/](../kustomize/) — the Kustomize layer that runs after `gitops` adopts the cluster.
- Blueprint schema and facet syntax — https://www.windsorcli.dev/docs/blueprints/
