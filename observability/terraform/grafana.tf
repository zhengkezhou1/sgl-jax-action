# Get current GCP client configuration for authentication
data "google_client_config" "default" {}

# Configure Kubernetes provider using GKE cluster credentials
provider "kubernetes" {
  host                   = "https://${google_container_cluster.primary.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
}

# Configure Helm provider using GKE cluster credentials
provider "helm" {
  kubernetes = {
    host                   = "https://${google_container_cluster.primary.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
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

# =============================================================================
# GMP Query Frontend
# =============================================================================
# Deploy a query frontend to enable PromQL queries against Google Managed Prometheus.
# This frontend proxies requests to the GMP API with proper authentication.

# Google Service Account for GMP Frontend
resource "google_service_account" "gmp_frontend" {
  account_id   = "gmp-frontend-sa"
  display_name = "GMP Frontend Service Account"
  project      = var.project_id
}

# Grant Monitoring Viewer role to read metrics from GMP
resource "google_project_iam_member" "gmp_frontend_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.gmp_frontend.email}"
}

# Workload Identity binding for GMP Frontend
resource "google_service_account_iam_member" "gmp_frontend_workload_identity" {
  service_account_id = google_service_account.gmp_frontend.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[monitoring/gmp-frontend]"
}

# Kubernetes Service Account for GMP Frontend
resource "kubernetes_service_account_v1" "gmp_frontend" {
  metadata {
    name      = "gmp-frontend"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.gmp_frontend.email
    }
  }
}

resource "kubernetes_deployment_v1" "gmp_frontend" {
  metadata {
    name      = "frontend"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "frontend"
      }
    }

    template {
      metadata {
        labels = {
          app = "frontend"
        }
      }

      spec {
        service_account_name            = kubernetes_service_account_v1.gmp_frontend.metadata[0].name
        automount_service_account_token = true

        affinity {
          node_affinity {
            required_during_scheduling_ignored_during_execution {
              node_selector_term {
                match_expressions {
                  key      = "kubernetes.io/arch"
                  operator = "In"
                  values   = ["arm64", "amd64"]
                }
                match_expressions {
                  key      = "kubernetes.io/os"
                  operator = "In"
                  values   = ["linux"]
                }
              }
            }
          }
        }

        container {
          name  = "frontend"
          image = "gke.gcr.io/prometheus-engine/frontend:v0.15.3-gke.0"
          args = [
            "--web.listen-address=:9090",
            "--query.project-id=${var.project_id}"
          ]

          port {
            container_port = 9090
            name           = "web"
          }

          security_context {
            allow_privilege_escalation = false
            privileged                 = false
            run_as_group               = 1000
            run_as_non_root            = true
            run_as_user                = 1000
            capabilities {
              drop = ["ALL"]
            }
          }

          liveness_probe {
            http_get {
              path = "/-/healthy"
              port = "web"
            }
          }

          readiness_probe {
            http_get {
              path = "/-/ready"
              port = "web"
            }
          }
        }
      }
    }
  }

  depends_on = [google_service_account_iam_member.gmp_frontend_workload_identity]
}

resource "kubernetes_service_v1" "gmp_frontend" {
  metadata {
    name      = "frontend"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }

  spec {
    cluster_ip = "None"
    selector = {
      app = "frontend"
    }

    port {
      port        = 9090
      target_port = 9090
      name        = "web"
    }
  }
}

# =============================================================================
# Grafana Deployment
# =============================================================================
# Note: Using Google Cloud Managed Service for Prometheus (GMP) instead of
# self-managed Prometheus. GMP is enabled in the GKE cluster configuration
# and provides a fully managed Prometheus-compatible monitoring solution.

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
        port = 80
      }

      # Grafana server configuration
      "grafana.ini" = {
        server = {
          root_url = "%(protocol)s://%(domain)s:%(http_port)s/"
        }
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

      # Pre-configure datasources for Grafana.
      # GMP (Google Managed Prometheus) is the default datasource for PromQL queries.
      # GCP Monitoring (Stackdriver) is available as a secondary option.
      datasources = {
        "datasources.yaml" = {
          apiVersion = 1
          datasources = [
            {
              # Google Cloud Managed Prometheus - query via in-cluster frontend
              # Frontend is deployed in the monitoring namespace
              name      = "Prometheus (GMP)"
              type      = "prometheus"
              url       = "http://frontend.monitoring.svc:9090"
              isDefault = true
            },
            {
              name      = "GCP Monitoring"
              type      = "stackdriver"
              isDefault = false
              jsonData = {
                authenticationType = "gce"
                defaultProject     = var.project_id
              }
            }
          ]
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
