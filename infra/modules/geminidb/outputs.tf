output "instance_id" {
  description = "GeminiDB 实例 ID"
  value       = huaweicloud_geminidb_instance.token_store.id
}

output "endpoint" {
  description = "内网接入地址（负载均衡地址）"
  value       = huaweicloud_geminidb_instance.token_store.lb_ip_address
}

output "port" {
  # 集群形态（mode=Cluster）DynamoDB 兼容数据面端口是 80（HA 端口），
  # 单节点形态才是 8000。provider 的 port 属性在集群形态下返回 8000，
  # 直接透传会让函数连错端口（内网 8000 不通 → 调用超时）。
  # 集群形态数据面端口为 80（2026-09-14 实测确认）。
  description = "数据面端口（集群形态 80）"
  value       = 80
}
