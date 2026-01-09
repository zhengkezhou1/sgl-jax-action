#!/bin/bash

set -e

# 1. Initialize Terraform
echo "Initializing Terraform for node pool creation..."
cd ./terraform/nodepool
terraform init

# 2. Apply Terraform configuration
echo "Applying Terraform configuration to create the node pool..."
terraform apply -auto-approve

echo "Node pool creation complete."
cd ../..
