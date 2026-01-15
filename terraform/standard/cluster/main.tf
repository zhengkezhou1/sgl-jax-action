provider "google" {
  project = var.project_id
  region  = var.region
}

# Look up the default network and subnetwork for the cluster
data "google_compute_network" "default" {
  name    = "default"
  project = var.project_id
}
data "google_compute_subnetwork" "default" {
  name    = "default"
  region  = var.region
  project = var.project_id
}

# Create a private GKE cluster with a public endpoint.
# This is a common configuration enforced by organization policies.
resource "google_container_cluster" "primary" {
  name       = var.cluster_name
  location   = var.region
  project    = var.project_id
  network    = data.google_compute_network.default.self_link
  subnetwork = data.google_compute_subnetwork.default.self_link

  # Explicitly disable deletion protection for this development environment
  deletion_protection = false

  initial_node_count = 1

  release_channel {
    channel = "RAPID"
  }

  remove_default_node_pool = true
}

resource "null_resource" "configure_kubectl" {
  provisioner "local-exec" {
    command = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --region ${var.region} --project ${var.project_id} && kubectl config set-context --current --namespace=default"
  }

  depends_on = [google_container_cluster.primary]
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
