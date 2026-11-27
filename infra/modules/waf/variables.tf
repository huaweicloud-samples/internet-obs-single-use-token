variable "enable_waf" {
  description = "是否启用 WAF（默认关闭，因套餐预付费与按需部署约定冲突）"
  type        = bool
  default     = false
}

variable "policy_name" {
  description = "防护策略名"
  type        = string
}

variable "protection_level" {
  description = "防护等级（数值越大规则越严）"
  type        = number
  default     = 1
}

variable "protection_mode" {
  description = "防护模式"
  type        = string
  default     = "log"
}

variable "domain_name" {
  description = "接入 WAF 的域名（启用时必填）"
  type        = string
  default     = ""
}

variable "origin_address" {
  description = "回源地址（API 网关实例入口地址）"
  type        = string
  default     = ""
}

variable "origin_port" {
  description = "回源端口"
  type        = number
  default     = 443
}
