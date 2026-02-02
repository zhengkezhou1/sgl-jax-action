terraform {
  required_version = ">= 1.14.3"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
  }
  backend "gcs" {
    bucket = "tpu-service-terraform-state"
    prefix = "pretrain/infra"
  }
}

provider "google" {
  project = var.project_id
}

resource "google_storage_bucket" "dataset" {
  name          = var.dataset_storage_bucket_name
  location      = var.location
  storage_class = var.storage_class

  versioning {
    enabled = var.versioning_enabled
  }

  lifecycle_rule {
    condition {
      age = var.dataset_lifecycle_age
    }
    action {
      type = var.lifecycle_rule_action_type
    }
  }

  force_destroy               = var.force_destroy
  uniform_bucket_level_access = var.uniform_bucket_level_access
}

resource "google_storage_bucket" "output" {
  name          = var.output_storage_bucket_name
  location      = var.location
  storage_class = var.storage_class

  versioning {
    enabled = var.versioning_enabled
  }

  lifecycle_rule {
    condition {
      age = var.output_lifecycle_age
    }
    action {
      type = var.lifecycle_rule_action_type
    }
  }

  force_destroy               = var.force_destroy
  uniform_bucket_level_access = var.uniform_bucket_level_access
}
