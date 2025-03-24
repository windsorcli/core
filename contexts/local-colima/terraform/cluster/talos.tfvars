// Managed by Windsor CLI: This file is partially managed by the windsor CLI. Your changes will not be overwritten.
// Module source: github.com/windsorcli/core//terraform/cluster/talos?ref=main

// The external controlplane API endpoint of the kubernetes API
cluster_endpoint = "https://controlplane-1.test:6443"

// The name of the cluster
cluster_name = "talos"

// A YAML string of common config patches to apply
common_config_patches = "\"cluster\":\n  \"apiServer\":\n    \"certSANs\":\n    - \"localhost\"\n    - \"controlplane-1.test\"\n    - \"10.5.0.2\"\n  \"extraManifests\":\n  - \"https://raw.githubusercontent.com/alex1989hu/kubelet-serving-cert-approver/v0.8.7/deploy/standalone-install.yaml\"\n\"machine\":\n  \"certSANs\":\n  - \"localhost\"\n  - \"controlplane-1.test\"\n  - \"10.5.0.2\"\n  \"features\":\n    \"hostDNS\":\n      \"forwardKubeDNSToHost\": true\n  \"kubelet\":\n    \"extraArgs\":\n      \"rotate-server-certificates\": \"true\"\n  \"network\": {}\n  \"registries\":\n    \"mirrors\":\n      \"docker.io\":\n        \"endpoints\":\n        - \"http://registry-1.docker.test:5000\"\n      \"gcr.io\":\n        \"endpoints\":\n        - \"http://gcr.test:5000\"\n      \"ghcr.io\":\n        \"endpoints\":\n        - \"http://ghcr.test:5000\"\n      \"quay.io\":\n        \"endpoints\":\n        - \"http://quay.test:5000\"\n      \"registry.k8s.io\":\n        \"endpoints\":\n        - \"http://registry.k8s.test:5000\"\n      \"registry.test\":\n        \"endpoints\":\n        - \"http://registry.test:5000\""

// Machine config details for control planes
controlplanes = [{
  endpoint = "controlplane-1.test"
  hostname = "controlplane-1.test"
  node     = "controlplane-1.test"
}]

// A YAML string of worker config patches to apply
worker_config_patches = "\"machine\":\n  \"kubelet\":\n    \"extraMounts\":\n    - \"destination\": \"/var/local\"\n      \"options\":\n      - \"rbind\"\n      - \"rw\"\n      \"source\": \"/var/local\"\n      \"type\": \"bind\""

// Machine config details for workers
workers = [{
  endpoint = "worker-1.test"
  hostname = "worker-1.test"
  node     = "worker-1.test"
}]
