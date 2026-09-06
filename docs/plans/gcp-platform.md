# GCP platform support

`platform` has no `gcp` value today (`none | aws | azure | hetzner | incus
| metal | docker | hyperv | vsphere`). This lays out what a `gcp` platform
needs, mapped against the AWS and Azure precedent already in this repo, the
decisions that need an explicit answer before writing Terraform, and a phase
order to deliver it incrementally.

## Precedent map

Each hyperscaler platform is the same set of layers, one implementation per
cloud. GCP's column is what this plan adds.

| Layer | AWS | Azure | GCP |
|---|---|---|---|
| State backend | `backend/s3` | `backend/azurerm` | `backend/gcs` |
| Network | `network/aws-vpc` | `network/azure-vnet` | `network/gcp-vpc` |
| Cluster | `cluster/aws-eks` (EKS) | `cluster/azure-aks` (AKS) | `cluster/gcp-gke` (GKE) |
| Public DNS zone | `dns/zone/route53` | `dns/zone/azure-dns` | `dns/zone/gcp-dns` |
| cert-manager ACME solver | `pki/resources/public-issuer/acme/route53` | `.../azuredns` | `.../clouddns` |
| external-dns provider | `dns/install/external-dns/providers/route53` | `.../azure` | `.../google` |
| Database support infra | `database/aws-rds` (KMS key) | `database/azure-postgres` (RG, private DNS zone, NSG, CMK) | `database/gcp-cloudsql` (KMS key, private VPC peering) |
| Crossplane provider identity | inline on `cluster/aws-eks` (Pod Identity) | `provisioning/crossplane-identity-azure` (Workload Identity) | `provisioning/crossplane-identity-gcp` (Workload Identity Federation) |
| Cluster driver | `eks` | `aks` | `gke` |

`cluster.driver` gains a fourth enum value, `gke`, defaulted by
`platform-base.yaml` the same way `aws → eks` and `azure → aks` are today.

## Open decisions

These need an answer before any Terraform gets written — each one changes
the module boundary, not just an input.

**GKE Standard vs Autopilot.** Standard gives node-pool control matching
`cluster.pools` (the same shape AWS/Azure already expose). Autopilot removes
node management entirely, which conflicts with `cluster.pools`'s existing
contract and with running Cilium as the CNI (Autopilot fixes the dataplane).
Recommend Standard, for parity with the other two platforms and because it's
the only mode that supports a customer-chosen CNI.

