variable "bucket_name" {
  type        = string
  description = "Globally unique S3 bucket name for the React frontend"
}

variable "domain_name" {
  type        = string
  description = "Frontend domain (e.g. example.com)"
}

variable "route53_zone_id" {
  type        = string
  description = "Route53 hosted zone ID"
}
