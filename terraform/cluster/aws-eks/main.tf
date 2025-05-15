// Define the required Terraform version and providers
terraform {
  required_version = ">=1.8"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.97.0"
    }
  }
}

locals {
  name = var.cluster_name != "" ? var.cluster_name : "cluster-${var.context_id}"
}

#-----------------------------------------------------------------------------------------------------------------------
# Data
#-----------------------------------------------------------------------------------------------------------------------

data "aws_vpc" "default" {
  count = var.vpc_id == null ? 1 : 0
  filter {
    name   = "tag:WindsorContextID"
    values = [var.context_id]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "tag:Tier"
    values = ["private"]
  }
  filter {
    name   = "vpc-id"
    values = [var.vpc_id != null ? var.vpc_id : data.aws_vpc.default[0].id]
  }
}

data "aws_region" "current" {}

#-----------------------------------------------------------------------------------------------------------------------
# EKS Cluster
#-----------------------------------------------------------------------------------------------------------------------
resource "aws_eks_cluster" "main" {
  # checkov:skip=CKV_AWS_38: Public access set via a variable.
  # checkov:skip=CKV_AWS_39: Public access set via a variable.
  name     = local.name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = data.aws_subnets.private.ids
    endpoint_private_access = true
    endpoint_public_access  = var.endpoint_public_access
    security_group_ids      = [aws_security_group.cluster_api_access.id]
  }

  # Enable secrets encryption using AWS KMS
  encryption_config {
    provider {
      key_arn = aws_kms_key.eks_encryption_key.arn
    }
    resources = ["secrets"]
  }

  # Enable control plane logging for all log types
  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  depends_on = [
    aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.cluster_AmazonEKSVPCResourceController,
    aws_kms_key.eks_encryption_key,
  ]
}

resource "aws_security_group" "cluster_api_access" {
  name        = "${local.name}-cluster-api-access"
  description = "Security group for EKS cluster API access"
  vpc_id      = data.aws_vpc.default[0].id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.cluster_api_access_cidr_block]
    description = "Allow K8s API access from the specified CIDR block"
  }
}

resource "aws_kms_key" "eks_encryption_key" {
  description             = "KMS key for EKS cluster ${local.name} secrets encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "Enable IAM User Permissions",
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        },
        Action   = "kms:*",
        Resource = "*"
      },
      {
        Sid    = "Allow EKS to use the key for secrets encryption",
        Effect = "Allow",
        Principal = {
          Service = "eks.amazonaws.com"
        },
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ],
        Resource = "*"
      }
    ]
  })
}

data "aws_caller_identity" "current" {}

#-----------------------------------------------------------------------------------------------------------------------
# IAM Roles
#-----------------------------------------------------------------------------------------------------------------------

resource "aws_iam_role" "cluster" {
  name = local.name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSVPCResourceController" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.cluster.name
}

resource "aws_iam_role" "node_group" {
  name = "${local.name}-node-group"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "node_group_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node_group.name
}

resource "aws_iam_role_policy_attachment" "node_group_AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node_group.name
}

resource "aws_iam_role_policy_attachment" "node_group_AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node_group.name
}

#-----------------------------------------------------------------------------------------------------------------------
# Node Groups
#-----------------------------------------------------------------------------------------------------------------------
resource "aws_eks_node_group" "main" {
  for_each = var.node_groups

  cluster_name    = aws_eks_cluster.main.name
  node_group_name = each.key
  node_role_arn   = aws_iam_role.node_group.arn
  subnet_ids      = data.aws_subnets.private.ids
  instance_types  = each.value.instance_types

  scaling_config {
    desired_size = each.value.desired_size
    max_size     = each.value.max_size
    min_size     = each.value.min_size
  }

  dynamic "taint" {
    for_each = each.value.taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  labels = each.value.labels

  # Set max pods per node to 64
  launch_template {
    name    = aws_launch_template.node_group[each.key].name
    version = aws_launch_template.node_group[each.key].latest_version
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_group_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.node_group_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.node_group_AmazonEC2ContainerRegistryReadOnly,
  ]
}

resource "aws_launch_template" "node_group" {
  for_each = var.node_groups

  name = "${local.name}-${each.key}"

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = each.value.disk_size
      volume_type           = "gp3"
      delete_on_termination = true
    }
  }

  network_interfaces {
    associate_public_ip_address = false
    delete_on_termination       = true
    security_groups             = [aws_eks_cluster.main.vpc_config[0].cluster_security_group_id]
  }

  # Disable IMDSv1 and require IMDSv2
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  user_data = base64encode(<<-EOT
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="==BOUNDARY=="

--==BOUNDARY==
Content-Type: text/x-shellscript; charset="us-ascii"

#!/bin/bash
set -o xtrace
/etc/eks/bootstrap.sh ${aws_eks_cluster.main.name} --use-max-pods false --kubelet-extra-args '--max-pods=110'

--==BOUNDARY==--
EOT
  )
}

