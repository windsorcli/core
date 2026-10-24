---
title: Database
description: In-cluster Postgres with CloudNativePG, and optionally a managed Postgres instance on AWS, Azure, or GCP.
sidebar_order: 2
---

An application such as `my-app` usually needs a Postgres database, and without one it has nowhere to keep its state. The core blueprint can give it one in two ways. [CloudNativePG](https://cloudnative-pg.io/) runs Postgres inside the cluster. [Crossplane](https://www.crossplane.io/) manages a Postgres instance on the platform's cloud from a Kubernetes resource you declare in the cluster. The guides in this category follow one running example: an application `my-app` in the namespace `my-app`, with a database named `my-app-db`.

## Turn on Postgres

You enable both options in a context's `values.yaml`. This file turns on in-cluster Postgres and cloud Postgres together on AWS:

```yaml
platform: aws            # Cloud databases only supported on AWS, Azure, and GCP
database:
  postgres:
    enabled: true        # CloudNativePG in the cluster
    cloud:
      enabled: true      # manage instances on the platform's cloud
```

`database.postgres.enabled` installs CloudNativePG, and `database.postgres.cloud.enabled` installs Crossplane with a provider for the cloud. The two settings are independent, so you can turn on either one alone. Cloud databases are supported only when `platform` is `aws`, `azure`, or `gcp`.

The cloud service Crossplane talks to is the *driver*, set in `database.postgres.cloud.driver`. You rarely set it yourself, because the blueprint picks it from `platform`. Each driver also has its own *in-cluster resource*: the Kubernetes resource kind you create to ask for a database instance. The defaults per platform are listed in this table:

| `platform` | database.postgres.cloud.driver | In-Cluster Resource |
|---|---|---|
| `aws` | [`rds`](rds.md) | `Instance` |
| `azure` | [`azuredb`](azuredb.md) | `FlexibleServer` |
| `gcp` | [`cloudsql`](cloudsql.md) | `DatabaseInstance` |

Each driver page shows the manifest that creates `my-app-db` on that cloud. The [CloudNativePG](cloudnativepg.md) page does the same for the in-cluster option.

## Application roles

Every cloud database places its administrative credentials in the `system-database` namespace, which leaves `my-app`, in its own namespace, with nothing to authenticate with. An *`AppRole`* resource generates a scoped application role and credential for your app on an existing instance. This `AppRole` gives `my-app` a role on the `my-app-db` instance:

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

`spec.instanceName` names the in-cluster resource for the instance, whichever driver created it. `spec.databaseName` names the database on that instance the role gets access to. The credential lands in a Secret in the `AppRole`'s namespace, named after `spec.secretName` when you set it and `<name>-credentials` otherwise. For the `my-app` `AppRole`, the resulting Secret looks like this:

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

`my-app` reads `endpoint`, `port`, `username`, and `password` from this Secret to connect.

> [!NOTE]
> `AppRole` does not work with CloudNativePG. A `Cluster` gets a `<cluster name>-app` Secret from the operator instead, described on the [CloudNativePG](cloudnativepg.md) page.

## Monitoring

Monitoring is on by default and works the same on every driver. When `telemetry.metrics.enabled` is true, which is its default, Core creates a monitor role for each instance and runs a `postgres_exporter` Deployment, Service, and PodMonitor against it. Setting `observability.enabled` adds the Postgres exporter dashboard.

Alert rules depend on `telemetry.alerts.enabled` as well, which is also true by default. With it on, the telemetry add-on installs one set of Prometheus alert rules for [CloudNativePG](cloudnativepg.md#alerts) when `database.postgres.enabled` is true, and another for the Postgres exporter on RDS and Azure. Cloud SQL has the exporter and dashboard but no alert rules yet.

## Demo database

The demo add-on can show all of this working before you write a manifest of your own. With `demo.enabled: true`, the demo deploys a sample database for each enabled driver, with a matching `AppRole` on the cloud drivers. `demo.resources.database` controls this and is on by default. The manifests are in [kustomize/demo/resources/database](../../../kustomize/demo/resources/database).
