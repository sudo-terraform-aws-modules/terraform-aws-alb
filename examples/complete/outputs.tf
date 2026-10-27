output "alb_dns_name" {
  description = "DNS name of the ALB."
  value       = module.alb.dns_name
}

output "target_group_arns" {
  description = "Target group ARNs."
  value       = module.alb.target_group_arns
}
