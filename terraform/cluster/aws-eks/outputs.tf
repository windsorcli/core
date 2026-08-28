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

output "aws_lb_controller_role_arn" {
  description = "ARN of the IAM role for the AWS Load Balancer Controller"
  value       = try(aws_iam_role.aws_lb_controller[0].arn, null)
}

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = local.name
}

output "karpenter_controller_role_arn" {
  description = "ARN of the Karpenter controller IAM role (assumed via Pod Identity)"
  value       = try(aws_iam_role.karpenter_controller[0].arn, null)
}

output "karpenter_node_role_name" {
  description = "Name of the IAM role for Karpenter-provisioned nodes"
  value       = try(aws_iam_role.karpenter_node[0].name, null)
}

output "karpenter_node_instance_profile_name" {
  description = "Name of the instance profile the EC2NodeClass attaches to Karpenter nodes"
  value       = try(aws_iam_instance_profile.karpenter_node[0].name, null)
}

output "karpenter_interruption_queue_name" {
  description = "Name of the Karpenter spot-interruption SQS queue"
  value       = try(aws_sqs_queue.karpenter[0].name, null)
}
