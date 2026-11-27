output "bucket_name" {
  description = "OBS 桶名"
  value       = huaweicloud_obs_bucket.sample.bucket
}

output "bucket_arn" {
  description = "OBS 桶 ARN（huaweicloud_obs_bucket 不暴露 arn，使用 obs 桶名带 region 后缀）"
  value       = "obs:${var.bucket_name}"
}

output "sample_object_key" {
  description = "示例对象键（仅当传 sample_image_path 时存在）"
  value       = var.sample_image_path != "" ? var.sample_object_key : ""
}

output "sample_object_uri" {
  description = "示例对象 OBS URI（仅当传 sample_image_path 时存在）"
  value       = var.sample_image_path != "" ? "obs://${huaweicloud_obs_bucket.sample.bucket}/${var.sample_object_key}" : ""
}