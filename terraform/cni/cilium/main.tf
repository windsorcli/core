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
# controllers start. The Flux HelmRelease in kustomize/cni/cilium/ adopts this release for
# ongoing lifecycle management (upgrades, config drift).

resource "helm_release" "cilium" {
  repository = "https://helm.cilium.io"
  chart      = "cilium"
  name       = "cilium"
  # renovate: datasource=helm depName=cilium package=cilium helmRepo=https://helm.cilium.io
  version   = var.cilium_version
  namespace = "kube-system"
  wait      = true
  timeout   = 300

  values = [yamlencode(merge(
    {
      # IPAM: controls how Cilium allocates pod IPs.
      # "kubernetes" uses node CIDR ranges (default, works for Talos/EKS without ENI).
      ipam = {
        mode = var.ipam_mode
      }

      operator = {
        replicas = 1
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

    # Talos-specific settings: grant required Linux capabilities (instead of full privileged
    # mode) and disable Cilium's cgroup auto-mount (Talos mounts cgroups at boot).
    var.talos_mode ? {
      securityContext = {
        capabilities = {
          ciliumAgent      = ["CHOWN", "KILL", "NET_ADMIN", "NET_RAW", "IPC_LOCK", "SYS_ADMIN", "SYS_RESOURCE", "DAC_OVERRIDE", "FOWNER", "SETGID", "SETUID"]
          cleanCiliumState = ["NET_ADMIN", "SYS_ADMIN", "SYS_RESOURCE"]
        }
      }
      cgroup = {
        autoMount = {
          enabled = false
        }
        hostRoot = "/sys/fs/cgroup"
      }
      } : {
      securityContext = null
      cgroup          = null
    }
  ))]
}
