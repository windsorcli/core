# Windsor Destroy Routine

Design for a reliable, idempotent, cloud-agnostic teardown of a Windsor blueprint.

## Problem

`windsor destroy` today applies a single `cleanup` Kustomization at the start of teardown, which deletes PVCs / Ingresses / LoadBalancer Services in context-labeled namespaces, then proceeds to prune HelmReleases and finally `terraform destroy` the cluster and infra. The model has structural gaps:

- The cleanup pass deletes PVCs while their consumer workloads are still running. The CSI external-attacher / external-provisioner finalizers on the resulting PVs cannot lift (volume still mounted), so PVs sit in `Terminating` indefinitely. When `terraform destroy` later removes the cluster, AWS keeps the underlying EBS volumes as orphans because nothing called `DeleteVolume`.
- Same shape for Service `type=LoadBalancer`: if the AWS LB controller's HelmRelease prunes before the Service is fully released, the NLB orphans in AWS.
- Operator-managed CRs (`Fluentd`, `Certificate`, etc.) have no `ownerReferences` to the operator that reconciles them. Pruning the operator first leaves the CRs and their materialized children as eternal orphans.
- The cleanup Job strips `pvc-protection` / `pv-protection` finalizers (safe), but cannot strip CSI-side finalizers without leaking cloud resources — so when a PV is stuck on a CSI finalizer, the cleanup Job is silently powerless.
- Add-on teardown order is implicit. The dependency graph is encoded in the blueprint's `dependsOn`, but the destroy path doesn't reverse-walk it; pruning happens in arbitrary controller-driven order.

These are not bugs in any one component. They are the cost of using a level-triggered reconciliation system (K8s + Flux) for an inherently ordered procedure (teardown). K8s has no built-in destroy orchestrator. Every platform that operates stateful workloads with cloud integration ends up writing one.

## Principle

Teardown is the same dependency graph as apply, walked in the opposite direction. Each step waits for *real termination* — the K8s object is gone from etcd — not for a deletion timestamp to be set. K8s finalizers are the cloud-agnostic abstraction for "external state has been released": every cloud controller adds a finalizer to its K8s object when it provisions external state and removes it only after the external state is destroyed. Waiting for `kubectl get <kind>/<name>` to return `NotFound` is therefore equivalent to waiting for the cloud-side resource to be gone, on any provider, without the orchestrator ever calling a cloud API.

## Algorithm

The CLI is the orchestrator. Flux is the executor.

```
suspend Flux GitRepository / Kustomization controller-side reconciliation
for node N in reverse-topological-sort(blueprint.dependsOn):
    footprint = derive(N)
    quiesce(footprint.workloads)
    cascade(footprint.crs)
    release(footprint.handles)
    prune(N)
    verify(N's footprint absent from K8s)
verify(no objects labeled context-id=<ctx> remain in K8s)
for node N in reverse-topological-sort(blueprint.terraform.dependsOn):
    terraform destroy
```

Each step is "make state == gone," not "do this action." Re-running destroy after a partial failure walks the same graph; nodes already gone are skipped, in-flight ones are resumed. Idempotency is a property of the algorithm, not a feature bolted on.

## Universal primitives

Every Kubernetes resource a Windsor blueprint produces fits one of four categories. The teardown rules between them are general, not per-node:

| Primitive | Examples | Rule |
|---|---|---|
| **Owner** | HelmRelease, operator Deployment, CRD-defining controller | Outlives anything it owns. |
| **Workload** | Deployment, StatefulSet, DaemonSet, Job | Releases its mounts/network before its Resources can delete. |
| **Resource** | PVC, Secret, ConfigMap | Workloads release first, then deletes. |
| **External handle** | `Service type=LB`, `PV` (CSI), `Ingress`, `Certificate`, `DNSEndpoint` | Cloud controller's finalizer keeps the object in etcd until external state is gone. Wait for `NotFound`. |

