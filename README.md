# Core

Core is the foundational blueprint for Windsor: a Kubernetes cluster bundled with the platform components that run on top of it (CNI, ingress, DNS, certificates, GitOps, storage, policy, observability). One command brings the whole thing up the same way, whether you're running it on a laptop, on bare metal, or on AWS or Azure.

It's a foundation for self-hosted services, internal platform teams, and anyone who wants a real Kubernetes environment to develop against without needing a managed cloud account. Install the [Windsor CLI](https://github.com/windsorcli/cli) to drive it, and see [windsorcli.dev](https://windsorcli.dev) for documentation. The blueprint is open source under [MPL 2.0](LICENSE) and runs entirely on your own hardware.

## Where it runs

| Environment | Cluster | Load balancing | Storage |
| --- | --- | --- | --- |
| Local (laptop) | Talos in containers on Docker or [Colima](https://github.com/abiosoft/colima) | none needed | Local volumes |
| Bare metal | Talos on your own hardware or VMs | [MetalLB](https://metallb.universe.tf) or [kube-vip](https://kube-vip.io) | [Longhorn](https://longhorn.io) or [OpenEBS](https://openebs.io) |
| AWS | EKS | AWS Load Balancer Controller | EBS |
| Azure | AKS | (managed) | Azure Disk |

Each environment runs the same blueprint with the same components on top. Only the substrate underneath changes.

## Quick start

You need [Terraform](https://developer.hashicorp.com/terraform/install) and either Docker or [Colima](https://github.com/abiosoft/colima) (on macOS). The CLI tells you about anything else.

```bash
windsor init local
windsor up
```

When that finishes, the cluster is online. Try:

```bash
windsor exec -- kubectl get pods -A
```

You should see Flux, cert-manager, Cilium, and the rest of the platform reconciling.

## What's in it

### Bootstrap and infrastructure (Terraform)

- Cluster modules for [Talos](https://www.talos.dev) (bare metal), AWS EKS, and Azure AKS.
- Network modules for AWS VPC and Azure VNet.
- Compute modules for Docker, used to provision the hosts that Talos runs on for local and bare metal deployments.
- Bootstrap modules for Cilium (CNI) and Flux (GitOps), plus a DNS zone module for the upstream zone.
- Terraform state backends for AWS S3 and Azure Storage.
- A workstation module for preparing a local development environment.

### Inside the cluster (Kustomize)

#### Networking

- The CNI is [Cilium](https://cilium.io), with Hubble, L2 announcements, Prometheus integration, and Gateway API support.
- Ingress is [NGINX](https://github.com/kubernetes/ingress-nginx). [Envoy](https://www.envoyproxy.io) plus the Gateway API handles north-south traffic.
- Load balancing uses MetalLB or kube-vip on bare metal, and the [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/) on EKS.
- DNS uses [CoreDNS](https://coredns.io) in-cluster and [external-dns](https://github.com/kubernetes-sigs/external-dns) to publish records to Route 53, Azure DNS, or other supported providers.

#### Security and policy

- PKI is [cert-manager](https://cert-manager.io) and [trust-manager](https://cert-manager.io/docs/trust/trust-manager/), with ACME public issuers and private issuers for internal certificates.
- Policy is enforced with [Kyverno](https://kyverno.io).

#### Storage and data

- Block storage drivers include AWS EBS, Azure Disk, Longhorn (HA and single-node modes), and OpenEBS.
- Object storage is [MinIO](https://min.io).
- Postgres clusters are managed by [CloudNativePG](https://cloudnative-pg.io), with HA and single-node modes.

#### GitOps

- [Flux](https://fluxcd.io) reconciles the blueprint and anything you deploy on top of it. The cluster manages itself once `windsor up` finishes.

#### Telemetry

Metrics and log collection from across the cluster, wired up before any workloads land.

- [Prometheus](https://prometheus.io) collects and stores metrics, and [metrics-server](https://github.com/kubernetes-sigs/metrics-server) exposes Kubernetes resource metrics for autoscaling and `kubectl top`.
- [Fluent Bit](https://fluentbit.io) and [Filebeat](https://www.elastic.co/beats/filebeat) collect and forward logs from cluster workloads.

#### Observability

Pre-configured analysis and visualization for what telemetry produces, with dashboards already bundled.

- [Grafana](https://grafana.com) ships with pre-built dashboards for Kubernetes, CloudNativePG, ingress, gateway, NGINX, Flux, cert-manager, Cilium, node-level metrics, and more.
- [Elasticsearch](https://www.elastic.co/elasticsearch) with [Kibana](https://www.elastic.co/kibana) provides full-text log search. [Quickwit](https://quickwit.io) is available as a lighter-weight alternative.
- [Fluentd](https://www.fluentd.org) handles log aggregation and routing between collectors and storage backends.

### Example workloads

The repo includes a [demo/](kustomize/demo/) directory with sample applications (Bookinfo, a static site, a database example) wired through ingress, gateway, and storage. Use them to see how applications fit on top of the platform.

## Composing on top

A Windsor blueprint has three top-level directories:

```
core/
├── kustomize/    cluster resources (CNI, ingress, DNS, ...)
├── terraform/    infrastructure (clusters, networks, state)
└── contexts/     per-environment configuration
    ├── _template/
    ├── local/
    └── aws-test/
```

Other blueprints follow the same shape. To set up a new environment, initialize a context against a platform: for example, `windsor init mycluster --platform metal` for bare metal, or `--platform aws` for EKS. Each context picks from a layered set of facets, with `platform-*` choosing the substrate, `option-*` toggling variations (CNI flavor, gateway type, single-node mode, storage backend), and `addon-*` opting into extras (observability stack, private CA, database, object store). Per-context overrides go in `values.yaml`.

## License

[Mozilla Public License 2.0](LICENSE).

## Contributing

Format, test, and scan with `task fmt`, `task test`, and `task scan`. Install the git hooks with `lefthook install`. Tooling versions are pinned in [aqua.yaml](aqua.yaml).
