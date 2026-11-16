---
title: Flux
description: Flux installation; hands reconciliation to the kustomize/ layer.
---

Installs Flux into a freshly-provisioned cluster so the Kustomize layer
under `core/kustomize/` can take over reconciliation. The module installs
the [flux-operator](https://fluxoperator.dev) and a `FluxInstance` (the
`flux-operator` and `flux-instance` Helm charts), which the operator
reconciles into the Flux CRDs and controllers. The windsor CLI creates the
root `GitRepository` and `Kustomization`, so the `FluxInstance` omits its
`sync` block and manages controllers only.

Controller tuning (concurrency, leader election, helm cache, the
kustomize-controller memory limit) is applied through
`spec.kustomize.patches`.

Controller images resolve by distribution version rather than per-image
digest, so the `require-image-digest` Kyverno policy exempts the Flux
namespace.

A readiness-gate Job blocks the apply until the operator reports the
`FluxInstance` Ready, so the toolkit CRDs exist before the windsor CLI
applies the blueprint. After bootstrap this layer is mostly inert — Flux
self-manages from the repo going forward.

A `removed` block drops the previous `fluxcd-community/flux2` Helm release from
Terraform state without uninstalling it, so the operator adopts the live
controllers. That chart renders the Flux CRDs as templates; a real
`helm uninstall flux2` would cascade-delete every GitRepository, Kustomization,
and HelmRelease in the cluster, so do not run it by hand.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.12.2 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | 3.3.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | 3.3.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | 3.9.1 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_helm"></a> [helm](#provider\_helm) | 3.3.0 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | 3.3.0 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.9.1 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [helm_release.flux_instance](https://registry.terraform.io/providers/hashicorp/helm/3.3.0/docs/resources/release) | resource |
| [helm_release.flux_operator](https://registry.terraform.io/providers/hashicorp/helm/3.3.0/docs/resources/release) | resource |
| [kubernetes_job_v1.flux_ready_gate](https://registry.terraform.io/providers/hashicorp/kubernetes/3.3.0/docs/resources/job_v1) | resource |
| [kubernetes_namespace_v1.flux_system](https://registry.terraform.io/providers/hashicorp/kubernetes/3.3.0/docs/resources/namespace_v1) | resource |
| [kubernetes_priority_class_v1.platform_critical](https://registry.terraform.io/providers/hashicorp/kubernetes/3.3.0/docs/resources/priority_class_v1) | resource |
| [kubernetes_role_binding_v1.flux_ready_gate](https://registry.terraform.io/providers/hashicorp/kubernetes/3.3.0/docs/resources/role_binding_v1) | resource |
| [kubernetes_role_v1.flux_ready_gate](https://registry.terraform.io/providers/hashicorp/kubernetes/3.3.0/docs/resources/role_v1) | resource |
| [kubernetes_secret_v1.git_auth](https://registry.terraform.io/providers/hashicorp/kubernetes/3.3.0/docs/resources/secret_v1) | resource |
| [kubernetes_secret_v1.image_pull](https://registry.terraform.io/providers/hashicorp/kubernetes/3.3.0/docs/resources/secret_v1) | resource |
| [kubernetes_secret_v1.webhook_token](https://registry.terraform.io/providers/hashicorp/kubernetes/3.3.0/docs/resources/secret_v1) | resource |
| [kubernetes_service_account_v1.flux_ready_gate](https://registry.terraform.io/providers/hashicorp/kubernetes/3.3.0/docs/resources/service_account_v1) | resource |
| [random_password.webhook_token](https://registry.terraform.io/providers/hashicorp/random/3.9.1/docs/resources/password) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_chart_repository"></a> [chart\_repository](#input\_chart\_repository) | OCI repository the flux-operator and flux-instance Helm charts are read from (e.g. oci://registry.example.com/charts). | `string` | `"oci://ghcr.io/controlplaneio-fluxcd/charts"` | no |
| <a name="input_concurrency"></a> [concurrency](#input\_concurrency) | Number of concurrent reconciliations per Flux controller | `number` | `2` | no |
| <a name="input_controller_image_tags"></a> [controller\_image\_tags](#input\_controller\_image\_tags) | Tag of each Flux controller image, with its digest. The images are read from <distribution\_registry>/<controller>. The tags MUST match flux\_version. | `map(string)` | <pre>{<br/>  "helm-controller": "v1.7.1@sha256:54526cc6ed1202d71d44c310676448065664f3255ad671d9a69ac26f904e617a",<br/>  "image-automation-controller": "v1.3.0@sha256:6ec488320def72fecfd01ab1289cc6c881d76b984fbbcf69b174e1e10886029e",<br/>  "image-reflector-controller": "v1.3.0@sha256:b4d2cbdc1b7a046c53786628fe900b72b31a95c4cec219478777e3f97c453635",<br/>  "kustomize-controller": "v1.10.1@sha256:37db29b25dae35b881a5e064acedb0cc954442da453a39eaa0eab7a90dbecc4e",<br/>  "notification-controller": "v1.10.0@sha256:9f58b9532ec9d3ccf539cd3ccdf283477a5dcb7777b922db5477d8bbd4d3767c",<br/>  "source-controller": "v1.10.1@sha256:611b6bca3eae95bcff471414d1fb14a4ab83d7f14e609cccef2bd389c121f37e"<br/>}</pre> | no |
| <a name="input_distribution_artifact"></a> [distribution\_artifact](#input\_distribution\_artifact) | OCI artifact the flux-operator reads the Flux distribution manifests from (FluxInstance spec.distribution.artifact). When empty, the operator uses the manifests in its own image, which MUST include flux\_version. | `string` | `""` | no |
| <a name="input_distribution_registry"></a> [distribution\_registry](#input\_distribution\_registry) | Registry the Flux controller images are pulled from (FluxInstance spec.distribution.registry), e.g. registry.example.com/fluxcd. | `string` | `"ghcr.io/fluxcd"` | no |
| <a name="input_distribution_variant"></a> [distribution\_variant](#input\_distribution\_variant) | Flux distribution variant the controller images belong to (FluxInstance spec.distribution.variant). It MUST be set when distribution\_registry is a mirror. When empty, the FluxInstance omits it. | `string` | `""` | no |
| <a name="input_flux_instance_version"></a> [flux\_instance\_version](#input\_flux\_instance\_version) | The version of the flux-instance Helm chart to install | `string` | `"0.62.1"` | no |
| <a name="input_flux_namespace"></a> [flux\_namespace](#input\_flux\_namespace) | The namespace in which Flux will be installed | `string` | `"system-gitops"` | no |
| <a name="input_flux_operator_version"></a> [flux\_operator\_version](#input\_flux\_operator\_version) | The version of the flux-operator Helm chart to install | `string` | `"0.62.1"` | no |
| <a name="input_flux_version"></a> [flux\_version](#input\_flux\_version) | The Flux distribution version the operator installs (FluxInstance spec.distribution.version) | `string` | `"2.10.0"` | no |
| <a name="input_git_auth_secret"></a> [git\_auth\_secret](#input\_git\_auth\_secret) | The name of the secret to store the git authentication details | `string` | `"flux-system"` | no |
| <a name="input_git_password"></a> [git\_password](#input\_git\_password) | The git password or PAT used to authenticte with the git provider | `string` | `""` | no |
| <a name="input_git_username"></a> [git\_username](#input\_git\_username) | The git user to use to authenticte with the git provider | `string` | `"git"` | no |
| <a name="input_image_automation"></a> [image\_automation](#input\_image\_automation) | Enable the Flux image-automation-controller. Only needed for automated image tag updates committed back to Git. | `bool` | `false` | no |
| <a name="input_image_pull_secret"></a> [image\_pull\_secret](#input\_image\_pull\_secret) | Docker config JSON with credentials for the registries that serve the flux-operator and Flux controller images. When empty, the images are pulled anonymously. | `string` | `""` | no |
| <a name="input_image_reflection"></a> [image\_reflection](#input\_image\_reflection) | Enable the Flux image-reflector-controller. Only needed alongside image-automation-controller to scan image registries. | `bool` | `false` | no |
| <a name="input_leader_election"></a> [leader\_election](#input\_leader\_election) | Enable leader election on Flux controllers. Disable on single-node clusters to eliminate lease-renewal traffic against etcd. | `bool` | `true` | no |
| <a name="input_mode"></a> [mode](#input\_mode) | GitOps reconciliation mode. 'push' installs notification-controller and creates the webhook-token secret. 'pull' omits both. | `string` | `"push"` | no |
| <a name="input_operator_image_repository"></a> [operator\_image\_repository](#input\_operator\_image\_repository) | Image repository for the flux-operator, without a tag (e.g. registry.example.com/controlplaneio-fluxcd/flux-operator). | `string` | `"ghcr.io/controlplaneio-fluxcd/flux-operator"` | no |
| <a name="input_operator_image_tag"></a> [operator\_image\_tag](#input\_operator\_image\_tag) | Tag of the flux-operator image, with its digest. | `string` | `"v0.62.1@sha256:1d09a3f96524d0895fb11e8072d84a3dd029cecdec0f869efa371be6b001469c"` | no |
| <a name="input_ready_gate_image"></a> [ready\_gate\_image](#input\_ready\_gate\_image) | Image for the Job that waits for the FluxInstance to report Ready. It must provide kubectl and sh. | `string` | `"ghcr.io/windsorcli/utils:1.37.2-r1@sha256:fe4838c4687df97b318d83138801592e07fcaab9df091a883bb121045958b38e"` | no |
| <a name="input_replicas"></a> [replicas](#input\_replicas) | Replica count for kustomize-controller, helm-controller, and notification-controller. source-controller stays pinned to 1 regardless of this value. Values above 1 require leader\_election. | `number` | `1` | no |
| <a name="input_ssh_known_hosts"></a> [ssh\_known\_hosts](#input\_ssh\_known\_hosts) | The known hosts to use for SSH authentication | `string` | `""` | no |
| <a name="input_ssh_private_key"></a> [ssh\_private\_key](#input\_ssh\_private\_key) | The private key to use for SSH authentication | `string` | `""` | no |
| <a name="input_ssh_public_key"></a> [ssh\_public\_key](#input\_ssh\_public\_key) | The public key to use for SSH authentication | `string` | `""` | no |
| <a name="input_webhook_token"></a> [webhook\_token](#input\_webhook\_token) | Token used by the Flux notification-controller Receiver. When null or empty, a random 48-char token is generated and persisted in state. | `string` | `null` | no |

## Outputs

No outputs.
<!-- END_TF_DOCS -->