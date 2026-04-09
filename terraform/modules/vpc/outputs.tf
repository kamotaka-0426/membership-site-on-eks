output "vpc_id" {
  value = aws_vpc.main.id
}

output "private_subnet_ids" {
  value = [aws_subnet.private_a.id, aws_subnet.private_c.id]
}

output "public_subnet_ids" {
  value = [aws_subnet.public_a.id, aws_subnet.public_c.id]
}

output "eks_nodes_sg_id" {
  value       = aws_security_group.eks_nodes.id
  description = "Security group ID for EKS worker nodes"
}
