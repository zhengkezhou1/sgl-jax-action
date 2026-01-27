创建集群
```
terrafrom init

terrafrom apply
```

更新 kube context
```zsh
gcloud container clusters get-credentials dev-pre-train-v6e \
    --region asia-northeast1 \
    --project tpu-service-473302
```

配置 sky config
```zsh
cat config.yaml > ~/.sky/config.yaml
```

启动 Ray Cluster
```
sky launch -r job.yaml
```