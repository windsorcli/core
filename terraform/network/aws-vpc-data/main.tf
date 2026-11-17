# Reads an existing VPC and its subnets and emits the same outputs as network/aws-vpc.

terraform {
  required_version = ">= 1.12.2"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.68.0"
    }
  }
}

provider "aws" {
  default_tags {
    tags = merge(
      var.tags,
      {
        WindsorContextID = var.context_id
        ManagedBy        = "Terraform"
      }
    )
  }
}

data "aws_vpc" "main" {
  id = var.vpc_id
}

locals {
  subnet_ids = toset(concat(var.public_subnet_ids, var.private_subnet_ids, var.isolated_subnet_ids))
}

data "aws_subnet" "selected" {
  for_each = local.subnet_ids
  id       = each.value

  lifecycle {
    postcondition {
      condition     = self.vpc_id == data.aws_vpc.main.id
      error_message = "Subnet ${each.value} belongs to ${self.vpc_id}, not ${var.vpc_id}."
    }
  }
}

locals {
  public_subnet_ids   = [for id in var.public_subnet_ids : data.aws_subnet.selected[id].id]
  private_subnet_ids  = [for id in var.private_subnet_ids : data.aws_subnet.selected[id].id]
  isolated_subnet_ids = [for id in var.isolated_subnet_ids : data.aws_subnet.selected[id].id]
  private_zones       = distinct([for id in var.private_subnet_ids : data.aws_subnet.selected[id].availability_zone])
  isolated_zones      = distinct([for id in var.isolated_subnet_ids : data.aws_subnet.selected[id].availability_zone])
}

resource "aws_db_subnet_group" "main" {
  count      = length(var.isolated_subnet_ids) > 0 ? 1 : 0
  name       = "rds-${var.context_id}"
  subnet_ids = local.isolated_subnet_ids

  tags = {
    Name = "rds-${var.context_id}"
  }

  lifecycle {
    precondition {
      condition     = length(local.isolated_zones) >= 2
      error_message = "isolated_subnet_ids span ${length(local.isolated_zones)} availability zone(s); an RDS subnet group needs at least 2."
    }
  }
}

data "aws_route53_zone" "private" {
  count   = var.private_zone_id != null ? 1 : 0
  zone_id = var.private_zone_id
}
