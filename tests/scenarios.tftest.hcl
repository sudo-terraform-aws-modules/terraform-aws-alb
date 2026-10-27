# End-to-end plan scenarios. Each run exercises a realistic configuration
# shape (not just a single validation) and asserts the key resources plan.
# Uses the mock provider so no AWS credentials are required. Data sources
# that return CIDRs are overridden with a valid value so the ingress rule
# resource does not reject the generated value.

mock_provider "aws" {
  mock_data "aws_vpc" {
    defaults = {
      cidr_block = "10.0.0.0/16"
    }
  }
}

# ── Internet-facing, module-managed SG, no logs (minimal shape) ───────────────

run "scenario_internet_facing_managed_sg_no_logs" {
  command = plan

  variables {
    name                  = "edge-alb"
    internal              = false
    vpc_id                = "vpc-00000000"
    subnet_ids            = ["subnet-00000001", "subnet-00000002"]
    create_security_group = true
    access_logs_enabled   = false
    deletion_protection   = false
    target_groups = {
      app = { port = 8080 }
    }
    listeners = {
      http = {
        port     = 80
        redirect = { port = "443", protocol = "HTTPS", status_code = "HTTP_301" }
      }
    }
  }

  assert {
    condition     = aws_lb.this[0].internal == false
    error_message = "ALB should be internet-facing."
  }

  assert {
    condition     = length(aws_security_group.this) == 1
    error_message = "Module-managed security group should be created."
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.this) == 2
    error_message = "Internet-facing default should create two ingress rules (HTTP + HTTPS)."
  }

  assert {
    condition     = length(aws_lb_listener.this) == 1
    error_message = "One listener should be planned."
  }
}

# ── Internet-facing, caller-supplied SG, access logs (complete shape) ─────────

