# Where does RDS's AWS support infra live?

`database.postgres.driver: rds` needs three AWS resources Crossplane
itself can't create: an IAM role/policy/Pod Identity association, a KMS
key for storage encryption, and a DB subnet group. Right now all three
sit in `cluster/aws-eks` — the KMS key and subnet group directly in its
`main.tf`, the IAM pieces in a nested `modules/crossplane-iam`. None of
them describe the EKS cluster. This document lays out why, what's
actually precedented elsewhere in this repo, and the options for where
this infra should live instead.

## Why `cluster/aws-eks` is the wrong home

`cluster/aws-eks`'s job is the EKS control plane and the Pod Identity
roles *core itself* wires up for the add-ons it installs — cert-manager,
aws-lb-controller, cluster-autoscaler, Karpenter. Those are core's own
add-ons, gated by core's own facets, with no independent lifecycle from
the cluster.

RDS is a different kind of thing: a capability a *customer's chart* opts
into after `windsor apply`, expressed as `database.postgres.driver`, the
same schema surface CloudNativePG uses. Its AWS support infra doesn't
describe the cluster; it describes the database. Filing it in
`cluster/aws-eks` because the IAM role happens to need Pod Identity, and
the subnet group happens to need VPC subnet IDs, is scoping by
implementation dependency, not by what the resources actually are.

## Precedent already in this repo

**`pki/ca`** is a top-level Terraform layer, gated by `pki.enabled`, wired
from `platform-base.yaml`, and it's genuinely optional — most contexts
never touch it. It's platform-independent (only the `tls` provider), so
it doesn't need a vendor split, but it proves an addon-scoped top-level
layer is a normal shape here.

**`dns/zone/route53`** is the closer match: `dns` is the capability-named
top-level layer, `zone/route53` is the AWS-specific implementation nested
one level down, gated by `dns.public_domain != ''`. It runs after
`backend` and *before* `cluster`, and `cluster` consumes its output
(`terraform_output('dns-zone', 'zone_id')`) to scope the cert-manager IAM
policy. That's the same shape RDS needs, just with the dependency
direction reversed — RDS's stack would depend on `cluster`'s output
instead of the other way around.

**`cluster/aws-eks/additions`** is a separate, separately-staged root
module (`dependsOn: [cluster]`, `destroy: false`) that exists specifically
because some resources are cluster-adjacent without being part of the
cluster module itself. It's scoped narrowly today (`kubernetes`-provider
resources needing a live API endpoint), so it's not a literal template
for RDS's `aws`-provider resources, but it's proof the "own stack,
dependent on cluster's outputs" shape is already accepted practice in
this exact directory.

ADR-0009 §3 currently claims "none of the 9 existing layers are
addon-scoped the way a database layer would be." `pki` and `dns-zone`
both contradict that — it undersold the precedent when IAM placement was
decided. Worth correcting regardless of which option below is chosen.

## Options

### A. Split nested submodules

Keep `cluster/aws-eks/modules/crossplane-iam` exactly as it is today —
IAM role/policy/Pod Identity, catalog keyed by resource type, `for_each`.
Add a new `cluster/aws-eks/modules/rds`, scoped to just the KMS key —
the DB subnet group moves to `network/aws-vpc` regardless of which option
here is chosen (see the subnet-group note under Option B; it applies to
every option).

- Smallest diff. No new blueprint dependency edges, no new
  `windsor apply` stage, no new destroy-ordering to reason about.
- Doesn't actually fix the complaint. `cluster/aws-eks/main.tf` and
  `variables.tf` still carry `crossplane_resources`,
  `manage_rds_encryption_key`, `rds_kms_key_arn`, `isolated_subnet_ids` —
  RDS-specific surface area, just contained in two submodules instead of
  one. `windsor plan terraform cluster` still churns on RDS changes that
  have nothing to do with the EKS control plane.

### B. Two new top-level layers, split by what actually varies together

Not one `database` layer holding everything — two, because the KMS key
and the IAM/Pod-Identity plumbing don't actually share a reason to change
together, and bundling them re-creates the exact "one name, two unrelated
collections of things" problem already rejected for `provisioning`.

