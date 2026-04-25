# AWS + Windsor 2.0 Roadmap

Target: bring AWS to GA parity with metal/azure, and land the schema changes
that should ship *before* 2.0 so we aren't schema-breaking post-GA.

## Headline gap

The AWS facet is a thin wrapper. [platform-aws.yaml](../contexts/_template/facets/platform-aws.yaml)
passes `cidr_block` and `domain_name` into Terraform and nothing else —
topology, node config, storage driver, gateway, policies, and the terraform
backend all exist in the schema but never reach AWS. Metal/Azure are 2–3
phases ahead on schema wiring; AWS also ships without the in-cluster
controllers needed to actually run production workloads (no LB controller,
External-DNS deploy, cert-manager, EFS, Karpenter).

---

## Phase 1 — Pools, topology, and node schema wiring

The foundation. Everything else compounds on top of correct node provisioning.

### Pool model (replaces `workers` on elastic providers)

Introduce `cluster.pools` as the primary node-provisioning abstraction for
elastic providers (`aws`, `azure`, `gcp`, `omni`). Metal/docker/incus keep
`cluster.workers` (static node list); Omni MachineClass + MachineSet is the
metal implementation of pools.

```yaml
cluster:
  pools:
    system:   { class: system,  count: 2,       lifecycle: on-demand }
    general:  { class: general, min: 3, max: 20 }
    batch:    { class: compute, min: 0, max: 50, lifecycle: spot }
    gpu:      { class: gpu,     min: 0, max: 4,  gpu: { kind: nvidia-l4 } }
```

**Three-tier shape, `class` is required:**

```yaml
class: compute                              # required, portable
requirements:                               # optional, mostly portable
  arch: arm64
  cpu_min: 4
  capacity_type: spot
instance_types: [m6i.large, m6a.large]      # escape hatch, provider-locked
```

Follows the pattern Karpenter NodePools, EKS Blueprints, Cluster API, and
Omni MachineClasses converged on. Pinning to a single instance type is a
known anti-pattern (capacity shortages take the pool down), so lead with
`class` + `requirements`; keep `instance_types` as a last resort for
GPU/regulatory workloads.

**Well-known classes** (portable across providers):
`system`, `general`, `compute`, `memory`, `storage`, `gpu`, `arm64`.

Each class maps per-provider to an instance family plus default
taints/labels so workloads target pools uniformly across clouds:

- `windsor.io/pool=<name>`
- `windsor.io/pool-class=<class>`

**`system` pool behavior:** auto-taint with `CriticalAddonsOnly=true:NoSchedule`
and auto-inject the matching toleration into every Windsor-managed
controller (Flux, CSI, CNI, LB controller, External-DNS, cert-manager).
Matches the AKS default and the documented AWS/Karpenter recommendation.

**Single-pool guard:** if a config declares exactly one pool, skip the taint
even if it's named `system`. Otherwise a single-pool cluster schedules
nothing. Auto-detect rather than require `taint: true` — simpler mental
model, matches what users actually mean.

**Migration:** `cluster.workers` continues to work on AWS as a desugared
single `general` pool, so existing configs don't break.

### Topology

Wire `topology` (`single-node`/`multi-node`/`ha`) into EKS: control-plane AZ
spread, NAT gateway mode, pool fan-out. Today the preset is ignored on AWS.

Honor `cluster.controlplanes.schedulable` (commit 2d8c2b2c) for single-node
AWS — currently unsupported.

### Other Phase 1 work

- Pool upgrade settings: drain timeout, max surge, soak duration.
- Flow `cluster.pools.*.root_disk_size`, `disks`, labels, taints into the
  EKS node-group / Karpenter NodePool equivalent.

---

## Phase 2 — Networking primitives

- Private-cluster mode as a first-class schema input (currently buried in TF
  defaults inside [cluster/aws-eks](../terraform/cluster/aws-eks/)).
- NAT routing mode (`per-az` | `single`) — large cost lever.
- VPC endpoints for S3/ECR/STS/EC2 (cost + private-cluster correctness).
- Subnet CIDR breakdown exposed (public/private/intra).

