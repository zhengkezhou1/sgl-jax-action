provider "google" {
  project = var.project_id
  # region  = var.region
}

resource "google_storage_bucket" "test-ant-pretrain-dataset" {
  name          = "test-ant-pretrain-dataset"
  location      = "US"
  storage_class = "STANDARD"

  uniform_bucket_level_access = true
}

resource "google_storage_bucket" "test-ant-pretrain-output" {
  name          = "test-ant-pretrain-output"
  location      = "US"
  storage_class = "STANDARD"

  uniform_bucket_level_access = true
}

resource "google_artifact_registry_repository" "test-ant-pretrain-docker-repository" {
  repository_id = "gcr.io"
  location      = "us"
  format        = "DOCKER"
  description   = "Docker repository for gcr.io compatibility"

  cleanup_policies {
    id     = "keep-recent-versions"
    action = "KEEP"

    most_recent_versions {
      keep_count = 10
    }
  }
}