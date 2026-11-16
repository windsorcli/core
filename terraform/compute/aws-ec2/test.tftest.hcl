mock_provider "aws" {
  mock_data "aws_subnet" {
    defaults = {
      vpc_id = "vpc-0123456789abcdef0"
    }
  }

  mock_data "aws_vpc" {
    defaults = {
      id         = "vpc-0123456789abcdef0"
      cidr_block = "10.150.0.0/16"
    }
  }
}

mock_provider "http" {
  mock_data "http" {
    defaults = {
      response_body = "[{\"cloud\":\"aws\",\"region\":\"us-east-1\",\"arch\":\"amd64\",\"id\":\"ami-0aaaaaaaaaaaaaaa1\"},{\"cloud\":\"aws\",\"region\":\"us-east-2\",\"arch\":\"arm64\",\"id\":\"ami-0bbbbbbbbbbbbbbb2\"},{\"cloud\":\"aws\",\"region\":\"us-east-2\",\"arch\":\"amd64\",\"id\":\"ami-0ccccccccccccccc3\"}]"
    }
  }
}

variables {
  context_id                 = "test123"
  region                     = "us-east-2"
  subnet_id                  = "subnet-0123456789abcdef0"
  talos_version              = "1.11.5"
  controlplane_instance_type = "m6a.2xlarge"
  controlplanes = [
    { hostname = "controlplane-1", node = "10.150.1.37" },
  ]
}

run "single_controlplane" {
  command = plan

  assert {
    condition     = length(aws_instance.this) == 1
    error_message = "Exactly one instance should be planned for a single control plane."
  }

  assert {
    condition     = aws_instance.this["controlplane-1"].private_ip == "10.150.1.37"
    error_message = "The instance should launch at the node address."
  }

  assert {
    condition     = aws_instance.this["controlplane-1"].ami == "ami-0ccccccccccccccc3"
    error_message = "The published amd64 Talos AMI for the region should be picked."
  }

  assert {
    condition     = aws_instance.this["controlplane-1"].instance_type == "m6a.2xlarge"
    error_message = "The control plane instance type should be used."
  }

  assert {
    condition     = aws_instance.this["controlplane-1"].tags["Name"] == "controlplane-1-test123"
    error_message = "The instance name should carry the context id."
  }

  assert {
    condition     = aws_instance.this["controlplane-1"].metadata_options[0].http_tokens == "required"
    error_message = "IMDSv2 should be required."
  }

  assert {
    condition     = aws_instance.this["controlplane-1"].root_block_device[0].encrypted == true
    error_message = "The root volume should be encrypted."
  }

  assert {
    condition     = alltrue([for rule in aws_vpc_security_group_ingress_rule.this : rule.cidr_ipv4 == "10.150.0.0/16"])
    error_message = "Ingress should be limited to the VPC CIDR."
  }

  assert {
    condition     = aws_kms_alias.ebs.name == "alias/talos-test123-ebs" && aws_kms_key.ebs.enable_key_rotation == true
    error_message = "A rotating KMS key should be created for the root volumes."
  }

  assert {
    condition     = aws_instance.this["controlplane-1"].root_block_device[0].volume_size == 100 && aws_instance.this["controlplane-1"].root_block_device[0].iops == 3000 && aws_instance.this["controlplane-1"].root_block_device[0].throughput == 125
    error_message = "The root volume should default to 100 GB, 3000 IOPS and 125 MB/s."
  }

  assert {
    condition     = output.controlplanes[0].endpoint == "10.150.1.37:50000" && length(output.workers) == 0
    error_message = "Outputs should describe the control plane in cluster/talos shape."
  }
}

run "workers_and_root_volumes" {
  command = plan

  variables {
    controlplane_root_volume = { size = 200, iops = 6000, throughput = 250 }
    worker_root_volume       = { size = 50 }
    worker_instance_type     = "m6a.large"
    workers = [
      { hostname = "worker-1", node = "10.150.1.40" },
      { hostname = "worker-2", node = "10.150.1.41" },
    ]
  }

  assert {
    condition     = length(aws_instance.this) == 3
    error_message = "One instance per control plane and worker should be planned."
  }

  assert {
    condition     = aws_instance.this["worker-2"].instance_type == "m6a.large" && aws_instance.this["worker-2"].private_ip == "10.150.1.41"
    error_message = "Workers should use the worker instance type at their node address."
  }

  assert {
    condition     = aws_instance.this["controlplane-1"].root_block_device[0].volume_size == 200 && aws_instance.this["controlplane-1"].root_block_device[0].iops == 6000 && aws_instance.this["controlplane-1"].root_block_device[0].throughput == 250
    error_message = "Control planes should use the control plane root volume."
  }

  assert {
    condition     = aws_instance.this["worker-1"].root_block_device[0].volume_size == 50 && aws_instance.this["worker-1"].root_block_device[0].iops == 3000
    error_message = "Workers should use the worker root volume with its own defaults."
  }

  assert {
    condition     = length(output.workers) == 2
    error_message = "Worker outputs should list both workers."
  }
}

run "worker_type_defaults_to_controlplane" {
  command = plan

  variables {
    workers = [
      { hostname = "worker-1", node = "10.150.1.40" },
    ]
  }

  assert {
    condition     = aws_instance.this["worker-1"].instance_type == "m6a.2xlarge"
    error_message = "Workers should fall back to the control plane instance type."
  }
}

run "requires_a_controlplane" {
  command = plan

  variables {
    controlplanes = []
  }

  expect_failures = [var.controlplanes]
}

run "rejects_a_tiny_root_volume" {
  command = plan

  variables {
    controlplane_root_volume = { size = 4 }
  }

  expect_failures = [var.controlplane_root_volume]
}
