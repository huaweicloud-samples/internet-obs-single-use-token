###############################################################################
# OBS 模块
# ----------------------------------------------------------------------------
# 落地 OBS 桶（私有 + 桶级服务端加密 + 版本控制）+ 示例图片上传。
#
# 访问控制说明：
#   桶 ACL 取 private，且不附加任何公共读写策略，匿名请求无法访问桶内对象。
#   目标区域不提供桶级公共访问阻断子资源（调用返回 405 Method Not Allowed），
#   故该护栏未以独立资源形式落地，改由「私有 ACL + 不附加公共策略」保证等效
#   结果；如后续在支持该子资源的区域部署，可补回对应资源。
#
# 内容变更检测：
#   不使用对象 etag 字段——桶级加密下服务端返回的 etag 与本地摘要不一致，
#   会造成每次 plan 都出现「待更新」差异；改由指纹资源触发对象重建。
###############################################################################

terraform {
  required_providers {
    huaweicloud = {
      source = "huaweicloud/huaweicloud"
    }
  }
}

resource "huaweicloud_obs_bucket" "sample" {
  bucket        = var.bucket_name
  acl           = "private"
  force_destroy = true
  versioning    = true

  # 桶级服务端加密（AES256）
  encryption    = true
  sse_algorithm = "AES256"

  tags = merge(var.tags, {
    Name = var.bucket_name
  })
}

# 示例图片指纹：文件内容变化时触发对象重建
resource "terraform_data" "sample_image" {
  triggers_replace = [
    var.sample_image_path != "" ? filemd5(var.sample_image_path) : "",
  ]
}

# 上传示例图片到桶根；sample_image_path 为空字符串时跳过
resource "huaweicloud_obs_bucket_object" "sample_image" {
  count = var.sample_image_path != "" ? 1 : 0

  bucket       = huaweicloud_obs_bucket.sample.bucket
  key          = var.sample_object_key
  source       = var.sample_image_path
  content_type = "image/png"

  tags = merge(var.tags, {
    Name = var.sample_object_key
  })

  lifecycle {
    replace_triggered_by = [terraform_data.sample_image]
  }
}
