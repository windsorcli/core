---
title: Database
description: Cloud-managed database infrastructure for application-requested Postgres.
stack_backing: Crossplane-managed Postgres
---

Shared infrastructure for application-requested cloud databases. Today this
is the KMS key, security group, and secret-reader role that back
[`database/aws-rds`](aws-rds) when `database.postgres.driver: rds`.

<!-- BEGIN_TERRAFORM_MODULES -->

## Modules

- [aws-rds](aws-rds/) — KMS encryption key for RDS storage, shared across every database in a context.
- [azure-postgres](azure-postgres/) — Resource group, private DNS zone, NSG, and optional customer-managed key for Azure Database for PostgreSQL Flexible Server.
- [gcp-cloudsql](gcp-cloudsql/) — Private service connection, KMS key, and admin credentials for Cloud SQL.
<!-- END_TERRAFORM_MODULES -->
