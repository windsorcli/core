---
title: Incus host
description: Server-scoped objects of one Incus cluster that every context on it shares, created by one context and kept on destroy.
---

Server-scoped objects of one Incus cluster. The module creates the storage
pool and the LAN network on every member, points each member's image, backup,
and log storage at volumes it creates, and creates projects and trusted client
certificates. `compute/incus` in each context then places its VMs on that pool
and network.

The module is opt-in. Without `incus.host` the facet does not add it, and
`compute/incus` uses a pool and network that already exist.

## Values

```yaml
incus:
  remote: lab
  targets: [node1, node2]
  network: lan
  storage_pool: default
  host:
    members:
      node1:
        storage_source: nvme/incus
        network_parent: enp86s0
      node2:
        storage_source: nvme/incus
        network_parent: eno1
    daemon_storage_pool: local
    projects:
      home:
        description: home cluster
    certificates:
      ci:
        certificate: |
          -----BEGIN CERTIFICATE-----
          ...
          -----END CERTIFICATE-----
        projects: [home]
```

| Key | Effect |
|-----|--------|
| `incus.host.members` | One entry per cluster member, keyed by member name. Each member MUST be listed, or the cluster-wide create fails. |
| `members.<name>.storage_source` | ZFS dataset on that member that backs `incus.storage_pool`. |
| `members.<name>.network_parent` | Bridge or interface on that member that backs `incus.network`. Required when `incus.network` is set. |
| `incus.storage_pool` | Name of the pool the module creates. Default `default`. |
| `incus.network` | Name of the `physical` network the module creates. Unset creates no network. |
| `incus.host.daemon_storage_pool` | Pool for the `images`, `backups`, and `logs` volume on each member, set as `storage.images_volume`, `storage.backups_volume`, and `storage.logs_volume`. Unset leaves those keys alone. |
| `incus.host.projects` | Projects keyed by name. A new project holds its own images, profiles, and storage volumes. |
| `incus.host.certificates` | Trusted client certificates keyed by name. One that lists `projects` is restricted to them. |

## Prerequisites

The module needs a formed cluster and a client remote that trusts the
operator's certificate. On IncusOS, these steps go through the IncusOS API
before the first apply:

- Install each member and join it to the cluster.
- Create the ZFS dataset named in `storage_source` on each member, for example
  `incus admin os system storage create-volume` with `use` set to `incus`.
- Add the `instances` role to the NIC on each member. The role creates the
  unmanaged bridge that `network_parent` names.

A member installed with IncusOS defaults already has `images` and `backups`
volumes on `local` and the matching server keys. With `daemon_storage_pool`
set, unset those keys and delete the volumes on that member first, or the
volume create fails.

## Network

The network is `type=physical` with a per-member `parent`, because the
bridge name differs per member. When the parent is a bridge, Incus attaches
each instance NIC as `nictype=bridged` on it, so many VMs share the network.
Incus runs no DHCP on it, so `compute/incus` takes declared node addresses.

## Placement of objects

Objects that a project can hold belong to the context. Objects that only the
server holds, or that only an unrestricted client can create, belong here.

| Object | Layer | Reason |
|--------|-------|--------|
| Storage pool | Host | Pools are server-wide. A clustered pool cannot be imported, so one layer MUST create it. |
| Physical network | Host | `features.networks` in a project needs OVN, so a `physical` network lives in the `default` project. |
| Daemon storage keys and volumes | Host | `storage.*_volume` keys are member-scoped server config. |
| Project | Host | Only an unrestricted client can create a project. |
| Certificates | Host | Certificates are server-wide, and a restricted client cannot list or create them. |
| Profiles, images, volumes, instances | Context | A new project holds its own copies. |
| Network zones | Context | `features.networks.zones` isolates zones per project. |
| Network ACLs | None | ACLs apply to managed bridge and OVN networks, and the physical network is neither. |
| Cluster groups | None | `incus.targets` names members. |

A context's restricted certificate lives here with its project. A context
that ran with that certificate could not refresh or destroy either object.

The facet passes no project to `compute/incus`, which places VMs in the
`default` project.

The Talos image belongs to the context. With `features.images` on, each
project caches its own copy, so two contexts can pin different Talos versions,
and the copy goes with the project.

## Ownership

One context per Incus cluster sets `incus.host`, and that context owns the
objects in its state. Other contexts on the cluster set the same
`incus.remote`, `incus.network`, and `incus.storage_pool` and leave
`incus.host` unset. Apply the owning context first.

The facet sets `destroy: false` on the component, and the pool and network
have `prevent_destroy`, so `windsor destroy` and a stray `terraform destroy`
leave them in place. Deleting the pool deletes every volume on it, so that
step stays manual: `incus storage delete <pool>`.

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
