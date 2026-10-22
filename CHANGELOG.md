# Changelog

All notable changes to this module are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the module uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Breaking changes

- `internal` is now required with no default. Callers must explicitly set `internal = true` or `internal = false`.
- `security_group_ids` is now required with no default. At least one security group ID must be provided.
- HTTP listeners that forward directly to targets are now rejected at plan time. HTTP listeners must use `redirect`. Set `allow_plaintext_http = true` to opt out for internal service-to-service ALBs.
- Target groups now use `name_prefix` instead of a fixed `name`. Existing target groups will be replaced on the next apply.
- `associate_waf` bool is now required to attach a WAF WebACL. Previously `waf_acl_arn != null` was sufficient.

### Added

- `create_security_group` variable: set to `true` to have the module create and manage the ALB security group. Defaults open HTTP (80) and HTTPS (443) inbound; egress is fully customisable via `security_group_ingress_rules` and `security_group_egress_rules`.
- `security_group_id` and `security_group_arn` outputs expose the module-created security group for use by target group security group rules.
- `ip_address_type` variable supports `ipv4`, `dualstack`, and `dualstack-without-public-ipv4` for IPv6 and dual-stack deployments.
- `connection_logs_bucket` / `connection_logs_prefix` variables enable ALB connection-level logging to S3 (separate from access logs).
- `preserve_host_header` variable: when `true`, the ALB forwards the client `Host` header unchanged to targets.
- Initial implementation of the ALB module.
- Support for multiple target groups with per-group health check and stickiness configuration.
- Listener support for HTTP and HTTPS with HTTP→HTTPS redirect action.
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

### Security

- `internal` is now required to prevent accidental public exposure.
- `access_logs_enabled` defaults to `true`; `access_logs_bucket` is required unless `access_logs_enabled = false`. This satisfies CKV_AWS_91 natively without a Checkov skip.
- HTTP forwarding is blocked by default; only redirects are allowed.
- `ssl_policy` validated against an allowlist of TLS 1.2+ policies.
- `deletion_protection` defaults to `true`.
- `drop_invalid_header_fields` hardcoded to `true`.
- `enable_waf_fail_open` defaults to `false`.
