local context = std.extVar("context");
local hlp = std.extVar("helpers");

// =============================================================================
// VARIABLE RESOLUTION
// =============================================================================

// Provider mapping
local rawProvider = hlp.getString(context, "provider", "local");
local provider = if rawProvider == "metal" then "local" else rawProvider;
local vmDriver = hlp.getString(context, "vm.driver", "");

// Basic configuration
local blueprintName = hlp.getString(context, "name", "template");
local repositoryUrl = if rawProvider == "local" then "http://git.test/git/" + hlp.getString(context, "projectName", "core") else "";

// =============================================================================
// BLUEPRINT
// =============================================================================

{
  kind: "Blueprint",
  apiVersion: "blueprints.windsorcli.dev/v1alpha1",
  metadata: {
    name: blueprintName,
    description: "This blueprint outlines resources in the " + blueprintName + " context",
  },
  repository: {
    url: repositoryUrl,
    ref: {
      branch: "main",
    },
    secretName: "flux-system",
  },
  sources: [],
  terraform: if provider == "aws" then [
    {
      path: "network/aws-vpc"
    },
    {
      path: "cluster/aws-eks"
    },
    {
      path: "cluster/aws-eks/additions",
      destroy: false
    },
    {
      path: "gitops/flux",
      destroy: false
    }
  ] else if provider == "azure" then [
    {
      path: "network/azure-vnet"
    },
    {
      path: "cluster/azure-aks"
    },
    {
      path: "gitops/flux",
      destroy: false
    }
  ] else [
    {
      path: "cluster/talos",
      parallelism: 1
    },
    {
      path: "gitops/flux",
      destroy: false,
      values: if rawProvider == "local" then {
        git_username: "local",
        git_password: "local",
        webhook_token: "abcdef123456",
      } else {}
    }
  ],
  kustomize: [
    {
      name: "telemetry-base",
      path: "telemetry/base",
      components: [
        "prometheus",
        "prometheus/flux",
        "fluentbit",
        "fluentbit/prometheus"
      ]
    },
    {
      name: "telemetry-resources",
      path: "telemetry/resources",
      components: [
        "metrics-server",
        "prometheus",
        "prometheus/flux",
        "fluentbit",
        "fluentbit/containerd",
        "fluentbit/fluentd",
        "fluentbit/kubernetes",
        "fluentbit/systemd"
      ],
      dependsOn: ["telemetry-base"]
    },
    {
      name: "policy-base",
      path: "policy/base",
      components: ["kyverno"]
    },
    {
      name: "policy-resources",
      path: "policy/resources",
      dependsOn: ["policy-base"]
    },
    {
      name: "pki-base",
      path: "pki/base",
      components: [
        "cert-manager",
        "trust-manager"
      ],
      dependsOn: ["policy-resources"]
    },
    {
      name: "pki-resources",
      path: "pki/resources",
      components: [
        "private-issuer/ca",
        "public-issuer/selfsigned"
      ],
      dependsOn: ["pki-base"]
    },
    {
      name: "ingress",
      path: "ingress",
      components: if provider == "aws" then [
        "nginx",
        "nginx/flux-webhook",
        "nginx/web"
      ] else if vmDriver == "docker-desktop" then [
        "nginx",
        "nginx/nodeport",
        "nginx/coredns",
        "nginx/flux-webhook",
        "nginx/web"
      ] else [
        "nginx",
        "nginx/loadbalancer",
        "nginx/coredns",
        "nginx/flux-webhook",
        "nginx/web"
      ],
      dependsOn: ["pki-resources"],
      cleanup: ["loadbalancers", "ingresses"]
    },
    {
      name: "dns",
      path: "dns",
      components: if provider == "aws" then [
        "external-dns",
        "external-dns/route53"
      ] else if vmDriver == "docker-desktop" then [
        "coredns",
        "coredns/etcd",
        "external-dns",
        "external-dns/localhost",
        "external-dns/coredns",
        "external-dns/ingress"
      ] else [
        "coredns",
        "coredns/etcd",
        "external-dns",
        "external-dns/coredns",
        "external-dns/ingress"
      ],
      dependsOn: if provider == "aws" then [] else ["pki-base"]
    },
    {
      name: "gitops",
      path: "gitops/flux",
      components: ["webhook"],
      dependsOn: ["ingress"]
    }
  ] + (if provider == "aws" then [
    {
      name: "csi",
      path: "csi",
      cleanup: ["pvcs"],
      components: ["aws-ebs"],
      dependsOn: ["gitops"]
    }
  ] else if provider == "local" then [
    {
      name: "csi",
      path: "csi",
      components: [
        "openebs",
        "openebs/dynamic-localpv"
      ],
      dependsOn: ["policy-resources"],
      cleanup: ["pvcs"]
    }
  ] + (if vmDriver != "docker-desktop" then [
    {
      name: "lb-base",
      path: "lb/base",
      components: ["metallb"],
      dependsOn: ["policy-resources"]
    },
    {
      name: "lb-resources",
      path: "lb/resources",
      components: ["metallb/layer2"],
      dependsOn: ["lb-base"]
    }
  ] else []) else []) + [
    {
      name: "observability",
      path: "observability",
      components: [
        "fluentd",
        "fluentd/filters/otel",
        "fluentd/outputs/quickwit",
        "quickwit",
        "quickwit/pvc",
        "grafana",
        "grafana/ingress",
        "grafana/prometheus",
        "grafana/node",
        "grafana/kubernetes",
        "grafana/flux",
        "grafana/quickwit"
      ],
      dependsOn: ["csi"]
    }
  ],
}
