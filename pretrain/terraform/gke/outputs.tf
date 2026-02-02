output "cluster_endpoint" {
  description = "The endpoint of the GKE cluster"
  value       = google_container_cluster.primary.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "The CA certificate of the GKE cluster"
  value       = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "tpu_node_pool_name" {
  description = "The name of the TPU node pool"
  value       = google_container_node_pool.tpu_node_pool.name
}

output "system_node_pool_name" {
  description = "The name of the system node pool"
  value       = google_container_node_pool.system_node_pool.name
}
