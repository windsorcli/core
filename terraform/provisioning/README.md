---
title: provisioning
description: IAM and Pod Identity plumbing that lets Crossplane's cloud providers act on the account.
stack_backing: Grants Crossplane AWS access
---

Cloud-provider IAM wiring for Crossplane, engine-specific and separate from
the KMS key [`database`](../database) shares across drivers. See
[`provisioning/crossplane-identity/aws`](crossplane-identity/aws) for the AWS module.

<!-- BEGIN_TERRAFORM_MODULES -->

## Modules

- [crossplane-identity/aws](crossplane-identity/aws/) — IAM and Pod Identity for Crossplane's AWS provider pods.
- [crossplane-identity/azure](crossplane-identity/azure/) — Workload Identity and RBAC for Crossplane's Azure provider pods.
- [crossplane-identity/gcp](crossplane-identity/gcp/) — Workload Identity Federation for Crossplane's GCP provider pods.
<!-- END_TERRAFORM_MODULES -->
