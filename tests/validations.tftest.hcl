# Tests for variable validations and lifecycle preconditions.
# Uses the mock provider so no AWS credentials are required.
#
# Tests that are not about logging set access_logs_enabled = false so the
# logging precondition does not interfere with the check being tested.

mock_provider "aws" {
  mock_data "aws_vpc" {
    defaults = {
      cidr_block = "10.0.0.0/16"
    }
  }
}

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

# ── TG name_prefix stays within the 6-char AWS cap ────────────────────────────

run "tg_name_prefix_is_capped_at_six_chars" {
  command = plan

  variables {
    name                = "test-alb"
    internal            = true
    vpc_id              = "vpc-00000000"
    subnet_ids          = ["subnet-00000001", "subnet-00000002"]
    security_group_ids  = ["sg-00000001"]
    access_logs_enabled = false
    target_groups = {
      "very-long-target-group-key" = { port = 8080 }
    }
  }

  assert {
    condition     = length(aws_lb_target_group.this["very-long-target-group-key"].name_prefix) <= 6
    error_message = "Target group name_prefix must be <= 6 characters (AWS cap)."
  }
}

# ── SG uses name_prefix so create_before_destroy replacements do not collide ──

run "sg_uses_name_prefix" {
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
    condition     = aws_security_group.this[0].name_prefix == "test-alb-alb-"
    error_message = "Security group should use name_prefix (not a fixed name) to support create_before_destroy."
  }
}

# ── WAF association succeeds when ARN provided ────────────────────────────────

run "associate_waf_with_arn_is_accepted" {
  command = plan

  variables {
    name                = "test-alb"
    internal            = true
    vpc_id              = "vpc-00000000"
    subnet_ids          = ["subnet-00000001", "subnet-00000002"]
    security_group_ids  = ["sg-00000001"]
    access_logs_enabled = false
    associate_waf       = true
    waf_acl_arn         = "arn:aws:wafv2:us-east-1:123456789012:regional/webacl/test/abc"
  }

  assert {
    condition     = length(aws_wafv2_web_acl_association.this) == 1
    error_message = "WAF association should be created when associate_waf = true and waf_acl_arn is set."
  }
}

# ── allow_plaintext_http only honoured when internal = true ───────────────────

run "plaintext_http_on_internet_facing_is_rejected" {
  command         = plan
  expect_failures = [aws_lb_listener.this]

  variables {
    name                 = "test-alb"
    internal             = false
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
}

# ── Extended TLS 1.2+ allowlist accepts Res / Ext1 / Ext2 variants ────────────

run "tls13_12_res_policy_is_accepted" {
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
        ssl_policy       = "ELBSecurityPolicy-TLS13-1-2-Res-2021-06"
        target_group_key = "app"
      }
    }
  }

  assert {
    condition     = aws_lb_listener.this["https"].ssl_policy == "ELBSecurityPolicy-TLS13-1-2-Res-2021-06"
    error_message = "The TLS13-1-2-Res 2021-06 policy should be accepted by the allowlist."
  }
}

# ── listener targets missing TG key is rejected ───────────────────────────────

run "listener_with_missing_target_group_key_is_rejected" {
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
        target_group_key = "ghost"
      }
    }
  }
}

# ── listener rule referencing missing listener_key is rejected ────────────────

run "listener_rule_with_missing_listener_key_is_rejected" {
  command         = plan
  expect_failures = [aws_lb_listener_rule.this]

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
        target_group_key = "app"
      }
    }
    listener_rules = {
      bad = {
        listener_key     = "ghost"
        target_group_key = "app"
        path_pattern     = ["/x"]
      }
    }
  }
}

# ── listener rule referencing missing target_group_key is rejected ────────────

run "listener_rule_with_missing_target_group_key_is_rejected" {
  command         = plan
  expect_failures = [aws_lb_listener_rule.this]

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
        target_group_key = "app"
      }
    }
    listener_rules = {
      bad = {
        listener_key     = "https"
        target_group_key = "ghost"
        path_pattern     = ["/x"]
      }
    }
  }
}

# ── listener rule with no conditions is rejected ──────────────────────────────

run "listener_rule_without_conditions_is_rejected" {
  command         = plan
  expect_failures = [aws_lb_listener_rule.this]

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
        target_group_key = "app"
      }
    }
    listener_rules = {
      bad = {
        listener_key     = "https"
        target_group_key = "app"
      }
    }
  }
}

