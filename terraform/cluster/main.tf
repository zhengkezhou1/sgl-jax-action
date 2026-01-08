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
  name        = var.cluster_name
  location    = var.region
  project     = var.project_id
  network     = data.google_compute_network.default.self_link
  subnetwork  = data.google_compute_subnetwork.default.self_link

  # Explicitly disable deletion protection for this development environment
  deletion_protection = false

  remove_default_node_pool = true
  initial_node_count       = 1

  # Define the private cluster configuration
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false # The master has a public IP
    master_global_access_config {
      enabled = true
    }
  }

  # Enable Workload Identity, which is required for Pods to access GCP services
  # and metadata securely.
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
}

# This firewall rule is CRITICAL for private clusters.
# It allows GKE nodes to communicate with the GKE master's public endpoint
# for essential services like DNS resolution.
resource "google_compute_firewall" "allow_nodes_to_public_master" {
  name      = "${var.cluster_name}-nodes-to-public-master"
  network   = data.google_compute_network.default.self_link
  project   = var.project_id
  direction = "EGRESS"
  priority  = 1000

  allow {
    protocol = "all"
  }

  # Source is dynamically set to the node's subnetwork IP range.
  source_ranges = [data.google_compute_subnetwork.default.ip_cidr_range]

  # Destination is the dynamically retrieved public IP of the GKE master.
  # We access the public_endpoint from the private_cluster_config block.
  destination_ranges = ["${google_container_cluster.primary.private_cluster_config[0].public_endpoint}/32"]

  description = "Allow GKE nodes to communicate with the GKE master's public endpoint for core services."
}

# Create a Cloud Router for NAT
resource "google_compute_router" "nat_router" {
  name    = "${var.cluster_name}-nat-router"
  region  = var.region
  network = data.google_compute_network.default.id
  project = var.project_id
}

# Create Cloud NAT to allow private nodes to access the internet
resource "google_compute_router_nat" "nat" {
  name                               = "${var.cluster_name}-nat"
  router                             = google_compute_router.nat_router.name
  region                             = var.region
  project                            = var.project_id
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  # Optimize for high pod count scenarios
  # Each NAT IP provides ~64k ports, default is 64 ports per VM
  # Increasing min_ports_per_vm allows more concurrent connections per node
  min_ports_per_vm = 128

  # Enable dynamic port allocation for better resource utilization
  enable_dynamic_port_allocation      = true
  enable_endpoint_independent_mapping = false

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
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
