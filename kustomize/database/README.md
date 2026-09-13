---
title: Database add-on
description: CloudNativePG operator for in-cluster PostgreSQL.
---

# Database

In-cluster PostgreSQL via the CloudNativePG operator. The add-on installs
the operator only. Actual database clusters are created elsewhere as
`postgresql.cnpg.io/v1` `Cluster` custom resources (see the demo add-on
for a worked example).

`clusterWide: true` means the single operator instance reconciles
`Cluster` CRs in any namespace, so application teams don't need their own
operator per workload namespace.

## Architecture

```mermaid
flowchart LR
  flux[Flux helm-controller]

  subgraph systemdb[system-database]
    operator_hr[HelmRelease cloudnativepg]
    operator_pod[CloudNativePG Operator]
  end

  subgraph anyns[any workload namespace]
    app[App workload]
    svc[Service<br/>read-write / read-only]
    cluster_cr[Cluster CR]
    sts[StatefulSet<br/>postgres instances]
    pvc[(PVC<br/>per instance)]
  end

  csi[(csi default<br/>StorageClass)]

  flux ==> operator_hr --> operator_pod
  operator_pod -.watches.-> cluster_cr
  cluster_cr -.creates.-> sts & svc
  sts --> pvc --> csi
  app ==> svc ==> sts
```

The Operator is the only thing this add-on installs. Cluster CRs and their
StatefulSets live in whatever namespace consumes the database. The demo
add-on places one in `demo-database`.

## Recipes

### Single-node

```yaml
flux:
  - name: database
    dependsOn: [csi]
    install:
      components:
        - cloudnativepg
        - cloudnativepg/single-node
      timeout: 15m
```

### HA cluster

```yaml
flux:
  - name: database
    dependsOn: [csi]
    install:
      components:
        - cloudnativepg
        - cloudnativepg/ha
      timeout: 15m
```

### With observability dashboards

```yaml
flux:
  - name: database
    dependsOn: [csi]
    install:
      components:
        - cloudnativepg
        - cloudnativepg/prometheus
        - cloudnativepg/ha
      timeout: 15m
```

The `cloudnativepg/prometheus` component adds
`dependsOn: kube-prometheus-stack` to the operator HelmRelease, so the
database-install kustomization waits for telemetry-install to be ready
before reconciling.

<!-- BEGIN_KUSTOMIZE_DOCS -->

## Components

