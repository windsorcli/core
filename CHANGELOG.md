# Changelog

Breaking config changes worth a manual look before upgrading. Release notes
for everything else are generated from merged PRs.

## Unreleased

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
