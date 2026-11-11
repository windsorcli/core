variable "context_id" {
  description = "The windsor context id for this deployment; used to name and tag resources."
  type        = string
  default     = ""
}

variable "context_path" {
  description = "The path to the context folder."
  type        = string
  default     = ""
}

variable "region" {
  description = "AWS region to launch the nodes in."
  type        = string
}

variable "subnet_id" {
  description = "Existing subnet to launch the nodes in. Every node address must fall inside it."
  type        = string
}

variable "talos_version" {
  description = "Talos version whose published AMI the nodes boot, with or without a leading v."
  type        = string
}

variable "ami_id" {
  description = "AMI to boot instead of the published Talos AMI for talos_version."
  type        = string
  default     = ""
}

variable "controlplanes" {
  description = "Control plane nodes to launch, each at its fixed private IP."
  type = list(object({
    hostname = string
    node     = string
  }))

  validation {
    condition     = length(var.controlplanes) > 0
    error_message = "At least one control plane node is required."
  }
}

variable "workers" {
  description = "Worker nodes to launch, each at its fixed private IP."
  type = list(object({
    hostname = string
    node     = string
  }))
  default = []
}

variable "controlplane_instance_type" {
  description = "EC2 instance type for control plane nodes."
  type        = string
}

variable "worker_instance_type" {
  description = "EC2 instance type for worker nodes. Defaults to the control plane type."
  type        = string
  default     = ""
}

variable "root_volume_size" {
  description = "Root volume size in GB."
  type        = number
  default     = 100

  validation {
    condition     = var.root_volume_size >= 8
    error_message = "Root volume size must be at least 8 GB."
  }
}

variable "root_volume_iops" {
  description = "Provisioned gp3 IOPS for the root volume."
  type        = number
  default     = 3000
}

variable "root_volume_throughput" {
  description = "Provisioned gp3 throughput for the root volume, in MB/s."
  type        = number
  default     = 125
}

variable "kms_key_id" {
  description = "KMS key that encrypts the root volume."
  type        = string
  default     = "alias/aws/ebs"
}

variable "allowed_cidr" {
  description = "CIDR allowed to reach the Talos API, the Kubernetes API and NodePorts. Defaults to the VPC CIDR."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags for every resource."
  type        = map(string)
  default     = {}
}
