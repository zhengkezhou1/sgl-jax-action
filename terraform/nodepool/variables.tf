
variable "project_id" {
  description = "The project ID to host the cluster in"
  type        = string
}

variable "region" {
  description = "The region to host the cluster in"
  type        = string
  default     = "asia-northeast1"
}

variable "cluster_name" {
  description = "The name of the GKE cluster"
  type        = string
  default     = "tpu-cluster"
}

variable "machine_type" {
  description = "the type of TPU machine to use"
  type = string
  default = "ct6e-standard-1t"
}

variable "node_locations" {
  description = "the comma-separated list of one or more zones where GKE creates the node pool"
  type = list(string)
  default = [ "asia-northeast1-b" ]
}

variable "pool_name" {
  description = "the name of the node pool to create"
  type = string
  default = "default-pool"
}
