#!/bin/bash

set -e

# 1. Initialize Terraform
echo "Initializing Terraform for cluster creation..."
cd ../terraform/cluster
terraform init

# 2. Apply Terraform configuration
echo "Applying Terraform configuration to create the cluster..."
terraform apply -auto-approve

echo "Cluster creation complete."
cd ../..
