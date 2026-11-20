# The aws-ec2 compute module launches Talos Linux nodes on EC2 in a subnet, at fixed or subnet-assigned private IPs, for the aws platform's cluster/talos step to bootstrap.

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
    time = {
      source  = "hashicorp/time"
      version = "~> 0.13"
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

data "aws_caller_identity" "current" {}

data "http" "talos_images" {
  url = "https://github.com/siderolabs/talos/releases/download/v${trimprefix(var.talos_version, "v")}/cloud-images.json"
}

locals {
  talos_amis = [
    for image in jsondecode(data.http.talos_images.response_body) : image.id
    if try(image.cloud, "aws") == "aws" && image.region == var.region && image.arch == "amd64" && startswith(image.id, "ami-")
  ]
  ami_id      = try(local.talos_amis[0], null)
  name_suffix = var.context_id != "" ? "-${var.context_id}" : ""
  tags = merge(
    var.context_id != "" ? { "windsorcli.dev/context-id" = var.context_id } : {},
    var.ephemeral ? { "windsorcli.dev/ephemeral" = "true", "windsorcli.dev/created-at" = time_static.created[0].rfc3339 } : {},
  )

  nodes = merge(
    { for node in var.controlplanes : node.hostname => merge(node, { role = "controlplane", instance_type = var.controlplane_instance_type, root_volume = var.controlplane_root_volume }) },
    { for node in var.workers : node.hostname => merge(node, { role = "worker", instance_type = coalesce(var.worker_instance_type, var.controlplane_instance_type), root_volume = var.worker_root_volume }) },
  )

  ingress_ports = {
    talos      = { from = 50000, to = 50000 }
    kubernetes = { from = 6443, to = 6443 }
    nodeports  = { from = 30000, to = 32767 }
  }
}

resource "time_static" "created" {
  count = var.ephemeral ? 1 : 0
}

resource "aws_kms_key" "ebs" {
  description             = "Talos node root volumes${local.name_suffix}"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  tags                    = merge(local.tags, { Name = "talos${local.name_suffix}-ebs" })

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid       = "Enable IAM User Permissions",
        Effect    = "Allow",
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" },
        Action    = "kms:*",
        Resource  = "*"
      },
      {
        Sid       = "Allow EC2 to use the key for EBS volume encryption",
        Effect    = "Allow",
        Principal = { Service = "ec2.amazonaws.com" },
        Action    = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey", "kms:CreateGrant"],
        Resource  = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "ebs" {
  name          = "alias/talos${local.name_suffix}-ebs"
  target_key_id = aws_kms_key.ebs.key_id
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
  cidr_ipv4         = data.aws_vpc.this.cidr_block
}

resource "aws_vpc_security_group_ingress_rule" "nodes" {
  security_group_id            = aws_security_group.this.id
  description                  = "node to node"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.this.id
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  description       = "all"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_instance" "this" {
  # checkov:skip=CKV_AWS_126: Detailed monitoring is billed per instance.
  # checkov:skip=CKV2_AWS_41: Talos nodes use no instance profile.
  for_each               = local.nodes
  ami                    = local.ami_id
  instance_type          = each.value.instance_type
  subnet_id              = var.subnet_id
  private_ip             = each.value.node
  vpc_security_group_ids = [aws_security_group.this.id]
  ebs_optimized          = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size           = each.value.root_volume.size
    volume_type           = "gp3"
    iops                  = each.value.root_volume.iops
    throughput            = each.value.root_volume.throughput
    encrypted             = true
    kms_key_id            = aws_kms_key.ebs.arn
    delete_on_termination = true
  }

  tags        = merge(local.tags, { Name = "${each.key}${local.name_suffix}", "windsorcli.dev/role" = each.value.role })
  volume_tags = merge(local.tags, { Name = "${each.key}${local.name_suffix}" })

  lifecycle {
    ignore_changes = [ami]

    precondition {
      condition     = local.ami_id != null
      error_message = "No amd64 Talos AMI is published for talos_version ${var.talos_version} in region ${var.region}."
    }
  }
}
