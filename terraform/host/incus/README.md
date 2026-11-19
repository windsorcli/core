---
title: Incus host
description: Shared ZFS storage pool on every member of one Incus cluster, kept on destroy.
---

A ZFS storage pool on every member of one Incus cluster. The module reads the
members from the cluster, defines the pool on each member with the ZFS dataset
`<storage_pool_name>/incus` as its source, then creates it once for the cluster.
On a server that is not clustered, it creates the pool directly.

## Prerequisites

The module needs a formed cluster and a client remote that trusts the
operator's certificate. On IncusOS, the dataset is the `incus` volume of the
IncusOS pool with the same name: create it on each member with
`incus admin os system storage create-volume`, with `use` set to `incus`,
before the first apply.

## Destroy

The pool has `prevent_destroy`. Deleting the pool deletes every volume on it,
so that step stays manual: `incus storage delete <pool>`.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.12.2 |
| <a name="requirement_incus"></a> [incus](#requirement\_incus) | 1.2.1 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_incus"></a> [incus](#provider\_incus) | 1.2.1 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [incus_storage_pool.main](https://registry.terraform.io/providers/lxc/incus/1.2.1/docs/resources/storage_pool) | resource |
| [incus_storage_pool.member](https://registry.terraform.io/providers/lxc/incus/1.2.1/docs/resources/storage_pool) | resource |
| [incus_cluster.main](https://registry.terraform.io/providers/lxc/incus/1.2.1/docs/data-sources/cluster) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_remote"></a> [remote](#input\_remote) | Incus client remote of the cluster. Null uses the client's default remote. | `string` | `null` | no |
| <a name="input_storage_pool_name"></a> [storage\_pool\_name](#input\_storage\_pool\_name) | Name of the shared storage pool. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_storage_pool"></a> [storage\_pool](#output\_storage\_pool) | Name of the shared storage pool. |
<!-- END_TF_DOCS -->
