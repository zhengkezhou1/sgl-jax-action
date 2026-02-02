output "dataset_bucket_name" {
  description = "The name of the dataset bucket"
  value       = google_storage_bucket.dataset.name
}

output "dataset_bucket_url" {
  description = "The gsutil URL of the dataset bucket"
  value       = "gs://${google_storage_bucket.dataset.name}"
}

output "output_bucket_name" {
  description = "The name of the output bucket"
  value       = google_storage_bucket.output.name
}

output "output_bucket_url" {
  description = "The gsutil URL of the output bucket"
  value       = "gs://${google_storage_bucket.output.name}"
}
