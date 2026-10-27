locals {
  # Allowlist of SSL policies that enforce TLS 1.2 or higher.
  # Policies not on this list are rejected by the listener precondition.
  # Update when AWS adds new policies: https://docs.aws.amazon.com/elasticloadbalancing/latest/application/describe-ssl-policies.html
  secure_ssl_policies = toset([
    "ELBSecurityPolicy-TLS13-1-2-2021-06",
    "ELBSecurityPolicy-TLS13-1-2-Res-2021-06",
    "ELBSecurityPolicy-TLS13-1-2-Ext1-2021-06",
    "ELBSecurityPolicy-TLS13-1-2-Ext2-2021-06",
    "ELBSecurityPolicy-TLS13-1-3-2021-06",
    "ELBSecurityPolicy-FS-1-2-Res-2020-10",
    "ELBSecurityPolicy-FS-1-2-2019-08",
    "ELBSecurityPolicy-FS-1-2-Res-2019-08",
    "ELBSecurityPolicy-TLS-1-2-Ext-2018-06",
    "ELBSecurityPolicy-TLS-1-2-2017-01",
  ])

  # Smart defaults for the module-created SG ingress:
  # - Internal ALB: HTTPS from VPC CIDR only (no 0.0.0.0/0 anti-pattern).
  # - Internet-facing: HTTP + HTTPS from 0.0.0.0/0 so browsers can reach it.
  # Only used when the caller leaves security_group_ingress_rules = null.
  default_ingress_rules = var.internal ? {
    https = {
      ip_protocol                  = "tcp"
      from_port                    = 443
      to_port                      = 443
      cidr_ipv4                    = try(data.aws_vpc.this[0].cidr_block, null)
      cidr_ipv6                    = null
      prefix_list_id               = null
      referenced_security_group_id = null
      description                  = "Allow HTTPS from VPC CIDR"
    }
    } : {
    http = {
      ip_protocol                  = "tcp"
      from_port                    = 80
      to_port                      = 80
      cidr_ipv4                    = "0.0.0.0/0"
      cidr_ipv6                    = null
      prefix_list_id               = null
      referenced_security_group_id = null
      description                  = "Allow HTTP from anywhere"
    }
    https = {
      ip_protocol                  = "tcp"
      from_port                    = 443
      to_port                      = 443
      cidr_ipv4                    = "0.0.0.0/0"
      cidr_ipv6                    = null
      prefix_list_id               = null
      referenced_security_group_id = null
      description                  = "Allow HTTPS from anywhere"
    }
  }

  # Default egress is always the VPC CIDR regardless of internal/internet-facing:
  # ALBs only forward to their registered targets, which live inside the VPC.
  # Egressing to 0.0.0.0/0 is unnecessary and gets flagged by security tooling.
  default_egress_rules = {
    vpc = {
      ip_protocol                  = "-1"
      from_port                    = null
      to_port                      = null
      cidr_ipv4                    = try(data.aws_vpc.this[0].cidr_block, null)
      cidr_ipv6                    = null
      prefix_list_id               = null
      referenced_security_group_id = null
      description                  = "Allow outbound within VPC CIDR"
    }
  }

  effective_ingress_rules = var.security_group_ingress_rules != null ? var.security_group_ingress_rules : local.default_ingress_rules
  effective_egress_rules  = var.security_group_egress_rules != null ? var.security_group_egress_rules : local.default_egress_rules
}

# VPC CIDR lookup, used to default the module-created SG rules.
# Only fetched when the SG is being created and we need a CIDR for the default
# (egress always needs it; ingress only needs it on internal ALBs).
data "aws_vpc" "this" {
  count = var.create && var.create_security_group && (
    var.security_group_egress_rules == null ||
    (var.internal && var.security_group_ingress_rules == null)
  ) ? 1 : 0
  id = var.vpc_id
}

# ── Security group (optional) ─────────────────────────────────────────────────

resource "aws_security_group" "this" {
  count = var.create && var.create_security_group ? 1 : 0

  # name_prefix (not name) so create_before_destroy replacements do not
  # collide with the existing SG.
  name_prefix = "${var.name}-alb-"
  description = coalesce(var.security_group_description, "Security group for ALB ${var.name}")
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-alb" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "this" {
  for_each = var.create && var.create_security_group ? local.effective_ingress_rules : {}

  security_group_id            = aws_security_group.this[0].id
  ip_protocol                  = each.value.ip_protocol
  from_port                    = each.value.from_port
  to_port                      = each.value.to_port
  cidr_ipv4                    = each.value.cidr_ipv4
  cidr_ipv6                    = each.value.cidr_ipv6
  prefix_list_id               = each.value.prefix_list_id
  referenced_security_group_id = each.value.referenced_security_group_id
  description                  = each.value.description

  tags = var.tags
}

