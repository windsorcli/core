mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
      arn        = "arn:aws:iam::123456789012:user/test-user"
      user_id    = "AIDAJQABLZS4A3QDU576Q"
    }
  }
}

variables {
  cluster_name         = "cluster-test"
  cluster_arn          = "arn:aws:eks:us-west-2:123456789012:cluster/cluster-test"
  cluster_tag          = "cluster-test"
  db_subnet_group_name = "test-rds"
  kms_key_arn          = "arn:aws:kms:us-west-2:123456789012:key/abcd1234-5678-90ab-cdef-1234567890ab"
}

# Verifies no roles are created with an empty resource set.
run "no_resources_selected" {
  command = plan

  assert {
    condition     = length(aws_iam_role.this) == 0
    error_message = "No IAM roles should be created when resources is empty"
  }
}

# Verifies the rds resource type creates a correctly scoped role, policy,
# and Pod Identity association.
run "rds_selected" {
  command = plan

  variables {
    resources = ["rds"]
  }

  assert {
    condition     = aws_iam_role.this["rds"].name == "cluster-test-crossplane-rds"
    error_message = "Role name should follow the cluster-crossplane-<resource> convention"
  }

  assert {
    condition     = strcontains(aws_iam_role.this["rds"].assume_role_policy, "arn:aws:eks:us-west-2:123456789012:cluster/cluster-test")
    error_message = "Trust policy should scope aws:SourceArn to the supplied cluster ARN"
  }

  assert {
    condition     = strcontains(aws_iam_policy.this["rds"].policy, "rds:CreateDBInstance")
    error_message = "Policy should include the rds:CreateDBInstance action"
  }

  assert {
    condition     = strcontains(aws_iam_policy.this["rds"].policy, "arn:aws:rds:*:123456789012:subgrp:test-rds")
    error_message = "Policy should authorize CreateDBInstance against the supplied DB subnet group ARN, not just the resulting instance ARN"
  }

  assert {
    condition     = strcontains(aws_iam_policy.this["rds"].policy, "\"aws:RequestTag/windsorcli.dev/cluster\":\"cluster-test\"")
    error_message = "Policy should condition create actions on the windsorcli.dev/cluster request tag"
  }

  assert {
    condition     = strcontains(aws_iam_policy.this["rds"].policy, "arn:aws:iam::123456789012:role/aws-service-role/rds.amazonaws.com/AWSServiceRoleForRDS")
    error_message = "Policy should allow creating the RDS service-linked role, required once per account before any DB instance can be created"
  }

  assert {
    condition     = strcontains(aws_iam_policy.this["rds"].policy, "\"kms:DescribeKey\"") && strcontains(aws_iam_policy.this["rds"].policy, "arn:aws:kms:us-west-2:123456789012:key/abcd1234-5678-90ab-cdef-1234567890ab")
    error_message = "Policy should allow describing the supplied KMS key"
  }

  assert {
    condition     = strcontains(aws_iam_policy.this["rds"].policy, "\"kms:CreateGrant\"") && strcontains(aws_iam_policy.this["rds"].policy, "\"kms:GrantIsForAWSResource\":\"true\"")
    error_message = "Policy should allow creating a grant on the supplied KMS key, scoped to grants made on RDS's own behalf"
  }

  assert {
    condition     = strcontains(aws_iam_policy.this["rds"].policy, "\"aws:ResourceTag/windsorcli.dev/cluster\":\"cluster-test\"")
    error_message = "Policy should condition modify/delete actions on the windsorcli.dev/cluster resource tag"
  }

  assert {
    condition     = aws_eks_pod_identity_association.this["rds"].namespace == "system-provisioning"
    error_message = "Pod Identity association should target the system-provisioning namespace"
  }

  assert {
    condition     = aws_eks_pod_identity_association.this["rds"].service_account == "provider-aws-rds"
    error_message = "Pod Identity association should target the provider-aws-rds service account"
  }
}

# Verifies an unsupported resource type is rejected.
run "unsupported_resource_rejected" {
  command = plan

  variables {
    resources = ["s3"]
  }

  expect_failures = [var.resources]
}

# Verifies a malformed KMS key ARN is rejected.
run "malformed_kms_key_arn_rejected" {
  command = plan

  variables {
    resources   = ["rds"]
    kms_key_arn = "not-an-arn"
  }

  expect_failures = [var.kms_key_arn]
}