**CNI: Cilium vs GKE Dataplane V2. Resolved — GKE Dataplane V2, matching the
AKS precedent already in this repo.** This repo's own `cluster/azure-aks`
answered the "cloud-managed Kubernetes + Cilium" question already:
`network_profile { network_policy = "cilium", network_data_plane = "cilium"
}` is unconditional in that module, using Azure's own managed Cilium
integration rather than a self-managed Helm install layered on top —
`cluster.cni.driver` stays empty for `platform == 'azure'`
(`platform-base.yaml`), so Windsor's own `terraform/cni/cilium` +
`option-cni.yaml` never fire there. `cluster/aws-eks` takes the opposite
default (AWS's native `vpc-cni` addon, no Cilium at all) but supports
opting into self-managed Cilium.

GKE Dataplane V2 (`datapath_provider = "ADVANCED_DATAPATH"`) is Google's
equivalent of AKS's managed Cilium integration — implemented with Cilium's
eBPF, run and configured entirely by Google. The AKS shape is the right one
to copy: enable Dataplane V2 unconditionally in `cluster/gcp-gke`, leave
`cluster.cni.driver` empty for `platform == 'gcp'` (same as azure/aws), and
never attempt a self-managed Cilium Helm install on top. That last part is
GKE-specific and not optional the way it is on AKS/EKS: Google's own docs
state Dataplane V2 doesn't support installing custom eBPF programs on its
nodes at all, unlike Azure CNI Powered by Cilium, which is explicitly
designed to be user-configurable. So `cluster.cni.driver == 'cilium'`
should never become a supported override for `platform == 'gcp'` the way it
is for `platform == 'aws'`.

The tradeoff: GKE clusters won't get the Hubble/Gateway-API/L2/Prometheus
features Windsor's own `cni/cilium` kustomize component provides on Talos
platforms — same tradeoff AKS and EKS already accept today, not a
regression specific to GKE.

**Workload Identity Federation for Crossplane.** GCP's equivalent of AWS Pod
Identity / Azure Workload Identity is Workload Identity Federation: a GCP
service account bound to a Kubernetes service account via an IAM policy
binding, no long-lived key. Maps cleanly to a new
`provisioning/crossplane-identity-gcp` layer, same shape as
`crossplane-identity-azure`.

**Storage CSI default.** AWS/Azure both bundle their CSI driver as a
cluster-addon IAM role inline on the cluster module (`aws-ebs-csi-driver`,
Azure Disk CSI). GKE ships the Persistent Disk CSI driver as a built-in
add-on (`gce_persistent_disk_csi_driver_config`) — no separate IAM wiring
needed, just enabling the add-on block, similar to how AKS's `azuredns`
add-ons are toggled.

**Database instance.** Following `database/aws-rds` / `database/azure-postgres`,
`database/gcp-cloudsql` owns the KMS key and any network prerequisite (Cloud
SQL needs private VPC peering when not using public IP) — not the Cloud SQL
instance itself, matching the existing pattern where the demo's `Instance`
CR is Crossplane-managed, not Terraform-managed.

## Project bootstrap (operator prerequisites)

GCP disables most APIs per-project by default, unlike AWS (always on) or
Azure (resource providers, mostly auto-registered). This is the same class
of problem `cluster/azure-aks` already solved for
`EncryptionAtHost`/`Microsoft.Compute`: a one-time, account-level
enablement step, documented as a `### Prerequisites` section in the
module's README, not managed by Terraform.

Reasons to keep it manual rather than a `google_project_service` resource:
`windsor destroy` must never disable project-level APIs (they can serve
things outside this module's scope), and enabling APIs needs Owner/Editor
IAM the long-lived deploy credential shouldn't need to carry.

`cluster/gcp-gke/README.md` documents:

```bash
gcloud services enable \
  container.googleapis.com compute.googleapis.com dns.googleapis.com \
  iam.googleapis.com cloudkms.googleapis.com sqladmin.googleapis.com \
  --project=<project-id>
```

plus a billing note mirroring Azure's ("requires a linked billing account;
GKE's control plane and Compute Engine nodes have no free tier").

**`gke-gcloud-auth-plugin`**, confirmed as a real, blocking prerequisite
during a live `windsor apply`: GKE has required this separate binary for
kubectl/client-go authentication since Kubernetes 1.26, and it isn't bundled
with a base `gcloud` install (`gcloud components install
gke-gcloud-auth-plugin`). Without it, Terraform's `kubernetes` provider
(used by `gitops/flux` to create the `flux-system` namespace) fails outright
— every other cluster resource in the chain applies fine first.

**metrics-server on GKE**, also found during the same live apply: GKE's own
`gcp-critical-pods` ResourceQuota (which every namespace needs to run a pod
at `system-cluster-critical` priority, the upstream metrics-server chart's
default) only ever gets created in `kube-system` — a namespace-scoped
restriction unique to GKE, not present on EKS/AKS. `platform-gcp.yaml`
suppresses Windsor's own metrics-server install (`metrics_server_enabled:
false`) since GKE already ships one built-in, the same fix
`platform-azure.yaml` already applies for AKS's own built-in copy.

**Auth**: matches `aws.profile` (assumes `aws configure sso` already ran)
and `azure.subscription_id`/`tenant_id` (assumes `az login` already ran).
GCP's equivalent is `gcloud auth application-default login` locally, or
Workload Identity Federation for CI. New schema block:

```yaml
gcp:
  project_id: <string>   # required when platform == 'gcp'
  region: <string>       # defaults to us-central1 when unset
```

Windsor doesn't create the GCP project itself, the same way it doesn't
create AWS accounts or Azure subscriptions — project creation and billing
linkage stay a manual, one-time operator step.

## New pieces, by directory

```
terraform/backend/gcs/                       state backend
terraform/network/gcp-vpc/                   VPC, subnets, firewall rules
terraform/cluster/gcp-gke/                   GKE Standard control plane, node pools
terraform/dns/zone/gcp-dns/                  public Cloud DNS zone
terraform/database/gcp-cloudsql/             KMS key, private service connection
terraform/provisioning/crossplane-identity-gcp/   Workload Identity Federation binding

kustomize/pki/resources/public-issuer/acme/clouddns/     cert-manager DNS-01 solver
kustomize/dns/install/external-dns/providers/google/     external-dns provider

contexts/_template/facets/platform-gcp.yaml
contexts/_template/tests/platform-gcp.test.yaml
```

Each new Terraform module gets its own `README.md` (terraform-docs
generated) and `test.tftest.hcl`, per the `terraform-style` skill's
conventions. `platform-gcp.yaml` follows `platform-azure.yaml`'s structure
directly — it's the closer precedent of the two (both are managed-control-
plane platforms with Workload Identity-style Crossplane auth, unlike AWS's
Pod Identity).

## Phase order

1. **Done.** `backend/gcs` + `network/gcp-vpc`. No facet yet. Validated that
   the module conventions (naming, `test.tftest.hcl` shape, `windsor plan`
   ergonomics) transfer cleanly to GCP's provider.
2. **Done.** `cluster/gcp-gke` with the CNI decision resolved: GKE Dataplane
   V2, matching the AKS precedent, confirmed against a real GKE cluster.
3. **Done.** `platform-gcp.yaml` wiring backend → network → cluster →
   gitops, gated `platform == 'gcp'`. Verified end-to-end with a real
   `windsor apply --wait`: every kustomization (gateway, observability, pki,
   policy, telemetry) reconciled Ready on a live GKE cluster, not just the
   bare cluster this phase originally targeted.
4. **DNS + cert-manager**: `dns/zone/gcp-dns`, the `clouddns` ACME solver,
   the `google` external-dns provider. Unlocks `dns.public_domain` on GCP.
5. **Done.** `database/gcp-cloudsql`, `provisioning/crossplane-identity-gcp`,
   and the `cloudsql` `database.postgres.driver`. Landed ahead of phase 4.
   Cloud SQL's `User` CR has no auto-generate mechanism for Postgres (unlike
   RDS/Flexible Server), so `gcp-cloudsql` generates the admin password
   itself and writes it to a Secret a chart's `User` CR reads via
   `passwordSecretRef`. Uses `roles/cloudsql.admin` at project scope —
   GCP's IAM model has no per-resource-group scoping the way Azure RBAC
   does, so this is a weaker boundary than the Azure equivalent.
6. **Full `platform-gcp.test.yaml`** covering every branch the equivalent
   AWS/Azure test files cover (minimal config, public domain, private
   gateway access, topology variants) plus docs (`docs/compatibility.md`
   gains a GCP row).

Each phase is a mergeable PR on its own, same granularity as the recent
single-platform-feature PRs in this repo's history.

## What this plan doesn't cover

Autopilot support, GCP Filestore (the EFS-equivalent), and Anthos/multi-
cluster mesh integration are all out of scope — none are needed to reach
parity with what AWS/Azure already support, and each is its own follow-on
scope once the base platform lands.

## Known gaps

`cluster/gcp-gke`'s `class: storage` pool resolves to a plain general-purpose
machine (`n4-standard-8`/`n4-standard-16`) with no local SSD attached — a
no-op compared to AWS's `i3`/`i4i` or Azure's `Lsv3`, both of which ship
local NVMe SSD as the defining feature of that class. GCP has no fixed
storage-optimized machine family; local SSD is a separate node-pool
attachment (`ephemeral_storage_local_ssd_config`), and making it actually
usable by pods needs a CSI provisioner on top, not just the attachment.
Scoped out until a real `class: storage` consumer on GCP needs it.

`cluster/gcp-gke`'s `pools` model is explicit, fixed node pools per class —
matching what `cluster/aws-eks` and `cluster/azure-aks` both actually ship
today. AWS is moving to self-hosted Karpenter and Azure is converging on
Node Auto-Provisioning (NAP); GKE has its own NAP that's the direct GCP
counterpart. Revisit this module's pools model once that migration actually
lands on AWS/Azure, rather than designing GCP's node-provisioning story
ahead of precedent that doesn't exist yet.
