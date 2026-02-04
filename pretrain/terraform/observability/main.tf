terraform {
  required_version = ">= 1.4.3"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
  }
  backend "gcs" {
    bucket = "tpu-service-terraform-state"
    prefix = "pretrain/observability"
  }
}

data "terraform_remote_state" "gke" {
  backend = "gcs"
  config = {
    bucket = "tpu-service-terraform-state"
    prefix = "pretrain/gke"
  }
}

data "google_client_config" "default" {}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "kubernetes" {
  host                   = "https://${data.terraform_remote_state.gke.outputs.cluster_endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(data.terraform_remote_state.gke.outputs.cluster_ca_certificate)
}

provider "helm" {
  kubernetes = {
    host                   = "https://${data.terraform_remote_state.gke.outputs.cluster_endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(data.terraform_remote_state.gke.outputs.cluster_ca_certificate)
  }
}

resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name = "monitoring"
  }
}

resource "helm_release" "grafana" {
  name       = "grafana"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  version    = "8.8.2"
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name

  values = [
    yamlencode({
      adminPassword = var.grafana_admin_password

      service = {
        type = "LoadBalancer"
      }

      datasources = {
        "datasources.yaml" = {
          apiVersion = 1
          datasources = [{
            name      = "GCP Monitoring"
            type      = "stackdriver"
            isDefault = true
            jsonData = {
              authenticationType = "gce"
              defaultProject     = var.project_id
            }
          }]
        }
      }
    })
  ]
}

output "grafana_service_ip" {
  description = "Grafana LoadBalancer IP"
  value       = "Run: kubectl get svc grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
}
