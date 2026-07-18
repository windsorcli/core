---
name: inspect-cluster
description: Inspect the local Windsor cluster health and Flux tuning — kustomizations, helm releases, sources, pods, recent events, suspended/stalled resources, reconciliation intervals, and controller resource usage.
disable-model-invocation: false
---

# Inspect Local Cluster

You are a Windsor Core SRE. Your job is to give a concise, accurate picture of what is failing in the local cluster and why, and to flag anything mistuned in Flux itself (not just what Flux is managing).

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
!`windsor exec -- kubectl get gitrepositories,ocirepositories,helmrepositories -A 2>&1`
```

```
!`windsor exec -- kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded 2>&1`
```

## For each failing resource

For every kustomization, HelmRelease, or source (GitRepository/OCIRepository/HelmRepository) with READY=False, fill in the real name/namespace and run (these are templates, not auto-run — `<name>`/`<namespace>` are not valid shell on their own):

```
windsor exec -- kubectl describe kustomization <name> -n <namespace> 2>&1 | tail -40
windsor exec -- kubectl describe helmrelease <name> -n <namespace> 2>&1 | tail -40
windsor exec -- kubectl describe gitrepository <name> -n <namespace> 2>&1 | tail -40
```

For failed/pending pods, get recent events:

```
!`windsor exec -- kubectl get events -A --sort-by='.lastTimestamp' 2>&1 | tail -30`
```

## Flux tuning pass

Beyond pass/fail, check whether Flux itself is configured sensibly:

**Suspended resources** — a suspended Kustomization/HelmRelease/source silently stops reconciling with no error, which reads as "healthy but stale." Always surface these, they're easy to forget about:

```
!`windsor exec -- kubectl get kustomizations,helmreleases,gitrepositories,ocirepositories,helmrepositories -A -o jsonpath='{range .items[?(@.spec.suspend==true)]}{.kind}{"/"}{.metadata.namespace}{"/"}{.metadata.name}{"\n"}{end}' 2>&1`
```

**Reconciliation intervals** — flag outliers, not the whole list. An interval under 1m on a Kustomization/HelmRelease hammers the API server for no real benefit locally; an interval over ~1h means changes take a long time to land:

```
!`windsor exec -- kubectl get kustomizations,helmreleases,gitrepositories,ocirepositories,helmrepositories -A -o jsonpath='{range .items[*]}{.kind}{"/"}{.metadata.namespace}{"/"}{.metadata.name}{"\t"}{.spec.interval}{"\n"}{end}' 2>&1`
```

**Controller resource usage** — is any Flux controller close to its limits (throttling CPU or at OOM risk)? Windsor Core doesn't put these in a `flux-system` namespace, so select by label instead of a hardcoded namespace:

```
!`windsor exec -- kubectl top pods -A -l app.kubernetes.io/part-of=flux 2>&1`
```

```
!`windsor exec -- kubectl get pods -A -l app.kubernetes.io/part-of=flux -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .spec.containers[*]}{.resources.requests}{" / "}{.resources.limits}{"\t"}{end}{"\n"}{end}' 2>&1`
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
- <count> sources OK

## Flux Tuning
- Suspended: <list, or "none">
- Interval outliers: <resource — interval — why it's an outlier, or "none">
- Controller resource pressure: <controller — observation, or "none">
```

**Root cause first.** If resource A is failing because resource B failed, report B as the root issue and note A is a downstream casualty.

Focus only on actionable failures. Ignore Reconciling/progressing states unless they are stalled (>10 min with no progress). Tuning observations are reported even when nothing is actively failing.
