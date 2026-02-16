# Cluster nodes on Docker (Talos, future k3s). Creates controlplane and worker containers;
# shape from cluster_nodes.distribution. Optional instances for custom/compose use.
# Outputs align with compute/incus for cluster modules.

# =============================================================================
# Provider
# =============================================================================

terraform {
  required_version = ">=1.8"
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "3.6.2"
    }
  }
}

# =============================================================================
# Locals
# =============================================================================

locals {
  network_name = var.network_name != "" ? var.network_name : "windsor-${var.context}"

  # Runtime: docker-desktop => localhost-only networking; colima/linux => advanced networking. Standardized with workstation/docker.
  runtime                  = var.runtime == "colima" ? "linux" : var.runtime
  use_localhost_networking = var.runtime == "docker-desktop"

  # Node shape: per-distribution (talos, future k3s) container definition:
  # ports, volume_specs, env_sku_key, privileged, security_opt, tmpfs.
  node_shapes = {
    talos = {
      controlplane = {
        ports = ["50000:50000/tcp", "6443:6443/tcp"]
        volume_specs = [
          { name = "system_state", path = "/system/state" },
          { name = "var", path = "/var" },
          { name = "etc_cni", path = "/etc/cni" },
          { name = "etc_kubernetes", path = "/etc/kubernetes" },
          { name = "usr_libexec_kubernetes", path = "/usr/libexec/kubernetes" },
          { name = "opt", path = "/opt" }
        ]
        env_sku_key  = "TALOSSKU"
        privileged   = true
        read_only    = true
        security_opt = ["seccomp=unconfined", "label=disable"]
        tmpfs        = { "/run" = "", "/system" = "", "/tmp" = "" }
      }
      worker = {
        ports        = []
        volume_specs = []
        env_sku_key  = "TALOSSKU"
        privileged   = true
        read_only    = true
        security_opt = ["seccomp=unconfined", "label=disable"]
        tmpfs        = { "/run" = "", "/system" = "", "/tmp" = "" }
      }
    }
  }

  dist          = var.cluster_nodes != null ? var.cluster_nodes.distribution : "talos"
  shape         = var.cluster_nodes != null ? local.node_shapes[local.dist] : null
  _cp_count     = var.cluster_nodes != null ? var.cluster_nodes.controlplanes.count : 0
  _worker_count = var.cluster_nodes != null ? var.cluster_nodes.workers.count : 0

  # Host ports: 6443 per cp (6443, 6444, …); 50000 range shared (cp1=50000, cp2=50001, worker-1=50002, …).
  # Exclude container-only 6443/50000 from shape so we emit host-mapped only (avoids external=null / known after apply).
  _cp_ports_container_only = [
    for p in local.shape != null ? local.shape.controlplane.ports : []
    : p if length(split(":", split("/", p)[0])) == 1
  ]
  _cp_ports_with_auto = { for i in range(local._cp_count) : i => concat(
    [for p in local._cp_ports_container_only : p if p != "6443/tcp" && p != "50000/tcp"],
    ["${6443 + i}:6443/tcp", "${50000 + i}:50000/tcp"],
    coalesce(var.cluster_nodes.controlplanes.hostports, [])
  ) }
  _worker_ports_with_auto = { for i in range(local._worker_count) : i => concat(
    [for p in(local.shape != null ? local.shape.worker.ports : []) : p if p != "50000/tcp"],
    ["${50000 + local._cp_count + i}:50000/tcp"],
    coalesce(var.cluster_nodes.workers.hostports, [])
  ) }

  # Cluster instances: controlplanes then workers. Ports override shape so auto + hostports win.
  cluster_nodes_instances = var.cluster_nodes != null ? concat(
    [for i in range(local._cp_count) : merge(merge({
      name     = "controlplane-${i + 1}"
      role     = "controlplane"
      count    = 1
      image    = var.cluster_nodes.controlplanes.image
      hostname = "controlplane-${i + 1}"
      ports    = local._cp_ports_with_auto[i]
      env = merge(
        { PLATFORM = "container" },
        { (local.shape.controlplane.env_sku_key) = "${var.cluster_nodes.controlplanes.cpu}CPU-${var.cluster_nodes.controlplanes.memory * 1024}RAM" }
      )
      volumes = concat(
        [for s in local.shape.controlplane.volume_specs : "controlplane_${i + 1}_${s.name}:${s.path}"],
        coalesce(var.cluster_nodes.controlplanes.volumes, [])
      )
    }, local.shape.controlplane), { ports = local._cp_ports_with_auto[i] })],
    [for i in range(local._worker_count) : merge(merge({
      name     = "worker-${i + 1}"
      role     = "worker"
      count    = 1
      image    = var.cluster_nodes.workers.image
      hostname = "worker-${i + 1}"
      ports    = local._worker_ports_with_auto[i]
      env = merge(
        { PLATFORM = "container" },
        { (local.shape.worker.env_sku_key) = "${var.cluster_nodes.workers.cpu}CPU-${var.cluster_nodes.workers.memory * 1024}RAM" }
      )
      volumes = concat(
        [for s in local.shape.worker.volume_specs : "worker_${i + 1}_${s.name}:${s.path}"],
        coalesce(var.cluster_nodes.workers.volumes, [])
      )
    }, local.shape.worker), { ports = local._worker_ports_with_auto[i] })]
  ) : []
  instance_definitions = concat(var.cluster_nodes != null ? local.cluster_nodes_instances : [], var.instances)

  # Expand instances (count > 1 → name-0, name-1, …) and key by container name for for_each.
  expanded_instances = flatten([
    for inst in local.instance_definitions : [
      for i in range(inst.count) : merge(inst, {
        container_name = inst.count > 1 ? "${inst.name}-${i}" : inst.name
        instance_name  = inst.name
        index          = i
      })
    ]
  ])
  containers_by_name = { for c in local.expanded_instances : c.container_name => c }

  # IP index: controlplanes, then workers, then instances. Sequential IPs from start_ip or base (host 2 if create_network, else 10).
  ip_index_per_container = merge(
    var.cluster_nodes != null ? merge(
      { for i in range(var.cluster_nodes.controlplanes.count) : "controlplane-${i + 1}" => i },
      { for i in range(var.cluster_nodes.workers.count) : "worker-${i + 1}" => local._cp_count + i }
    ) : {},
    length(var.instances) > 0 ? merge([
      for inst_idx, inst in var.instances : {
        for i in range(inst.count) :
        (inst.count > 1 ? "${inst.name}-${i}" : inst.name) =>
        local._cp_count + local._worker_count + (inst_idx == 0 ? 0 : sum([for p in slice(var.instances, 0, inst_idx) : p.count])) + i
      }
    ]...) : {}
  )

  network_prefix_len = var.network_cidr != null ? tonumber(split("/", var.network_cidr)[1]) : null
  gateway            = var.create_network && var.network_cidr != null ? cidrhost(var.network_cidr, 1) : null
  start_index = (var.start_ip != null && var.network_cidr != null) ? try(
    [for i in range(0, 2048) : i if cidrhost(var.network_cidr, i) == var.start_ip][0],
    null
  ) : null
  _sequential_base = (var.start_ip != null && var.network_cidr != null && local.start_index != null) ? local.start_index : (
    (var.create_network && var.network_cidr != null) ? 2 :
    (!var.create_network && var.network_cidr != null) ? 10 : null
  )
  sequential_ips = local._sequential_base != null ? {
    for name, idx in local.ip_index_per_container :
    name => "${cidrhost(var.network_cidr, local._sequential_base + idx)}/${local.network_prefix_len}"
  } : {}
  container_ipv4 = {
    for name, c in local.containers_by_name : name => (
      try(c.ipv4_address, null) != null ? c.ipv4_address :
      try(local.sequential_ips[name], null) != null ? local.sequential_ips[name] : null
    )
  }

  unique_images               = distinct([for c in local.expanded_instances : c.image])
  image_id_map                = { for ref in local.unique_images : ref => docker_image.instances[ref].image_id }
  instance_to_first_container = { for inst in local.instance_definitions : inst.name => inst.count > 1 ? "${inst.name}-0" : inst.name }

  # Ports: parse "host:container/protocol" or "container/protocol", dedup by (internal, protocol) preferring host-mapped, sort for stable plan.
  _port_spec_raw = {
    for name, c in local.containers_by_name : name => [
      for p in coalesce(c.ports, []) :
      length(split("/", p)) > 1 ? {
        internal = tonumber(split(":", split("/", p)[0])[length(split(":", split("/", p)[0])) - 1]),
        external = length(split(":", split("/", p)[0])) > 1 ? tonumber(split(":", split("/", p)[0])[0]) : null,
        protocol = split("/", p)[1]
        } : {
        internal = tonumber(split(":", p)[length(split(":", p)) - 1]),
        external = length(split(":", p)) > 1 ? tonumber(split(":", p)[0]) : null,
        protocol = "tcp"
      }
    ]
  }
  _port_spec_grouped = {
    for name, specs in local._port_spec_raw : name => { for s in specs : "${s.internal}-${s.protocol}" => s... }
  }
  _port_spec_deduped = {
    for name, grouped in local._port_spec_grouped : name => { for k, list in grouped : k => try([for x in list : x if x.external != null][0], list[0]) }
  }
  container_port_specs = {
    for name, m in local._port_spec_deduped : name => values({ for k, v in m : "${format("%05d", v.internal)}-${v.protocol}" => v })
  }

  # Named volumes: source from instance volumes (source:dest); resolve {container_name}, {instance_name}, {index}; skip bind mounts (/ or . prefix).
  named_volume_names = toset([
    for x in flatten([
      for c in local.expanded_instances : [
        for v in coalesce(c.volumes, []) :
        (length(regexall("^/", split(":", v)[0])) > 0 || length(regexall("^\\.", split(":", v)[0])) > 0) ? null : replace(
          replace(
            replace(
              replace(split(":", v)[0], "{container_name}", c.container_name),
              "{instance_name}", c.instance_name
            ),
            "{index}", tostring(c.index)
          ),
          "{index_1}", tostring(c.index + 1)
        )
      ]
    ])
    : x if x != null
  ])
}

