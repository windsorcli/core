---
title: compute/docker
description: Provisions Talos controlplane and worker containers on Docker. Outputs node lists consumed by cluster/talos.
---

# compute/docker

Runs Talos as Docker containers on a workstation. This module is the
node-provisioning step on `platform: docker`: it pulls the Talos image,
creates a network (or attaches to an existing one), and starts a
container per controlplane and worker. Its outputs (the node IPs,
endpoints, and roles) are then consumed by [`cluster/talos`](../../cluster/talos/),
which applies machine configuration and bootstraps the cluster.

The module supports two runtimes that differ in how the host reaches
container endpoints:

- `runtime: linux` (the default — covers plain Docker on Linux and Colima): containers get routable IPs on the workstation network, and `cluster/talos` reaches them at `<container-ip>:50000`.
- `runtime: docker-desktop`: containers are reachable only via localhost. The module assigns sequential host ports starting at `50000` (cp1 → `127.0.0.1:50000`, cp2 → `127.0.0.1:50001`, ...) and emits those endpoints so `cluster/talos` can bootstrap from the host.

## Wiring

Wired by [option-workstation.yaml](../../../contexts/_template/facets/option-workstation.yaml)
when `platform: docker` and `cluster.enabled: true` (the default). The
network is created elsewhere by [workstation/docker](../../workstation/docker/);
this module attaches to it via `create_network: false` and the
workstation module's output fields.

```yaml
terraform:
  - name: compute
    path: compute/docker
    dependsOn:
      - workstation
    inputs:
      create_network: false
      network_name: <from workstation output>
      network_cidr: <from workstation output>
      start_ip: <from workstation output>
      runtime: linux
      compose_project: <from workstation output>
      cluster_nodes:
        controlplanes:
          count: 1
          image: ghcr.io/siderolabs/talos:v1.12.6
          cpu: 2
          memory: 2
          hostports: []
          volumes: []
        workers:
          count: 0
          image: ghcr.io/siderolabs/talos:v1.12.6
          cpu: 4
          memory: 4
          hostports: []
          volumes: []
```

How those flow from `values.yaml`:

- `cluster_nodes.controlplanes.*` and `cluster_nodes.workers.*` — `cluster.controlplanes.{count,image,cpu,memory,hostports,volumes}` and `cluster.workers.{...}`. These are the per-pool sizing knobs the operator sets.
- `runtime` — `workstation.runtime` (defaults to `linux`). On `docker-desktop` the module switches to localhost networking and host port mappings.
- `network_name`, `network_cidr`, `start_ip`, `compose_project` — pulled from [`workstation/docker`](../../workstation/docker/)'s outputs via deferred `terraform_output(...)`. Set the values there, not here.
- `image` (controlplane / worker) — `cluster.controlplanes.image` / `cluster.workers.image`, defaulting to `talos.docker_image` (Renovate-pinned).
- `hostports` — `cluster.controlplanes.hostports` / `cluster.workers.hostports`. Auto-set to `["8080:30080/tcp", "8443:30443/tcp"]` on `docker-desktop`; empty otherwise.

The `workstation` Terraform dep ensures the network and supporting
state exist before containers attach.

## Outputs

Outputs are designed to drop directly into [`cluster/talos`](../../cluster/talos/):

- `controlplanes`, `workers` — list of `{hostname, endpoint, node, ...}` objects. `endpoint` is `<ip>:50000` on `linux`/`colima` runtimes; `127.0.0.1:<host-port>` on `docker-desktop`.
- `instances` — flat list of every container with role, IP, image (same shape as `compute/incus.instances`).
- `network_name`, `network_type`, `network_managed`, `container_ports` — supporting outputs.

## Security

Container volumes (`docker_volume.named`) hold Talos node state.
Teardown must remove them or the next bootstrap inherits the old
machine secrets and the TLS handshake fails — see the
`talos_machine_secrets` recreation hazard documented in
[`cluster/talos`](../../cluster/talos/).

The module does not handle external credentials. Image pulls use the
Docker daemon's configured registry credentials.

## See also

