#!/bin/bash

set -e

# 1. Initialize Terraform
echo "Initializing Terraform for cluster creation..."
cd terraform/cluster
terraform init

# 2. Apply Terraform configuration
echo "Applying Terraform configuration to create the cluster..."
# We target the cluster and networking resources first to ensure the Kubernetes provider
# can properly initialize with the cluster endpoint for subsequent resources (like ArgoCD).
terraform apply -target=google_container_cluster.primary \
  -target=google_compute_firewall.allow_nodes_to_public_master \
  -target=google_compute_router.nat_router \
  -target=google_compute_router_nat.nat \
  -auto-approve

echo "Cluster infrastructure created. Applying addons..."
terraform apply -auto-approve

echo "Cluster creation complete."
cd ../..
