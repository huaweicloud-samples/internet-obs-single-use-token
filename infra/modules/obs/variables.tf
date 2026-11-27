variable "bucket_name" {
  description = "OBS 桶名（全局唯一，建议带项目前缀）"
  type        = string
}

variable "sample_object_key" {
  description = "示例图片在 OBS 中的对象键"
  type        = string
  default     = "sample-image.png"
}

variable "sample_image_path" {
  description = "本地示例图片路径（相对当前工作目录）；空字符串则不传示例对象"
  type        = string
  default     = ""
}

variable "tags" {
  description = "公共标签"
  type        = map(string)
  default     = {}
}