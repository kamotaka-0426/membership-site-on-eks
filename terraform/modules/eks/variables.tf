variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "public_subnet_ids" { type = list(string) }
variable "eks_nodes_sg_id" {
  type        = string
  description = "Security group ID for EKS worker nodes"
}
variable "github_actions_role_arn" {
  type        = string
  description = "ARN of the GitHub Actions OIDC role to grant cluster admin access"
}
