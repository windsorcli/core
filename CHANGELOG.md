# Changelog

Breaking config changes worth a manual look before upgrading. Release notes
for everything else are generated from merged PRs.

## Unreleased

### The cluster CA is always installed

Every context now runs the `pki/ca` Terraform step and installs
trust-manager, and the `private` ClusterIssuer always signs with the
cluster CA. `pki.enabled` is deprecated and ignored. Contexts that left it
unset or `false` outside dev mode used a selfsigned `private` issuer, so
cert-manager reissues their workload certificates on upgrade.

| Old | New |
| --- | --- |
| `pki.private_ca.cert` | `pki.ca.cert` |
| `pki.private_ca.key` | `pki.ca.key` |

`pki.private_ca` still works as a fallback when `pki.ca` is unset.

### `addons.*` flattened into top-level schema keys

The `addons` namespace is gone. Update `values.yaml`:

| Old | New |
| --- | --- |
| `addons.private_ca.enabled` | `pki.enabled` |
| `addons.private_dns.enabled` | `dns.private.enabled` |
| `addons.observability.*` | `observability.*` |
| `addons.object_store.*` | `object_store.*` |
| `addons.database.*` | `database.*` |

Any `addons:` key left in `values.yaml` now fails schema validation at
`windsor apply`/`windsor test`.

### Hetzner rejects `dns.private_domain`

Hetzner has no private DNS and no internal gateway. A context with
`platform: hetzner` and `dns.private_domain` set now fails composition. Remove
`dns.private_domain` and use `dns.public_domain`. Dev mode is unaffected.
