`/terraform/autopilot-cluster`
```zsh
terraform init

terraform apply
```

更新 kubeconfig 凭证
```zsh
gcloud container clusters get-credentials skypilot-standard-tpu --region asia-northeast1 --project tpu-service-473302
```

使用 当前目录下的 config.yaml 覆盖 `~/.skypilot/config.yaml` 内容
```zsh
cp ./skypilot/config.yaml ~/.sky
```

```zsh
sky launch -r ./skypilot/tpu-v6e.yaml
```

```
curl http://127.0.0.1:30000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "meta-llama/Llama-3-8b-chat-hf",
    "messages": [
      {
        "role": "system",
        "content": "你是一个有用的助手。"
      },
      {
        "role": "user",
        "content": "你好，请介绍一下你自己。"
      }
    ],
    "temperature": 0.7
  }' | jq
```
