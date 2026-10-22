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
    Defaults to allowing HTTP (80) and HTTPS (443) from 0.0.0.0/0.

    Example (restrict to known CIDR):
      security_group_ingress_rules = {
        https_corp = {
          ip_protocol = "tcp"
          from_port   = 443
          to_port     = 443
          cidr_ipv4   = "10.0.0.0/8"
        }
      }
  EOT
  type = map(object({
    ip_protocol = string
    from_port   = optional(number, null)
    to_port     = optional(number, null)
    cidr_ipv4   = optional(string, null)
    cidr_ipv6   = optional(string, null)
    description = optional(string, "")
  }))
  default = {
    http = {
      ip_protocol = "tcp"
      from_port   = 80
      to_port     = 80
      cidr_ipv4   = "0.0.0.0/0"
      description = "Allow HTTP from anywhere"
    }
    https = {
      ip_protocol = "tcp"
      from_port   = 443
      to_port     = 443
      cidr_ipv4   = "0.0.0.0/0"
      description = "Allow HTTPS from anywhere"
    }
  }
}

variable "security_group_egress_rules" {
  description = <<-EOT
    Egress rules for the created security group. Only used when create_security_group = true.
    Defaults to allowing all outbound traffic. Restrict to VPC CIDR in production.

    Example (restrict egress to VPC):
      security_group_egress_rules = {
        vpc_only = {
          ip_protocol = "-1"
          cidr_ipv4   = "10.0.0.0/16"
        }
      }
  EOT
  type = map(object({
    ip_protocol = string
    from_port   = optional(number, null)
    to_port     = optional(number, null)
    cidr_ipv4   = optional(string, null)
    cidr_ipv6   = optional(string, null)
    description = optional(string, "")
  }))
  default = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
      description = "Allow all outbound traffic"
    }
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
  description = "Connection idle timeout in seconds."
  type        = number
  default     = 60
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
  description = "S3 key prefix for access logs. Defaults to the ALB name when null."
  type        = string
  default     = null
}

variable "connection_logs_bucket" {
  description = "S3 bucket name for ALB connection logs (connection-level events). Set to null to disable."
  type        = string
  default     = null
}

variable "connection_logs_prefix" {
  description = "S3 key prefix for connection logs. Defaults to the ALB name when null."
  type        = string
  default     = null
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
}

# ── Listeners ─────────────────────────────────────────────────────────────────

variable "listeners" {
  description = <<-EOT
    Map of listeners to create. Key is a logical name (e.g. "http", "https").

    Example:
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
  }))
  default = {}
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
  description = "Set to true to allow HTTP listeners to forward directly to targets without redirecting. Use only for internal ALBs serving service-to-service traffic."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to all resources."
  type        = map(string)
  default     = {}
}
