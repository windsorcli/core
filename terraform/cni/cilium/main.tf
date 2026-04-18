#-----------------------------------------------------------------------------------------------------------------------
# Setup
#-----------------------------------------------------------------------------------------------------------------------

terraform {
  required_version = ">=1.8"
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "3.1.1"
    }
  }
}

#-----------------------------------------------------------------------------------------------------------------------
# Locals
#-----------------------------------------------------------------------------------------------------------------------

locals {
  # Extract host and port from cluster_endpoint (https://host:port) when kube-proxy replacement
  # is enabled. k8sServiceHost/k8sServicePort let Cilium reach the API server directly before
  # eBPF service rules are active.
  k8s_service_host = var.kube_proxy_replacement ? regex("https://([^/:]+)", var.cluster_endpoint)[0] : ""
  k8s_service_port = var.kube_proxy_replacement ? try(tonumber(regex("https://[^:]+:([0-9]+)", var.cluster_endpoint)[0]), 6443) : 0
}

#-----------------------------------------------------------------------------------------------------------------------
# Cilium Bootstrap
#-----------------------------------------------------------------------------------------------------------------------
# Cilium is installed here (before Flux) so that pod networking is available when the GitOps
# controllers start. The Flux HelmRelease in kustomize/cni/cilium/ adopts this release via
# matching releaseName + storageNamespace and owns day-2 feature configuration
# (hubble, gateway, prometheus, l2, bpf perf, cluster identity).
#
# The values below deliberately overlap with the Flux HelmRelease base so the two agree on
# the baseline (IPAM mode, kube-proxy wiring, operator replicas, Talos capabilities). We do
# *not* use lifecycle.ignore_changes on `values` here: the hashicorp/helm provider rewrites
# user-supplied values on every apply regardless of that directive, so the only way to
# prevent drift between `windsor up` and steady-state is to keep the two sides in sync.
# Feature patches (hubble, gateway, etc.) live only in Flux — Terraform will not stomp them
# because it doesn't know about them; Flux reconciles them back on top of this baseline
# within seconds of any bootstrap re-run.

resource "helm_release" "cilium" {
  repository = "https://helm.cilium.io"
  chart      = "cilium"
  name       = "cilium"
  # renovate: datasource=helm depName=cilium package=cilium helmRepo=https://helm.cilium.io
  version   = var.cilium_version
  namespace = "kube-system"
  wait      = true
  timeout   = 600

  values = [yamlencode(merge(
    {
      # IPAM mode is baked into node state; changing it post-install forces pod IP churn.
      # Must match the Flux-managed value.
      ipam = {
        mode = var.ipam_mode
      }

      # Operator replicas must match the Flux-managed value so re-runs of this module
      # don't flap the deployment between Flux reconciles. Caller decides the count
      # (single-node → 1, everything else → 2); see var.operator_replicas.
      operator = {
        replicas = var.operator_replicas
      }
    },

    # kube-proxy replacement: set k8sServiceHost/k8sServicePort so Cilium can reach the API
    # server before its own eBPF service proxy is active.
    var.kube_proxy_replacement ? {
      kubeProxyReplacement = true
      k8sServiceHost       = local.k8s_service_host
      k8sServicePort       = local.k8s_service_port
      } : {
      kubeProxyReplacement = null
      k8sServiceHost       = null
      k8sServicePort       = null
    },

    # Non-privileged mode: grant the explicit Linux capabilities Cilium needs instead of
    # running with full privileged=true. The capability list is fixed (upstream-recommended
    # minimum set); privileged-or-not is the caller's decision.
    var.privileged ? {
      securityContext = null
      } : {
      securityContext = {
        capabilities = {
          ciliumAgent      = ["CHOWN", "KILL", "NET_ADMIN", "NET_RAW", "IPC_LOCK", "SYS_ADMIN", "SYS_RESOURCE", "DAC_OVERRIDE", "FOWNER", "SETGID", "SETUID"]
          cleanCiliumState = ["NET_ADMIN", "SYS_ADMIN", "SYS_RESOURCE"]
        }
      }
    },

    # Skip Cilium's cgroup auto-mount on hosts that mount cgroups at init; point at the
    # standard cgroup v2 path (/sys/fs/cgroup) so the agent uses the existing mount.
    var.cgroup_auto_mount ? {
      cgroup = null
      } : {
      cgroup = {
        autoMount = {
          enabled = false
        }
        hostRoot = "/sys/fs/cgroup"
      }
    }
  ))]
}
