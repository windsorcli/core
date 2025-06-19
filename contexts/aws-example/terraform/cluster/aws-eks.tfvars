# Managed by Windsor CLI: This file is partially managed by the windsor CLI. Your changes will not be overwritten.
# Module source: github.com/windsorcli/core//terraform/cluster/aws-eks?ref=main

# The name of the EKS cluster.
# cluster_name = ""

# The kubernetes version to deploy.
# kubernetes_version = "1.32"

# Whether to enable public access to the EKS cluster.
# endpoint_public_access = true

# The CIDR block for the cluster API access.
# cluster_api_access_cidr_block = "0.0.0.0/0"

# The ID of the VPC where the EKS cluster will be created.
# vpc_id = null

# Map of EKS managed node group definitions to create.
# node_groups = {
#   default = {
#     desired_size = null
#     instance_types = ["t3.medium"]
#     max_size = null
#     min_size = null
#   }
# }

# Maximum number of pods that can run on a single node
# max_pods_per_node = null

# Configuration for the VPC CNI addon
# vpc_cni_config = {
#   enable_prefix_delegation = true
#   minimum_ip_target = null
#   warm_ip_target = null
#   warm_prefix_target = null
# }

# Map of EKS Fargate profile definitions to create.
# fargate_profiles = {}

# Map of EKS add-ons
# addons = {
#   aws-ebs-csi-driver = {}
#   aws-efs-csi-driver = {}
#   coredns = {}
#   eks-pod-identity-agent = {}
#   external-dns = {}
#   vpc-cni = {}
# }
