# Exported config blocks

Core lists these config blocks under `exports:` in `contexts/_template/blueprint.yaml`. Other blueprints, such as the manager, MAY read them. Each block's keys and types are part of core's public interface. Changing a key or type requires a coordinated change in consumers.

## gateway_endpoints

| Key | Type | Meaning |
|---|---|---|
| `internal_ip` | string | Internal gateway address, empty when unset |
| `external_ip` | string | External gateway address, empty when unset |
| `internal_mode` | string | `nodeport` or `loadbalancer` |
| `external_mode` | string | `nodeport`, `clusterip` or `loadbalancer` |
| `internal` | bool | An internal gateway exists |
| `internal_enabled` | bool | Internal gateway is on |
| `external_enabled` | bool | External gateway is on |
| `external_https` | bool | External gateway serves HTTPS |
| `internal_https` | bool | Internal gateway serves HTTPS |
| `cilium_lb` | bool | Cilium assigns the pool addresses |
| `public` | object | Route target for browser- and remote-facing services |
| `public.name` | string | `external`, `internal`, or empty when no gateway serves |
| `public.domain` | string | Domain for public routes |
| `public.ip` | string | Address of the public route target, empty when unset |
| `private` | object | Route target for operator-only services |
| `private.name` | string | `internal`, or empty when no internal gateway exists |
| `private.domain` | string | Domain for private routes, empty when no internal gateway exists |
| `private.ip` | string | Address of the private route target, empty when unset |
| `listener_hostports` | list of strings | Docker-desktop host port mappings, `port:port/tcp` entries |
| `external_listener_ports` | string | One-line JSON array of Service ports for the external gateway's `node_ports` |
| `internal_listener_ports` | string | One-line JSON array of Service ports for the internal gateway's `node_ports` |

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
