---
title: host
description: Host-level objects that several contexts share and that outlive any one context.
stack_name: Host
stack_backing: Proxmox VE
---

Host-level objects that `windsor destroy` leaves in place. Each module is
opt-in and runs with `destroy: false`. See [`host/proxmox`](proxmox) for the
Proxmox VE module.

<!-- BEGIN_TERRAFORM_MODULES -->

## Modules

- [proxmox](proxmox/) — Opt-in image datastore for Proxmox VE, created by one context and kept on destroy.
<!-- END_TERRAFORM_MODULES -->