resource "aws_vpc_security_group_egress_rule" "this" {
  for_each = var.create && var.create_security_group ? local.effective_egress_rules : {}

  security_group_id            = aws_security_group.this[0].id
  ip_protocol                  = each.value.ip_protocol
  from_port                    = each.value.from_port
  to_port                      = each.value.to_port
  cidr_ipv4                    = each.value.cidr_ipv4
  cidr_ipv6                    = each.value.cidr_ipv6
  prefix_list_id               = each.value.prefix_list_id
  referenced_security_group_id = each.value.referenced_security_group_id
  description                  = each.value.description

  tags = var.tags
}

# ── ALB ───────────────────────────────────────────────────────────────────────

resource "aws_lb" "this" {
  count = var.create ? 1 : 0

  name               = var.name
  internal           = var.internal
  load_balancer_type = "application"
  ip_address_type    = var.ip_address_type
  subnets            = var.subnet_ids

  # Merge the module-created SG (if any) with caller-supplied IDs.
  security_groups = concat(
    [for sg in aws_security_group.this : sg.id],
    var.security_group_ids,
  )

  enable_deletion_protection = var.deletion_protection
  idle_timeout               = var.idle_timeout
  enable_http2               = var.enable_http2
  preserve_host_header       = var.preserve_host_header
  drop_invalid_header_fields = true
  enable_waf_fail_open       = var.enable_waf_fail_open
  desync_mitigation_mode     = var.desync_mitigation_mode

  dynamic "access_logs" {
    for_each = var.access_logs_enabled && var.access_logs_bucket != null ? [1] : []
    content {
      bucket  = var.access_logs_bucket
      prefix  = coalesce(var.access_logs_prefix, var.name)
      enabled = true
    }
  }

  dynamic "connection_logs" {
    for_each = var.connection_logs_bucket != null ? [1] : []
    content {
      bucket  = var.connection_logs_bucket
      prefix  = coalesce(var.connection_logs_prefix, var.name)
      enabled = true
    }
  }

  tags = var.tags

  lifecycle {
    precondition {
      condition     = !var.access_logs_enabled || var.access_logs_bucket != null
      error_message = "access_logs_bucket is required when access_logs_enabled is true. To opt out of logging, set access_logs_enabled = false."
    }
    precondition {
      condition     = var.create_security_group || length(var.security_group_ids) > 0
      error_message = "Either create_security_group = true or at least one security_group_id must be provided."
    }
  }
}

# ── Target groups ─────────────────────────────────────────────────────────────

