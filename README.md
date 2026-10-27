# terraform-aws-alb

[![CI](https://github.com/sudo-terraform-aws-modules/terraform-aws-alb/actions/workflows/main.yml/badge.svg)](https://github.com/sudo-terraform-aws-modules/terraform-aws-alb/actions/workflows/main.yml)
[![Terraform](https://img.shields.io/badge/terraform-%3E%3D%201.3.0-blue)](https://developer.hashicorp.com/terraform/downloads)
[![AWS Provider](https://img.shields.io/badge/aws-%3E%3D%206.0.0-orange)](https://registry.terraform.io/providers/hashicorp/aws/latest)
[![License](https://img.shields.io/badge/license-Apache%202.0-green)](./LICENSE)

<img width="600" alt="SUDO x AWS" src="https://github.com/user-attachments/assets/f7044ff9-afce-4811-91c6-2f3c95635abb" />

A Terraform module for AWS Application Load Balancer (ALB). Creates and manages ALBs, target groups, HTTP/HTTPS listeners, and listener rules with path- and host-based routing. Designed for ECS Fargate services using IP-based target groups.

## Default behaviour

Out of the box the module ships with production-safe defaults so a minimal configuration lands on the right side of security and operability:

- `deletion_protection = true` - the ALB cannot be deleted via the API without an explicit opt-out.
- `drop_invalid_header_fields = true` - hard-coded, never configurable.
- `access_logs_enabled = true` - callers must provide `access_logs_bucket` or explicitly disable logging.
- `enable_waf_fail_open = false` - requests are dropped if the WAF is unavailable.
- `desync_mitigation_mode = "defensive"` - mitigates HTTP desync attacks.
- `ssl_policy` on HTTPS listeners is validated against an allowlist of TLS 1.2+ policies; weaker policies are rejected at plan time.
- HTTP listeners must `redirect` to HTTPS; plain HTTP forwarding to targets is only allowed on internal ALBs with `allow_plaintext_http = true`.
- Module-created security groups for internal ALBs default to HTTPS from the VPC CIDR, not `0.0.0.0/0`.
- `enable_http2 = true`, `idle_timeout = 60`, `ip_address_type = "ipv4"`.

Target groups use `name_prefix` and `create_before_destroy` so replacements never collide. The security group does the same.

## Prerequisites

Before applying this module in production, make sure the following are in place:

- **Caller IAM permissions**: `elasticloadbalancing:*`, `ec2:Describe*`, `ec2:CreateSecurityGroup`, `ec2:AuthorizeSecurityGroupIngress`, `ec2:AuthorizeSecurityGroupEgress`, `ec2:CreateTags`, `wafv2:AssociateWebACL` (if attaching a WAF).
- **VPC, subnets, and route tables** already exist. Internet-facing ALBs need public subnets with an IGW; internal ALBs need private subnets reachable from the clients.
- **ACM certificate** in the same region as the ALB if any listener uses HTTPS.
- **S3 bucket for access logs** with a bucket policy allowing the [regional ELB service account](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/enable-access-logging.html#attach-bucket-policy) to write. Without the policy, enabling logs silently fails.
- **WAFv2 WebACL** in the same scope (regional) as the ALB if `associate_waf = true`.

### Immutable settings

Changing any of these after the first apply forces the ALB or its security group to be replaced, which causes a brief disconnect from Route53 and any dependent services:

- `name`, `internal`, `ip_address_type`, `subnet_ids`, `vpc_id`
- `security_group_description`, `vpc_id` on the managed security group

Plan before applying any change to the inputs above.

### Costs

ALBs are billed per hour and per LCU (Load Balancer Capacity Unit). Access logs and connection logs incur S3 PUT + storage charges. WAF association is billed per WebACL + per request processed. See [the AWS pricing page](https://aws.amazon.com/elasticloadbalancing/pricing/) for current rates.

### State and secrets

The module does not store secrets in state. Certificate ARNs and WAF ARNs are opaque identifiers. Access log S3 bucket names are the only naming information in state.

## Usage

### Minimal (internet-facing, module-managed SG)

The simplest usable configuration. Lets the module create a security group and skip access logs. See `examples/minimal` for a runnable version.

```hcl
module "alb" {
  source = "sudo-terraform-aws-modules/alb/aws"

  name       = "my-app"
  internal   = false
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets

  create_security_group = true
  access_logs_enabled   = false

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
```

### Complete (HTTPS + redirect + path routing + access logs)

Realistic production shape: HTTPS listener with a certificate, HTTP-to-HTTPS redirect, path-based routing, and access logs to S3. See `examples/complete` for a runnable version.

```hcl
module "alb" {
  source = "sudo-terraform-aws-modules/alb/aws"

  name               = "my-app"
  internal           = false
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.public_subnets
  security_group_ids = [aws_security_group.alb.id]

  access_logs_bucket = aws_s3_bucket.alb_logs.bucket

  target_groups = {
    app = {
      port         = 8080
      health_check = { path = "/health", matcher = "200" }
    }
    api = {
      port         = 9090
      health_check = { path = "/api/health", matcher = "200-299" }
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
      certificate_arn  = module.acm.arn
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

  tags = { Environment = "production" }
}
```

### Route53 alias record

```hcl
module "route53" {
  source    = "sudo-terraform-aws-modules/sudo-route53/aws"
  zone_id   = data.aws_route53_zone.this.zone_id
  zone_name = "example.com"

  records = [
    {
      name  = "app"
      type  = "A"
      alias = {
        name                   = module.alb.dns_name
        zone_id                = module.alb.zone_id
        evaluate_target_health = true
      }
    }
  ]
}
```

## Security recommendations

### Attach a WAF to internet-facing ALBs

The module does not force WAF association, but internet-facing ALBs (`internal = false`) should normally have a WAFv2 WebACL attached. WAF is the single highest-ROI control for OWASP Top 10 attacks (SQL injection, XSS, path traversal), credential stuffing, and bot traffic. Pass the WebACL ARN and set `associate_waf = true`:

```hcl
module "alb" {
  source = "sudo-terraform-aws-modules/alb/aws"

  internal      = false
  associate_waf = true
  waf_acl_arn   = aws_wafv2_web_acl.public.arn
  # ...
}
```

If you intentionally do not attach a WAF (service mesh behind another L7 proxy, pure internal use case, etc.), document the decision in your root module. Internal ALBs can usually skip WAF since traffic is already inside the trust boundary.

### Mutual TLS (client certificate authentication)

For zero-trust architectures, B2B APIs, or regulated workloads, use `mutual_authentication` on HTTPS listeners to require client certificates:

```hcl
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
```

Modes:
- `off` - no client cert required (default).
- `passthrough` - ALB passes client cert in `X-Amzn-Mtls-Clientcert` header without validation.
- `verify` - ALB validates client cert against the trust store before forwarding; `trust_store_arn` is required.

### Access log bucket hardening

The S3 bucket pointed to by `access_logs_bucket` receives sensitive data (client IP addresses, user agents, request URLs including query strings). Apply standard bucket controls:

- `aws_s3_bucket_server_side_encryption_configuration` with SSE-KMS (CKV_AWS_145).
- `aws_s3_bucket_public_access_block` with all four flags true.
- `aws_s3_bucket_versioning` enabled for tamper evidence.
- `aws_s3_bucket_lifecycle_configuration` with a retention + expiration policy so logs do not accumulate forever.
- `aws_s3_bucket_policy` allowing only the regional ELB service account prefix path.
- Treat the bucket as PII under GDPR/CCPA if your users are in those jurisdictions.

## Known limitations

### Response headers (HSTS, CSP, etc.)

The module does not inject HSTS or other security response headers at the ALB layer. AWS ALB does not natively support response header modification on forwarded responses, so there is no first-class provider resource to configure. If you need HSTS or similar policies, add them at one of these layers instead:

- **CloudFront** in front of the ALB with a `ResponseHeadersPolicy` (HSTS, CSP, X-Content-Type-Options, Referrer-Policy, Permissions-Policy).
- **WAFv2 Custom Response rules** on the WebACL attached via `associate_waf = true`.
- **Application middleware** in the service behind the ALB.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.0.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.69.1 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_lb.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb_listener.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_listener_rule.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_rule) | resource |
| [aws_lb_target_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_wafv2_web_acl_association.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl_association) | resource |
| [aws_vpc.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/vpc) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_access_logs_bucket"></a> [access\_logs\_bucket](#input\_access\_logs\_bucket) | S3 bucket name for ALB access logs. Required when access\_logs\_enabled is true. The bucket must have the ELB service account allowed to write. | `string` | `null` | no |
| <a name="input_access_logs_enabled"></a> [access\_logs\_enabled](#input\_access\_logs\_enabled) | Whether to enable ALB access logs. Defaults to true. When true, access\_logs\_bucket must also be set. Set to false only when you have an explicit reason to disable logging. | `bool` | `true` | no |
| <a name="input_access_logs_prefix"></a> [access\_logs\_prefix](#input\_access\_logs\_prefix) | S3 key prefix for access logs. Defaults to the ALB name when null. Must not start or end with '/'. | `string` | `null` | no |
| <a name="input_allow_plaintext_http"></a> [allow\_plaintext\_http](#input\_allow\_plaintext\_http) | Allow HTTP listeners to forward directly to targets without redirecting. Only honoured when 'internal = true' - the listener precondition rejects plaintext HTTP on internet-facing ALBs. | `bool` | `false` | no |
| <a name="input_associate_waf"></a> [associate\_waf](#input\_associate\_waf) | Set to true to associate the waf\_acl\_arn WAF WebACL with the ALB. Using a bool avoids plan-time errors when waf\_acl\_arn is a computed value created in the same apply. | `bool` | `false` | no |
| <a name="input_connection_logs_bucket"></a> [connection\_logs\_bucket](#input\_connection\_logs\_bucket) | S3 bucket name for ALB connection logs (connection-level events). Set to null to disable. | `string` | `null` | no |
| <a name="input_connection_logs_prefix"></a> [connection\_logs\_prefix](#input\_connection\_logs\_prefix) | S3 key prefix for connection logs. Defaults to the ALB name when null. Must not start or end with '/'. | `string` | `null` | no |
| <a name="input_create"></a> [create](#input\_create) | Controls whether the ALB and associated resources are created. | `bool` | `true` | no |
| <a name="input_create_security_group"></a> [create\_security\_group](#input\_create\_security\_group) | Set to true to create and manage a security group for the ALB. When false, at least one security\_group\_id must be provided. | `bool` | `false` | no |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | If true, the ALB cannot be deleted via the AWS API. Defaults to true for production safety. | `bool` | `true` | no |
| <a name="input_desync_mitigation_mode"></a> [desync\_mitigation\_mode](#input\_desync\_mitigation\_mode) | How the ALB handles requests that might pose a security risk due to HTTP desync. Valid values: monitor, defensive, strictest. | `string` | `"defensive"` | no |
| <a name="input_enable_http2"></a> [enable\_http2](#input\_enable\_http2) | Whether HTTP/2 is enabled. | `bool` | `true` | no |
| <a name="input_enable_waf_fail_open"></a> [enable\_waf\_fail\_open](#input\_enable\_waf\_fail\_open) | Whether to allow the ALB to route requests to targets if WAF is unavailable. Defaults to false. | `bool` | `false` | no |
| <a name="input_idle_timeout"></a> [idle\_timeout](#input\_idle\_timeout) | Connection idle timeout in seconds. Must be between 1 and 4000 (AWS cap). | `number` | `60` | no |
| <a name="input_internal"></a> [internal](#input\_internal) | Set to true for an internal ALB, false for internet-facing. Required - must be set explicitly. | `bool` | n/a | yes |
| <a name="input_ip_address_type"></a> [ip\_address\_type](#input\_ip\_address\_type) | IP address type for the ALB. Valid values: ipv4, dualstack, dualstack-without-public-ipv4. | `string` | `"ipv4"` | no |
| <a name="input_listener_rules"></a> [listener\_rules](#input\_listener\_rules) | Map of listener rules for path- and host-based routing. Key is a logical name.<br/><br/>Example:<br/>  listener\_rules = {<br/>    api = {<br/>      listener\_key     = "https"<br/>      target\_group\_key = "api"<br/>      priority         = 10<br/>      path\_pattern     = ["/api/*"]<br/>    }<br/>  } | <pre>map(object({<br/>    listener_key     = string<br/>    target_group_key = string<br/>    priority         = optional(number, null)<br/>    path_pattern     = optional(list(string), null)<br/>    host_header      = optional(list(string), null)<br/>    http_header = optional(object({<br/>      name   = string<br/>      values = list(string)<br/>    }), null)<br/>  }))</pre> | `{}` | no |
| <a name="input_listeners"></a> [listeners](#input\_listeners) | Map of listeners to create. Key is a logical name (e.g. "http", "https").<br/><br/>Example (HTTPS with mutual TLS / client certificate authentication):<br/>  listeners = {<br/>    https = {<br/>      port             = 443<br/>      protocol         = "HTTPS"<br/>      certificate\_arn  = module.acm.arn<br/>      target\_group\_key = "app"<br/>      mutual\_authentication = {<br/>        mode            = "verify"<br/>        trust\_store\_arn = aws\_lb\_trust\_store.corp.arn<br/>      }<br/>    }<br/>  }<br/><br/>Example (HTTP to HTTPS redirect + HTTPS forwarding):<br/>  listeners = {<br/>    http = {<br/>      port     = 80<br/>      redirect = { port = "443", protocol = "HTTPS", status\_code = "HTTP\_301" }<br/>    }<br/>    https = {<br/>      port             = 443<br/>      protocol         = "HTTPS"<br/>      certificate\_arn  = module.acm.arn<br/>      target\_group\_key = "app"<br/>    }<br/>  } | <pre>map(object({<br/>    port             = number<br/>    protocol         = optional(string, "HTTP")<br/>    target_group_key = optional(string, null)<br/>    certificate_arn  = optional(string, null)<br/>    ssl_policy       = optional(string, "ELBSecurityPolicy-TLS13-1-2-2021-06")<br/>    redirect = optional(object({<br/>      port        = optional(string, "443")<br/>      protocol    = optional(string, "HTTPS")<br/>      status_code = optional(string, "HTTP_301")<br/>    }), null)<br/>    mutual_authentication = optional(object({<br/>      mode                             = string<br/>      trust_store_arn                  = optional(string, null)<br/>      advertise_trust_store_ca_names   = optional(string, null)<br/>      ignore_client_certificate_expiry = optional(bool, false)<br/>    }), null)<br/>  }))</pre> | `{}` | no |
| <a name="input_name"></a> [name](#input\_name) | Name of the ALB. Also used as a prefix for target group names. | `string` | n/a | yes |
| <a name="input_preserve_host_header"></a> [preserve\_host\_header](#input\_preserve\_host\_header) | Whether to preserve the client request host header on requests to the target. | `bool` | `false` | no |
| <a name="input_security_group_description"></a> [security\_group\_description](#input\_security\_group\_description) | Description for the created security group. Defaults to 'Security group for ALB <name>'. | `string` | `null` | no |
| <a name="input_security_group_egress_rules"></a> [security\_group\_egress\_rules](#input\_security\_group\_egress\_rules) | Egress rules for the created security group. Only used when create\_security\_group = true.<br/>When null, the module defaults to allowing all protocols to the VPC CIDR<br/>(looked up via data source). ALBs only forward to in-VPC targets, so this<br/>is a safer default than 0.0.0.0/0.<br/>Exactly one destination must be set per rule: cidr\_ipv4, cidr\_ipv6, prefix\_list\_id, or referenced\_security\_group\_id.<br/><br/>Example (restrict egress to a subset of the VPC):<br/>  security\_group\_egress\_rules = {<br/>    vpc\_only = {<br/>      ip\_protocol = "-1"<br/>      cidr\_ipv4   = "10.0.0.0/16"<br/>    }<br/>  }<br/><br/>Example (allow egress only to a specific target security group):<br/>  security\_group\_egress\_rules = {<br/>    to\_app = {<br/>      ip\_protocol                  = "tcp"<br/>      from\_port                    = 8080<br/>      to\_port                      = 8080<br/>      referenced\_security\_group\_id = aws\_security\_group.app.id<br/>    }<br/>  } | <pre>map(object({<br/>    ip_protocol                  = string<br/>    from_port                    = optional(number, null)<br/>    to_port                      = optional(number, null)<br/>    cidr_ipv4                    = optional(string, null)<br/>    cidr_ipv6                    = optional(string, null)<br/>    prefix_list_id               = optional(string, null)<br/>    referenced_security_group_id = optional(string, null)<br/>    description                  = optional(string, "")<br/>  }))</pre> | `null` | no |
| <a name="input_security_group_ids"></a> [security\_group\_ids](#input\_security\_group\_ids) | List of additional security group IDs to assign to the ALB. At least one is required when create\_security\_group is false. | `list(string)` | `[]` | no |
| <a name="input_security_group_ingress_rules"></a> [security\_group\_ingress\_rules](#input\_security\_group\_ingress\_rules) | Ingress rules for the created security group. Only used when create\_security\_group = true.<br/>When null, the module picks a safe default based on internal:<br/>  - internal = true: HTTPS (443) from the VPC CIDR only (looked up via data source).<br/>  - internal = false: HTTP (80) and HTTPS (443) from 0.0.0.0/0 so browsers can reach the ALB.<br/>Exactly one source must be set per rule: cidr\_ipv4, cidr\_ipv6, prefix\_list\_id, or referenced\_security\_group\_id.<br/><br/>Example (restrict to a known CIDR):<br/>  security\_group\_ingress\_rules = {<br/>    https\_corp = {<br/>      ip\_protocol = "tcp"<br/>      from\_port   = 443<br/>      to\_port     = 443<br/>      cidr\_ipv4   = "10.0.0.0/8"<br/>    }<br/>  }<br/><br/>Example (allow only a specific client security group):<br/>  security\_group\_ingress\_rules = {<br/>    https\_from\_app = {<br/>      ip\_protocol                  = "tcp"<br/>      from\_port                    = 443<br/>      to\_port                      = 443<br/>      referenced\_security\_group\_id = aws\_security\_group.app.id<br/>    }<br/>  } | <pre>map(object({<br/>    ip_protocol                  = string<br/>    from_port                    = optional(number, null)<br/>    to_port                      = optional(number, null)<br/>    cidr_ipv4                    = optional(string, null)<br/>    cidr_ipv6                    = optional(string, null)<br/>    prefix_list_id               = optional(string, null)<br/>    referenced_security_group_id = optional(string, null)<br/>    description                  = optional(string, "")<br/>  }))</pre> | `null` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | List of subnet IDs. Use public subnets for internet-facing, private for internal. | `list(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources. | `map(string)` | `{}` | no |
| <a name="input_target_groups"></a> [target\_groups](#input\_target\_groups) | Map of target groups to create. Key is a logical name referenced by listeners and rules.<br/><br/>Example:<br/>  target\_groups = {<br/>    app = {<br/>      port     = 8080<br/>      protocol = "HTTP"<br/>      health\_check = {<br/>        path    = "/health"<br/>        matcher = "200"<br/>      }<br/>    }<br/>  } | <pre>map(object({<br/>    port                 = number<br/>    protocol             = optional(string, "HTTP")<br/>    target_type          = optional(string, "ip")<br/>    deregistration_delay = optional(number, 30)<br/>    slow_start           = optional(number, 0)<br/>    health_check = optional(object({<br/>      protocol            = optional(string, null)<br/>      port                = optional(string, "traffic-port")<br/>      path                = optional(string, "/")<br/>      matcher             = optional(string, "200-299")<br/>      healthy_threshold   = optional(number, 3)<br/>      unhealthy_threshold = optional(number, 3)<br/>      interval            = optional(number, 30)<br/>      timeout             = optional(number, 5)<br/>    }), null)<br/>    stickiness = optional(object({<br/>      type            = optional(string, "lb_cookie")<br/>      cookie_duration = optional(number, 86400)<br/>      cookie_name     = optional(string, null)<br/>      enabled         = optional(bool, true)<br/>    }), null)<br/>  }))</pre> | `{}` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID where target groups will be created. | `string` | n/a | yes |
| <a name="input_waf_acl_arn"></a> [waf\_acl\_arn](#input\_waf\_acl\_arn) | ARN of a WAFv2 web ACL to associate with the ALB. Set associate\_waf = true to attach it. | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_arn"></a> [arn](#output\_arn) | ARN of the ALB. |
| <a name="output_dns_name"></a> [dns\_name](#output\_dns\_name) | DNS name of the ALB. Use as the alias target in Route53. |
| <a name="output_id"></a> [id](#output\_id) | ID of the ALB. |
| <a name="output_listener_arns"></a> [listener\_arns](#output\_listener\_arns) | Map of logical listener key to ARN. |
| <a name="output_listener_rule_arns"></a> [listener\_rule\_arns](#output\_listener\_rule\_arns) | Map of logical listener rule key to ARN. |
| <a name="output_security_group_arn"></a> [security\_group\_arn](#output\_security\_group\_arn) | ARN of the module-created security group. Null when create\_security\_group is false. |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | ID of the module-created security group. Null when create\_security\_group is false. |
| <a name="output_target_group_arns"></a> [target\_group\_arns](#output\_target\_group\_arns) | Map of logical target group key to ARN. |
| <a name="output_target_groups"></a> [target\_groups](#output\_target\_groups) | Map of target group attributes keyed by logical name. |
| <a name="output_waf_acl_association_id"></a> [waf\_acl\_association\_id](#output\_waf\_acl\_association\_id) | ID of the WAFv2 web ACL association, or null when no WAF is attached. |
| <a name="output_zone_id"></a> [zone\_id](#output\_zone\_id) | Hosted zone ID of the ALB. Use with Route53 alias records. |
<!-- END_TF_DOCS -->
