# The Incus Workstation module creates Windsor local-development containers using the Incus provider.
# It optionally creates a bridge network (create_network=true) or uses an existing one (e.g. incusbr0 when runtime is colima).
# Same IP layout as workstation/docker: 1=gateway, 2=dns, 3=git, 4+=registries. Use compute/incus when cluster is enabled.

# =============================================================================
# Provider Configuration
# =============================================================================

terraform {
  required_version = ">=1.8"
  required_providers {
    incus = {
      source  = "lxc/incus"
      version = "1.0.2"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.7.0"
    }
  }
}

# OCI remotes for image pulls so docker: and ghcr: refs resolve. If you see "Image not found", ensure the Incus
# client has these remotes (e.g. incus remote add docker https://docker.io --protocol=oci --public).
provider "incus" {
  remote {
    name     = "docker"
    address  = "https://docker.io"
    protocol = "oci"
    public   = true
  }
  remote {
    name     = "ghcr"
    address  = "https://ghcr.io"
    protocol = "oci"
    public   = true
  }
}

# =============================================================================
# Locals
# =============================================================================

locals {
  domain_name           = coalesce(var.domain_name, var.context)
  network_name_resolved = coalesce(var.network_name, "windsor-${var.context}")
  compose_project       = "workstation-windsor-${var.context}"
  # Incus: bridge networking only; no localhost/port-publish mode like docker-desktop (docker uses loadbalancer_cidr for that)
  loadbalancer_start_ip = coalesce(var.loadbalancer_start_ip, cidrhost(cidrsubnet(var.network_cidr, 8, 1), 1))
  webhook_host_derived  = local.loadbalancer_start_ip
  webhook_host          = coalesce(var.webhook_host, var.primary_node_ip, local.webhook_host_derived)
  webhook_url           = "http://${local.webhook_host}:9292/hook/${var.webhook_token}"
  gateway               = cidrhost(var.network_cidr, 1)
  dns_ip                = cidrhost(var.network_cidr, 2)
  attached_network      = var.create_network ? local.network_name_resolved : var.network_name
  git_ip                = cidrhost(var.network_cidr, 3)
  registry_keys_sorted  = sort(keys(var.registries))
  registry_ips = {
    for i, k in local.registry_keys_sorted : k => cidrhost(var.network_cidr, 4 + i)
  }
  # Strip trailing TLD from registry key so hostname is registry.k8s.test not registry.k8s.io.test
  registry_hostname_tlds = toset(["io", "com", "test", "dev", "org", "net"])
  registry_hostname_base = {
    for k in local.registry_keys_sorted : k => (
      length(split(".", k)) > 1 && contains(local.registry_hostname_tlds, element(split(".", k), length(split(".", k)) - 1))
      ? join(".", slice(split(".", k), 0, length(split(".", k)) - 1))
      : k
    )
  }
  registry_hostname = { for k in local.registry_keys_sorted : k => "${local.registry_hostname_base[k]}.${local.domain_name}" }
  service_ips = merge(
    { dns = local.dns_ip, git = local.git_ip },
    local.registry_ips
  )
  dns_forward_target = coalesce(var.dns_forward_target, local.loadbalancer_start_ip)
  corefile_host_entries = concat(
    var.enable_dns ? ["${local.dns_ip} dns.${local.domain_name}"] : [],
    [for k in local.registry_keys_sorted : "${local.registry_ips[k]} ${local.registry_hostname[k]}"],
    var.enable_git ? ["${local.git_ip} git.${local.domain_name}"] : []
  )
  corefile_content = var.enable_dns ? templatefile("${path.module}/templates/Corefile.tpl", {
    context            = local.domain_name
    host_entries       = local.corefile_host_entries
    dns_forward_target = local.dns_forward_target
  }) : ""
  corefile_path = var.enable_dns ? "${var.project_root}/.windsor/Corefile" : null
}

# =============================================================================
# Network (only when create_network; else use existing e.g. incusbr0 for Colima)
# =============================================================================

