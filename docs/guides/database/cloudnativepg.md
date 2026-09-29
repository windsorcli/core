---
title: CloudNativePG
description: In-cluster Postgres through the CloudNativePG operator.
---

CloudNativePG runs Postgres inside the cluster. It works on any platform and needs no cloud account, including on AWS, Azure, and GCP.

## Turn it on

```yaml
database:
  postgres:
    enabled: true
```

When enabled, the CloudNativePG operator is installed in the `system-database` namespace and watches every namespace. Windsor creates no application databases; add-ons that need Postgres, such as Keycloak, create their own `Cluster`.

This setting is independent of `database.postgres.cloud`, so both can be enabled at once.

To launch a database, use the following [Cluster](https://cloudnative-pg.io/documentation/current/cloudnative-pg.v1/#postgresql-cnpg-io-v1-Cluster) manifest:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: my-app-db
  namespace: my-app
spec:
  instances: 2
  bootstrap:
    initdb:
      database: myapp
  storage:
    size: 1Gi
  monitoring:
    enablePodMonitor: true
```

The operator replicates and fails over the instances. Windsor configures no backups; set them in the `Cluster` spec. The operator also generates a `basic-auth` Secret named `<cluster name>-app` (`my-app-db-app` here) in the `Cluster`'s namespace. It holds the username, password, RW service hostname, port, database name, and ready-made connection URIs, and the user owns the database. See [Secrets](https://cloudnative-pg.io/documentation/current/applications/#secrets) in the CloudNativePG docs.

## Topology

The context's `topology` setting changes how the operator itself runs:

- `ha` runs two operator replicas with pod anti-affinity across nodes and adds a PodDisruptionBudget so one replica stays up during node drains.
- `single-node` turns off the operator's leader election, which avoids constant lease writes to etcd on a one-node cluster.

`topology` does not affect your databases. The number of Postgres instances, and therefore whether a database fails over, comes from `spec.instances` on the `Cluster`. A `Cluster` with `instances: 1` is a single Postgres instance on any topology.

## Under the hood

```mermaid
flowchart LR
  flux[Flux helm-controller]
  operator[CloudNativePG operator]
  app[Your App]
  cluster[Cluster CR]
  pg[(Postgres pods)]

  flux ==> operator
  app -->|declares| cluster
  cluster -->|reconciled by| operator
  operator -->|manages| pg
  classDef k8s fill:#DCEBFF,stroke:#326CE5,color:#0B2A5B
  classDef app fill:#DDF3E1,stroke:#2E7D32,color:#123D17
  class flux,operator,cluster,pg k8s
  class app app
```

## Reference

- [kustomize/database](../../../kustomize/database)
- [kustomize/demo/resources/database/cloudnativepg](../../../kustomize/demo/resources/database/cloudnativepg)
- [kustomize/observability](../../../kustomize/observability)
