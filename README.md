# sgl-jax-action

GKE TPU 集群部署和管理工具集，用于在 Google Cloud Platform 上快速部署和管理 TPU 工作负载。

## 项目概述

本项目提供了一套完整的 Terraform 配置和自动化脚本，用于：
- 创建私有 GKE 集群（支持 Workload Identity）
- 配置 CPU 和 TPU 节点池
- 部署 TPU 工作负载（SGLang 服务）
- 通过 SSH 访问 TPU Pod 并自动配置 TPU 环境变量

## 目录结构

```
.
├── script/                    # 自动化部署脚本
│   ├── apply_cluster.sh      # 创建 GKE 集群
│   ├── apply_nodepool.sh     # 创建节点池
│   ├── deploy_workload.sh    # 部署工作负载
│   └── test-ssh-tpu-env.sh   # 测试 SSH TPU 环境
├── terraform/                 # Terraform 配置文件
│   ├── cluster/              # GKE 集群配置
│   ├── nodepool/             # 节点池配置
│   └── workload/             # 工作负载配置
└── manifests/                 # Kubernetes manifest 文件
```

## 先决条件

1. **Google Cloud Platform 账号**
   - 已创建 GCP 项目
   - 已启用相关 API（GKE、Compute Engine、Cloud NAT）
   - 已配置计费账号

2. **本地工具**
   - [Terraform](https://www.terraform.io/downloads) >= 1.0
   - [gcloud CLI](https://cloud.google.com/sdk/docs/install)
   - [kubectl](https://kubernetes.io/docs/tasks/tools/)
   - SSH 密钥对

3. **认证配置**
   ```bash
   gcloud auth application-default login
   gcloud config set project YOUR_PROJECT_ID
   ```

## 快速开始

### 1. 创建 GKE 集群

使用自动化脚本创建带有 Workload Identity、Cloud NAT 和私有节点的 GKE 集群：

```bash
cd script
./apply_cluster.sh
```

该脚本会：
- 初始化 Terraform
- 创建私有 GKE 集群
- 配置 Workload Identity
- 设置 Cloud NAT 以允许私有节点访问互联网
- 配置防火墙规则

**配置参数**（在 `terraform/cluster/variables.tf` 中）：
- `project_id`: GCP 项目 ID
- `region`: 集群区域（默认：`asia-northeast1`）
- `cluster_name`: 集群名称（默认：`tpu-v6-cluster`）

### 2. 创建节点池

创建 CPU 节点池（系统组件）和 TPU 节点池（工作负载）：

```bash
./apply_nodepool.sh
```

该脚本会：
- 初始化 Terraform
- 创建 CPU 节点池（用于 kube-dns、metrics-server 等）
- 创建 TPU 节点池（用于运行 TPU 工作负载）

**配置参数**（在 `terraform/nodepool/variables.tf` 中）：
- `tpu_node_count`: TPU 节点数量
- `machine_type`: TPU 机器类型
- `node_locations`: 节点位置

### 3. 部署工作负载

部署 TPU 工作负载并配置 SSH 访问：

```bash
./deploy_workload.sh ~/.ssh/id_rsa.pub
```

**参数说明**：
- 第一个参数：SSH 公钥文件路径（必需）

该脚本会：
- 读取您的 SSH 公钥
- 部署 TPU Pod
- 配置 SSH 访问
- 自动设置 TPU 环境变量
- 创建 LoadBalancer 服务

**输出**：
脚本完成后会显示如何获取外部 IP 的命令：
```bash
kubectl get svc sgl-svc-$(whoami) -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

### 4. 连接到 GKE 集群

```bash
gcloud container clusters get-credentials tpu-v6-cluster \
  --region=asia-northeast1 \
  --project=YOUR_PROJECT_ID
```

## 验证部署

### 1. 检查 Pod 状态

```bash
kubectl get pods -l app=sgl-tpu
```

### 2. SSH 连接到 TPU Pod

```bash
EXTERNAL_IP=$(kubectl get svc sgl-svc-$(whoami) -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
ssh root@$EXTERNAL_IP
```

连接后，TPU 环境变量会自动加载：
```bash
# 查看 TPU 环境变量
env | grep TPU

# 测试 JAX TPU
pip install -U "jax[tpu]"
python3 -c "import jax; print(jax.devices())"
```

### 4. 测试服务可用性

```bash
git clone https://github.com/sgl-project/sglang-jax

cd sglang-jax

pip install -e "python[all]"

python -u -m sgl_jax.launch_server --model-path Qwen/Qwen-7B-Chat --trust-remote-code  --dist-init-addr=0.0.0.0:10011 --nnodes=1  --tp-size=1 --device=tpu --random-seed=3 --node-rank=0 --mem-fraction-static=0.8 --max-prefill-tokens=8192 --download-dir=/tmp --dtype=bfloat16  --skip-server-warmup --host 0.0.0.0 --port 30000

curl http://localhost:30000/v1/chat/completions \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{ "model": "", "messages": [ { "role": "user", "content": "who are you?" } ] }' | jq
```

## 架构说明

### 集群配置
- **类型**：私有 GKE 集群（私有节点 + 公共 Master 端点）
- **Workload Identity**：启用（用于安全访问 GCP 服务）
- **Cloud NAT**：配置（允许私有节点访问互联网）
- **网络**：使用 default VPC 和子网

### 节点池
1. **CPU 节点池**
   - 用于系统组件（kube-dns、metrics-server 等）
   - 支持自动扩缩容
   - 机器类型可配置

2. **TPU 节点池**
   - 用于运行 TPU 工作负载
   - 支持多可用区部署
   - 配置 TPU 环境变量自动加载

### 工作负载
- **镜像**：自定义 TPU 镜像
- **SSH 访问**：通过 LoadBalancer（端口 22）
- **服务端口**：30000（HTTP API）
- **TPU 环境**：自动配置在 `/etc/profile.d/tpu-env.sh`

## 清理资源

按照以下顺序删除资源：

1. **删除工作负载**
   ```bash
   cd terraform/workload
   terraform destroy -auto-approve
   ```

2. **删除节点池**
   ```bash
   cd terraform/nodepool
   terraform destroy -auto-approve
   ```

3. **删除集群**
   ```bash
   cd terraform/cluster
   terraform destroy -auto-approve
   ```