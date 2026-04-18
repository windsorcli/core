mock_provider "helm" {}

# Verifies the bootstrap helm_release is created with the expected metadata and
# chart-default values (privileged on, cgroup auto-mount on, no explicit caps).
run "minimal_configuration" {
  command = plan

  variables {
    cluster_endpoint = "https://10.5.0.10:6443"
  }

  assert {
    condition     = helm_release.cilium.chart == "cilium"
    error_message = "Chart should be 'cilium'"
  }

  assert {
    condition     = helm_release.cilium.name == "cilium"
    error_message = "Release name should be 'cilium' so Flux can adopt it via matching releaseName"
  }

  assert {
    condition     = helm_release.cilium.namespace == "kube-system"
    error_message = "Release should be installed in kube-system per Cilium upstream convention"
  }

  assert {
    condition     = helm_release.cilium.repository == "https://helm.cilium.io"
    error_message = "Repository should be the official Cilium Helm repo"
  }

  assert {
    condition     = helm_release.cilium.timeout == 600
    error_message = "Timeout should be 600s to accommodate cold-cluster image pulls + CRD apply"
  }

  assert {
    condition     = helm_release.cilium.wait == true
    error_message = "wait=true ensures downstream terraform steps don't race the bootstrap"
  }

  assert {
    condition     = yamldecode(helm_release.cilium.values[0]).ipam.mode == "kubernetes"
    error_message = "IPAM mode should default to 'kubernetes'"
  }

  assert {
    condition     = yamldecode(helm_release.cilium.values[0]).operator.replicas == 2
    error_message = "Default topology is multi-node so operator replicas should be 2 (chart-aligned for controller redundancy)"
  }

  assert {
    condition     = yamldecode(helm_release.cilium.values[0]).kubeProxyReplacement == true
    error_message = "kubeProxyReplacement should be enabled by default"
  }

  assert {
    condition     = yamldecode(helm_release.cilium.values[0]).k8sServiceHost == "10.5.0.10"
    error_message = "k8sServiceHost should be parsed from cluster_endpoint"
  }

  assert {
    condition     = yamldecode(helm_release.cilium.values[0]).k8sServicePort == 6443
    error_message = "k8sServicePort should be parsed from cluster_endpoint"
  }

  assert {
    condition     = yamldecode(helm_release.cilium.values[0]).securityContext == null
    error_message = "securityContext should be null when privileged (chart default privileged:true applies)"
  }

  assert {
    condition     = yamldecode(helm_release.cilium.values[0]).cgroup == null
    error_message = "cgroup should be null when auto-mount is on (chart default)"
  }
}

# Verifies privileged=false swaps full-privileged mode for an explicit Linux
# capability set (required on Talos and other non-privileged-pod environments).
run "privileged_false_sets_explicit_capabilities" {
  command = plan

  variables {
    cluster_endpoint = "https://10.5.0.10:6443"
    privileged       = false
  }

  assert {
    condition     = contains(yamldecode(helm_release.cilium.values[0]).securityContext.capabilities.ciliumAgent, "NET_ADMIN")
    error_message = "ciliumAgent capabilities should include NET_ADMIN"
  }

  assert {
    condition     = contains(yamldecode(helm_release.cilium.values[0]).securityContext.capabilities.ciliumAgent, "SYS_ADMIN")
    error_message = "ciliumAgent capabilities should include SYS_ADMIN"
  }

  assert {
    condition     = contains(yamldecode(helm_release.cilium.values[0]).securityContext.capabilities.cleanCiliumState, "NET_ADMIN")
    error_message = "cleanCiliumState capabilities should include NET_ADMIN"
  }
}

