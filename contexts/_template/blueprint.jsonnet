local context = std.extVar("context");
local hlp = std.extVar("helpers");

// Map "metal" provider to "local" for template purposes
local rawProvider = hlp.getString(context, "provider", "local");
local provider = if rawProvider == "metal" then "local" else rawProvider;

// Repository configuration
local repositoryConfig = {
  url: if rawProvider == "local" then "http://git.test/git/" + hlp.getString(context, "projectName", "core") else "",
  ref: {
    branch: "main",
  },
  secretName: "flux-system",
};

// Platform-specific terraform configurations
local terraformConfigs = {
  "aws": [
    {
      path: "backend/s3",
    },
    {
      path: "network/aws-vpc",
    },
    {
      path: "cluster/aws-eks",
    },
    {
      path: "cluster/aws-eks/additions",
      destroy: false
    },
    {
      path: "gitops/flux",
      destroy: false,
    }
  ],
  "azure": [
    {
      path: "backend/azurerm",
    },
    {
      path: "network/azure-vnet",
    },
    {
      path: "cluster/azure-aks",
    },
    {
      path: "gitops/flux",
      destroy: false,
    }
  ],
  "local": [
    {
      path: "cluster/talos",
      parallelism: 1,
    },
    {
      path: "gitops/flux",
      destroy: false,
      values: if rawProvider == "local" then {
        git_username: "local",
        git_password: "local",
        webhook_token: "abcdef123456",
      } else {},
    }
  ]
};

// Determine the vmDriver for conditional logic in local configs
local vmDriver = hlp.getString(context, "vm.driver", "");

