# dns/zone/route53

Creates a public Route53 hosted zone for a domain. Kept independent of any
network/cluster module so a domain can be provisioned standalone — useful
for zone-only deployments and for cases where DNS infra has a different
lifecycle than compute.

The zone is consumed by:

- **cert-manager (ACME Route53 solver)** — DNS-01 challenges for Let's
  Encrypt certificates issued via the `public` ClusterIssuer.
- **external-dns** — automatic publication of Gateway / Service hostnames
  as Route53 records.

After apply, point your domain registrar at the `name_servers` output so
public DNS queries resolve through this zone.

`force_destroy` is set to `true` unconditionally so `windsor destroy`
can tear the zone down even when it still has records (ACME challenge
TXTs, external-dns entries) — the AWS provider reads `force_destroy`
from state at delete time, so it has to be persisted from apply.
Matches the `backend/s3` bucket pattern.

## DNSSEC (`enable_dnssec`)

Off by default. When enabled, provisions a us-east-1 KSK KMS key
(`ECC_NIST_P256` / `SIGN_VERIFY`), an `aws_route53_key_signing_key`,
and `aws_route53_hosted_zone_dnssec` set to `SIGNING`. Route53 only
accepts KSK keys from us-east-1 — that's why the module pins a
`us_east_1` provider alias regardless of the deployment region.

After apply, publish the DS record at the domain registrar — the
`ds_record` output exposes `key_tag`, `signing_algorithm_mnemonic`,
`digest_algorithm_mnemonic`, `digest_value`, and the formatted
`ds_record` string. Until that NS-side handoff completes, DNSSEC-
validating resolvers will fail to resolve the zone, so don't enable
this without coordinating with whoever controls the registrar.

## Query logging (`enable_query_logging`)

Off by default. When enabled, provisions a CloudWatch log group at
`/aws/route53/<domain>` in us-east-1 (Route53 only delivers query
logs to us-east-1), a resource policy granting Route53
`logs:CreateLogStream` / `logs:PutLogEvents`, and an
`aws_route53_query_log` binding. Retention defaults to 30 days and is
configurable via `query_log_retention_days`. CloudWatch ingestion
plus storage cost scales with query volume.

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
