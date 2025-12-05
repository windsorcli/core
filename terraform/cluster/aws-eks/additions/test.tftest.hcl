mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
  mock_data "aws_region" {
    defaults = {
      name   = "us-west-2"
      region = "us-west-2"
    }
  }
  mock_data "aws_eks_cluster" {
    defaults = {
      name = "test-cluster"
      arn  = "arn:aws:eks:us-west-2:123456789012:cluster/test-cluster"
    }
  }
}

mock_provider "kubernetes" {}

# Verifies that the module creates resources with minimal configuration,
# ensuring that all default values are correctly applied and only required variables are set.
run "minimal_configuration" {
  command = plan

  variables {
    context_id = "test"
  }

  assert {
    condition     = kubernetes_namespace.system_dns.metadata[0].name == "system-dns"
    error_message = "Namespace should be created with default name 'system-dns'"
  }

  assert {
    condition     = kubernetes_config_map.external_dns.metadata[0].name == "external-dns"
    error_message = "ConfigMap should be created with name 'external-dns'"
  }

  assert {
    condition     = kubernetes_config_map.external_dns.data.aws_region == "us-west-2"
    error_message = "ConfigMap should have correct AWS region"
  }

  assert {
    condition     = kubernetes_config_map.external_dns.data.txt_owner_id == "cluster-test"
    error_message = "ConfigMap should have correct txt owner ID"
  }
}

# Verifies that the module handles all optional variables correctly
run "full_configuration" {
  command = plan

  variables {
    context_id     = "test"
    cluster_name   = "custom-cluster"
    route53_region = "us-east-1"
  }

  assert {
    condition     = kubernetes_config_map.external_dns.metadata[0].name == "external-dns"
    error_message = "ConfigMap should be created with name 'external-dns'"
  }

  assert {
    condition     = kubernetes_config_map.external_dns.data.aws_region == "us-east-1"
    error_message = "ConfigMap should use provided AWS region"
  }

  assert {
    condition     = kubernetes_config_map.external_dns.data.txt_owner_id == "custom-cluster"
    error_message = "ConfigMap should have correct txt owner ID"
  }
}
