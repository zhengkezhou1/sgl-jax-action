
provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.region

  remove_default_node_pool = true
  initial_node_count       = 1
}

output "cluster_name" {
  value = google_container_cluster.primary.name
}

output "region" {
  value = var.region
}

output "project_id" {
  value = var.project_id
}
