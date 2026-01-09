# sgl-jax-action

GKE TPU 集群部署和管理工具集，采用 GitOps (ArgoCD) 模式管理调度服务，并通过 HTTP API 提交和管理 TPU 任务。

## 前置要求

1. **GCP 账号**：已创建项目并启用 GKE、Compute Engine、Cloud NAT API。
2. **本地工具**：
   - Terraform >= 1.0
   - gcloud CLI
   - kubectl
   - curl
3. **认证**：
   ```bash
   gcloud auth application-default login
   gcloud config set project <YOUR_PROJECT_ID>
   ```

## 快速开始

### 1. 创建 GKE 集群

首先创建基础网络和 GKE 控制平面：

```bash
./script/apply_cluster.sh
```

### 2. 创建节点池

创建用于运行 TPU 任务的专用节点池（包含 CPU 和 TPU 节点）：

```bash
./script/apply_nodepool.sh
```

### 3. 部署 ArgoCD

在集群就绪后，部署 ArgoCD 以实现 GitOps 管理：

```bash
./script/deploy_argocd.sh
```
*脚本会自动输出 ArgoCD 的访问地址和登录凭证。*

### 4. 部署调度服务 (Scheduler)

通过 ArgoCD 部署 Scheduler 服务：

```bash
kubectl apply -f k8s/applications/scheduler-app.yaml
```

检查 ArgoCD 应用状态，确保服务同步完成：
```bash
kubectl get application -n argocd
```

### 5. 提交 TPU 任务

获取 Scheduler 服务的外部 IP：
```bash
SCHEDULER_IP=$(kubectl get svc sgl-scheduler -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Scheduler Endpoint: http://$SCHEDULER_IP:8080"
```

提交任务 (示例)：
```bash
curl -X POST "http://$SCHEDULER_IP:8080/api/jobs" \
  -H "Content-Type: application/json" \
  -d "{ 
    \"user_name\": \"test-user\",
    \"ssh_pub_key\": \"$(cat ~/.ssh/id_rsa.pub)\",
    \"tpu_type\": \"tpu-v6e-slice\",
    \"tpu_topology\": \"1x1\",
    \"tpu_count\": 1
}"
```

### 6. 查看状态与连接

查询任务状态（包含 SSH 连接命令）：
```bash
curl "http://$SCHEDULER_IP:8080/api/jobs/status?user_name=test-user"
```

输出示例：
```json
{
  "job_id": "test-user",
  "status": "Ready",
  "external_ip": "34.123.45.67",
  "ssh_command": "ssh root@34.123.45.67"
}
```

```bash
# 查看 TPU 环境变量
env | grep TPU

# 测试 JAX TPU
pip install -U "jax[tpu]"
python3 -c "import jax; print(jax.devices())"
```

## 资源清理

```bash
# 1. 删除节点池
cd terraform/nodepool
terraform destroy -auto-approve

# 2. 删除集群及 ArgoCD
cd ../cluster
terraform destroy -auto-approve
```
