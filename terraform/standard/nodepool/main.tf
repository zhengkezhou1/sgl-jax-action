provider "google" {
  project = var.project_id
  region  = var.region
}

data "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.region
  project  = var.project_id
}

# TPU node pool for workloads
resource "google_container_node_pool" "tpu_node_pool" {
  project        = var.project_id
  cluster        = data.google_container_cluster.primary.name
  name           = var.pool_name
  location       = data.google_container_cluster.primary.location
  node_locations = var.node_locations
  node_count     = var.tpu_node_count

  node_config {
    machine_type = var.machine_type
    spot         = false
  }

  autoscaling {
    min_node_count = var.min_node_count
    max_node_count = var.max_node_count
  }
}

# CPU node pool for k8s system components
resource "google_container_node_pool" "system_node_pool" {
  project        = var.project_id
  cluster        = data.google_container_cluster.primary.name
  name           = "system-node-pool"
  location       = data.google_container_cluster.primary.location
  node_locations = var.node_locations
  node_count     = var.min_node_count

  node_config {
    machine_type = var.cpu_machine_type
  }
}
