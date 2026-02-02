# 单机测试

创建集群
```
terrafrom init

terrafrom apply
```

更新 kubeconfig 凭证
```
gcloud container clusters get-credentials tpu-v6e-pre-train \
    --region asia-northeast1 \
    --project tpu-service-473302
```

配置 sky config
skypilot 会通过 `config.yaml` 在 k8s 上部署 Ray Cluster, 所以当集群资源发生变化时,需要同步到配置文件.
例如 tpu 拓扑: 2x2->2x4, 在单节点的情况下需要为 Master Node 指定 `google.com/tpu: 8`
```zsh
cat config.yaml > ~/.sky/config.yaml
```

启动 Ray Cluster
```
sky launch -r job.yaml
```

预训练测试
```
python3 -m MaxText.train src/MaxText/configs/base.yml \
  run_name=llama2-7b \
  model_name=llama2-7b \
  base_output_directory=gs://test-ant-pretrain-output \
  dataset_type=synthetic \
  steps=100
```