#!/bin/bash
# TPU Workload Deployment Script
# Purpose: Automate deployment of SSH-accessible GKE TPU development environment

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Print functions
info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Temporary file for generated YAML
TEMP_YAML=""

# Cleanup function
cleanup() {
    if [ -n "$TEMP_YAML" ] && [ -f "$TEMP_YAML" ]; then
        rm -f "$TEMP_YAML"
    fi
}
trap cleanup EXIT

# Usage information
usage() {
    cat << EOF
Usage: $0 <username> [ssh-public-key-file]

Deploy a TPU workload with SSH access via LoadBalancer.

Arguments:
  username              Developer username (for resource isolation)
                        Must be lowercase alphanumeric with hyphens
  ssh-public-key-file   Path to SSH public key file
                        Default: ~/.ssh/id_rsa.pub

Examples:
  $0 alice
  $0 alice ~/.ssh/id_ed25519.pub
  $0 bob-dev ~/.ssh/id_rsa.pub

EOF
    exit 1
}

# Validate arguments
if [ $# -lt 1 ]; then
    error "Missing username argument"
    usage
fi

USER_NAME="$1"
SSH_KEY_FILE="${2:-$HOME/.ssh/id_rsa.pub}"

# Validate username format (DNS-1123 compatible)
if ! [[ "$USER_NAME" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]]; then
    error "Invalid username format: $USER_NAME"
    error "Username must be lowercase alphanumeric with hyphens"
    error "Examples: alice, bob-dev, user123"
    exit 1
fi

# Validate SSH public key file exists
if [ ! -f "$SSH_KEY_FILE" ]; then
    error "SSH public key file not found: $SSH_KEY_FILE"
    error "Please specify a valid SSH public key file"
    exit 1
fi

# Read SSH public key
SSH_PUB_KEY=$(cat "$SSH_KEY_FILE")
if [ -z "$SSH_PUB_KEY" ]; then
    error "SSH public key file is empty: $SSH_KEY_FILE"
    exit 1
fi

info "Deployment Configuration:"
info "  Username: $USER_NAME"
info "  SSH Key:  $SSH_KEY_FILE"
echo ""

# Check kubectl is installed
if ! command -v kubectl &> /dev/null; then
    error "kubectl not found"
    error "Please install kubectl: https://kubernetes.io/docs/tasks/tools/"
    exit 1
fi

# Check cluster connection
info "Checking Kubernetes cluster connection..."
if ! kubectl cluster-info &> /dev/null; then
    error "Cannot connect to Kubernetes cluster"
    error "Please configure kubectl to connect to your GKE cluster"
    error "Example: gcloud container clusters get-credentials CLUSTER_NAME --region REGION"
    exit 1
fi

CURRENT_CONTEXT=$(kubectl config current-context)
info "Connected to cluster: $CURRENT_CONTEXT"
echo ""

# Generate temporary YAML with variable substitution
info "Generating deployment configuration..."
TEMP_YAML=$(mktemp)

# Export variables for envsubst
export USER_NAME
export SSH_PUB_KEY

# Use envsubst if available, otherwise fall back to sed
if command -v envsubst &> /dev/null; then
    envsubst < tpu-workload.yaml > "$TEMP_YAML"
else
    warn "envsubst not found, using sed (less reliable with special characters)"
    # Escape special characters for sed
    SSH_PUB_KEY_ESCAPED=$(echo "$SSH_PUB_KEY" | sed 's/[&/\]/\\&/g')
    sed -e "s/\${USER_NAME}/$USER_NAME/g" \
        -e "s|\${SSH_PUB_KEY}|$SSH_PUB_KEY_ESCAPED|g" \
        tpu-workload.yaml > "$TEMP_YAML"
fi

# Validate generated YAML syntax
if ! kubectl apply --dry-run=client -f "$TEMP_YAML" &> /dev/null; then
    error "Generated YAML has syntax errors"
    error "Please check the template file: tpu-workload.yaml"
    exit 1
fi

info "Configuration generated successfully"
echo ""

# Apply Kubernetes resources
info "Applying Kubernetes resources..."
if ! kubectl apply -f "$TEMP_YAML"; then
    error "Failed to apply Kubernetes resources"
    error "Check the error messages above for details"
    exit 1
fi

info "Resources applied successfully"
echo ""

# Wait for Pod to be ready
info "Waiting for Pod to be ready (timeout: 5 minutes)..."
if ! kubectl wait --for=condition=ready pod \
    -l app=sgl-tpu,developer="$USER_NAME" \
    --timeout=300s 2>/dev/null; then
    error "Pod failed to become ready within timeout"
    error ""
    error "Troubleshooting steps:"
    error "  1. Check Pod status:"
    error "     kubectl get pods -l developer=$USER_NAME"
    error ""
    error "  2. Check Pod events:"
    error "     kubectl describe pod -l developer=$USER_NAME"
    error ""
    error "  3. Check Pod logs:"
    error "     kubectl logs -l developer=$USER_NAME"
    error ""
    error "Common issues:"
    error "  - TPU resources not available (check node capacity)"
    error "  - Image pull errors (check network and credentials)"
    error "  - Resource quota exceeded"
    exit 1
fi

info "Pod is ready"
echo ""

# Wait for LoadBalancer External IP
info "Waiting for LoadBalancer IP (timeout: 5 minutes)..."
EXTERNAL_IP=""
for i in {1..60}; do
    EXTERNAL_IP=$(kubectl get svc "sgl-svc-$USER_NAME" \
        -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)

    if [ -n "$EXTERNAL_IP" ]; then
        break
    fi

    if [ $((i % 10)) -eq 0 ]; then
        info "Still waiting for LoadBalancer IP... ($i/60)"
    fi

    sleep 5
done

if [ -z "$EXTERNAL_IP" ]; then
    error "Failed to get LoadBalancer external IP within timeout"
    error ""
    error "Troubleshooting steps:"
    error "  1. Check Service status:"
    error "     kubectl get svc sgl-svc-$USER_NAME"
    error ""
    error "  2. Check Service events:"
    error "     kubectl describe svc sgl-svc-$USER_NAME"
    error ""
    error "Common issues:"
    error "  - Cloud provider doesn't support LoadBalancer"
    error "  - Insufficient quota for load balancers"
    error "  - Network configuration issues"
    exit 1
fi

# Display deployment results
echo ""
echo "========================================"
info "Deployment Successful!"
echo "========================================"
echo ""
echo "LoadBalancer IP:  $EXTERNAL_IP"
echo "SSH Connection:   ssh root@$EXTERNAL_IP"
echo ""
echo "Private Key:      Use the private key corresponding to:"
echo "                  $SSH_KEY_FILE"
echo ""

# Show resource status
echo "Resource Status:"
echo "----------------"
kubectl get pods,svc -l developer="$USER_NAME"
echo ""

# Show helpful commands
echo "Useful Commands:"
echo "----------------"
echo "View logs:"
echo "  kubectl logs -l developer=$USER_NAME -f"
echo ""
echo "Execute commands in container:"
echo "  kubectl exec -it deployment/sgl-tpu-$USER_NAME -- /bin/bash"
echo ""
echo "Check resource usage:"
echo "  kubectl top pod -l developer=$USER_NAME"
echo ""
echo "Delete deployment:"
echo "  kubectl delete -l developer=$USER_NAME"
echo "  OR use: ./undeploy.sh $USER_NAME"
echo ""

info "Setup complete! You can now connect via SSH:"
echo "  ssh root@$EXTERNAL_IP"
echo ""
