
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
  description = "the name of the TPU node pool to create"
  type        = string
  default     = "tpu-v6e-dev"
}

# CPU node pool variables
variable "cpu_machine_type" {
  description = "Machine type for CPU nodes (system components)"
  type        = string
  default     = "e2-medium"
}

variable "cpu_node_count" {
  description = "Initial number of CPU nodes"
  type        = number
  default     = 1
}

variable "cpu_min_nodes" {
  description = "Minimum number of CPU nodes in autoscaling"
  type        = number
  default     = 1
}

variable "cpu_max_nodes" {
  description = "Maximum number of CPU nodes in autoscaling"
  type        = number
  default     = 3
}

# TPU node pool variables
variable "tpu_node_count" {
  description = "Number of TPU nodes"
  type        = number
  default     = 1
}
