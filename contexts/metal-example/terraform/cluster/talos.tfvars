# Managed by Windsor CLI: This file is partially managed by the windsor CLI. Your changes will not be overwritten.
# Module source: github.com/windsorcli/core//terraform/cluster/talos?ref=main

# The kubernetes version to deploy.
# kubernetes_version = "1.33.1"

# The talos version to deploy.
# talos_version = "1.10.3"

# The name of the cluster.
cluster_name = "talos"

# The external controlplane API endpoint of the kubernetes API.
cluster_endpoint = "https://10.5.0.2:6443"

# A list of machine configuration details for control planes.
controlplanes = [{
  endpoint = "10.5.0.2:50000"
  node     = "controlplane-1"
}]

# A list of machine configuration details
workers = [{
  endpoint = "10.5.0.11:50000"
  node     = "worker-1"
}]

# A YAML string of common config patches to apply. Can be an empty string or valid YAML.
common_config_patches = <<EOF
"cluster":
  "apiServer":
    "certSANs":
    - "localhost"
    - "10.5.0.2"
    - "controlplane-1"
    - "controlplane-1.test"
  "extraManifests":
  - "https://raw.githubusercontent.com/alex1989hu/kubelet-serving-cert-approver/v0.8.7/deploy/standalone-install.yaml"
"machine":
  "certSANs":
  - "localhost"
  - "10.5.0.2"
  - "controlplane-1"
  - "controlplane-1.test"
  "kubelet":
    "extraArgs":
      "rotate-server-certificates": "true"
EOF


# A YAML string of controlplane config patches to apply. Can be an empty string or valid YAML.
controlplane_config_patches = ""

# A YAML string of worker config patches to apply. Can be an empty string or valid YAML.
worker_config_patches = <<EOF
"machine":
  "kubelet":
    "extraMounts":
    - "destination": "/var/local"
      "options":
      - "rbind"
      - "rw"
      "source": "/var/local"
      "type": "bind"
EOF

