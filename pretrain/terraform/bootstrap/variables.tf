variable "project_id" {
  description = "The GCP project ID to host the Terraform state bucket"
  type        = string
  default     = "tpu-service-473302"
}

variable "terraform_state_bucket_name" {
  description = "Name of the GCS bucket for storing Terraform state files. Must be globally unique"
  type        = string
  default     = "tpu-service-terraform-state"
}

variable "location" {
  description = "The location for the Terraform state bucket"
  type        = string
  default     = "US"
}

variable "storage_class" {
  description = "The storage class for the Terraform state bucket. Options: STANDARD, NEARLINE, COLDLINE, ARCHIVE"
  type        = string
  default     = "STANDARD"
}

variable "versioning_enabled" {
  description = "Enable object versioning for the Terraform state bucket. Strongly recommended for state files"
  type        = bool
  default     = true
}

variable "uniform_bucket_level_access" {
  description = "Enable uniform bucket-level access. When true, ACLs are disabled and access is managed exclusively through IAM policies"
  type        = bool
  default     = true
}

variable "public_access_prevention" {
  description = "Public access prevention setting. Options: enforced, inherited"
  type        = string
  default     = "enforced"
}

variable "force_destroy" {
  description = "When true, allows bucket deletion even if it contains objects. Set to false for state buckets to prevent accidental data loss"
  type        = bool
  default     = false
}
