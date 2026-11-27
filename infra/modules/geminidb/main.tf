###############################################################################
# GeminiDB 模块（DynamoDB 兼容接口）
# ----------------------------------------------------------------------------
# 落地 GeminiDB 兼容 DynamoDB 接口实例，承载单次使用 token 表
# （hash_key = token，含 TTL 属性 ttl）。
#
# 要点：
#   - datastore.type 必须全小写 "dynamodb"
#   - datastore.version 必须为空字符串（兼容接口对外不提供版本号）
#   - flavor.storage 必须全大写 "ULTRAHIGH"
#   - 集群形态 availability_zone 是逗号分隔的字符串（不是 list），需 3 个可用区
#   - 数据面只认实例账号 rwuser + 实例管理员密码，不接受统一身份认证的临时
#     凭证，也不支持 securityToken
#   - 集群形态数据面端口为 80（单节点形态才是 8000）
###############################################################################

terraform {
  required_providers {
    huaweicloud = {
      source = "huaweicloud/huaweicloud"
    }
  }
}

resource "huaweicloud_geminidb_instance" "token_store" {
  name              = var.instance_name
  mode              = "Cluster"
  charging_mode     = "postPaid"
  password          = var.geminidb_password
  availability_zone = var.availability_zone
  vpc_id            = var.vpc_id
  subnet_id         = var.subnet_id
  security_group_id = var.security_group_id

  datastore {
    type           = "dynamodb"
    storage_engine = "rocksDB"
    version        = ""
  }

  flavor {
    num       = var.node_num
    size      = var.storage_size
    spec_code = var.geminidb_flavor_spec
    storage   = "ULTRAHIGH"
  }

  tags = merge(var.tags, {
    Name = var.instance_name
  })
}
