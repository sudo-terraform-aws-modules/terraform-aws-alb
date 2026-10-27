variable "create" {
  description = "Controls whether the ALB and associated resources are created."
  type        = bool
  default     = true
}

variable "name" {
  description = "Name of the ALB. Also used as a prefix for target group names."
  type        = string
  nullable    = false

  validation {
    condition     = length(var.name) <= 32 && !startswith(var.name, "internal-")
    error_message = "ALB name must be 32 characters or fewer and cannot start with 'internal-'."
  }
}

variable "internal" {
  description = "Set to true for an internal ALB, false for internet-facing. Required - must be set explicitly."
  type        = bool
  nullable    = false
}

variable "vpc_id" {
  description = "VPC ID where target groups will be created."
  type        = string
  nullable    = false
}

variable "subnet_ids" {
  description = "List of subnet IDs. Use public subnets for internet-facing, private for internal."
  type        = list(string)
  nullable    = false
}

variable "ip_address_type" {
  description = "IP address type for the ALB. Valid values: ipv4, dualstack, dualstack-without-public-ipv4."
  type        = string
  default     = "ipv4"

  validation {
    condition     = contains(["ipv4", "dualstack", "dualstack-without-public-ipv4"], var.ip_address_type)
    error_message = "ip_address_type must be one of: ipv4, dualstack, dualstack-without-public-ipv4."
  }
}

# ── Security groups ────────────────────────────────────────────────────────────

variable "create_security_group" {
  description = "Set to true to create and manage a security group for the ALB. When false, at least one security_group_id must be provided."
  type        = bool
  default     = false
}

variable "security_group_description" {
  description = "Description for the created security group. Defaults to 'Security group for ALB <name>'."
  type        = string
  default     = null
}

variable "security_group_ingress_rules" {
  description = <<-EOT
    Ingress rules for the created security group. Only used when create_security_group = true.
    When null, the module picks a safe default based on internal:
      - internal = true: HTTPS (443) from the VPC CIDR only (looked up via data source).
      - internal = false: HTTP (80) and HTTPS (443) from 0.0.0.0/0 so browsers can reach the ALB.
    Exactly one source must be set per rule: cidr_ipv4, cidr_ipv6, prefix_list_id, or referenced_security_group_id.

    Example (restrict to a known CIDR):
      security_group_ingress_rules = {
        https_corp = {
          ip_protocol = "tcp"
          from_port   = 443
          to_port     = 443
          cidr_ipv4   = "10.0.0.0/8"
        }
      }

    Example (allow only a specific client security group):
      security_group_ingress_rules = {
        https_from_app = {
          ip_protocol                  = "tcp"
          from_port                    = 443
          to_port                      = 443
          referenced_security_group_id = aws_security_group.app.id
        }
      }
  EOT
  type = map(object({
    ip_protocol                  = string
    from_port                    = optional(number, null)
    to_port                      = optional(number, null)
    cidr_ipv4                    = optional(string, null)
    cidr_ipv6                    = optional(string, null)
    prefix_list_id               = optional(string, null)
    referenced_security_group_id = optional(string, null)
    description                  = optional(string, "")
  }))
  default = null

  validation {
    condition = var.security_group_ingress_rules == null ? true : alltrue([
      for k, v in var.security_group_ingress_rules :
      length(compact([v.cidr_ipv4, v.cidr_ipv6, v.prefix_list_id, v.referenced_security_group_id])) == 1
    ])
    error_message = "Each security_group_ingress_rules entry must set exactly one of: cidr_ipv4, cidr_ipv6, prefix_list_id, referenced_security_group_id."
  }
}

