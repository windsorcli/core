mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
      arn        = "arn:aws:iam::123456789012:user/test-user"
      user_id    = "AIDAJQABLZS4A3QDU576Q"
    }
  }
  mock_data "aws_region" {
    defaults = {
      name = "us-east-1"
    }
  }
  mock_data "aws_availability_zones" {
    defaults = {
      names    = ["us-east-1a", "us-east-1b", "us-east-1c"]
      zone_ids = ["use1-az1", "use1-az2", "use1-az3"]
      id       = "us-east-1"
    }
  }
}

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
    condition     = length(aws_flow_log.main) == 1
    error_message = "VPC Flow Logs should be enabled"
  }
}

run "cloudwatch_logs_disabled" {
  command = plan

  variables {
    enable_cloudwatch_logs = false
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.vpc_flow_logs) == 0
    error_message = "No CloudWatch log group should be created when logging is disabled"
  }
  assert {
    condition     = length(aws_flow_log.main) == 0
    error_message = "No VPC flow log should be created when logging is disabled"
  }
}

# Default: skip_destroy is true so historical flow logs survive teardown
# and age out via retention_in_days. Logs outliving the infra is the
# safer default for environments that may need forensics or compliance
# retention; ephemeral envs opt out by setting preserve_logs_on_destroy=false.
run "preserve_logs_default_true" {
  command = plan

  variables {
    context_id = "test"
  }

  assert {
    condition     = aws_cloudwatch_log_group.vpc_flow_logs[0].skip_destroy == true
    error_message = "skip_destroy must default to true so logs survive destroy by default."
  }
}

# Opt-out: ephemeral environments can flip the flag false to get the
# original "destroy removes the log group" behavior.
run "preserve_logs_opt_out" {
  command = plan

  variables {
    context_id               = "test"
    preserve_logs_on_destroy = false
  }

  assert {
    condition     = aws_cloudwatch_log_group.vpc_flow_logs[0].skip_destroy == false
    error_message = "skip_destroy should be wired to preserve_logs_on_destroy and flip to false when opted out."
  }
}
