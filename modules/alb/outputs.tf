output "alb_name" {
  description = "The name of the ALB that has been deployed using this module."
  value       = aws_alb.alb.name
}

output "alb_arn" {
  description = "The AWS ARN of the ALB that has been deployed using this module."
  value       = aws_alb.alb.arn
}

output "alb_arn_suffix" {
  description = "The AWS ARN Suffix of the ALB that has been deployed using this module."
  value       = aws_alb.alb.arn_suffix
}

output "alb_dns_name" {
  description = "The DNS name that can be used to reach the ALB that has been deployed using this module."
  value       = aws_alb.alb.dns_name
}

output "alb_hosted_zone_id" {
  description = "The Route 53 Hosted Zone ID that manages the DNS record for the ALB that has been deployed using this module."
  value       = aws_alb.alb.zone_id
}

output "alb_security_group_id" {
  description = "The AWS ID of the security group for the ALB that has been deployed using this module."
  value       = aws_security_group.alb.id
}

output "listener_arns" {
  description = "A map from port to the AWS ARNs of the listeners for the ALB that has been deployed using this module."
  value = merge(
    local.http_listener_port_arns,
    local.https_listener_non_acm_port_arns,
    local.https_listener_acm_port_arns,
  )
}

output "http_listener_arns" {
  description = "A map from port to the AWS ARNs of the HTTP listener for the ALB that has been deployed using this module."
  value       = local.http_listener_port_arns
}

output "https_listener_non_acm_cert_arns" {
  description = "A map from port to the AWS ARNs of the HTTPS listener that uses non-ACM SSL certificates for the ALB that has been deployed using this module."
  value       = local.https_listener_non_acm_port_arns
}

output "https_listener_acm_cert_arns" {
  description = "A map from port to the AWS ARNs of the HTTPS listener that uses ACM SSL certificates for the ALB that has been deployed using this module."
  value       = local.https_listener_acm_port_arns
}

# ---------------------------------------------------------------------------------------------------------------------
# INTERMEDIATE COMPUTATIONS
# The following locals are intermediate computations to make the output computations easier to manage
# ---------------------------------------------------------------------------------------------------------------------

locals {
  http_listener_port_arns = {
    for listener in aws_alb_listener.http :
    listener.port => listener.arn
  }
  https_listener_non_acm_port_arns = {
    for listener in aws_alb_listener.https_non_acm_certs :
    listener.port => listener.arn
  }
  https_listener_acm_port_arns = {
    for listener in aws_alb_listener.https_acm_certs :
    listener.port => listener.arn
  }
}