# Verifies cgroup_auto_mount=false disables the agent's self-mount and points
# at the pre-existing cgroup v2 mount at /sys/fs/cgroup.
run "cgroup_auto_mount_false_configures_host_mount" {
  command = plan

  variables {
    cluster_endpoint  = "https://10.5.0.10:6443"
    cgroup_auto_mount = false
  }

  assert {
    condition     = yamldecode(helm_release.cilium.values[0]).cgroup.autoMount.enabled == false
    error_message = "cgroup.autoMount.enabled should be false"
  }

  assert {
    condition     = yamldecode(helm_release.cilium.values[0]).cgroup.hostRoot == "/sys/fs/cgroup"
    error_message = "cgroup.hostRoot should point at the standard cgroup v2 mount"
  }
}

# Verifies that disabling kube-proxy replacement nulls out the API server wiring
# so the chart falls back to in-cluster service discovery.
run "kube_proxy_replacement_disabled" {
  command = plan

  variables {
    kube_proxy_replacement = false
  }

  assert {
    condition     = yamldecode(helm_release.cilium.values[0]).kubeProxyReplacement == null
    error_message = "kubeProxyReplacement should be null when disabled"
  }

  assert {
    condition     = yamldecode(helm_release.cilium.values[0]).k8sServiceHost == null
    error_message = "k8sServiceHost should be null when kube-proxy replacement is disabled"
  }

  assert {
    condition     = yamldecode(helm_release.cilium.values[0]).k8sServicePort == null
    error_message = "k8sServicePort should be null when kube-proxy replacement is disabled"
  }
}

# Verifies that non-default IPAM modes (e.g. 'eni' for EKS native networking) pass through.
run "ipam_mode_eni" {
  command = plan

  variables {
    cluster_endpoint = "https://10.5.0.10:6443"
    ipam_mode        = "eni"
  }

  assert {
    condition     = yamldecode(helm_release.cilium.values[0]).ipam.mode == "eni"
    error_message = "IPAM mode should reflect the input variable"
  }
}

# Verifies cluster_endpoint parsing handles non-default ports and hostnames.
run "cluster_endpoint_parsing" {
  command = plan

  variables {
    cluster_endpoint = "https://api.cluster.example.com:8443"
  }

  assert {
    condition     = yamldecode(helm_release.cilium.values[0]).k8sServiceHost == "api.cluster.example.com"
    error_message = "Hostname should be parsed from cluster_endpoint"
  }

  assert {
    condition     = yamldecode(helm_release.cilium.values[0]).k8sServicePort == 8443
    error_message = "Port should be parsed from cluster_endpoint"
  }
}

# Verifies the chart version is controlled by the cilium_version variable. This
# sets the initial install version; the Flux HelmRelease reconciles to whatever
# version it specifies and owns subsequent upgrades.
run "custom_cilium_version" {
  command = plan

  variables {
    cluster_endpoint = "https://10.5.0.10:6443"
    cilium_version   = "1.17.2"
  }

  assert {
    condition     = helm_release.cilium.version == "1.17.2"
    error_message = "Chart version should reflect the cilium_version input"
  }
}

# Verifies operator_replicas=1 passes through (single-node caller wanting to
# avoid the hostPort conflict from two replicas on one node).
run "operator_replicas_one_passes_through" {
  command = plan

  variables {
    cluster_endpoint  = "https://10.5.0.10:6443"
    operator_replicas = 1
  }

  assert {
    condition     = yamldecode(helm_release.cilium.values[0]).operator.replicas == 1
    error_message = "operator_replicas=1 input should produce operator.replicas=1 in the release values"
  }
}

# Verifies input validation rejects malformed cilium_version, non-https
# cluster_endpoint, unsupported ipam_mode, and out-of-range operator_replicas.
run "invalid_inputs_fail_validation" {
  command = plan

  variables {
    cilium_version    = "1.16"             # missing patch
    cluster_endpoint  = "http://insecure"  # not https
    ipam_mode         = "custom"           # not in allowed list
    operator_replicas = 99                 # out of range
  }

  expect_failures = [
    var.cilium_version,
    var.cluster_endpoint,
    var.ipam_mode,
    var.operator_replicas,
  ]
}
