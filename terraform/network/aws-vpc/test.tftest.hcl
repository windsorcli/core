mock_provider "aws" {}

# Verifies that the module creates the VPC and subnets with minimal configuration.
# Tests default values for naming, CIDR, and subnet creation.
run "minimal_configuration" {
  command = plan

  variables {
    context_id = "test"
  }

  assert {
    condition     = aws_vpc.main.tags.Name == "network-test"
    error_message = "VPC name should follow default naming convention"
  }

  assert {
    condition     = aws_vpc.main.cidr_block == "10.0.0.0/16"
    error_message = "VPC CIDR should default to '10.0.0.0/16'"
  }

  assert {
    condition     = length(aws_subnet.public) == 3
    error_message = "Three public subnets should be created by default (one per AZ)"
  }

  assert {
    condition     = length(aws_subnet.private) == 3
    error_message = "Three private subnets should be created by default (one per AZ)"
  }

  assert {
    condition     = length(aws_subnet.isolated) == 3
    error_message = "Three isolated subnets should be created by default (one per AZ)"
  }

  assert {
    condition     = length(aws_nat_gateway.main) == 3
    error_message = "Three NAT Gateways should be created by default (one per AZ)"
  }

  assert {
    condition     = aws_internet_gateway.main.vpc_id == aws_vpc.main.id
    error_message = "Internet Gateway should be attached to the VPC"
  }
}

# Tests a full configuration with all optional variables explicitly set.
# Validates that user-supplied values override defaults for naming, CIDR, and subnet creation.
run "full_configuration" {
  command = plan

  variables {
    name               = "custom-vpc"
    cidr_block         = "10.30.0.0/16"
    availability_zones = 2
    subnet_newbits     = 8
    enable_flow_logs   = true
    context_id         = "test"
  }

  assert {
    condition     = aws_vpc.main.tags.Name == "custom-vpc"
    error_message = "VPC name should match input"
  }

  assert {
    condition     = aws_vpc.main.cidr_block == "10.30.0.0/16"
    error_message = "VPC CIDR should match input"
  }

  assert {
    condition     = length(aws_subnet.public) == 2
    error_message = "Two public subnets should be created"
  }

  assert {
    condition     = length(aws_subnet.private) == 2
    error_message = "Two private subnets should be created"
  }

  assert {
    condition     = length(aws_subnet.isolated) == 2
    error_message = "Two isolated subnets should be created"
  }

  assert {
    condition     = length(aws_nat_gateway.main) == 2
    error_message = "Two NAT Gateways should be created"
  }

  assert {
    condition     = length(aws_flow_log.vpc_flow_logs) == 1
    error_message = "VPC Flow Logs should be enabled"
  }
}
