# terraform/modules/eks/outputs.tf

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_certificate_authority_data" {
  description = "EKS cluster certificate authority data"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider ARN"
  value       = aws_iam_openid_connect_provider.main.arn
}

output "oidc_provider" {
  description = "IAM OIDC provider URL (without https://)"
  value       = replace(aws_iam_openid_connect_provider.main.url, "https://", "")
}
