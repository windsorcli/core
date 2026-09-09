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

## Notes

### Prerequisites

GCP disables most APIs per-project by default. Enable them once, before the
first apply:

```bash
gcloud services enable \
  container.googleapis.com compute.googleapis.com dns.googleapis.com \
  iam.googleapis.com cloudkms.googleapis.com sqladmin.googleapis.com \
  servicenetworking.googleapis.com \
  --project=<project-id>
```

Requires a linked billing account; GKE's control plane and Compute Engine
nodes have no free tier.

The identity running `terraform apply`/`destroy` needs project roles
beyond `roles/editor` alone. GCP excludes several service boundaries
from it entirely, confirmed directly against real `apply`/`destroy`
cycles through this module and `database/gcp-cloudsql`:

```bash
for ROLE in roles/editor roles/resourcemanager.projectIamAdmin \
  roles/iam.serviceAccountAdmin roles/cloudkms.admin \
  roles/servicenetworking.networksAdmin roles/container.admin; do
  gcloud projects add-iam-policy-binding <project-id> \
    --member="serviceAccount:<identity>" --role="$ROLE"
done
```

- `roles/cloudkms.admin` — `roles/editor` excludes Cloud KMS.
  `database/gcp-cloudsql`'s key needs it.
- `roles/servicenetworking.networksAdmin` — `roles/editor` excludes
  Service Networking peering management. `database/gcp-cloudsql`'s
  private connection needs it.
- `roles/container.admin` — creating a `Role`, `ClusterRole`, or
  `ClusterRoleBinding` inside the cluster (`gitops/flux` does this)
  needs `container.roles.create`/`container.clusterRoles.create`/
  `container.clusterRoleBindings.create`, none of which
  `roles/editor` grants. This is a GKE-specific guard against RBAC
  privilege escalation, on top of standard Kubernetes RBAC.
- `roles/resourcemanager.projectIamAdmin`, `roles/iam.serviceAccountAdmin` —
  the IAM bindings `provisioning/crossplane-identity-gcp` creates.

`kubectl`/client-go authentication against a GKE cluster needs the
`gke-gcloud-auth-plugin` binary, not bundled with a base `gcloud` install:

