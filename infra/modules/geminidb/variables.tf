variable "instance_name" {
  description = "GeminiDB 实例名"
  type        = string
}

variable "region" {
  description = "华为云 region"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_id" {
  description = "子网 ID"
  type        = string
}

variable "security_group_id" {
  description = "安全组 ID"
  type        = string
}

variable "geminidb_password" {
  description = "实例管理员（rwuser）密码"
  type        = string
  sensitive   = true
}

variable "geminidb_flavor_spec" {
  description = "节点规格码（DynamoDB 兼容接口复用宽表规格族）"
  type        = string
}

variable "availability_zone" {
  description = "可用区，逗号分隔字符串"
  type        = string
}

variable "node_num" {
  description = "节点数"
  type        = number
}

variable "storage_size" {
  description = "单节点磁盘容量（GB）"
  type        = number
}

variable "tags" {
  description = "公共标签"
  type        = map(string)
  default     = {}
}
