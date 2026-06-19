// Define the required Terraform version and providers
terraform {
  required_version = ">= 1.12.2"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.47.0"
    }
  }
}

provider "aws" {
  default_tags {
    tags = merge(
      var.tags,
      {
        WindsorContextID = var.context_id
        ManagedBy        = "Terraform"
      }
    )
  }
}


#-----------------------------------------------------------------------------------------------------------------------
# Data
#-----------------------------------------------------------------------------------------------------------------------

data "aws_region" "current" {}

locals {
  name        = var.cluster_name != "" ? var.cluster_name : "cluster-${var.context_id}"
  kms_key_arn = var.enable_secrets_encryption ? (var.secrets_encryption_kms_key_id != null ? var.secrets_encryption_kms_key_id : (length(aws_kms_key.eks_encryption_key) > 0 ? aws_kms_key.eks_encryption_key[0].arn : null)) : null
  ebs_kms_key_id = var.enable_ebs_encryption ? (
    var.ebs_volume_kms_key_id != null ? var.ebs_volume_kms_key_id : (
      length(aws_kms_key.ebs_encryption_key) > 0 ? aws_kms_key.ebs_encryption_key[0].key_id : null
    )
  ) : null
}

#-----------------------------------------------------------------------------------------------------------------------
# EKS Cluster
#-----------------------------------------------------------------------------------------------------------------------

# When manage_log_group is false EKS creates this group itself with no
# retention or CMK. We accept that for ephemeral clusters because TF-managed
# groups race with EKS shutdown writes and leave orphans that block same-name
# recreates.
resource "aws_cloudwatch_log_group" "eks_cluster" {
  count             = var.enable_cloudwatch_logs && var.manage_log_group ? 1 : 0
  name              = "/aws/eks/${local.name}/cluster"
  retention_in_days = 365
  kms_key_id        = local.kms_key_arn

  tags = merge(
    var.tags,
    {
      Name             = "${local.name}-cluster-logs"
      WindsorContextID = var.context_id
    }
  )
}

resource "aws_eks_cluster" "main" {
  # checkov:skip=CKV_AWS_38: Public access set via a variable.
  # checkov:skip=CKV_AWS_39: Public access set via a variable.
  # checkov:skip=CKV_AWS_339: Kubernetes version is populated from the cloud provider's stable version via Renovate.
  name     = local.name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = var.endpoint_private_access
    endpoint_public_access  = var.endpoint_public_access
    security_group_ids      = [aws_security_group.cluster_api_access.id]
  }

  # Enable control plane logging for all log types
  enabled_cluster_log_types = var.enable_cloudwatch_logs ? [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ] : []

  dynamic "encryption_config" {
    for_each = local.kms_key_arn != null ? [1] : []
    content {
      provider {
        key_arn = local.kms_key_arn
      }
      resources = ["secrets"]
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.cluster_AmazonEKSVPCResourceController,
    aws_kms_key.eks_encryption_key,
    aws_cloudwatch_log_group.eks_cluster,
  ]
}

resource "aws_security_group" "cluster_api_access" {
  name        = "${local.name}-cluster-api-access"
  description = "Security group for EKS cluster API access"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.cluster_api_access_cidr_block]
    description = "Allow K8s API access from the specified CIDR block"
  }
}

resource "aws_kms_key" "eks_encryption_key" {
  # checkov:skip=CKV2_AWS_64:Policy is defined inline via jsonencode; checkov's graph engine can't trace the conditional concat() over Statement.
  count                   = var.enable_secrets_encryption && var.secrets_encryption_kms_key_id == null ? 1 : 0
  description             = "KMS key for EKS cluster ${local.name} secrets encryption"
  deletion_window_in_days = var.kms_key_deletion_window_in_days
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = concat([
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
      ],
      var.enable_cloudwatch_logs && var.manage_log_group ? [
        {
          Sid    = "Allow CloudWatch Logs to use the key",
          Effect = "Allow",
          Principal = {
            Service = "logs.${data.aws_region.current.region}.amazonaws.com"
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
    ] : [])
  })
}

resource "aws_kms_alias" "eks_encryption_key" {
  count         = var.enable_secrets_encryption && var.secrets_encryption_kms_key_id == null ? 1 : 0
  name          = "alias/${local.name}-eks-encryption"
  target_key_id = aws_kms_key.eks_encryption_key[0].key_id
}

