---
name: facet-author
description: Author Windsor facets, config expressions, and schema additions. Knows facet YAML structure, expression syntax, the layering system (provider > option > addon), and how to write matching test cases.
---

# Facet Author

## Apply when
- Creating or modifying a facet in `contexts/_template/facets/`
- Adding config expressions or `when:` conditions
- Adding new fields to `contexts/_template/schema.yaml`
- Writing test cases for a new or changed facet

## Facet file structure

Location: `contexts/_template/facets/<type>-<name>.yaml`

Naming convention:
- `provider-<name>.yaml` — adds infrastructure for a specific cloud/platform
- `option-<name>.yaml` — a user-toggleable feature (gateway, dev mode, workstation)
- `addon-<name>.yaml` — an optional addon (private-dns, observability, object-store)
- `config-<name>.yaml` — low-level configuration helpers (talos config)

```yaml
kind: Facet
apiVersion: blueprints.windsorcli.dev/v1alpha1
metadata:
  name: <name>
  description: "One-line description of what this facet does"

when: <expression>    # optional top-level guard — omit if always applies

config:
- name: <config-key>
  value: <static-or-expression>

terraform: []         # terraform stacks this facet manages (omit if none)

kustomize:
- name: <kustomization-name>
  path: <path-relative-to-kustomize/>
  when: <expression>               # optional per-entry guard
  dependsOn:
    - <other-kustomization-name>
  components:
    - <component-path>
    - "${<expression> ? 'component/path' : ''}"  # conditional component
  substitutions:
    key: ${<expression>}
  timeout: 10m
  interval: 5m
  destroyOnly: false               # true for cleanup kustomizations only
```

## Expression syntax

Windsor uses a CEL-like expression language in `${...}` blocks and `when:` fields.

### Operators
```
??        null-coalescing: left ?? right  →  left if not null/undefined, else right
==        equality
!=        inequality
&&        logical AND
||        logical OR
!         logical NOT
? :       ternary: condition ? then : else
```

### Accessing values
```
provider              top-level schema field
platform              alias for provider (platform ?? provider is the canonical pattern)
gateway.enabled       nested field access
addons.private_dns.enabled
workstation.runtime
```

### Common patterns

**Null-coalescing default:**
```yaml
value: "${dns.domain ?? 'test'}"
```

**Conditional component:**
```yaml
- "${addons.private_dns.enabled == true ? 'nginx/coredns' : ''}"
```
Empty string `''` means "no component" — Windsor strips empty entries.

**Nested condition with fallback:**
```yaml
- "${(workstation.runtime ?? (platform == 'docker' ? 'docker-desktop' : '')) == 'docker-desktop' ? 'nginx/nodeport' : 'nginx/loadbalancer'}"
```

**Boolean check with default:**
```yaml
when: (gitops.webhook.enabled ?? true) == true
```

**Boolean negation for opt-out:**
```yaml
value: ${addons.private_ca.enabled != false}   # true unless explicitly set false
```

## The layering system

Facets are composed in dependency order. Later facets can override or extend earlier ones.

```
provider-base     → shared base for all providers (policy, PKI, telemetry, gitops)
provider-<name>   → cloud-specific additions (AWS, Azure, Incus, Metal, Docker)
option-dev        → dev mode enhancements (selfsigned certs, grafana dev credentials)
option-workstation → workstation services (DNS, registries, git livereload)
option-gateway    → cluster ingress (nginx or envoy, canonical "gateway-resources" name)
addon-private-ca  → private CA and trust-manager
addon-private-dns → self-hosted CoreDNS
addon-observability → Grafana, Elasticsearch/Kibana
addon-object-store → MinIO
addon-database    → CloudNativePG
```

**Rules:**
- A facet at a higher layer can depend on (`dependsOn`) kustomizations from a lower layer
- A facet must not assume another optional facet is applied — use `?? default` for safety
- Avoid cross-facet `config` overrides unless you are explicitly extending a base value

## Kustomization naming

Kustomization `name` values are the stable identifiers that `dependsOn` and facet tests reference. Use descriptive kebab-case names:

- `policy-base`, `policy-resources`
- `pki-base`, `pki-resources`
- `telemetry-base`, `telemetry-resources`
- `gateway-base`, `gateway-resources` (canonical traffic entrypoint)
- `observability`, `observability-kibana`
- `addon-object-store`

**Canonical names matter.** Dependent facets use `dependsOn: [gateway-resources]` regardless of which driver is active. Both nginx and envoy modes must emit a kustomization named `gateway-resources`.

## Schema additions

When a facet introduces a new config key, add it to `contexts/_template/schema.yaml`:

```yaml
properties:
  my_feature:
    type: object
    properties:
      enabled:
        type: boolean
        default: false
        description: Enable my feature
      driver:
        type: string
        enum:
          - option-a
          - option-b
        default: option-a
        description: Driver for my feature
    additionalProperties: false
```

Always set `additionalProperties: false` on new objects. Provide a `default` where the field is optional. Add a clear `description`.

## Config section

The `config` section sets computed/effective values that downstream expressions and kustomize substitutions use. Name config keys descriptively:

```yaml
config:
- name: gateway_effective
  value:
    enabled: ${gateway.enabled ?? ingress.enabled ?? true}
    driver: "${gateway.driver ?? 'nginx'}"
```

Use `_effective` suffix when the config key resolves aliases or applies defaults. Reference these derived keys in `when:` and component expressions.

## Writing a matching test file

Every new facet needs `contexts/_template/tests/<facet-name>.test.yaml`. See `windsor-test` skill for test file format and patterns. Minimum cases:

1. Feature enabled with standard config
2. Feature disabled (assert excluded)
3. Each conditional component (one case per branch)
4. Backward-compatibility alias if the facet has one

Run `task test:blueprint` to verify.

## Local development environment

Facet changes are tested against the local Windsor cluster. The environment is created with:

```bash
windsor up local --vm-driver <driver>
```

Available VM drivers and their capabilities:
- `colima` — standard local VM, suitable for most facet and kustomize work
- `colima-incus` — supports disk/volume creation (use when testing CSI, PVC, or storage-related resources)
- `docker-desktop` — uses Docker Desktop VM

The environment can be fully destroyed and recreated quickly:

```bash
windsor down --clean --skip-tf --skip-k8s
```

This is the fastest way to get a clean state when validating facet changes end-to-end.

### Live reload

The local cluster uses `git-livereload` — **saving a file is all that's needed to trigger Flux reconciliation.** There is no need to commit, push, or manually annotate kustomizations during local development. Changes are picked up automatically within seconds of saving.
