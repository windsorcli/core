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

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
