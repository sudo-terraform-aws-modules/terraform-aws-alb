module "alb" {
  source = "../.."

  name   = var.name
  vpc_id = var.vpc_id

  # Internet-facing with a module-managed security group.
  # The default rules allow HTTP (80) and HTTPS (443) from 0.0.0.0/0.
  internal              = false
  subnet_ids            = var.subnet_ids
  create_security_group = true

  deletion_protection = false

  target_groups = {
    app = {
      port = 8080
    }
  }

  listeners = {
    http = {
      port     = 80
      redirect = { port = "443", protocol = "HTTPS", status_code = "HTTP_301" }
    }
  }
}

output "alb_dns_name" {
  description = "DNS name of the ALB."
  value       = module.alb.dns_name
}

output "security_group_id" {
  description = "ID of the ALB security group (for target group ingress rules)."
  value       = module.alb.security_group_id
}
