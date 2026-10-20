---
title: Cilium
description: Out-of-band Cilium bootstrap for Talos clusters.
---

Installs Cilium directly via Helm against the Talos API before Flux exists,
so Pods can network during cluster bring-up. `kustomize/cni/` adopts the
running release afterward and takes over day-2 changes.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.12.2 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | 3.3.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_helm"></a> [helm](#provider\_helm) | 3.3.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [helm_release.cilium](https://registry.terraform.io/providers/hashicorp/helm/3.3.0/docs/resources/release) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cgroup_auto_mount"></a> [cgroup\_auto\_mount](#input\_cgroup\_auto\_mount) | Let Cilium mount the cgroup2 fs at startup (chart default). Set to false on systems that mount cgroups during init (Talos, most systemd-based distros on recent kernels) so Cilium uses the pre-mounted path instead of racing to mount its own. | `bool` | `true` | no |
| <a name="input_chart_repository"></a> [chart\_repository](#input\_chart\_repository) | Helm repository the Cilium chart is read from. Accepts an oci:// registry address such as oci://registry.example.com/charts or a web address such as https://helm.cilium.io. The chart name stays cilium. | `string` | `"oci://quay.io/cilium/charts"` | no |
| <a name="input_cilium_version"></a> [cilium\_version](#input\_cilium\_version) | Version of the Cilium Helm chart to install. | `string` | `"1.20.3"` | no |
| <a name="input_image_registry"></a> [image\_registry](#input\_image\_registry) | Registry path the Cilium images are pulled from, without a scheme or trailing slash (e.g. registry.example.com/cilium). The agent, operator, envoy, and certgen images are read from <image\_registry>/<image>. | `string` | `"quay.io/cilium"` | no |
| <a name="input_ipam_mode"></a> [ipam\_mode](#input\_ipam\_mode) | Cilium IPAM mode. 'kubernetes' uses node CIDR ranges (default, works for Talos). 'eni' uses AWS ENI-based allocation for EKS native networking. | `string` | `"kubernetes"` | no |
| <a name="input_k8s_service_host"></a> [k8s\_service\_host](#input\_k8s\_service\_host) | API server host Cilium reaches before its eBPF service rules are active. Required when kube\_proxy\_replacement is true. | `string` | `""` | no |
| <a name="input_k8s_service_port"></a> [k8s\_service\_port](#input\_k8s\_service\_port) | API server port for k8s\_service\_host. | `number` | `6443` | no |
| <a name="input_kube_proxy_replacement"></a> [kube\_proxy\_replacement](#input\_kube\_proxy\_replacement) | Replace kube-proxy with Cilium's eBPF implementation. Requires k8s\_service\_host to be set. Recommended for Talos. | `bool` | `true` | no |
| <a name="input_operator_replicas"></a> [operator\_replicas](#input\_operator\_replicas) | Cilium operator replica count. Keep aligned with the Flux-managed HelmRelease so re-runs of this bootstrap don't scale the deployment up or down between Flux reconciles. 1 on physically single-node clusters (operator binds a hostPort, so two replicas can't co-schedule); 2 elsewhere for controller redundancy. | `number` | `2` | no |
| <a name="input_privileged"></a> [privileged](#input\_privileged) | Run the Cilium agent as a privileged container (chart default). Set to false on systems that forbid privileged pods (Talos, hardened distros); the agent will run with an explicit set of Linux capabilities instead. | `bool` | `true` | no |

## Outputs

No outputs.
<!-- END_TF_DOCS -->