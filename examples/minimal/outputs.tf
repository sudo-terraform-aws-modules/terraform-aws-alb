output "alb_dns_name" {
  description = "DNS name of the ALB."
  value       = module.alb.dns_name
}

output "security_group_id" {
  description = "ID of the ALB security group (for target group ingress rules)."
  value       = module.alb.security_group_id
}
