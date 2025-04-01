// Managed by Windsor CLI: This file is partially managed by the windsor CLI. Your changes will not be overwritten.
// Module source: github.com/windsorcli/core//terraform/cluster/talos?ref=main

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
  extraManifests:
  - https://raw.githubusercontent.com/alex1989hu/kubelet-serving-cert-approver/v0.8.7/deploy/standalone-install.yaml
machine:
  certSANs:
  - localhost
  - 10.5.0.2
  kubelet:
    extraArgs:
      rotate-server-certificates: "true"
  network: {}
  registries:
    mirrors:
      docker.io:
        endpoints:
        - http://registry-1.docker.test:5000
      gcr.io:
        endpoints:
        - http://gcr.test:5000
      ghcr.io:
        endpoints:
        - http://ghcr.test:5000
      quay.io:
        endpoints:
        - http://quay.test:5000
      registry.k8s.io:
        endpoints:
        - http://registry.k8s.test:5000
      registry.test:
        endpoints:
        - http://registry.test:5000
EOF

// Machine config details for control planes
controlplanes = [{
  endpoint = "10.5.0.2:50000"
  hostname = "controlplane-1.test"
  node     = "10.5.0.2"
}]

// A YAML string of worker config patches to apply
worker_config_patches = <<EOF
machine:
  kubelet:
    extraMounts:
    - destination: /var/local
      options:
      - rbind
      - rw
      source: /var/local
      type: bind
EOF

// Machine config details for workers
workers = [{
  endpoint = "10.5.0.11:50000"
  hostname = "worker-1.test"
  node     = "10.5.0.11"
}]