resource "aws_kms_key" "ebs_encryption_key" {
  count                   = var.enable_ebs_encryption && var.ebs_volume_kms_key_id == null ? 1 : 0
  description             = "KMS key for EKS cluster ${local.name} EBS volume encryption"
  deletion_window_in_days = var.kms_key_deletion_window_in_days
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
        Sid    = "Allow EC2 to use the key for EBS volume encryption",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
          "kms:CreateGrant"
        ],
        Resource = "*"
      },
      {
        Sid    = "Allow service-linked roles to use the key",
        Effect = "Allow",
        Principal = {
          AWS = "*"
        },
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
          "kms:CreateGrant"
        ],
        Resource = "*",
        Condition = {
          StringLike = {
            "aws:PrincipalArn" = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/*"
          }
        }
      }
    ]
  })
}

resource "aws_kms_alias" "ebs_encryption_key" {
  count         = var.enable_ebs_encryption && var.ebs_volume_kms_key_id == null ? 1 : 0
  name          = "alias/${local.name}-ebs-encryption"
  target_key_id = aws_kms_key.ebs_encryption_key[0].key_id
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

locals {
  # Node groups launch into node_subnet_ids when set, else all private subnets.
  # The control plane keeps private_subnet_ids — EKS requires ENIs in >=2 AZs.
  node_subnet_ids = var.node_subnet_ids != null ? var.node_subnet_ids : var.private_subnet_ids

  # Per-pool autoscaling resolution. An explicit pool.autoscaling.enabled wins;
  # otherwise system-class pools are fixed and every other class autoscales.
  pools_autoscaling = {
    for name, p in var.pools : name => {
      enabled = p.autoscaling != null && p.autoscaling.enabled != null ? p.autoscaling.enabled : p.class != "system"
      min     = p.autoscaling != null ? p.autoscaling.min : null
      max     = p.autoscaling != null ? p.autoscaling.max : null
    }
  }

  pools_node_groups = {
    for name, p in var.pools : name => {
      instance_types = p.instance_types != null && length(p.instance_types) > 0 ? p.instance_types : lookup(var.class_instance_types, p.class, null)
      capacity_type  = p.lifecycle == "spot" ? "SPOT" : "ON_DEMAND"
      # desired_size is set once; the autoscaler owns it thereafter (ignore_changes).
      desired_size = p.count
      # Defaults: min 1, max 3 — but never cap below the declared count, so a
      # count>3 pool stays valid (desired must sit within [min, max]).
      autoscaling_enabled = local.pools_autoscaling[name].enabled
      min_size            = local.pools_autoscaling[name].enabled ? coalesce(local.pools_autoscaling[name].min, min(p.count, 1)) : p.count
      max_size            = local.pools_autoscaling[name].enabled ? coalesce(local.pools_autoscaling[name].max, max(p.count, 3)) : p.count
      disk_size           = coalesce(p.root_disk_size, 64)
      labels = merge(
        p.labels,
        {
          "windsorcli.dev/pool"       = name
          "windsorcli.dev/pool-class" = p.class
        }
      )
      # System-class pools carry the CriticalAddonsOnly=true:NoSchedule taint AKS
      # applies via only_critical_addons_enabled, so user workloads avoid them —
      # unless the pool already declares a CriticalAddonsOnly taint of its own.
      taints = concat(
        [for t in p.taints : {
          key    = t.key
          value  = t.value != null ? t.value : ""
          effect = t.effect
        }],
        p.class == "system" && !contains([for t in p.taints : t.key], "CriticalAddonsOnly") ? [{
          key    = "CriticalAddonsOnly"
          value  = "true"
          effect = "NO_SCHEDULE"
        }] : []
      )
    }
  }

  effective_node_groups = length(var.pools) > 0 ? local.pools_node_groups : {
    for name, ng in var.node_groups : name => {
      instance_types      = ng.instance_types
      capacity_type       = ng.capacity_type
      desired_size        = ng.desired_size
      autoscaling_enabled = ng.min_size != ng.max_size
      min_size            = ng.min_size
      max_size            = ng.max_size
      disk_size           = ng.disk_size
      labels              = ng.labels
      taints              = ng.taints
    }
  }

  # Node groups the cluster-autoscaler should manage, for ASG discovery tagging.
  autoscaler_node_groups = {
    for name, ng in local.effective_node_groups : name => ng if ng.autoscaling_enabled
  }
}

resource "aws_eks_node_group" "main" {
  for_each = local.effective_node_groups

  cluster_name           = aws_eks_cluster.main.name
  node_group_name_prefix = "${each.key}-"
  node_role_arn          = aws_iam_role.node_group.arn
  subnet_ids             = local.node_subnet_ids
  instance_types         = each.value.instance_types
  capacity_type          = each.value.capacity_type == "ON_DEMAND" ? null : each.value.capacity_type

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

  launch_template {
    id      = aws_launch_template.node_group[each.key].id
    version = aws_launch_template.node_group[each.key].latest_version
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_group_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.node_group_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.node_group_AmazonEC2ContainerRegistryReadOnly,
  ]

  lifecycle {
    create_before_destroy = true
    ignore_changes = [
      scaling_config[0].desired_size,
    ]
  }
}

# Tag the managed node groups' ASGs so the cluster-autoscaler can auto-discover
# them. Only autoscaling-enabled pools are tagged; fixed pools are left untouched.
resource "aws_autoscaling_group_tag" "cluster_autoscaler_enabled" {
  for_each               = var.create_cluster_autoscaler_role ? local.autoscaler_node_groups : {}
  autoscaling_group_name = aws_eks_node_group.main[each.key].resources[0].autoscaling_groups[0].name

  tag {
    key                 = "k8s.io/cluster-autoscaler/enabled"
    value               = "true"
    propagate_at_launch = false
  }
}

resource "aws_autoscaling_group_tag" "cluster_autoscaler_owned" {
  for_each               = var.create_cluster_autoscaler_role ? local.autoscaler_node_groups : {}
  autoscaling_group_name = aws_eks_node_group.main[each.key].resources[0].autoscaling_groups[0].name

  tag {
    key                 = "k8s.io/cluster-autoscaler/${local.name}"
    value               = "owned"
    propagate_at_launch = false
  }
}

resource "aws_launch_template" "node_group" {
  for_each = local.effective_node_groups

  name_prefix            = "${local.name}-${each.key}-"
  update_default_version = true

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = each.value.disk_size
      volume_type           = "gp3"
      encrypted             = var.enable_ebs_encryption
      kms_key_id            = local.ebs_kms_key_id
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
  subnet_ids             = var.private_subnet_ids

  dynamic "selector" {
    for_each = each.value.selectors
    content {
      namespace = selector.value.namespace
      labels    = lookup(selector.value, "labels", null)
    }
  }

  tags = lookup(each.value, "tags", {})

  lifecycle {
    create_before_destroy = true
  }
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
  count = var.create_external_dns_role || contains(keys(var.addons), "external-dns") ? 1 : 0
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
  count       = var.create_external_dns_role || contains(keys(var.addons), "external-dns") ? 1 : 0
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
  count      = var.create_external_dns_role || contains(keys(var.addons), "external-dns") ? 1 : 0
  policy_arn = aws_iam_policy.external_dns[0].arn
  role       = aws_iam_role.external_dns[0].name
}

#-----------------------------------------------------------------------------------------------------------------------
# AWS Load Balancer Controller IAM Role
#-----------------------------------------------------------------------------------------------------------------------

resource "aws_iam_role" "aws_lb_controller" {
  count = var.create_aws_lb_controller_role ? 1 : 0
  name  = "${local.name}-aws-lb-controller"

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
    Name = "${local.name}-aws-lb-controller"
  }
}

resource "aws_iam_policy" "aws_lb_controller" {
  # Verbatim from upstream:
  # https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json
  # checkov:skip=CKV_AWS_355: Wildcard resources are required by the upstream policy.
  # checkov:skip=CKV_AWS_109: Same as above.
  # checkov:skip=CKV_AWS_111: Same as above.
  count       = var.create_aws_lb_controller_role ? 1 : 0
  name        = "${local.name}-aws-lb-controller"
  description = "IAM policy for the AWS Load Balancer Controller"
  policy      = file("${path.module}/iam-policies/aws-lb-controller.json")

  tags = {
    Name = "${local.name}-aws-lb-controller"
  }
}

resource "aws_iam_role_policy_attachment" "aws_lb_controller" {
  count      = var.create_aws_lb_controller_role ? 1 : 0
  policy_arn = aws_iam_policy.aws_lb_controller[0].arn
  role       = aws_iam_role.aws_lb_controller[0].name
}

resource "aws_iam_role" "cluster_autoscaler" {
  count = var.create_cluster_autoscaler_role ? 1 : 0
  name  = "${local.name}-cluster-autoscaler"

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
    Name = "${local.name}-cluster-autoscaler"
  }
}

resource "aws_iam_policy" "cluster_autoscaler" {
  # Read actions need account-wide scope for ASG/instance discovery (they don't
  # support resource-level permissions). The mutating actions are scoped to the
  # autoscaling-group ARN pattern and further gated to ASGs this cluster owns via
  # the discovery-tag condition.
  count       = var.create_cluster_autoscaler_role ? 1 : 0
  name        = "${local.name}-cluster-autoscaler"
  description = "IAM policy for the Kubernetes cluster-autoscaler"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ClusterAutoscalerDiscovery"
        Effect = "Allow"
        # autoscaling:* and ec2:Describe*/Get* don't support resource-level
        # permissions, so "*" is the only valid scope for them.
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeScalingActivities",
          "autoscaling:DescribeTags",
          "ec2:DescribeImages",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:GetInstanceTypesFromInstanceRequirements",
        ]
        Resource = "*"
      },
      {
        Sid      = "ClusterAutoscalerDescribeNodegroups"
        Effect   = "Allow"
        Action   = ["eks:DescribeNodegroup"]
        Resource = "arn:aws:eks:*:*:nodegroup/${local.name}/*/*"
      },
      {
        Sid    = "ClusterAutoscalerManageOwnedGroups"
        Effect = "Allow"
        Action = [
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup",
        ]
        Resource = "arn:aws:autoscaling:*:*:autoScalingGroup:*:autoScalingGroupName/*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/k8s.io/cluster-autoscaler/${local.name}" = "owned"
          }
        }
      },
    ]
  })

  tags = {
    Name = "${local.name}-cluster-autoscaler"
  }
}

