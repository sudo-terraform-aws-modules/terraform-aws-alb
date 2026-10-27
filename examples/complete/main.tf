module "alb" {
  source = "../.."

  name               = var.name
  internal           = false
  vpc_id             = var.vpc_id
  subnet_ids         = var.subnet_ids
  security_group_ids = var.security_group_ids

  access_logs_bucket = var.access_logs_bucket

  deletion_protection = false
  idle_timeout        = 60
  enable_http2        = true

  target_groups = {
    app = {
      port     = 8080
      protocol = "HTTP"
      health_check = {
        path    = "/health"
        matcher = "200"
      }
    }
    api = {
      port     = 9090
      protocol = "HTTP"
      health_check = {
        path     = "/api/health"
        matcher  = "200-299"
        interval = 15
      }
    }
  }

  listeners = {
    http = {
      port     = 80
      protocol = "HTTP"
      redirect = {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
    https = {
      port             = 443
      protocol         = "HTTPS"
      certificate_arn  = var.certificate_arn
      target_group_key = "app"
    }
  }

  listener_rules = {
    api = {
      listener_key     = "https"
      target_group_key = "api"
      priority         = 10
      path_pattern     = ["/api/*"]
    }
  }

  tags = {
    Environment = "production"
    Team        = "platform"
  }
}
