# Managed by Windsor CLI: This file is partially managed by the windsor CLI. Your changes will not be overwritten.

# The kubernetes version to deploy.
# kubernetes_version = "1.33.2"

# The talos version to deploy.
# talos_version = "1.10.5"

# The name of the cluster.
cluster_name = "talos"

# The external controlplane API endpoint of the kubernetes API.
cluster_endpoint = "https://127.0.0.1:6443"

# A list of machine configuration details for control planes.
controlplanes = [{
  endpoint = "127.0.0.1:50000"
  node     = "controlplane-1"
}]

# A list of machine configuration details
workers = [{
  endpoint = "127.0.0.1:50001"
  node     = "worker-1"
}]

# A YAML string of common config patches to apply. Can be an empty string or valid YAML.
common_config_patches = <<EOF
"cluster":
  "apiServer":
    "certSANs":
    - "localhost"
    - "127.0.0.1"
    - "controlplane-1"
    - "controlplane-1.test"
  "extraManifests":
  - "https://raw.githubusercontent.com/alex1989hu/kubelet-serving-cert-approver/v0.8.7/deploy/standalone-install.yaml"
"machine":
  "certSANs":
  - "localhost"
  - "127.0.0.1"
  - "controlplane-1"
  - "controlplane-1.test"
  "kubelet":
    "extraArgs":
      "rotate-server-certificates": "true"
  "network":
    "interfaces":
    - "ignore": true
      "interface": "eth0"
  "registries":
    "mirrors":
      "docker.io":
        "endpoints":
        - "http://registry-1.docker.test:5000"
      "gcr.io":
        "endpoints":
        - "http://gcr.test:5000"
      "ghcr.io":
        "endpoints":
        - "http://ghcr.test:5000"
      "quay.io":
        "endpoints":
        - "http://quay.test:5000"
      "registry.k8s.io":
        "endpoints":
        - "http://registry.k8s.test:5000"
      "registry.test":
        "endpoints":
        - "http://registry.test:5000"
EOF


# A YAML string of controlplane config patches to apply. Can be an empty string or valid YAML.
# controlplane_config_patches = ""

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
