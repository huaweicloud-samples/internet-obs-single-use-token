variable "function_name" {
  description = "函数名"
  type        = string
}

variable "region" {
  description = "华为云 region"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID（函数访问 GeminiDB 需入 VPC）"
  type        = string
}

variable "subnet_id" {
  description = "子网 ID"
  type        = string
}

variable "code_bucket_name" {
  description = "存放代码 zip 的 OBS 桶名"
  type        = string
}

variable "code_object_key" {
  description = "代码 zip 的对象键"
  type        = string
}

variable "memory_size" {
  description = "函数内存（MB）"
  type        = number
}

variable "timeout" {
  description = "函数超时（秒）"
  type        = number
}

variable "token_table_name" {
  description = "token 表名"
  type        = string
}

variable "geminidb_endpoint" {
  description = "GeminiDB 内网接入地址"
  type        = string
}

variable "geminidb_port" {
  description = "GeminiDB 数据面端口"
  type        = number
}

variable "geminidb_password" {
  description = "GeminiDB 实例管理员密码"
  type        = string
  sensitive   = true
}

variable "obs_bucket_name" {
  description = "签名 URL 目标桶"
  type        = string
}

variable "obs_object_key" {
  description = "签名 URL 目标对象键"
  type        = string
}

variable "token_ttl_seconds" {
  description = "token 有效期（秒）"
  type        = number
}

variable "presigned_url_expiration" {
  description = "签名 URL 有效期（秒）"
  type        = number
}

variable "log_level" {
  description = "日志级别"
  type        = string
}

variable "tags" {
  description = "公共标签"
  type        = map(string)
  default     = {}
}

variable "runtime" {
  description = "函数运行时"
  type        = string
  default     = "Python3.9"
}

variable "code_zip_path" {
  description = "本地代码 zip 路径（非空时由本模块上传到对象存储并托管）"
  type        = string
  default     = ""
}

variable "obs_signer_ak" {
  description = "URL 预签名专用永久 AK（委托临时 AK 无法用于 URL 签名）"
  type        = string
  sensitive   = true
  default     = ""
}

variable "obs_signer_sk" {
  description = "URL 预签名专用永久 SK"
  type        = string
  sensitive   = true
  default     = ""
}
