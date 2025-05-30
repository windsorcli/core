# Mayastor DiskPool Provisioner

A Helm chart that creates DiskPool resources for Mayastor.

## Prerequisites

- Kubernetes cluster with Mayastor installed
- Nodes labeled with `openebs.io/engine=mayastor`

## Installation

```bash
helm install mayastor-pool-provisioner . \
  --set diskPools[0].nodeLabel=openebs.io/engine=mayastor \
  --set diskPools[0].disks[0]=/dev/sdb
```

## Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `diskPools[].nodeLabel` | Node label selector (format: key=value) | `openebs.io/engine=mayastor` |
| `diskPools[].disks` | List of disk paths to use | `[]` |
| `diskPools[].count` | Maximum number of nodes to create pools on | `99999` |
| `diskPools[].poolNamePrefix` | Prefix for pool names | `pool-on-` |
| `diskPools[].protocol` | Storage protocol | `nvmf` |
| `diskPools[].fsType` | Filesystem type | `xfs` |
| `diskPools[].thinProvisioning` | Enable thin provisioning | `true` |
| `diskPools[].stsAffinityGroup` | Enable StatefulSet affinity grouping | `false` |
| `diskPools[].cloneFsIdAsVolumeId` | Clone filesystem ID as volume ID | `false` |
| `diskPools[].resources.requests.memory` | Memory request | `512Mi` |
| `diskPools[].resources.requests.cpu` | CPU request | `100m` |
| `diskPools[].resources.limits.memory` | Memory limit | `1Gi` |
| `diskPools[].resources.limits.cpu` | CPU limit | `500m` |
