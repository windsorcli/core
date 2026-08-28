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
  cluster_name = "cluster-test"
  cluster_arn  = "arn:aws:eks:us-west-2:123456789012:cluster/cluster-test"
  cluster_tag  = "cluster-test"
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
    condition     = strcontains(aws_iam_policy.this["rds"].policy, "arn:aws:rds:*:123456789012:subgrp:cluster-test-crossplane-rds")
    error_message = "Policy should authorize CreateDBInstance against the DB subnet group ARN it references, not just the resulting instance ARN"
  }

  assert {
    condition     = strcontains(aws_iam_policy.this["rds"].policy, "\"aws:RequestTag/windsorcli.dev/cluster\":\"cluster-test\"")
    error_message = "Policy should condition create actions on the windsorcli.dev/cluster request tag"
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
