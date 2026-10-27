# Changelog

All notable changes to this module are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the module uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Breaking changes

- `internal` is now required with no default. Callers must explicitly set `internal = true` or `internal = false`.
- Callers must now provide either `create_security_group = true` or at least one entry in `security_group_ids`. The `aws_lb` precondition rejects the config at plan time if neither is set.
- HTTP listeners that forward directly to targets are now rejected at plan time. HTTP listeners must use `redirect`. Set `allow_plaintext_http = true` to opt out for internal service-to-service ALBs.
- Target groups now use `name_prefix` instead of a fixed `name`. Existing target groups will be replaced on the next apply.
- `associate_waf` bool is now required to attach a WAF WebACL. Previously `waf_acl_arn != null` was sufficient.
- The module-created security group now uses `name_prefix` instead of a fixed `name` so `create_before_destroy` replacements no longer collide. Existing security groups will be replaced on the next apply.
- When `create_security_group = true` and the caller does not set `security_group_ingress_rules`, the default now depends on `internal`:
  - `internal = true`: HTTPS (443) from the VPC CIDR only (looked up via a new `data.aws_vpc.this` lookup). Previously defaulted to 0.0.0.0/0.
  - `internal = false`: HTTP (80) and HTTPS (443) from 0.0.0.0/0 (unchanged).
- `allow_plaintext_http = true` now only takes effect when `internal = true`. Previously it also silenced the precondition on internet-facing ALBs.
- When `create_security_group = true` and the caller does not set `security_group_egress_rules`, the default is now all protocols to the VPC CIDR (looked up via `data.aws_vpc.this`). Previously defaulted to 0.0.0.0/0. ALBs only forward to in-VPC targets, so wider egress served no purpose and got flagged by security tooling.
- `security_group_ingress_rules` and `security_group_egress_rules` object types gained `prefix_list_id` and `referenced_security_group_id` fields so callers can allow traffic by prefix list or by target security group ID, not just by CIDR. A variable validation now requires exactly one source per rule.

### Added

- `create_security_group` variable: set to `true` to have the module create and manage the ALB security group. Defaults open HTTP (80) and HTTPS (443) inbound; egress is fully customisable via `security_group_ingress_rules` and `security_group_egress_rules`.
- `security_group_id` and `security_group_arn` outputs expose the module-created security group for use by target group security group rules.
- `ip_address_type` variable supports `ipv4`, `dualstack`, and `dualstack-without-public-ipv4` for IPv6 and dual-stack deployments.
- `connection_logs_bucket` / `connection_logs_prefix` variables enable ALB connection-level logging to S3 (separate from access logs).
- `preserve_host_header` variable: when `true`, the ALB forwards the client `Host` header unchanged to targets.
- `mutual_authentication` field on `listeners` object: configure mTLS (client certificate authentication) on HTTPS listeners. Modes `off`, `passthrough`, `verify`; `verify` requires `trust_store_arn`. mTLS on non-HTTPS listeners is rejected at plan.
- Initial implementation of the ALB module.
- Support for multiple target groups with per-group health check and stickiness configuration.
- Listener support for HTTP and HTTPS with HTTP-to-HTTPS redirect action.
- Listener rules for path-pattern, host-header, and HTTP header based routing.
- Access logs to S3, deletion protection, idle timeout, and HTTP/2 toggles.
- WAF WebACL association via `associate_waf` + `waf_acl_arn`.
- `enable_waf_fail_open` and `desync_mitigation_mode` variables with secure defaults.
- `allow_plaintext_http` variable for internal service-to-service ALBs.
- `examples/minimal` and `examples/complete` usage examples.

### Fixed

- Target group replacement no longer fails with `already exists` when port, protocol, or type changes.
- HTTPS target group health checks now default to HTTPS instead of HTTP.
- Empty `security_group_ids` no longer causes drift after first apply.
- WAF association no longer fails at plan when `waf_acl_arn` is a computed value.
- Listeners with no `redirect` and no `target_group_key` now fail at plan with a clear error.
- HTTPS listeners without `certificate_arn` now fail at plan instead of apply.
- Listener rules with no `path_pattern`, `host_header`, or `http_header` condition now fail at plan instead of hitting a cryptic provider error at apply.
- `idle_timeout` outside 1-4000 is rejected at plan.
- Listener and target group `port` outside 1-65535 is rejected at plan.
- Listener `protocol` outside HTTP/HTTPS and target group `protocol` outside HTTP/HTTPS/HTTP2/GRPC are rejected at plan.
- `target_type` outside instance/ip/lambda/alb is rejected at plan.
- `stickiness.type` outside lb_cookie/app_cookie/source_ip is rejected at plan.
- `stickiness.cookie_name` combined with `stickiness.type = "lb_cookie"` is rejected at plan (only valid with app_cookie).
- `stickiness.cookie_duration` outside 1-604800 is rejected at plan.
- `listener_rules.priority` outside 1-50000 is rejected at plan.
- `target_groups` keys must now be lowercase alphanumeric (optionally with hyphens, max 6 chars for the AWS name prefix) and are rejected at plan if they are not.
- `access_logs_prefix` / `connection_logs_prefix` with leading or trailing `/` are rejected at plan.

### Security

- `internal` is now required to prevent accidental public exposure.
- `access_logs_enabled` defaults to `true`; `access_logs_bucket` is required unless `access_logs_enabled = false`. This satisfies CKV_AWS_91 natively without a Checkov skip.
- HTTP forwarding is blocked by default; only redirects are allowed.
- `ssl_policy` validated against an allowlist of TLS 1.2+ policies (now includes the `TLS13-1-2-Res`, `TLS13-1-2-Ext1`, and `TLS13-1-2-Ext2` variants of the 2021-06 policy).
- README now documents security recommendations for WAF association on internet-facing ALBs, mTLS usage, and access log bucket hardening (SSE-KMS, BPA, versioning, lifecycle, PII treatment).
- `deletion_protection` defaults to `true`.
- `drop_invalid_header_fields` hardcoded to `true`.
- `enable_waf_fail_open` defaults to `false`.
