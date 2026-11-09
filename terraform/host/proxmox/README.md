---
title: Proxmox host
description: Opt-in image datastore for Proxmox VE, created by one context and kept on destroy.
---

Host-level Proxmox VE objects. The first object is a directory storage for
downloaded Talos images. Other contexts on the host can use it, and
`windsor destroy` leaves it in place.

The module is opt-in. Without `proxmox.manage_image_datastore: true` the
facet does not add it, and `compute/proxmox` uses an existing datastore.

## Ownership

Any one context can create the storage. That context owns it in its own
state. Other contexts do not manage it: they set `proxmox.image_datastore` to
the same id and leave `manage_image_datastore` off. The plan-time check in
`compute/proxmox` fails when the storage is missing or lacks the `import`
content type, so apply the creating context first.

The facet sets `destroy: false` on the component, and the storage has
`prevent_destroy`, so `windsor destroy` and a stray `terraform destroy` leave
it in place. Destroy clears the state of the creating context. If that context
runs `windsor apply` again, the create fails because the storage exists. Turn
`manage_image_datastore` off in that context and reference the storage.

Deleting the storage is a manual step: `pvesm remove <id>`, and `rm -r` on the
directory if the files are no longer needed.

## Permissions

| Path | Privileges |
|------|------------|
| `/storage` (propagate) | `Datastore.Allocate`, to create the storage |

`/storage/<id>` does not exist before the first apply, so the create privilege
goes on `/storage`. After the storage exists, the user needs the privileges in
the `compute/proxmox` README on `/storage/<id>`.

```bash
pveum role add WindsorStorageAdmin --privs "Datastore.Allocate"
pveum acl modify /storage --users windsor@pve --roles WindsorStorageAdmin
```

## Scope

One host or one cluster per context. `nodes` lists the nodes where the storage
is available, and the first node is the one Terraform reads. The module does
not install Proxmox or form a cluster.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.12.2 |
| <a name="requirement_proxmox"></a> [proxmox](#requirement\_proxmox) | ~> 0.116 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_proxmox"></a> [proxmox](#provider\_proxmox) | ~> 0.116 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [proxmox_storage_directory.images](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/storage_directory) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_image_datastore_id"></a> [image\_datastore\_id](#input\_image\_datastore\_id) | Id of the directory storage that receives downloaded images. | `string` | n/a | yes |
| <a name="input_image_datastore_path"></a> [image\_datastore\_path](#input\_image\_datastore\_path) | Absolute directory path on the node that backs the storage. | `string` | n/a | yes |
| <a name="input_nodes"></a> [nodes](#input\_nodes) | Proxmox VE nodes where the image datastore is available. | `list(string)` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_image_datastore_id"></a> [image\_datastore\_id](#output\_image\_datastore\_id) | Id of the image datastore. |
<!-- END_TF_DOCS -->