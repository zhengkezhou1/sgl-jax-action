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
  default     = "pkg-service"
}

variable "node_locations" {
  description = "The comma-separated list of one or more zones where GKE creates the node pool"
  type        = list(string)
  default     = ["us-central1-a","us-central1-b","us-central1-c", "us-central1-f"]
}

variable "tpu_v7x_machine_type" {
  description = "The type of TPU machine to use"
  type        = string
  default     = "tpu7x-standard-4t"
}

variable "tpu_spot" {
  description = "Whether to use spot instances for TPU nodes"
  type        = bool
  default     = false
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