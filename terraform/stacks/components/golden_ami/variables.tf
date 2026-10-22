variable "region" {
  type = string
}

variable "bucket_name" {
  type    = string
  default = "infragraph-demo-webapp"
}

variable "channel_name" {
  type    = string
  default = "production"
}
