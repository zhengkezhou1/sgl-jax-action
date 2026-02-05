variable "project_id" {
  description = "The GCP project ID"
  type        = string
  default     = "tpu-service-473302"
}

variable "region" {
  description = "The GCP region"
  type        = string
  default     = "us-central1"
}

variable "cluster_name" {
  description = "The GKE cluster name"
  type        = string
  default     = "test-ant-pre-train"
}

variable "grafana_admin_password" {
  description = "Grafana admin password"
  type        = string
  sensitive   = true
}