resource "aws_lb_target_group" "this" {
  for_each = var.create ? var.target_groups : {}

  # AWS caps name_prefix at 6 characters for target groups.
  name_prefix = substr(each.key, 0, 6)
  port        = each.value.port
  protocol    = upper(each.value.protocol)
  target_type = each.value.target_type
  vpc_id      = var.vpc_id

  deregistration_delay = each.value.deregistration_delay
  slow_start           = each.value.slow_start

  health_check {
    enabled             = true
    protocol            = upper(coalesce(try(each.value.health_check.protocol, null), each.value.protocol))
    port                = try(each.value.health_check.port, "traffic-port")
    path                = try(each.value.health_check.path, "/")
    matcher             = try(each.value.health_check.matcher, "200-299")
    healthy_threshold   = try(each.value.health_check.healthy_threshold, 3)
    unhealthy_threshold = try(each.value.health_check.unhealthy_threshold, 3)
    interval            = try(each.value.health_check.interval, 30)
    timeout             = try(each.value.health_check.timeout, 5)
  }

  dynamic "stickiness" {
    for_each = each.value.stickiness != null ? [each.value.stickiness] : []
    content {
      type            = stickiness.value.type
      cookie_duration = stickiness.value.cookie_duration
      cookie_name     = stickiness.value.cookie_name
      enabled         = stickiness.value.enabled
    }
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

# ── Listeners ─────────────────────────────────────────────────────────────────

resource "aws_lb_listener" "this" {
  for_each = var.create ? var.listeners : {}

  load_balancer_arn = aws_lb.this[0].arn
  port              = each.value.port
  protocol          = upper(each.value.protocol)
  ssl_policy        = upper(each.value.protocol) == "HTTPS" ? each.value.ssl_policy : null
  certificate_arn   = upper(each.value.protocol) == "HTTPS" ? each.value.certificate_arn : null

  dynamic "default_action" {
    for_each = each.value.redirect != null ? [each.value.redirect] : []
    content {
      type = "redirect"
      redirect {
        port        = default_action.value.port
        protocol    = default_action.value.protocol
        status_code = default_action.value.status_code
      }
    }
  }

  dynamic "default_action" {
    for_each = each.value.redirect == null ? [1] : []
    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.this[each.value.target_group_key].arn
    }
  }

  dynamic "mutual_authentication" {
    for_each = each.value.mutual_authentication != null ? [each.value.mutual_authentication] : []
    content {
      mode                             = mutual_authentication.value.mode
      trust_store_arn                  = mutual_authentication.value.mode == "verify" ? mutual_authentication.value.trust_store_arn : null
      advertise_trust_store_ca_names   = mutual_authentication.value.mode == "verify" ? mutual_authentication.value.advertise_trust_store_ca_names : null
      ignore_client_certificate_expiry = mutual_authentication.value.mode == "verify" ? mutual_authentication.value.ignore_client_certificate_expiry : null
    }
  }

  tags = var.tags

  lifecycle {
    precondition {
      condition     = each.value.redirect != null || each.value.target_group_key != null
      error_message = "Listener '${each.key}' must specify either 'redirect' or 'target_group_key'."
    }
    precondition {
      condition     = each.value.target_group_key == null ? true : contains(keys(var.target_groups), each.value.target_group_key)
      error_message = "Listener '${each.key}' references target_group_key '${coalesce(each.value.target_group_key, "<null>")}' which is not defined in var.target_groups."
    }
    precondition {
      condition     = upper(each.value.protocol) != "HTTPS" || each.value.certificate_arn != null
      error_message = "HTTPS listener '${each.key}' requires 'certificate_arn' to be set."
    }
    precondition {
      condition     = upper(each.value.protocol) != "HTTP" || each.value.redirect != null || (var.allow_plaintext_http && var.internal)
      error_message = "HTTP listener '${each.key}' must use 'redirect' to enforce HTTPS. 'allow_plaintext_http = true' is only honoured when 'internal = true'."
    }
    precondition {
      condition     = upper(each.value.protocol) != "HTTPS" || contains(local.secure_ssl_policies, each.value.ssl_policy)
      error_message = "HTTPS listener '${each.key}': ssl_policy '${each.value.ssl_policy}' is not in the approved TLS 1.2+ list. Use ELBSecurityPolicy-TLS13-1-2-2021-06 or another approved policy."
    }
    precondition {
      condition     = each.value.mutual_authentication == null ? true : upper(each.value.protocol) == "HTTPS"
      error_message = "Listener '${each.key}': mutual_authentication is only valid on HTTPS listeners. Set protocol = \"HTTPS\" or remove the mutual_authentication block."
    }
    precondition {
      condition     = each.value.mutual_authentication == null ? true : (each.value.mutual_authentication.mode != "verify" ? true : each.value.mutual_authentication.trust_store_arn != null)
      error_message = "Listener '${each.key}': mutual_authentication.trust_store_arn is required when mutual_authentication.mode = \"verify\"."
    }
  }
}

# ── Listener rules ────────────────────────────────────────────────────────────

resource "aws_lb_listener_rule" "this" {
  for_each = var.create ? var.listener_rules : {}

  listener_arn = aws_lb_listener.this[each.value.listener_key].arn
  priority     = each.value.priority

  dynamic "condition" {
    for_each = each.value.path_pattern != null ? [each.value.path_pattern] : []
    content {
      path_pattern {
        values = condition.value
      }
    }
  }

  dynamic "condition" {
    for_each = each.value.host_header != null ? [each.value.host_header] : []
    content {
      host_header {
        values = condition.value
      }
    }
  }

  dynamic "condition" {
    for_each = each.value.http_header != null ? [each.value.http_header] : []
    content {
      http_header {
        http_header_name = condition.value.name
        values           = condition.value.values
      }
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[each.value.target_group_key].arn
  }

  tags = var.tags

  lifecycle {
    precondition {
      condition     = contains(keys(var.listeners), each.value.listener_key)
      error_message = "Listener rule '${each.key}' references listener_key '${each.value.listener_key}' which is not defined in var.listeners."
    }
    precondition {
      condition     = contains(keys(var.target_groups), each.value.target_group_key)
      error_message = "Listener rule '${each.key}' references target_group_key '${each.value.target_group_key}' which is not defined in var.target_groups."
    }
    precondition {
      condition     = each.value.path_pattern != null || each.value.host_header != null || each.value.http_header != null
      error_message = "Listener rule '${each.key}' must specify at least one condition (path_pattern, host_header, or http_header). An ALB rule with no conditions is rejected by AWS at apply time."
    }
  }
}

# ── WAF ───────────────────────────────────────────────────────────────────────

resource "aws_wafv2_web_acl_association" "this" {
  count = var.create && var.associate_waf ? 1 : 0

  resource_arn = aws_lb.this[0].arn
  web_acl_arn  = var.waf_acl_arn

  lifecycle {
    precondition {
      condition     = var.waf_acl_arn != null
      error_message = "waf_acl_arn must be set when associate_waf is true."
    }
  }
}
