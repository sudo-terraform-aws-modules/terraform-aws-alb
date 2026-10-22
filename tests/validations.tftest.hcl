# Tests for variable validations and lifecycle preconditions.
# Uses the mock provider so no AWS credentials are required.
#
# Tests that are not about logging set access_logs_enabled = false so the
# logging precondition does not interfere with the check being tested.

mock_provider "aws" {}

# ── name validation ────────────────────────────────────────────────────────────

run "name_too_long_is_rejected" {
  command         = plan
  expect_failures = [var.name]

  variables {
    name               = "this-name-is-way-too-long-and-exceeds-32chars"
    internal           = true
    vpc_id             = "vpc-00000000"
    subnet_ids         = ["subnet-00000001", "subnet-00000002"]
    security_group_ids = ["sg-00000001"]
  }
}

run "name_with_internal_prefix_is_rejected" {
  command         = plan
  expect_failures = [var.name]

  variables {
    name               = "internal-my-alb"
    internal           = true
    vpc_id             = "vpc-00000000"
    subnet_ids         = ["subnet-00000001", "subnet-00000002"]
    security_group_ids = ["sg-00000001"]
  }
}

# ── security_group_ids validation ─────────────────────────────────────────────

run "empty_security_group_ids_is_rejected" {
  command         = plan
  expect_failures = [aws_lb.this]

  variables {
    name                = "test-alb"
    internal            = true
    vpc_id              = "vpc-00000000"
    subnet_ids          = ["subnet-00000001", "subnet-00000002"]
    security_group_ids  = []
    access_logs_enabled = false
  }
}

run "create_security_group_without_ids_is_accepted" {
  command = plan

  variables {
    name                  = "test-alb"
    internal              = true
    vpc_id                = "vpc-00000000"
    subnet_ids            = ["subnet-00000001", "subnet-00000002"]
    create_security_group = true
    access_logs_enabled   = false
  }

  assert {
    condition     = length(aws_security_group.this) == 1
    error_message = "Security group should be created when create_security_group = true."
  }
}

# ── desync_mitigation_mode validation ─────────────────────────────────────────

run "invalid_desync_mode_is_rejected" {
  command         = plan
  expect_failures = [var.desync_mitigation_mode]

  variables {
    name                   = "test-alb"
    internal               = true
    vpc_id                 = "vpc-00000000"
    subnet_ids             = ["subnet-00000001", "subnet-00000002"]
    security_group_ids     = ["sg-00000001"]
    desync_mitigation_mode = "invalid"
  }
}

# ── access logs enabled by default ────────────────────────────────────────────

run "alb_without_bucket_is_rejected_when_logs_enabled" {
  command         = plan
  expect_failures = [aws_lb.this]

  variables {
    name               = "test-alb"
    internal           = true
    vpc_id             = "vpc-00000000"
    subnet_ids         = ["subnet-00000001", "subnet-00000002"]
    security_group_ids = ["sg-00000001"]
    # access_logs_enabled defaults to true, no bucket provided -> precondition fails
  }
}

run "access_logs_opt_out_is_allowed" {
  command = plan

  variables {
    name                = "test-alb"
    internal            = true
    vpc_id              = "vpc-00000000"
    subnet_ids          = ["subnet-00000001", "subnet-00000002"]
    security_group_ids  = ["sg-00000001"]
    access_logs_enabled = false
  }

  assert {
    condition     = aws_lb.this[0].internal == true
    error_message = "ALB should be internal."
  }
}

# ── listener: redirect or target_group_key required ───────────────────────────

run "listener_with_no_action_is_rejected" {
  command         = plan
  expect_failures = [aws_lb_listener.this]

  variables {
    name                = "test-alb"
    internal            = true
    vpc_id              = "vpc-00000000"
    subnet_ids          = ["subnet-00000001", "subnet-00000002"]
    security_group_ids  = ["sg-00000001"]
    access_logs_enabled = false
    target_groups = {
      app = { port = 8080 }
    }
    listeners = {
      http = { port = 80 }
    }
  }
}

# ── listener: HTTPS requires certificate_arn ──────────────────────────────────

run "https_listener_without_cert_is_rejected" {
  command         = plan
  expect_failures = [aws_lb_listener.this]

  variables {
    name                = "test-alb"
    internal            = true
    vpc_id              = "vpc-00000000"
    subnet_ids          = ["subnet-00000001", "subnet-00000002"]
    security_group_ids  = ["sg-00000001"]
    access_logs_enabled = false
    target_groups = {
      app = { port = 8080 }
    }
    listeners = {
      https = {
        port             = 443
        protocol         = "HTTPS"
        target_group_key = "app"
      }
    }
  }
}

