variable "github_repo" {
  type        = string
  description = "GitHub repository in 'owner/repo' format (e.g. 'kamotaka-0426/membership-site-on-eks')"
}

variable "frontend_bucket_name" {
  type        = string
  description = "Globally unique S3 bucket name for the React frontend (e.g. 'membership-blog-eks-frontend-20260405')"
}
