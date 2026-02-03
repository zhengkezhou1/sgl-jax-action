# 在 GKE 上申请 TPU

## single host

[Create a single-host TPU slice node pool](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/tpus#single-host)

### TPU v6e

```tf
# Signle host TPU v6e node pool for workloads
resource "google_container_node_pool" "signle_host_v6e_2x2_node_pool" {
  project        = var.project_id
  cluster        = google_container_cluster.primary.name
  name           = "signle-host-v6e-2x2-node-pool"
  location       = google_container_cluster.primary.location
  node_locations = var.node_locations
  node_count     = var.tpu_v6e_min_node_count

  node_config {
    machine_type = var.tpu_v6e_machine_type
    spot         = var.tpu_spot
  }

  placement_policy {
    type         = "COMPACT"
    tpu_topology = "2x2"
  }

  autoscaling {
    min_node_count = var.tpu_v6e_min_node_count
    max_node_count = var.tpu_v6e_max_node_count
  }
}
```

### TPU v7x

```tf
# Signle host TPU v7x node pool for workloads
resource "google_container_node_pool" "signle_host_v7x_2x2x1_node_pool" {
  project        = var.project_id
  cluster        = google_container_cluster.primary.name
  name           = "signle-host-v7x-2x2x1-node-pool"
  location       = google_container_cluster.primary.location
  node_locations = var.node_locations
  node_count     = var.tpu_v7x_min_node_count

  node_config {
    machine_type = var.tpu_v7x_machine_type
    spot         = var.tpu_spot
  }

  autoscaling {
    min_node_count = var.tpu_v7x_min_node_count
    max_node_count = var.tpu_v7x_max_node_count
  }
}
```

## multi host

[Create a multi-host TPU slice node pool](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/tpus#multi-host)

```tf
#Multi Host TPU v7x node pool for workloads
resource "google_container_node_pool" "multi_host_v7x_2x2x2_node_pool" {
  project        = var.project_id
  cluster        = google_container_cluster.primary.name
  name           = "multi-host-v7x-2x2x2-node-pool"
  location       = google_container_cluster.primary.location
  node_locations = var.node_locations
  node_count     = 2

  node_config {
    machine_type = var.tpu_v7x_machine_type
    spot         = var.tpu_spot
  }

  placement_policy {
    #policy_name = "multi-host-tpu7x-resource-policy"
    type         = "COMPACT"
    tpu_topology = "2x2x2"
  }

  autoscaling {
    max_node_count       = 2
    location_policy      = "ANY"
  }
}
```

## ⚠️注意事项

### TPU machine type

- TPU 7x 只有 `tpu7x-standard-4t` 一种 **machine type**. 在创建 single/mulit host 节点池 (**node pool**) 时不需要考虑 **topology** 与 **machine type** 之间的关系.
- TPU v6e 中不同的 **topology** 在不同的 **machine type** 中创建出来的 节点池 (**node pool**) 可能是不一样的, 假设申请了 **topology** 为 *2x4* 的节点池.
  - 在 `ct6e-standard-8t` 中一台机器有 8 个芯片,正好满足需求.创建出 single host 节点池.
  - 在 `ct6e-standard-4t` 中一台机器有 4 个芯片,因此需要 2 台机器互联才能满足需求.创建出 multi host 节点池.


[choose-tpu-version](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/plan-tpus#choose-tpu-version)

| TPU 版本 | 机器类型 | vCPU 的数量 | 每个虚拟机的芯片数量 | 内存 (GiB) | NUMA 节点的数量 | 被抢占的可能性 |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| TPU Trillium (v6e) | ct6e-standard-1t | 44 | 1 | 448 | 2 | 较高 |
| TPU Trillium (v6e) | ct6e-standard-4t | 180 | 4 | 720 | 1 | 中 |
| TPU Trillium (v6e) | ct6e-standard-8t | 180 | 8 | 1440 | 2 | 较低 |
| Ironwood (TPU7x)（预览版） | tpu7x-standard-4t | 224 | 4 | 960 | 2 | 不适用 |

### Auto scaling
- 当设置了 `placement_policy.type` = `COMPACT` 时. 节点的数量要么为0,要么是最大值(topoloy 结构对应的芯片数 / 对应机器类型的芯片数量).

### Tpu7x 节点池大小不支持就地更新

```bash
terraform apply 
data.google_compute_subnetwork.default: Reading...
data.google_compute_network.default: Reading...
google_compute_resource_policy.multi-host-tpu7x-resource-policy: Refreshing state... [id=projects/tpu-service-473302/regions/us-central1/resourcePolicies/multi-host-tpu7x-resource-policy]
data.google_compute_network.default: Read complete after 0s [id=projects/tpu-service-473302/global/networks/default]
data.google_compute_subnetwork.default: Read complete after 1s [id=projects/tpu-service-473302/regions/us-central1/subnetworks/default]
google_container_cluster.primary: Refreshing state... [id=projects/tpu-service-473302/locations/us-central1/clusters/test-ant-pre-train]
null_resource.configure_kubectl: Refreshing state... [id=7880743603987318818]
google_container_node_pool.signle_host_v6e_2x2_node_pool: Refreshing state... [id=projects/tpu-service-473302/locations/us-central1/clusters/test-ant-pre-train/nodePools/signle-host-v6e-2x2-node-pool]
google_container_node_pool.system_node_pool: Refreshing state... [id=projects/tpu-service-473302/locations/us-central1/clusters/test-ant-pre-train/nodePools/system-node-pool]
google_container_node_pool.multi_host_v7x_2x2x2_node_pool: Refreshing state... [id=projects/tpu-service-473302/locations/us-central1/clusters/test-ant-pre-train/nodePools/multi-host-v7x-2x2x2-node-pool]
google_container_node_pool.signle_host_v7x_2x2x1_node_pool: Refreshing state... [id=projects/tpu-service-473302/locations/us-central1/clusters/test-ant-pre-train/nodePools/signle-host-v7x-2x2x1-node-pool]

Terraform used the selected providers to generate the following execution plan. Resource actions are indicated with the following symbols:
  ~ update in-place

Terraform will perform the following actions:

  # google_container_node_pool.multi_host_v7x_2x2x2_node_pool will be updated in-place
  ~ resource "google_container_node_pool" "multi_host_v7x_2x2x2_node_pool" {
        id                          = "projects/tpu-service-473302/locations/us-central1/clusters/test-ant-pre-train/nodePools/multi-host-v7x-2x2x2-node-pool"
        name                        = "multi-host-v7x-2x2x2-node-pool"
      ~ node_count                  = 0 -> 2
        # (10 unchanged attributes hidden)

      ~ placement_policy {
          - tpu_topology = "2x2x2" -> null
          + type         = "COMPACT"
            # (1 unchanged attribute hidden)
        }

        # (5 unchanged blocks hidden)
    }

Plan: 0 to add, 1 to change, 0 to destroy.

Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes

google_container_node_pool.multi_host_v7x_2x2x2_node_pool: Modifying... [id=projects/tpu-service-473302/locations/us-central1/clusters/test-ant-pre-train/nodePools/multi-host-v7x-2x2x2-node-pool]
╷
│ Error: googleapi: Error 501: Unimplemented: Multi-host TPU pool (multi-host-v7x-2x2x2-node-pool) manual resize is not supported.
│ Details:
│ [
│   {
│     "@type": "type.googleapis.com/google.rpc.RequestInfo",
│     "requestId": "0xcff762d34a99432b"
│   },
│   {
│     "@type": "type.googleapis.com/google.rpc.ErrorInfo",
│     "domain": "container.googleapis.com",
│     "reason": "UNIMPLEMENTED"
│   }
│ ]
│ , notImplemented
│ 
│   with google_container_node_pool.multi_host_v7x_2x2x2_node_pool,
│   on main.tf line 115, in resource "google_container_node_pool" "multi_host_v7x_2x2x2_node_pool":
│  115: resource "google_container_node_pool" "multi_host_v7x_2x2x2_node_pool" {
│ 
╵
```