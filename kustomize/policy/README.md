---
title: Policy add-on
description: Kyverno admission controller and the cluster's baseline ClusterPolicies.
---

# Policy

Kyverno is the policy engine. The add-on splits across two
Kustomization paths so Flux can reconcile the operator (CRDs +
workloads) before the ClusterPolicy CRs that depend on those CRDs.
`policy-base` installs the Kyverno Helm release, with optional patches
that enable the reports and cleanup controllers. `policy-resources`
applies the baseline ClusterPolicies that this blueprint relies on,
and depends on `policy-base`.

The baseline policies match Pods in `system-*` namespaces and in
namespaces labeled `policy.windsorcli.dev/managed: true`. Workload
namespaces that opt out (label set to `false`) or unlabeled
non-`system-*` namespaces aren't subject to these policies.

## Architecture

```mermaid
flowchart LR
  flux[Flux helm-controller]

  subgraph systempolicy[system-policy]
    kyverno_hr[HelmRelease kyverno]
    admission[admission-controller]
    background[background-controller]
    reports[reports-controller<br/>opt-in]
    cleanup[cleanup-controller<br/>opt-in]
  end

  cp_limits[ClusterPolicy<br/>resource-limits-requests]
  cp_digest[ClusterPolicy<br/>require-image-digest]
  pods[Pods in system-*<br/>or labeled namespaces]

  flux ==> kyverno_hr
  kyverno_hr --> admission & background & reports & cleanup
  admission -.evaluates.-> cp_digest
  background -.evaluates.-> cp_limits
  cp_digest -.matches.-> pods
  cp_limits -.matches.-> pods
```

The admission controller blocks Pod admission when an Enforce policy
fails. The background controller audits existing Pods against Audit
policies and writes Events and PolicyReports (the latter only when
`kyverno/reports` is enabled).

## Recipes

### Baseline (admission + ClusterPolicies)

```yaml
- name: policy-base
  path: policy/base
  components: [kyverno]
  timeout: 30m

- name: policy-resources
  path: policy/resources
  dependsOn: [policy-base]
  components:
    - kyverno/resource-limits-requests
    - kyverno/require-image-digest
  timeout: 5m
```

This is what `policies.enabled: true` materializes (the default).

### With Policy Reports

```yaml
- name: policy-base
  path: policy/base
  components: [kyverno, kyverno/reports]
```

Set `policies.reporting: enabled`. PolicyReport and
ClusterPolicyReport CRs are written for every evaluation, suitable
for ingest by Policy Reporter or Grafana dashboards.

### With Cleanup Policies

```yaml
- name: policy-base
  path: policy/base
  components: [kyverno, kyverno/cleanup]
```

Set `policies.cleanup: enabled`. The blueprint ships no
`CleanupPolicy` CRs out of the box, so enable this only if you intend
to add your own.

<!-- BEGIN_KUSTOMIZE_DOCS -->

## Components — `policy-base`

| Component | Enable when | Effect |
|---|---|---|
| `kyverno` | always | Helm release of Kyverno in `system-policy`. Installs the admission, background, and reports controllers (the cleanup controller is disabled at this layer; opt in via `kyverno/cleanup`). NO_COLOR is set on the admission and background containers. |
| `kyverno/reports` | `policies.reporting == 'enabled'` | Patches the kyverno HelmRelease to set `reportsController.enabled: true` so PolicyReport / ClusterPolicyReport CRs are written for evaluated policies. |
| `kyverno/cleanup` | `policies.cleanup == 'enabled'` | Patches the kyverno HelmRelease to set `cleanupController.enabled: true` so CleanupPolicy / ClusterCleanupPolicy CRs are executed on their cron schedules. Disabled by default because the blueprint ships no CleanupPolicy resources. |

## Components — `policy-resources`

| Component | Enable when | Effect |
|---|---|---|
| `kyverno/resource-limits-requests` | `policies.resource_limits_requests != 'disabled'` | ClusterPolicy `resource-limits-requests` validating (Audit) that every container has CPU and memory `resources.limits` + `resources.requests` set. Matches Pods in `system-*` namespaces and namespaces labeled `policy.windsorcli.dev/managed: true`. Skips `kube-system`. |
| `kyverno/require-image-digest` | `policies.require_image_digest != 'disabled'` | ClusterPolicy `require-image-digest` validating (Enforce) that every container image reference includes a `sha256:` digest (`repo:tag@sha256:…` or `repo@sha256:…`). Same namespace match scope as `resource-limits-requests`. |

<!-- END_KUSTOMIZE_DOCS -->

## See also

- [contexts/_template/facets/platform-base.yaml](../../contexts/_template/facets/platform-base.yaml) for the canonical wiring for both facets.
- [kustomize/policy/resources/kyverno/resource-limits-requests/cluster-policies.yaml](resources/kyverno/resource-limits-requests/cluster-policies.yaml) for the Audit policy.
- [kustomize/policy/resources/kyverno/require-image-digest/cluster-policy.yaml](resources/kyverno/require-image-digest/cluster-policy.yaml) for the Enforce policy.
- Related add-ons: [observability](../observability/) (`grafana/dashboards/*` for Kyverno metrics if added), [cni](../cni/) (depends on `policy-resources` for the cilium/gateway LBIPAM ClusterPolicy).
