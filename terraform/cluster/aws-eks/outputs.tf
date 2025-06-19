#-----------------------------------------------------------------------------------------------------------------------
# Outputs
#-----------------------------------------------------------------------------------------------------------------------

output "cluster_id" {
  description = "The name/id of the EKS cluster."
  value       = aws_eks_cluster.main.id
}

output "cluster_arn" {
  description = "The Amazon Resource Name (ARN) of the cluster."
  value       = aws_eks_cluster.main.arn
}

output "cluster_endpoint" {
  description = "The endpoint for the Kubernetes API server."
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_security_group_id" {
  description = "The security group ID attached to the EKS cluster."
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

output "kubeconfig_certificate_authority_data" {
  description = "The base64 encoded certificate data required to communicate with the cluster."
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "external_dns_role_arn" {
  description = "ARN of the IAM role for external-dns"
  value       = try(aws_iam_role.external_dns[0].arn, null)
}

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = local.name
}
