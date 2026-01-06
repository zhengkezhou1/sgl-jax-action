#!/bin/bash

set -e

# Check if SSH public key path is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <path-to-your-ssh-public-key>"
  exit 1
fi

SSH_PUB_KEY_PATH=$1

# Check if the public key file exists
if [ ! -f "$SSH_PUB_KEY_PATH" ]; then
  echo "Error: SSH public key file not found at $SSH_PUB_KEY_PATH"
  exit 1
fi

USER_NAME=$(whoami)
SSH_PUB_KEY_CONTENT=$(cat "$SSH_PUB_KEY_PATH")

# Get the directory of the script itself
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
# Go to the terraform/workload directory relative to the script's location
WORKLOAD_DIR="$SCRIPT_DIR/../terraform/workload"

echo "Changing to the '$WORKLOAD_DIR' directory..."
cd "$WORKLOAD_DIR"

# Force clean the local Terraform environment to prevent caching issues
echo "Forcing a clean of the Terraform environment..."
rm -rf .terraform*

# Initialize Terraform
echo "Initializing Terraform for the workload..."
terraform init

# Apply Terraform configuration to deploy the workload
echo "Applying Terraform configuration to deploy the workload..."
# We pass the username and ssh key as variables on the command line
terraform apply -auto-approve \
  -var="user_name=$USER_NAME" \
  -var="ssh_pub_key=$SSH_PUB_KEY_CONTENT"

echo "Deployment complete."
echo "You can find the external IP of your TPU workload by running:"
# Note: kubectl must be configured to the correct cluster context for this to work.
echo "kubectl get svc sgl-svc-$USER_NAME -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"