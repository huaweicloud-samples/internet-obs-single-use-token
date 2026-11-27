###############################################################################
# APIG 模块（专享版）
# ----------------------------------------------------------------------------
# 落地 APIG 专享版实例 + 分组 + 应用 + AppCode 鉴权 + 两条 API
# （GET /token 生成；POST /token 交换）+ 发布 + 限流策略。
#
# 要点：
#   - edition 为必填，取基础版规格
#   - security_group_id 是字符串（不是列表）
#   - 应用认证通过 simple_authentication 开关 + AppCode（自定义认证头）
#   - 发布记录不含 group_id，只按环境发布；发布 ID 由发布记录导出，
#     限流策略按发布 ID 关联到两条 API
#   - 限流策略对应按 IP 的速率限制
###############################################################################

terraform {
  required_providers {
    huaweicloud = {
      source = "huaweicloud/huaweicloud"
    }
  }
}

resource "huaweicloud_apig_instance" "main" {
  name               = "${var.api_name}-instance"
  edition            = "BASIC"
  description        = "Dedicated instance for ${var.api_name}"
  vpc_id             = var.vpc_id
  subnet_id          = var.subnet_id
  security_group_id  = var.security_group_id
  availability_zones = var.availability_zones

  # 公网入口：互联网场景必须开启（ingress EIP + 带宽规格）
  # APIC.7259 约束——该入口仅支持带宽规格，不支持按流量模式
  loadbalancer_provider           = "elb"
  ingress_bandwidth_size          = 5
  ingress_bandwidth_charging_mode = "bandwidth"

  maintain_begin = "02:00:00"

  tags = var.tags
}

resource "huaweicloud_apig_group" "main" {
  name        = "${var.api_name}-group"
  instance_id = huaweicloud_apig_instance.main.id
  description = "API group for ${var.api_name}"
}

resource "huaweicloud_apig_application" "main" {
  # APIG 应用名只允许字母/数字/下划线（连字符触 APIG.2011）
  name        = replace("${var.api_name}-app", "-", "_")
  instance_id = huaweicloud_apig_instance.main.id
  description = "Application for AppCode authentication"
}

resource "huaweicloud_apig_appcode" "main" {
  application_id = huaweicloud_apig_application.main.id
  instance_id    = huaweicloud_apig_instance.main.id
  # value 为 computed：由 APIG 自动生成（显式传值触 APIG.2011）
}

# GET /token：生成单次使用 token
resource "huaweicloud_apig_api" "get_token" {
  name             = "${var.api_name}-get-token"
  group_id         = huaweicloud_apig_group.main.id
  instance_id      = huaweicloud_apig_instance.main.id
  type             = "Private"
  request_method   = "GET"
  request_path     = "/token"
  request_protocol = "HTTPS"
  matching         = "Exact"
  description      = "Generate a single-use application token"

  simple_authentication   = true
  security_authentication = "APP"

  func_graph {
    # 云端存储的 URN 无 :latest 后缀；若不规范化 provider 会尝试更新
    # func_graph 块（不可更新）→ func_graph can't be updated
    function_urn     = replace(var.function_urn, ":latest", "")
    timeout          = 30000
    request_protocol = "HTTPS"
    network_type     = "V1"
    version          = "latest"
  }
}

# POST /token：用 token 换短期签名 URL
resource "huaweicloud_apig_api" "post_token" {
  name             = "${var.api_name}-post-token"
  group_id         = huaweicloud_apig_group.main.id
  instance_id      = huaweicloud_apig_instance.main.id
  type             = "Private"
  request_method   = "POST"
  request_path     = "/token"
  request_protocol = "HTTPS"
  matching         = "Exact"
  description      = "Exchange a single-use token for a short-lived signed URL"

  simple_authentication   = true
  security_authentication = "APP"

  func_graph {
    # 云端存储的 URN 无 :latest 后缀；若不规范化 provider 会尝试更新
    # func_graph 块（不可更新）→ func_graph can't be updated
    function_urn     = replace(var.function_urn, ":latest", "")
    timeout          = 30000
    request_protocol = "HTTPS"
    network_type     = "V1"
    version          = "latest"
  }

  # 注意：函数后端不支持 BODY 位置参数，token 由函数解析 event.body。
}

# 发布环境：RELEASE 是专享版实例预置的默认环境（id=DEFAULT_ENVIRONMENT_RELEASE_ID），
# 直接引用而非创建（同名创建报 APIG.3205 The environment name already exists）
data "huaweicloud_apig_environments" "main" {
  instance_id = huaweicloud_apig_instance.main.id
  name        = var.environment
}

resource "huaweicloud_apig_api_publishment" "get_token" {
  instance_id = huaweicloud_apig_instance.main.id
  api_id      = huaweicloud_apig_api.get_token.id
  env_id      = data.huaweicloud_apig_environments.main.environments[0].id
}

resource "huaweicloud_apig_api_publishment" "post_token" {
  instance_id = huaweicloud_apig_instance.main.id
  api_id      = huaweicloud_apig_api.post_token.id
  env_id      = data.huaweicloud_apig_environments.main.environments[0].id
}

# 限流策略：时间窗内单 API 请求上限
resource "huaweicloud_apig_throttling_policy" "main" {
  instance_id = huaweicloud_apig_instance.main.id
  # 限流策略名同样只允许字母/数字/下划线
  name             = replace("${var.api_name}-throttle", "-", "_")
  type             = "API-based"
  period           = var.throttle_period
  period_unit      = var.period_unit
  max_api_requests = var.max_api_requests
  description      = "Rate limiting for ${var.api_name}"
}

resource "huaweicloud_apig_throttling_policy_associate" "main" {
  instance_id = huaweicloud_apig_instance.main.id
  policy_id   = huaweicloud_apig_throttling_policy.main.id
  publish_ids = [
    huaweicloud_apig_api_publishment.get_token.publish_id,
    huaweicloud_apig_api_publishment.post_token.publish_id,
  ]
}


# APP 认证模式下，应用必须显式授权才能调用 API（否则 APIG.0304）
resource "huaweicloud_apig_application_authorization" "main" {
  instance_id    = huaweicloud_apig_instance.main.id
  application_id = huaweicloud_apig_application.main.id
  env_id         = data.huaweicloud_apig_environments.main.environments[0].id
  api_ids = [
    huaweicloud_apig_api.get_token.id,
    huaweicloud_apig_api.post_token.id,
  ]
}
