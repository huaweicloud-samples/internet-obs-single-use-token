###############################################################################
# 根入口：互联网场景 · OBS 单次使用 token 短期签名 URL 服务
# ----------------------------------------------------------------------------
# 资源分层（按依赖顺序）：
#   Layer 0: 网络底座（VPC / 子网 / 安全组）
#   Layer 1: 对象存储（OBS 桶 + 示例图片）
#   Layer 2: 宽表数据库（GeminiDB DynamoDB 兼容接口）
#   Layer 3: 函数计算（FunctionGraph，Python 3.9）
#   Layer 4: API 网关（APIG 专享版 + AppCode 鉴权 + 限流策略）
#   Layer 5: 桶策略（授权函数委托读取对象，签名 URL 生效前提）
#
# 顶层约定：
#   - region: cn-north-4
#   - provider: huaweicloud ~> 1.95
#   - 资源分层见下方 Layer 0–6 注释（网络 / 存储 / 数据库 / 函数 / 网关 / 桶策略 / 防火墙）
###############################################################################

terraform {
  required_version = ">= 1.5"

  required_providers {
    huaweicloud = {
      source  = "huaweicloud/huaweicloud"
      version = "~> 1.95"
    }
  }
}

provider "huaweicloud" {
  region = var.region
}

# ============================================================================
# Layer 0: 网络底座
# ============================================================================

resource "huaweicloud_vpc" "main" {
  name = "${var.project_name}-vpc"
  cidr = var.vpc_cidr

  tags = var.tags

  timeouts {
    delete = "60m"
  }
}

resource "huaweicloud_vpc_subnet" "main" {
  name       = "${var.project_name}-subnet"
  vpc_id     = huaweicloud_vpc.main.id
  cidr       = var.subnet_cidr
  gateway_ip = cidrhost(var.subnet_cidr, 1)

  tags = var.tags

  timeouts {
    delete = "60m"
  }
}

resource "huaweicloud_networking_secgroup" "main" {
  name        = "${var.project_name}-sg"
  description = "Security group for ${var.project_name}"
}

# 当前账号（取 domain id，用于 OBS 桶策略 Principal）
data "huaweicloud_account" "current" {}

# ============================================================================
# Layer 1: OBS 桶
# ============================================================================

module "obs" {
  source = "./modules/obs"

  bucket_name       = var.obs_bucket_name
  sample_object_key = var.obs_object_key
  sample_image_path = var.sample_image_path
  tags              = var.tags
}

# ============================================================================
# Layer 2: GeminiDB（DynamoDB 兼容接口）
# ============================================================================

module "geminidb" {
  source = "./modules/geminidb"

  instance_name        = var.geminidb_instance_name
  region               = var.region
  vpc_id               = huaweicloud_vpc.main.id
  subnet_id            = huaweicloud_vpc_subnet.main.id
  security_group_id    = huaweicloud_networking_secgroup.main.id
  geminidb_password    = var.geminidb_password
  geminidb_flavor_spec = var.geminidb_flavor_spec
  availability_zone    = var.geminidb_availability_zone
  node_num             = var.geminidb_node_num
  storage_size         = var.geminidb_storage_size
  tags                 = var.tags
}

# ============================================================================
# Layer 3: FunctionGraph 函数
# ============================================================================

module "functiongraph" {
  source = "./modules/functiongraph"

  function_name            = var.function_name
  region                   = var.region
  vpc_id                   = huaweicloud_vpc.main.id
  subnet_id                = huaweicloud_vpc_subnet.main.id
  code_bucket_name         = var.code_bucket_name
  code_object_key          = var.code_object_key
  code_zip_path            = var.code_zip_path
  memory_size              = var.function_memory_size
  timeout                  = var.function_timeout
  token_table_name         = var.token_table_name
  geminidb_endpoint        = module.geminidb.endpoint
  geminidb_port            = module.geminidb.port
  geminidb_password        = var.geminidb_password
  obs_bucket_name          = module.obs.bucket_name
  obs_object_key           = var.obs_object_key
  token_ttl_seconds        = var.token_ttl_seconds
  presigned_url_expiration = var.presigned_url_expiration
  log_level                = var.function_log_level
  obs_signer_ak            = var.obs_signer_access_key_id
  obs_signer_sk            = var.obs_signer_secret_access_key
  tags                     = var.tags
}

# ============================================================================
# Layer 4: APIG 专享版（API 网关 + AppCode 鉴权 + 限流）
# ============================================================================

module "apig" {
  source = "./modules/apig"

  api_name           = "${var.project_name}-api"
  region             = var.region
  vpc_id             = huaweicloud_vpc.main.id
  subnet_id          = huaweicloud_vpc_subnet.main.id
  security_group_id  = huaweicloud_networking_secgroup.main.id
  availability_zones = var.apig_availability_zones
  function_urn       = module.functiongraph.function_urn
  appcode            = var.apig_appcode
  environment        = var.apig_environment
  max_api_requests   = var.apig_max_api_requests
  throttle_period    = var.apig_throttle_period
  period_unit        = var.apig_throttle_period_unit
  tags               = var.tags
}

# ============================================================================
# Layer 5: OBS 桶策略（函数委托读对象）
# ----------------------------------------------------------------------------
# 函数以委托临时凭证对签名 URL 进行签名；客户端持 URL 取对象时，OBS 按签名
# 主体（委托）的权限校验，因此必须显式授予委托 GetObject 权限。
# ============================================================================

resource "huaweicloud_obs_bucket_policy" "agency_read" {
  bucket = module.obs.bucket_name

  policy = jsonencode({
    Statement = [
      {
        Sid    = "AllowAgencyReadForSignedUrl"
        Effect = "Allow"
        Principal = {
          ID = ["domain/${data.huaweicloud_account.current.id}:agency/${module.functiongraph.agency_name}"]
        }
        Action   = ["GetObject"]
        Resource = ["${module.obs.bucket_name}/*"]
      },
    ]
  })
}

# ============================================================================
# Layer 6: WAF（可选，默认关闭）
# ----------------------------------------------------------------------------
# 生产环境的 WAF 为可选付费服务，与默认关闭约定一致，
# 故默认不启用；默认的速率限制由接入层限流策略承担（见 apig 模块）。
# ============================================================================

module "waf" {
  source = "./modules/waf"

  enable_waf       = var.enable_waf
  policy_name      = "${var.project_name}-waf"
  protection_level = var.waf_protection_level
  domain_name      = var.waf_domain_name
  origin_address   = module.apig.ingress_address
  origin_port      = 443
}

