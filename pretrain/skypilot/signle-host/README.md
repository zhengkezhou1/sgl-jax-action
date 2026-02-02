# 使用 skypilot 在 GKE 上进行预训练

单主机测试(ct6e-standard-8t * 8)

## 创建 GKE 集群
`pretrain/terraform/gke`
```bash
terraform init
terraform apply
```

## 配置 sky config

```bash
cp config.yaml > ~/.sky
```

## 启动 Ray 集群
```bash
sky launch -r setup.yaml
```