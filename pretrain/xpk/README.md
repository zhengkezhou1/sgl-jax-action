使用 XPK 在 MaxText 上进行预训练(TPU 7x)

# 创建存储桶用来管理数据集以及 checkpoint

在当前仓库的 terraform 目录下下执行:
```bash
terraform apply
```

# 构建 MaxText 基础镜像

在 `ant-pretrain` 根目录下执行以下命令以构建 TPU 运行时环境:
```bash
bash dependencies/scripts/docker_build_dependency_image.sh DEVICE=tpu MODE=stable
```

输出:
```bash
Building docker image: maxtext_base_image. This will take a few minutes but the image can be reused as you iterate.
DEVICE=tpu
MODE=stable
Building docker image with arguments: DEVICE=tpu WORKFLOW=pre-training MODE=stable JAX_VERSION=NONE LIBTPU_VERSION=NONE
[+] Building 22.0s (26/26) FINISHED                                                                                                                        docker:orbstack
 => [internal] load build definition from maxtext_tpu_dependencies.Dockerfile                                                                                         0.0s
 => => transferring dockerfile: 2.89kB                                                                                                                                0.0s
 => resolve image config for docker-image://docker.io/docker/dockerfile:experimental                                                                                  2.0s
 => [auth] docker/dockerfile:pull token for registry-1.docker.io                                                                                                      0.0s
 => CACHED docker-image://docker.io/docker/dockerfile:experimental@sha256:600e5c62eedff338b3f7a0850beb7c05866e0ef27b2d2e8c02aa468e78496ff5                            0.0s
 => [internal] load .dockerignore                                                                                                                                     0.0s
 => => transferring context: 34B                                                                                                                                      0.0s
 => [internal] load build definition from maxtext_tpu_dependencies.Dockerfile                                                                                         0.0s
 => [internal] load metadata for docker.io/library/python:3.12-slim-bullseye                                                                                          1.4s
 => [auth] library/python:pull token for registry-1.docker.io                                                                                                         0.0s
 => [internal] load build context                                                                                                                                     0.0s
 => => transferring context: 80.82kB                                                                                                                                  0.0s
 => [stage-0  1/16] FROM docker.io/library/python:3.12-slim-bullseye@sha256:411fa4dcfdce7e7a3057c45662beba9dcd4fa36b2e50a2bfcd6c9333e59bf0db                          0.0s
 => CACHED [stage-0  2/16] RUN apt-get update && apt-get install -y curl gnupg                                                                                        0.0s
 => CACHED [stage-0  3/16] RUN echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/so  0.0s
 => CACHED [stage-0  4/16] RUN curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -              0.0s
 => CACHED [stage-0  5/16] RUN apt-get update && apt-get install -y google-cloud-sdk                                                                                  0.0s
 => CACHED [stage-0  6/16] RUN update-alternatives --install /usr/bin/python3 python3 /usr/local/bin/python3.12 1                                                     0.0s
 => CACHED [stage-0  7/16] WORKDIR /deps                                                                                                                              0.0s
 => CACHED [stage-0  8/16] COPY tools/setup tools/setup/                                                                                                              0.0s
 => CACHED [stage-0  9/16] COPY dependencies/requirements/ dependencies/requirements/                                                                                 0.0s
 => CACHED [stage-0 10/16] COPY src/install_maxtext_extra_deps/extra_deps_from_github.txt src/install_maxtext_extra_deps/                                             0.0s
 => CACHED [stage-0 11/16] COPY libtpu.so* /root/custom_libtpu/                                                                                                       0.0s
 => CACHED [stage-0 12/16] RUN echo "Running command: bash setup.sh MODE=stable JAX_VERSION=NONE LIBTPU_VERSION=NONE DEVICE=tpu"                                      0.0s
 => CACHED [stage-0 13/16] RUN --mount=type=cache,target=/root/.cache/pip bash /deps/tools/setup/setup.sh MODE=stable JAX_VERSION=NONE LIBTPU_VERSION=NONE DEVICE=tp  0.0s
 => [stage-0 14/16] COPY . .                                                                                                                                          0.4s
 => [stage-0 15/16] RUN if [ "false" = "true" ]; then         echo "Downloading test assets from GCS...";         if ! gcloud storage cp -r gs://maxtext-test-assets  0.1s
 => [stage-0 16/16] RUN test -f '/tmp/venv_created' && "$(tail -n1 /tmp/venv_created)"/bin/activate ; pip install --no-dependencies -e .                             17.5s
 => exporting to image                                                                                                                                                0.2s 
 => => exporting layers                                                                                                                                               0.2s 
 => => writing image sha256:48d66f43f9c925ed4f3352b07fee10619567ccf0a9afb6c78f652c0461ba2554                                                                          0.0s 
 => => naming to docker.io/library/maxtext_base_image                                                                                                                 0.0s

*************************

Built your base docker image and named it maxtext_base_image.
It only has the dependencies installed. Assuming you're on a TPUVM, to run the
docker image locally and mirror your local working directory run:
docker run -v /Users/hongmao/workplace/ant-pretrain:/deps --rm -it --privileged --entrypoint bash maxtext_base_image

You can run MaxText and your development tests inside of the docker image. Changes to your workspace will automatically
be reflected inside the docker container.
Once you want you upload your docker container to GCR, take a look at docker_upload_runner.sh                                                       
```

