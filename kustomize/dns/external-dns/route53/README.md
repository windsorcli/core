# External DNS Route53 Configuration

This component configures external-dns to use AWS Route53 for DNS management in EKS clusters.

## Dependencies

This component requires the `aws-eks/additions` Terraform module to be applied first, as it creates a ConfigMap with required configuration values:

```hcl
resource "kubernetes_config_map" "external_dns" {
  metadata {
    name      = "external-dns"
    namespace = "system-dns"
  }

  data = {
    aws_role_arn = "arn:aws:iam::${account_id}:role/${cluster_name}-external-dns"
    aws_region   = "us-west-2"  # or cluster's region
    txt_owner_id = "${cluster_name}-${context_id}"
  }
}
```

## Configuration Values

The HelmRelease uses the following values from the ConfigMap:

| ConfigMap Key | Helm Value Path | Description |
|---------------|----------------|-------------|
| aws_role_arn | aws.role_arn | IAM role ARN for external-dns |
| aws_region | aws.region | AWS region for Route53 operations |
| txt_owner_id | txtOwnerId | Unique identifier for TXT records |

## Usage

1. Apply the `aws-eks/additions` Terraform module to create the ConfigMap
2. Apply this kustomization to deploy external-dns with Route53 configuration

## Notes

- The ConfigMap must exist in the `system-dns` namespace
- The IAM role referenced by `aws_role_arn` must have appropriate Route53 permissions
- The `txt_owner_id` is constructed as `${cluster_name}-${context_id}` to ensure uniqueness across clusters
