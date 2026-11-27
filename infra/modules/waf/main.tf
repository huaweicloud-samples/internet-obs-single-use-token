###############################################################################
# WAF 模块（可选启用）
# ----------------------------------------------------------------------------
# 落地 Web 应用防火墙防护策略，并把域名接入 WAF 回源到 API 网关入口。
#
# 本模块**默认关闭**（enable_waf = false）。生产环境的 WAF 为可选付费服务，
# 与默认关闭约定一致；如确需开启，需先完成 WAF 服务开通，再把 enable_waf
# 置为 true 并补齐域名。
#
# 默认的按需防护由接入层承担：
#   - 速率限制 → 网关限流策略（见 apig 模块）
#   - 入参校验 → 网关请求参数校验 + 函数侧模型校验
###############################################################################

terraform {
  required_providers {
    huaweicloud = {
      source = "huaweicloud/huaweicloud"
    }
  }
}

resource "huaweicloud_waf_policy" "main" {
  count = var.enable_waf ? 1 : 0

  name  = var.policy_name
  level = var.protection_level

  # 防护模式：仅记录 / 拦截，由控制台按需切换
  protection_mode = var.protection_mode
}

resource "huaweicloud_waf_domain" "apig" {
  count = var.enable_waf ? 1 : 0

  domain         = var.domain_name
  policy_id      = huaweicloud_waf_policy.main[0].id
  protect_status = 1 # 1 = 已开启防护

  # 回源到 API 网关实例入口
  server {
    address         = var.origin_address
    port            = var.origin_port
    type            = "ip"
    client_protocol = "HTTPS"
    server_protocol = "HTTPS"
  }
}
