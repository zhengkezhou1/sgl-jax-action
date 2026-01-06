terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.11"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Get GKE cluster credentials
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

data "google_client_config" "default" {}

# Read and template the YAML file
locals {
  template = templatefile("${path.module}/tpu-workload.yaml.tpl", {
    USER_NAME     = var.user_name,
    SSH_PUB_KEY   = nonsensitive(var.ssh_pub_key),
    TPU_TYPE      = var.tpu_type,
    TPU_TOPOLOGY  = var.tpu_topology,
    TPU_COUNT     = var.tpu_count,
    K8S_NAMESPACE = var.k8s_namespace
  })
  # Split the multi-document YAML into a list of individual YAML documents
  # Filter out empty documents and comment-only sections
  yamls = [for doc in split("---", local.template) : trimspace(doc) if trimspace(doc) != "" && can(regex("^apiVersion:", trimspace(doc)))]
}

# Create Kubernetes resources from the templated YAML
resource "kubernetes_manifest" "tpu_workload" {
  for_each = nonsensitive({ for i, y in local.yamls : i => y })

  manifest = yamldecode(each.value)
}

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
  # This is a placeholder, as 'tpu-v6e-slice' is not a valid nodeSelector value.
  # The actual selection happens via machine_type in the node pool.
  # We use a common label for selection.
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