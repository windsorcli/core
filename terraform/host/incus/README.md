---
title: Incus host
description: Server-scoped objects of one Incus cluster that several contexts share, kept on destroy.
---

Server-scoped objects of one Incus cluster. The module creates a storage pool
and a `physical` network on every member in `members`, an `images`, `backups`,
and `logs` volume on each member for that member's daemon storage, projects,
and trusted client certificates.

## Members

A storage pool or network on an Incus cluster is defined on each member, then
created once for the cluster. `members` holds the values that differ per member:

- `storage_source` is the ZFS dataset on that member that backs the pool.
- `network_parent` is the bridge or interface on that member that backs the
  network.

Every cluster member MUST be in `members`, or the cluster-wide create fails.

When `network_parent` is a bridge, Incus attaches each instance NIC to it as a
bridged NIC, so many instances share the network. Incus runs no DHCP on a
`physical` network.

## Prerequisites

On IncusOS, these steps go through the IncusOS API before the first apply:

- Install each member and join it to the cluster.
- Create the dataset named in `storage_source` on each member with
  `incus admin os system storage create-volume`, with `use` set to `incus`.
- Add the `instances` role to the NIC on each member. The role creates the
  bridge that `network_parent` names.

A member installed with IncusOS defaults already has `images` and `backups`
volumes on `local` and the server keys that point at them. With
`daemon_storage_pool` set, unset `storage.images_volume` and
`storage.backups_volume` and delete those volumes on that member first, or the
volume create fails.

A certificate the cluster already trusts fails to create. Import it by
fingerprint, or leave it out of `certificates`.

## Destroy

The pool and network have `prevent_destroy`. Deleting the pool deletes every
volume on it, so that step stays manual: `incus storage delete <pool>`.

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
| [incus_certificate.main](https://registry.terraform.io/providers/lxc/incus/1.2.1/docs/resources/certificate) | resource |
| [incus_network.main](https://registry.terraform.io/providers/lxc/incus/1.2.1/docs/resources/network) | resource |
| [incus_network.member](https://registry.terraform.io/providers/lxc/incus/1.2.1/docs/resources/network) | resource |
| [incus_project.main](https://registry.terraform.io/providers/lxc/incus/1.2.1/docs/resources/project) | resource |
| [incus_server.member](https://registry.terraform.io/providers/lxc/incus/1.2.1/docs/resources/server) | resource |
| [incus_storage_pool.main](https://registry.terraform.io/providers/lxc/incus/1.2.1/docs/resources/storage_pool) | resource |
| [incus_storage_pool.member](https://registry.terraform.io/providers/lxc/incus/1.2.1/docs/resources/storage_pool) | resource |
| [incus_storage_volume.daemon](https://registry.terraform.io/providers/lxc/incus/1.2.1/docs/resources/storage_volume) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_certificates"></a> [certificates](#input\_certificates) | Trusted client certificates keyed by name. A certificate that lists projects is restricted to them. | <pre>map(object({<br/>    certificate = string<br/>    description = optional(string)<br/>    type        = optional(string, "client")<br/>    projects    = optional(list(string), [])<br/>  }))</pre> | `{}` | no |
| <a name="input_daemon_storage_pool"></a> [daemon\_storage\_pool](#input\_daemon\_storage\_pool) | Pool that holds each member's images, backups, and logs volumes. Null leaves the server config unmanaged. | `string` | `null` | no |
| <a name="input_members"></a> [members](#input\_members) | Cluster members keyed by member name, with each member's storage source and network parent. | <pre>map(object({<br/>    storage_source = string<br/>    network_parent = optional(string)<br/>  }))</pre> | n/a | yes |
| <a name="input_network_name"></a> [network\_name](#input\_network\_name) | Name of the shared physical network. Null creates no network. | `string` | `null` | no |
| <a name="input_projects"></a> [projects](#input\_projects) | Projects keyed by name. | <pre>map(object({<br/>    description = optional(string)<br/>    config      = optional(map(string), {})<br/>  }))</pre> | `{}` | no |
| <a name="input_remote"></a> [remote](#input\_remote) | Incus client remote of the cluster. Null uses the client's default remote. | `string` | `null` | no |
| <a name="input_storage_pool_driver"></a> [storage\_pool\_driver](#input\_storage\_pool\_driver) | Storage driver of the shared storage pool. | `string` | `"zfs"` | no |
| <a name="input_storage_pool_name"></a> [storage\_pool\_name](#input\_storage\_pool\_name) | Name of the shared storage pool. | `string` | `"default"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_network"></a> [network](#output\_network) | Name of the shared physical network, or null when the module creates none. |
| <a name="output_projects"></a> [projects](#output\_projects) | Names of the projects the module creates. |
| <a name="output_storage_pool"></a> [storage\_pool](#output\_storage\_pool) | Name of the shared storage pool. |
<!-- END_TF_DOCS -->
