#!/bin/bash
# TPU Workload Undeployment Script
# Purpose: Clean up all resources for a specific user's TPU workload

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

# Usage information
usage() {
    cat << EOF
Usage: $0 <username> [--force]

Delete all TPU workload resources for a specific user.

Arguments:
  username    Developer username whose resources will be deleted
  --force     Skip confirmation prompt (use with caution)

Examples:
  $0 alice
  $0 bob-dev --force

Resources deleted:
  - Deployment: sgl-tpu-<username>
  - Service: sgl-svc-<username>
  - ConfigMap: sgl-ssh-key-<username>

EOF
    exit 1
}

# Parse arguments
if [ $# -lt 1 ]; then
    error "Missing username argument"
    usage
fi

USER_NAME="$1"
FORCE_DELETE=false

if [ $# -eq 2 ] && [ "$2" == "--force" ]; then
    FORCE_DELETE=true
fi

# Validate username format
if ! [[ "$USER_NAME" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]]; then
    error "Invalid username format: $USER_NAME"
    exit 1
fi

# Check kubectl is installed
if ! command -v kubectl &> /dev/null; then
    error "kubectl not found"
    error "Please install kubectl: https://kubernetes.io/docs/tasks/tools/"
    exit 1
fi

# Check cluster connection
if ! kubectl cluster-info &> /dev/null; then
    error "Cannot connect to Kubernetes cluster"
    error "Please configure kubectl to connect to your GKE cluster"
    exit 1
fi

# Check if resources exist
info "Checking for existing resources for user: $USER_NAME"
echo ""

DEPLOYMENT_EXISTS=false
SERVICE_EXISTS=false
CONFIGMAP_EXISTS=false

if kubectl get deployment "sgl-tpu-$USER_NAME" &> /dev/null; then
    DEPLOYMENT_EXISTS=true
    info "Found Deployment: sgl-tpu-$USER_NAME"
fi

if kubectl get service "sgl-svc-$USER_NAME" &> /dev/null; then
    SERVICE_EXISTS=true
    info "Found Service: sgl-svc-$USER_NAME"
fi

if kubectl get configmap "sgl-ssh-key-$USER_NAME" &> /dev/null; then
    CONFIGMAP_EXISTS=true
    info "Found ConfigMap: sgl-ssh-key-$USER_NAME"
fi

# Check if any resources exist
if [ "$DEPLOYMENT_EXISTS" = false ] && [ "$SERVICE_EXISTS" = false ] && [ "$CONFIGMAP_EXISTS" = false ]; then
    warn "No resources found for user: $USER_NAME"
    warn "Nothing to delete"
    exit 0
fi

echo ""

# Show current resource status
info "Current resource status:"
echo "------------------------"
kubectl get pods,svc,configmap -l developer="$USER_NAME" 2>/dev/null || true
echo ""

# Confirmation prompt (unless --force)
if [ "$FORCE_DELETE" = false ]; then
    warn "This will delete all resources for user: $USER_NAME"
    warn "This action cannot be undone!"
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " CONFIRM

    if [ "$CONFIRM" != "yes" ]; then
        info "Deletion cancelled by user"
        exit 0
    fi
    echo ""
fi

# Delete resources
info "Deleting resources for user: $USER_NAME"
echo ""

DELETED_COUNT=0

# Delete by label (most reliable method)
if kubectl get all -l developer="$USER_NAME" &> /dev/null; then
    info "Deleting all resources with label developer=$USER_NAME..."
    if kubectl delete all -l developer="$USER_NAME" --timeout=60s; then
        ((DELETED_COUNT++))
        info "Deleted workload resources successfully"
    else
        warn "Some workload resources may not have been deleted"
    fi
    echo ""
fi

# Delete ConfigMap separately (not included in 'all')
if [ "$CONFIGMAP_EXISTS" = true ]; then
    info "Deleting ConfigMap: sgl-ssh-key-$USER_NAME"
    if kubectl delete configmap "sgl-ssh-key-$USER_NAME" --timeout=30s; then
        ((DELETED_COUNT++))
        info "ConfigMap deleted successfully"
    else
        warn "Failed to delete ConfigMap"
    fi
    echo ""
fi

# Wait for resources to be fully deleted
info "Waiting for resources to be fully deleted..."
sleep 3

# Verify deletion
REMAINING_RESOURCES=$(kubectl get all,configmap -l developer="$USER_NAME" 2>/dev/null | wc -l)

if [ "$REMAINING_RESOURCES" -le 1 ]; then
    echo ""
    echo "========================================"
    info "Cleanup Successful!"
    echo "========================================"
    echo ""
    info "All resources for user '$USER_NAME' have been deleted"
    echo ""
else
    echo ""
    warn "Some resources may still exist:"
    kubectl get all,configmap -l developer="$USER_NAME" 2>/dev/null || true
    echo ""
    warn "You may need to manually delete remaining resources:"
    echo "  kubectl delete deployment sgl-tpu-$USER_NAME"
    echo "  kubectl delete service sgl-svc-$USER_NAME"
    echo "  kubectl delete configmap sgl-ssh-key-$USER_NAME"
    exit 1
fi

info "Cleanup complete!"