The orchestrator does not need to know which controller manages which kind. It needs to know that a finalizer on an object means "wait for the controller to lift it" and that the object disappearing from the API means "the external state is gone."

## `derive(N)` — discovering a node's footprint

Everything required is data Kubernetes already exposes:

- **Flux inventory.** Every `Kustomization` has `status.inventory.entries` listing the GVKs and names it manages. Every `HelmRelease` has the equivalent via `helm get manifest`.
- **CRs of node-owned CRDs.** If the inventory contains a `CustomResourceDefinition`, every instance of that CRD cluster-wide is part of the node's footprint for cascade purposes.
- **Workloads in target namespaces.** `kubectl get sts,deploy,ds,job -n <ns>` filtered by `ownerReferences` chained back to the inventory.
- **External handles.** Inventory entries of kind `Service` (with `spec.type == LoadBalancer`), `PersistentVolumeClaim`, `Ingress`, `Certificate`, `DNSEndpoint`, etc.

No per-node configuration is required to derive the footprint. The blueprint already declares what each node installs; Flux already tracks what it materialized.

## `quiesce` — drain workloads

For every workload in the footprint:

1. Patch `spec.replicas: 0` (Deployment, StatefulSet) or delete (DaemonSet, Job).
2. Wait until `kubectl get pods -l <selector>` returns an empty set in the target namespaces.

This is the step that fixes the stuck-PV class of bug. By the time `quiesce` returns, no pod in the node's namespaces is mounting any PVC.

## `cascade` — delete operator-managed CRs

For every CRD the node introduced:

1. `kubectl delete <crd>.<group> --all -A` (or scoped to the node's namespaces if the CRs are namespaced and the node is namespace-scoped).
2. Wait until no instances remain.

This deletes children of operators *before* the operator itself prunes — fixing the `Fluentd` / `Certificate` / `Subscription` orphan class.

## `release` — delete external handles, wait for actual disappearance

For each external-handle entry in the footprint:

1. Issue the delete (`kubectl delete pvc/svc/ingress/...`).
2. Wait until `kubectl get` returns `NotFound`.

The wait is the whole point. The cloud controller's finalizer is what keeps the object in etcd until it has confirmed external-side cleanup. We trust the contract: when the object is gone, the cloud resource is gone.

If the wait times out, the controller is buggy or a consumer wasn't quiesced. Both are K8s-visible problems with K8s-visible fixes. **The orchestrator does not strip CSI / cloud-controller finalizers.** Doing so would leak external state and is the failure mode the current design exhibits.

## `prune` — delete the node itself

1. Delete the `Kustomization` (or `HelmRelease`).
2. Wait for Flux's inventory to clear and for `Kustomization` itself to be `NotFound`.

Reverse-DAG order ensures that by the time a node prunes, every node depending on it has already pruned — meaning every consumer of the controllers this node provides is already gone, so the controllers can shut down without orphaning anyone.

## `verify` — defense-in-depth audit

After the in-cluster walk completes:

1. Across all namespaces labeled `windsorcli.dev/context-id=<ctx>`, confirm zero of: `Pod`, `PVC`, `PV` (with claimRef into a context ns), `Service type=LB`, `Ingress`, `Certificate`, `DNSEndpoint`.
2. Confirm zero CRs of context-introduced CRDs cluster-wide.
3. If anything remains, fail loudly with the offending object listed. Do not strip finalizers.

This is not where leaks should be caught — by construction, the algorithm should leave nothing behind. The verify phase exists to make orchestrator bugs visible before they become billing surprises.

## Terraform reverse traversal

Once the cluster is empty:

1. Walk `blueprint.terraform.dependsOn` in reverse topological order.
2. `terraform destroy` each stack.

Because Phase 1–6 left no PVs / LBs / ENIs hanging off the cluster, EKS / AKS node group destruction completes without volume-detach hangs and without LB-deletion timeouts. The cluster stack destroys cleanly. Network destroys cleanly. The backend stack destroys last, with `force_destroy = var.operation == "destroy"` letting the state bucket release its versioned contents.

## Idempotency

Every step is phrased as "ensure state matches absent," not "perform this delete." Re-running destroy after any failure mode:

- Walks the same reverse-DAG.
- For each node, checks whether its `Kustomization`/`HelmRelease` still exists. If not, skips.
- For partially-quiesced or partially-released nodes, picks up where the previous run left off — `quiesce` is idempotent (scaling 0→0 is a no-op), `cascade` skips already-deleted CRs, `release` waits on whatever is still present.
- `terraform destroy` is already idempotent.

There is no state file the orchestrator maintains. The K8s API + Flux inventory + Terraform state are the source of truth.

## Per-node escape hatches

Most blueprint entries declare nothing destroy-related. The few that need to override defaults can use:

| Field | Purpose |
|---|---|
| `destroy: false` | Skip this node entirely on destroy. Already supported. |
| `destroyTimeout: <duration>` | Override the default wait window for slow controllers. |
| `destroyPolicy: orphan` | Leave this node's resources behind on purpose. Rare; mostly for shared infra a context doesn't own. |
| `preDestroy: <inline kubectl>` | Custom command to run before `quiesce`. Escape hatch for genuinely bespoke choreography. Should be rare; if many nodes need it, the universal algorithm is missing a primitive. |

## Worked examples

### Stuck `fluentd` PV (the bug that motivated this design)

Today: cleanup deletes `fluentd-buffer-pvc-fluentd-0` while `fluentd-0` pod is still running. CSI finalizers on the PV cannot lift. PV sits in `Terminating` for hours.

Under the new algorithm:
1. Reverse-DAG places the `observability` node before `telemetry-base`, `cluster`, `cni`, etc.
2. `derive(observability)` reads the Flux inventory, sees the `Fluentd` CRD instance.
3. `cascade` deletes the `Fluentd` CR. fluent-operator reconciles, deletes the StatefulSet.
4. `quiesce` waits until no pods remain in `system-observability`.
5. `release` deletes any leftover PVCs; CSI external-attacher detaches the volume (fluentd-0 is gone), external-provisioner calls `DeleteVolume`, finalizers lift, PV is `NotFound`.
6. `prune` deletes the `observability` Kustomization.
7. Walk continues to `telemetry-base`, eventually to `cluster` add-ons including EBS CSI — which is still alive throughout because nothing depends on it being gone yet.

No bespoke per-node config. The fix falls out of the universal walk.

### `Service type=LoadBalancer` orphaning an NLB

Today: AWS LB controller HelmRelease prunes before the consuming Service is fully released. NLB orphans in AWS.

Under the new algorithm:
1. The node owning the Service depends transitively on the `aws-lb-controller` node via its consumer relationship (or explicitly via `dependsOn`).
2. Reverse-DAG ensures the consumer's `release` step runs first.
3. `release` deletes the Service and waits for `NotFound`. The AWS LB controller's finalizer (`service.kubernetes.io/load-balancer-cleanup`) holds the object in etcd until the AWS API confirms NLB deletion.
4. Service is `NotFound`. NLB is gone. Only then does the walk reach the `aws-lb-controller` node and prune it.

Cloud-agnostic: the same algorithm works on Azure (Azure LB controller's finalizer), on metal (MetalLB's finalizer), on any future provider whose controller follows the K8s finalizer contract.

### `Certificate` orphaning after cert-manager prunes

Today: cert-manager HelmRelease prunes; `Certificate` CRs become orphans; their `Secret`s linger; ACME records may leak.

Under the new algorithm:
1. `derive(pki-base)` finds the `Certificate` / `Order` / `Challenge` CRDs in cert-manager's inventory.
2. `cascade` deletes all instances cluster-wide. cert-manager reconciles, revokes certificates upstream where applicable, deletes Secrets it owns.
3. `quiesce` is a no-op for cert-manager itself (no workloads to drain beyond the controller pod, which prunes naturally).
4. `prune` removes the cert-manager Kustomization.

## What stays from today's system

- Blueprint format, `dependsOn`, the per-context configuration model.
- Flux as the in-cluster reconciliation engine.
- The CLI's role as orchestrator across terraform stacks and kustomize entries.
- `destroy: false` flag on entries that should not be torn down (`cluster-additions`, `gitops`).
- The existing `cleanup` Kustomization, repurposed as the `verify` phase — a defense-in-depth audit, not the primary teardown mechanism.
- The `force_destroy = var.operation == "destroy"` pattern on the S3 backend stack.

## What changes

| Area | Today | Proposed |
|---|---|---|
| When does cleanup run? | Single up-front pass before any other prune. | Per-node, interleaved with reverse-DAG walk. |
| What waits on what? | `--wait=false` everywhere; finalizer-strip-and-pray. | Wait for `NotFound` on every external handle. |
| How is order enforced? | Implicit; Flux prunes Kustomizations in arbitrary order. | Explicit reverse-topological sort of `dependsOn`. |
| Operator CRs | Orphaned when operator prunes. | Cascade-deleted before operator prunes. |
| Add-on teardown | Implicit (and wrong). | Reverse-DAG ensures controllers outlive their consumers. |
| Cloud-side leaks | Silent until billing. | Either prevented by construction or surfaced as wait timeouts during destroy. |
| Cloud SDK in orchestrator | None today, but proposed in earlier drafts. | None. Pure K8s API. Cloud-agnostic. |
| Idempotent re-run | Partial. | By construction. |

## Implementation surface

The new code is small relative to the existing CLI:

1. Reverse-topological-sort over the blueprint DAG. The CLI already builds the forward sort for apply.
2. A small library of "wait for K8s state" probes — pod count by selector, `kubectl get` returning `NotFound`, Flux inventory empty. These are kind-agnostic; one set of probes serves every node.
3. Per-step orchestration: `quiesce`, `cascade`, `release`, `prune`, `verify`. Each is a thin wrapper around kubectl-equivalent API calls.
4. Suspend/resume of Flux controllers at the boundaries.

No new CRDs. No new controllers. No cloud SDKs. No per-resource-kind probe library beyond "is it gone." The algorithm derives what to do from data K8s already exposes.

## Tradeoffs

- **More orchestration than today.** This is meaningful new code in the CLI. The payoff is that destroy becomes the same kind of thing as apply — declarative, debuggable, resumable — instead of a one-shot script-and-pray.
- **Trusts the controllers.** A controller that doesn't lift its finalizer correctly will manifest as a wait timeout. This is loud and debuggable, but it does mean orchestrator correctness depends on every cloud controller in the stack honoring the K8s finalizer contract. In practice they all do — this is the contract K8s itself defines.
- **No ad-hoc finalizer stripping.** The current cleanup Job's "strip pvc-protection" path can stay (it's safe and sometimes needed when a PVC is stuck because of a bound PV that's been release-deleted), but stripping CSI / cloud-controller finalizers is forbidden. If the algorithm is correct, it isn't needed; if the algorithm fails, stripping silently leaks external state and is the wrong escape hatch.
- **No cloud-side audit during destroy.** Tag-based checks against AWS / Azure to find orphans are a useful billing/security layer, but they live elsewhere — outside the destroy pipeline. The destroy pipeline's correctness is provable by inspection of the K8s API alone.

## References

- HashiCorp Terraform: dependency graph and reverse-traversal destroy semantics.
- Kubernetes finalizers: <https://kubernetes.io/docs/concepts/overview/working-with-objects/finalizers/>
- Flux Kustomization inventory: <https://fluxcd.io/flux/components/kustomize/kustomizations/#inventory>
- Cluster API: ownerReferences-based cascading delete for cluster lifecycle.
- Crossplane composition functions: ordered deletion via composition lifecycle.
- ArgoCD sync waves and prune propagation: per-resource ordering for both sync and prune.
