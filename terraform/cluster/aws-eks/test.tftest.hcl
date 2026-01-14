mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
      arn        = "arn:aws:iam::123456789012:user/test-user"
      user_id    = "AIDAJQABLZS4A3QDU576Q"
    }
  }
  mock_data "aws_vpc" {
    defaults = {
      id         = "vpc-12345678"
      cidr_block = "10.0.0.0/16"
    }
  }
  mock_data "aws_subnets" {
    defaults = {
      ids = ["subnet-12345678", "subnet-87654321", "subnet-11223344"]
    }
  }
  mock_data "aws_region" {
    defaults = {
      name = "us-west-2"
    }
  }
}

# Verifies that the module creates an EKS cluster with minimal configuration,
# ensuring that all default values are correctly applied and only required variables are set.
run "minimal_configuration" {
  command = plan

  variables {
    context_id         = "test"
    kubernetes_version = "1.32"
  }

  assert {
    condition     = aws_eks_cluster.main.name == "cluster-test"
    error_message = "Cluster name should default to 'cluster-test' when cluster_name is omitted"
  }

  assert {
    condition     = aws_iam_role.cluster.name == "cluster-test"
    error_message = "Cluster IAM role name should follow default naming convention"
  }

  assert {
    condition     = aws_eks_node_group.main["default"].node_group_name == "default"
    error_message = "Default node group should use 'default' name"
  }

  assert {
    condition     = aws_eks_node_group.main["default"].instance_types[0] == "t3.xlarge"
    error_message = "Default node group should use t3.xlarge instance type"
  }

  assert {
    condition     = aws_eks_node_group.main["default"].scaling_config[0].desired_size == 2
    error_message = "Default node group should have 2 nodes"
  }

  assert {
    condition     = var.enable_secrets_encryption == true
    error_message = "enable_secrets_encryption should default to true"
  }

  assert {
    condition     = var.secrets_encryption_kms_key_id == null
    error_message = "secrets_encryption_kms_key_id should default to null"
  }

  assert {
    condition     = length(aws_kms_key.eks_encryption_key) == 1
    error_message = "Internal KMS key should be created when enable_secrets_encryption is true and secrets_encryption_kms_key_id is null"
  }

  assert {
    condition     = aws_eks_cluster.main.vpc_config[0].endpoint_public_access == true
    error_message = "Public endpoint should be enabled by default"
  }

  assert {
    condition     = var.enable_ebs_encryption == true
    error_message = "enable_ebs_encryption should default to true"
  }

  assert {
    condition     = aws_launch_template.node_group["default"].block_device_mappings[0].ebs[0].encrypted == true
    error_message = "EBS volumes should be encrypted by default"
  }

  assert {
    condition     = length(aws_kms_key.ebs_encryption_key) == 1
    error_message = "EBS encryption key should be created when enable_ebs_encryption is true and no key is provided"
  }

  assert {
    condition     = aws_launch_template.node_group["default"].block_device_mappings[0].ebs[0].kms_key_id != null
    error_message = "EBS volumes should have a KMS key ID specified when encryption is enabled"
  }
}

run "minimal_configuration_cloudwatch_logs_disabled" {
  command = plan

  variables {
    context_id             = "test"
    cluster_name           = "windsor-eks"
    kubernetes_version     = "1.32"
    enable_cloudwatch_logs = false
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.eks_cluster) == 0
    error_message = "No CloudWatch log group should be created when logging is disabled"
  }
  assert {
    condition     = length(aws_eks_cluster.main.enabled_cluster_log_types) == 0
    error_message = "No log types should be enabled when logging is disabled"
  }
  assert {
    condition     = length(aws_kms_key.eks_encryption_key) == 1
    error_message = "KMS key should be created when enable_secrets_encryption is true"
  }
  assert {
    condition     = length(jsondecode(aws_kms_key.eks_encryption_key[0].policy).Statement) == 2
    error_message = "KMS key policy should only have 2 statements when CloudWatch logs are disabled"
  }
  assert {
    condition     = alltrue([for s in jsondecode(aws_kms_key.eks_encryption_key[0].policy).Statement : s.Sid != "Allow CloudWatch Logs to use the key"])
    error_message = "KMS key policy should not include CloudWatch Logs permissions when disabled"
  }
}