**`terraform/database/aws-rds`** — the KMS key and its alias. Nothing
else. Wired from `platform-aws.yaml` with `dependsOn: [network, cluster]`
(the latter only for `cluster_name`, used in naming/tagging — no IAM
coupling). Named for the *capability*, not the mechanism, deliberately:
encryption is a property of the data, independent of whether Crossplane
or (someday) Terraform itself creates the actual RDS instance. That's
also why it's not `aws-rds-crossplane` — a future Terraform-native mode
(`aws_db_instance` created directly, no Crossplane involved) would want
the *same* key, not a second one scoped to a different engine. If that
mode ever gets built, it *extends* this layer (adds the instance
resource, still keyed by the same encryption story), it doesn't need a
new one. No naming collision to reserve against, because the layer was
never engine-specific to begin with.

That extension is also where this layer's own multiplicity would live.
The KMS key and subnet group stay singular per cluster either way — that
part doesn't change — but Terraform-native database *instances* are a
different story from Crossplane-managed ones: a chart's `Instance` CRs
are unbounded and entirely outside Windsor's blueprint (the whole point
of the Crossplane design — Windsor never has to know how many exist), but
a Terraform-native database is *declared in the blueprint*, the same way
`cluster.pools` or `node_groups` are today. So when that mode gets built,
it's a `for_each` over a blueprint-declared map (`database.postgres.instances`
or similar → `var.instances = { orders = {...}, analytics = {...} }` in
this layer), each producing its own `aws_db_instance`, all still sharing
the one KMS key and subnet group already here. Two different mechanisms
for "more than one database," coexisting in the same layer because the
shared encryption/network story underneath neither cares nor needs to
change which mechanism is asking for it — this is precisely why the key
and subnet group had to be singular and engine-agnostic from the start,
not a detail to work out later.

**`terraform/provisioning/crossplane-iam`** — the IAM role, policy, and
Pod Identity association, moved out of `cluster/aws-eks/modules/` as-is
(same catalog/`for_each` shape, same content) into its own top-level
layer under `provisioning`, mirroring `kustomize/provisioning/`'s own
top-level name for the identical reason: this is Crossplane's own
wiring, not a database concept. Unlike the KMS key, this genuinely *is*
engine-specific — Pod Identity exists because a Crossplane provider pod
needs credentials to call AWS on the cluster's behalf. A Terraform-native
mode wouldn't need any of it; `windsor apply`'s own credentials would
create the instance directly, no in-cluster pod involved. So keeping
"crossplane" in this layer's name is accurate, not presumptuous — it's
the one piece that's genuinely inseparable from the engine. Wired with
`dependsOn: [cluster, database]`: `cluster_name`/`cluster_arn` from the
former, `kms_key_arn` from the latter (the catalog's `rds` entry needs
it for the `kms:DescribeKey`/`kms:CreateGrant` statements). The
catalog/`for_each` stays, and keeps earning its keep here specifically —
unlike the KMS key, IAM policies for a second Crossplane-managed AWS
resource type genuinely *are* a repeated shape, so a second entry in this
map is the right extension point when that happens, matching
`kustomize/provisioning/install/crossplane/<resource-type>` growing the
same way.

`cluster/aws-eks` goes back to owning nothing RDS-related either way:
delete `modules/crossplane-iam`, drop `crossplane_resources`,
`isolated_subnet_ids`, `manage_rds_encryption_key`, `rds_kms_key_arn`
from its `variables.tf`.