- [workstation/docker](../../workstation/docker/) — provisions the network this module attaches to.
- [cluster/talos](../../cluster/talos/) — consumes this module's `controlplanes`/`workers` outputs.
- [compute/incus](../../compute/incus/) — sister module for Incus VMs (same outputs shape).
- [option-workstation.yaml](../../../contexts/_template/facets/option-workstation.yaml) — wiring when `platform: docker`.

## Reference

The full module interface — every input, output, and resource — is
listed below. Override any input from your context by adding a tfvars
file at `contexts/<context>/terraform/compute.tfvars`.

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
| [docker_container.containers](https://registry.terraform.io/providers/kreuzwerker/docker/4.2.0/docs/resources/container) | resource |
| [docker_image.instances](https://registry.terraform.io/providers/kreuzwerker/docker/4.2.0/docs/resources/image) | resource |
| [docker_network.main](https://registry.terraform.io/providers/kreuzwerker/docker/4.2.0/docs/resources/network) | resource |
| [docker_volume.named](https://registry.terraform.io/providers/kreuzwerker/docker/4.2.0/docs/resources/volume) | resource |

### Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cluster_nodes"></a> [cluster\_nodes](#input\_cluster\_nodes) | Declare controlplanes and workers by count and image. Module expands to N+M containers; shape (ports, volumes, env) is chosen by distribution. hostports: first controlplane gets controlplanes.hostports when no workers, else first worker gets workers.hostports. | <pre>object({<br/>    distribution = optional(string, "talos")<br/>    controlplanes = object({<br/>      count     = number<br/>      image     = string<br/>      cpu       = optional(number, 2)<br/>      memory    = optional(number, 2)        # GB<br/>      volumes   = optional(list(string), []) # source:dest; source = host path (/ or .) for bind mount, or volume name for named volume. Appended to distribution shape.<br/>      hostports = optional(list(string), []) # host:container/protocol. Applied to first controlplane when no workers (primary node).<br/>    })<br/>    workers = object({<br/>      count     = number<br/>      image     = string<br/>      cpu       = optional(number, 4)<br/>      memory    = optional(number, 4)        # GB<br/>      volumes   = optional(list(string), []) # source:dest; host path or named volume. Appended to distribution shape.<br/>      hostports = optional(list(string), []) # host:container/protocol. Applied to first worker when workers exist (primary node).<br/>    })<br/>  })</pre> | `null` | no |
| <a name="input_compose_project"></a> [compose\_project](#input\_compose\_project) | Docker Compose project name (e.g. terraform\_output(workstation, compose\_project)). When set, containers get label com.docker.compose.project so they appear in the same compose group. | `string` | `null` | no |
| <a name="input_context"></a> [context](#input\_context) | The windsor context id for this deployment. Typically set implicitly via TF\_VAR\_context; no need to pass in facet inputs. | `string` | `""` | no |
| <a name="input_context_id"></a> [context\_id](#input\_context\_id) | The windsor context id for this deployment. Typically set implicitly via TF\_VAR\_context; no need to pass in facet inputs. | `string` | `""` | no |
| <a name="input_create_network"></a> [create\_network](#input\_create\_network) | Whether to create the network. If false, network\_name must reference an existing network | `bool` | `true` | no |
| <a name="input_instances"></a> [instances](#input\_instances) | List of instance definitions. Used in addition to cluster\_nodes when both are set. Each object specifies container parameters such as image, count, ports, volumes, environment variables, networks, and other optional settings. | <pre>list(object({<br/>    name         = string # Instance/container name (prefix when count > 1, then -0, -1, ...)<br/>    image        = string # Image reference (e.g. nginx:alpine)<br/>    count        = optional(number, 1)<br/>    role         = optional(string)           # Role for outputs (e.g. controlplane, worker)<br/>    ports        = optional(list(string), []) # "host:container/protocol" or "container/protocol" (e.g. 50000/tcp, 8080:30080/tcp, 8053:30053/udp)<br/>    volumes      = optional(list(string), []) # "host:container" or "volume_name:container"; volume_name may contain {container_name}, {instance_name}, {index}, {index_1}<br/>    env          = optional(map(string), {})<br/>    networks     = optional(list(string), []) # Network names; empty = default network<br/>    command      = optional(list(string))<br/>    entrypoint   = optional(list(string))<br/>    restart      = optional(string, "unless-stopped")<br/>    labels       = optional(map(string), {})<br/>    hostname     = optional(string) # May contain {container_name}, {instance_name}, {index}, {index_1} (1-based)<br/>    privileged   = optional(bool, false)<br/>    read_only    = optional(bool, false)<br/>    security_opt = optional(list(string), []) # e.g. ["seccomp=unconfined"]<br/>    tmpfs        = optional(map(string), {})  # path -> options (e.g. { "/run" = "", "/tmp" = "" })<br/>    ipv4_address = optional(string)<br/>    healthcheck = optional(object({<br/>      test         = list(string) # e.g. ["CMD", "curl", "-f", "http://localhost/"]<br/>      interval     = optional(string, "30s")<br/>      timeout      = optional(string, "10s")<br/>      retries      = optional(number, 3)<br/>      start_period = optional(string, "0s")<br/>    }))<br/>    depends_on = optional(list(string), []) # Other instance names (creation order)<br/>  }))</pre> | `[]` | no |
| <a name="input_network_cidr"></a> [network\_cidr](#input\_network\_cidr) | CIDR of the network. When create\_network is false (e.g. workstation), use terraform\_output(workstation, network\_cidr). When set with start\_ip, containers get sequential IPs from start\_ip. | `string` | `null` | no |
| <a name="input_network_driver"></a> [network\_driver](#input\_network\_driver) | Docker network driver (bridge, overlay, etc.) | `string` | `"bridge"` | no |
| <a name="input_network_name"></a> [network\_name](#input\_network\_name) | Name of the network to use. When create\_network is false (e.g. attaching to workstation network), use terraform\_output(workstation, network\_name). When create\_network is true this network is created; empty defaults to windsor-{context}. | `string` | `""` | no |
| <a name="input_project_root"></a> [project\_root](#input\_project\_root) | Project root path for bind mounts (e.g. Talos /var/mnt/local). When set, facets can pass project\_root + '/.volumes:/var/mnt/local' in instance volumes. | `string` | `null` | no |
| <a name="input_runtime"></a> [runtime](#input\_runtime) | Docker host runtime: docker-desktop (localhost-only networking, no VM control) or colima/docker/linux (advanced networking, IP routing). 'colima' and 'docker' are aliases for 'linux'. Standardized with workstation/docker. | `string` | `"linux"` | no |
| <a name="input_start_ip"></a> [start\_ip](#input\_start\_ip) | First container IP for sequential assignment. When create\_network is false (e.g. workstation), use terraform\_output(workstation, next\_ip). With network\_cidr, all containers get sequential IPs from this address. | `string` | `null` | no |

### Outputs

| Name | Description |
|------|-------------|
| <a name="output_container_ports"></a> [container\_ports](#output\_container\_ports) | Port list per container name (for tests: hostports only on first controlplane when no workers, first worker when workers exist). |
| <a name="output_controlplanes"></a> [controlplanes](#output\_controlplanes) | List of controlplane instances for cluster/talos (hostname, endpoint, node). Consumed by provider-docker → cluster/talos when workstation enabled. |
| <a name="output_instances"></a> [instances](#output\_instances) | Flat list of all instances. Same shape as compute/incus (name, hostname, ipv4, ipv6, status, type, image, role). |
| <a name="output_network_managed"></a> [network\_managed](#output\_network\_managed) | Whether the network was created by this module (true when create\_network is true) |
| <a name="output_network_name"></a> [network\_name](#output\_network\_name) | The name of the network being used |
| <a name="output_network_type"></a> [network\_type](#output\_network\_type) | The network driver when create\_network is true (e.g. bridge). Null if network was not created by this module |
| <a name="output_workers"></a> [workers](#output\_workers) | List of worker instances for cluster/talos (hostname, endpoint, node). Consumed by provider-docker → cluster/talos when workstation enabled. |
<!-- END_TF_DOCS -->