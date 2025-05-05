// Define the required Terraform version and providers
terraform {
  required_version = ">=1.8"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

#-----------------------------------------------------------------------------------------------------------------------
# AWS VPC Configuration
#-----------------------------------------------------------------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name}-vpc"
  }
}

# Enable VPC Flow Logs
resource "aws_flow_log" "vpc_flow_logs" {
  log_destination      = aws_cloudwatch_log_group.vpc_flow_logs.arn
  log_destination_type = "cloud-watch-logs"
  traffic_type         = "ALL"
  vpc_id               = aws_vpc.main.id
  iam_role_arn         = aws_iam_role.vpc_flow_logs.arn
}

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws/vpc-flow-logs/${var.name}"
  retention_in_days = 30

  tags = {
    Name = "${var.name}-vpc-flow-logs"
  }
}

resource "aws_iam_role" "vpc_flow_logs" {
  name = "${var.name}-vpc-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "vpc-flow-logs.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "vpc_flow_logs" {
  name = "${var.name}-vpc-flow-logs-policy"
  role = aws_iam_role.vpc_flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Effect   = "Allow"
      Resource = "arn:aws:logs:*:*:log-group:/aws/vpc-flow-logs/*"
    }]
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
    Name = "${var.name}-public-${data.aws_availability_zones.available.names[count.index]}"
    Tier = "public"
  }
}

# Private Subnets
resource "aws_subnet" "private" {
  count             = var.availability_zones
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.cidr_block, var.subnet_newbits, count.index + length(data.aws_availability_zones.available.names))
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.name}-private-${data.aws_availability_zones.available.names[count.index]}"
    Tier = "private"
  }
}

# Data Subnets
resource "aws_subnet" "data" {
  count             = var.availability_zones
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.cidr_block, var.subnet_newbits, count.index + 2 * length(data.aws_availability_zones.available.names))
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.name}-data-${data.aws_availability_zones.available.names[count.index]}"
    Tier = "data"
  }
}

#-----------------------------------------------------------------------------------------------------------------------
# Internet Gateway
#-----------------------------------------------------------------------------------------------------------------------

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name}-igw"
  }
}

#-----------------------------------------------------------------------------------------------------------------------
# NAT Gateways
#-----------------------------------------------------------------------------------------------------------------------

resource "aws_eip" "nat" {
  count  = var.availability_zones
  domain = "vpc"

  tags = {
    Name = "${var.name}-nat-eip-${data.aws_availability_zones.available.names[count.index]}"
  }
}

resource "aws_nat_gateway" "main" {
  count         = var.availability_zones
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "${var.name}-nat-${data.aws_availability_zones.available.names[count.index]}"
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
    Name = "${var.name}-public-rt"
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
    Name = "${var.name}-private-rt-${data.aws_availability_zones.available.names[count.index]}"
  }
}

# Data Route Tables (one per AZ)
resource "aws_route_table" "data" {
  count  = var.availability_zones
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = {
    Name = "${var.name}-data-rt-${data.aws_availability_zones.available.names[count.index]}"
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

# Data Subnet Associations
resource "aws_route_table_association" "data" {
  count          = var.availability_zones
  subnet_id      = aws_subnet.data[count.index].id
  route_table_id = aws_route_table.data[count.index].id
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

# Enable DNS query logging for Route53 hosted zone
resource "aws_cloudwatch_log_group" "route53_query_logs" {
  count = var.domain_name != null ? 1 : 0
  name  = "/aws/route53/${var.domain_name}"

  retention_in_days = 30

  tags = {
    Name = "${var.name}-route53-query-logs"
  }
}

resource "aws_route53_query_log" "main" {
  count                    = var.domain_name != null ? 1 : 0
  depends_on               = [aws_cloudwatch_log_resource_policy.route53_query_logging]
  cloudwatch_log_group_arn = aws_cloudwatch_log_group.route53_query_logs[0].arn
  zone_id                  = aws_route53_zone.main[0].zone_id
}

resource "aws_cloudwatch_log_resource_policy" "route53_query_logging" {
  count       = var.domain_name != null ? 1 : 0
  policy_name = "route53-query-logging-policy"
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
      ]
      Effect    = "Allow"
      Principal = { Service = "route53.amazonaws.com" }
      Resource  = "arn:aws:logs:*:*:log-group:/aws/route53/*"
    }]
  })
}
