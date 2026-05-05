## Reference

<!-- BEGIN_TF_DOCS -->
### Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >=1.8 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | ~> 4.71.0 |

### Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | 4.71.0 |

### Modules

No modules.

### Resources

| Name | Type |
|------|------|
| [azurerm_dns_zone.main](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/dns_zone) | resource |
| [azurerm_resource_group.dns](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group) | resource |
| [azurerm_resource_group.dns](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/resource_group) | data source |
| [azurerm_subscription.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/subscription) | data source |

### Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_context_id"></a> [context\_id](#input\_context\_id) | The windsor context id for this deployment. | `string` | `""` | no |
| <a name="input_domain_name"></a> [domain\_name](#input\_domain\_name) | The fully-qualified domain name for the public DNS zone (e.g. example.com). | `string` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | Azure region for the resource group. Azure DNS zones are global, but the RG itself has a region. | `string` | `"eastus"` | no |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Existing resource group to create the DNS zone in. Leave empty to provision a new RG named rg-dns-<context\_id>. | `string` | `""` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags applied to the zone and resource group. | `map(string)` | `{}` | no |

### Outputs

| Name | Description |
|------|-------------|
| <a name="output_name_servers"></a> [name\_servers](#output\_name\_servers) | Authoritative name servers for the zone. Configure these as NS records at your domain registrar so public DNS queries resolve through this zone. |
| <a name="output_resource_group_name"></a> [resource\_group\_name](#output\_resource\_group\_name) | The resource group the DNS zone lives in. Required by cert-manager (azureDNS solver) and external-dns (Azure provider). |
| <a name="output_subscription_id"></a> [subscription\_id](#output\_subscription\_id) | Subscription the zone lives in. Required by cert-manager (azureDNS solver) and external-dns (Azure provider). |
| <a name="output_tenant_id"></a> [tenant\_id](#output\_tenant\_id) | Tenant the zone lives in. Required by cert-manager (azureDNS solver) and external-dns (Azure provider) when authenticating via Workload Identity. |
| <a name="output_zone_id"></a> [zone\_id](#output\_zone\_id) | The full Azure resource ID of the DNS zone. |
| <a name="output_zone_name"></a> [zone\_name](#output\_zone\_name) | The fully-qualified domain name of the DNS zone. |
<!-- END_TF_DOCS -->