---

## Phase 3 — In-cluster controllers

Without these AWS is effectively "EKS + EBS + figure out the rest." Each
item below is a new kustomize component + IRSA/Pod Identity binding.

- **AWS Load Balancer Controller** — unblocks `gateway` on AWS.
- **External-DNS Helm deploy** — today only the IAM role exists in
  [cluster/aws-eks/additions](../terraform/cluster/aws-eks/additions/); no
  controller runs.
- ~~**Cert-Manager + Route 53 DNS-01** — no ACME path on AWS today.~~
  Implemented: setting `dns.public_domain` on AWS provisions the public
  Route53 zone via the standalone
  [dns/zone/route53](../terraform/dns/zone/route53/) stack, wires the
  cert-manager IAM role + Pod Identity binding in
  [cluster/aws-eks](../terraform/cluster/aws-eks/)
  (`create_cert_manager_role`), and emits the `public-issuer/acme`
  ClusterIssuer
  ([kustomize/pki/resources/public-issuer/acme](../kustomize/pki/resources/public-issuer/acme/)).
  The Gateway TLS cert switches from `private` to `public` automatically.
  Top-level `email` is required; `dev: true` selects the Let's Encrypt
  staging endpoint to avoid prod rate-limit burns. Operator's only
  manual step: delegate the domain at their registrar to the name
  servers exposed by the dns-zone stack output.
- **EFS CSI** — addon is in the default list but not deployed or
  kustomized; add access points.
- Wire `cluster.storage.driver` (openebs/longhorn) as a layer on top of
  EBS, matching the 9f7a5b4f pattern used on other providers.
- Wire `gateway` (envoy/cilium) — AWS currently has no gateway integration.

All controllers must ship tolerations for `CriticalAddonsOnly` (see Phase 1
system-pool behavior).

---

## Phase 4 — New schema (land before 2.0 ships)

Schema-breaking changes belong here so they're done before GA.

### Expand `topology` from preset to object

Today it's a coarse enum (`single-node` / `multi-node` / `ha`). Grow it:

```yaml
topology:
  regions: [us-east-1]
  zones: [us-east-1a, us-east-1b, us-east-1c]
  failure_domains: 3
  control_plane_placement: spread | single-az
```

Keep the preset enum as syntactic sugar that expands into the object.

### New `aws` provider block

```yaml
aws:
  account_id: ...
  role_arn: ...
  profile: ...
  partition: aws | aws-us-gov | aws-cn
  default_tags: { ... }
```

### `cluster.autoscaling`

```yaml
cluster:
  autoscaling:
    driver: karpenter | cluster-autoscaler | none
```

Karpenter's NodePool CRD becomes *the* implementation of a pool on AWS when
`driver: karpenter` — no separate abstraction.

### `cluster.identity`

```yaml
cluster:
  identity:
    mode: irsa | pod-identity | workload-federation
```

### `dns.zones[]`

Today there's one `public_domain`. Multi-zone External-DNS needs a list.

### `cluster.pools` schema

The full formal schema for Phase 1's pool model lands here. Fields:
`class` (required enum), `count` | (`min`, `max`), `lifecycle`
(on-demand | spot), `requirements`, `instance_types`, `gpu`,
`root_disk_size`, `disks`, `labels`, `taints`, `upgrade`.

---

## Phase 5 — Day-2 & compliance

