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
  mock_data "aws_subnet" {
    defaults = {
      id = "subnet-12345678"
    }
  }
  mock_data "aws_subnet_ids" {
    defaults = {
      ids = ["subnet-12345678", "subnet-87654321", "subnet-11223344"]
    }
  }
}

# Verifies that the module creates an EKS cluster with minimal configuration,
# ensuring that all default values are correctly applied and only required variables are set.
run "minimal_configuration" {
  command = plan

  variables {
    context_id = "test"
  }

  assert {
    condition     = aws_eks_cluster.main.name == "windsor-eks-cluster-test"
    error_message = "Cluster name should default to 'windsor-eks-cluster-test' when cluster_name is omitted"
  }

  assert {
    condition     = aws_iam_role.cluster.name == "windsor-eks-cluster-role-test"
    error_message = "Cluster IAM role name should follow default naming convention"
  }

  assert {
    condition     = aws_eks_node_group.system.node_group_name == "system"
    error_message = "Default node group should use 'system' name"
  }

  assert {
    condition     = aws_eks_node_group.system.instance_types[0] == "t3.medium"
    error_message = "Default node group should use t3.medium instance type"
  }

  assert {
    condition     = aws_eks_node_group.system.scaling_config[0].desired_size == 2
    error_message = "Default node group should have 2 nodes"
  }

  assert {
    condition     = aws_eks_cluster.main.encryption_config[0].resources[0] == "secrets"
    error_message = "Secrets encryption should be enabled by default"
  }

  assert {
    condition     = aws_eks_cluster.main.vpc_config[0].endpoint_private_access == false
    error_message = "Private endpoint should be disabled by default"
  }

  assert {
    condition     = aws_eks_cluster.main.vpc_config[0].endpoint_public_access == true
    error_message = "Public endpoint should be enabled by default"
  }
}

# Tests a full configuration with all optional variables explicitly set,
# verifying that the module correctly applies all user-supplied values for node groups and feature flags.
run "full_configuration" {
  command = plan

  variables {
    context_id    = "test"
    cluster_name  = "test-cluster"
    k8s_version   = "1.30"
    default_node_group = {
      name          = "system"
      instance_type = "m5.large"
      disk_size     = 50
      min_size      = 2
      max_size      = 5
      desired_size  = 3
    }
    additional_node_groups = [{
      name          = "workload"
      instance_type = "c5.large"
      disk_size     = 100
      min_size      = 1
      max_size      = 10
      desired_size  = 3
    }]
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = ["10.0.0.0/8"]
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
    condition     = aws_eks_node_group.system.node_group_name == "system"
    error_message = "Default node group name should match input"
  }

  assert {
    condition     = aws_eks_node_group.system.instance_types[0] == "m5.large"
    error_message = "Default node group instance type should match input"
  }

  assert {
    condition     = aws_eks_node_group.system.disk_size == 50
    error_message = "Default node group disk size should match input"
  }

  assert {
    condition     = aws_eks_node_group.system.scaling_config[0].min_size == 2
    error_message = "Default node group min size should match input"
  }

  assert {
    condition     = aws_eks_node_group.system.scaling_config[0].max_size == 5
    error_message = "Default node group max size should match input"
  }

  assert {
    condition     = aws_eks_node_group.system.scaling_config[0].desired_size == 3
    error_message = "Default node group desired size should match input"
  }

  assert {
    condition     = length(aws_eks_node_group.additional) == 1
    error_message = "Additional node group should be created when specified"
  }

  assert {
    condition     = aws_eks_node_group.additional[0].node_group_name == "workload"
    error_message = "Additional node group name should match input"
  }

  assert {
    condition     = aws_eks_node_group.additional[0].instance_types[0] == "c5.large"
    error_message = "Additional node group instance type should match input"
  }

  assert {
    condition     = aws_eks_node_group.additional[0].disk_size == 100
    error_message = "Additional node group disk size should match input"
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
    condition     = aws_eks_cluster.main.vpc_config[0].public_access_cidrs[0] == "10.0.0.0/8"
    error_message = "Public access CIDRs should match input"
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

  assert {
    condition     = length(local_file.kube_config) == 0
    error_message = "No kubeconfig file should be generated without context path"
  }
}
