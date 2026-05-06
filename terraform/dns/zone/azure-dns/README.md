---
title: dns/zone/azure-dns
description: Provisions a public Azure DNS zone (and optionally its resource group) for cert-manager ACME and external-dns.
---

# dns/zone/azure-dns

Creates a public Azure DNS zone for a domain, plus (when no
`resource_group_name` is supplied) a dedicated resource group named
`rg-dns-<context_id>` to hold it. Kept independent of any
network/cluster module so a domain can be provisioned standalone —
useful for zone-only deployments and for cases where DNS infra has a
different lifecycle than compute.

The zone is consumed by:

- **cert-manager (azureDNS ACME solver)** — DNS-01 challenges for Let's Encrypt certificates issued via the `public` ClusterIssuer.
- **external-dns (Azure provider)** — automatic publication of Gateway / Service hostnames as DNS records.

After apply, point your domain registrar at the `name_servers`
output so public DNS queries resolve through this zone. The
`zone_id`, `resource_group_name`, `subscription_id`, and `tenant_id`
outputs feed [`cluster/azure-aks`](../../../cluster/azure-aks/)'s
cert-manager and external-dns Workload Identity wiring.

The zone owns its own resource group by default so the cluster's
lifecycle doesn't drag the zone (and the registrar's NS delegation
effort) with it on `windsor destroy`. To pin the zone into an
existing RG instead, set `resource_group_name`.

## Wiring

Wired by [platform-azure.yaml](../../../../contexts/_template/facets/platform-azure.yaml). The facet only emits this entry when the operator sets `dns.public_domain`.

```yaml
terraform:
  - name: dns-zone
    path: dns/zone/azure-dns
    when: "(dns.public_domain ?? '') != ''"
    inputs:
      domain_name: <dns.public_domain>
```

How those flow from `values.yaml`:

- `domain_name` — `dns.public_domain`. Required; the zone is `domain_name`-named.
- `location` — defaults to `eastus`. Azure DNS zones are global; the location only applies to the resource group when this module creates one. Override via tfvars if you want the RG colocated with the rest of your stack.

## See also

- [`cluster/azure-aks`](../../../cluster/azure-aks/) — consumes `zone_id`, `resource_group_name`, `subscription_id`, and `tenant_id` to wire up cert-manager and external-dns Workload Identity.
- [`dns/zone/route53`](../route53/) — sister module for AWS.
- [platform-azure.yaml](../../../../contexts/_template/facets/platform-azure.yaml) — facet wiring.

## Reference

The full module interface — every input, output, and resource — is
listed below. Override any input from your context by adding a tfvars
file at `contexts/<context>/terraform/dns-zone.tfvars`.

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