- CloudWatch Container Insights addon (Azure shipped the equivalent in
  #1197; AWS has nothing).
- Wire `terraform.backend` → S3/DynamoDB on AWS (commit b435e101 added the
  schema; AWS facet ignores it). See **Appendix A** for the state-backend
  hardening work this depends on.
- Wire `policies.*` (commit c871d9a1) through to EKS-specific enforcement.
- `aws_auth` / access entries schema for break-glass.
- KMS key rotation lifecycle exposed.

---

## Phase 6 — Tests & GA gating

[platform-aws.test.yaml](../contexts/_template/tests/platform-aws.test.yaml)
has 4 cases. For GA it needs, at minimum, tests for:

- Each topology preset and the expanded topology object.
- Each pool class (system, general, compute, gpu, spot).
- Single-pool cluster (verifies the system-taint guard).
- Multi-AZ and private cluster.
- Karpenter vs managed-node-group paths.
- Cilium + EKS.
- Gateway enabled.
- Each storage driver.
- Backend-in-S3.
- Single-node regression (`schedulable: true`).

Terraform module tests in [terraform/cluster/aws-eks](../terraform/cluster/aws-eks/)
and [terraform/network/aws-vpc](../terraform/network/aws-vpc/) need to move
beyond syntax checks.

---

## Sequencing

1. **Phase 1 first.** Without node schema wiring (pools, topology,
   schedulable), the rest compounds on a broken foundation.
2. **Phase 3 next** — biggest user-visible "works out of the box" win.
3. **Phase 4 before 2.0 ships** — schema changes must land pre-GA.
4. Phase 2, 5, 6 interleave with the above; Phase 6 gates the 2.0 release.

## Open decisions still worth making

- Do pool names have a closed set of reserved values (`system`) or are they
  fully user-defined with `class` carrying the semantics? (Leaning: fully
  user-defined, `class: system` triggers taint behavior — pool *name* is
  arbitrary.)
- Does `cluster.workers` stay permanently as metal's node-list shape, or
  does metal-via-Omni also move to pools? (Leaning: Omni uses pools, pure
  static metal keeps workers.)
- Karpenter as the AWS default autoscaler from day one, or keep EKS managed
  node groups as the default and Karpenter opt-in? (Leaning: managed node
  groups default, Karpenter opt-in at 2.0, flip the default post-GA.)

---

## Appendix A — State backend hardening

Sources referenced here: HashiCorp
[S3](https://developer.hashicorp.com/terraform/language/backend/s3) and
[azurerm](https://developer.hashicorp.com/terraform/language/backend/azurerm)
docs, [AWS Prescriptive Guidance](https://docs.aws.amazon.com/prescriptive-guidance/latest/terraform-aws-provider-best-practices/backend.html),
[Microsoft Learn: Store Terraform state in Azure Storage](https://learn.microsoft.com/en-us/azure/developer/terraform/store-state-in-azure-storage),
[Securing Terraform State in Azure (Microsoft Community Hub)](https://techcommunity.microsoft.com/blog/fasttrackforazureblog/securing-terraform-state-in-azure/3787254),
[OpenTofu State and Plan Encryption](https://opentofu.org/docs/language/state/encryption/),
[S3 native state locking — Bryan Schaatsbergen](https://www.bschaatsbergen.com/s3-native-state-locking).

The 2026 state of the art has moved on from the patterns currently
encoded in [terraform/backend/s3](../terraform/backend/s3/) and
[terraform/backend/azurerm](../terraform/backend/azurerm/). Phase 5's
"wire `terraform.backend`" item should not wire the current modules as-is;
the modules need hardening first.

### A.1 — S3 backend (`terraform/backend/s3`)

**What changed upstream:**
- Terraform 1.10+ added S3-native locking (`use_lockfile = true`) using S3
  conditional writes (`If-None-Match: *`) to create a `.tflock` object
  alongside the state. HashiCorp has deprecated the DynamoDB locking path
  and plans to remove it.
- Bucket-policy guidance now expects TLS-only enforcement on every
  statement (not just admin access) and deny-if-unencrypted on PutObject.
- Object Lock (Compliance/Governance) has become the recommended guard
  against malicious state rollback, layered on top of versioning.
- OIDC federation from CI (GitHub Actions, GitLab, etc.) has replaced
  long-lived IAM access keys as the default pipeline credential.

**Work items:**

1. **Switch default locking to `use_lockfile`.** Keep `enable_dynamodb`
   as an opt-in for users pinned to old Terraform versions, but flip the
   default. Update the template at
   [terraform/backend/s3/templates](../terraform/backend/s3/templates/)
   to emit `use_lockfile = true`.
2. **Tighten the bucket policy.**
   [terraform/backend/s3/main.tf:104-110](../terraform/backend/s3/main.tf#L104-L110)
   currently uses `Resource = ["*"]` (with a scoped-ARN variant commented
   out — a red flag). Scope to the bucket ARN + `/*`.
3. **Add a deny-unless-TLS statement** covering the whole bucket (today
   TLS is only enforced as a condition on the admin statement).
4. **Add a deny-if-unencrypted PutObject statement.**
5. **Optional `aws_s3_bucket_object_lock_configuration`** with a
   governance-mode retention variable, opt-in.
6. **Ship a sibling OIDC-provider submodule** so users can plumb GitHub
   Actions / GitLab into the backend without long-lived keys.

### A.2 — azurerm backend (`terraform/backend/azurerm`)

**What changed upstream:**
- Microsoft's and HashiCorp's current guidance is to set
  `use_azuread_auth = true` and `use_oidc = true` on the backend block,
  disabling shared-key access on the storage account entirely. Pipelines
  authenticate via workload identity federation; RBAC (`Storage Blob
  Data Contributor`) controls access.
- Private endpoints + storage firewall are the expected production
  defaults; the public-access-by-default pattern is called out explicitly
  as wrong for state backends.
- Native blob-lease locking remains the correct locking primitive — no
  equivalent of the DynamoDB → S3-native migration is needed.

**Work items:**

1. **Emit `use_azuread_auth = true` and `use_oidc = true`** in the
   backend template at
   [terraform/backend/azurerm/templates](../terraform/backend/azurerm/templates/).
2. **Disable shared-key access** on
   [`azurerm_storage_account`](../terraform/backend/azurerm/main.tf#L26)
   (`shared_access_key_enabled = false`, `default_to_oauth_authentication = true`).
3. **Flip `allow_public_access` default to `false`** in
   [terraform/backend/azurerm/variables.tf:82](../terraform/backend/azurerm/variables.tf#L82).
   Require explicit opt-in plus `allowed_ip_ranges`.
4. **Add an optional private-endpoint submodule** (private endpoint +
   Private DNS zone + VNet link).
5. **Bootstrap Key Vault** when `enable_cmk = true` and no
   `key_vault_key_id` is supplied — currently BYO-vault only. Include
   purge protection and soft-delete on the vault.
6. **Add a `role_assignments` variable** granting `Storage Blob Data
   Contributor` to pipeline principal IDs — azurerm equivalent of s3's
   `terraform_state_iam_roles`.
7. **Fix the destroy path** (parity with the AWS `force_destroy` on
   `operation == "destroy"`). Versioning + 7-day blob/container retention
   currently blocks clean teardown. Add an `operation` variable and
   drain blob versions + disable retention when destroying.
8. **Add diagnostic-settings plumbing** to a Log Analytics workspace —
   parity with s3's access-log bucket wiring.

### A.3 — Optional: OpenTofu state-level encryption (cross-cutting)

OpenTofu 1.7+ added native state-and-plan encryption *above* the backend
layer: a PBKDF2 key provider + AES-GCM AEAD, or cloud KMS key providers
(AWS/GCP/OpenBao). HashiCorp Terraform has no equivalent; the closest is
HYOK in HCP Terraform. If Windsor wants defense-in-depth so a storage-
account leak isn't game over, this is the only option outside HCP.

Proposed: make OpenTofu state encryption a Windsor-wide optional feature
(not per-provider), gated on the user's runtime. When OpenTofu is
detected, optionally emit an `encryption` block in the generated
backend config wired to the same KMS key used for at-rest encryption
(AWS KMS key or Azure Key Vault key), giving double-wrap encryption.
This aligns with the zero-trust posture expected at GA and is the single
largest step-change in state security since 2024.

**Decision to make:** does Windsor support this only on OpenTofu, or
also on HCP Terraform via HYOK? Leaning OpenTofu-only for 2.0 — HYOK
requires HCP Terraform paid tier and narrows our user base.
