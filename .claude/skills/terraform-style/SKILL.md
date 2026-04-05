---
name: terraform-style
description: Enforce Windsor Core Terraform module structure, naming, and style conventions. Use when creating or editing any Terraform file.
---

# Windsor Terraform Style

## Apply when
- Creating or editing any `*.tf` or `*.tftest.hcl` file.
- Adding a new Terraform module.
- Reviewing module structure or documentation.

## Module structure

Every module requires exactly these files:
1. `main.tf`
2. `variables.tf`
3. `outputs.tf`
4. `test.tftest.hcl`
5. `README.md`

Folder layout: `terraform/<layer>/<implementation>` (e.g. `terraform/gitops/flux`, `terraform/cluster/talos`). Implementations may be vendor-prefixed (e.g. `aws-eks`).

## File organization

`main.tf` sections in order, using this exact header format:

```hcl
# =============================================================================
# [SECTION NAME]
# =============================================================================
```

Common sections: `Provider Configuration`, then logical resource groups (e.g. `Network Resources`, `Compute Resources`). Define locals within their relevant section, not in a separate block.

## Naming

- Use underscores only in resource names; never hyphens.
- Avoid redundancy: `resource "azurerm_virtual_network" "core"` not `"core_network"`.

## Variables and outputs

- Type-constrain all variables; add `validation` blocks for user-facing inputs.
- Mark credentials, tokens, and keys `sensitive = true` on both variables and outputs.
- Write clear, concise descriptions: what it is, not why it exists.

## Resource documentation

```hcl
# The [Resource] is a [brief description].
# It provides [explanation].
resource "type" "name" { ... }
```

No inline comments inside resource blocks.

## Dependencies and abstractions

- Prefer explicit variable passing; avoid `terraform_remote_state`.
- Avoid data sources for cross-resource wiring when explicit references work.
- Use `depends_on` only for non-inferable dependencies.
- No submodules unless a resource group is reused within the same parent module.
- No third-party modules.
