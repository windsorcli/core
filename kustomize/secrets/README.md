---
title: Secrets add-on
description: External Secrets Operator and its self-hosted or external secrets store.
---

# Secrets

Runtime secret sync into a live cluster: External Secrets Operator (ESO,
the controller) and the store it reads from — self-hosted OpenBao, or a
Vault-API-compatible instance this cluster doesn't own. Same split as
`pki`'s cert-manager/trust-manager: one domain, two tools, two
namespaces, independently enable-able.

## Architecture

```mermaid
flowchart LR
  flux[Flux helm-controller]

  subgraph syssecrets[system-secrets]
    hr_eso[HelmRelease external-secrets]
    ctrl[Deployment controller]
    webhook[Deployment webhook]
  end

  subgraph sysstore[system-secrets-store]
    hr_bao[HelmRelease openbao]
    bao[StatefulSet openbao]
    svc[Service openbao :8200]
    init[Job openbao-init]
    unseal[CronJob openbao-unseal]
    initsecret[Secret openbao-init]
  end

  subgraph sysgateway[system-gateway]
    route[HTTPRoute openbao]
  end

  subgraph anyns[any namespace]
    store[ClusterSecretStore]
    es[ExternalSecret]
    secret[Secret]
  end

  flux --> hr_eso
  flux --> hr_bao
  hr_eso --> ctrl
  hr_eso --> webhook
  hr_bao --> bao
  bao --> svc
  init -. init once .-> bao
  init --> initsecret
  unseal -. resubmit share, no-op on cloud KMS .-> bao
  unseal -. reads .-> initsecret
  route -. private gateway.access only .-> svc
  ctrl -. watches .-> store
  ctrl -. watches .-> es
  ctrl --> secret
  store -. reads .-> bao
```

Enabling `external_secrets` alone installs the controller with nothing
to sync from. Enabling `secrets_store` on top of it (openbao driver)
installs a self-hosted store in its own namespace; the external driver
skips installing anything and just points a `ClusterSecretStore` at an
instance this cluster doesn't run.

## Recipes

### Controller only

```yaml
external_secrets:
  enabled: true
```

### Self-hosted OpenBao

```yaml
external_secrets:
  enabled: true
secrets_store:
  enabled: true
  driver: openbao
```

### Point at a store this cluster doesn't own

```yaml
external_secrets:
  enabled: true
secrets_store:
  enabled: true
  driver: external
  external:
    url: https://vault.example.internal:8200
    kubernetes_auth:
      mount_path: my-cluster
      role: my-cluster-role
```

### Self-hosted OpenBao, monitored, UI on the private gateway

```yaml
external_secrets:
  enabled: true
secrets_store:
  enabled: true
  driver: openbao
telemetry:
  metrics:
    enabled: true
gateway:
  enabled: true
  access: private
```

`openbao/prometheus` and `openbao/gateway` are both purely additive —
neither is required for the store to work, and both key off config this
add-on doesn't own (`telemetry.metrics.enabled`, `gateway.access`)
rather than a knob of their own.

## Operations

`openbao/bootstrap` inits and unseals OpenBao automatically — a Job runs
`bao operator init` once, and a CronJob resubmits the stored Shamir share
after every restart (a no-op on AWS/Azure, where a cloud auto-unseal
driver handles that instead). Configuring the Kubernetes auth method ESO
authenticates against is separate, not-yet-scoped work — the root token
this produces isn't turned into anything scoped yet.

If an `ExternalSecret` stays `SecretSyncedError` with no store found,
check that `secrets_store` is actually enabled and, for the `openbao`
driver, that the instance is unsealed (`kubectl get secret openbao-init
-n system-secrets-store` should exist; check the `openbao-init` Job and
`openbao-unseal` CronJob logs if it doesn't, or if it exists but the pod
stays `0/1`).

If the ESO webhook's admission requests time out, check
`system-secrets` for CrashLoopBackOff pods before assuming a
network-policy or DNS issue; the webhook Service backs both CRD
validation and conversion.

## Security

Both namespaces enforce the `restricted` Pod Security Standard. ESO's
chart ships a `restricted`-compliant `securityContext` by default and
isn't overridden here. OpenBao's chart sets no `securityContext` at
all, so this add-on supplies one explicitly under
`server.statefulSet.securityContext` — `restricted` has no path to
grant `IPC_LOCK`, the capability Vault-family servers otherwise use to
mlock secrets in memory, so OpenBao runs without it under the
stricter PSA level.

