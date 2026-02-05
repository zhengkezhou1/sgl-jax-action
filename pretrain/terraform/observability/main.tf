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

# Get current GCP client configuration for authentication
data "google_client_config" "default" {}

# Fetch GKE cluster details to configure Kubernetes/Helm providers
data "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.region
  project  = var.project_id
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Configure Kubernetes provider using GKE cluster credentials
provider "kubernetes" {
  host                   = "https://${data.google_container_cluster.primary.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(data.google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
}

# Configure Helm provider using GKE cluster credentials
provider "helm" {
  kubernetes = {
    host                   = "https://${data.google_container_cluster.primary.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(data.google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
  }
}

# =============================================================================
# Workload Identity Configuration for Grafana
# =============================================================================
# Workload Identity allows the Grafana pod to authenticate as a Google Cloud
# service account, enabling secure access to GCP APIs (Cloud Monitoring, etc.)
# without embedding credentials in the container.

# Google Service Account (GSA) that Grafana will use to access GCP APIs
resource "google_service_account" "grafana" {
  account_id   = "grafana-sa"
  display_name = "Grafana Service Account"
  project      = var.project_id
}

# Grant Monitoring Viewer role - required to read metrics from Cloud Monitoring
resource "google_project_iam_member" "grafana_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.grafana.email}"
}

# Grant Browser role - required to list projects in Grafana's project selector
resource "google_project_iam_member" "grafana_browser" {
  project = var.project_id
  role    = "roles/browser"
  member  = "serviceAccount:${google_service_account.grafana.email}"
}

# Workload Identity binding: Allow Kubernetes Service Account (KSA) "grafana"
# in namespace "monitoring" to impersonate the Google Service Account (GSA).
# Format: serviceAccount:PROJECT_ID.svc.id.goog[NAMESPACE/KSA_NAME]
resource "google_service_account_iam_member" "grafana_workload_identity" {
  service_account_id = google_service_account.grafana.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[monitoring/grafana]"
}

resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name = "monitoring"
  }
}

# Deploy Grafana via Helm chart
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

      # Kubernetes Service Account configuration for Workload Identity.
      # The annotation links this KSA to the Google Service Account,
      # allowing Grafana to authenticate as the GSA when accessing GCP APIs.
      serviceAccount = {
        create = true
        name   = "grafana"
        annotations = {
          "iam.gke.io/gcp-service-account" = google_service_account.grafana.email
        }
      }

      # Pre-configure Google Cloud Monitoring (Stackdriver) as the default datasource.
      # Uses GCE authentication which leverages Workload Identity credentials.
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

  # Ensure Workload Identity binding exists before deploying Grafana
  depends_on = [google_service_account_iam_member.grafana_workload_identity]
}

output "grafana_service_ip" {
  description = "Grafana LoadBalancer IP"
  value       = "Run: kubectl get svc grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
}