// Platform-specific kustomize configurations
local kustomizeConfigs = {
  "aws": [
    {
      name: "telemetry-base",
      path: "telemetry/base",
      components: [
        "prometheus",
        "prometheus/flux"
      ],
    },
    {
      name: "telemetry-resources",
      path: "telemetry/resources",
      dependsOn: [
        "telemetry-base"
      ],
      components: [
        "metrics-server",
        "prometheus",
        "prometheus/flux"
      ],
    },
    {
      name: "policy-base",
      path: "policy/base",
      components: [
        "kyverno"
      ],
    },
    {
      name: "policy-resources",
      path: "policy/resources",
      dependsOn: [
        "policy-base"
      ],
    },
    {
      name: "csi",
      path: "csi",
      cleanup: [
        "pvcs"
      ],
    },
    {
      name: "ingress",
      path: "ingress",
      dependsOn: [
        "pki-resources"
      ],
      components: [
        "nginx",
        "nginx/flux-webhook",
        "nginx/web"
      ],
      cleanup: [
        "loadbalancers",
        "ingresses"
      ],
    },
    {
      name: "pki-base",
      path: "pki/base",
      dependsOn: [
        "policy-resources"
      ],
      components: [
        "cert-manager",
        "trust-manager"
      ],
    },
    {
      name: "pki-resources",
      path: "pki/resources",
      dependsOn: [
        "pki-base"
      ],
      components: [
        "private-issuer/ca",
        "public-issuer/selfsigned"
      ],
    },
    {
      name: "dns",
      path: "dns",
      components: [
        "external-dns",
        "external-dns/route53"
      ],
    },
    {
      name: "observability",
      path: "observability",
      dependsOn: [
        "ingress"
      ],
      components: [
        "grafana",
        "grafana/ingress",
        "grafana/prometheus",
        "grafana/node",
        "grafana/kubernetes",
        "grafana/flux"
      ],
    }
  ],
  "azure": [
    {
      name: "telemetry-base",
      path: "telemetry/base",
      components: [
        "prometheus",
        "prometheus/flux"
      ],
    },
    {
      name: "telemetry-resources",
      path: "telemetry/resources",
      dependsOn: [
        "telemetry-base"
      ],
      components: [
        "prometheus",
        "prometheus/flux"
      ],
    },
    {
      name: "policy-base",
      path: "policy/base",
      components: [
        "kyverno"
      ],
    },
    {
      name: "policy-resources",
      path: "policy/resources",
      dependsOn: [
        "policy-base"
      ],
    },
    {
      name: "pki-base",
      path: "pki/base",
      dependsOn: [
        "policy-resources"
      ],
      components: [
        "cert-manager",
        "trust-manager"
      ],
    },
    {
      name: "pki-resources",
      path: "pki/resources",
      dependsOn: [
        "pki-base"
      ],
      components: [
        "private-issuer/ca",
        "public-issuer/selfsigned"
      ],
    },
    {
      name: "ingress",
      path: "ingress",
      dependsOn: [
        "pki-resources"
      ],
      components: [
        "nginx",
        "nginx/flux-webhook",
        "nginx/web"
      ],
    },
    {
      name: "gitops",
      path: "gitops/flux",
      dependsOn: [
        "ingress"
      ],
      components: [
        "webhook"
      ],
    },
    {
      name: "observability",
      path: "observability",
      dependsOn: [
        "ingress"
      ],
      components: [
        "grafana",
        "grafana/ingress",
        "grafana/prometheus",
        "grafana/node",
        "grafana/kubernetes",
        "grafana/flux"
      ],
    }
  ],
  "local": [
    {
      name: "telemetry-base",
      path: "telemetry/base",
      components: [
        "prometheus",
        "prometheus/flux",
        "fluentbit",
        "fluentbit/prometheus"
      ],
    },
    {
      name: "telemetry-resources",
      path: "telemetry/resources",
      dependsOn: [
        "telemetry-base"
      ],
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
    },
    {
      name: "policy-base",
      path: "policy/base",
      components: [
        "kyverno"
      ],
    },
    {
      name: "policy-resources",
      path: "policy/resources",
      dependsOn: [
        "policy-base"
      ],
    },
    {
      name: "csi",
      path: "csi",
      dependsOn: [
        "policy-resources"
      ],
      components: [
        "openebs",
        "openebs/dynamic-localpv"
      ],
    },
  ] + (if vmDriver != "docker-desktop" then [
    {
      name: "lb-base",
      path: "lb/base",
      dependsOn: [
        "policy-resources"
      ],
      components: [
        "metallb"
      ],
    },
    {
      name: "lb-resources",
      path: "lb/resources",
      dependsOn: [
        "lb-base"
      ],
      components: [
        "metallb/layer2"
      ],
    }
  ] else []) + [
    {
      name: "ingress",
      path: "ingress",
      dependsOn: [
        "pki-resources"
      ],
      components: if vmDriver == "docker-desktop" then [
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
    },
    {
      name: "pki-base",
      path: "pki/base",
      dependsOn: [
        "policy-resources"
      ],
      components: [
        "cert-manager",
        "trust-manager"
      ],
    },
    {
      name: "pki-resources",
      path: "pki/resources",
      dependsOn: [
        "pki-base"
      ],
      components: [
        "private-issuer/ca",
        "public-issuer/selfsigned"
      ],
    },
    {
      name: "dns",
      path: "dns",
      dependsOn: [
        "pki-base"
      ],
      components: if vmDriver == "docker-desktop" then [
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
    },
    {
      name: "gitops",
      path: "gitops/flux",
      dependsOn: [
        "ingress"
      ],
      components: [
        "webhook"
      ],
    }
  ]
};

// Blueprint metadata
local blueprintMetadata = {
  kind: "Blueprint",
  apiVersion: "blueprints.windsorcli.dev/v1alpha1",
  metadata: {
    name: hlp.getString(context, "name", "template"),
    description: "This blueprint outlines resources in the " + hlp.getString(context, "name", "template") + " context",
  },
};

// Source configuration
local sourceConfig = [];

// Start of Blueprint
blueprintMetadata + {
  repository: repositoryConfig,
  sources: sourceConfig,
  terraform: terraformConfigs[provider],
  kustomize: kustomizeConfigs[provider],
} 
