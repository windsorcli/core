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

requires:             # optional — fail composition with a readable message
- when: <expression>  #   optional guard; omit to always require
  paths:
    - <config.path>   #   these must be set/non-empty when the guard holds
  message: <plain-English reason the field is needed>

config:
- name: <config-key>
  value: <static-or-expression>
  requires:           # requires also works on a config entry; it inherits
  - paths:            #   the entry's own `when:`, so no need to repeat it
      - <config.path>
    message: <reason>

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

## Comment and layout standard

Every facet follows this standard. The comment rules in the repo `CLAUDE.md`
also apply.

### Comments

Read top to bottom, a facet's comments describe what it builds. Where a value
or condition changes the result, the comment says what you get in each case.
A reader holding a set of values in their head can follow along and see which
entries apply.

Beyond that, comment only what the YAML doesn't make obvious: why a default is
what it is, an upstream bug, or an ordering constraint. Write each comment as a
technical statement, in the terse register of a maintainer's note. Use precise
verbs such as requires, provisions and resolves to, in place of needs, gets or
wants. Lead with the thing being described and trail the condition: "Core
provisions the S3 state bucket unless specified by terraform.backend." A
fragment is fine where it reads naturally: "Nodes in a single AZ unless
topology is ha."

- A comment MUST be one line. Several lines MAY sit above one entry when each
  line states a separate fact.
- A multi-line expression, or one built from map, filter, reduce or nested
  ternaries, MUST have a one-line comment above it that says what it computes.
  A comment above the entry covers it when the entry holds only that expression.
- A comment MUST sit directly above the line it explains. A comment about one
  input goes above that input, not above the whole entry.
- A comment MUST NOT repeat the YAML, a `when:` expression, or a `requires`
  message. A comment that only names what the key below it holds is a repeat.
- A comment MUST name the exact field, value or resource it refers to. Vague
  references such as "selected in config", "once applied", "steps such as" or
  "used by X only" MUST be replaced with the name or deleted.
- A comment on a module input MUST describe what this line computes. It MUST
  NOT describe what the module does with the value.
- A comment MUST NOT summarize what a later section states. A facet-level
  `when:` takes no comment.
- A comment MUST NOT use em-dashes or "not X, but Y" contrasts.
- A comment MUST NOT say "always" or "never" unless it is literally true.
- A comment MUST describe this facet. It MUST NOT explain how the CLI composes,
  merges, orders or destroys facets in general.
- If an old comment carries a fact the YAML doesn't show, shorten it. Don't
  delete it.

```yaml
# Terraform
# =============================================================================
terraform:
  - name: cluster
    inputs:
      # Nodes in a single AZ unless topology is ha.
      node_subnet_ids: "${topology == 'ha' ? subnets : [subnets[0]]}"

  # Public Route53 zone, created when dns.public_domain is set. A separate stack
  # keeps the zone and its NS delegation independent of the cluster.
  - name: dns-zone
```

### Section headers

Each top-level block after `when:` MUST start with a section header: the
block name, then a line of 77 `=` characters. Lines that apply to the whole
block MAY follow the rule, directly above the key. No other comment uses
`=` or `-` rule lines.

```yaml
# Flux
# =============================================================================
# EKS only from here. Talos on AWS uses just the base flux systems.
flux:
```

### Block order

Top-level blocks MUST appear in this order. Leave out the blocks a facet
doesn't use.

`kind`, `apiVersion`, `metadata`, `ordinal`, `when`, `requires`, `config`,
`substitutions`, `backend`, `crds`, `terraform`, `flux`, `kustomize`,
`messages`

One blank line separates top-level blocks. Nothing goes above `kind`.
Entries inside a list MUST keep their order, since the composer reads them
in order.

### Machine annotations

Tools read these comments. They MUST stay exactly as written, in place.

- `# artifact:` tags, read by Renovate and the CLI artifact scanner. A tag
  applies to the next line that isn't blank or a comment.
- `# renovate:` annotations. Renovate reads the line directly below, so
  nothing can go between them.
- `# BEGIN talos_images` and `# END talos_images` in `config-talos.yaml`,
  which `task talos:images` rewrites between.

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
platform              top-level schema field (canonical platform selector)
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

**Enum check with default:**
```yaml
when: (gitops.mode ?? 'push') == 'push'
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

- `policy-install`, `policy-resources` (compiled from a `flux:` system entry)
- `pki-install`, `pki-resources` (compiled from a `flux:` system entry)
- `telemetry-install`, `telemetry-resources` (compiled from a `flux:` system entry)
- `gateway-install`, `gateway-resources` (compiled from a `flux:` system entry; canonical traffic entrypoint)
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