variable "security_group_egress_rules" {
  description = <<-EOT
    Egress rules for the created security group. Only used when create_security_group = true.
    When null, the module defaults to allowing all protocols to the VPC CIDR
    (looked up via data source). ALBs only forward to in-VPC targets, so this
    is a safer default than 0.0.0.0/0.
    Exactly one destination must be set per rule: cidr_ipv4, cidr_ipv6, prefix_list_id, or referenced_security_group_id.

    Example (restrict egress to a subset of the VPC):
      security_group_egress_rules = {
        vpc_only = {
          ip_protocol = "-1"
          cidr_ipv4   = "10.0.0.0/16"
        }
      }

    Example (allow egress only to a specific target security group):
      security_group_egress_rules = {
        to_app = {
          ip_protocol                  = "tcp"
          from_port                    = 8080
          to_port                      = 8080
          referenced_security_group_id = aws_security_group.app.id
        }
      }
  EOT
  type = map(object({
    ip_protocol                  = string
    from_port                    = optional(number, null)
    to_port                      = optional(number, null)
    cidr_ipv4                    = optional(string, null)
    cidr_ipv6                    = optional(string, null)
    prefix_list_id               = optional(string, null)
    referenced_security_group_id = optional(string, null)
    description                  = optional(string, "")
  }))
  default = null

  validation {
    condition = var.security_group_egress_rules == null ? true : alltrue([
      for k, v in var.security_group_egress_rules :
      length(compact([v.cidr_ipv4, v.cidr_ipv6, v.prefix_list_id, v.referenced_security_group_id])) == 1
    ])
    error_message = "Each security_group_egress_rules entry must set exactly one of: cidr_ipv4, cidr_ipv6, prefix_list_id, referenced_security_group_id."
  }
}

variable "security_group_ids" {
  description = "List of additional security group IDs to assign to the ALB. At least one is required when create_security_group is false."
  type        = list(string)
  nullable    = false
  default     = []
}

# ── ALB behaviour ──────────────────────────────────────────────────────────────

variable "deletion_protection" {
  description = "If true, the ALB cannot be deleted via the AWS API. Defaults to true for production safety."
  type        = bool
  default     = true
}

variable "idle_timeout" {
  description = "Connection idle timeout in seconds. Must be between 1 and 4000 (AWS cap)."
  type        = number
  default     = 60

  validation {
    condition     = var.idle_timeout >= 1 && var.idle_timeout <= 4000
    error_message = "idle_timeout must be between 1 and 4000 seconds."
  }
}

variable "enable_http2" {
  description = "Whether HTTP/2 is enabled."
  type        = bool
  default     = true
}

variable "preserve_host_header" {
  description = "Whether to preserve the client request host header on requests to the target."
  type        = bool
  default     = false
}

variable "enable_waf_fail_open" {
  description = "Whether to allow the ALB to route requests to targets if WAF is unavailable. Defaults to false."
  type        = bool
  default     = false
}

variable "desync_mitigation_mode" {
  description = "How the ALB handles requests that might pose a security risk due to HTTP desync. Valid values: monitor, defensive, strictest."
  type        = string
  default     = "defensive"

  validation {
    condition     = contains(["monitor", "defensive", "strictest"], var.desync_mitigation_mode)
    error_message = "desync_mitigation_mode must be one of: monitor, defensive, strictest."
  }
}

# ── Logging ────────────────────────────────────────────────────────────────────

variable "access_logs_enabled" {
  description = "Whether to enable ALB access logs. Defaults to true. When true, access_logs_bucket must also be set. Set to false only when you have an explicit reason to disable logging."
  type        = bool
  default     = true
}

variable "access_logs_bucket" {
  description = "S3 bucket name for ALB access logs. Required when access_logs_enabled is true. The bucket must have the ELB service account allowed to write."
  type        = string
  default     = null
}

variable "access_logs_prefix" {
  description = "S3 key prefix for access logs. Defaults to the ALB name when null. Must not start or end with '/'."
  type        = string
  default     = null

  validation {
    condition     = var.access_logs_prefix == null ? true : (!startswith(var.access_logs_prefix, "/") && !endswith(var.access_logs_prefix, "/"))
    error_message = "access_logs_prefix must not start or end with '/' - it is used as the S3 key prefix verbatim."
  }
}

variable "connection_logs_bucket" {
  description = "S3 bucket name for ALB connection logs (connection-level events). Set to null to disable."
  type        = string
  default     = null
}

