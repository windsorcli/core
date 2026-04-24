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

`force_destroy` is driven by `var.operation` (set automatically by
Windsor via `TF_VAR_operation`): `false` during apply (protects the
zone), `true` during `windsor destroy` (allows teardown even when the
zone still has records).

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
