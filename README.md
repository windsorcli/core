# Core

Core is a Kubernetes platform shipped as a versioned blueprint. CNI, ingress, GitOps, certificates, storage, and observability are pinned together, tested as a unit, and brought up by a single command on a laptop, on bare metal, on AWS, or on Azure.

Composition compiles to plain Terraform and Kustomize. Nothing proprietary runs in the deployed infrastructure — Core is only present at build time. Each release is tested end to end, and the upgrade path from previous versions is validated atomically in CI before it ships.

Open source under [MPL 2.0](LICENSE). Drive it with the [Windsor CLI](https://github.com/windsorcli/cli). Documentation at [windsorcli.dev](https://windsorcli.dev).

## Where it runs

| Environment | Cluster | Load balancing | Storage |
| --- | --- | --- | --- |
| Local | [Talos](https://www.talos.dev) in Docker or [Colima](https://github.com/abiosoft/colima) | — | Local volumes |
| Bare metal | Talos on hardware or VMs | [MetalLB](https://metallb.universe.tf) or [kube-vip](https://kube-vip.io) | [Longhorn](https://longhorn.io) or [OpenEBS](https://openebs.io) |
| AWS | EKS | AWS Load Balancer Controller | EBS |
| Azure | AKS | (managed) | Azure Disk |

The same blueprint runs in each. Only the substrate underneath changes.

## Quick start

You need [Terraform](https://developer.hashicorp.com/terraform/install) and either Docker or [Colima](https://github.com/abiosoft/colima). The CLI tells you about anything else.

```bash
windsor init local
windsor up
```

This brings up Talos in Docker, the baseline platform, and — because `windsor init local` enables dev mode — the observability stack and a few other addons. When it finishes, the cluster is online:

```bash
windsor exec -- kubectl get pods -A
```

You should see Flux, cert-manager, the gateway, and the rest of the platform reconciling.

## Composition

A Windsor blueprint is a Terraform stack plus Kubernetes manifests, parameterized by conditional fragments called *facets*. Facets declare a `when` expression — `platform == 'aws'`, `addons.observability.enabled == true` — and the Terraform inputs and Kustomize overlays they contribute when the condition holds. The same blueprint retargets across substrates by varying which facets match, not by forking source.

```
core/
├── kustomize/    cluster resources
├── terraform/    infrastructure
└── contexts/     per-environment configuration
    ├── _template/
    ├── local/
    └── aws-test/
```

Each context has a `values.yaml` that describes intent: a compact, schema-validated description of what the operator wants. Facets translate that intent into the specific Terraform inputs and Kustomize overlays that realize it on the chosen substrate. The schema (`contexts/_template/schema.yaml`) defines what values the blueprint accepts.

Initialize a new context against a platform: `windsor init mycluster --platform metal`, or `--platform aws` for EKS.

Other blueprints follow the same shape. They can extend Core, replace it, or compose alongside it. Anyone can publish a blueprint to an OCI registry and reference it from a context.

## Components

**Infrastructure (Terraform).** Cluster modules for Talos, EKS, and AKS. Network modules for AWS VPC and Azure VNet. Bootstrap modules for Cilium (CNI) and Flux (GitOps). Terraform state backends for AWS S3 and Azure Storage.

**Baseline cluster platform.** [Flux](https://fluxcd.io) for GitOps. [cert-manager](https://cert-manager.io) for TLS, with public ACME and selfsigned issuers. [Kyverno](https://kyverno.io) for policy. [Prometheus](https://prometheus.io) and [metrics-server](https://github.com/kubernetes-sigs/metrics-server) for metrics; [Fluent Bit](https://fluentbit.io), [Filebeat](https://www.elastic.co/beats/filebeat), and [Fluentd](https://www.fluentd.org) for logs. [CoreDNS](https://coredns.io) in-cluster, [external-dns](https://github.com/kubernetes-sigs/external-dns) to publish records to Route 53, Azure DNS, or other supported providers.

**CNI.** [Cilium](https://cilium.io) is the default on Talos clusters, including local Colima setups. Docker Desktop falls back to Flannel for runtime compatibility. EKS and AKS use their managed CNIs.

**Gateway driver.** Choose [Envoy](https://www.envoyproxy.io) plus [Gateway API](https://gateway-api.sigs.k8s.io), [NGINX](https://github.com/kubernetes/ingress-nginx) plus the Ingress API, or Cilium Gateway when the CNI is Cilium.

**Load balancing (substrate-dependent).** [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/) on EKS. [MetalLB](https://metallb.universe.tf) or [kube-vip](https://kube-vip.io) on bare metal.

**Storage (substrate-dependent).** Block storage via EBS on EKS, Azure Disk on AKS, [Longhorn](https://longhorn.io) or [OpenEBS](https://openebs.io) on Talos.

**Optional addons.** [trust-manager](https://cert-manager.io/docs/trust/trust-manager/) with a private CA. Self-hosted CoreDNS for private zones. [MinIO](https://min.io) for object storage. Postgres clusters managed by [CloudNativePG](https://cloudnative-pg.io). An observability stack with [Grafana](https://grafana.com) and prebuilt dashboards, [Elasticsearch](https://www.elastic.co/elasticsearch) with [Kibana](https://www.elastic.co/kibana), or [Quickwit](https://quickwit.io) as a lighter alternative.

The [demo/](kustomize/demo/) directory has sample applications wired through ingress, gateway, and storage.

## License

[Mozilla Public License 2.0](LICENSE).

## Contributing

Format, test, and scan with `task fmt`, `task test`, and `task scan`. Install the git hooks with `lefthook install`. Tooling versions are pinned in [aqua.yaml](aqua.yaml).
