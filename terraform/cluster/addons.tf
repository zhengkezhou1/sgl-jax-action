# Retrieve an access token as the Terraform runner
data "google_client_config" "default" {}

# Configure the Kubernetes provider to connect to the created cluster
provider "kubernetes" {
  host                   = "https://${google_container_cluster.primary.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
}

# Configure the Helm provider to use the same connection
provider "helm" {
  kubernetes {
    host                   = "https://${google_container_cluster.primary.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
  }
}

# --------------------------------------------------------------------------------
# Install ArgoCD Module
# --------------------------------------------------------------------------------
module "argocd" {
  source = "../modules/argocd"

  namespace     = "argocd"
  values_yaml = <<EOF
configs:
  params:
    server.insecure: true # 仅供测试方便，生产建议配合 Ingress/TLS
server:
  extraArgs:
  - --insecure
  service:
    type: LoadBalancer
EOF
}
