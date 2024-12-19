kubernetes_version = "1.30.8"
talos_version = "1.8.4"
cluster_name = "talos"
cluster_endpoint = "https://10.5.0.3:6443"
controlplanes = [
  {
    hostname = "controlplane-1.test"
    node     = "10.5.0.3"
    endpoint = "10.5.0.3:50000"
  },
]
workers = [
  {
    hostname = "worker-1.test"
    node     = "10.5.0.12"
    endpoint = "10.5.0.12:50000"
  },
]

common_config_patches = <<-EOT
cluster:
  apiServer:
    certSANs:
    - "localhost"
    - "10.5.0.3"
machine:
  certSANs:
  - "localhost"
  - "10.5.0.3"
  features:
    hostDNS:
      forwardKubeDNSToHost: true
  network:
    interfaces:
      - ignore: true
        interface: eth0
  install:
      disk: /dev/sda # The disk used for installations.
      image: ghcr.io/siderolabs/installer:v1.7.0 # Allows for supplying the image used to perform the installation.
      wipe: true
EOT
