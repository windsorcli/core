---
title: Backend
description: Remote Terraform state for cloud contexts (S3, AzureRM, GCS).
stack_backing: S3 · AzureRM · GCS
---

The backend category has one driver per cloud: `s3` (AWS), `azurerm`
(Azure), and `gcs` (GCP), selected by `terraform.backend.type`. Each
provisions its own storage plus a locking mechanism — see that
driver's own page for its recipe, diagram, and inputs. The `local`,
`kubernetes`, and `none` backend types don't run a Terraform module;
they're consumed directly by Terraform without provisioning anything:

```yaml
# Any platform; common for dev contexts.
terraform:
  backend:
    type: local
```

No backend module runs. Terraform state lives next to each stack in
the context's local state directory. Use this for single-operator dev
clusters and CI runs that don't share state across machines.

The backend stack runs first in every cloud context. The downstream
stacks (`network`, `cluster`, `dns-zone`) all depend on it.

The bootstrap pass runs each backend module with a local state file,
which provisions the bucket or Storage Account. Subsequent
`windsor apply` calls then read and write state through the remote
backend and hold the lock for the duration of the run.

## Operations

The bootstrap is a chicken-and-egg situation: the bucket has to exist
before Terraform can use it for state. Each cloud module solves this
by running with a local backend on the first apply, then handing the
state location over to the remote backend for subsequent runs.

A state lock held by a dead run won't release on its own. A crashed
`windsor apply` leaves the lock in place. On AWS, delete the row from
the DynamoDB lock table; on Azure, release the lease on the state
blob. Audit the state first, because the lock exists for a reason.
GCP is the exception: its generation-precondition locking isn't held
across runs, so a crashed apply leaves nothing to clean up.

Switching `terraform.backend.type` on a context that already has
remote state requires manual migration via
`terraform init -migrate-state`. Windsor doesn't auto-migrate.

`type: none` stops Windsor from emitting a backend block. Terraform then
falls back to its built-in local backend and writes `terraform.tfstate`
to the working directory. State is on disk but not centralized or
locked, which is fine for ephemeral test contexts and inappropriate
for anything shared across machines.

## Security

The `s3` module enables versioning, server-side KMS encryption, and a
public access block on the bucket. Versioning doubles as a poor-man's
audit trail for state writes.

The `azurerm` module uses blob leases for locking. The lease ID is
scoped to the Storage Account credential and isn't visible from
outside.

The `gcs` module uses Google-managed encryption by default; set
`enable_cmek` to bring your own KMS key instead. IAM access to the
bucket is least-privilege by default — grant readers/writers
explicitly via `terraform_state_principals` rather than relying on
project-wide roles.

None of the three modules makes the state object public. Bucket
policies on S3, Storage Account network rules on Azure, and bucket IAM
on GCS all follow account/project defaults. In production, tighten
each to private subnets or service endpoints.

<!-- BEGIN_TERRAFORM_MODULES -->

## Modules

- [azurerm](azurerm/) — Remote Terraform state on Azure Blob + native lease.
- [gcs](gcs/) — Remote Terraform state on Google Cloud Storage.
- [s3](s3/) — Remote Terraform state on S3 + DynamoDB lock.
<!-- END_TERRAFORM_MODULES -->

## See also

- [Terraform backend docs](https://developer.hashicorp.com/terraform/language/backend) for the upstream backend reference.
- [../cluster/](../cluster/) and [../network/](../network/) for the downstream stacks that read state from the backend.
