module "alb" {
  source = "../.."

  name   = var.name
  vpc_id = var.vpc_id

  # Internet-facing with a module-managed security group.
  # The default rules allow HTTP (80) and HTTPS (443) from 0.0.0.0/0.
  internal              = false
  subnet_ids            = var.subnet_ids
  create_security_group = true

  # Access logs are enabled by default and require an S3 bucket. The minimal
  # example turns them off; see examples/complete for a bucket-backed setup.
  access_logs_enabled = false
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
