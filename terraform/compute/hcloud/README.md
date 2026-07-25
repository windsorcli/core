---
title: compute/hcloud
description: Provisions Talos Linux nodes on Hetzner Cloud.
---

# compute/hcloud

Provisions Talos Linux nodes on Hetzner Cloud. Builds a Talos Image Factory
snapshot with the `hcloud-talos/imager` provider (or reuses a supplied snapshot
id), creates a private network, and boots servers from the snapshot into Talos
maintenance mode. Windsor's `cluster/talos` module then applies machine config
over each server's public IP.

The `HCLOUD_TOKEN` environment variable authenticates both the hcloud and imager
providers.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.12.2 |
| <a name="requirement_hcloud"></a> [hcloud](#requirement\_hcloud) | 1.66.1 |
| <a name="requirement_imager"></a> [imager](#requirement\_imager) | 1.0.16 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_hcloud"></a> [hcloud](#provider\_hcloud) | 1.66.1 |
| <a name="provider_imager"></a> [imager](#provider\_imager) | 1.0.16 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [hcloud_firewall.this](https://registry.terraform.io/providers/hetznercloud/hcloud/1.66.1/docs/resources/firewall) | resource |
| [hcloud_network.this](https://registry.terraform.io/providers/hetznercloud/hcloud/1.66.1/docs/resources/network) | resource |
| [hcloud_network_subnet.this](https://registry.terraform.io/providers/hetznercloud/hcloud/1.66.1/docs/resources/network_subnet) | resource |
| [hcloud_placement_group.this](https://registry.terraform.io/providers/hetznercloud/hcloud/1.66.1/docs/resources/placement_group) | resource |
| [hcloud_server.this](https://registry.terraform.io/providers/hetznercloud/hcloud/1.66.1/docs/resources/server) | resource |
| [hcloud_server_network.this](https://registry.terraform.io/providers/hetznercloud/hcloud/1.66.1/docs/resources/server_network) | resource |
| [imager_image.this](https://registry.terraform.io/providers/hcloud-talos/imager/1.0.16/docs/resources/image) | resource |
| [terraform_data.node_replacement](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_api_allowed_cidrs"></a> [api\_allowed\_cidrs](#input\_api\_allowed\_cidrs) | Source CIDRs allowed to reach the Talos API (50000) and Kubernetes API (6443) on the public interface. | `list(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |
| <a name="input_context_id"></a> [context\_id](#input\_context\_id) | The windsor context id for this deployment; used to name and label resources. | `string` | `""` | no |
| <a name="input_context_path"></a> [context\_path](#input\_context\_path) | The path to the context folder. | `string` | `""` | no |
| <a name="input_hcloud_token"></a> [hcloud\_token](#input\_hcloud\_token) | Hetzner Cloud API token for the hcloud and imager providers. Empty falls back to the HCLOUD\_TOKEN environment variable. | `string` | `""` | no |
| <a name="input_image_ids"></a> [image\_ids](#input\_image\_ids) | Pre-existing Hetzner snapshot ids by architecture (x86/arm). When set for an architecture, that snapshot is used instead of building one with the imager provider. | <pre>object({<br/>    x86 = optional(string, "")<br/>    arm = optional(string, "")<br/>  })</pre> | `{}` | no |
| <a name="input_instances"></a> [instances](#input\_instances) | Node groups to provision. Each group expands into `count` servers named <name>-<n> (1-indexed). Architecture is derived from server\_type (cax* → arm, otherwise x86). | <pre>list(object({<br/>    name        = string<br/>    role        = string<br/>    count       = number<br/>    server_type = string<br/>  }))</pre> | `[]` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Additional labels for all resources. | `map(string)` | `{}` | no |
| <a name="input_location"></a> [location](#input\_location) | Hetzner datacenter location for servers (e.g. fsn1, nbg1, hel1, ash, hil, sin). | `string` | `"fsn1"` | no |
| <a name="input_network_cidr"></a> [network\_cidr](#input\_network\_cidr) | CIDR for the private network. A /24 node subnet is carved from it automatically. | `string` | `"10.5.0.0/16"` | no |
| <a name="input_network_zone"></a> [network\_zone](#input\_network\_zone) | Hetzner network zone the private network spans (e.g. eu-central, us-east, us-west, ap-southeast). | `string` | `"eu-central"` | no |
| <a name="input_talos_schematic_id"></a> [talos\_schematic\_id](#input\_talos\_schematic\_id) | Talos Image Factory schematic id for the hcloud image. Defaults to the empty (no-extension) schematic. | `string` | `"376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba"` | no |
| <a name="input_talos_version"></a> [talos\_version](#input\_talos\_version) | Talos version used to build the Image Factory snapshot (e.g. 1.13.7). | `string` | `"1.13.7"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_controlplanes"></a> [controlplanes](#output\_controlplanes) | Control plane nodes formatted for Talos (hostname, endpoint, node, private\_ipv4). Empty until IPs are assigned. |
| <a name="output_location"></a> [location](#output\_location) | Hetzner location the servers run in; consumed by the cloud load balancer. |
| <a name="output_network_id"></a> [network\_id](#output\_network\_id) | Id of the private network, consumed by the hcloud cloud-controller-manager for pod routing. |
| <a name="output_network_name"></a> [network\_name](#output\_network\_name) | Name of the private network. |
| <a name="output_network_zone"></a> [network\_zone](#output\_network\_zone) | Hetzner network zone the private network spans. |
| <a name="output_node_subnet_cidr"></a> [node\_subnet\_cidr](#output\_node\_subnet\_cidr) | The /24 subnet nodes are attached to within the private network. |
| <a name="output_workers"></a> [workers](#output\_workers) | Worker nodes formatted for Talos (hostname, endpoint, node, private\_ipv4). Empty when no workers exist. |
<!-- END_TF_DOCS -->