**The DB subnet group moves to `network/aws-vpc`, not into either new
layer.** `aws_subnet.isolated` and its route table/associations are
already created unconditionally in `network/aws-vpc/main.tf` —
regardless of whether anything uses them, the same way the private/public
tiers are. An `aws_db_subnet_group` wrapping the isolated subnets costs
nothing and fits that same unconditional pattern; there's no reason to
gate its creation on `database.postgres.driver == 'rds'` any more than
the subnets themselves are gated. It's also the most neutral of the
three resources — pure networking, no engine or encryption opinion at
all — so `network` is the right, uncontested home. `network/aws-vpc`
gains one new output (`db_subnet_group_name`) so the real value is
discoverable and testable — but the name it holds stays a deterministic
convention, not a generated one: **`${context_id}-rds`**, not
`${cluster_name}-crossplane-rds` — dropping "crossplane" here for the
same reason the KMS key drops it. That's deliberate for a second reason
too: the whole point of `driver: rds` is that a *third-party* Helm
chart, installed separately from core's own blueprint, authors the
`Instance` CR. That chart has no access to Flux's `postBuild.substitute`
at all — that mechanism only resolves inside Windsor's own
blueprint-compiled Kustomizations. So a real chart can't consume
`terraform_output('network', 'db_subnet_group_name')` via substitution
the way the demo can; it needs a value it can hardcode or template from
information it already has (its own `values.yaml`, populated by whoever
installs it). A documented, deterministic naming convention is that
value — the terraform output exists for discoverability/testing, not as
the intended delivery mechanism to a customer's chart.

The same reasoning applies to `kmsKeyId`, which today is threaded to the
demo via a `rds_kms_key_arn` substitution — that's demo-only plumbing,
not something a third-party chart could reach either. KMS keys support
aliases, and `kmsKeyId` accepts an alias name directly, so the fix is the
same shape as the subnet group: give the self-created key a stable,
documented alias — **`alias/${context_id}-rds`** — and have both the
demo and the documented third-party contract reference that alias by
name, not the raw ARN. Confirmed against AWS's own docs (see below) this
only works for the self-created path; BYOK and ephemeral each have their
own answer.

With both values naming-convention-driven, the demo should exercise that
same convention rather than lean on Flux substitution for either field —
it's meant to be a worked example of the actual third-party contract, and
using Windsor-only plumbing there would document the wrong thing. The
`cluster_name` substitution stays (it's foundational identifying info the
demo already threads, and a real chart needs to obtain it some other way
regardless), but `rds_kms_key_arn` as a substitution goes away entirely
once the alias exists.

- Matches the `dns-zone`/`pki` precedent directly: each capability's AWS
  infra is its own inspectable, independently-planned stack.
  `windsor plan terraform database` and `windsor plan terraform
  provisioning` both become real, narrow things to check — exactly what
  this session's troubleshooting loop has been doing by hand against
  `cluster` all along. Disabling `database.postgres.driver` cleanly tears
  down both stacks with zero risk to the cluster itself. `cluster/aws-eks`
  stays legible as "the EKS control plane and core's own add-ons," full
  stop. Naming is honest at every layer, and each of the two new stacks
  varies for a genuinely different reason — one for data/encryption
  concerns, one for engine/identity concerns — so a future change to
  either doesn't ripple into the other. `terraform/provisioning/` and
  `kustomize/provisioning/` now name the same underlying concept the same
  way, which they didn't before.
- Real diff, slightly larger than a single new layer: two new
  directories instead of one, two new dependency edges (one of them a
  diamond — `provisioning` depends on both `cluster` and `database`),
  two more apply stages, plus the `network/aws-vpc` change and its own
  new output. Also surfaces a teardown-ordering question: with the subnet
  group unconditional in `network`, the only thing left with a
  Crossplane-managed-`Instance` teardown hazard is the KMS key itself —
  Terraform destroying it while a live `Instance` still references it
  would fail or orphan the instance. That risk exists today regardless of
  where this code lives, but a standalone stack makes it a more visible
  thing to actually decide and document (likely: `destroy: false` on
  `database`, matching how `gitops` and `cluster-additions` already
  handle their own teardown ordering, plus documented guidance that the
  `Instance` must be deleted first).

### C. Hybrid (not recommended)

One `database` layer holding the KMS key, subnet group, *and* the IAM/
Pod-Identity catalog together, rejected earlier for bundling
dissimilar things under one name — mentioned only to rule it back out
now that the split is more precise: it would still couple the KMS key's
name/lifecycle to "crossplane" specifically, re-introducing the naming
collision Option B avoids for a future Terraform-native mode.

## Deeper implementation details and repercussions

### The KMS alias idea only works for the self-created key

