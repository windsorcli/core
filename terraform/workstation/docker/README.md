---
title: workstation/docker
description: Provisions the Docker network and supporting services (CoreDNS, git livereload, registry mirrors) that back a workstation cluster.
---

# workstation/docker

Backs a workstation Talos cluster running on Docker. This module
creates the Docker network the cluster nodes attach to, plus a small
set of supporting service containers — a CoreDNS resolver for the
context's private DNS zone, a git-livereload server for development
hot-reload, and per-registry mirror containers (Distribution proxying
upstream registries) for offline-friendly image pulls. Its outputs
(network name, CIDR, the first IP available for cluster nodes) are
consumed by [`compute/docker`](../../compute/docker/), which then
attaches Talos containers to the same network.

This module is the bottom of the workstation Terraform stack:
`workstation/docker` → [`compute/docker`](../../compute/docker/) →
[`cluster/talos`](../../cluster/talos/) →
[`cni/cilium`](../../cni/cilium/) →
[`gitops/flux`](../../gitops/flux/).

## Wiring

Wired by [option-workstation.yaml](../../../contexts/_template/facets/option-workstation.yaml)
in two variants — one for `docker-desktop` runtime, one for everything
else (`linux`, `colima`). The variants differ in how the host reaches
in-context services: docker-desktop uses NodePort-style port mappings
on the host; linux and colima use routable container IPs.

### Docker (linux / colima)

```yaml
terraform:
  - name: workstation
    path: workstation/docker
    inputs:
      runtime: linux
      domain_name: <dns.private_domain>
      network_name: windsor-<context>
      network_cidr: 10.5.0.0/16
      dns_forward_target: 10.5.1.10        # LB IP
      webhook_host: 10.5.1.10
      webhook_port: 80                      # 9292 if Gateway is disabled
      webhook_enabled: false
      enable_dns: true
      enable_git: true
      registries:
        gcr.io: { remote: https://gcr.io }
        ghcr.io: { remote: https://ghcr.io }
        # ... etc
```

### docker-desktop

```yaml
terraform:
  - name: workstation
    path: workstation/docker
    inputs:
      runtime: docker-desktop
      domain_name: <dns.private_domain>
      network_name: windsor-<context>
      network_cidr: 10.5.0.0/16
      dns_forward_target: 10.5.0.10:30053   # gateway:NodePort
      webhook_host: 10.5.0.10
      webhook_port: 30292                   # NodePort
      primary_node_ip: 10.5.0.10
      # ...
```

How the inputs flow from `values.yaml`:

- `domain_name` — `dns.private_domain`. Stamped into the CoreDNS Corefile and onto the per-service hostnames (`dns.<domain>`, `git.<domain>`, `<registry-host>.<domain>`).
- `network_cidr` — `network.cidr_block`. Drives every IP the module assigns: gateway=`.1`, dns=`.2`, git=`.3`, registries=`.4..(node_start_offset-1)`, cluster nodes=`.10+`.
- `runtime` — `workstation.runtime`. The value `docker` from the schema is normalized to `linux` for this module's input.
- `enable_dns`, `enable_git` — `workstation.services.dns` / `workstation.services.git` (both default to `true`).
- `registries` — `docker.registries` if set, else a built-in set of common upstreams (`gcr.io`, `ghcr.io`, `quay.io`, `reg.kyverno.io`, `registry-1.docker.io`, `registry.k8s.io`). Empty when `workstation.services.registries: false`.
- `webhook_enabled` — `workstation.git.livereload && gitops.mode == 'push'`. The git-livereload container POSTs to a Flux Receiver when files change; only enabled if both git livereload and push-mode GitOps are on.
- `webhook_token` — `gitops.webhook.token` (the same token the [`gitops/flux`](../../gitops/flux/) module installs into the cluster). The git-livereload container uses it to compute the Flux Receiver webhook URL.
- `git_username`, `git_password` — `workstation.git.username` / `workstation.git.password` (default `local`/`local`).

The `dns_forward_target` and `webhook_host` differ by runtime because
docker-desktop has no routable container network — services are reached
via NodePort port mappings on the host.

## Outputs

The outputs are designed to drop directly into
[`compute/docker`](../../compute/docker/):

