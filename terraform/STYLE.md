# Windsor Core Code Style Guide

## Best Practices

1. Use consistent, descriptive resource names with underscores (_), never hyphens (-).
2. Minimize submodules; only use them for resource reuse within a parent module. Never use third-party modules.
3. Keep modules focused and small; avoid unnecessary abstraction.
4. Validate relevant user inputs with type constraints and validation blocks.
5. Use mock providers in tests to isolate module logic.
6. Group resources by logical function and use section headers for clarity.
7. Document all public variables and outputs clearly.
8. Prefer local variables for complex expressions or repeated logic.
9. Keep resource dependencies explicit using `depends_on` only when necessary.
10. Avoid inline comments inside resource blocks; use block-level comments for documentation.
11. Avoid using `terraform_remote_state` data sources; prefer explicit variable passing between modules.
12. Avoid using data sources to implicitly reference resources; prefer explicit resource references or variable passing.
13. Parameterize module inputs as variables rather than hardcoding values or using data sources.
14. Mark sensitive values (credentials, keys, tokens) with `sensitive: true` in both input and output variables.

## Folder Structure

- The top-level folders represent generic system-oriented layers (e.g., `backend`, `network`, `cluster`, `gitops`).
- The second-level folders represent different implementations of that layer.
- Implementations may be prefixed by vendor (e.g., `azure-`, `aws-`).
- This structure allows for clear separation of concerns and easy addition of new implementations.

Example:
```
/
├── backend/
│   ├── azurerm/
│   └── s3/
├── network/
│   ├── azure-vnet/
│   └── aws-vpc/
├── cluster/
│   ├── talos/
│   └── aws-eks/
└── gitops/
    └── flux/
```

### Resource Naming
- Always use underscores (_) for resource names, never hyphens (-).
- Resource names should be descriptive and consistent across the codebase.
- Avoid redundancy; if the resource type is a "network," do not include "_network" in the name.
- Example: `resource "azurerm_virtual_network" "core" { ... }` instead of `resource "azurerm_virtual_network" "core_network" { ... }`.

### Submodules
- Submodules should be minimized.
- Only introduce a submodule when a specific resource or resource group is reused in several places within its parent module.
- Submodules should not be used for simple grouping or organization.
- Never use third-party modules; all submodules must be defined within this repository.
- Example use case: a submodule for a repeated storage resource used by multiple components in the parent module.

## Module Structure

A typical Terraform module should contain:
1. Main module file (`main.tf`)
2. Variables file (`variables.tf`)
3. Outputs file (`outputs.tf`)
4. Test file (`test.tftest.hcl`)
5. Documentation file (`README.md`)

## File Organization

### Main Module File
1. Provider configuration
2. Resource definitions grouped by logical function
3. Data source lookups
4. Local variables
5. Section headers using `# =============================================================================`

### Variables File
1. Input variable definitions with strict validation
2. Comprehensive descriptions
3. Sensible defaults where appropriate
4. Type constraints
5. Validation rules using regex where applicable

Example:
```hcl
variable "cluster_name" {
  description = "The name of the cluster."
  type        = string
  default     = "talos"
  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "The cluster name must not be empty."
  }
}
```

### Test File
1. Mock provider configuration
2. Test variables with realistic defaults
3. Test cases organized by configuration scenario
4. Clear test descriptions
5. Comprehensive assertions

Example test structure:
```hcl
mock_provider "provider" {}

run "scenario_name" {
  command = plan

  variables {
    # Test variables with realistic defaults
  }

  assert {
    condition     = resource.attribute == expected_value
    error_message = "Clear error message"
  }
}
```

## Documentation Style

### Module Headers
Every module MUST begin with a header in the following format:
```hcl
# The [ModuleName] is a [brief description]
# It provides [detailed explanation]
# [role in infrastructure]
# [key features/capabilities]
```

### Section Headers
Section headers MUST follow this exact format:
```hcl
# =============================================================================
# [SECTION NAME]
# =============================================================================
```

File Organization:
1. `outputs.tf` - Contains all module outputs
2. `variables.tf` - Contains all input variables
3. `main.tf` - Contains resources organized by logical grouping

Section names in `main.tf` should be organized by logical resource grouping. Common groupings include:
1. Provider Configuration
2. Network Resources
3. Compute Resources
4. Storage Resources
5. Security Resources

Local variables should be defined within their relevant resource sections, not in a separate section.

Example:
```hcl
# =============================================================================
# Provider Configuration
# =============================================================================

provider "azurerm" {
  features {}
}

# =============================================================================
# Network Resources
# =============================================================================

locals {
  vnet_name = "${var.prefix}-vnet"
}

resource "azurerm_virtual_network" "this" {
  name = local.vnet_name
  # ...
}

# =============================================================================
# Compute Resources
# =============================================================================

locals {
  vm_name = "${var.prefix}-vm"
}

resource "azurerm_virtual_machine" "this" {
  name = local.vm_name
  # ...
}
```

### Resource Documentation
- Brief description at the top of each resource
- No inline comments within resource blocks
- Focus on what and why, not how

Example:
```hcl
# The [ResourceName] is a [brief description]
# It provides [detailed explanation]
resource "resource_type" "resource_name" {
  # Configuration
}
```

## Testing Patterns

### Test Structure
Tests should follow a clear scenario-based structure:

```hcl
run "Scenario" {
  command = plan

  # Given [context]
  variables {
    # Test variables with realistic defaults
  }

  # When [action]
  # (implicit in the plan/apply command)

  # Then [result]
  assert {
    condition     = resource.attribute == expected_value
    error_message = "Expected X, got Y"
  }
}
```

### Module Test Pattern

Each module should be tested with the following scenarios, as applicable:

1. **Minimal Configuration**
   - Only required variables set.
   - Asserts that default resources are created with expected default values.
   - Example: Verifies that required outputs/files/resources are generated.

2. **Full Configuration**
   - All optional variables set.
   - Asserts that all features and customizations are reflected in the outputs/resources.
   - Example: Verifies that all optional resources are created and attributes match inputs.

3. **Feature/Conditional Configuration**
   - Enables/disables specific features or toggles.
   - Asserts that resources are created or omitted as expected.
   - Example: Verifies that enabling a feature creates a resource, disabling omits it.

4. **Module-Specific/Edge Cases**
   - Tests unique logic, edge cases, or error conditions.
   - Example: Verifies that no files are created when a required path is empty, or that invalid input is handled with a clear error.

5. **Combined Negative Tests**
   - Test multiple validation rules simultaneously in a single test case.
   - Use `expect_failures` to verify all validation rules are enforced.
   - Include invalid values for all variables with validation rules.
   - Example: Testing all input validations (type constraints, format requirements, YAML validation) in one test.

**Assertions should:**
- Check for presence/absence of resources, files, or outputs.
- Validate that resource attributes match input variables.
- Confirm correct handling of edge cases and error conditions.
- Use `expect_failures` for negative tests to verify validation rules.

**Tests should not:**
- Assert on implementation details not exposed via outputs or resources.
- Create separate negative tests for each validation rule when they can be combined.

### Test Organization
1. Group related tests together by configuration scenario
2. Use descriptive scenario names
3. Test both success and failure cases
4. Validate all important attributes
5. Include edge cases
6. Use mock providers for external dependencies 
