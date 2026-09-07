#---------------------------------------------------------------------------------------------------
# Providers Configuration
# This section defines the required providers for the Terraform configuration.
# Project and credentials come from GOOGLE_CLOUD_PROJECT / Application Default
# Credentials, matching how the azurerm network module relies on ARM_* env vars.
#---------------------------------------------------------------------------------------------------

terraform {
  required_version = ">= 1.12.2"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "8.1.0"
    }
  }
}

#---------------------------------------------------------------------------------------------------
# Local Variables
#---------------------------------------------------------------------------------------------------

locals {
  network_name = var.network_name != "" ? var.network_name : "${var.name}-${var.context_id}"
  zone_names   = slice(data.google_compute_zones.available.names, 0, min(var.zone_count, length(data.google_compute_zones.available.names)))
}

#---------------------------------------------------------------------------------------------------
# VPC Network
# The network is the project-wide container for every subnet below. It
# disables auto-created subnets so each tier is explicitly sized.
#---------------------------------------------------------------------------------------------------

resource "google_compute_network" "this" {
  name                    = local.network_name
  auto_create_subnetworks = false
}

#---------------------------------------------------------------------------------------------------
# Zones
# Zones downstream node placement chooses from, capped to var.zone_count.
#---------------------------------------------------------------------------------------------------

data "google_compute_zones" "available" {
  region = var.region
  status = "UP"
}

#---------------------------------------------------------------------------------------------------
# Subnets
# GCP subnets are regional, not zonal — one subnet per tier already spans
# every zone in the region, unlike AWS/Azure's one-subnet-per-AZ model.
#---------------------------------------------------------------------------------------------------

# Public subnet holds resources that route directly to the internet gateway.
resource "google_compute_subnetwork" "public" {
  name                     = "public-${var.context_id}"
  network                  = google_compute_network.this.id
  region                   = var.region
  ip_cidr_range            = var.public_subnet_cidr != "" ? var.public_subnet_cidr : cidrsubnet(var.cidr_block, 4, 1)
  private_ip_google_access = true

  dynamic "log_config" {
    for_each = var.enable_flow_logs ? [1] : []
    content {
      aggregation_interval = "INTERVAL_5_SEC"
      flow_sampling        = 0.5
      metadata             = "INCLUDE_ALL_METADATA"
    }
  }
}

# Private subnet egresses through Cloud NAT and never receives a public IP.
resource "google_compute_subnetwork" "private" {
  name                     = "private-${var.context_id}"
  network                  = google_compute_network.this.id
  region                   = var.region
  ip_cidr_range            = var.private_subnet_cidr != "" ? var.private_subnet_cidr : cidrsubnet(var.cidr_block, 2, 1)
  private_ip_google_access = true

  dynamic "log_config" {
    for_each = var.enable_flow_logs ? [1] : []
    content {
      aggregation_interval = "INTERVAL_5_SEC"
      flow_sampling        = 0.5
      metadata             = "INCLUDE_ALL_METADATA"
    }
  }
}

# Isolated subnet has no NAT route, for resources that must not reach the
# internet in either direction (e.g. a managed database's private peering).
resource "google_compute_subnetwork" "isolated" {
  name                     = "isolated-${var.context_id}"
  network                  = google_compute_network.this.id
  region                   = var.region
  ip_cidr_range            = var.isolated_subnet_cidr != "" ? var.isolated_subnet_cidr : cidrsubnet(var.cidr_block, 4, 0)
  private_ip_google_access = true

  dynamic "log_config" {
    for_each = var.enable_flow_logs ? [1] : []
    content {
      aggregation_interval = "INTERVAL_5_SEC"
      flow_sampling        = 0.5
      metadata             = "INCLUDE_ALL_METADATA"
    }
  }
}

#---------------------------------------------------------------------------------------------------
# Firewall
# GCP VPCs deny all ingress by default. These rules open the traffic a
# Kubernetes cluster and its operators need.
#---------------------------------------------------------------------------------------------------

# Cluster nodes, pods, and services all reach each other over the VPC's own
# CIDR — GKE and Cilium both depend on this being open.
resource "google_compute_firewall" "internal" {
  name          = "${local.network_name}-allow-internal"
  network       = google_compute_network.this.id
  direction     = "INGRESS"
  source_ranges = [var.cidr_block]

  allow {
    protocol = "all"
  }
}

# GCP's load balancer and node health checks originate from these two fixed
# ranges (cloud.google.com/load-balancing/docs/health-check-concepts#ip-ranges).
resource "google_compute_firewall" "health_checks" {
  name          = "${local.network_name}-allow-health-checks"
  network       = google_compute_network.this.id
  direction     = "INGRESS"
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]

  allow {
    protocol = "tcp"
  }
}

# Identity-Aware Proxy's fixed range is GCP's recommended path for SSH/RDP to
# instances with no public IP, replacing bastion hosts.
resource "google_compute_firewall" "iap_ingress" {
  count         = var.enable_iap_ingress ? 1 : 0
  name          = "${local.network_name}-allow-iap-ingress"
  network       = google_compute_network.this.id
  direction     = "INGRESS"
  source_ranges = ["35.235.240.0/20"]

  allow {
    protocol = "tcp"
    ports    = ["22", "3389"]
  }
}

#---------------------------------------------------------------------------------------------------
# Cloud NAT
# Gives the private subnet outbound internet access with no public IP on
# any instance, the GCP equivalent of a NAT Gateway.
#---------------------------------------------------------------------------------------------------

# Cloud Router is the control-plane prerequisite Cloud NAT attaches to.
resource "google_compute_router" "this" {
  count   = var.enable_nat ? 1 : 0
  name    = "${local.network_name}-router"
  network = google_compute_network.this.id
  region  = var.region
}

resource "google_compute_router_nat" "this" {
  count                              = var.enable_nat ? 1 : 0
  name                               = "${local.network_name}-nat"
  router                             = google_compute_router.this[0].name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.private.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}
