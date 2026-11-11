# The aws-ec2 compute module launches Talos Linux nodes on EC2 at fixed private IPs in an existing subnet, so the metal platform's cluster/talos step can bootstrap them as it would bare-metal machines.

terraform {
  required_version = ">= 1.12.2"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.68.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "3.5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

data "aws_subnet" "this" {
  id = var.subnet_id
}

data "aws_vpc" "this" {
  id = data.aws_subnet.this.vpc_id
}

data "http" "talos_images" {
  count = var.ami_id == "" ? 1 : 0
  url   = "https://github.com/siderolabs/talos/releases/download/v${trimprefix(var.talos_version, "v")}/cloud-images.json"
}

locals {
  talos_images = var.ami_id == "" ? jsondecode(data.http.talos_images[0].response_body) : []
  talos_amis = [
    for image in local.talos_images : image.id
    if try(image.cloud, "aws") == "aws" && image.region == var.region && image.arch == "amd64" && startswith(image.id, "ami-")
  ]
  ami_id       = var.ami_id != "" ? var.ami_id : local.talos_amis[0]
  allowed_cidr = var.allowed_cidr != "" ? var.allowed_cidr : data.aws_vpc.this.cidr_block
  name_suffix  = var.context_id != "" ? "-${var.context_id}" : ""
  tags         = merge(var.tags, var.context_id != "" ? { "windsorcli.dev/context-id" = var.context_id } : {})

  nodes = merge(
    { for node in var.controlplanes : node.hostname => merge(node, { role = "controlplane", instance_type = var.controlplane_instance_type }) },
    { for node in var.workers : node.hostname => merge(node, { role = "worker", instance_type = coalesce(var.worker_instance_type, var.controlplane_instance_type) }) },
  )

  ingress_ports = {
    talos      = { from = 50000, to = 50000 }
    kubernetes = { from = 6443, to = 6443 }
    nodeports  = { from = 30000, to = 32767 }
  }
}

resource "aws_security_group" "this" {
  name        = "talos${local.name_suffix}"
  description = "Talos nodes${local.name_suffix}"
  vpc_id      = data.aws_vpc.this.id
  tags        = merge(local.tags, { Name = "talos${local.name_suffix}" })
}

resource "aws_vpc_security_group_ingress_rule" "this" {
  for_each          = local.ingress_ports
  security_group_id = aws_security_group.this.id
  description       = each.key
  ip_protocol       = "tcp"
  from_port         = each.value.from
  to_port           = each.value.to
  cidr_ipv4         = local.allowed_cidr
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  description       = "all"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_instance" "this" {
  for_each               = local.nodes
  ami                    = local.ami_id
  instance_type          = each.value.instance_type
  subnet_id              = var.subnet_id
  private_ip             = each.value.node
  vpc_security_group_ids = [aws_security_group.this.id]

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    iops                  = var.root_volume_iops
    throughput            = var.root_volume_throughput
    encrypted             = true
    kms_key_id            = var.kms_key_id
    delete_on_termination = true
  }

  tags        = merge(local.tags, { Name = "${each.key}${local.name_suffix}", "windsorcli.dev/role" = each.value.role })
  volume_tags = merge(local.tags, { Name = "${each.key}${local.name_suffix}" })

  lifecycle {
    ignore_changes = [ami]
  }
}
