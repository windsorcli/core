---
title: compute
description: Provisions Talos nodes (containers or VMs) on a workstation runtime, ahead of cluster/talos bootstrapping the cluster.
---

# compute

Node provisioning for Talos clusters running on a workstation. Two
sibling modules implement the same role on different runtimes; the
one in play is selected by the workstation runtime, not the cloud
platform.

| Module | Runtime | Nodes |
|---|---|---|
| [`docker`](docker/) | Plain Docker on Linux, Colima, or Docker Desktop | One container per controlplane / worker |
| [`incus`](incus/) | Incus (LXD-derived hypervisor) | One VM per controlplane / worker |

Both expose a parallel output shape so [`cluster/talos`](../cluster/talos/)
can consume them generically:

- `controlplanes` — list of `{hostname, endpoint, node}` for each controlplane.
- `workers` — same shape for workers.
- `instances` — flat list of all nodes with `{name, hostname, ipv4, ipv6, status, type, image, role}`.

These outputs are the contract `cluster/talos` reads to apply
machine config and bootstrap etcd.

The category is only relevant on workstation runtimes (Docker /
Incus). Managed-cluster contexts (`platform: aws` / `platform:
azure`) don't run a `compute` step — EKS and AKS provision their own
node groups inline. Bare-metal Talos uses operator-managed hardware.

## Wiring

Wired by [option-workstation.yaml](../../contexts/_template/facets/option-workstation.yaml)
when the workstation runtime is in play and `cluster.enabled: true`.
Both variants follow the same shape:

```yaml
terraform:
  - name: compute
    path: compute/docker        # or compute/incus
    dependsOn:
      - workstation
    inputs:
      cluster_nodes: <cluster.controlplanes / cluster.workers from values.yaml>
      runtime: <workstation.runtime>
      # network_name, network_cidr, start_ip, compose_project come from the
      # workstation module's outputs via deferred terraform_output(...)
```

How those flow from `values.yaml`:

- `cluster_nodes.controlplanes.*` / `cluster_nodes.workers.*` — `cluster.controlplanes.{count,image,cpu,memory,...}` and `cluster.workers.{...}` from `values.yaml`.
- `runtime` — `workstation.runtime` (the Docker variant treats `linux` / `colima` / `docker` as aliases; `docker-desktop` switches to localhost networking + host port mappings).
- Network attachment — pulled from [`workstation/docker`](../workstation/docker/) / [`workstation/incus`](../workstation/incus/) outputs. Set the values there, not here.

The `workstation` Terraform dep ensures the network and supporting
state exist before nodes attach.

## Teardown

Both modules persist node-state volumes (Docker named volumes on the
docker variant; Incus VM disks on the incus variant). `windsor
destroy` removes them automatically; manual node teardown must
remove the volumes too — leftover volumes carry the old Talos CA
and a fresh cluster bootstrap will fail TLS handshake against them.
See the `talos_machine_secrets` recreation hazard documented in
[`cluster/talos`](../cluster/talos/).

## See also

- [compute/docker](docker/) — Talos containers on Docker.
- [compute/incus](incus/) — Talos VMs on Incus.
- [`workstation/`](../workstation/) — provisions the network these modules attach to.
- [`cluster/talos`](../cluster/talos/) — consumes the outputs to bootstrap the cluster.
- [option-workstation.yaml](../../contexts/_template/facets/option-workstation.yaml) — facet wiring.