- `network_name`, `network_cidr` — the Docker network compute attaches to (`create_network: false`).
- `next_ip` — the first IP available for cluster nodes (host index = `node_start_offset`, default `10`). Stable across registry add/remove because registries fill the reserved block `[4, node_start_offset)`.
- `compose_project` — Docker Compose project name (`workstation-windsor-<context>`); `compute/docker` reuses it so cluster containers and workstation services appear in the same compose group.
- `domain_name` — for facet expressions that need the resolved domain.
- `loadbalancer_start_ip`, `webhook_host`, `dns_ip` — derived service IPs.
- `service_ips`, `containers`, `registries` — per-service IP assignments and container names. The `registries` output includes a computed `hostname` per entry (e.g. `gcr.<domain>`) consumed by Talos registry mirror config.

## Security

`git_username` / `git_password` default to `local` / `local` — fine for
local dev, not for anything else. The git-livereload container exposes
HTTP basic auth on this credential pair. The `webhook_token` is the
same token consumed by the [`gitops/flux`](../../gitops/flux/) module
to authenticate webhook deliveries; the workstation development default
(`abcdef123456`) is **not safe outside local dev**.

The CoreDNS container is reachable only on the workstation network (or
host loopback on docker-desktop). Registry mirror containers
authenticate to upstream registries using the `username`/`password`
fields in each registry entry; those credentials live in this module's
state.

## See also

- [compute/docker](../../compute/docker/) — provisions cluster nodes that attach to this module's network.
- [cluster/talos](../../cluster/talos/) — its registry-mirror config consumes this module's `registries` output (with computed hostnames).
- [workstation/incus](../incus/) — sister module for Incus VMs.
- [option-workstation.yaml](../../../contexts/_template/facets/option-workstation.yaml) — wiring for both runtime variants.

## Reference

The full module interface — every input, output, and resource — is
listed below. Override any input from your context by adding a tfvars
file at `contexts/<context>/terraform/workstation.tfvars`.

