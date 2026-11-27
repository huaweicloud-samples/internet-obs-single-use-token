variable "api_name" {
  description = "API 名称前缀"
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

variable "availability_zones" {
  description = "实例可用区列表（APIG 专享版多 AZ 部署；不指定会触发服务端 APIC.9999）"
  type        = list(string)
}

variable "security_group_id" {
  description = "安全组 ID"
  type        = string
}

variable "function_urn" {
  description = "后端函数 URN"
  type        = string
}

variable "appcode" {
  description = "应用认证 AppCode"
  type        = string
  sensitive   = true
}

variable "environment" {
  description = "发布环境名"
  type        = string
}

variable "max_api_requests" {
  description = "时间窗内单 API 最大请求数"
  type        = number
}

variable "throttle_period" {
  description = "时间窗长度"
  type        = number
}

variable "period_unit" {
  description = "时间窗单位"
  type        = string
}

variable "tags" {
  description = "公共标签"
  type        = map(string)
  default     = {}
}
