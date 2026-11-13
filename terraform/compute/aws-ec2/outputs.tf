output "controlplanes" {
  description = "Control plane nodes in the shape cluster/talos consumes."
  value = [
    for node in var.controlplanes : {
      hostname    = node.hostname
      endpoint    = "${aws_instance.this[node.hostname].private_ip}:50000"
      node        = aws_instance.this[node.hostname].private_ip
      instance_id = aws_instance.this[node.hostname].id
    }
  ]
}

output "workers" {
  description = "Worker nodes in the shape cluster/talos consumes."
  value = [
    for node in var.workers : {
      hostname    = node.hostname
      endpoint    = "${aws_instance.this[node.hostname].private_ip}:50000"
      node        = aws_instance.this[node.hostname].private_ip
      instance_id = aws_instance.this[node.hostname].id
    }
  ]
}

output "security_group_id" {
  description = "Security group attached to every node."
  value       = aws_security_group.this.id
}

output "ami_id" {
  description = "AMI the nodes booted."
  value       = local.ami_id
}