<!-- BEGIN_TF_DOCS -->
### Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >=1.8 |
| <a name="requirement_docker"></a> [docker](#requirement\_docker) | 4.2.0 |

### Providers

| Name | Version |
|------|---------|
| <a name="provider_docker"></a> [docker](#provider\_docker) | 4.2.0 |

### Modules

No modules.

### Resources

| Name | Type |
|------|------|
| [docker_container.dns](https://registry.terraform.io/providers/kreuzwerker/docker/4.2.0/docs/resources/container) | resource |
| [docker_container.git](https://registry.terraform.io/providers/kreuzwerker/docker/4.2.0/docs/resources/container) | resource |
| [docker_container.registry](https://registry.terraform.io/providers/kreuzwerker/docker/4.2.0/docs/resources/container) | resource |
| [docker_image.coredns](https://registry.terraform.io/providers/kreuzwerker/docker/4.2.0/docs/resources/image) | resource |
| [docker_image.git_livereload](https://registry.terraform.io/providers/kreuzwerker/docker/4.2.0/docs/resources/image) | resource |
| [docker_image.registry](https://registry.terraform.io/providers/kreuzwerker/docker/4.2.0/docs/resources/image) | resource |
| [docker_network.main](https://registry.terraform.io/providers/kreuzwerker/docker/4.2.0/docs/resources/network) | resource |

### Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_context"></a> [context](#input\_context) | Windsor context name (e.g. local, test). Used for compose\_project and labels; container names use domain\_name (which defaults to context). Universal variable provided by the environment. | `string` | n/a | yes |
| <a name="input_dns_forward_target"></a> [dns\_forward\_target](#input\_dns\_forward\_target) | Target for Corefile forward directive (context zone). If null: linux uses loadbalancer\_start\_ip, docker-desktop uses gateway:8053. | `string` | `null` | no |
| <a name="input_domain_name"></a> [domain\_name](#input\_domain\_name) | Domain name used for DNS zone and hostnames in the Corefile (e.g. dns.domain\_name, git.domain\_name). Defaults to context when not set. | `string` | `null` | no |
| <a name="input_enable_dns"></a> [enable\_dns](#input\_enable\_dns) | Create the DNS (CoreDNS) container. | `bool` | `true` | no |
| <a name="input_enable_git"></a> [enable\_git](#input\_enable\_git) | Create the git livereload container. | `bool` | `true` | no |
| <a name="input_git_password"></a> [git\_password](#input\_git\_password) | Password for git livereload HTTP auth. Defaults to local. | `string` | `"local"` | no |
| <a name="input_git_rsync_exclude"></a> [git\_rsync\_exclude](#input\_git\_rsync\_exclude) | Comma-separated list of paths to exclude from rsync (git livereload). | `string` | `".windsor,.terraform,.volumes,.venv"` | no |
| <a name="input_git_rsync_include"></a> [git\_rsync\_include](#input\_git\_rsync\_include) | Comma-separated list of paths to include in rsync (git livereload). | `string` | `"kustomize"` | no |
| <a name="input_git_rsync_protect"></a> [git\_rsync\_protect](#input\_git\_rsync\_protect) | Comma-separated list of paths to protect from deletion in rsync (git livereload). | `string` | `"flux-system"` | no |
| <a name="input_git_username"></a> [git\_username](#input\_git\_username) | Username for git livereload HTTP auth. Defaults to local. | `string` | `"local"` | no |
| <a name="input_loadbalancer_start_ip"></a> [loadbalancer\_start\_ip](#input\_loadbalancer\_start\_ip) | First IP in the load balancer range (e.g. 10.5.1.1). Used to derive webhook\_host and dns\_forward\_target when not overridden. If null, derived as first host of next /24 from network\_cidr. | `string` | `null` | no |
| <a name="input_network_cidr"></a> [network\_cidr](#input\_network\_cidr) | CIDR for the Docker network (e.g. 10.5.0.0/16). Service IPs are assigned sequentially from the lowest block: 1=gateway, 2=dns, 3=git, 4+=registries. Corefile, load balancer subnet, and webhook host are derived from this. | `string` | `"10.5.0.0/16"` | no |
| <a name="input_network_name"></a> [network\_name](#input\_network\_name) | Name of the Docker network for workstation containers. Defaults to windsor-{context} when not set. | `string` | `null` | no |
| <a name="input_node_start_offset"></a> [node\_start\_offset](#input\_node\_start\_offset) | Host index in network\_cidr at which compute nodes begin (exposed via next\_ip for compute/docker start\_ip). Registries fill the fixed reserved block [4, node\_start\_offset) so adding or removing a registry never shifts node IPs. Default 10 matches compute/docker's own sequential base for attached networks. | `number` | `10` | no |
| <a name="input_primary_node_ip"></a> [primary\_node\_ip](#input\_primary\_node\_ip) | IP of the primary developing node (controlplane or worker) for NodePort webhook. If set and webhook\_host is null, used as webhook host. | `string` | `null` | no |
| <a name="input_project_root"></a> [project\_root](#input\_project\_root) | Absolute path to the project root. Used for bind mounts (e.g. .volumes, .windsor, repo). Universal variable provided by the environment. | `string` | n/a | yes |
| <a name="input_receiver_name"></a> [receiver\_name](#input\_receiver\_name) | Name of the Flux Receiver resource used to compute the webhook URL path. | `string` | `"flux-webhook"` | no |
| <a name="input_receiver_namespace"></a> [receiver\_namespace](#input\_receiver\_namespace) | Namespace of the Flux Receiver resource used to compute the webhook URL path. | `string` | `"system-gitops"` | no |
| <a name="input_registries"></a> [registries](#input\_registries) | Map of registry configs (aligned with windsor docker.registries). Key is registry host (e.g. gcr.io, registry.k8s.io). Each entry: remote (proxy upstream URL; Distribution supports only remoteurl, username, password, ttl), hostport (publish port on host, optional). Omit remote for local-only registry. Null is coalesced to empty in the module. Count must fit in the reserved block (node\_start\_offset - 4); raise node\_start\_offset if you need more. | <pre>map(object({<br/>    remote   = optional(string)<br/>    local    = optional(string)<br/>    hostport = optional(number)<br/>  }))</pre> | <pre>{<br/>  "gcr.io": {<br/>    "remote": "https://gcr.io"<br/>  },<br/>  "ghcr.io": {<br/>    "remote": "https://ghcr.io"<br/>  },<br/>  "quay.io": {<br/>    "remote": "https://quay.io"<br/>  },<br/>  "reg.kyverno.io": {<br/>    "remote": "https://reg.kyverno.io"<br/>  },<br/>  "registry-1.docker.io": {<br/>    "local": "docker.io",<br/>    "remote": "https://registry-1.docker.io"<br/>  },<br/>  "registry.k8s.io": {<br/>    "remote": "https://registry.k8s.io"<br/>  }<br/>}</pre> | no |
| <a name="input_runtime"></a> [runtime](#input\_runtime) | Docker host runtime: docker-desktop (localhost-only networking), colima/docker/linux (advanced networking). 'colima' and 'docker' are aliases for 'linux'. Standardized with compute/docker. | `string` | `"docker-desktop"` | no |
| <a name="input_webhook_enabled"></a> [webhook\_enabled](#input\_webhook\_enabled) | Enable git livereload webhook notifications. | `bool` | `true` | no |
| <a name="input_webhook_host"></a> [webhook\_host](#input\_webhook\_host) | IP (or host) for the git livereload webhook URL. Primary load balancer IP or primary developing node IP. If null, derived from loadbalancer\_start\_ip: linux (or colima) = loadbalancer\_start\_ip, docker-desktop = host 10 in same /24 (e.g. 10.5.1.10). | `string` | `null` | no |
| <a name="input_webhook_port"></a> [webhook\_port](#input\_webhook\_port) | Port for the git livereload webhook URL. Use NodePort in docker-desktop mode when gateway is exposed via NodePort. | `number` | `9292` | no |
| <a name="input_webhook_token"></a> [webhook\_token](#input\_webhook\_token) | Raw token for the Flux Receiver secret. The webhook URL is derived by hashing this with the receiver name and namespace. | `string` | `"abcdef123456"` | no |

### Outputs

| Name | Description |
|------|-------------|
| <a name="output_compose_project"></a> [compose\_project](#output\_compose\_project) | Docker Compose project name (workstation-windsor-{context}). Use as compute/docker compose\_project so cluster containers share the same compose group. |
| <a name="output_containers"></a> [containers](#output\_containers) | Map of service name to container name: dns, git (when enabled), and each registry key. |
| <a name="output_corefile_path"></a> [corefile\_path](#output\_corefile\_path) | Path to the Corefile on the host; null when Corefile is injected into the container via upload (no host file). |
| <a name="output_dns_ip"></a> [dns\_ip](#output\_dns\_ip) | Host-facing IP for the DNS container. For docker-desktop runtime, 127.0.0.1 (ports published to localhost); otherwise cidrhost(network\_cidr, 2). |
| <a name="output_domain_name"></a> [domain\_name](#output\_domain\_name) | Domain name used for DNS zone and hostnames (dns.domain\_name, git.domain\_name, etc.). Equal to var.domain\_name when set, otherwise var.context. |
| <a name="output_loadbalancer_start_ip"></a> [loadbalancer\_start\_ip](#output\_loadbalancer\_start\_ip) | First IP in the load balancer range. Derived from network\_cidr (first host of next /24) when not set. Webhook host and dns\_forward\_target are derived from this. |
| <a name="output_network_cidr"></a> [network\_cidr](#output\_network\_cidr) | CIDR of the Docker network (same as var.network\_cidr). Used by compute/docker when attaching to this network. |
| <a name="output_network_id"></a> [network\_id](#output\_network\_id) | ID of the Docker network. |
| <a name="output_network_name"></a> [network\_name](#output\_network\_name) | Name of the Docker network. |
| <a name="output_next_ip"></a> [next\_ip](#output\_next\_ip) | First IP for sequential node assignment. Fixed at host index var.node\_start\_offset (default 10); stable across registry add/remove because registries fill the reserved block [4, node\_start\_offset). Use as compute/docker start\_ip when attaching to this network. |
| <a name="output_registries"></a> [registries](#output\_registries) | Registry config with computed hostname per entry. Merges var.registries with hostname (e.g. gcr.domain\_name) for cluster Talos mirrors and other consumers. |
| <a name="output_service_ips"></a> [service\_ips](#output\_service\_ips) | IPv4 addresses from network\_cidr: dns=2, git=3, registries=4..(node\_start\_offset-1). |
| <a name="output_webhook_host"></a> [webhook\_host](#output\_webhook\_host) | IP (or host) used for the git livereload webhook URL. Derived from loadbalancer\_start\_ip when webhook\_host and primary\_node\_ip are not set. |
<!-- END_TF_DOCS -->