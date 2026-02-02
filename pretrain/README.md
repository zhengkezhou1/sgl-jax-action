## 准备 GCS 存储桶

### 创建 terraform state 存储桶
`pretrain/terraform/bootstrap`
```bash
terraform init
terraform apply
```

### 创建 dataset, checkpoint 存储桶
`pretrain/terraform/infra`
```bash
terraform init
terraform apply
```

## 准备 [Data pipelines](https://maxtext.readthedocs.io/en/latest/guides/data_input_pipeline.html#data-pipelines)

以 TFDS pipeline 为例,在根目录下执行以下命令即可将 dataset 拷贝到 GCS 中

```bash
export PROJECT_ID=tpu-service-473302
export DATASET_PATH=gs://test-ant-pretrain-dataset

bash tools/data_generation/download_dataset.sh ${PROJECT_ID} ${DATASET_PATH}
```

## 使用不同的工具部署训练负载

### xpk 

[使用 XPK 在 MaxText 上进行预训练](/pretrain/xpk/README.md)

### skypilot

[使用 skypilot 在 GKE 上进行预训练](/pretrain/skypilot/signle-host/README.md)