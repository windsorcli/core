mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
      arn        = "arn:aws:iam::123456789012:user/test-user"
      user_id    = "AIDAJQABLZS4A3QDU576Q"
    }
  }
  mock_data "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:us-west-2:123456789012:key/aws-managed-default-key"
    }
  }
}

variables {
  context_id                = "test"
  cluster_name              = "cluster-test"
  cluster_arn               = "arn:aws:eks:us-west-2:123456789012:cluster/cluster-test"
  vpc_id                    = "vpc-12345678"
  cluster_security_group_id = "sg-0eks1234"
}

# Verifies the default path: a dedicated CMK is created with a stable alias.
run "manages_dedicated_key_by_default" {
  command = plan

  assert {
    condition     = length(aws_kms_key.rds) == 1
    error_message = "A dedicated CMK should be created by default"
  }

  assert {
    condition     = aws_kms_alias.rds[0].name == "alias/test-rds"
    error_message = "The dedicated CMK's alias should follow the <context_id>-rds convention"
  }

  assert {
    condition     = length(data.aws_kms_key.rds_default) == 0
    error_message = "The AWS-managed default key should not be looked up when managing a dedicated CMK"
  }

  assert {
    condition     = aws_security_group.rds.vpc_id == "vpc-12345678"
    error_message = "The RDS security group should be created in the supplied VPC"
  }

  assert {
    condition     = contains(aws_security_group.rds.ingress[*].to_port, 5432)
    error_message = "The RDS security group should allow inbound on the Postgres port"
  }

  assert {
    condition     = contains(flatten(aws_security_group.rds.ingress[*].security_groups), "sg-0eks1234")
    error_message = "The RDS security group should scope ingress to the cluster's own security group, not an open CIDR"
  }

  assert {
    condition     = strcontains(aws_iam_policy.secret_reader.policy, "\"secretsmanager:GetSecretValue\"") && strcontains(aws_iam_policy.secret_reader.policy, "secret:rds!*")
    error_message = "The secret-reader policy should allow reading RDS-managed master password secrets"
  }

  assert {
    condition     = aws_eks_pod_identity_association.secret_reader.namespace == "system-provisioning" && aws_eks_pod_identity_association.secret_reader.service_account == "rds-secret-reader"
    error_message = "The secret-reader Pod Identity association should target a fixed system-provisioning/rds-secret-reader identity"
  }
}

# Verifies manage_encryption_key = false skips the dedicated CMK and falls
# back to the account's AWS-managed default key.
run "falls_back_to_default_key_when_unmanaged" {
  command = plan

  variables {
    manage_encryption_key = false
  }

  assert {
    condition     = length(aws_kms_key.rds) == 0
    error_message = "No dedicated CMK should be created when manage_encryption_key is false"
  }

  assert {
    condition     = length(data.aws_kms_key.rds_default) == 1
    error_message = "The AWS-managed default key should be looked up when manage_encryption_key is false"
  }

  assert {
    condition     = output.kms_key_alias == null
    error_message = "No alias exists for the AWS-managed default key"
  }
}

# Verifies an explicit kms_key_arn skips creating a dedicated CMK entirely,
# even when manage_encryption_key is left at its default.
run "byok_kms_key_arn_skips_dedicated_key" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/abcd1234-5678-90ab-cdef-1234567890ab"
  }

  assert {
    condition     = length(aws_kms_key.rds) == 0
    error_message = "No dedicated CMK should be created when kms_key_arn supplies an existing key"
  }

  assert {
    condition     = length(data.aws_kms_key.rds_default) == 0
    error_message = "The default key lookup should be skipped when kms_key_arn supplies an existing key"
  }

  assert {
    condition     = output.kms_key_arn == "arn:aws:kms:us-west-2:123456789012:key/abcd1234-5678-90ab-cdef-1234567890ab"
    error_message = "kms_key_arn output should pass the supplied ARN through unchanged"
  }
}

# Verifies a malformed kms_key_arn is rejected.
run "malformed_kms_key_arn_rejected" {
  command = plan

  variables {
    kms_key_arn = "not-an-arn"
  }

  expect_failures = [var.kms_key_arn]
}

# Verifies vpc_id is required.
run "vpc_id_required" {
  command = plan

  variables {
    vpc_id = null
  }

  expect_failures = [var.vpc_id]
}

# Verifies cluster_security_group_id is required.
run "cluster_security_group_id_required" {
  command = plan

  variables {
    cluster_security_group_id = null
  }

  expect_failures = [var.cluster_security_group_id]
}
