---
title: "ADR-0015: RDS admin password via autoGeneratePassword, not Secrets Manager"
description: Switches the demo Instance CR from manageMasterUserPassword (AWS Secrets Manager) to autoGeneratePassword + passwordSecretRef, the same mechanism FlexibleServer already uses — removing an entire IAM identity and the Secrets Manager fetch stage, at the cost of AWS's own automatic password rotation. Revises ADR-0009 §7.
---

# ADR-0015: RDS admin password via autoGeneratePassword, not Secrets Manager

## Status

Proposed, implemented on `feat/provider-sql-app-role` alongside
[ADR-0013](0013-declarative-app-role-provider-sql.md) and
[ADR-0014](0014-database-domain-namespace-consolidation.md). Revises
[ADR-0009](0009-crossplane-cloud-databases.md) §7's choice of
`manageMasterUserPassword`. Not yet verified live.

## Context

ADR-0009 §7 gave RDS's `Instance` a master password managed by AWS
Secrets Manager (`manageMasterUserPassword: true`), and built a bootstrap
identity (`rds-secret-reader`, Pod Identity, `secretsmanager:GetSecretValue`)
specifically to read it back out. At the time, this looked like the only
option — `manageMasterUserPassword` was the field in view, and Azure's
`FlexibleServer` genuinely does support a different mechanism, so RDS
needing to be different wasn't obviously wrong.

Checking the actual pinned provider source (not assumed) turned up
`Instance.spec.forProvider.autoGeneratePassword` + `passwordSecretRef` —
confirmed present at `crossplane-contrib/provider-upjet-aws@v2.7.0`
(`apis/cluster/rds/v1beta3/zz_instance_types.go`), the version this repo's
`v2.7.2` pin descends from. This is the identical mechanism
`FlexibleServer` already uses: generate the password once, write it
directly to a named Kubernetes Secret, no AWS Secrets Manager involved at
all. `ManageMasterUserPassword` and `AutoGeneratePassword` are mutually
exclusive on the same resource.

## Decision

`kustomize/demo/resources/database/rds/instance.yaml` drops
`manageMasterUserPassword: true` for:

```yaml
autoGeneratePassword: true
passwordSecretRef:
  name: demo-db-admin-credentials
  namespace: system-database
  key: password
```

This makes RDS's admin-credential flow byte-for-byte the same shape as
`FlexibleServer`'s. Everything downstream simplifies to match:

- `app-role/connection-secret-cronjob.yaml` and
  `monitoring-cronjob-policy.yaml`'s embedded fetch both drop the
  two-stage `masterUserSecret[0].secretArn` → `aws secretsmanager
  get-secret-value` round trip for a single `kubectl get secret
  <name>-admin-credentials` read, identical to Azure's.
- `terraform/database/aws-rds`'s entire "Secret Reader Role" section —
  the `rds-secret-reader` IAM role, policy (scoped to exactly
  `secretsmanager:GetSecretValue` on `secret:rds!*`, nothing else), and
  its EKS Pod Identity association — is dead code once nothing needs to
  read Secrets Manager. Removed, along with the `cluster_name`/`cluster_arn`
  variables that existed only to build its trust policy, the
  `secret_reader_role_arn` output, and the corresponding `platform-aws.yaml`
  facet inputs.
- `terraform/provisioning/crossplane-iam`'s `rds` catalog entry loses the
  `secretsmanager:CreateSecret`/`secretsmanager:TagResource`/`kms:DescribeKey`
  (against the account's Secrets Manager key) statements — these existed
  because `manageMasterUserPassword: true` makes RDS itself call
  Secrets Manager on `CreateDBInstance`; with `autoGeneratePassword`,
  the password is written by Crossplane's own controller directly to the
  Kubernetes API, needing no AWS IAM grant at all.
- The `rds-secret-reader` k8s ServiceAccount stays — it still needs
  plain Kubernetes RBAC to read/write Secrets in `system-database` and
  read the `Instance` CR — but carries no AWS IAM binding anymore,
  matching `flexibleserver-bootstrap`/`cloudsql-bootstrap`, which never
  had one.

## Consequences

**This is a real regression, not a pure simplification.** ADR-0009 §7
explicitly relied on AWS-managed rotation: *"only the admin credential
rotates, via AWS."* `manageMasterUserPassword` gets automatic rotation
natively from Secrets Manager; `autoGeneratePassword` generates the
password once and writes it to a static Kubernetes Secret that nothing
ever rotates again — the same non-rotating posture Azure and GCP's admin
credentials already have. Presented as an explicit tradeoff, not
discovered after the fact: consistency with the other two drivers and a
materially smaller IAM/credential-fetch surface, traded against AWS
being the one driver that previously had real automatic admin-password
rotation.

- `task test:terraform` passes for `database/aws-rds` and
  `provisioning/crossplane-iam` with the removed resources/variables/
  assertions. `task test:blueprint` passes at 359 cases, including the
  `platform-aws.test.yaml` case asserting `database`'s terraform inputs
  no longer include `cluster_name`/`cluster_arn`.
- Not yet verified live: whether `autoGeneratePassword` behaves
  identically for RDS as it does for FlexibleServer under real load
  (write timing relative to `Instance` reaching `Ready`, matching the
  same race ADR-0013 already documented and built a poll for).

## Alternatives considered

**Keep `manageMasterUserPassword`, accept the asymmetry.** Real option —
this is the one driver with genuine automatic rotation today, and
switching trades that away for a smaller IAM surface and structural
consistency. Rejected in favor of matching Azure/GCP, on the judgment
that consistency across all three drivers (all three CronJobs, all three
`ProviderConfig`-feeding flows shaped identically) is worth more than a
rotation capability that wasn't otherwise being built on top of — no
rotation schedule was configured, no consumer was reacting to rotation
events; it was latent, not actively relied on beyond the initial
generation.

## References

- [ADR-0009](0009-crossplane-cloud-databases.md) §7 — the original
  `manageMasterUserPassword` decision this ADR revises.
- [ADR-0013](0013-declarative-app-role-provider-sql.md) — the
  connection-secret mirror this change simplifies for the `rds` driver.
- `crossplane-contrib/provider-upjet-aws`, `apis/cluster/rds/v1beta3/zz_instance_types.go`
  — `AutoGeneratePassword`/`PasswordSecretRef`/`ManageMasterUserPassword`
  field definitions this ADR's Decision section cites.
