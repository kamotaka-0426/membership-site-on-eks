variable "origin_verify_secret" {
  type        = string
  description = "Secret value for X-Origin-Verify custom header"
  sensitive   = true
}

variable "origin_domain_name" {
  type        = string
  description = "DNS name of the EKS LoadBalancer Service (e.g. xxx.elb.amazonaws.com)"
}

variable "domain_name" {
  type        = string
  description = "Custom domain for CloudFront (e.g. api.example.com)"
}

variable "route53_zone_id" {
  type        = string
  description = "Route53 hosted zone ID used for ACM DNS validation and alias record"
}