OpenBao's listener is TLS-only — no `tls_disable`, cert issued by the
`private` ClusterIssuer (`certificate.yaml`), same pattern as
coredns/etcd. Server-side TLS only, not mutual TLS: ESO authenticates
via OpenBao's own Kubernetes auth method, not a client certificate.
The UI is on by default (`ui.enabled: true` in the HelmRelease values,
a proper chart toggle — not something to flip inside the raw
`standalone.config` block, which only controls whether the server
serves UI assets at all, not whether a Service exposes them).

`openbao/bootstrap`'s root token and (on Shamir platforms) unseal share
land in a plain `openbao-init` Secret in `system-secrets-store`. Whoever
can read Secrets in that namespace has root on the store — an accepted
v0.8.0 tradeoff, not a permanent one. On AWS and Azure, `openbao/aws-kms-unseal`
and `openbao/azure-keyvault-unseal` remove the recurring unseal-share
exposure by moving that key into the platform's own KMS, authenticated
through Pod Identity / Workload Identity — no static credential, no key
material this repo holds. Everywhere else, the Secret is the interim
root-of-trust.

`openbao/dev`'s `admin` userpass user carries the same broad `admin`
policy the root token effectively grants — it's a login convenience, not a
narrower-scoped identity. `secrets_store.admin_password` is a sensitive
schema property, placed as the `openbao-dev-password` Secret via the
facet's `secrets:` block rather than a plaintext substitution.

CRDs for External Secrets Operator are vendored under
`kustomize/crds/external-secrets-<version>/` (`installCRDs: false` in
the HelmRelease values) rather than chart-managed, so Helm never
silently upgrades or deletes them — see `kustomize/crds/`.

<!-- BEGIN_KUSTOMIZE_DOCS -->

## Substitutions

| Name | Required when | Effect |
|---|---|---|
| `external_domain` | `openbao/gateway` is enabled | Hostname domain for the `openbao.<domain>` route. `dns.private_domain` when set, else `dns.public_domain`. |
| `aws_region` | platform is `aws` AND `secrets_store.driver == 'openbao'` | AWS region for the `seal "awskms"` stanza. Sourced from `aws.region`. |
| `openbao_kms_key_id` | platform is `aws` AND `secrets_store.driver == 'openbao'` | KMS key ID for the `seal "awskms"` stanza. Sourced from `terraform_output('cluster', 'openbao_kms_key_id')`. |
| `openbao_tenant_id` | platform is `azure` AND `secrets_store.driver == 'openbao'` | Azure AD tenant ID for the `seal "azurekeyvault"` stanza and the Workload Identity annotation. Sourced from `terraform_output('cluster', 'tenant_id')`. |
| `openbao_client_id` | platform is `azure` AND `secrets_store.driver == 'openbao'` | Client ID of OpenBao's User-Assigned Managed Identity, for the `seal "azurekeyvault"` stanza and the Workload Identity annotation. Sourced from `terraform_output('cluster', 'openbao_client_id')`. |
| `openbao_vault_name` | platform is `azure` AND `secrets_store.driver == 'openbao'` | Name of the dedicated Key Vault holding OpenBao's unseal key, for the `seal "azurekeyvault"` stanza. Sourced from `terraform_output('cluster', 'openbao_key_vault_name')`. |
| `openbao_key_name` | platform is `azure` AND `secrets_store.driver == 'openbao'` | Name of the key OpenBao's Azure Key Vault seal wraps/unwraps with. Sourced from `terraform_output('cluster', 'openbao_key_name')`. |

## Components