resource "aws_iam_role_policy_attachment" "cluster_autoscaler" {
  count      = var.create_cluster_autoscaler_role ? 1 : 0
  policy_arn = aws_iam_policy.cluster_autoscaler[0].arn
  role       = aws_iam_role.cluster_autoscaler[0].name
}

#-----------------------------------------------------------------------------------------------------------------------
# Cert Manager IAM Role (ACME Route53 DNS-01 solver)
#-----------------------------------------------------------------------------------------------------------------------

resource "aws_iam_role" "cert_manager" {
  count = var.create_cert_manager_role ? 1 : 0
  name  = "${local.name}-cert-manager"

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
    Name = "${local.name}-cert-manager"
  }
}

resource "aws_iam_policy" "cert_manager" {
  # This policy is based on the official cert-manager documentation for the
  # Route53 DNS-01 solver:
  # https://cert-manager.io/docs/configuration/acme/dns01/route53/
  count       = var.create_cert_manager_role ? 1 : 0
  name        = "${local.name}-cert-manager"
  description = "IAM policy for cert-manager ACME Route53 DNS-01 solver"

  # Scope record-write actions to the operator-supplied zone IDs when set,
  # so cert-manager can't touch unrelated zones in the same account. Falls
  # back to a wildcard when no zones are passed (legacy direct-module use).
  # ListHostedZonesByName remains '*' — the cert-manager solver calls it
  # without a zone ID and AWS doesn't accept resource-level constraints
  # on it.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["route53:GetChange"]
        Resource = "arn:aws:route53:::change/*"
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets",
          "route53:ListResourceRecordSets",
        ]
        Resource = length(var.cert_manager_hosted_zone_ids) > 0 ? [
          for id in var.cert_manager_hosted_zone_ids : "arn:aws:route53:::hostedzone/${id}"
        ] : ["arn:aws:route53:::hostedzone/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["route53:ListHostedZonesByName"]
        Resource = "*"
      },
    ]
  })

  tags = {
    Name = "${local.name}-cert-manager"
  }
}

