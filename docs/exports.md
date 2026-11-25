# Exported config blocks

Core lists these config blocks under `exports:` in `contexts/_template/blueprint.yaml`. Other blueprints, such as the manager, MAY read them. Each block's keys and types are part of core's public interface. Changing a key or type requires a coordinated change in consumers.

## gateway_endpoints

| Key | Type | Meaning |
|---|---|---|
| `internal_ip` | string | Internal gateway address, empty when unset |
| `external_ip` | string | External gateway address, empty when unset |
| `internal_mode` | string | `nodeport` or `loadbalancer` |
| `external_mode` | string | `nodeport` or `loadbalancer` |
| `internal_enabled` | bool | Internal gateway is on |
| `external_enabled` | bool | External gateway is on |
| `external_https` | bool | External gateway serves HTTPS |
| `internal_https` | bool | Internal gateway serves HTTPS |
| `cilium_lb` | bool | Cilium assigns the pool addresses |

## identity_provider

| Key | Type | Meaning |
|---|---|---|
| `realm` | string | Keycloak realm name |
| `display_name` | string | Label shown for the SSO provider |
| `admin_group` | string | Group granted cluster admin |
| `issuer` | string | OIDC issuer URL for external consumers |
| `backchannel_issuer` | string | OIDC issuer URL for in-cluster calls |

Admin credentials are not exported.

## load_balancer

| Key | Type | Meaning |
|---|---|---|
| `driver` | string | Load balancer driver, such as `cilium` or `kube-vip` |
| `mode` | string | `loadbalancer` or `nodeport` |
| `enabled` | bool | A load balancer is in use |
| `controller_required` | bool | A cloud or in-cluster controller must assign addresses |

## cluster_node_counts

| Key | Type | Meaning |
|---|---|---|
| `controlplanes` | number | Control plane node count, at least 1 |
| `workers` | number | Worker node count |
