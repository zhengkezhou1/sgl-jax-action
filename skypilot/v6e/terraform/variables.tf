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

variable "cluster_name" {
  description = "The name of the GKE cluster"
  type        = string
  default     = "tpu-v6e-pre-train"
}

variable "node_locations" {
  description = "The comma-separated list of one or more zones where GKE creates the node pool"
  type        = list(string)
  default     = ["asia-northeast1-b"]
}

# TPU node pool variables
variable "tpu_machine_type" {
  description = "The type of TPU machine to use"
  type        = string
  default     = "ct6e-standard-4t"
}

variable "tpu_topology" {
  description = "The TPU topology (e.g., 2x4, 4x8)"
  type        = string
  default     = "2x2"
}

variable "tpu_min_node_count" {
  description = "Minimum number of TPU nodes for autoscaling"
  type        = number
  default     = 1
}

variable "tpu_max_node_count" {
  description = "Maximum number of TPU nodes (must equal slice size: topology chips / chips per node)"
  type        = number
  default     = 2
}

# CPU node pool variables
variable "cpu_machine_type" {
  description = "Machine type for CPU nodes (system components)"
  type        = string
  default     = "e2-highmem-8"
}

variable "cpu_node_count" {
  description = "Number of CPU nodes for system components"
  type        = number
  default     = 1
}
