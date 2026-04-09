# Route53 hosted zone — provisioned as part of the bootstrap foundation
resource "aws_route53_zone" "main" {
  name = var.domain_name
}

variable "domain_name" {
  type        = string
  description = "Root domain name for the hosted zone (e.g. 'example.com')"
}