| Component | Enable when | Effect |
|---|---|---|
| `external-secrets` | `external_secrets.enabled: true` | Helm release of External Secrets Operator in `system-secrets`. Install-only: manages `ExternalSecret` and `ClusterSecretStore` CRs, creates none of its own. CRDs are vendored under `kustomize/crds/external-secrets-<version>/`, not chart-managed (`installCRDs: false`). |
| `openbao` | `secrets_store.enabled: true` AND `secrets_store.driver == 'openbao'` (default) | Helm release of OpenBao in `system-secrets-store`, plus its server `Certificate` off the `private` ClusterIssuer and the `openbao-ca-trust` Secret the chart's own `BackendTLSPolicy` validates against (`server.gateway.tlsPolicy.enabled: true`, always rendered — inert without an attached HTTPRoute). `openbao-ca-trust` is placed via the facet's `secrets:` block (`terraform_output('pki', 'cert')`), not a Flux substitution — a ConfigMap built that way lost the CA's PEM line breaks. Self-hosted, single-cluster secrets store; standalone mode with file-backed storage on a PVC (depends on `csi`). Ships sealed and uninitialized until `openbao/bootstrap` runs. |
| `openbao/bootstrap` | `secrets_store.enabled: true` AND `secrets_store.driver == 'openbao'` (always, every platform) | One-time init Job plus a recurring unseal CronJob. The Job calls `bao operator init` once (skipped once its output Secret exists) and asks OpenBao's own `/v1/sys/seal-status` for the seal type to init correctly whether it's Shamir or a cloud auto-unseal driver. The CronJob resubmits the stored Shamir share every 2 minutes, no-oping instantly when already unsealed or on a non-Shamir seal. The root token and any Shamir share land in a plain `openbao-init` Secret in `system-secrets-store` — whoever can read Secrets there has root on the store. |
| `openbao/dev` | `dev: true` AND `secrets_store.enabled: true` AND `secrets_store.driver == 'openbao'` | Enables OpenBao's `userpass` auth method and creates a local `admin` user, so the UI is reachable without pasting the root token. Idempotent — skips enabling `userpass` if already present, upserts the policy and user every run. Password comes from `secrets_store.admin_password` (defaults to `openbao`), placed as the `openbao-dev-password` Secret via the facet's `secrets:` block since it's a sensitive schema property, not a plaintext substitution. |
| `openbao/prometheus` | `secrets_store.enabled: true` AND `secrets_store.driver == 'openbao'` AND `telemetry.metrics.enabled: true` | Patches the OpenBao HelmRelease to enable `serverTelemetry.serviceMonitor` (`release: kube-prometheus-stack` discovery labels, `insecureSkipVerify: true` since the scrape target is the same self-signed-CA listener). `unauthenticated_metrics_access` is always on in the base config so the endpoint is scrapable whenever this component is added. |
| `openbao/gateway` | `secrets_store.enabled: true` AND `secrets_store.driver == 'openbao'` AND `gateway.access == 'private'` | Routes `openbao.${external_domain}` through the shared Gateway to the `openbao` Service. Client-side TLS terminates at the gateway; the backend hop to OpenBao's TLS-only listener is covered by the always-rendered `BackendTLSPolicy` from the `openbao` component. |
| `openbao/aws-kms-unseal` | platform is `aws` AND `secrets_store.enabled: true` AND `secrets_store.driver == 'openbao'` | Replaces `server.standalone.config` with the base config plus a `seal "awskms"` stanza, so OpenBao auto-unseals via AWS KMS instead of Shamir. Authenticated through Pod Identity (`create_openbao_kms_role` on the cluster module) — no static credential. |
| `openbao/azure-keyvault-unseal` | platform is `azure` AND `secrets_store.enabled: true` AND `secrets_store.driver == 'openbao'` | Replaces `server.standalone.config` with the base config plus a `seal "azurekeyvault"` stanza, so OpenBao auto-unseals via Azure Key Vault instead of Shamir. |
| `openbao/azure-workload-identity` | platform is `azure` AND `secrets_store.enabled: true` AND `secrets_store.driver == 'openbao'` | Annotates the OpenBao ServiceAccount and labels the pod for Azure Workload Identity, so the SA token exchanges for an Azure AD token scoped to the Key Vault `openbao/azure-keyvault-unseal` wraps/unwraps against (`create_openbao_identity` on the cluster module). |

## Dependencies

| Add-on | Required when | Reason |
|---|---|---|
| `csi` | `secrets_store.enabled: true` AND `secrets_store.driver == 'openbao'` | OpenBao's standalone mode needs a PVC for its file storage backend; the default StorageClass must exist first. |
| `pki-install` | `secrets_store.enabled: true` AND `secrets_store.driver == 'openbao'` | OpenBao's server Certificate is issued by the private ClusterIssuer; cert-manager must be reconciling first. |
| `gateway-resources` | `openbao/gateway` is enabled | The shared Gateway must exist before the HTTPRoute can attach to it. |

<!-- END_KUSTOMIZE_DOCS -->

## See also

- [contexts/_template/facets/addon-external-secrets.yaml](../../contexts/_template/facets/addon-external-secrets.yaml) and [addon-secrets-store.yaml](../../contexts/_template/facets/addon-secrets-store.yaml) for the canonical wiring.
- `kustomize/crds/` for the vendored-CRD convention.
- [kustomize/pki/](../pki/) for the sibling multi-tool, multi-namespace add-on this one follows.
