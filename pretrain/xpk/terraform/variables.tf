variable "project_id" {
  description = "The project ID to host the cluster in"
  type        = string
  default = "tpu-service-473302"
}

variable "region" {
  description = "The region to host the cluster in"
  type        = string
  default     = "asia-northeast1"
}