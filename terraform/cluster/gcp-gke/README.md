---
title: cluster/gcp-gke
description: Managed Kubernetes control plane on GCP.
---

# cluster/gcp-gke

Managed Kubernetes control plane on GCP. GKE Standard with Dataplane V2
enabled — Google's own managed Cilium integration, the same shape
`cluster/azure-aks` uses (`network_data_plane = "cilium"`), so Windsor's
own `cni/cilium` kustomize component never installs on GKE. Nodes are
private with no public IP; the control plane keeps a public endpoint
restricted to `authorized_networks`. Workload Identity is enabled at the
cluster level for later Workload Identity Federation bindings. Consumes a
VPC network and private subnet from `network/gcp-vpc`.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.12.2 |
| <a name="requirement_google"></a> [google](#requirement\_google) | 8.1.0 |
| <a name="requirement_null"></a> [null](#requirement\_null) | ~> 3.2 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 8.1.0 |
| <a name="provider_null"></a> [null](#provider\_null) | 3.3.1 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [google_container_cluster.this](https://registry.terraform.io/providers/hashicorp/google/8.1.0/docs/resources/container_cluster) | resource |
| [google_container_node_pool.pools](https://registry.terraform.io/providers/hashicorp/google/8.1.0/docs/resources/container_node_pool) | resource |
| [google_container_node_pool.system](https://registry.terraform.io/providers/hashicorp/google/8.1.0/docs/resources/container_node_pool) | resource |
| [null_resource.kubeconfig](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_authorized_networks"></a> [authorized\_networks](#input\_authorized\_networks) | CIDR blocks allowed to reach the control plane's public endpoint | `list(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |
| <a name="input_class_machine_types"></a> [class\_machine\_types](#input\_class\_machine\_types) | Default GCE machine type list per portable pool class. Only the first entry is used; remaining entries document an operator preference order. A pool's explicit instance\_types overrides this map. When overriding this variable, all seven class keys must be supplied — partial overrides are rejected at validate time. | `map(list(string))` | <pre>{<br/>  "arm64": [<br/>    "t2a-standard-4",<br/>    "t2a-standard-8"<br/>  ],<br/>  "compute": [<br/>    "c2-standard-4",<br/>    "c2-standard-8",<br/>    "c2-standard-16"<br/>  ],<br/>  "general": [<br/>    "e2-standard-4",<br/>    "n2-standard-4",<br/>    "e2-standard-8"<br/>  ],<br/>  "gpu": [<br/>    "g2-standard-4",<br/>    "g2-standard-8"<br/>  ],<br/>  "memory": [<br/>    "n2-highmem-4",<br/>    "n2-highmem-8"<br/>  ],<br/>  "storage": [<br/>    "n2-standard-8",<br/>    "n2-standard-16"<br/>  ],<br/>  "system": [<br/>    "e2-standard-2",<br/>    "e2-standard-4"<br/>  ]<br/>}</pre> | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the GKE cluster. If not provided, a default name will be generated | `string` | `""` | no |
| <a name="input_context_id"></a> [context\_id](#input\_context\_id) | Context ID for the resources | `string` | n/a | yes |
| <a name="input_context_path"></a> [context\_path](#input\_context\_path) | The path to the context folder, where kubeconfig is stored | `string` | `""` | no |
| <a name="input_master_ipv4_cidr_block"></a> [master\_ipv4\_cidr\_block](#input\_master\_ipv4\_cidr\_block) | A /28 CIDR block for the private control plane's internal address, disjoint from every subnet in the VPC | `string` | `"172.16.0.0/28"` | no |
| <a name="input_name"></a> [name](#input\_name) | Name prefix for the GKE cluster | `string` | `"cluster"` | no |
| <a name="input_network_id"></a> [network\_id](#input\_network\_id) | ID of the VPC network the cluster attaches to. Pipe network/gcp-vpc's network\_id output. | `string` | n/a | yes |
| <a name="input_pools"></a> [pools](#input\_pools) | Portable user-pool definitions, keyed by pool name; mirrors the AWS-EKS/AKS pools input. Empty falls back to one autoscaling general pool. Autoscaling defaults on (min 1, max 3) for every class except system. | <pre>map(object({<br/>    class          = string<br/>    count          = number<br/>    lifecycle      = optional(string, "on-demand")<br/>    instance_types = optional(list(string))<br/>    root_disk_size = optional(number)<br/>    autoscaling = optional(object({<br/>      enabled = optional(bool)<br/>      min     = optional(number)<br/>      max     = optional(number)<br/>    }))<br/>    labels = optional(map(string), {})<br/>    taints = optional(list(object({<br/>      key    = string<br/>      value  = optional(string)<br/>      effect = string<br/>    })), [])<br/>  }))</pre> | `{}` | no |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | GCP project ID the cluster is created in | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | GCP region for the cluster | `string` | `"us-central1"` | no |
| <a name="input_release_channel"></a> [release\_channel](#input\_release\_channel) | GKE release channel: RAPID, REGULAR, or STABLE | `string` | `"REGULAR"` | no |
| <a name="input_subnetwork_id"></a> [subnetwork\_id](#input\_subnetwork\_id) | ID of the private subnet nodes attach to. Pipe network/gcp-vpc's private\_subnet\_id output. | `string` | n/a | yes |
| <a name="input_system_node_pool"></a> [system\_node\_pool](#input\_system\_node\_pool) | Configuration for the system node pool | <pre>object({<br/>    machine_type        = string<br/>    disk_size_gb        = number<br/>    node_count          = number<br/>    autoscaling_enabled = bool<br/>    min_count           = number<br/>    max_count           = number<br/>  })</pre> | <pre>{<br/>  "autoscaling_enabled": true,<br/>  "disk_size_gb": 50,<br/>  "machine_type": "e2-standard-2",<br/>  "max_count": 3,<br/>  "min_count": 1,<br/>  "node_count": 1<br/>}</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_cluster_id"></a> [cluster\_id](#output\_cluster\_id) | Fully qualified ID of the GKE cluster. |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | Name of the GKE cluster. Consumed by kustomize substitutions (txt-owner-id, etc.). |
| <a name="output_endpoint"></a> [endpoint](#output\_endpoint) | IP address of the cluster's control plane endpoint. |
| <a name="output_project_id"></a> [project\_id](#output\_project\_id) | GCP project the cluster lives in. |
| <a name="output_region"></a> [region](#output\_region) | GCP region the cluster lives in. |
| <a name="output_workload_pool"></a> [workload\_pool](#output\_workload\_pool) | Workload Identity pool (PROJECT\_ID.svc.id.goog). Required to bind Workload Identity Federation credentials to Kubernetes ServiceAccounts. |
<!-- END_TF_DOCS -->
