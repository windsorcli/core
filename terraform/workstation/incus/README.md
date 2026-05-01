<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >=1.8 |
| <a name="requirement_incus"></a> [incus](#requirement\_incus) | 1.0.2 |
| <a name="requirement_local"></a> [local](#requirement\_local) | 2.8.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_incus"></a> [incus](#provider\_incus) | 1.0.2 |
| <a name="provider_local"></a> [local](#provider\_local) | 2.8.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [incus_instance.dns](https://registry.terraform.io/providers/lxc/incus/1.0.2/docs/resources/instance) | resource |
| [incus_instance.git](https://registry.terraform.io/providers/lxc/incus/1.0.2/docs/resources/instance) | resource |
| [incus_instance.registry](https://registry.terraform.io/providers/lxc/incus/1.0.2/docs/resources/instance) | resource |
| [incus_network.main](https://registry.terraform.io/providers/lxc/incus/1.0.2/docs/resources/network) | resource |
| [local_file.corefile](https://registry.terraform.io/providers/hashicorp/local/2.8.0/docs/resources/file) | resource |
| [local_file.registry_cache_dir](https://registry.terraform.io/providers/hashicorp/local/2.8.0/docs/resources/file) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_context"></a> [context](#input\_context) | Windsor context name (e.g. local, test). Used for network name and instance names; container names use domain\_name (which defaults to context). Universal variable provided by the environment. | `string` | n/a | yes |
| <a name="input_create_network"></a> [create\_network](#input\_create\_network) | Whether to create the Incus network. If false, use network\_name as existing network (e.g. incusbr0 when runtime is colima). | `bool` | `true` | no |
| <a name="input_dns_forward_target"></a> [dns\_forward\_target](#input\_dns\_forward\_target) | Target for Corefile forward directive (context zone). If null, uses loadbalancer\_start\_ip. | `string` | `null` | no |
| <a name="input_domain_name"></a> [domain\_name](#input\_domain\_name) | Domain name used for DNS zone and hostnames in the Corefile (e.g. dns.domain\_name, git.domain\_name). Defaults to context when not set. | `string` | `null` | no |
| <a name="input_enable_dns"></a> [enable\_dns](#input\_enable\_dns) | Create the DNS (CoreDNS) container. | `bool` | `true` | no |
| <a name="input_enable_git"></a> [enable\_git](#input\_enable\_git) | Create the git livereload container. | `bool` | `true` | no |
| <a name="input_git_password"></a> [git\_password](#input\_git\_password) | Password for git livereload HTTP auth. Defaults to local. | `string` | `"local"` | no |
| <a name="input_git_rsync_exclude"></a> [git\_rsync\_exclude](#input\_git\_rsync\_exclude) | Comma-separated list of paths to exclude from rsync (git livereload). | `string` | `".windsor,.terraform,.volumes,.venv"` | no |
| <a name="input_git_rsync_include"></a> [git\_rsync\_include](#input\_git\_rsync\_include) | Comma-separated list of paths to include in rsync (git livereload). | `string` | `"kustomize"` | no |
| <a name="input_git_rsync_protect"></a> [git\_rsync\_protect](#input\_git\_rsync\_protect) | Comma-separated list of paths to protect from deletion in rsync (git livereload). | `string` | `"flux-system"` | no |
| <a name="input_git_username"></a> [git\_username](#input\_git\_username) | Username for git livereload HTTP auth. Defaults to local. | `string` | `"local"` | no |
| <a name="input_loadbalancer_start_ip"></a> [loadbalancer\_start\_ip](#input\_loadbalancer\_start\_ip) | First IP in the load balancer range (e.g. 10.5.1.1). Used to derive webhook\_host and dns\_forward\_target when not overridden. If null, derived as first host of next /24 from network\_cidr. | `string` | `null` | no |
| <a name="input_network_cidr"></a> [network\_cidr](#input\_network\_cidr) | CIDR for the Incus network (e.g. 10.5.0.0/16). Service IPs are assigned sequentially: 1=gateway, 2=dns, 3=git, 4+=registries. Corefile, load balancer subnet, and webhook host are derived from this. | `string` | `"10.5.0.0/16"` | no |
| <a name="input_network_name"></a> [network\_name](#input\_network\_name) | Name of the Incus bridge network. When create\_network is true, defaults to windsor-{context}. When create\_network is false, must be the existing network (e.g. incusbr0 for Colima). | `string` | `null` | no |
| <a name="input_node_start_offset"></a> [node\_start\_offset](#input\_node\_start\_offset) | Host index in network\_cidr at which compute nodes begin (exposed via next\_ip for compute/incus). Registries fill the fixed reserved block [4, node\_start\_offset) so adding or removing a registry never shifts node IPs. Default 10 matches the hardcoded controlplane offset used by option-workstation. | `number` | `10` | no |
| <a name="input_primary_node_ip"></a> [primary\_node\_ip](#input\_primary\_node\_ip) | IP of the primary developing node (controlplane or worker) for NodePort webhook. If set and webhook\_host is null, used as webhook host. | `string` | `null` | no |
| <a name="input_project_root"></a> [project\_root](#input\_project\_root) | Absolute path to the project root. Used for bind mounts (Corefile, .windsor/cache, repo). Universal variable provided by the environment. | `string` | n/a | yes |
| <a name="input_receiver_name"></a> [receiver\_name](#input\_receiver\_name) | Name of the Flux Receiver resource used to compute the webhook URL path. | `string` | `"flux-webhook"` | no |
| <a name="input_receiver_namespace"></a> [receiver\_namespace](#input\_receiver\_namespace) | Namespace of the Flux Receiver resource used to compute the webhook URL path. | `string` | `"system-gitops"` | no |
| <a name="input_registries"></a> [registries](#input\_registries) | Map of registry configs (aligned with windsor docker.registries). Key is registry host (e.g. gcr.io, registry.k8s.io). Each entry: remote (proxy upstream URL), hostport (unused for Incus; kept for API compatibility), local. Omit remote for local-only registry. | <pre>map(object({<br/>    remote   = optional(string)<br/>    local    = optional(string)<br/>    hostport = optional(number)<br/>  }))</pre> | <pre>{<br/>  "gcr.io": {<br/>    "remote": "https://gcr.io"<br/>  },<br/>  "ghcr.io": {<br/>    "remote": "https://ghcr.io"<br/>  },<br/>  "quay.io": {<br/>    "remote": "https://quay.io"<br/>  },<br/>  "reg.kyverno.io": {<br/>    "remote": "https://reg.kyverno.io"<br/>  },<br/>  "registry-1.docker.io": {<br/>    "local": "docker.io",<br/>    "remote": "https://registry-1.docker.io"<br/>  },<br/>  "registry.k8s.io": {<br/>    "remote": "https://registry.k8s.io"<br/>  }<br/>}</pre> | no |
| <a name="input_webhook_enabled"></a> [webhook\_enabled](#input\_webhook\_enabled) | Enable git livereload webhook notifications. | `bool` | `true` | no |
| <a name="input_webhook_host"></a> [webhook\_host](#input\_webhook\_host) | IP (or host) for the git livereload webhook URL. If null, derived from loadbalancer\_start\_ip. | `string` | `null` | no |
| <a name="input_webhook_port"></a> [webhook\_port](#input\_webhook\_port) | Port for the git livereload webhook URL. | `number` | `9292` | no |
| <a name="input_webhook_token"></a> [webhook\_token](#input\_webhook\_token) | Raw token for the Flux Receiver secret. The webhook URL is derived by hashing this with the receiver name and namespace. | `string` | `"abcdef123456"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_compose_project"></a> [compose\_project](#output\_compose\_project) | Compose project name (workstation-windsor-{context}). Kept for API compatibility with workstation/docker; compute/incus does not use it. |
| <a name="output_containers"></a> [containers](#output\_containers) | Map of service name to instance name: dns, git (when enabled), and each registry key. |
| <a name="output_corefile_path"></a> [corefile\_path](#output\_corefile\_path) | Path to the Corefile on the host (project\_root/.windsor/Corefile). Written by Terraform when enable\_dns is true. |
| <a name="output_dns_ip"></a> [dns\_ip](#output\_dns\_ip) | IPv4 address reserved for the DNS container (cidrhost(network\_cidr, 2)). Present in service\_ips.dns when enable\_dns is true. |
| <a name="output_domain_name"></a> [domain\_name](#output\_domain\_name) | Domain name used for DNS zone and hostnames (dns.domain\_name, git.domain\_name, etc.). Equal to var.domain\_name when set, otherwise var.context. |
| <a name="output_loadbalancer_start_ip"></a> [loadbalancer\_start\_ip](#output\_loadbalancer\_start\_ip) | First IP in the load balancer range. Derived from network\_cidr (first host of next /24) when not set. Webhook host and dns\_forward\_target are derived from this. |
| <a name="output_network_cidr"></a> [network\_cidr](#output\_network\_cidr) | CIDR of the Incus network (same as var.network\_cidr). Used by compute/incus when attaching to this network. |
| <a name="output_network_name"></a> [network\_name](#output\_network\_name) | Name of the Incus network (created or existing when create\_network is false). |
| <a name="output_next_ip"></a> [next\_ip](#output\_next\_ip) | First IP for sequential node assignment. Fixed at host index var.node\_start\_offset (default 10); stable across registry add/remove because registries fill the reserved block [4, node\_start\_offset). Use as compute/incus start offset when attaching to this network. |
| <a name="output_registries"></a> [registries](#output\_registries) | Registry config with computed hostname per entry. Same shape as workstation/docker for cluster Talos mirrors. |
| <a name="output_service_ips"></a> [service\_ips](#output\_service\_ips) | IPv4 addresses from network\_cidr (sequential: dns=2, git=3, registries=4+). |
| <a name="output_webhook_host"></a> [webhook\_host](#output\_webhook\_host) | IP (or host) used for the git livereload webhook URL. Derived from loadbalancer\_start\_ip when webhook\_host and primary\_node\_ip are not set. |
<!-- END_TF_DOCS -->