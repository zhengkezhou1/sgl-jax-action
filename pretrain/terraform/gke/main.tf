terraform {
  required_version = ">= 1.14.3"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
  }
  backend "gcs" {
    bucket = "tpu-service-terraform-state"
    prefix = "pretrain/gke"
  }
}

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

  initial_node_count = var.cpu_node_count

  release_channel {
    channel = "RAPID"
  }

  # Enable Workload Identity to allow Kubernetes service accounts to act as
  # Google Cloud service accounts. This provides a more secure way for workloads
  # to access Google Cloud APIs without using node service account credentials.
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  remove_default_node_pool = true
}

resource "null_resource" "configure_kubectl" {
  provisioner "local-exec" {
    command = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --region ${var.region} --project ${var.project_id} && kubectl config set-context --current --namespace=default"
  }

  depends_on = [google_container_cluster.primary]
}

# Signle host TPU v6e node pool for workloads
resource "google_container_node_pool" "signle_host_v6e_2x2_node_pool" {
  project        = var.project_id
  cluster        = google_container_cluster.primary.name
  name           = "signle-host-v6e-2x2-node-pool"
  location       = google_container_cluster.primary.location
  node_locations = var.node_locations
  node_count     = var.tpu_v6e_min_node_count

  node_config {
    machine_type = var.tpu_v6e_machine_type
    spot         = var.tpu_spot
  }

  placement_policy {
    type         = "COMPACT"
    tpu_topology = "2x2"
  }

  autoscaling {
    min_node_count = var.tpu_v6e_min_node_count
    max_node_count = var.tpu_v6e_max_node_count
  }
}

# Signle host TPU v7x node pool for workloads
resource "google_container_node_pool" "signle_host_v7x_2x2x1_node_pool" {
  project        = var.project_id
  cluster        = google_container_cluster.primary.name
  name           = "signle-host-v7x-2x2x1-node-pool"
  location       = google_container_cluster.primary.location
  node_locations = var.node_locations
  node_count     = var.tpu_v7x_min_node_count

  node_config {
    machine_type = var.tpu_v7x_machine_type
    spot         = var.tpu_spot
  }

  autoscaling {
    min_node_count = var.tpu_v7x_min_node_count
    max_node_count = var.tpu_v7x_max_node_count
  }
}

resource "google_compute_resource_policy" "multi-host-tpu7x-resource-policy" {
  name   = "multi-host-tpu7x-resource-policy"
  region = var.region
  workload_policy {
    type = "HIGH_THROUGHPUT"
    accelerator_topology = "2x2x2"
  }
}

#Multi Host TPU v7x node pool for workloads
resource "google_container_node_pool" "multi_host_v7x_2x2x2_node_pool" {
  project        = var.project_id
  cluster        = google_container_cluster.primary.name
  name           = "multi-host-v7x-2x2x2-node-pool"
  location       = google_container_cluster.primary.location
  node_locations = var.node_locations
  node_count     = 2

  node_config {
    machine_type = var.tpu_v7x_machine_type
    spot         = var.tpu_spot
  }

  placement_policy {
    policy_name = "multi-host-tpu7x-resource-policy"
    type = "COMPACT"
  }

  autoscaling {
    max_node_count       = 2
    location_policy      = "ANY"
  }
}

# CPU node pool for k8s system components
resource "google_container_node_pool" "system_node_pool" {
  project        = var.project_id
  cluster        = google_container_cluster.primary.name
  name           = var.cpu_node_pool_name
  location       = google_container_cluster.primary.location
  node_locations = var.node_locations
  node_count     = var.cpu_node_count

  node_config {
    machine_type = var.cpu_machine_type

    # Enable GKE Metadata Server to support Workload Identity.
    # This allows pods to authenticate as Google Cloud service accounts
    # instead of using the node's service account.
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
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