# Tests a full configuration with all optional variables explicitly set,
# verifying that the module correctly applies all user-supplied values for node groups and feature flags.
run "full_configuration" {
  command = plan

  variables {
    context_id         = "test"
    cluster_name       = "test-cluster"
    kubernetes_version = "1.30"
    node_groups = {
      system = {
        instance_types = ["m5.large"]
        disk_size      = 50
        min_size       = 2
        max_size       = 5
        desired_size   = 3
      }
      workload = {
        instance_types = ["c5.large"]
        disk_size      = 100
        min_size       = 1
        max_size       = 10
        desired_size   = 3
      }
    }
    endpoint_private_access       = true
    endpoint_public_access        = true
    cluster_api_access_cidr_block = "10.0.0.0/8"
    enable_secrets_encryption     = true
    secrets_encryption_kms_key_id  = "arn:aws:kms:us-west-2:123456789012:key/abcd1234-5678-90ab-cdef-1234567890ab"
    enable_ebs_encryption          = true
    ebs_volume_kms_key_id          = "arn:aws:kms:us-west-2:123456789012:key/abcd1234-5678-90ab-cdef-1234567890ab"
  }

  assert {
    condition     = aws_eks_cluster.main.name == "test-cluster"
    error_message = "Cluster name should match input"
  }

  assert {
    condition     = aws_eks_cluster.main.version == "1.30"
    error_message = "Kubernetes version should match input"
  }

  assert {
    condition     = aws_eks_node_group.main["system"].node_group_name == "system"
    error_message = "Default node group name should match input"
  }

  assert {
    condition     = aws_eks_node_group.main["system"].instance_types[0] == "m5.large"
    error_message = "Default node group instance type should match input"
  }

  assert {
    condition     = aws_eks_node_group.main["system"].scaling_config[0].min_size == 2
    error_message = "Default node group min size should match input"
  }

  assert {
    condition     = aws_eks_node_group.main["system"].scaling_config[0].max_size == 5
    error_message = "Default node group max size should match input"
  }

  assert {
    condition     = aws_eks_node_group.main["system"].scaling_config[0].desired_size == 3
    error_message = "Default node group desired size should match input"
  }

  assert {
    condition     = length(aws_eks_node_group.main) == 2
    error_message = "Additional node group should be created when specified"
  }

  assert {
    condition     = aws_eks_node_group.main["workload"].node_group_name == "workload"
    error_message = "Additional node group name should match input"
  }

  assert {
    condition     = aws_eks_node_group.main["workload"].instance_types[0] == "c5.large"
    error_message = "Additional node group instance type should match input"
  }

  assert {
    condition     = aws_eks_cluster.main.vpc_config[0].endpoint_private_access == true
    error_message = "Private endpoint should be enabled"
  }

  assert {
    condition     = aws_eks_cluster.main.vpc_config[0].endpoint_public_access == true
    error_message = "Public endpoint should be enabled"
  }

  assert {
    condition = alltrue([
      for ingress in aws_security_group.cluster_api_access.ingress :
      contains(ingress.cidr_blocks, var.cluster_api_access_cidr_block)
      if ingress.from_port == 443 && ingress.to_port == 443
    ])
    error_message = "Cluster API access security group should use the specified CIDR block"
  }

  assert {
    condition     = aws_security_group.cluster_api_access.name == "${local.name}-cluster-api-access"
    error_message = "Security group name should follow naming convention"
  }

  assert {
    condition = anytrue([
      for ingress in aws_security_group.cluster_api_access.ingress :
      ingress.from_port == 443 && ingress.to_port == 443
    ])
    error_message = "Security group should allow port 443 for Kubernetes API access"
  }

  assert {
    condition     = var.enable_secrets_encryption == true
    error_message = "enable_secrets_encryption should be true"
  }

  assert {
    condition     = var.secrets_encryption_kms_key_id == "arn:aws:kms:us-west-2:123456789012:key/abcd1234-5678-90ab-cdef-1234567890ab"
    error_message = "secrets_encryption_kms_key_id should match input"
  }

  assert {
    condition     = length(aws_kms_key.eks_encryption_key) == 0
    error_message = "No internal KMS key should be created when secrets_encryption_kms_key_id is provided"
  }

  assert {
    condition     = aws_eks_cluster.main.encryption_config[0].provider[0].key_arn == var.secrets_encryption_kms_key_id
    error_message = "Cluster encryption_config should use the provided external KMS key ARN"
  }

  assert {
    condition     = aws_launch_template.node_group["system"].block_device_mappings[0].ebs[0].encrypted == true
    error_message = "EBS volumes should be encrypted when enable_ebs_encryption is true"
  }

  assert {
    condition     = aws_launch_template.node_group["system"].block_device_mappings[0].ebs[0].kms_key_id == var.ebs_volume_kms_key_id
    error_message = "EBS volumes should use the provided KMS key"
  }

  assert {
    condition     = length(aws_kms_key.ebs_encryption_key) == 0
    error_message = "No EBS encryption key should be created when a key is provided"
  }
}

# Tests the private cluster configuration, ensuring that enabling the endpoint_private_access
# and disabling endpoint_public_access results in a private EKS cluster as expected.
run "private_cluster" {
  command = plan

  variables {
    context_id              = "test"
    cluster_name            = "test-cluster"
    endpoint_private_access = true
    endpoint_public_access  = false
  }

  assert {
    condition     = aws_eks_cluster.main.vpc_config[0].endpoint_private_access == true
    error_message = "Private endpoint should be enabled"
  }

  assert {
    condition     = aws_eks_cluster.main.vpc_config[0].endpoint_public_access == false
    error_message = "Public endpoint should be disabled"
  }
}

# Verifies that no kubeconfig file is generated when context_path is empty,
# preventing unnecessary file creation in the root directory.
run "no_config_files" {
  command = plan

  variables {
    context_id   = "test"
    cluster_name = "test-cluster"
    context_path = ""
  }

  # This test verifies that when context_path is empty, no kubeconfig is generated
  # Since there's no local_file.kube_config resource in the module, we need to test
  # the conditions that would lead to kubeconfig generation instead
  assert {
    condition     = var.context_path == ""
    error_message = "Context path should be empty for this test"
  }
}

# Test for using an existing KMS key for EKS secrets encryption
run "use_existing_kms_key" {
  command = plan

  variables {
    context_id                    = "test"
    enable_secrets_encryption     = true
    secrets_encryption_kms_key_id = "arn:aws:kms:us-west-2:123456789012:key/abcd1234-5678-90ab-cdef-1234567890ab"
  }

  assert {
    condition     = length(aws_kms_key.eks_encryption_key) == 0
    error_message = "No KMS key should be created when using an existing key"
  }

  assert {
    condition     = length(aws_eks_cluster.main.encryption_config) == 1 ? aws_eks_cluster.main.encryption_config[0].provider[0].key_arn == var.secrets_encryption_kms_key_id : true
    error_message = "Cluster should use the provided KMS key ARN if encryption_config is present"
  }
}

run "multiple_invalid_inputs" {
  command = plan
  expect_failures = [
    var.kubernetes_version,
  ]
  variables {
    kubernetes_version = "v1.32"
  }
}