# 管理 XPK 集群

XPK 会通过 Pathway + JobSet 的方式来执行训练负载

- `ACCELERATOR_TYPE` 根据拓扑结构决定是否创建 multihost 节点池(node pool), 例如: `tpu7x-2x2x2`, `tpu7x-2x2x1`.
- `CLUSTER_CPU_MACHINE_TYPE` tpu 节点 具有污点 `google.com/tpu` 使得一些 k8s 系统组件无法被调度(这里是 core-dns), 需要一台 CPU 节点来承载系统组件的 pod.

```bash
export PROJECT_ID="tpu-service-473302"
export CLUSTER_NAME="tpu7x-pre-train"
export ZONE="us-central1-c"
export ACCELERATOR_TYPE="tpu7x-2x2x2"
export CLUSTER_CPU_MACHINE_TYPE=n1-standard-8
```

## 创建集群

```bash
xpk cluster create \
--project=${PROJECT_ID} \
--zone=${ZONE} \
--cluster ${CLUSTER_NAME} \
--cluster-cpu-machine-type=${CLUSTER_CPU_MACHINE_TYPE} \
--tpu-type=${ACCELERATOR_TYPE} \
--spot
```

## 删除集群

```bash
xpk cluster delete \
--cluster=${CLUSTER_NAME} \
--project=${PROJECT_ID} \
--zone=${ZONE}
```

# 准备 Dataset

修改 src/MaxText/configs/base.yml 后执行 `bash dependencies/scripts/docker_build_dependency_image.sh DEVICE=tpu MODE=stable`

# 创建 workload

```bash
export CLUSTER_NAME="tpu7x-pre-train"
export ACCELERATOR_TYPE="tpu7x-2x2x2"
export BASE_DOCKER_IMAGE="maxtext_base_image"
export WORKLOAD_NAME="test-ant-pretrain-lingv2-8b"
export DATASET_PATH="gs://test-ant-pretrain-dataset"
export BASE_OUTPUT_DIR="gs://test-ant-pretrain-ouput"
xpk workload create\
  --cluster ${CLUSTER_NAME} \
  --workload ${USER}-${WORKLOAD_NAME} \
  --base-docker-image ${BASE_DOCKER_IMAGE} \
  --tpu-type ${ACCELERATOR_TYPE} \
  --command "python3 -m MaxText.train src/MaxText/configs/base.yml run_name=${USER}-lingv2-8b base_output_directory=${BASE_OUTPUT_DIR} dataset_path=${DATASET_PATH} steps=100"
```