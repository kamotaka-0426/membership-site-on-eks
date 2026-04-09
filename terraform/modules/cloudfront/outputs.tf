output "distribution_id" {
  value       = aws_cloudfront_distribution.api.id
  description = "CloudFront distribution ID for the API"
}

output "distribution_domain_name" {
  value       = aws_cloudfront_distribution.api.domain_name
  description = "CloudFront domain name for the API"
}
