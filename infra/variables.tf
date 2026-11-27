###############################################################################
# 根变量
###############################################################################

variable "region" {
  description = "华为云 region"
  type        = string
  default     = "cn-north-4"
}

variable "project_name" {
  description = "项目名（资源命名前缀）"
  type        = string
  default     = "internet-obs-single-use-token"
}

variable "tags" {
  description = "公共标签"
  type        = map(string)
  default = {
    project = "internet-obs-single-use-token"
  }
}

# ----- 网络 -----

variable "vpc_cidr" {
  description = "VPC 网段"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "子网网段"
  type        = string
  default     = "10.0.1.0/24"
}

# ----- OBS -----

variable "obs_bucket_name" {
  description = "OBS 桶名（全局唯一，建议带项目前缀 + 随机后缀）"
  type        = string
}

variable "obs_object_key" {
  description = "示例对象键（签名 URL 的目标对象）"
  type        = string
  default     = "sample-image.png"
}

variable "sample_image_path" {
  description = "本地示例图片路径（apply 时上传到桶根）；空字符串则不上传"
  type        = string
  default     = "../assets/sample-image.png"
}

# ----- GeminiDB -----

variable "geminidb_instance_name" {
  description = "GeminiDB 实例名"
  type        = string
  default     = "token-store"
}

variable "token_table_name" {
  description = "token 表名（函数首次写入时自动创建）"
  type        = string
  default     = "single-use-tokens"
}

variable "geminidb_password" {
  description = "GeminiDB 实例管理员密码（rwuser）；建议经 TF_VAR_geminidb_password 注入"
  type        = string
  sensitive   = true
}

variable "geminidb_flavor_spec" {
  description = "GeminiDB 节点规格码（DynamoDB 兼容接口复用宽表规格族）"
  type        = string
  default     = "geminidb.cassandra.large.4"
}

variable "geminidb_availability_zone" {
  description = "可用区（逗号分隔字符串；集群形态需 3 个可用区）"
  type        = string
  default     = "cn-north-4a,cn-north-4b,cn-north-4c"
}

variable "geminidb_node_num" {
  description = "节点数（集群形态 3–12）"
  type        = number
  default     = 3
}

variable "geminidb_storage_size" {
  description = "单节点磁盘容量（GB，10 的倍数）"
  type        = number
  default     = 100
}

# ----- FunctionGraph -----

variable "function_name" {
  description = "函数名"
  type        = string
  default     = "token-handler"
}

variable "code_bucket_name" {
  description = "存放函数代码 zip 的 OBS 桶名（通常与 obs_bucket_name 同桶）"
  type        = string
}

variable "code_object_key" {
  description = "函数代码 zip 在 OBS 中的对象键"
  type        = string
  default     = "function-code/token-handler.zip"
}

variable "code_zip_path" {
  description = "本地函数代码包路径（非空时由 IaC 上传到对象存储并托管，改动即触发函数重建）"
  type        = string
  default     = ""
}

variable "function_memory_size" {
  description = "函数内存（MB）"
  type        = number
  default     = 512
}

variable "function_timeout" {
  description = "函数超时（秒）"
  type        = number
  default     = 30
}

variable "token_ttl_seconds" {
  description = "token 有效期（秒）"
  type        = number
  default     = 3600
}

variable "presigned_url_expiration" {
  description = "签名 URL 有效期（秒）"
  type        = number
  default     = 300
}

variable "function_log_level" {
  description = "函数日志级别"
  type        = string
  default     = "INFO"
}

variable "obs_signer_access_key_id" {
  description = "OBS 签名专用永久 AK（用于函数内预签名 URL；与运行时 AK/SK 分离便于轮换）"
  type        = string
  sensitive   = true
}

variable "obs_signer_secret_access_key" {
  description = "OBS 签名专用永久 SK"
  type        = string
  sensitive   = true
}

# ----- APIG -----

variable "apig_appcode" {
  description = "应用认证 AppCode（客户端在 X-Apig-AppCode 头携带）"
  type        = string
  sensitive   = true
}

variable "apig_environment" {
  description = "API 发布环境名"
  type        = string
  default     = "RELEASE"
}

variable "apig_availability_zones" {
  description = "APIG 专享版实例可用区（缺省会触发服务端 APIC.9999）"
  type        = list(string)
  default     = ["cn-north-4a", "cn-north-4b"]
}

variable "apig_max_api_requests" {
  description = "限流策略：时间窗内单 API 最大请求数"
  type        = number
  default     = 100
}

variable "apig_throttle_period" {
  description = "限流策略：时间窗长度"
  type        = number
  default     = 1
}

variable "apig_throttle_period_unit" {
  description = "限流策略：时间窗单位"
  type        = string
  default     = "MINUTE"
}

# ----- WAF（可选）-----

variable "enable_waf" {
  description = "是否启用 WAF（默认关闭；WAF 为可选付费服务）"
  type        = bool
  default     = false
}

variable "waf_protection_level" {
  description = "WAF 防护等级"
  type        = number
  default     = 1
}

variable "waf_domain_name" {
  description = "接入 WAF 的域名（enable_waf = true 时必填）"
  type        = string
  default     = ""
}
