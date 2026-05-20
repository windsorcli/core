---
title: backend
description: Picks the cloud-native Terraform state backend (S3 or Azure Storage) the rest of the platform stack writes its state to.
---

# backend

Bootstraps the Terraform remote-state backend the rest of the
platform stack writes its state to. Two sibling modules implement
the same role on different clouds; exactly one runs per
`windsor apply`, selected by the active platform facet.

| Module | Platform | Storage | Locking |
|---|---|---|---|
| [`s3`](s3/) | `platform: aws` | S3 bucket + customer-managed KMS key | S3-native (`use_lockfile = true`) |
| [`azurerm`](azurerm/) | `platform: azure` | Azure storage account + private blob container | Native blob lease |

Both modules:

- Run first on their platform — every other module on that platform declares `dependsOn: backend` so the storage exists before any state writes.
- Generate a `backend.tfvars` snippet into the active context (`<context_path>/backend.tfvars`) so subsequent modules pick up the right backend config.
- Provision their own KMS / encryption story (mandatory on AWS, optional CMK on Azure).
- Use cloud-native locking — neither needs an external lock table (no DynamoDB, no separate Cosmos / table store).

Contexts that aren't on a supported cloud (workstation runtimes,
bare metal) don't run a module from this category — the Windsor CLI
handles state-backend wiring for them directly.

## Wiring

Both variants are wired by their platform facets with no explicit
inputs; `context_path` and `context_id` are auto-injected by the
Windsor CLI based on the active context.

```yaml
terraform:
  - name: backend
    path: backend/s3        # or backend/azurerm
    # no inputs
```

The modules' other variables (bucket / account names, region,
KMS / CMK toggles, IAM-role / IP-range allowlists) keep their
module defaults. Override per-context via tfvars at
`contexts/<context>/terraform/backend.tfvars`.

## See also

- [backend/s3](s3/) — AWS state backend.
- [backend/azurerm](azurerm/) — Azure state backend.
- [platform-aws.yaml](../../contexts/_template/facets/platform-aws.yaml) / [platform-azure.yaml](../../contexts/_template/facets/platform-azure.yaml) — facet wiring.