variable "connection_logs_prefix" {
  description = "S3 key prefix for connection logs. Defaults to the ALB name when null. Must not start or end with '/'."
  type        = string
  default     = null

  validation {
    condition     = var.connection_logs_prefix == null ? true : (!startswith(var.connection_logs_prefix, "/") && !endswith(var.connection_logs_prefix, "/"))
    error_message = "connection_logs_prefix must not start or end with '/' - it is used as the S3 key prefix verbatim."
  }
}

# ── Target groups ─────────────────────────────────────────────────────────────

variable "target_groups" {
  description = <<-EOT
    Map of target groups to create. Key is a logical name referenced by listeners and rules.

    Example:
      target_groups = {
        app = {
          port     = 8080
          protocol = "HTTP"
          health_check = {
            path    = "/health"
            matcher = "200"
          }
        }
      }
  EOT
  type = map(object({
    port                 = number
    protocol             = optional(string, "HTTP")
    target_type          = optional(string, "ip")
    deregistration_delay = optional(number, 30)
    slow_start           = optional(number, 0)
    health_check = optional(object({
      protocol            = optional(string, null)
      port                = optional(string, "traffic-port")
      path                = optional(string, "/")
      matcher             = optional(string, "200-299")
      healthy_threshold   = optional(number, 3)
      unhealthy_threshold = optional(number, 3)
      interval            = optional(number, 30)
      timeout             = optional(number, 5)
    }), null)
    stickiness = optional(object({
      type            = optional(string, "lb_cookie")
      cookie_duration = optional(number, 86400)
      cookie_name     = optional(string, null)
      enabled         = optional(bool, true)
    }), null)
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.target_groups) : can(regex("^[a-z0-9][-a-z0-9]*$", substr(k, 0, 6)))])
    error_message = "target_groups keys: the first 6 characters are used as the AWS target group name prefix and must be lowercase alphanumeric, optionally with hyphens, starting with an alphanumeric character."
  }

  validation {
    condition     = alltrue([for k, v in var.target_groups : v.port >= 1 && v.port <= 65535])
    error_message = "All target_groups ports must be between 1 and 65535."
  }

  validation {
    condition     = alltrue([for k, v in var.target_groups : contains(["HTTP", "HTTPS", "HTTP2", "GRPC"], upper(v.protocol))])
    error_message = "target_groups protocol must be HTTP, HTTPS, HTTP2, or GRPC."
  }

  validation {
    condition     = alltrue([for k, v in var.target_groups : contains(["instance", "ip", "lambda", "alb"], v.target_type)])
    error_message = "target_groups target_type must be instance, ip, lambda, or alb."
  }

  validation {
    condition     = alltrue([for k, v in var.target_groups : v.stickiness == null ? true : contains(["lb_cookie", "app_cookie", "source_ip"], v.stickiness.type)])
    error_message = "target_groups stickiness.type must be lb_cookie, app_cookie, or source_ip."
  }

  validation {
    condition     = alltrue([for k, v in var.target_groups : v.stickiness == null ? true : !(v.stickiness.type == "lb_cookie" && v.stickiness.cookie_name != null)])
    error_message = "target_groups stickiness.cookie_name is only valid when stickiness.type = app_cookie, not lb_cookie."
  }

  validation {
    condition     = alltrue([for k, v in var.target_groups : v.stickiness == null ? true : (v.stickiness.cookie_duration == null ? true : (v.stickiness.cookie_duration >= 1 && v.stickiness.cookie_duration <= 604800))])
    error_message = "target_groups stickiness.cookie_duration must be between 1 and 604800 seconds (7 days)."
  }
}

# ── Listeners ─────────────────────────────────────────────────────────────────

