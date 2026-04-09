# GitHub OIDC Provider (one per AWS account is sufficient)
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # Empty list defers to AWS-managed Root CA verification
  thumbprint_list = []
}

# IAM role assumed by GitHub Actions via OIDC
resource "aws_iam_role" "github_actions" {
  name = "github-actions-oidc-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Condition = {
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*"
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

# ECR push/pull permissions
resource "aws_iam_role_policy_attachment" "github_actions_ecr_power_user" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

# EKS describe permissions (required for aws eks update-kubeconfig)
resource "aws_iam_role_policy" "github_actions_eks" {
  name = "github-actions-eks"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster", "eks:ListClusters"]
        Resource = "*"
      }
    ]
  })
}

# S3 and CloudFront permissions for frontend deployment
resource "aws_iam_role_policy" "github_actions_frontend" {
  name = "github-actions-frontend"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:ListBucket", "s3:DeleteObject"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["cloudfront:CreateInvalidation"]
        Resource = "*"
      }
    ]
  })
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}