#-----------------------------------------------------------------------------------------------------------------------
# Fargate Profile
#-----------------------------------------------------------------------------------------------------------------------

resource "aws_iam_role" "fargate" {
  name = "${local.name}-fargate-profile"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks-fargate-pods.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "fargate_pod_execution_role_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
  role       = aws_iam_role.fargate.name
}

resource "aws_eks_fargate_profile" "main" {
  for_each = var.fargate_profiles != null ? var.fargate_profiles : {}

  cluster_name           = aws_eks_cluster.main.name
  fargate_profile_name   = each.key
  pod_execution_role_arn = aws_iam_role.fargate.arn
  subnet_ids             = data.aws_subnets.private.ids

  dynamic "selector" {
    for_each = each.value.selectors
    content {
      namespace = selector.value.namespace
      labels    = lookup(selector.value, "labels", null)
    }
  }

  tags = lookup(each.value, "tags", {})
}

#-----------------------------------------------------------------------------------------------------------------------
# Add-On Versions
#-----------------------------------------------------------------------------------------------------------------------

data "aws_eks_addon_version" "default" {
  for_each = var.addons

  addon_name         = each.key
  kubernetes_version = aws_eks_cluster.main.version
  most_recent        = true
}

#-----------------------------------------------------------------------------------------------------------------------
# VPC CNI IAM Role
#-----------------------------------------------------------------------------------------------------------------------

resource "aws_iam_role" "vpc_cni" {
  count = contains(keys(var.addons), "vpc-cni") ? 1 : 0
  name  = "${local.name}-vpc-cni"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = ["sts:AssumeRole", "sts:TagSession"]
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${local.name}-vpc-cni"
  }
}

resource "aws_iam_role_policy_attachment" "vpc_cni" {
  count      = contains(keys(var.addons), "vpc-cni") ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.vpc_cni[0].name
}


#-----------------------------------------------------------------------------------------------------------------------
# EBS CSI Driver IAM Role
#-----------------------------------------------------------------------------------------------------------------------

resource "aws_iam_role" "ebs_csi" {
  count = contains(keys(var.addons), "aws-ebs-csi-driver") ? 1 : 0
  name  = "${local.name}-aws-ebs-csi-driver"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = ["sts:AssumeRole", "sts:TagSession"]
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${local.name}-aws-ebs-csi-driver"
  }
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  count      = contains(keys(var.addons), "aws-ebs-csi-driver") ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_csi[0].name
}

#-----------------------------------------------------------------------------------------------------------------------
# EFS CSI Driver IAM Role
#-----------------------------------------------------------------------------------------------------------------------

resource "aws_iam_role" "efs_csi" {
  count = contains(keys(var.addons), "aws-efs-csi-driver") ? 1 : 0
  name  = "${local.name}-aws-efs-csi-driver"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = ["sts:AssumeRole", "sts:TagSession"]
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${local.name}-aws-efs-csi-driver"
  }
}

resource "aws_iam_role_policy_attachment" "efs_csi" {
  count      = contains(keys(var.addons), "aws-efs-csi-driver") ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
  role       = aws_iam_role.efs_csi[0].name
}

#-----------------------------------------------------------------------------------------------------------------------
# Pod Identity Agent IAM Role
#-----------------------------------------------------------------------------------------------------------------------

resource "aws_iam_role" "pod_identity_agent" {
  count = contains(keys(var.addons), "pod-identity-agent") ? 1 : 0
  name  = "${local.name}-pod-identity-agent"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${local.name}-pod-identity-agent"
  }
}

resource "aws_iam_policy" "pod_identity_agent" {
  count       = contains(keys(var.addons), "pod-identity-agent") ? 1 : 0
  name        = "${local.name}-pod-identity-agent"
  description = "IAM policy for EKS Pod Identity Agent"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:CreateServiceLinkedRole"
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/eks-auth.amazonaws.com"
        Condition = {
          StringEquals = {
            "iam:AWSServiceName" = "eks-auth.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${local.name}-pod-identity-agent"
  }
}

resource "aws_iam_role_policy_attachment" "pod_identity_agent" {
  count      = contains(keys(var.addons), "pod-identity-agent") ? 1 : 0
  policy_arn = aws_iam_policy.pod_identity_agent[0].arn
  role       = aws_iam_role.pod_identity_agent[0].name
}


#-----------------------------------------------------------------------------------------------------------------------
# External DNS IAM Role
#-----------------------------------------------------------------------------------------------------------------------

resource "aws_iam_role" "external_dns" {
  count = contains(keys(var.addons), "external-dns") ? 1 : 0
  name  = "${local.name}-external-dns"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = ["sts:AssumeRole", "sts:TagSession"]
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${local.name}-external-dns"
  }
}

