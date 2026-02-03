# 使用 Terraform 在 GKE 上创建 TPU 实例

[在 GKE 上申请 TPU](/pretrain/terraform/gke/README.md)

# 使用 skypilot 部署 workload

## skypilot 配置

在创建了对应的 TPU 节点池之后,需要修改 skypilot 对应的配置, 然后覆盖默认值
```bash
cp pretrain/skypilot/multi-host/config/config.yaml ~/.sky/config.ymal
```

在绝大多数情况下对节点池的变更(修改 topology 结构, 使用不同架构的 TPU...)总是会需要修改以下内容:

- `${tpu_type}`: 节点池对应的 TPU 类型
- `${tpu_topology}`: 节点池对应的 topology 结构
- `${chip_nums}`: 构成节点池的虚拟机上的所有芯片数量

定义 Ray Node 如何被调度到节点池的节点上并申请对应的资源(CPU,memory,TPU)
```yaml
# config.yaml
kubernetes:
  pod_config:
    spec:
    ...
      nodeSelector:
        cloud.google.com/gke-tpu-accelerator: ${tpu_type}
        cloud.google.com/gke-tpu-topology: ${tpu_topology}
      containers:
        - name: ray-node
          image: us-docker.pkg.dev/cloud-tpu-images/jax-ai-image/tpu@sha256:33fd74d1ac4a45de18855cfec6c41644bf59d5b4e76a343d32f52b6553f0e804
          resources:
            requests:
              cpu: "36"
              memory: "500Gi"    
              google.com/tpu: ${chip_nums}
            limits:
              cpu: "36"
              memory: "500Gi"
              google.com/tpu: ${chip_nums}
    ...
```

## 部署 Cluster

skypilot 会使用 `~/.sky/config.yaml` 中的配置来部署 Ray Cluster.同时在 `setup.yaml` 中完成本地仓库的挂载.

- `${num_nodes}`: cluster 会从节点池中使用到的节点数量
- `${ant_pretrain_repo_path}`: 本地的预训练仓库路径,挂载到云端. 所有的变更都会同步到所有节点中

### 在 multi host 的节点池上部署 Cluster

```bash
sky launch -r ./pretrain/skypilot/multi-host/setup.yaml
```

```yaml
# setup.yaml
num_nodes: ${num_nodes}

resources:
  cloud: kubernetes

file_mounts:
  ~/sky_workdir: ${ant_pretrain_repo_path}

setup: |
  conda init bash
  conda create -n ant-pretrain -c conda-forge python=3.12 -y
  conda activate ant-pretrain
  cd ~/sky_workdir
  bash tools/setup/setup.sh DEVICE=tpu

run: |
  echo "Cluster is ready. Use 'sky exec <cluster-name> job.yaml' to run jobs."
```


### 输出

#### GKE 节点池扩容
![GKE 扩容](/pretrain/skypilot/img/multi-host扩容.png)

#### skypilot 构建集群
![skypilot 构建集群](/pretrain/skypilot/img/skypilot重试拉起集群.png)


## 提交任务

⚠️有时候会出现 TLS 超时

```bash
sky exec -d ${cluster_name} ./pretrain/skypilot/multi-host/job.yaml
```

## 查看日志

拿到上一步提交任务的 ID 执行以下操作:

```bash
sky logs sky-338f-hongmao ${job_id}
```