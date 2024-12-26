// Managed by Windsor CLI: This file is partially managed by the windsor CLI. Your changes will not be overwritten.
// Module source: github.com/windsorcli/core//terraform/cluster/talos?ref=v0.1.0

// The external controlplane API endpoint of the kubernetes API.
cluster_endpoint = "https://10.5.0.2:6443"

// The name of the cluster.
cluster_name = "talos"

// A YAML string of common config patches to apply. Can be an empty string or valid YAML.
common_config_patches = "\"cluster\":\n  \"apiServer\":\n    \"certSANs\":\n    - \"localhost\"\n    - \"10.5.0.2\"\n\"machine\":\n  \"certSANs\":\n  - \"localhost\"\n  - \"10.5.0.2\"\n  \"features\":\n    \"hostDNS\":\n      \"forwardKubeDNSToHost\": true\n  \"network\":\n    \"interfaces\":\n    - \"ignore\": true\n      \"interface\": \"eth0\""

// A list of machine configuration details for control planes.
controlplanes = [{
  endpoint = "10.5.0.2:50000"
  hostname = "controlplane-1.test"
  node     = "10.5.0.2"
}]

// A list of machine configuration details
workers = [{
  endpoint = "10.5.0.11:50000"
  hostname = "worker-1.test"
  node     = "10.5.0.11"
}]