# ── variable validations ──────────────────────────────────────────────────────

run "idle_timeout_out_of_range_is_rejected" {
  command         = plan
  expect_failures = [var.idle_timeout]

  variables {
    name               = "test-alb"
    internal           = true
    vpc_id             = "vpc-00000000"
    subnet_ids         = ["subnet-00000001", "subnet-00000002"]
    security_group_ids = ["sg-00000001"]
    idle_timeout       = 5000
  }
}

run "listener_port_out_of_range_is_rejected" {
  command         = plan
  expect_failures = [var.listeners]

  variables {
    name                = "test-alb"
    internal            = true
    vpc_id              = "vpc-00000000"
    subnet_ids          = ["subnet-00000001", "subnet-00000002"]
    security_group_ids  = ["sg-00000001"]
    access_logs_enabled = false
    listeners = {
      bad = {
        port     = 99999
        redirect = { port = "443", protocol = "HTTPS", status_code = "HTTP_301" }
      }
    }
  }
}

run "tg_cookie_name_with_lb_cookie_is_rejected" {
  command         = plan
  expect_failures = [var.target_groups]

  variables {
    name                = "test-alb"
    internal            = true
    vpc_id              = "vpc-00000000"
    subnet_ids          = ["subnet-00000001", "subnet-00000002"]
    security_group_ids  = ["sg-00000001"]
    access_logs_enabled = false
    target_groups = {
      app = {
        port = 8080
        stickiness = {
          type        = "lb_cookie"
          cookie_name = "SESSION"
        }
      }
    }
  }
}

run "tg_uppercase_key_is_rejected" {
  command         = plan
  expect_failures = [var.target_groups]

  variables {
    name                = "test-alb"
    internal            = true
    vpc_id              = "vpc-00000000"
    subnet_ids          = ["subnet-00000001", "subnet-00000002"]
    security_group_ids  = ["sg-00000001"]
    access_logs_enabled = false
    target_groups = {
      "App-Pool" = { port = 8080 }
    }
  }
}

run "access_logs_prefix_with_leading_slash_is_rejected" {
  command         = plan
  expect_failures = [var.access_logs_prefix]

  variables {
    name               = "test-alb"
    internal           = true
    vpc_id             = "vpc-00000000"
    subnet_ids         = ["subnet-00000001", "subnet-00000002"]
    security_group_ids = ["sg-00000001"]
    access_logs_bucket = "my-bucket"
    access_logs_prefix = "/logs"
  }
}

# ── mTLS: verify mode requires trust_store_arn ────────────────────────────────

run "mtls_verify_without_trust_store_is_rejected" {
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
        target_group_key = "app"
        mutual_authentication = {
          mode = "verify"
        }
      }
    }
  }
}

# ── mTLS: only valid on HTTPS listeners ───────────────────────────────────────

run "mtls_on_http_listener_is_rejected" {
  command         = plan
  expect_failures = [aws_lb_listener.this]

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
        mutual_authentication = {
          mode            = "verify"
          trust_store_arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:truststore/test/abc"
        }
      }
    }
  }
}

# ── mTLS: invalid mode is rejected ────────────────────────────────────────────

run "mtls_invalid_mode_is_rejected" {
  command         = plan
  expect_failures = [var.listeners]

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
        target_group_key = "app"
        mutual_authentication = {
          mode = "always"
        }
      }
    }
  }
}

# ── mTLS: verify mode with trust store is accepted ────────────────────────────

run "mtls_verify_with_trust_store_is_accepted" {
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
        target_group_key = "app"
        mutual_authentication = {
          mode            = "verify"
          trust_store_arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:truststore/test/abc"
        }
      }
    }
  }

  assert {
    condition     = aws_lb_listener.this["https"].mutual_authentication[0].mode == "verify"
    error_message = "mTLS verify mode should plan successfully when trust_store_arn is set."
  }
}

# ── mTLS: passthrough mode is accepted ────────────────────────────────────────

run "mtls_passthrough_mode_is_accepted" {
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
        target_group_key = "app"
        mutual_authentication = {
          mode = "passthrough"
        }
      }
    }
  }

  assert {
    condition     = aws_lb_listener.this["https"].mutual_authentication[0].mode == "passthrough"
    error_message = "mTLS passthrough mode should plan successfully without a trust store."
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
