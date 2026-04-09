# Route53 hosted zone
output "route53_zone_id" {
  value       = aws_route53_zone.main.zone_id
  description = "Route53 hosted zone ID"
}

output "route53_name_servers" {
  value       = aws_route53_zone.main.name_servers
  description = "NS records — set these at your domain registrar"
}

output "domain_name" {
  value       = var.domain_name
  description = "Root domain name"
}

# S3 bucket name for remote state storage
output "terraform_state_bucket_name" {
  value       = aws_s3_bucket.terraform_state.bucket
  description = "Set this as the bucket name in envs/dev/main.tf backend config"
}

# DynamoDB table name for state locking
output "terraform_locks_table_name" {
  value       = aws_dynamodb_table.terraform_locks.name
  description = "DynamoDB table for state locking"
}
