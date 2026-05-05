## Reference

<!-- BEGIN_TF_DOCS -->
### Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >=1.7.3 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | 3.1.1 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | 3.1.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | 3.8.1 |

### Providers

| Name | Version |
|------|---------|
| <a name="provider_helm"></a> [helm](#provider\_helm) | 3.1.1 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | 3.1.0 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.8.1 |

### Modules

No modules.

### Resources

| Name | Type |
|------|------|
| [helm_release.flux_system](https://registry.terraform.io/providers/hashicorp/helm/3.1.1/docs/resources/release) | resource |
| [kubernetes_namespace_v1.flux_system](https://registry.terraform.io/providers/hashicorp/kubernetes/3.1.0/docs/resources/namespace_v1) | resource |
| [kubernetes_secret_v1.git_auth](https://registry.terraform.io/providers/hashicorp/kubernetes/3.1.0/docs/resources/secret_v1) | resource |
| [kubernetes_secret_v1.webhook_token](https://registry.terraform.io/providers/hashicorp/kubernetes/3.1.0/docs/resources/secret_v1) | resource |
| [random_password.webhook_token](https://registry.terraform.io/providers/hashicorp/random/3.8.1/docs/resources/password) | resource |

### Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_concurrency"></a> [concurrency](#input\_concurrency) | Number of concurrent reconciliations per Flux controller | `number` | `2` | no |
| <a name="input_flux_helm_version"></a> [flux\_helm\_version](#input\_flux\_helm\_version) | The version of Flux Helm chart to install | `string` | `"2.18.3"` | no |
| <a name="input_flux_namespace"></a> [flux\_namespace](#input\_flux\_namespace) | The namespace in which Flux will be installed | `string` | `"system-gitops"` | no |
| <a name="input_flux_version"></a> [flux\_version](#input\_flux\_version) | The version of Flux to install | `string` | `"2.8.6"` | no |
| <a name="input_git_auth_secret"></a> [git\_auth\_secret](#input\_git\_auth\_secret) | The name of the secret to store the git authentication details | `string` | `"flux-system"` | no |
| <a name="input_git_password"></a> [git\_password](#input\_git\_password) | The git password or PAT used to authenticte with the git provider | `string` | `""` | no |
| <a name="input_git_username"></a> [git\_username](#input\_git\_username) | The git user to use to authenticte with the git provider | `string` | `"git"` | no |
| <a name="input_image_automation"></a> [image\_automation](#input\_image\_automation) | Enable the Flux image-automation-controller. Only needed for automated image tag updates committed back to Git. | `bool` | `false` | no |
| <a name="input_image_reflection"></a> [image\_reflection](#input\_image\_reflection) | Enable the Flux image-reflector-controller. Only needed alongside image-automation-controller to scan image registries. | `bool` | `false` | no |
| <a name="input_leader_election"></a> [leader\_election](#input\_leader\_election) | Enable leader election on Flux controllers. Disable on single-node clusters to eliminate lease-renewal traffic against etcd. | `bool` | `true` | no |
| <a name="input_mode"></a> [mode](#input\_mode) | GitOps reconciliation mode. 'push' installs notification-controller and creates the webhook-token secret. 'pull' omits both. | `string` | `"push"` | no |
| <a name="input_ssh_known_hosts"></a> [ssh\_known\_hosts](#input\_ssh\_known\_hosts) | The known hosts to use for SSH authentication | `string` | `""` | no |
| <a name="input_ssh_private_key"></a> [ssh\_private\_key](#input\_ssh\_private\_key) | The private key to use for SSH authentication | `string` | `""` | no |
| <a name="input_ssh_public_key"></a> [ssh\_public\_key](#input\_ssh\_public\_key) | The public key to use for SSH authentication | `string` | `""` | no |
| <a name="input_webhook_token"></a> [webhook\_token](#input\_webhook\_token) | Token used by the Flux notification-controller Receiver. When null or empty, a random 48-char token is generated and persisted in state. | `string` | `null` | no |

### Outputs

No outputs.
<!-- END_TF_DOCS -->