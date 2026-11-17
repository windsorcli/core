mock_provider "aws" {
  mock_data "aws_route53_zone" {
    defaults = {
      name = "corp.example.internal"
    }
  }
}

override_data {
  target = data.aws_subnet.selected["subnet-0a01"]
  values = {
    id                = "subnet-0a01"
    vpc_id            = "vpc-0abc"
    availability_zone = "us-east-1a"
  }
}

override_data {
  target = data.aws_subnet.selected["subnet-0b01"]
  values = {
    id                = "subnet-0b01"
    vpc_id            = "vpc-0abc"
    availability_zone = "us-east-1b"
  }
}

override_data {
  target = data.aws_subnet.selected["subnet-0a02"]
  values = {
    id                = "subnet-0a02"
    vpc_id            = "vpc-0abc"
    availability_zone = "us-east-1a"
  }
}

override_data {
  target = data.aws_subnet.selected["subnet-0b02"]
  values = {
    id                = "subnet-0b02"
    vpc_id            = "vpc-0abc"
    availability_zone = "us-east-1b"
  }
}

override_data {
  target = data.aws_subnet.selected["subnet-0f99"]
  values = {
    id                = "subnet-0f99"
    vpc_id            = "vpc-0other"
    availability_zone = "us-east-1a"
  }
}

run "private_only" {
  command = plan

  variables {
    context_id         = "test"
    vpc_id             = "vpc-0abc"
    private_subnet_ids = ["subnet-0a01", "subnet-0b01"]
  }

  assert {
    condition     = output.vpc_id == "vpc-0abc"
    error_message = "vpc_id should pass through the supplied VPC"
  }

  assert {
    condition     = output.private_subnet_ids == ["subnet-0a01", "subnet-0b01"]
    error_message = "private_subnet_ids should keep the supplied order"
  }

  assert {
    condition     = output.public_subnet_ids == [] && output.isolated_subnet_ids == []
    error_message = "Unset tiers should be empty"
  }

  assert {
    condition     = length(aws_db_subnet_group.main) == 0
    error_message = "No DB subnet group without isolated subnets"
  }

  assert {
    condition     = output.private_zone_id == null && output.private_zone_name == null
    error_message = "Private zone outputs should be null without private_zone_id"
  }
}

run "all_tiers" {
  command = plan

  variables {
    context_id          = "test"
    vpc_id              = "vpc-0abc"
    public_subnet_ids   = ["subnet-0a01", "subnet-0b01"]
    private_subnet_ids  = ["subnet-0a01", "subnet-0b01"]
    isolated_subnet_ids = ["subnet-0a02", "subnet-0b02"]
    private_zone_id     = "Z0123456789"
  }

  assert {
    condition     = output.public_subnet_ids == ["subnet-0a01", "subnet-0b01"]
    error_message = "A subnet may serve more than one tier"
  }

  assert {
    condition     = aws_db_subnet_group.main[0].name == "rds-test"
    error_message = "DB subnet group should be named rds-<context_id>"
  }

  assert {
    condition     = toset(aws_db_subnet_group.main[0].subnet_ids) == toset(["subnet-0a02", "subnet-0b02"])
    error_message = "DB subnet group should span the isolated subnets"
  }

  assert {
    condition     = output.private_zone_name == "corp.example.internal"
    error_message = "private_zone_name should come from the supplied zone"
  }
}

run "private_single_zone_rejected" {
  command = plan

  variables {
    context_id         = "test"
    vpc_id             = "vpc-0abc"
    private_subnet_ids = ["subnet-0a01", "subnet-0a02"]
  }

  expect_failures = [output.private_subnet_ids]
}

run "isolated_single_zone_rejected" {
  command = plan

  variables {
    context_id          = "test"
    vpc_id              = "vpc-0abc"
    private_subnet_ids  = ["subnet-0a01", "subnet-0b01"]
    isolated_subnet_ids = ["subnet-0a01", "subnet-0a02"]
  }

  expect_failures = [aws_db_subnet_group.main]
}

run "subnet_outside_vpc_rejected" {
  command = plan

  variables {
    context_id         = "test"
    vpc_id             = "vpc-0abc"
    private_subnet_ids = ["subnet-0a01", "subnet-0b01", "subnet-0f99"]
  }

  expect_failures = [data.aws_subnet.selected]
}

run "empty_private_rejected" {
  command = plan

  variables {
    context_id         = "test"
    vpc_id             = "vpc-0abc"
    private_subnet_ids = []
  }

  expect_failures = [var.private_subnet_ids]
}

run "malformed_vpc_id_rejected" {
  command = plan

  variables {
    context_id         = "test"
    vpc_id             = "network-1"
    private_subnet_ids = ["subnet-0a01", "subnet-0b01"]
  }

  expect_failures = [var.vpc_id]
}
