---
title: Database
description: In-cluster Postgres with CloudNativePG, and optionally a managed Postgres instance on AWS, Azure, or GCP.
sidebar_order: 2
---

The core blueprint supports Postgres database management. In-cluster databases are provided by [CloudNativePG](https://cloudnative-pg.io/). In-cluster management of cloud databases is provided by [Crossplane](https://www.crossplane.io/). The following config can be placed in a context's `values.yaml` file to enable both.

```yaml
platform: aws            # Cloud databases only supported on AWS, Azure, and GCP
database:
  postgres:
    enabled: true        # CloudNativePG in the cluster
    cloud:
      enabled: true      # manage instances on the platform's cloud
```

Depending on platform, the database driver is set to one of these defaults:

| `platform` | database.postgres.cloud.driver | In-Cluster Resource |
|---|---|---|
| `aws` | [`rds`](rds.md) | `Instance` |
| `azure` | [`azuredb`](azuredb.md) | `FlexibleServer` |
| `gcp` | [`cloudsql`](cloudsql.md) | `DatabaseInstance` |

## Application roles

Cloud databases each place administrative credentials in the `system-database` namespace. In order for your application to authenticate, an `AppRole` resource
can be used to generate a scoped application role and credential for your app:

```yaml
apiVersion: database.windsorcli.dev/v1alpha1
kind: AppRole
metadata:
  name: my-app
  namespace: my-app
spec:
  instanceName: my-app-db         # name of the Instance, FlexibleServer, or DatabaseInstance
  databaseName: myapp
  # secretName: my-app-db-credentials   # optional; defaults to <name>-credentials
```

The resulting Secret:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: my-app-credentials
  namespace: my-app
stringData:
  endpoint: <instance-endpoint>
  port: "5432"
  username: my-app
  password: <generated>
```

> **Note:** `AppRole` does not work with CloudNativePG. A `Cluster` gets a `<cluster name>-app` Secret from the operator instead, described on the [CloudNativePG](cloudnativepg.md) page.

## Monitoring

When `telemetry.metrics.enabled` is true (the default), Core creates a monitor role for each instance and runs a `postgres_exporter` Deployment, Service, and PodMonitor against it. `observability.enabled` adds the Postgres exporter dashboard.

When `telemetry.alerts.enabled` is also true (the default), the telemetry add-on installs Prometheus alert rules: one set for [CloudNativePG](cloudnativepg.md#alerts) when `database.postgres.enabled` is true, and one for the Postgres exporter on RDS and Azure. Cloud SQL has the exporter and dashboard but no alert rules yet.

## Demo database

With `demo.enabled: true`, the demo deploys a sample database for each enabled driver, with a matching `AppRole` on the cloud drivers. `demo.resources.database` controls this and is on by default. The manifests are in [kustomize/demo/resources/database](../../../kustomize/demo/resources/database).
