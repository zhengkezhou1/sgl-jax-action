terraform {
  required_version = ">= 1.14.3"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
  }
  # No backend block - uses local state
  # This is intentional for bootstrap resources
}

provider "google" {
  project = var.project_id
}

resource "google_storage_bucket" "terraform_state" {
  name          = var.terraform_state_bucket_name
  location      = var.location
  storage_class = var.storage_class

  versioning {
    enabled = var.versioning_enabled
  }

  uniform_bucket_level_access = var.uniform_bucket_level_access
  public_access_prevention    = var.public_access_prevention
  force_destroy               = var.force_destroy
}
