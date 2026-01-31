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

# (2x4) TPU node pool for workloads
resource "google_container_node_pool" "multi_host_tpu_node_pool" {
  project        = var.project_id
  cluster        = google_container_cluster.primary.name
  name           = "hongmao-dev-v6e"
  location       = google_container_cluster.primary.location
  node_locations = var.node_locations
  node_count     = 1

  node_config {
    machine_type = var.tpu_machine_type
    spot         = false
  }

  # placement_policy {
  #   type         = "COMPACT"
  #   tpu_topology = var.tpu_topology
  # }

  autoscaling {
    min_node_count = var.tpu_min_node_count
    max_node_count = var.tpu_max_node_count
  }
}

# CPU node pool for k8s system components
resource "google_container_node_pool" "system_node_pool" {
  project        = var.project_id
  cluster        = google_container_cluster.primary.name
  name           = "system-node-pool"
  location       = google_container_cluster.primary.location
  node_locations = var.node_locations
  node_count     = var.cpu_node_count

  node_config {
    machine_type = var.cpu_machine_type
  }
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
