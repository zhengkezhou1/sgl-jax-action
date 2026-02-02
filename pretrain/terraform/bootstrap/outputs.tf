output "terraform_state_bucket_name" {
  description = "The name of the Terraform state bucket"
  value       = google_storage_bucket.terraform_state.name
}

output "terraform_state_bucket_url" {
  description = "The URL of the Terraform state bucket"
  value       = google_storage_bucket.terraform_state.url
}

output "backend_config" {
  description = "Backend configuration to use in other Terraform modules"
  value = {
    bucket = google_storage_bucket.terraform_state.name
    prefix = "pretrain/infra"
  }
}
