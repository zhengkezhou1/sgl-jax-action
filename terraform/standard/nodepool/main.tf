provider "google" {
  project = var.project_id
  region  = var.region
}

data "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.region
  project  = var.project_id
}

# default(2x2) TPU node pool for workloads
resource "google_container_node_pool" "single_host_tpu_node_pool" {
  project        = var.project_id
  cluster        = data.google_container_cluster.primary.name
  name           = "single-host-resources"
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

# (2x4) TPU node pool for workloads
resource "google_container_node_pool" "multi_host_tpu_node_pool" {
  project        = var.project_id
  cluster        = data.google_container_cluster.primary.name
  name           = "multi-host-resources"
  location       = data.google_container_cluster.primary.location
  node_locations = var.node_locations
  # node_count omitted - autoscaling will manage (valid values: 0 or 2 for 2x4 topology)

  node_config {
    machine_type = "ct6e-standard-4t"
    spot         = false
  }

  placement_policy {
    type         = "COMPACT"
    tpu_topology = "2x4"
  }

  autoscaling {
    min_node_count = 0
    max_node_count = 2
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
