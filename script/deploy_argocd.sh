#!/bin/bash
set -e

# Color definitions
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Deploy or Update ArgoCD (LoadBalancer mode) ===${NC}"

# 1. Execute Terraform
echo -e "\n${BLUE}[1/3] Running Terraform... (configuring LoadBalancer)${NC}"
cd terraform/cluster
terraform init -upgrade
terraform apply -auto-approve

# 2. Get cluster credentials from Terraform outputs
echo -e "\n${BLUE}[2/3] Getting cluster credentials...${NC}"
CLUSTER_NAME=$(terraform output -raw cluster_name)
REGION=$(terraform output -raw region)
PROJECT_ID=$(terraform output -raw project_id)
cd ../.. # Back to project root

gcloud container clusters get-credentials "$CLUSTER_NAME" --region "$REGION" --project "$PROJECT_ID"

# 3. Get and display ArgoCD login information
echo -e "\n${BLUE}[3/3] Waiting for external IP allocation...${NC}"

# Wait for ArgoCD Server service to be assigned an external IP
LB_IP=""
echo -n "Waiting for LoadBalancer IP."
while [ -z "$LB_IP" ]; do
    sleep 5
    echo -n "."
    # Try to get IP
    LB_IP=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
done
echo ""

ADMIN_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

echo -e "\n${GREEN}================== ArgoCD Ready ==================${NC}"
echo -e "URL:       http://${LB_IP}"
echo -e "Username:  admin"
echo -e "Password:  ${GREEN}${ADMIN_PASSWORD}${NC}"
echo -e "${GREEN}==================================================${NC}"
