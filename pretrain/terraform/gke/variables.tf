variable "project_id" {
  description = "The project ID to host the cluster in"
  type        = string
  default     = "tpu-service-473302"
}

variable "region" {
  description = "The region to host the cluster in"
  type        = string
  default     = "us-central1"
}

variable "cluster_name" {
  description = "The name of the GKE cluster"
  type        = string
  default     = "test-ant-pre-train"
}

variable "node_locations" {
  description = "The comma-separated list of one or more zones where GKE creates the node pool"
  type        = list(string)
  default     = ["us-central1-c"]
}

# TPU v6e node pool variables
variable "tpu_node_pool_name_v6e" {
  description = "The name of the TPU node pool"
  type        = string
  default     = "tpu-v6e-node-pool"
}

variable "tpu_machine_type_v6e" {
  description = "The type of TPU machine to use"
  type        = string
  default     = "ct6e-standard-4t"
}

variable "tpu_topology_v6e" {
  description = "The TPU topology (e.g., 2x4, 4x8)"
  type        = string
  default     = "2x4"
}

variable "tpu_v6e_min_node_count" {
  description = "Minimum number of TPU nodes for autoscaling"
  type        = number
  default     = 1
}

variable "tpu_v6e_max_node_count" {
  description = "Maximum number of TPU nodes (must equal slice size: topology chips / chips per node)"
  type        = number
  default     = 8
}

# TPU v7x node pool variables
variable "tpu_v7x_node_pool_name" {
  description = "The name of the TPU node pool"
  type        = string
  default     = "tpu-v7x-node-pool"
}

variable "tpu_v7x_machine_type" {
  description = "The type of TPU machine to use"
  type        = string
  default     = "tpu7x-standard-4t"
}

variable "tpu_v7x_topology" {
  description = "The TPU topology (e.g., 2x2x1, 2x2x2)"
  type        = string
  default     = "2x2x1"
}

variable "tpu_v7x_min_node_count" {
  description = "Minimum number of TPU nodes for autoscaling"
  type        = number
  default     = 0
}

variable "tpu_v7x_max_node_count" {
  description = "Maximum number of TPU nodes (must equal slice size: topology chips / chips per node)"
  type        = number
  default     = 4
}

variable "tpu_spot" {
  description = "Whether to use spot instances for TPU nodes"
  type        = bool
  default     = true
}

# CPU node pool variables
variable "cpu_node_pool_name" {
  description = "The name of the CPU node pool"
  type        = string
  default     = "system-node-pool"
}

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
