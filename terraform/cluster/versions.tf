terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "7.15.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "3.0.1"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }
  required_version = ">= 1.0"
}
