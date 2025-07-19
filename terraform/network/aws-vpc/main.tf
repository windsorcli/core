// Define the required Terraform version and providers
terraform {
  required_version = ">=1.8"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.7.2"
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

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  name = var.name != "" ? var.name : "network-${var.context_id}"
}

#-----------------------------------------------------------------------------------------------------------------------
# AWS VPC Configuration
#-----------------------------------------------------------------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = local.name
  }
}

resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id

  # Ensure no ingress rules are defined (restricting all inbound traffic)
  ingress = []

  # Ensure no egress rules are defined (restricting all outbound traffic)
  egress = []

  tags = {
    Name        = "${local.name}-default"
    Description = "Default security group with all traffic restricted"
  }
}

# Enable VPC Flow Logs
resource "aws_flow_log" "main" {
  count                    = var.enable_cloudwatch_logs ? 1 : 0
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.vpc_flow_logs[0].arn
  iam_role_arn             = aws_iam_role.vpc_flow_logs[0].arn
  traffic_type             = "ALL"
  vpc_id                   = aws_vpc.main.id
  max_aggregation_interval = 60

  tags = {
    Name = "${local.name}-flow-logs"
  }
}

resource "random_string" "log_group_suffix" {
  count   = var.enable_flow_logs ? 1 : 0
  length  = 3
  special = false
  upper   = false
}

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/vpc/flow-logs/${local.name}"
  retention_in_days = 365
  kms_key_id        = var.create_flow_logs_kms_key ? aws_kms_key.vpc_flow_logs[0].arn : var.flow_logs_kms_key_id

  tags = {
    Name = "${local.name}-flow-logs"
  }
}

resource "null_resource" "delete_vpc_flow_logs" {
  count = var.enable_cloudwatch_logs ? 1 : 0

  triggers = {
    log_group_name = aws_cloudwatch_log_group.vpc_flow_logs[0].name
  }

  provisioner "local-exec" {
    when    = destroy
    command = "aws logs delete-log-group --log-group-name \"${self.triggers.log_group_name}\""
  }

  depends_on = [aws_vpc.main]
}

resource "aws_kms_key" "vpc_flow_logs" {
  count                   = var.create_flow_logs_kms_key ? 1 : 0
  description             = "KMS key for CloudWatch Logs encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "Enable IAM User Permissions",
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        },
        Action   = "kms:*",
        Resource = "*"
      },
      {
        Sid    = "Allow CloudWatch Logs to use the key",
        Effect = "Allow",
        Principal = {
          Service = "logs.${data.aws_region.current.name}.amazonaws.com"
        },
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "vpc_flow_logs" {
  count         = var.create_flow_logs_kms_key ? 1 : 0
  name          = "alias/${local.name}-flow-logs"
  target_key_id = aws_kms_key.vpc_flow_logs[0].key_id
}

resource "aws_iam_role" "vpc_flow_logs" {
  count = var.enable_cloudwatch_logs ? 1 : 0
  name  = "${local.name}-vpc-flow-logs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${local.name}-vpc-flow-logs"
  }
}

resource "aws_iam_role_policy" "vpc_flow_logs" {
  count = var.enable_cloudwatch_logs ? 1 : 0
  name  = "${local.name}-vpc-flow-logs"
  role  = aws_iam_role.vpc_flow_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/vpc/flow-logs/${local.name}-*"
        ]
      }
    ]
  })
}

#-----------------------------------------------------------------------------------------------------------------------
# Subnets
#-----------------------------------------------------------------------------------------------------------------------

data "aws_availability_zones" "available" {}

# Public Subnets
resource "aws_subnet" "public" {
  count             = var.availability_zones
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.cidr_block, var.subnet_newbits, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  map_public_ip_on_launch = false # Disable automatic public IP assignment for security

  tags = {
    Name = "${local.name}-public-${data.aws_availability_zones.available.names[count.index]}"
    Tier = "public"
  }
}

# Private Subnets
resource "aws_subnet" "private" {
  count  = var.availability_zones
  vpc_id = aws_vpc.main.id
  cidr_block = cidrsubnet(
    var.cidr_block, var.subnet_newbits, count.index + length(data.aws_availability_zones.available.names)
  )
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${local.name}-private-${data.aws_availability_zones.available.names[count.index]}"
    Tier = "private"
  }
}

# Isolated Subnets
resource "aws_subnet" "isolated" {
  count  = var.availability_zones
  vpc_id = aws_vpc.main.id
  cidr_block = cidrsubnet(
    var.cidr_block, var.subnet_newbits, count.index + 2 * length(data.aws_availability_zones.available.names)
  )
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${local.name}-isolated-${data.aws_availability_zones.available.names[count.index]}"
    Tier = "isolated"
  }
}

#-----------------------------------------------------------------------------------------------------------------------
# Internet Gateway
#-----------------------------------------------------------------------------------------------------------------------

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = local.name
  }
}

#-----------------------------------------------------------------------------------------------------------------------
# NAT Gateways
#-----------------------------------------------------------------------------------------------------------------------

resource "aws_eip" "nat" {
  count  = var.availability_zones
  domain = "vpc"

  tags = {
    Name = "${local.name}-nat-${data.aws_availability_zones.available.names[count.index]}"
  }
}

resource "aws_nat_gateway" "main" {
  count         = var.availability_zones
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "${local.name}-nat-${data.aws_availability_zones.available.names[count.index]}"
  }

  depends_on = [aws_internet_gateway.main]
}

#-----------------------------------------------------------------------------------------------------------------------
# Route Tables
#-----------------------------------------------------------------------------------------------------------------------

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${local.name}-public"
  }
}

# Private Route Tables (one per AZ)
resource "aws_route_table" "private" {
  count  = var.availability_zones
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = {
    Name = "${local.name}-private-${data.aws_availability_zones.available.names[count.index]}"
  }
}

# Isolated Route Tables (one per AZ)
resource "aws_route_table" "isolated" {
  count  = var.availability_zones
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name}-isolated-${data.aws_availability_zones.available.names[count.index]}"
  }
}

#-----------------------------------------------------------------------------------------------------------------------
# Route Table Associations
#-----------------------------------------------------------------------------------------------------------------------

# Public Subnet Associations
resource "aws_route_table_association" "public" {
  count          = var.availability_zones
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private Subnet Associations
resource "aws_route_table_association" "private" {
  count          = var.availability_zones
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Isolated Subnet Associations
resource "aws_route_table_association" "isolated" {
  count          = var.availability_zones
  subnet_id      = aws_subnet.isolated[count.index].id
  route_table_id = aws_route_table.isolated[count.index].id
}

#-----------------------------------------------------------------------------------------------------------------------
# Route53 Hosted Zone
#-----------------------------------------------------------------------------------------------------------------------
resource "aws_route53_zone" "main" {
  count = var.domain_name != null ? 1 : 0
  name  = var.domain_name

  vpc {
    vpc_id = aws_vpc.main.id
  }
}
