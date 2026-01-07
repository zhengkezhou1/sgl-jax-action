provider "google" {
  project = var.project_id
  region  = var.region
}

data "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.region
  project  = var.project_id
}

# CPU node pool for system components (kube-dns, metrics-server, etc.)
resource "google_container_node_pool" "cpu_node_pool" {
  project    = var.project_id
  cluster    = data.google_container_cluster.primary.name
  name       = "cpu-pool"
  location   = data.google_container_cluster.primary.location
  node_count = var.cpu_node_count

  autoscaling {
    min_node_count = var.cpu_min_nodes
    max_node_count = var.cpu_max_nodes
  }

  node_config {
    machine_type = var.cpu_machine_type
    disk_size_gb = 50
    disk_type    = "pd-standard"

    # OAuth scopes for the node
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    # Metadata to disable legacy metadata endpoints
    metadata = {
      disable-legacy-endpoints = "true"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
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

    # Enable the GKE Metadata Server for Workload Identity
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }
}