resource "incus_network" "main" {
  count = var.create_network ? 1 : 0

  name = local.network_name_resolved
  type = "bridge"
  config = {
    "ipv4.address" = "${local.gateway}/${split("/", var.network_cidr)[1]}"
    "ipv4.dhcp"    = "true"
    "ipv4.nat"     = "true"
  }
}

# =============================================================================
# Corefile on host (Incus mounts file; no in-container upload)
# =============================================================================

resource "local_file" "corefile" {
  count = var.enable_dns ? 1 : 0

  content         = local.corefile_content
  filename        = local.corefile_path
  file_permission = "0644"
}

# =============================================================================
# Instance: dns
# =============================================================================

resource "incus_instance" "dns" {
  count = var.enable_dns ? 1 : 0
  name  = replace("dns.${local.domain_name}", ".", "-")
  type  = "container"
  # renovate: datasource=docker depName=coredns/coredns package=coredns/coredns
  image = "docker:coredns/coredns:1.14.1"
  config = {
    "raw.lxc"        = "lxc.apparmor.profile=unconfined"
    "oci.entrypoint" = "/coredns -conf /etc/coredns/Corefile"
  }

  device {
    name = "eth0"
    type = "nic"
    properties = {
      network        = local.attached_network
      "ipv4.address" = local.dns_ip
    }
  }

  device {
    name = "corefile"
    type = "disk"
    properties = {
      source   = local.corefile_path
      path     = "/etc/coredns/Corefile"
      readonly = "true"
    }
  }

  depends_on = [incus_network.main, local_file.corefile]

  lifecycle {
    replace_triggered_by = [local_file.corefile]
  }
}

# =============================================================================
# Registry cache dirs (Incus requires disk source path to exist before create)
# =============================================================================

resource "terraform_data" "registry_cache_dirs" {
  for_each = var.registries
  triggers_replace = {
    path = "${var.project_root}/.windsor/cache/docker/registries/${each.key}"
  }
  provisioner "local-exec" {
    command = "mkdir -p '${var.project_root}/.windsor/cache/docker/registries/${each.key}'"
  }
}

# =============================================================================
# Instances: registries (from var.registries)
# =============================================================================

resource "incus_instance" "registry" {
  for_each = var.registries
  name     = replace(local.registry_hostname[each.key], ".", "-")
  type     = "container"
  # renovate: datasource=docker depName=library/registry package=library/registry
  image      = "docker:library/registry:3.0.0"
  depends_on = [incus_network.main, terraform_data.registry_cache_dirs]
  config = each.value.remote != null ? {
    "environment.REGISTRY_PROXY_REMOTEURL" = each.value.remote
  } : {}

  device {
    name = "eth0"
    type = "nic"
    properties = {
      network        = local.attached_network
      "ipv4.address" = local.registry_ips[each.key]
    }
  }

  device {
    name = "docker-cache"
    type = "disk"
    properties = {
      source = "${var.project_root}/.windsor/cache/docker/registries/${each.key}"
      path   = "/var/lib/registry"
    }
  }
}

# =============================================================================
# Instance: git
# =============================================================================

resource "incus_instance" "git" {
  count      = var.enable_git ? 1 : 0
  depends_on = [incus_network.main]
  name       = replace("git.${local.domain_name}", ".", "-")
  type       = "container"
  # renovate: datasource=github-releases depName=windsorcli/git-livereload
  image = "ghcr:windsorcli/git-livereload:v0.2.1"
  config = {
    "environment.GIT_PASSWORD"  = var.git_password
    "environment.GIT_USERNAME"  = var.git_username
    "environment.RSYNC_EXCLUDE" = var.git_rsync_exclude
    "environment.RSYNC_INCLUDE" = var.git_rsync_include
    "environment.RSYNC_PROTECT" = var.git_rsync_protect
    "environment.VERIFY_SSL"    = "false"
    "environment.WEBHOOK_URL"   = local.webhook_url
  }

  device {
    name = "eth0"
    type = "nic"
    properties = {
      network        = local.attached_network
      "ipv4.address" = local.git_ip
    }
  }

  device {
    name = "project-root"
    type = "disk"
    properties = {
      source = var.project_root
      path   = "/repos/mount/core"
    }
  }
}
