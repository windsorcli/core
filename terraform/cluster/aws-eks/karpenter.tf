#-----------------------------------------------------------------------------------------------------------------------
# Karpenter substrate
# AWS-side prerequisites for self-hosted Karpenter: controller and node IAM, the
# spot-interruption SQS queue with its EventBridge rules, and subnet/security-group
# discovery tags. Karpenter itself is deployed via Flux and consumes the outputs.
# Gated by enable_karpenter; the resources sit unused until the Karpenter release
# is deployed, so enabling this alone does not change a running cluster.
#-----------------------------------------------------------------------------------------------------------------------

locals {
  karpenter_node_managed_policies = var.enable_karpenter ? toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ]) : toset([])

  # EventBridge rules that feed node-disruption events to the interruption queue.
  karpenter_event_rules = var.enable_karpenter ? {
    spot_interruption     = { source = ["aws.ec2"], detail_type = ["EC2 Spot Instance Interruption Warning"] }
    rebalance             = { source = ["aws.ec2"], detail_type = ["EC2 Instance Rebalance Recommendation"] }
    instance_state_change = { source = ["aws.ec2"], detail_type = ["EC2 Instance State-change Notification"] }
    scheduled_change      = { source = ["aws.health"], detail_type = ["AWS Health Event"] }
  } : {}
}

# Controller role, assumed via EKS Pod Identity.
resource "aws_iam_role" "karpenter_controller" {
  count = var.enable_karpenter ? 1 : 0
  name  = "${local.name}-karpenter"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
    }]
  })

  tags = { Name = "${local.name}-karpenter" }
}

resource "aws_iam_policy" "karpenter_controller" {
  # Scoped Karpenter v1 controller policy. The regional-read and pricing actions
  # do not support resource-level permissions, so they require "*".
  # checkov:skip=CKV_AWS_355: Wildcard resources required by the read actions.
  # checkov:skip=CKV_AWS_109: Same as above.
  # checkov:skip=CKV_AWS_111: Same as above.
  count       = var.enable_karpenter ? 1 : 0
  name        = "${local.name}-karpenter"
  description = "IAM policy for the Karpenter controller"
  policy = templatefile("${path.module}/iam-policies/karpenter-controller.json", {
    cluster_name           = local.name
    region                 = data.aws_region.current.region
    account_id             = data.aws_caller_identity.current.account_id
    node_role_arn          = aws_iam_role.karpenter_node[0].arn
    interruption_queue_arn = aws_sqs_queue.karpenter[0].arn
  })

  tags = { Name = "${local.name}-karpenter" }
}

resource "aws_iam_role_policy_attachment" "karpenter_controller" {
  count      = var.enable_karpenter ? 1 : 0
  policy_arn = aws_iam_policy.karpenter_controller[0].arn
  role       = aws_iam_role.karpenter_controller[0].name
}

resource "aws_eks_pod_identity_association" "karpenter" {
  count = var.enable_karpenter ? 1 : 0

  cluster_name    = aws_eks_cluster.main.name
  namespace       = "system-compute"
  service_account = "karpenter"
  role_arn        = aws_iam_role.karpenter_controller[0].arn
}

# Node role and instance profile for Karpenter-provisioned nodes. The instance
# profile is created here (not by Karpenter) so the controller policy can omit
# instance-profile management permissions; the EC2NodeClass references it directly.
resource "aws_iam_role" "karpenter_node" {
  count = var.enable_karpenter ? 1 : 0
  name  = "${local.name}-karpenter-node"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = { Name = "${local.name}-karpenter-node" }
}

resource "aws_iam_role_policy_attachment" "karpenter_node" {
  for_each   = local.karpenter_node_managed_policies
  policy_arn = each.value
  role       = aws_iam_role.karpenter_node[0].name
}

resource "aws_iam_instance_profile" "karpenter_node" {
  count = var.enable_karpenter ? 1 : 0
  name  = "${local.name}-karpenter-node"
  role  = aws_iam_role.karpenter_node[0].name
  tags  = { Name = "${local.name}-karpenter-node" }
}

# Spot-interruption queue. Karpenter drains and replaces nodes ahead of
# reclamation by consuming interruption, rebalance, and health events.
resource "aws_sqs_queue" "karpenter" {
  count                     = var.enable_karpenter ? 1 : 0
  name                      = "${local.name}-karpenter"
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true
  tags                      = { Name = "${local.name}-karpenter" }
}

resource "aws_sqs_queue_policy" "karpenter" {
  count     = var.enable_karpenter ? 1 : 0
  queue_url = aws_sqs_queue.karpenter[0].url

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "EC2InterruptionPolicy"
      Effect    = "Allow"
      Principal = { Service = ["events.amazonaws.com", "sqs.amazonaws.com"] }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.karpenter[0].arn
    }]
  })
}

resource "aws_cloudwatch_event_rule" "karpenter" {
  for_each = local.karpenter_event_rules
  name     = "${local.name}-karpenter-${each.key}"
  event_pattern = jsonencode({
    source      = each.value.source
    detail-type = each.value.detail_type
  })
  tags = { Name = "${local.name}-karpenter-${each.key}" }
}

resource "aws_cloudwatch_event_target" "karpenter" {
  for_each  = local.karpenter_event_rules
  rule      = aws_cloudwatch_event_rule.karpenter[each.key].name
  target_id = "KarpenterInterruptionQueue"
  arn       = aws_sqs_queue.karpenter[0].arn
}

# Discovery tags let the EC2NodeClass select subnets and the cluster security
# group by tag instead of hardcoding IDs.
resource "aws_ec2_tag" "karpenter_discovery_subnet" {
  for_each    = var.enable_karpenter ? toset(local.node_subnet_ids) : toset([])
  resource_id = each.value
  key         = "karpenter.sh/discovery"
  value       = local.name
}

resource "aws_ec2_tag" "karpenter_discovery_sg" {
  count       = var.enable_karpenter ? 1 : 0
  resource_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  key         = "karpenter.sh/discovery"
  value       = local.name
}
