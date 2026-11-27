output "instance_id" {
  description = "APIG 实例 ID"
  value       = huaweicloud_apig_instance.main.id
}

output "ingress_address" {
  description = "实例入口地址"
  value       = huaweicloud_apig_instance.main.ingress_address
}

output "invoke_url" {
  description = "API 调用基础地址"
  value       = "https://${huaweicloud_apig_instance.main.ingress_address}"
}

output "application_id" {
  description = "应用 ID"
  value       = huaweicloud_apig_application.main.id
}

output "appcode" {
  description = "应用认证 AppCode"
  value       = huaweicloud_apig_appcode.main.value
  sensitive   = true
}

output "group_id" {
  description = "API 分组 ID"
  value       = huaweicloud_apig_group.main.id
}
