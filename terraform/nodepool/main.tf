provider "google" {
  project = var.project_id
  region  = var.region
}

data "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.region
  project  = var.project_id
}

resource "google_container_node_pool" "tpu_node_pool" {
  project            = var.project_id
  cluster            = data.google_container_cluster.primary.name
  name               = var.pool_name
  location           = data.google_container_cluster.primary.location
  node_locations     = var.node_locations
  node_count         = 1

  node_config {
    machine_type = var.machine_type
    spot         = false
    # flex_start is a feature in preview and might not be available in all regions.
    # It has been commented out. Uncomment if you are in a region that supports it.
    # flex_start = false
  }
}