resource "aws_iam_policy" "external_dns" {
  # This policy is based on the official External DNS documentation for AWS
  # https://kubernetes-sigs.github.io/external-dns/v0.17.0/docs/tutorials/aws/#iam-policy
  # checkov:skip=CKV_AWS_355: This policy is straight from the External DNS documentation
  count       = contains(keys(var.addons), "external-dns") ? 1 : 0
  name        = "${local.name}-external-dns"
  description = "IAM policy for External DNS"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets"
        ]
        Resource = [
          "arn:aws:route53:::hostedzone/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets",
          "route53:ListTagsForResource"
        ]
        Resource = [
          "*"
        ]
      }
    ]
  })

  tags = {
    Name = "${local.name}-external-dns"
  }
}

resource "aws_iam_role_policy_attachment" "external_dns" {
  count      = contains(keys(var.addons), "external-dns") ? 1 : 0
  policy_arn = aws_iam_policy.external_dns[0].arn
  role       = aws_iam_role.external_dns[0].name
}

#-----------------------------------------------------------------------------------------------------------------------
# Create Add-Ons
#-----------------------------------------------------------------------------------------------------------------------

locals {
  addon_configuration = {
    for name, addon in var.addons : name => {
      version = lookup(addon, "version", data.aws_eks_addon_version.default[name].version)
      role_arn = (
        name == "vpc-cni" ? try(aws_iam_role.vpc_cni[0].arn, null) :
        name == "aws-ebs-csi-driver" ? try(aws_iam_role.ebs_csi[0].arn, null) :
        name == "aws-efs-csi-driver" ? try(aws_iam_role.efs_csi[0].arn, null) :
        name == "eks-pod-identity-agent" ? try(aws_iam_role.pod_identity_agent[0].arn, null) :
        name == "external-dns" ? try(aws_iam_role.external_dns[0].arn, null) :
        null
      )
      service_account_name = (
        name == "vpc-cni" ? "aws-node" :
        name == "aws-ebs-csi-driver" ? "ebs-csi-controller-sa" :
        name == "aws-efs-csi-driver" ? "efs-csi-controller-sa" :
        name == "eks-pod-identity-agent" ? "pod-identity-agent" :
        name == "external-dns" ? "external-dns" :
        null
      )
      tags = lookup(addon, "tags", {})
    }
  }
}

resource "aws_eks_addon" "main" {
  for_each = var.addons

  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = each.key
  addon_version               = local.addon_configuration[each.key].version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  service_account_role_arn = (
    each.key == "eks-pod-identity-agent" ? local.addon_configuration[each.key].role_arn : null
  )

  # Configure VPC CNI to allow more max pods per node
  configuration_values = each.key == "vpc-cni" ? jsonencode({
    env = {
      ENABLE_PREFIX_DELEGATION = tostring(var.vpc_cni_config.enable_prefix_delegation)
      WARM_PREFIX_TARGET       = tostring(var.vpc_cni_config.warm_prefix_target)
      WARM_IP_TARGET           = tostring(var.vpc_cni_config.warm_ip_target)
      MINIMUM_IP_TARGET        = tostring(var.vpc_cni_config.minimum_ip_target)
    }
  }) : null

  dynamic "pod_identity_association" {
    for_each = (
      each.key != "eks-pod-identity-agent" &&
      local.addon_configuration[each.key].role_arn != null
    ) ? [1] : []
    content {
      role_arn        = local.addon_configuration[each.key].role_arn
      service_account = local.addon_configuration[each.key].service_account_name
    }
  }
  tags = local.addon_configuration[each.key].tags
}

#-----------------------------------------------------------------------------------------------------------------------
# Kubeconfig
#-----------------------------------------------------------------------------------------------------------------------

locals {
  kubeconfig_path = "${var.context_path}/.kube/config"
}

# Create the kubeconfig directory if it doesn't exist
resource "null_resource" "create_kubeconfig_dir" {
  count = local.kubeconfig_path != "" ? 1 : 0

  provisioner "local-exec" {
    command = "mkdir -p $(dirname ${local.kubeconfig_path})"
  }
}


resource "local_sensitive_file" "kubeconfig" {
  count = local.kubeconfig_path != "" ? 1 : 0

  content = templatefile("${path.module}/templates/kubeconfig.tpl", {
    cluster_name     = aws_eks_cluster.main.name
    cluster_endpoint = aws_eks_cluster.main.endpoint
    cluster_ca       = aws_eks_cluster.main.certificate_authority[0].data
    region           = data.aws_region.current.name
  })
  filename        = local.kubeconfig_path
  file_permission = "0600"

  lifecycle {
    ignore_changes = [content] // Ignore changes to content to prevent unnecessary updates
  }
}
