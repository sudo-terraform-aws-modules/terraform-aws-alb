output "arn" {
  description = "ARN of the ALB."
  value       = try(aws_lb.this[0].arn, null)
}

output "dns_name" {
  description = "DNS name of the ALB. Use as the alias target in Route53."
  value       = try(aws_lb.this[0].dns_name, null)
}

output "zone_id" {
  description = "Hosted zone ID of the ALB. Use with Route53 alias records."
  value       = try(aws_lb.this[0].zone_id, null)
}

output "id" {
  description = "ID of the ALB."
  value       = try(aws_lb.this[0].id, null)
}

output "security_group_id" {
  description = "ID of the module-created security group. Null when create_security_group is false."
  value       = try(aws_security_group.this[0].id, null)
}

output "security_group_arn" {
  description = "ARN of the module-created security group. Null when create_security_group is false."
  value       = try(aws_security_group.this[0].arn, null)
}

output "target_group_arns" {
  description = "Map of logical target group key to ARN."
  value       = { for k, v in aws_lb_target_group.this : k => v.arn }
}

output "target_groups" {
  description = "Map of target group attributes keyed by logical name."
  value = {
    for k, v in aws_lb_target_group.this : k => {
      arn  = v.arn
      name = v.name
      port = v.port
    }
  }
}

output "listener_arns" {
  description = "Map of logical listener key to ARN."
  value       = { for k, v in aws_lb_listener.this : k => v.arn }
}

output "listener_rule_arns" {
  description = "Map of logical listener rule key to ARN."
  value       = { for k, v in aws_lb_listener_rule.this : k => v.arn }
}

output "waf_acl_association_id" {
  description = "ID of the WAFv2 web ACL association, or null when no WAF is attached."
  value       = try(aws_wafv2_web_acl_association.this[0].id, null)
}
