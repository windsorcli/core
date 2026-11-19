---
title: host
description: Host-level objects that several contexts share and that outlive any one context.
stack_name: Host
stack_backing: Incus · Proxmox VE
---

Host-level objects that `windsor destroy` leaves in place. Each module is
opt-in and runs with `destroy: false`. See [`host/incus`](incus) for the Incus
module and [`host/proxmox`](proxmox) for the Proxmox VE module.

<!-- BEGIN_TERRAFORM_MODULES -->

## Modules

- [incus](incus/) — Shared ZFS storage pool on every member of one Incus cluster, kept on destroy.
- [proxmox](proxmox/) — Opt-in image datastore for Proxmox VE, created by one context and kept on destroy.
<!-- END_TERRAFORM_MODULES -->
