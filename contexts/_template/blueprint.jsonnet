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

// Helper to concatenate arrays (std.flattenArrays expects array of arrays)
local concat(arrays) = std.foldl(function(x, y) x + y, arrays, []);

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
      path: "network/aws-vpc",
    },
    {
      path: "cluster/aws-eks",
    },
    {
      path: "cluster/aws-eks/additions",
      destroy: false,
    },
    {
      path: "gitops/flux",
      destroy: false,
    },
  ] else if provider == "azure" then [
    {
      path: "network/azure-vnet",
    },
    {
      path: "cluster/azure-aks",
    },
    {
      path: "gitops/flux",
      destroy: false,
    },
  ] else [
    {
      path: "cluster/talos",
      parallelism: 1,
    },
    {
      path: "gitops/flux",
      destroy: false,
    },
  ],
  kustomize:
    concat([
      [
        {
          name: "telemetry-base",
          path: "telemetry/base",
          components: [
            "prometheus",
            "prometheus/flux",
            "fluentbit",
            "fluentbit/prometheus",
          ],
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
            "fluentbit/systemd",
          ],
          dependsOn: ["telemetry-base"],
        },
        {
          name: "policy-base",
          path: "policy/base",
          components: ["kyverno"],
        },
        {
          name: "policy-resources",
          path: "policy/resources",
          dependsOn: ["policy-base"],
        },
        {
          name: "csi",
          path: "csi",
          components:
            if provider == "aws" then ["aws-ebs"]
            else if provider == "local" then [
              "openebs",
              "openebs/dynamic-localpv",
            ]
            else [],
          dependsOn: ["policy-resources"],
          cleanup: ["pvcs"],
        },
        {
          name: "pki-base",
          path: "pki/base",
          components: [
            "cert-manager",
            "trust-manager",
          ],
          dependsOn: ["policy-resources"],
        },
        {
          name: "pki-resources",
          path: "pki/resources",
          components: [
            "private-issuer/ca",
            "public-issuer/selfsigned",
          ],
          dependsOn: ["pki-base"],
        },
        {
          name: "ingress",
          path: "ingress",
          components:
            if provider == "aws" then [
              "nginx",
              "nginx/flux-webhook",
              "nginx/web",
            ] else
              std.filter(
                function(x) x != null,
                [
                  "nginx",
                  if vmDriver == "docker-desktop" then "nginx/nodeport" else null,
                  "nginx/coredns",
                  "nginx/flux-webhook",
                  "nginx/web",
                ]
              ),
          dependsOn: ["pki-resources"],
          cleanup: ["loadbalancers", "ingresses"],
        },
        {
          name: "dns",
          path: "dns",
          components:
            if provider == "aws" then [
              "external-dns",
              "external-dns/route53",
            ]
            else if vmDriver == "docker-desktop" then [
              "coredns",
              "coredns/etcd",
              "external-dns",
              "external-dns/localhost",
              "external-dns/coredns",
              "external-dns/ingress",
            ]
            else [
              "coredns",
              "coredns/etcd",
              "external-dns",
              "external-dns/coredns",
              "external-dns/ingress",
            ],
          dependsOn: if provider == "aws" then [] else ["pki-base"],
        },
        {
          name: "gitops",
          path: "gitops/flux",
          components: ["webhook"],
          dependsOn: ["ingress"],
        },
      ],
      // Optionally add MetalLB for local non-docker-desktop
      if provider == "local" && vmDriver != "docker-desktop" then [
        {
          name: "lb-base",
          path: "lb/base",
          components: ["metallb"],
          dependsOn: ["policy-resources"],
        },
        {
          name: "lb-resources",
          path: "lb/resources",
          components: ["metallb/layer2"],
          dependsOn: ["lb-base"],
        },
      ] else [],
      [
        {
          name: "observability",
          path: "observability",
          components:
            concat([
              [
                "fluentd",
                "fluentd/filters/otel",
                "fluentd/outputs/stdout",
              ],
              if provider == "local" then [
                "fluentd/outputs/quickwit",
                "quickwit",
                "quickwit/pvc",
              ] else [],
              [
                "grafana",
                "grafana/ingress",
                "grafana/prometheus",
                "grafana/node",
                "grafana/kubernetes",
                "grafana/flux",
              ],
              if provider == "local" then [
                "grafana/quickwit",
              ] else [],
            ]),
          dependsOn: ["csi", "ingress"],
        },
      ],
    ]),
}
