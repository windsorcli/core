---
title: workstation
description: Provisions the local network plus supporting services (DNS, git-livereload, registry mirrors) that workstation Talos clusters attach to.
---

# workstation

Sets up the local network and supporting services a workstation
Talos cluster sits on. Two sibling modules implement the same role
on different runtimes:

| Module | Runtime | Provisioned |
|---|---|---|
| [`docker`](docker/) | Plain Docker on Linux, Colima, or Docker Desktop | Docker network, CoreDNS container, git-livereload, registry mirrors |
| [`incus`](incus/) | Incus (LXD-derived hypervisor) | Incus network, same supporting services as containers |

Both modules carve a `/24` (default) out of the local LAN and lay
out IPs predictably so node hostnames and supporting services are
easy to reason about:

| IP | Role |
|---|---|
| `.1` | network gateway |
| `.2` | CoreDNS |
| `.3` | git-livereload |
| `.4 .. (node_start_offset - 1)` | registry mirrors |
| `.10+` | Talos nodes (provisioned by [`compute/`](../compute/)) |

Outputs (`network_name`, `network_cidr`, `compose_project`,
`next_ip`) are consumed by [`compute/docker`](../compute/docker/) /
[`compute/incus`](../compute/incus/) so the nodes attach to this
network and continue the IP sequence past `node_start_offset`.

This category is only relevant on workstation runtimes. Managed-
cluster contexts (`platform: aws` / `platform: azure`) don't run a
`workstation` step — cloud networking comes from
[`network/aws-vpc`](../network/aws-vpc/) /
[`network/azure-vnet`](../network/azure-vnet/) instead.

## Wiring

Wired by [option-workstation.yaml](../../contexts/_template/facets/option-workstation.yaml)
when the workstation runtime is in play. Both variants take the same
high-level inputs:

```yaml
terraform:
  - name: workstation
    path: workstation/docker        # or workstation/incus
    inputs:
      runtime: <workstation.runtime>
      network_cidr: <network.cidr_block from values.yaml>
      domain_name: <dns.private_domain ?? "test">
```

How those flow from `values.yaml`:

- `runtime` — `workstation.runtime`. Determines whether endpoints are routable (`linux` / `colima` / `docker`) or localhost-only (`docker-desktop`).
- `network_cidr` — `network.cidr_block`. The local-LAN block carved up per the table above.
- `domain_name` — `dns.private_domain`. Drives CoreDNS records for the supporting services. When the input is unset, the module falls back to the active context name.

## See also

- [workstation/docker](docker/) — Docker / Colima / Docker Desktop runtime.
- [workstation/incus](incus/) — Incus runtime.
- [`compute/`](../compute/) — Talos node provisioning attaches to this network.
- [option-workstation.yaml](../../contexts/_template/facets/option-workstation.yaml) — facet wiring.