# ── listener: HTTP must redirect ──────────────────────────────────────────────

run "http_forward_without_flag_is_rejected" {
  command         = plan
  expect_failures = [aws_lb_listener.this]

  variables {
    name                = "test-alb"
    internal            = true
    vpc_id              = "vpc-00000000"
    subnet_ids          = ["subnet-00000001", "subnet-00000002"]
    security_group_ids  = ["sg-00000001"]
    access_logs_enabled = false
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
}

run "http_forward_with_allow_flag_is_accepted" {
  command = plan

  variables {
    name                 = "test-alb"
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
    condition     = aws_lb_listener.this["http"].port == 80
    error_message = "HTTP listener should be created on port 80."
  }
}

# ── listener: ssl_policy allowlist ────────────────────────────────────────────

run "insecure_ssl_policy_is_rejected" {
  command         = plan
  expect_failures = [aws_lb_listener.this]

  variables {
    name                = "test-alb"
    internal            = true
    vpc_id              = "vpc-00000000"
    subnet_ids          = ["subnet-00000001", "subnet-00000002"]
    security_group_ids  = ["sg-00000001"]
    access_logs_enabled = false
    target_groups = {
      app = { port = 8080 }
    }
    listeners = {
      https = {
        port             = 443
        protocol         = "HTTPS"
        certificate_arn  = "arn:aws:acm:us-east-1:123456789012:certificate/test"
        ssl_policy       = "ELBSecurityPolicy-2016-08"
        target_group_key = "app"
      }
    }
  }
}

run "secure_ssl_policy_is_accepted" {
  command = plan

  variables {
    name                = "test-alb"
    internal            = true
    vpc_id              = "vpc-00000000"
    subnet_ids          = ["subnet-00000001", "subnet-00000002"]
    security_group_ids  = ["sg-00000001"]
    access_logs_enabled = false
    target_groups = {
      app = { port = 8080 }
    }
    listeners = {
      https = {
        port             = 443
        protocol         = "HTTPS"
        certificate_arn  = "arn:aws:acm:us-east-1:123456789012:certificate/test"
        ssl_policy       = "ELBSecurityPolicy-TLS13-1-2-2021-06"
        target_group_key = "app"
      }
    }
  }

  assert {
    condition     = aws_lb_listener.this["https"].ssl_policy == "ELBSecurityPolicy-TLS13-1-2-2021-06"
    error_message = "Secure SSL policy should be accepted."
  }
}

# ── WAF: waf_acl_arn required when associate_waf = true ───────────────────────

run "associate_waf_without_arn_is_rejected" {
  command         = plan
  expect_failures = [aws_wafv2_web_acl_association.this]

  variables {
    name                = "test-alb"
    internal            = true
    vpc_id              = "vpc-00000000"
    subnet_ids          = ["subnet-00000001", "subnet-00000002"]
    security_group_ids  = ["sg-00000001"]
    access_logs_enabled = false
    associate_waf       = true
  }
}

# ── health check follows TG protocol ─────────────────────────────────────────

run "https_tg_gets_https_health_check" {
  command = plan

  variables {
    name                = "test-alb"
    internal            = true
    vpc_id              = "vpc-00000000"
    subnet_ids          = ["subnet-00000001", "subnet-00000002"]
    security_group_ids  = ["sg-00000001"]
    access_logs_enabled = false
    target_groups = {
      app = {
        port     = 8443
        protocol = "HTTPS"
        health_check = {
          path = "/health"
        }
      }
    }
  }

  assert {
    condition     = aws_lb_target_group.this["app"].health_check[0].protocol == "HTTPS"
    error_message = "Health check should inherit the TG protocol (HTTPS) when not explicitly set."
  }
}

# ── create = false produces no resources ──────────────────────────────────────

run "create_false_produces_no_resources" {
  command = plan

  variables {
    name               = "test-alb"
    internal           = true
    create             = false
    vpc_id             = "vpc-00000000"
    subnet_ids         = ["subnet-00000001", "subnet-00000002"]
    security_group_ids = ["sg-00000001"]
  }

  assert {
    condition     = length(aws_lb.this) == 0
    error_message = "No ALB should be created when create = false."
  }
}