Confirmed against [AWS's own KMS documentation](https://docs.aws.amazon.com/kms/latest/developerguide/alias-authorization.html):
a custom alias can target any *customer managed* key in the same account
and Region. AWS managed keys — `aws/rds` included — can't have a
custom alias created for them at all; `CreateAlias` rejects it. So the
alias-based convention only applies when `manage_rds_encryption_key` is
true (the dedicated CMK path). Two other paths don't need it:

- **Ephemeral** (`manage_rds_encryption_key: false`, no dedicated CMK):
  there's nothing to alias. The documented contract for this path is just
  "reference `alias/aws/rds` directly" — already a fixed, AWS-owned name,
  not something Windsor invents.
- **BYOK** (`crossplane_kms_key_arn` set): the operator already knows the
  ARN — they're the one who put it in `values.yaml`. Aliasing it would
  also need `kms:CreateAlias`/`kms:DeleteAlias` permission on a key they
  own and may have locked down with their own key policy, which core has
  no business assuming. Skip creating an alias for this path; the
  operator hands the same ARN they already configured straight to
  whatever chart needs it.

So the alias only gets created in one of the three paths, not all three
— worth being explicit about that in the ADR rather than implying a
uniform mechanism.

### The catalog/`for_each` indirection moves, but keeps earning its keep

`crossplane-iam`'s `for_each` over a `crossplane_resources` set exists so
nothing needs a hand-written IAM block per Crossplane resource type as
more get added. With the split in Option B, this indirection now lives
in `provisioning/crossplane-iam` specifically — and there it's still the
right call, since a second Crossplane-managed AWS resource type (S3, say)
would need its own provider pod's own IAM policy, a genuinely repeated
shape. The KMS key in `database/aws-rds`, by contrast, has no such
multiplicity to abstract over — it's one key, full stop, so it stays flat
(matching `pki/ca`'s shape), no catalog needed there at all. The split
resolves what looked like a contradiction earlier: it's not that the
catalog pattern stopped being useful, it's that it was only ever earning
its keep for the IAM piece, not the encryption piece — bundling them
together under one name obscured that.

### State migration: this is a cross-state move, not an in-place one

`crossplane-iam`'s resources and `aws_db_subnet_group.crossplane_rds`
already exist live in `aws-test`'s `cluster` Terraform state (the IAM
role/policy/attachment, the Pod Identity association, the subnet group —
five resources, applied earlier this session). Moving them into two new
top-level layers means two *different state files* — `moved {}` blocks
only relocate addresses within one root module's state, they can't reach
across separate Terraform states the way this restructuring needs. Absent
a manual `terraform state mv -state-out=...` per resource, `windsor plan`
on this change will show these five as destroy-then-create, not
in-place moves.

That's fine right now: none of the five hold anything with a lifecycle of
its own (an IAM role recreated under the same name is functionally
identical, the subnet group recreated with the same subnets is a no-op
in practice, Pod Identity re-association is immediate). The one resource
where destroy-and-recreate is genuinely dangerous — the KMS key — was
never applied live in the first place (the dedicated-CMK change from
earlier this session is still staged, not applied), so there's no
existing encrypted data that would be orphaned by a new key ARN. That
window won't stay open forever: once a real Crossplane-managed `Instance`
is actually encrypted under a key this repo manages, a restructuring
like this one would need real state surgery first. Worth a one-line note
in the ADR so a future similar change doesn't assume this stays free.

### `network/aws-vpc`'s unconditional subnet group needs 2+ AZs

RDS requires a DB subnet group to span at least two Availability Zones.
`network/aws-vpc`'s `availability_zones` variable defaults to 3 and isn't
wired from any facet today (`platform-azure.yaml` sets Azure's equivalent
per-topology; nothing touches AWS's), so every real context already
clears that bar — but there's no explicit guard, and creating the subnet
group unconditionally (rather than only when `driver == 'rds'`) means
*every* AWS context now depends on that being true, not just the ones
using RDS. A `validation` block requiring `availability_zones >= 2` is
cheap insurance and documents the constraint instead of leaving it
implicit.

### Kustomize wiring gets simpler, not just relocated

With both `dbSubnetGroupName` and `kmsKeyId` (self-managed-CMK path)
resolvable from `cluster_name` alone via the documented convention, the
demo's `rds_kms_key_arn` substitution disappears entirely — no
replacement substitution needed, since `cluster_name` is already threaded
for other reasons. Net effect on `option-demo.yaml`/`instance.yaml` is a
reduction in wiring, not a like-for-like relocation.

### Teardown ordering still needs an explicit decision

Independent of where this code lives, destroying the KMS key or subnet
group while a live Crossplane-managed `Instance` still references them
fails or orphans the instance. As new, separately-staged top-level
layers this becomes a concrete thing to decide rather than an implicit
property of `cluster`'s own teardown: most likely `destroy: false` on
`database` (matching `gitops`/`cluster-additions`), with documented
guidance that the `Instance` must be deleted first.
`provisioning/crossplane-iam` doesn't need the same treatment — deleting
an IAM role/Pod-Identity-association out from under a running provider
pod just breaks that pod's next credential refresh, it doesn't touch the
database itself. Not blocking for this change, but shouldn't ship
without an explicit answer either way.

### Size of the change

New: `terraform/database/aws-rds` (KMS key + alias; `main.tf`,
`variables.tf`, `outputs.tf`, `test.tftest.hcl`, `README.md`) and
`terraform/provisioning/crossplane-iam` (`crossplane-iam`'s current
content, relocated as-is; same 5 files). Deleted:
`cluster/aws-eks/modules/crossplane-iam`. Shrinks:
`cluster/aws-eks/{main,variables,outputs}.tf` (four variables and every
RDS-specific resource removed). Small addition:
`network/aws-vpc/{main,variables,outputs}.tf` (one resource, one
validation, one output). Net-simpler:
`platform-aws.yaml`/`option-demo.yaml`/`instance.yaml`. Real rewrite:
ADR-0009 §3 plus a new subsection for the naming-convention contract.
`platform-aws.test.yaml` and `network/aws-vpc/test.tftest.hcl` both need
new cases; the deleted submodule's test splits into the two new layers'
own.

## Recommendation

B. It's the option that actually answers what "cluster-adjacent in
spirit, but not the cluster" should mean here: give each capability its
own place, name each for what it's already called everywhere else in
this repo, and stop asking `cluster/aws-eks` to carry a customer-opted-in
application dependency it has no other reason to own. Splitting into two
layers instead of one avoids bundling the encryption story (which should
outlive any particular engine) with the IAM story (which is genuinely
tied to Crossplane specifically) under a single name that would misdescribe
one or the other. It also corrects ADR-0009 §3's claim that no
addon-scoped top-level layer exists — `pki` and `dns-zone` already prove
the shape works well here, twice.

If this is the direction: `terraform/database/aws-rds` gets the KMS key
and gives the *self-created* key (not BYOK, not ephemeral) a stable
`alias/${context_id}-rds` alias; `terraform/provisioning/crossplane-iam`
gets `crossplane-iam`'s current content moved as-is, plus a new
`kms_key_arn` input sourced from `database`'s output; `network/aws-vpc`
gains the DB subnet group (named `${context_id}-rds`, same convention,
no "crossplane") and a `db_subnet_group_name` output for
discoverability/testing; `cluster/aws-eks` loses all four RDS-related
variables and the submodule entirely; `platform-aws.yaml` gets two new
terraform entries (`database` depending on `network` + `cluster`;
`provisioning` depending on `cluster` + `database`), and the `network`
entry's own inputs are unchanged (the subnet group needs no new input,
just the isolated subnets already created there); every touched test
(`platform-aws.test.yaml`, `network/aws-vpc/test.tftest.hcl`, the deleted
submodule's `test.tftest.hcl` splits into each new layer's own, each
asserting the real name/alias matches the documented convention)
follows; the demo's `rds/instance.yaml` drops the `rds_kms_key_arn`
substitution entirely and references `dbSubnetGroupName`/`kmsKeyId` by
the same naming convention a third-party chart would use; ADR-0009 gets a
new subsection documenting that convention as the actual contract, and §3
gets rewritten to describe the two new layers instead of the submodule.
