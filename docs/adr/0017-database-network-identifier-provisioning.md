---
title: "ADR-0017: Kyverno defaults the remaining cloud-network identifiers, fail-closed"
description: Extends the existing tag/resource-group/project Kyverno mutations (kustomize/database/resources/crossplane/postgres/*) with a second, separate mutation per driver that fills in each driver's subnet/security-group/KMS/network fields only when the resource doesn't already set them — failurePolicy Fail, not Ignore, matching the precedent inject-private-ca and cilium-gateway-lbipam-sharing already set for correctness-critical mutations with no IAM-style backstop. No new claim type, no chart migration, no reliance on a chart reading anything, and a chart's own explicit value always wins.
---

# ADR-0017: Kyverno defaults the remaining cloud-network identifiers, fail-closed

## Status

Implemented on `database-network-defaults`. Fourth draft. First:
deterministic naming plus a Kyverno fallback for AWS's security group.
Second: a Windsor-owned Crossplane Composition — rejected as too large a
lift. Third: a published `ConfigMap` a chart reads via Helm's `lookup` —
scrutinized and rejected as discovery without enforcement, a real
regression from how every other correctness-critical mutation in this
repo behaves.

Verified: all three new `MutatingPolicy` resources (§1) compile and
reach `Ready` against the local test cluster's live Kyverno v1.19.1
install (CEL syntax, `has()`/optional-chaining guards, `ApplyConfiguration`
nesting). Field names and served API versions for all three providers
(`rds.aws.upbound.io Instance`, `dbforpostgresql.azure.upbound.io
FlexibleServer`, `sql.gcp.upbound.io DatabaseInstance`) were confirmed
directly against the real installed provider CRDs — installing
Crossplane 2.4.1 plus all three provider packages standalone in the
local cluster, `kubectl explain`-ing the real schema, then tearing it
back down. That surfaced two real, pre-existing bugs in the
already-merged tag/resource-group/project policies, fixed here as part
of the same change (§1, "Bugs found along the way"): GCP's
`DatabaseInstance` only serves `v1beta2` (`v1beta1`, which those
policies matched, does not exist for this CRD at all — the mutation has
been silently never firing); Azure's `FlexibleServer` serves both
`v1beta1` and `v1beta2` (those policies matched only `v1beta1`, missing
coverage). `windsor test`'s existing 361 cases pass unchanged.

**Not yet verified**: end-to-end behavior against a real cloud account
(create an `Instance`/`FlexibleServer`/`DatabaseInstance` with a field
omitted, confirm the default lands and the resource reaches `Ready`).
The local test cluster's single node couldn't sustain a live Crossplane
+ all-three-providers footprint long enough for this — installing all
three concurrently exhausted the node's memory and briefly took
Kyverno's own admission controller offline (unrelated to this ADR's
policies; recovered once the test installation was torn down). A
real-account pass is a reasonable follow-up before this is fully
trusted, the same posture ADR-0009/0011's own "Verification needed"
sections took for their initial merges.

## Context

`kustomize/demo/resources/database/{rds,azuredb,cloudsql}/` is the only
place today that creates `rds.aws.upbound.io Instance`,
`dbforpostgresql.azure.upbound.io FlexibleServer`, and
`sql.gcp.upbound.io DatabaseInstance` CRs, supplying cloud-specific
fields — subnet group/ID, KMS key, security group, resource group,
network — via Flux `substitutions:` sourced from `terraform_output(...)`.
[ADR-0009](0009-crossplane-cloud-databases.md) §3 frames the actual
requirement: a real third-party chart, installed after `windsor apply`
via plain `helm install`, has no Flux substitution access and no
Terraform access, and cannot supply these values the way
`option-demo.yaml` does.

ADR-0009 §3 already closes part of this gap with a Kyverno mutation:
`crossplane-instance-tag` (and its Azure/GCP siblings,
`crossplane-azuredb-rg`/the GCP context-label and project policies —
all migrated from `kyverno.io/v1 ClusterPolicy` to `policies.kyverno.io
MutatingPolicy` in this session's PR #2866) force-sets tags,
resource-group, and project on every matching resource's admission,
`failurePolicy: Ignore`. That's safe specifically because AWS's IAM
condition (and Azure's role-assignment scope) rejects a wrongly- or
untagged resource regardless of whether the mutation lands — a missed
mutation degrades to "IAM says no," never to "silently wrong."

The subnet group, KMS key, security group, delegated subnet, private
DNS zone, and network ID have no such backstop. Two mechanisms were
proposed and rejected for them before this draft:

**A Windsor-owned Crossplane `CompositeResourceDefinition`/`Composition`**
would let Crossplane itself inject every value uniformly, but only by
having the chart create Windsor's own claim type instead of the
provider's native resource — reversing ADR-0009 §4, and a
disproportionately large surface for the actual problem.

**A published `ConfigMap`, read via Helm's `lookup` function.** Simple,
additive, needs no new claim type. Scrutinized and rejected: `lookup`
cannot be rendered offline (`helm template`, `--dry-run`, most CI/GitOps
diff paths return nothing), so a chart that gets it wrong, or runs
before the `ConfigMap` exists, silently creates a database with an
empty or missing subnet/security-group/KMS field — no error, no
correction. It is discovery, not enforcement: nothing stops a chart
from ignoring the value, hardcoding a stale copy, or mis-reading it, the
same gap that exists today with no mechanism at all. And unlike
everything else in this repo, it doesn't reconcile — a value baked in
at one `helm install` never updates if the underlying network changes,
where every Flux-managed value in this repo self-heals on its own.

The reasoning that ruled out Kyverno for these fields in both earlier
drafts — "no IAM backstop, so a missed mutation is silently wrong" —
doesn't hold up as an argument against Kyverno itself, only against
`failurePolicy: Ignore`. This repo already runs two other Kyverno
mutations with **no backstop of any kind** and `failurePolicy: Fail`:
`inject-private-ca` (a pod that needs the CA bundle must not start
without it) and `cilium-gateway-lbipam-sharing` (the LBIPAM annotations
must be present at creation or the Service loses IP sharing). Both
accept "if Kyverno is unreachable, the create is rejected" as the
correct failure mode for a value with no other safety net. A subnet
group, security group, or KMS key is exactly that kind of value: there
is no cloud-side check catching "this Instance references no security
group" the way there is for "this Instance has the wrong tag."

## Decision

### 1. A second `MutatingPolicy` per driver, alongside the existing tag mutation, `failurePolicy: Fail`, defaulting rather than force-setting

Not a change to the existing tag/resource-group/project policies —
those keep `Ignore` and their unconditional overwrite, exactly as
ADR-0009 §3 justified: a chart-supplied tag has no legitimate reason to
win, since IAM checks it against this cluster's own condition
regardless of what a chart writes, so overwriting it is both safe and
necessary. The new policies behave differently on purpose: they set
`spec.forProvider.<field>` **only when the resource doesn't already set
it**, checked per field with a plain `has()` guard (these are real
schema-defined struct fields on the upjet-generated CRD, not map keys,
so a direct `has(object.spec.forProvider.dbSubnetGroupName)` guard is
safe — unlike the map-key case this session's PR #2866 had to route
around with optional-chaining for `namespaceObject.metadata.labels`).
A chart that has a real reason to choose its own subnet, security
group, KMS key, or network — a deliberately different topology, a
customer-managed key outside Windsor's own, a second security group for
tighter access — keeps that choice; the mutation exists only for the
chart that doesn't know or care, filling in Windsor's own environment
values as the default rather than the enforced answer.

A new, separate `MutatingPolicy` per driver (a `MutatingPolicy`'s
`failurePolicy` is set once for the whole object, so a field needing
`Fail` can't share an object with one that needs `Ignore`), living
alongside the existing one in the same directory:

- `kustomize/database/resources/crossplane/postgres/aws-rds/network-policy.yaml`
  — `crossplane-instance-network`, matching
  `rds.aws.upbound.io/{v1beta1,v1beta2,v1beta3} Instance`, defaulting
  `spec.forProvider.dbSubnetGroupName`, `spec.forProvider.kmsKeyId`,
  `spec.forProvider.vpcSecurityGroupIds` when absent (`CREATE, UPDATE`
  — none of the three are documented as immutable on this CRD).
- `kustomize/database/resources/crossplane/postgres/azure-postgres/network-policy.yaml`
  — `crossplane-azuredb-network`, matching
  `dbforpostgresql.azure.upbound.io/{v1beta1,v1beta2} FlexibleServer`,
  defaulting `spec.forProvider.delegatedSubnetId` and
  `spec.forProvider.privateDnsZoneId` when absent (`CREATE` only — both
  fields are documented as forcing a new `FlexibleServer` if changed).
- `kustomize/database/resources/crossplane/postgres/gcp-cloudsql/network-policy.yaml`
  — `crossplane-cloudsql-network`, matching
  `sql.gcp.upbound.io/v1beta2 DatabaseInstance`, defaulting
  `spec.forProvider.encryptionKeyName` and
  `spec.forProvider.settings.ipConfiguration.privateNetwork` when absent
  (`CREATE, UPDATE`).

**Bugs found along the way, fixed here.** Confirming these field names
and versions against the real provider CRDs (installing Crossplane
2.4.1 plus all three providers standalone, `kubectl explain`, then
tearing the installation back down) surfaced that GCP's
`DatabaseInstance` CRD serves only `v1beta2` — the existing
`crossplane-instance-tag`/`crossplane-cloudsql-project` policies
matched `v1beta1`, a version that has never existed for this CRD, so
those mutations have never actually fired. Azure's `FlexibleServer`
serves both `v1beta1` and `v1beta2`; the existing
`crossplane-instance-tag`/`crossplane-azuredb-rg` policies matched only
`v1beta1`. Both fixed in the same files this ADR otherwise leaves
alone, since they were already open for the version list this ADR's own
new policies needed to get right.

Each reads the exact `terraform_output(...)` values
`addon-database.yaml`'s `substitutions:` already compute for its own
terraform inputs today (`db_subnet_group_name`, `kms_key_arn`,
`security_group_id`; `azuredb_subnet_id`, `azuredb_private_dns_zone_id`;
`cloudsql_network_id`, and GCP's KMS key resource name) — added to that
same `flux:` entry's `substitutions:` block, closing the duplication
this investigation started from: one place per driver computes these
values, feeding both its existing terraform inputs and now this new
policy, rather than `addon-database.yaml` and `option-demo.yaml` each
deriving them independently.

### 2. A chart creates the plain provider resource and never has to know any of this

This is the actual payoff: a third-party chart's
`Instance`/`FlexibleServer`/`DatabaseInstance` can simply omit
`dbSubnetGroupName`/`kmsKeyId`/`vpcSecurityGroupIds` and land in the
right subnet, security group, and encryption key with no knowledge of
any of them. Unlike the tag mutation, a chart that *does* set one of
these fields keeps its own value — the default only fills a gap, it
never corrects a chart's deliberate choice. No `lookup`, no naming
convention, no new claim type, no chart-side change of any kind versus
what ADR-0009 §4 already established. `option-demo.yaml` is unaffected
for the same reason: it already supplies every one of these fields
directly, so the default never has anything to fill in for it.

### 3. `failurePolicy: Fail` couples database provisioning to Kyverno's own availability — accepted, and already the norm

If the admission webhook is unreachable, creating an `Instance`,
`FlexibleServer`, or `DatabaseInstance` fails outright, cluster-wide,
regardless of which chart is trying. This is a real cost, not a free
lunch — but it's the exact cost `inject-private-ca` and
`cilium-gateway-lbipam-sharing` already accept elsewhere in this same
policy install, and `kustomize/policy/README.md`'s own "Webhook
availability" section names the mitigation already in place:
`namespaceSelector` excludes `kube-system`/the GitOps namespace so Flux
can always recover, and `kyverno/ha` (three admission-controller
replicas plus a PDB) is available on `topology == 'ha'` for exactly
this reason. No new mitigation is needed here that doesn't already
exist for the other `Fail` mutations this policy install runs today.

## Alternatives considered

**A published `ConfigMap`, read via `lookup` (this ADR's third draft).**
Covered in Context. The deciding factor: it trades away the one
property this problem actually needs — a guarantee the value is
correct — for a lower-ceremony mechanism that only helps a chart that
already chose to use it correctly, and doesn't self-heal if the
underlying value changes.

**A Windsor-owned Crossplane Composition (this ADR's second draft).**
Still the more powerful answer if a future need requires more than
these six fields, or genuine cross-cloud claim portability. Not
justified for this scope: Kyverno already solves the correctness
problem for these specific fields with a mechanism this repo already
runs, at a fraction of the surface area.

**Deterministic naming (this ADR's first draft).** Still true for AWS's
`dbSubnetGroupName`/`kmsKeyId` (ADR-0009 §3) — this decision doesn't
contradict that, it just stops asking the chart to reconstruct it: the
chart can supply the deterministic name itself (unaffected, still
valid) *or* omit the field and let Kyverno supply it. Extending the
same convention to Azure/GCP was rejected as strictly worse than
Kyverno once Kyverno is already the mechanism for AWS's security group
— no reason to keep two different chart-facing contracts (naming
convention on one cloud, a defaulting mutation on the others) when one
mutation-based contract covers all three uniformly.

## Verification done, and what's left

Done: exact field names/shapes and served API versions for all three
providers, confirmed directly against the real installed CRDs (Decision
§1's "Bugs found along the way"). Immutability: confirmed Azure's two
fields force a new `FlexibleServer` (`CREATE`-only match applied); AWS's
three fields carry no such note (`CREATE, UPDATE` is safe); GCP's two
fields likewise. All three new policies apply cleanly and reach
`status.conditionStatus.ready: true` against the local cluster's live
Kyverno v1.19.1 install, with no CEL compile errors — the same
compiles-and-reaches-Ready bar this session's PR #2866 applied to the
five original database policies (which also couldn't get full live
behavioral testing, for the identical missing-provider-CRDs-locally
reason). `windsor test`'s 361 cases pass unchanged.

Left before this is fully trusted:

- End-to-end behavioral verification against a real cloud account:
  create an `Instance`/`FlexibleServer`/`DatabaseInstance` with a field
  omitted, confirm the default lands correctly and the resource reaches
  `Ready`; create a second with the field explicitly set, confirm it's
  left untouched. The local test cluster's single node can't sustain a
  live Crossplane-plus-all-three-providers footprint long enough for
  this (see Status) — needs either a beefier local node or a real
  `aws-test`/`azure-test`/`gcp-test` context.
- Confirm `failurePolicy: Fail` on a resource this cluster-scoped
  (`Instance`/`FlexibleServer`/`DatabaseInstance` are all cluster-scoped
  MRs) doesn't interact badly with the same `namespaceSelector`
  exclusions the shared webhook config already carries — expected to be
  fine (cluster-scoped resources bypass `namespaceSelector` entirely,
  confirmed empirically this session for `ValidatingPolicy`), not yet
  confirmed for this specific new policy.

## References

- [ADR-0009](0009-crossplane-cloud-databases.md) §3, §4, §7 — the
  existing tag-mutation precedent this ADR extends, the "no core
  abstraction" decision this draft doesn't reverse (unlike the second
  draft), and the create-only-field precedent (`dbName`) relevant to
  Verification.
- `kustomize/pki/resources/private-issuer/ca/kyverno-inject/`,
  `kustomize/cni/install/cilium/gateway/lbipam/` — the existing
  `failurePolicy: Fail`-with-no-backstop precedent this ADR's Decision
  §3 cites.
- `kustomize/policy/README.md` "Webhook availability" — the mitigation
  already in place for every `Fail` policy this install runs, including
  the two new ones this ADR adds.
- `contexts/_template/facets/addon-database.yaml`,
  `contexts/_template/facets/option-demo.yaml` — where the duplicated
  `terraform_output(...)` lookups this ADR resolves currently live.
- windsorcli/core PR #2866 — the Kyverno `ClusterPolicy` →
  `policies.kyverno.io` migration whose review raised this question,
  and the source of the CEL syntax patterns (`ApplyConfiguration`,
  `dyn()` casting for heterogeneous map literals) these new policies
  will reuse.