variable "listeners" {
  description = <<-EOT
    Map of listeners to create. Key is a logical name (e.g. "http", "https").

    Example (HTTPS with mutual TLS / client certificate authentication):
      listeners = {
        https = {
          port             = 443
          protocol         = "HTTPS"
          certificate_arn  = module.acm.arn
          target_group_key = "app"
          mutual_authentication = {
            mode            = "verify"
            trust_store_arn = aws_lb_trust_store.corp.arn
          }
        }
      }

    Example (HTTP to HTTPS redirect + HTTPS forwarding):
      listeners = {
        http = {
          port     = 80
          redirect = { port = "443", protocol = "HTTPS", status_code = "HTTP_301" }
        }
        https = {
          port             = 443
          protocol         = "HTTPS"
          certificate_arn  = module.acm.arn
          target_group_key = "app"
        }
      }
  EOT
  type = map(object({
    port             = number
    protocol         = optional(string, "HTTP")
    target_group_key = optional(string, null)
    certificate_arn  = optional(string, null)
    ssl_policy       = optional(string, "ELBSecurityPolicy-TLS13-1-2-2021-06")
    redirect = optional(object({
      port        = optional(string, "443")
      protocol    = optional(string, "HTTPS")
      status_code = optional(string, "HTTP_301")
    }), null)
    mutual_authentication = optional(object({
      mode                             = string
      trust_store_arn                  = optional(string, null)
      advertise_trust_store_ca_names   = optional(string, null)
      ignore_client_certificate_expiry = optional(bool, false)
    }), null)
  }))
  default = {}

  validation {
    condition     = alltrue([for k, v in var.listeners : v.port >= 1 && v.port <= 65535])
    error_message = "All listener ports must be between 1 and 65535."
  }

  validation {
    condition     = alltrue([for k, v in var.listeners : contains(["HTTP", "HTTPS"], upper(v.protocol))])
    error_message = "listeners protocol must be HTTP or HTTPS."
  }

  validation {
    condition     = alltrue([for k, v in var.listeners : v.redirect == null ? true : contains(["HTTP_301", "HTTP_302"], v.redirect.status_code)])
    error_message = "listeners redirect.status_code must be HTTP_301 or HTTP_302."
  }

  validation {
    condition     = alltrue([for k, v in var.listeners : v.mutual_authentication == null ? true : contains(["off", "passthrough", "verify"], v.mutual_authentication.mode)])
    error_message = "listeners mutual_authentication.mode must be off, passthrough, or verify."
  }

  validation {
    condition = alltrue([
      for k, v in var.listeners :
      v.mutual_authentication == null ? true : (
        v.mutual_authentication.advertise_trust_store_ca_names == null ? true : contains(["off", "on"], v.mutual_authentication.advertise_trust_store_ca_names)
      )
    ])
    error_message = "listeners mutual_authentication.advertise_trust_store_ca_names must be off or on when set."
  }
}

variable "listener_rules" {
  description = <<-EOT
    Map of listener rules for path- and host-based routing. Key is a logical name.

    Example:
      listener_rules = {
        api = {
          listener_key     = "https"
          target_group_key = "api"
          priority         = 10
          path_pattern     = ["/api/*"]
        }
      }
  EOT
  type = map(object({
    listener_key     = string
    target_group_key = string
    priority         = optional(number, null)
    path_pattern     = optional(list(string), null)
    host_header      = optional(list(string), null)
    http_header = optional(object({
      name   = string
      values = list(string)
    }), null)
  }))
  default = {}

  validation {
    condition     = alltrue([for k, v in var.listener_rules : v.priority == null ? true : (v.priority >= 1 && v.priority <= 50000)])
    error_message = "listener_rules priority must be between 1 and 50000 when set."
  }
}

# ── WAF ───────────────────────────────────────────────────────────────────────

variable "waf_acl_arn" {
  description = "ARN of a WAFv2 web ACL to associate with the ALB. Set associate_waf = true to attach it."
  type        = string
  default     = null
}

variable "associate_waf" {
  description = "Set to true to associate the waf_acl_arn WAF WebACL with the ALB. Using a bool avoids plan-time errors when waf_acl_arn is a computed value created in the same apply."
  type        = bool
  default     = false
}

# ── HTTP policy ───────────────────────────────────────────────────────────────

variable "allow_plaintext_http" {
  description = "Allow HTTP listeners to forward directly to targets without redirecting. Only honoured when 'internal = true' - the listener precondition rejects plaintext HTTP on internet-facing ALBs."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to all resources."
  type        = map(string)
  default     = {}
}
