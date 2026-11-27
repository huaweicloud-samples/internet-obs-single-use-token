###############################################################################
# FunctionGraph 模块
# ----------------------------------------------------------------------------
# 落地函数执行委托 + 函数（代码 zip 经 OBS 下发）。
#
# 要点：
#   - 函数签名保持 handler(event, context)；event 为网关触发器规范
#   - 委托按角色作用域归属：全局服务级角色放 domain_roles，项目级角色放
#     project_role（授错层级会静默不生效）
#   - 函数需加入 VPC 才能访问同 VPC 内的宽表实例（vpc_id + network_id）
#   - 代码走 code_type = "obs"（zip 经对象存储下发，比本地 zip 稳）
#   - 代码对象由本模块托管时，改动 zip 会自动触发函数重建
###############################################################################

terraform {
  required_providers {
    huaweicloud = {
      source = "huaweicloud/huaweicloud"
    }
  }
}

# 函数执行委托：委托给函数计算服务身份，并授予对象存储全局服务级角色
# （读取签名 URL 的目标对象）
resource "huaweicloud_identity_agency" "functiongraph" {
  name                   = "${var.function_name}-agency"
  description            = "Agency for the function to access object storage"
  duration               = "FOREVER"
  delegated_service_name = "op_svc_cff"

  # OBS 是全局服务：管理员角色走 domain_roles
  domain_roles = [
    "OBS Administrator",
  ]

  # VPC 是项目级服务：VPC Administrator 必须挂 project_role，
  # 否则函数入 VPC 报 VPC.0216 Policy doesn't allow 'get_network'
  project_role {
    project = var.region
    roles   = ["VPC Administrator"]
  }
}

# 代码包指纹：zip 内容变化 -> 对象 key 带 hash 变化 -> 新对象 + 新 code_url
# （函数侧 code_url 变化走 UpdateFunctionCode 热更新，函数不重建、URN 不变，
#   APIG func_graph 引用完全不受影响；绝不能 replace 函数）
locals {
  code_hash       = var.code_zip_path != "" ? substr(filemd5(var.code_zip_path), 0, 8) : "unmanaged"
  code_object_key = var.code_zip_path != "" ? "function-code/token-handler-${local.code_hash}.zip" : var.code_object_key
}

# 代码包对象（code_zip_path 非空时由本模块托管上传；key 带内容 hash，变化即新对象）
resource "huaweicloud_obs_bucket_object" "code" {
  count = var.code_zip_path != "" ? 1 : 0

  bucket = var.code_bucket_name
  key    = local.code_object_key
  source = var.code_zip_path
}

resource "huaweicloud_fgs_function" "token_handler" {
  name        = var.function_name
  app         = "token_handler"
  agency      = huaweicloud_identity_agency.functiongraph.name
  handler     = "handler.handler"
  memory_size = var.memory_size
  timeout     = var.timeout
  runtime     = var.runtime

  # 加入 VPC，使函数可访问同 VPC 内的宽表实例
  vpc_id     = var.vpc_id
  network_id = var.subnet_id

  enable_lts_log = true

  # 代码 zip 经对象存储下发
  code_type = "obs"
  code_url  = "https://${var.code_bucket_name}.obs.${var.region}.myhuaweicloud.com/${local.code_object_key}"

  user_data = jsonencode({
    TABLE_NAME               = var.token_table_name
    GEMINIDB_ENDPOINT        = var.geminidb_endpoint
    GEMINIDB_PORT            = tostring(var.geminidb_port)
    GEMINIDB_USER            = "rwuser"
    GEMINIDB_PASSWORD        = var.geminidb_password
    OBS_BUCKET_NAME          = var.obs_bucket_name
    OBS_OBJECT_KEY           = var.obs_object_key
    TOKEN_TTL_SECONDS        = tostring(var.token_ttl_seconds)
    PRESIGNED_URL_EXPIRATION = tostring(var.presigned_url_expiration)
    LOG_LEVEL                = var.log_level
    REGION                   = var.region
    # URL 预签名专用永久 AK/SK：委托临时 AK 生成的 URL 在对象存储签名校验层
    # 报 InvalidAccessKeyId（实测），永久 AK 签名校验一定通过。
    OBS_SIGNER_AK            = var.obs_signer_ak
    OBS_SIGNER_SK            = var.obs_signer_sk
  })

  tags = var.tags

  depends_on = [
    huaweicloud_identity_agency.functiongraph,
    huaweicloud_obs_bucket_object.code,
  ]

}