```bash
gcloud components install gke-gcloud-auth-plugin
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.12.2 |
| <a name="requirement_google"></a> [google](#requirement\_google) | 8.2.0 |
| <a name="requirement_null"></a> [null](#requirement\_null) | ~> 3.2 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 8.2.0 |
| <a name="provider_null"></a> [null](#provider\_null) | 3.3.1 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [google_container_cluster.this](https://registry.terraform.io/providers/hashicorp/google/8.2.0/docs/resources/container_cluster) | resource |
| [google_container_node_pool.pools](https://registry.terraform.io/providers/hashicorp/google/8.2.0/docs/resources/container_node_pool) | resource |
| [google_container_node_pool.system](https://registry.terraform.io/providers/hashicorp/google/8.2.0/docs/resources/container_node_pool) | resource |
| [google_dns_managed_zone_iam_member.cert_manager_dns](https://registry.terraform.io/providers/hashicorp/google/8.2.0/docs/resources/dns_managed_zone_iam_member) | resource |
| [google_dns_managed_zone_iam_member.external_dns_dns](https://registry.terraform.io/providers/hashicorp/google/8.2.0/docs/resources/dns_managed_zone_iam_member) | resource |
| [google_project_iam_member.cert_manager_dns_list](https://registry.terraform.io/providers/hashicorp/google/8.2.0/docs/resources/project_iam_member) | resource |
| [google_project_iam_member.external_dns_dns_list](https://registry.terraform.io/providers/hashicorp/google/8.2.0/docs/resources/project_iam_member) | resource |
| [google_service_account.cert_manager](https://registry.terraform.io/providers/hashicorp/google/8.2.0/docs/resources/service_account) | resource |
| [google_service_account.external_dns](https://registry.terraform.io/providers/hashicorp/google/8.2.0/docs/resources/service_account) | resource |
| [google_service_account_iam_member.cert_manager_workload_identity](https://registry.terraform.io/providers/hashicorp/google/8.2.0/docs/resources/service_account_iam_member) | resource |
| [google_service_account_iam_member.external_dns_workload_identity](https://registry.terraform.io/providers/hashicorp/google/8.2.0/docs/resources/service_account_iam_member) | resource |
| [null_resource.kubeconfig](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_authorized_networks"></a> [authorized\_networks](#input\_authorized\_networks) | CIDR blocks allowed to reach the control plane's public endpoint | `list(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |
| <a name="input_cert_manager_dns_zone_names"></a> [cert\_manager\_dns\_zone\_names](#input\_cert\_manager\_dns\_zone\_names) | Names of the Cloud DNS managed zones cert-manager is allowed to write ACME challenge records to. The roles/dns.admin grant is scoped to these zones — leave empty when create\_cert\_manager\_identity is false. | `list(string)` | `[]` | no |
| <a name="input_class_machine_types"></a> [class\_machine\_types](#input\_class\_machine\_types) | GCE machine type list per portable pool class, in fallback order. An autoscaling pool creates one node pool per entry, falling over to the next on a capacity failure; a fixed-count pool only uses the first. A pool's explicit instance\_types overrides this map with the same semantics. Overriding requires all seven class keys — partial overrides are rejected at validate time. | `map(list(string))` | <pre>{<br/>  "arm64": [<br/>    "t2a-standard-4",<br/>    "t2a-standard-8"<br/>  ],<br/>  "compute": [<br/>    "c2-standard-4",<br/>    "c2-standard-8",<br/>    "c2-standard-16"<br/>  ],<br/>  "general": [<br/>    "e2-standard-4",<br/>    "n2d-standard-4",<br/>    "n2-standard-4"<br/>  ],<br/>  "gpu": [<br/>    "g2-standard-4",<br/>    "g2-standard-8"<br/>  ],<br/>  "memory": [<br/>    "n2-highmem-4",<br/>    "n2-highmem-8"<br/>  ],<br/>  "storage": [<br/>    "n2-standard-8",<br/>    "n2-standard-16"<br/>  ],<br/>  "system": [<br/>    "e2-standard-2",<br/>    "n2d-standard-2",<br/>    "n2-standard-2"<br/>  ]<br/>}</pre> | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the GKE cluster. If not provided, a default name will be generated | `string` | `""` | no |
| <a name="input_context_id"></a> [context\_id](#input\_context\_id) | Context ID for the resources | `string` | n/a | yes |
| <a name="input_context_path"></a> [context\_path](#input\_context\_path) | The path to the context folder, where kubeconfig is stored | `string` | `""` | no |
| <a name="input_create_cert_manager_identity"></a> [create\_cert\_manager\_identity](#input\_create\_cert\_manager\_identity) | Whether to provision a Google Service Account, Workload Identity binding, and roles/dns.admin grants for cert-manager's cloudDNS ACME DNS-01 solver. Enable when cert-manager will issue ACME certificates against a Cloud DNS zone. | `bool` | `false` | no |
| <a name="input_create_external_dns_identity"></a> [create\_external\_dns\_identity](#input\_create\_external\_dns\_identity) | Whether to provision a Google Service Account, Workload Identity binding, and roles/dns.admin grants for external-dns. Enable when external-dns will publish records to a Cloud DNS zone. | `bool` | `true` | no |
| <a name="input_external_dns_dns_zone_names"></a> [external\_dns\_dns\_zone\_names](#input\_external\_dns\_dns\_zone\_names) | Names of the Cloud DNS managed zones external-dns is allowed to manage records in. The roles/dns.admin grant is scoped to these zones — leave empty when create\_external\_dns\_identity is false. | `list(string)` | `[]` | no |
| <a name="input_master_ipv4_cidr_block"></a> [master\_ipv4\_cidr\_block](#input\_master\_ipv4\_cidr\_block) | A /28 CIDR block for the private control plane's internal address, disjoint from every subnet in the VPC | `string` | `"172.16.0.0/28"` | no |
| <a name="input_name"></a> [name](#input\_name) | Name prefix for the GKE cluster | `string` | `"cluster"` | no |
| <a name="input_network_id"></a> [network\_id](#input\_network\_id) | ID of the VPC network the cluster attaches to. Pipe network/gcp-vpc's network\_id output. | `string` | n/a | yes |
| <a name="input_node_locations"></a> [node\_locations](#input\_node\_locations) | Zones the cluster's own bootstrap pool and every node pool are placed in. GKE creates one instance group per zone listed here, so a fixed-count pool's node\_count multiplies by length(node\_locations). | `list(string)` | n/a | yes |
| <a name="input_pools"></a> [pools](#input\_pools) | Portable user-pool definitions, keyed by pool name; mirrors the AWS-EKS/AKS pools input. Empty falls back to one autoscaling general pool. Autoscaling defaults on (min 1, max 3) for every class except system. | <pre>map(object({<br/>    class          = string<br/>    count          = number<br/>    lifecycle      = optional(string, "on-demand")<br/>    instance_types = optional(list(string))<br/>    root_disk_size = optional(number)<br/>    autoscaling = optional(object({<br/>      enabled = optional(bool)<br/>      min     = optional(number)<br/>      max     = optional(number)<br/>    }))<br/>    labels = optional(map(string), {})<br/>    taints = optional(list(object({<br/>      key    = string<br/>      value  = optional(string)<br/>      effect = string<br/>    })), [])<br/>  }))</pre> | `{}` | no |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | GCP project ID the cluster is created in | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | GCP region for the cluster | `string` | `"us-central1"` | no |
| <a name="input_release_channel"></a> [release\_channel](#input\_release\_channel) | GKE release channel: RAPID, REGULAR, or STABLE | `string` | `"REGULAR"` | no |
| <a name="input_subnetwork_id"></a> [subnetwork\_id](#input\_subnetwork\_id) | ID of the private subnet nodes attach to. Pipe network/gcp-vpc's private\_subnet\_id output. | `string` | n/a | yes |
| <a name="input_system_node_pool"></a> [system\_node\_pool](#input\_system\_node\_pool) | Configuration for the system node pool. Fields default independently, so a caller can override just node\_count. machine\_type is a fallback-ordered list, same semantics as class\_machine\_types: the primary keeps the pool's configured size, and each additional entry backs a fallback pool GKE's autoscaler can fall over to when the primary is out of capacity. | <pre>object({<br/>    machine_type        = optional(list(string), ["e2-standard-2", "n2d-standard-2", "n2-standard-2"])<br/>    disk_size_gb        = optional(number, 50)<br/>    node_count          = optional(number, 1)<br/>    autoscaling_enabled = optional(bool, false)<br/>    min_count           = optional(number, 1)<br/>    max_count           = optional(number, 3)<br/>  })</pre> | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_cert_manager_service_account_email"></a> [cert\_manager\_service\_account\_email](#output\_cert\_manager\_service\_account\_email) | Email of the cert-manager Google Service Account. Annotate cert-manager's KSA with iam.gke.io/gcp-service-account to bind it. |
| <a name="output_cluster_id"></a> [cluster\_id](#output\_cluster\_id) | Fully qualified ID of the GKE cluster. |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | Name of the GKE cluster. Consumed by kustomize substitutions (txt-owner-id, etc.). |
| <a name="output_endpoint"></a> [endpoint](#output\_endpoint) | IP address of the cluster's control plane endpoint. |
| <a name="output_external_dns_service_account_email"></a> [external\_dns\_service\_account\_email](#output\_external\_dns\_service\_account\_email) | Email of the external-dns Google Service Account. Annotate external-dns's KSA with iam.gke.io/gcp-service-account to bind it. |
| <a name="output_project_id"></a> [project\_id](#output\_project\_id) | GCP project the cluster lives in. |
| <a name="output_region"></a> [region](#output\_region) | GCP region the cluster lives in. |
| <a name="output_workload_pool"></a> [workload\_pool](#output\_workload\_pool) | Workload Identity pool (PROJECT\_ID.svc.id.goog). Required to bind Workload Identity Federation credentials to Kubernetes ServiceAccounts. |
<!-- END_TF_DOCS -->