# =============================================================================
# Resources
# =============================================================================

resource "docker_network" "main" {
  count = var.create_network ? 1 : 0

  name    = local.network_name
  driver  = var.network_driver
  options = { "com.docker.network.enable_ipv4" = "true", "com.docker.network.enable_ipv6" = "false" }

  dynamic "ipam_config" {
    for_each = var.network_cidr != null ? [1] : []
    content {
      subnet  = var.network_cidr
      gateway = local.gateway
    }
  }
}

resource "docker_volume" "named" {
  for_each = local.named_volume_names
  name     = each.value

  dynamic "labels" {
    for_each = var.compose_project != null ? { "com.docker.compose.project" = var.compose_project } : {}
    content {
      label = labels.key
      value = labels.value
    }
  }
}

resource "docker_image" "instances" {
  for_each = toset(local.unique_images)
  name     = each.value
}

resource "docker_container" "containers" {
  for_each = local.containers_by_name

  name       = each.value.container_name
  image      = local.image_id_map[each.value.image]
  restart    = try(each.value.restart, "unless-stopped")
  privileged = try(each.value.privileged, false)
  read_only  = try(each.value.read_only, false)

  security_opts = toset(coalesce(try(each.value.security_opt, null), []))

  tmpfs = length(coalesce(try(each.value.tmpfs, null), {})) > 0 ? try(each.value.tmpfs, {}) : null

  command    = length(coalesce(try(each.value.command, null), [])) > 0 ? each.value.command : null
  entrypoint = length(coalesce(try(each.value.entrypoint, null), [])) > 0 ? each.value.entrypoint : null

  hostname = try(each.value.hostname, null) != null ? replace(
    replace(
      replace(
        replace(each.value.hostname, "{container_name}", each.key),
        "{instance_name}", each.value.instance_name
      ),
      "{index}", tostring(each.value.index)
    ),
    "{index_1}", tostring(each.value.index + 1)
  ) : null

  env = [for k, v in coalesce(try(each.value.env, null), {}) : "${k}=${v}"]

  dynamic "ports" {
    for_each = local.container_port_specs[each.key]
    content {
      internal = ports.value.internal
      external = ports.value.external
      protocol = ports.value.protocol
    }
  }

  dynamic "volumes" {
    for_each = coalesce(try(each.value.volumes, null), [])
    content {
      host_path = (
        length(regexall("^/", split(":", volumes.value)[0])) > 0 ||
        length(regexall("^\\.", split(":", volumes.value)[0])) > 0
      ) ? split(":", volumes.value)[0] : null
      volume_name = (
        length(regexall("^/", split(":", volumes.value)[0])) > 0 ||
        length(regexall("^\\.", split(":", volumes.value)[0])) > 0
        ) ? null : replace(
        replace(
          replace(
            replace(split(":", volumes.value)[0], "{container_name}", each.key),
            "{instance_name}", each.value.instance_name
          ),
          "{index}", tostring(each.value.index)
        ),
        "{index_1}", tostring(each.value.index + 1)
      )
      container_path = join(":", slice(split(":", volumes.value), 1, length(split(":", volumes.value))))
      read_only      = false
    }
  }

  dynamic "labels" {
    for_each = merge(
      coalesce(try(each.value.labels, null), {}),
      var.compose_project != null ? { "com.docker.compose.project" = var.compose_project } : {}
    )
    content {
      label = labels.key
      value = labels.value
    }
  }

  dynamic "healthcheck" {
    for_each = try(each.value.healthcheck, null) != null ? [each.value.healthcheck] : []
    content {
      test         = healthcheck.value.test
      interval     = healthcheck.value.interval
      timeout      = healthcheck.value.timeout
      retries      = healthcheck.value.retries
      start_period = healthcheck.value.start_period
    }
  }

  dynamic "networks_advanced" {
    for_each = length(coalesce(try(each.value.networks, null), [])) > 0 ? each.value.networks : [local.network_name]
    content {
      name         = networks_advanced.value
      ipv4_address = (networks_advanced.value == local.network_name && try(local.container_ipv4[each.key], null) != null) ? split("/", local.container_ipv4[each.key])[0] : null
    }
  }

  depends_on = [
    docker_network.main,
    docker_image.instances,
    docker_volume.named
  ]

  lifecycle {
    create_before_destroy = false
  }
}
