// Managed by Windsor CLI: This file is partially managed by the windsor CLI. Your changes will not be overwritten.

// The external controlplane API endpoint of the kubernetes API
cluster_endpoint = "https://10.5.0.2:6443"

// The name of the cluster
cluster_name = "talos"

// A YAML string of common config patches to apply
common_config_patches = <<EOF
cluster:
  apiServer:
    certSANs:
    - localhost
    - 10.5.0.2
machine:
  certSANs:
  - localhost
  - 10.5.0.2
  features:
    hostDNS:
      forwardKubeDNSToHost: true
  network:
    interfaces:
    - ignore: true
      interface: eth0
  registries:
    mirrors:
      gcr.test:
        endpoints:
        - https://gcr.io
      ghcr.test:
        endpoints:
        - https://ghcr.io
      quay.test:
        endpoints:
        - https://quay.io
      registry-1.docker.test:
        endpoints:
        - https://docker.io
      registry.k8s.test:
        endpoints:
        - https://registry.k8s.io
EOF

// Machine config details for control planes
controlplanes = [{
  endpoint = "10.5.0.2:50000"
  hostname = "controlplane-1.test"
  node     = "10.5.0.2"
}]

// Machine config details for workers
workers = [{
  endpoint = "10.5.0.11:50000"
  hostname = "worker-1.test"
  node     = "10.5.0.11"
}]
