output "db_password_raw" {
  value     = random_password.db_password.result
  sensitive = true
}

output "db_instance_endpoint" {
  value = aws_db_instance.main.address
}

output "db_secret_arn" {
  value       = aws_secretsmanager_secret.db_password.arn
  description = "ARN of the Secrets Manager secret containing the RDS password"
}
