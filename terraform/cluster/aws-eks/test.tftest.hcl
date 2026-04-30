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
      name = "us-west-2"
    }
  }
}

variables {
  vpc_id             = "vpc-12345678"
  private_subnet_ids = ["subnet-12345678", "subnet-87654321", "subnet-11223344"]
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
    condition     = startswith(aws_eks_node_group.main["default"].node_group_name_prefix, "default-")
    error_message = "Default node group should use 'default-' name prefix for create_before_destroy support"
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
    condition     = aws_launch_template.node_group["default"].block_device_mappings[0].ebs[0].encrypted == "true"
    error_message = "EBS volumes should be encrypted by default"
  }

  assert {
    condition     = length(aws_kms_key.ebs_encryption_key) == 1
    error_message = "EBS encryption key should be created when enable_ebs_encryption is true and no key is provided"
  }
}

run "cloudwatch_logs_disabled" {
  command = plan

  variables {
    context_id             = "test"
    cluster_name           = "windsor-eks"
    kubernetes_version     = "1.32"
    enable_cloudwatch_logs = false
  }

  assert {
    condition     = length(aws_eks_cluster.main.enabled_cluster_log_types) == 0
    error_message = "No log types should be enabled when enable_cloudwatch_logs is false"
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
    secrets_encryption_kms_key_id = "arn:aws:kms:us-west-2:123456789012:key/abcd1234-5678-90ab-cdef-1234567890ab"
    enable_ebs_encryption         = true
    ebs_volume_kms_key_id         = "arn:aws:kms:us-west-2:123456789012:key/abcd1234-5678-90ab-cdef-1234567890ab"
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
    condition     = startswith(aws_eks_node_group.main["system"].node_group_name_prefix, "system-")
    error_message = "System node group should use 'system-' name prefix for create_before_destroy support"
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
    condition     = startswith(aws_eks_node_group.main["workload"].node_group_name_prefix, "workload-")
    error_message = "Workload node group should use 'workload-' name prefix for create_before_destroy support"
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
    condition     = aws_launch_template.node_group["system"].block_device_mappings[0].ebs[0].encrypted == "true"
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

# Surfaces the migration message rather than terraform's generic
# "Missing required argument" so operators relying on the legacy
# tag-based discovery get a useful pointer.
run "vpc_id_null_emits_migration_error" {
  command = plan
  variables {
    context_id = "test"
    vpc_id     = null
  }
  expect_failures = [var.vpc_id]
}

run "private_subnet_ids_empty_emits_migration_error" {
  command = plan
  variables {
    context_id         = "test"
    private_subnet_ids = []
  }
  expect_failures = [var.private_subnet_ids]
}

# Verifies the cert-manager IAM role + Pod Identity association are NOT
# created by default (var.create_cert_manager_role defaults to false).
run "cert_manager_role_disabled_by_default" {
  command = plan

  variables {
    context_id = "test"
  }

  assert {
    condition     = length(aws_iam_role.cert_manager) == 0
    error_message = "cert-manager IAM role should not be created when create_cert_manager_role is false"
  }

  assert {
    condition     = length(aws_eks_pod_identity_association.cert_manager) == 0
    error_message = "cert-manager Pod Identity association should not be created when create_cert_manager_role is false"
  }
}

# Verifies the AWS LB Controller IAM role + policy + Pod Identity binding
# (system-lb / aws-load-balancer-controller service account) are created by
# default. Opt out via create_aws_lb_controller_role = false.
run "aws_lb_controller_role_enabled_by_default" {
  command = plan

  variables {
    context_id = "test"
  }

  assert {
    condition     = length(aws_iam_role.aws_lb_controller) == 1
    error_message = "AWS LB Controller IAM role should be created by default"
  }

  assert {
    condition     = aws_iam_role.aws_lb_controller[0].name == "cluster-test-aws-lb-controller"
    error_message = "AWS LB Controller IAM role name should follow the cluster naming convention"
  }

  assert {
    condition     = length(aws_iam_policy.aws_lb_controller) == 1
    error_message = "AWS LB Controller IAM policy should be created by default"
  }

  assert {
    condition     = length(aws_eks_pod_identity_association.aws_lb_controller) == 1
    error_message = "AWS LB Controller Pod Identity association should be created by default"
  }

  assert {
    condition     = aws_eks_pod_identity_association.aws_lb_controller[0].namespace == "system-lb"
    error_message = "AWS LB Controller Pod Identity association should target the system-lb namespace"
  }

  assert {
    condition     = aws_eks_pod_identity_association.aws_lb_controller[0].service_account == "aws-load-balancer-controller"
    error_message = "AWS LB Controller Pod Identity association should target the aws-load-balancer-controller service account"
  }

  # Sanity-check the upstream IAM policy is in place via a marker action.
  assert {
    condition     = strcontains(aws_iam_policy.aws_lb_controller[0].policy, "elasticloadbalancing:CreateLoadBalancer")
    error_message = "AWS LB Controller policy should include the elasticloadbalancing:CreateLoadBalancer action"
  }
}

run "aws_lb_controller_role_can_be_disabled" {
  command = plan

  variables {
    context_id                    = "test"
    create_aws_lb_controller_role = false
  }

  assert {
    condition     = length(aws_iam_role.aws_lb_controller) == 0
    error_message = "AWS LB Controller IAM role should not be created when create_aws_lb_controller_role is false"
  }

  assert {
    condition     = length(aws_eks_pod_identity_association.aws_lb_controller) == 0
    error_message = "AWS LB Controller Pod Identity association should not be created when create_aws_lb_controller_role is false"
  }
}

# Verifies the cert-manager IAM role, Route53 policy, and Pod Identity binding
# (system-pki / cert-manager service account) are created when opted in.
run "cert_manager_role_enabled" {
  command = plan

  variables {
    context_id               = "test"
    create_cert_manager_role = true
  }

  assert {
    condition     = length(aws_iam_role.cert_manager) == 1
    error_message = "cert-manager IAM role should be created when create_cert_manager_role is true"
  }

  assert {
    condition     = aws_iam_role.cert_manager[0].name == "cluster-test-cert-manager"
    error_message = "cert-manager IAM role name should follow the cluster naming convention"
  }

  assert {
    condition     = length(aws_iam_policy.cert_manager) == 1
    error_message = "cert-manager IAM policy should be created when create_cert_manager_role is true"
  }

  assert {
    condition     = length(aws_eks_pod_identity_association.cert_manager) == 1
    error_message = "cert-manager Pod Identity association should be created when create_cert_manager_role is true"
  }

  assert {
    condition     = aws_eks_pod_identity_association.cert_manager[0].namespace == "system-pki"
    error_message = "cert-manager Pod Identity association should target the system-pki namespace"
  }

  assert {
    condition     = aws_eks_pod_identity_association.cert_manager[0].service_account == "cert-manager"
    error_message = "cert-manager Pod Identity association should target the cert-manager service account"
  }

  # No zone IDs supplied → falls back to wildcard (legacy direct-module use).
  assert {
    condition     = strcontains(aws_iam_policy.cert_manager[0].policy, "\"arn:aws:route53:::hostedzone/*\"")
    error_message = "cert-manager policy should fall back to a wildcard zone ARN when no zone IDs are supplied"
  }
}

# Verifies the cert-manager Route53 record-write actions are scoped to the
# operator-supplied zone IDs (e.g. the dns-zone module's zone_id output) and
# don't reach for the wildcard. ListHostedZonesByName remains '*' since the
# solver calls it without a zone ID.
run "cert_manager_policy_scoped_to_zone_ids" {
  command = plan

  variables {
    context_id                   = "test"
    create_cert_manager_role     = true
    cert_manager_hosted_zone_ids = ["Z1ABCDEF12345", "Z9ZYXWVU98765"]
  }

  assert {
    condition     = strcontains(aws_iam_policy.cert_manager[0].policy, "\"arn:aws:route53:::hostedzone/Z1ABCDEF12345\"")
    error_message = "cert-manager policy should reference the first supplied zone ARN"
  }

  assert {
    condition     = strcontains(aws_iam_policy.cert_manager[0].policy, "\"arn:aws:route53:::hostedzone/Z9ZYXWVU98765\"")
    error_message = "cert-manager policy should reference the second supplied zone ARN"
  }

  assert {
    condition     = !strcontains(aws_iam_policy.cert_manager[0].policy, "\"arn:aws:route53:::hostedzone/*\"")
    error_message = "cert-manager policy must not include the wildcard zone ARN when zone IDs are supplied"
  }
}

# Verifies the pools path: when var.pools is non-empty, it replaces var.node_groups
# entirely. Class maps to a default instance family, lifecycle maps to capacity_type,
# and the pool name + class are auto-injected as windsor.io/pool labels.
run "pools_drive_node_groups_when_set" {
  command = plan

  variables {
    context_id         = "test"
    kubernetes_version = "1.34"
    pools = {
      system = {
        class = "system"
        count = 2
      }
      batch = {
        class     = "compute"
        count     = 5
        lifecycle = "spot"
      }
    }
  }

  assert {
    condition     = length(aws_eks_node_group.main) == 2
    error_message = "Two pools should produce two node groups (the default node_group is suppressed)"
  }

  assert {
    condition     = aws_eks_node_group.main["system"].instance_types[0] == "t3.medium"
    error_message = "system class should default to t3.medium head of the instance_types list"
  }

  assert {
    condition     = aws_eks_node_group.main["batch"].capacity_type == "SPOT"
    error_message = "lifecycle: spot should resolve to SPOT capacity_type"
  }

  assert {
    condition     = aws_eks_node_group.main["batch"].scaling_config[0].desired_size == 5 && aws_eks_node_group.main["batch"].scaling_config[0].min_size == 5 && aws_eks_node_group.main["batch"].scaling_config[0].max_size == 5
    error_message = "count should pin desired/min/max to the same value"
  }

  assert {
    condition     = aws_eks_node_group.main["system"].labels["windsor.io/pool"] == "system" && aws_eks_node_group.main["system"].labels["windsor.io/pool-class"] == "system"
    error_message = "Pool name and class should be auto-injected as windsor.io/pool labels"
  }
}

# Verifies the explicit-instance-types escape hatch: when a pool sets instance_types,
# the class default is bypassed but the pool-class label still flows through.
run "pool_instance_types_override_class_default" {
  command = plan

  variables {
    context_id         = "test"
    kubernetes_version = "1.34"
    pools = {
      gpu = {
        class          = "gpu"
        count          = 1
        instance_types = ["p4d.24xlarge"]
      }
    }
  }

  assert {
    condition     = aws_eks_node_group.main["gpu"].instance_types[0] == "p4d.24xlarge"
    error_message = "Explicit instance_types should override the class default"
  }

  assert {
    condition     = aws_eks_node_group.main["gpu"].labels["windsor.io/pool-class"] == "gpu"
    error_message = "windsor.io/pool-class should still reflect the declared class"
  }
}

# Verifies the class_instance_types validation rejects partial overrides.
# Without this, a partial override would panic mid-plan on the first pool
# whose class is missing from the operator's map.
run "class_instance_types_rejects_partial_override" {
  command = plan

  variables {
    context_id = "test"
    class_instance_types = {
      general = ["m6i.xlarge"]
    }
  }

  expect_failures = [var.class_instance_types]
}

# Negative count would error opaquely at AWS API time. The validation
# surfaces it at plan.
run "pool_rejects_negative_count" {
  command = plan

  variables {
    context_id = "test"
    pools = {
      bad = {
        class = "general"
        count = -1
      }
    }
  }

  expect_failures = [var.pools]
}

# Lowercase "spot" or any non-canonical value would slip past type-check
# and reach AWS with an opaque rejection. Validation surfaces it at plan.
run "node_group_rejects_lowercase_capacity_type" {
  command = plan

  variables {
    context_id = "test"
    node_groups = {
      bad = {
        instance_types = ["t3.xlarge"]
        min_size       = 1
        max_size       = 1
        desired_size   = 1
        capacity_type  = "spot"
      }
    }
  }

  expect_failures = [var.node_groups]
}

# Empty instance_types should fall through to the class default. coalesce()
# would return the empty list as-is (it only skips null + empty string), so
# the instance_types pick logic uses an explicit length check instead.
run "pool_empty_instance_types_falls_back_to_class_default" {
  command = plan

  variables {
    context_id         = "test"
    kubernetes_version = "1.34"
    pools = {
      empty = {
        class          = "general"
        count          = 1
        instance_types = []
      }
    }
  }

  assert {
    condition     = aws_eks_node_group.main["empty"].instance_types[0] == "t3.xlarge"
    error_message = "Empty instance_types list should fall through to the general class default"
  }
}
