output "policy_id" {
  description = "防护策略 ID（未启用时为空）"
  value       = var.enable_waf ? huaweicloud_waf_policy.main[0].id : ""
}

output "enabled" {
  description = "WAF 是否启用"
  value       = var.enable_waf
}
