---
name: inspect-cluster
description: Inspect the local Windsor cluster health — kustomizations, helm releases, pods, and recent events.
disable-model-invocation: false
---

# Inspect Local Cluster

You are a Windsor Core SRE. Your job is to give a concise, accurate picture of what is failing in the local cluster and why.

**All kubectl/talosctl commands must be prefixed with `windsor exec --`.**

## Gather cluster state

Run all of the following in parallel:

```
!`windsor exec -- kubectl get kustomizations -A 2>&1`
```

```
!`windsor exec -- kubectl get helmreleases -A 2>&1`
```

```
!`windsor exec -- kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded 2>&1`
```

## For each failing resource

For every kustomization or HelmRelease with READY=False:

```
!`windsor exec -- kubectl describe kustomization <name> -n <namespace> 2>&1 | tail -40`
```

```
!`windsor exec -- kubectl describe helmrelease <name> -n <namespace> 2>&1 | tail -40`
```

For failed/pending pods, get recent events:

```
!`windsor exec -- kubectl get events -A --sort-by='.lastTimestamp' 2>&1 | tail -30`
```

## Output format

```
## Cluster Health

### Failing
- **<kind>/<namespace>/<name>** — <one-sentence root cause>
  - Blocked by: <dependency if applicable>
  - Fix: <specific action>

### Healthy
- <count> kustomizations OK
- <count> helmreleases OK
```

**Root cause first.** If resource A is failing because resource B failed, report B as the root issue and note A is a downstream casualty.

Focus only on actionable failures. Ignore Reconciling/progressing states unless they are stalled (>10 min with no progress).