run "scenario_internet_facing_external_sg_with_logs" {
  command = plan

  variables {
    name               = "prod-alb"
    internal           = false
    vpc_id             = "vpc-00000000"
    subnet_ids         = ["subnet-00000001", "subnet-00000002"]
    security_group_ids = ["sg-00000001", "sg-00000002"]
    access_logs_bucket = "my-alb-logs"
    target_groups = {
      app = {
        port         = 8080
        health_check = { path = "/health", matcher = "200" }
      }
      api = {
        port         = 9090
        health_check = { path = "/api/health", matcher = "200-299", interval = 15 }
      }
    }
    listeners = {
      http = {
        port     = 80
        redirect = { port = "443", protocol = "HTTPS", status_code = "HTTP_301" }
      }
      https = {
        port             = 443
        protocol         = "HTTPS"
        certificate_arn  = "arn:aws:acm:us-east-1:123456789012:certificate/test"
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
  }

  assert {
    condition     = length(aws_lb_target_group.this) == 2
    error_message = "Two target groups should be planned."
  }

  assert {
    condition     = length(aws_lb_listener.this) == 2
    error_message = "Two listeners (http + https) should be planned."
  }

  assert {
    condition     = length(aws_lb_listener_rule.this) == 1
    error_message = "One listener rule should be planned."
  }

  assert {
    condition     = length(aws_security_group.this) == 0
    error_message = "No module-managed SG should be created when create_security_group = false."
  }
}

# ── Internal ALB, managed SG, VPC CIDR ingress by default ─────────────────────

run "scenario_internal_managed_sg_vpc_cidr_default" {
  command = plan

  variables {
    name                  = "svc-alb"
    internal              = true
    vpc_id                = "vpc-00000000"
    subnet_ids            = ["subnet-00000001", "subnet-00000002"]
    create_security_group = true
    access_logs_enabled   = false
    target_groups = {
      app = { port = 8080 }
    }
    listeners = {
      https = {
        port             = 443
        protocol         = "HTTPS"
        certificate_arn  = "arn:aws:acm:us-east-1:123456789012:certificate/test"
        target_group_key = "app"
      }
    }
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.this) == 1
    error_message = "Internal default should create exactly one ingress rule (HTTPS from VPC CIDR)."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.this["https"].cidr_ipv4 == "10.0.0.0/16"
    error_message = "Internal default ingress should use the VPC CIDR, not 0.0.0.0/0."
  }
}

# ── Internal ALB with allow_plaintext_http (service-to-service) ───────────────

run "scenario_internal_allow_plaintext_http" {
  command = plan

  variables {
    name                 = "svc-alb"
    internal             = true
    allow_plaintext_http = true
    vpc_id               = "vpc-00000000"
    subnet_ids           = ["subnet-00000001", "subnet-00000002"]
    security_group_ids   = ["sg-00000001"]
    access_logs_enabled  = false
    target_groups = {
      app = { port = 8080 }
    }
    listeners = {
      http = {
        port             = 80
        target_group_key = "app"
      }
    }
  }

  assert {
    condition     = aws_lb_listener.this["http"].protocol == "HTTP"
    error_message = "HTTP listener should be planned when allow_plaintext_http = true and internal = true."
  }
}

# ── Dualstack ALB with IPv6 subnets ───────────────────────────────────────────

run "scenario_dualstack_ipv6" {
  command = plan

  variables {
    name                = "ipv6-alb"
    internal            = false
    ip_address_type     = "dualstack"
    vpc_id              = "vpc-00000000"
    subnet_ids          = ["subnet-00000001", "subnet-00000002"]
    security_group_ids  = ["sg-00000001"]
    access_logs_enabled = false
  }

  assert {
    condition     = aws_lb.this[0].ip_address_type == "dualstack"
    error_message = "ALB should be planned with dualstack IP address type."
  }
}

# ── Target groups: stickiness variants (lb_cookie, app_cookie, source_ip) ─────

run "scenario_stickiness_variants" {
  command = plan

  variables {
    name                = "sticky-alb"
    internal            = true
    vpc_id              = "vpc-00000000"
    subnet_ids          = ["subnet-00000001", "subnet-00000002"]
    security_group_ids  = ["sg-00000001"]
    access_logs_enabled = false
    target_groups = {
      lbcook = {
        port = 8080
        stickiness = {
          type            = "lb_cookie"
          cookie_duration = 3600
        }
      }
      appcok = {
        port = 8081
        stickiness = {
          type            = "app_cookie"
          cookie_name     = "SESSION"
          cookie_duration = 7200
        }
      }
      srcip = {
        port = 8082
        stickiness = {
          type = "source_ip"
        }
      }
    }
  }

  assert {
    condition     = length(aws_lb_target_group.this) == 3
    error_message = "All three stickiness variants should plan successfully."
  }
}

# ── Listener rules covering all three condition types ─────────────────────────

run "scenario_listener_rules_all_condition_types" {
  command = plan

  variables {
    name                = "routed-alb"
    internal            = true
    vpc_id              = "vpc-00000000"
    subnet_ids          = ["subnet-00000001", "subnet-00000002"]
    security_group_ids  = ["sg-00000001"]
    access_logs_enabled = false
    target_groups = {
      api  = { port = 9090 }
      web  = { port = 8080 }
      beta = { port = 8081 }
    }
    listeners = {
      https = {
        port             = 443
        protocol         = "HTTPS"
        certificate_arn  = "arn:aws:acm:us-east-1:123456789012:certificate/test"
        target_group_key = "web"
      }
    }
    listener_rules = {
      by_path = {
        listener_key     = "https"
        target_group_key = "api"
        priority         = 10
        path_pattern     = ["/api/*", "/v2/*"]
      }
      by_host = {
        listener_key     = "https"
        target_group_key = "web"
        priority         = 20
        host_header      = ["app.example.com"]
      }
      by_header = {
        listener_key     = "https"
        target_group_key = "beta"
        priority         = 30
        http_header = {
          name   = "X-Beta"
          values = ["true"]
        }
      }
    }
  }

  assert {
    condition     = length(aws_lb_listener_rule.this) == 3
    error_message = "All three listener rules (path, host, header) should plan."
  }
}

# ── Connection logs enabled alongside access logs ─────────────────────────────

run "scenario_access_and_connection_logs" {
  command = plan

  variables {
    name                   = "logged-alb"
    internal               = false
    vpc_id                 = "vpc-00000000"
    subnet_ids             = ["subnet-00000001", "subnet-00000002"]
    security_group_ids     = ["sg-00000001"]
    access_logs_bucket     = "my-access-logs"
    access_logs_prefix     = "alb/access"
    connection_logs_bucket = "my-conn-logs"
    connection_logs_prefix = "alb/conn"
  }

  assert {
    condition     = length(aws_lb.this[0].access_logs) == 1
    error_message = "Access logs block should be planned when bucket is set."
  }

  assert {
    condition     = length(aws_lb.this[0].connection_logs) == 1
    error_message = "Connection logs block should be planned when bucket is set."
  }
}

# ── Explicit ingress rules override the default ───────────────────────────────

run "scenario_explicit_ingress_rules_override_default" {
  command = plan

  variables {
    name                  = "custom-alb"
    internal              = false
    vpc_id                = "vpc-00000000"
    subnet_ids            = ["subnet-00000001", "subnet-00000002"]
    create_security_group = true
    access_logs_enabled   = false
    security_group_ingress_rules = {
      corp = {
        ip_protocol = "tcp"
        from_port   = 443
        to_port     = 443
        cidr_ipv4   = "10.100.0.0/16"
        description = "HTTPS from corp network"
      }
    }
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.this) == 1
    error_message = "Explicit ingress rules should override the default two-rule set."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.this["corp"].cidr_ipv4 == "10.100.0.0/16"
    error_message = "Caller-supplied CIDR should be used verbatim."
  }
}

# ── WAF association happy path ────────────────────────────────────────────────

run "scenario_waf_association" {
  command = plan

  variables {
    name                = "waf-alb"
    internal            = false
    vpc_id              = "vpc-00000000"
    subnet_ids          = ["subnet-00000001", "subnet-00000002"]
    security_group_ids  = ["sg-00000001"]
    access_logs_enabled = false
    associate_waf       = true
    waf_acl_arn         = "arn:aws:wafv2:us-east-1:123456789012:regional/webacl/prod/abc"
  }

  assert {
    condition     = length(aws_wafv2_web_acl_association.this) == 1
    error_message = "WAF association should be planned when associate_waf and waf_acl_arn are set."
  }
}

# ── examples/minimal plans cleanly ────────────────────────────────────────────

run "example_minimal_plans_cleanly" {
  command = plan

  module {
    source = "./examples/minimal"
  }

  variables {
    name       = "example-min"
    vpc_id     = "vpc-00000000"
    subnet_ids = ["subnet-00000001", "subnet-00000002"]
  }
}

# ── examples/complete plans cleanly ───────────────────────────────────────────

run "example_complete_plans_cleanly" {
  command = plan

  module {
    source = "./examples/complete"
  }

  variables {
    name               = "example-full"
    vpc_id             = "vpc-00000000"
    subnet_ids         = ["subnet-00000001", "subnet-00000002"]
    security_group_ids = ["sg-00000001"]
    certificate_arn    = "arn:aws:acm:us-east-1:123456789012:certificate/example"
    access_logs_bucket = "example-alb-logs"
  }
}
