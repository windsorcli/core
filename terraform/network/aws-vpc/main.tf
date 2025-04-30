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

  map_public_ip_on_launch = true

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