| Component | Enable when | Effect |
|---|---|---|
| `cloudnativepg` | `database.postgres.driver == 'cloudnativepg'` | Helm release of CloudNativePG in `system-database`. `clusterWide: true` so the operator reconciles `Cluster` CRs in any namespace. Mutating and validating webhooks default to `failurePolicy: Fail` so misconfigured Clusters are rejected at admission. |
| `cloudnativepg/prometheus` | `database.postgres.driver == 'cloudnativepg'` AND `observability.enabled: true` | Patches the operator HelmRelease to depend on `kube-prometheus-stack` (system-telemetry) and enable `monitoring.podMonitorEnabled: true` with `release: kube-prometheus-stack` discovery labels. |
| `cloudnativepg/ha` | `database.postgres.driver == 'cloudnativepg'` AND `topology == 'ha'` | Patches the operator HelmRelease for HA: `replicaCount: 2`, hostname-key pod anti-affinity, rolling update `maxUnavailable: 1`. Adds a `PodDisruptionBudget` (`minAvailable: 1`) selecting the operator pods. |
| `cloudnativepg/single-node` | `database.postgres.driver == 'cloudnativepg'` AND `topology == 'single-node'` | Patches the operator HelmRelease to append `--leader-elect=false` via `additionalArgs`. The chart unconditionally passes `--leader-elect`; Go's flag parser is last-wins so the override wins. |
| `crossplane/postgres/instance-connection` | a chart opts into `app-role` and/or `monitor-role` — always paired with at least one of them as a peer component | Per-instance admin connection for `provider-sql`: a `ProviderConfig` reading a `<pg_instance_name>-connection` Secret, and the `WatchOperation` that mirrors it — reacting to the instance CR's own changes, copying its endpoint and admin credential into that Secret (reading the admin username from the instance CR's own spec or from its admin credential Secret, depending on the driver). Shared by `app-role` and `monitor-role`, which both need this same admin-level connection. Requires `pg_instance_name`, `pg_crd_apiversion`, `pg_crd_kind`, `pg_endpoint_field`, `pg_username_field`, and `pg_username_from_secret` — the driver's own CRD identity and status field names, supplied as Flux substitutions. Needs `crossplane/function-python` and Crossplane's `--enable-operations` alpha flag (see `kustomize/provisioning`). |
| `crossplane/postgres/app-role` | a chart opts in, combined with `instance-connection` as a peer component — see `kustomize/demo/resources/database/{rds,flexibleserver,cloudsql}` for a worked example | Application-credential provisioning for any `provider-sql`-fronted instance CR, driver-agnostic — the role owns its database, matching CNPG's own default `app` user. The `postgresql.sql.crossplane.io` `Role` (auto-generates its own password, publishes `<pg_instance_name>-<pg_database_name>-app-credentials` via `writeConnectionSecretToRef`), `Database` (adopts the database the driver's own instance component already created, reconciling its `ownerRef` to that `Role`), and a `Grant` giving the admin connection membership in the new role, required by PostgreSQL before it can reassign the database's owner. Requires `pg_instance_name`, `pg_database_name`, `pg_target_namespace`, and `pg_admin_username`. |
| `crossplane/postgres/monitor-role` | a chart opts in, combined with `instance-connection` as a peer component | Read-only monitoring credential for any `provider-sql`-fronted instance CR, driver-agnostic — a `Role` (auto-generates its own password, publishes `<pg_instance_name>-monitor-credentials` via `writeConnectionSecretToRef`) granted the `pg_monitor` role via a `Grant`. Requires `pg_instance_name`. |
| `crossplane/postgres/monitoring-exporter` | a chart opts in, combined with `monitor-role` as a peer component — `telemetry.metrics.enabled` (default true) gates it in `kustomize/demo`'s own facet entry | A `postgres_exporter` Deployment/Service/PodMonitor in `system-database`, driver-agnostic, reading the Secret `monitor-role` publishes. Requires `pg_instance_name`. `PodMonitor` (`monitoring.coreos.com/v1`) only exists once the metrics pipeline vendors prometheus-operator's CRDs. |
| `crossplane/postgres/aws-rds` | `database.postgres.driver == 'rds'` | RDS's own `default` `ProviderConfig` (credentials source `PodIdentity`, so a consuming `Instance` CR needs no `providerConfigRef`), and a Kyverno `ClusterPolicy` that force-sets the `windsorcli.dev/cluster` tag on every `Instance`. No chart opt-in, matching CNPG's own free monitoring. Requires `kustomize/provisioning`'s `Provider` to report Healthy/Installed first. |
| `crossplane/postgres/azure-postgres` | `database.postgres.driver == 'flexibleserver'` | Azure twin of `crossplane/postgres/aws-rds`. The `default` `ProviderConfig` (credentials source `OIDCTokenFile`, so a consuming `FlexibleServer` CR needs no `providerConfigRef`), and a Kyverno `ClusterPolicy` that force-sets `resourceGroupName` on every `FlexibleServer` to the context's dedicated postgres resource group. No chart opt-in, matching CNPG's own free monitoring. |
| `crossplane/postgres/gcp-cloudsql` | `database.postgres.driver == 'cloudsql'` | GCP twin of `crossplane/postgres/aws-rds`. The `default` `ProviderConfig` (credentials source `InjectedIdentity`, so a consuming `DatabaseInstance` CR needs no `providerConfigRef`), and a Kyverno `ClusterPolicy` that force-sets `project` on every `DatabaseInstance` to the context's GCP project. No chart opt-in, matching CNPG's own free monitoring. |

## Dependencies

| Add-on | Required when | Reason |
|---|---|---|
| `csi` | always | PostgreSQL `Cluster` CRs request PVCs for data storage; the default StorageClass must exist before the operator can bring a Cluster up. |

<!-- END_KUSTOMIZE_DOCS -->

## See also

- [contexts/_template/facets/addon-database.yaml](../../contexts/_template/facets/addon-database.yaml) for the canonical wiring and Grafana dashboard patch.
- [contexts/_template/facets/option-single-node.yaml](../../contexts/_template/facets/option-single-node.yaml) for the `cloudnativepg/single-node` patch wiring.
- [kustomize/demo/database/](../demo/database/) for a worked example (a `Cluster` CR named `demo-cluster`).
- Related add-ons: [csi](../csi/), [observability](../observability/) (`grafana/dashboards/cloudnativepg`), [telemetry](../telemetry/).
