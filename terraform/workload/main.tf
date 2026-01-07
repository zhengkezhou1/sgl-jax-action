terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# --- Workload Identity Setup ---

# 1. Create a Google Service Account (GSA) for the TPU workload
resource "google_service_account" "tpu_workload_gsa" {
  account_id   = "${var.user_name}-tpu-sa"
  display_name = "Service Account for TPU Workload"
  project      = var.project_id
}

# --- FINAL FIX: Grant the GSA the necessary permissions ---
# The GSA needs the TPU Viewer role to be able to query TPU metadata.
resource "google_project_iam_member" "tpu_viewer_binding" {
  project = var.project_id
  role    = "roles/tpu.viewer"
  member  = google_service_account.tpu_workload_gsa.member
}

# 2. Create a Kubernetes Service Account (KSA)
resource "kubernetes_service_account_v1" "tpu_workload_ksa" {
  metadata {
    name      = var.k8s_service_account_name
    namespace = var.k8s_namespace
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.tpu_workload_gsa.email
    }
  }
}

# 3. Bind the KSA to the GSA
# This allows the KSA to act as the GSA.
resource "google_service_account_iam_binding" "workload_identity_binding" {
  service_account_id = google_service_account.tpu_workload_gsa.name
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[${var.k8s_namespace}/${kubernetes_service_account_v1.tpu_workload_ksa.metadata[0].name}]",
  ]
}


# --- Kubernetes Manifest Deployment ---

# Get GKE cluster credentials
data "google_client_config" "default" {}
data "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.region
  project  = var.project_id
}

provider "kubernetes" {
  host                   = "https://${data.google_container_cluster.primary.endpoint}"
  cluster_ca_certificate = base64decode(data.google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
  token                  = data.google_client_config.default.access_token
}

# Read and template the YAML file
locals {
  template = templatefile("${path.module}/tpu-workload.yaml.tpl", {
    USER_NAME              = var.user_name,
    SSH_PUB_KEY            = nonsensitive(var.ssh_pub_key),
    TPU_TYPE               = var.tpu_type,
    TPU_TOPOLOGY           = var.tpu_topology,
    TPU_COUNT              = var.tpu_count,
    K8S_NAMESPACE          = var.k8s_namespace,
    K8S_SERVICE_ACCOUNT_NAME = kubernetes_service_account_v1.tpu_workload_ksa.metadata[0].name
  })
  # Split the multi-document YAML and filter out empty documents and comment-only sections
  yamls = [for doc in split("---", local.template) : trimspace(doc) if trimspace(doc) != "" && can(regex("^apiVersion:", trimspace(doc)))]
}

# Create Kubernetes resources from the templated YAML
resource "kubernetes_manifest" "tpu_workload" {
  for_each = nonsensitive({ for i, y in local.yamls : i => y })
  manifest = yamldecode(each.value)

  # Handle field manager conflicts (e.g., serviceAccount vs serviceAccountName)
  field_manager {
    force_conflicts = true
  }
}

# --- Variable Definitions ---

variable "project_id" {
  description = "The project ID to host the cluster in."
  type        = string
}
variable "region" {
  description = "The region the cluster is in."
  type        = string
  default     = "asia-northeast1"
}
variable "cluster_name" {
  description = "The name of the GKE cluster."
  type        = string
  default     = "tpu-v6-cluster"
}
variable "k8s_namespace" {
  description = "The Kubernetes namespace to deploy resources into."
  type        = string
  default     = "default"
}
variable "k8s_service_account_name" {
  description = "The name for the Kubernetes Service Account."
  type        = string
  default     = "tpu-workload-sa"
}
variable "user_name" {
  description = "The username for isolating resources."
  type        = string
}
variable "ssh_pub_key" {
  description = "The content of the SSH public key."
  type        = string
  sensitive   = true
}
variable "tpu_type" {
  description = "The TPU accelerator type."
  type        = string
  default     = "tpu-v6e-slice"
}
variable "tpu_topology" {
  description = "The TPU topology."
  type        = string
  default     = "1x1"
}
variable "tpu_count" {
  description = "The number of TPU chips."
  type        = number
  default     = 1
}