resource "aws_iam_role_policy_attachment" "cert_manager" {
  count      = var.create_cert_manager_role ? 1 : 0
  policy_arn = aws_iam_policy.cert_manager[0].arn
  role       = aws_iam_role.cert_manager[0].name
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
  depends_on = [
    aws_eks_node_group.main
  ]

  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = each.key
  addon_version               = local.addon_configuration[each.key].version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

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

resource "aws_eks_pod_identity_association" "external_dns" {
  count = var.create_external_dns_role && !contains(keys(var.addons), "external-dns") ? 1 : 0

  cluster_name    = aws_eks_cluster.main.name
  namespace       = "system-dns"
  service_account = "external-dns"
  role_arn        = aws_iam_role.external_dns[0].arn
}

resource "aws_eks_pod_identity_association" "aws_lb_controller" {
  count = var.create_aws_lb_controller_role ? 1 : 0

  cluster_name    = aws_eks_cluster.main.name
  namespace       = "system-lb"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.aws_lb_controller[0].arn
}

resource "aws_eks_pod_identity_association" "cluster_autoscaler" {
  count = var.create_cluster_autoscaler_role ? 1 : 0

  cluster_name    = aws_eks_cluster.main.name
  namespace       = "system-compute"
  service_account = "cluster-autoscaler"
  role_arn        = aws_iam_role.cluster_autoscaler[0].arn
}

resource "aws_eks_pod_identity_association" "cert_manager" {
  count = var.create_cert_manager_role ? 1 : 0

  cluster_name    = aws_eks_cluster.main.name
  namespace       = "system-pki"
  service_account = "cert-manager"
  role_arn        = aws_iam_role.cert_manager[0].arn
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

  content = templatefile("${path.module}/_templates/kubeconfig.tpl", {
    cluster_name     = aws_eks_cluster.main.name
    cluster_endpoint = aws_eks_cluster.main.endpoint
    cluster_ca       = aws_eks_cluster.main.certificate_authority[0].data
    region           = data.aws_region.current.region
  })
  filename        = local.kubeconfig_path
  file_permission = "0600"

  lifecycle {
    ignore_changes = [content]
  }
}
