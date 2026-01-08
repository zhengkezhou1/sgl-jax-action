#!/bin/bash
set -e

# 颜色定义
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== 部署或更新 ArgoCD 至 GKE 集群 ===${NC}"

# 1. 执行 Terraform
echo -e "\n${BLUE}[1/3] 正在执行 Terraform... (这将同步 GKE 集群和 ArgoCD 的状态)${NC}"
cd terraform/cluster
terraform init
terraform apply -auto-approve

# 2. 从 Terraform 输出获取集群信息
echo -e "\n${BLUE}[2/3] 正在获取集群凭证...${NC}"
CLUSTER_NAME=$(terraform output -raw cluster_name)
REGION=$(terraform output -raw region)
PROJECT_ID=$(terraform output -raw project_id)
cd ../.. # 返回项目根目录

gcloud container clusters get-credentials "$CLUSTER_NAME" --region "$REGION" --project "$PROJECT_ID"

# 3. 获取并显示 ArgoCD 登录信息
echo -e "\n${BLUE}[3/3] 正在获取 ArgoCD 登录信息...${NC}"
echo -e "请等待 ArgoCD 服务完全就绪..."

# 等待 argocd-server deployment 可用
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

ADMIN_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

echo -e "\n${GREEN}================== ArgoCD 准备就绪 ==================${NC}"
echo -e "访问地址:  https://localhost:8080 (需要开启端口转发)"
echo -e "用户:      admin"
echo -e "密码:      ${GREEN}${ADMIN_PASSWORD}${NC}"
echo -e "\n${BLUE}请在新终端中运行以下命令以访问 UI:${NC}"
echo -e "kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo -e "${GREEN}=====================================================${NC}"
