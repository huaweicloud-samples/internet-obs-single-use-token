###############################################################################
# 根输出
###############################################################################

output "api_base_url" {
  description = "API 调用基础地址（APIG 实例入口，HTTPS）"
  value       = module.apig.invoke_url
}

output "token_endpoint" {
  description = "token 端点（GET 生成单次使用 token；POST 用 token 换签名 URL）"
  value       = "${module.apig.invoke_url}/token"
}

output "apig_instance_id" {
  description = "APIG 专享版实例 ID"
  value       = module.apig.instance_id
}

output "apig_application_id" {
  description = "APIG 应用 ID（AppCode 归属应用）"
  value       = module.apig.application_id
}

output "apig_appcode" {
  description = "应用认证 AppCode（客户端在 X-Apig-AppCode 头携带）"
  value       = module.apig.appcode
  sensitive   = true
}

output "obs_bucket_name" {
  description = "OBS 桶名（签名 URL 的目标桶）"
  value       = module.obs.bucket_name
}

output "obs_object_key" {
  description = "示例对象键"
  value       = var.obs_object_key
}

output "geminidb_endpoint" {
  description = "GeminiDB 内网接入地址（负载均衡地址）"
  value       = module.geminidb.endpoint
}

output "geminidb_port" {
  description = "GeminiDB 数据面端口（集群形态为 80）"
  value       = module.geminidb.port
}

output "token_table_name" {
  description = "token 表名（函数首次写入时自动创建）"
  value       = var.token_table_name
}

output "function_name" {
  description = "FunctionGraph 函数名"
  value       = module.functiongraph.function_name
}

output "function_urn" {
  description = "FunctionGraph 函数 URN"
  value       = module.functiongraph.function_urn
}
