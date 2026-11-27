output "function_name" {
  description = "函数名"
  value       = huaweicloud_fgs_function.token_handler.name
}

output "function_urn" {
  description = "函数 URN"
  value       = huaweicloud_fgs_function.token_handler.urn
}

output "agency_name" {
  description = "函数执行委托名"
  value       = huaweicloud_identity_agency.functiongraph.name
}
