variable "project_id" {
  description = "The GCP project ID to host the storage buckets"
  type        = string
  default     = "tpu-service-473302"
}

variable "dataset_storage_bucket_name" {
  description = "Name of the GCS bucket for storing pretraining datasets"
  type        = string
  default     = "tpu-service-pretrain-dataset"
}

variable "output_storage_bucket_name" {
  description = "Name of the GCS bucket for storing model checkpoints and training outputs"
  type        = string
  default     = "tpu-service-pretrain-output"
}

variable "location" {
  description = "The location for the storage buckets. Use multi-region (e.g., 'US') for high availability or single region (e.g., 'us-central1') for lower latency"
  type        = string
  default     = "US"
}

variable "storage_class" {
  description = "The storage class for the buckets. Options: STANDARD, NEARLINE, COLDLINE, ARCHIVE"
  type        = string
  default     = "STANDARD"
}

variable "versioning_enabled" {
  description = "Enable object versioning to preserve, retrieve, and restore previous versions of objects"
  type        = bool
  default     = true
}

variable "force_destroy" {
  description = "When true, allows bucket deletion even if it contains objects. Set to false for production to prevent accidental data loss"
  type        = bool
  default     = false
}

variable "dataset_lifecycle_age" {
  description = "Number of days after which objects are subject to the lifecycle action (e.g., deletion or storage class change)"
  type        = number
  default     = 90
}

variable "output_lifecycle_age" {
  description = "Number of days after which objects are subject to the lifecycle action (e.g., deletion or storage class change)"
  type        = number
  default     = 30
}

variable "lifecycle_rule_action_type" {
  description = "The lifecycle action to take. Options: Delete, SetStorageClass, AbortIncompleteMultipartUpload"
  type        = string
  default     = "Delete"
}

variable "uniform_bucket_level_access" {
  description = "Enable uniform bucket-level access. When true, ACLs are disabled and access is managed exclusively through IAM policies"
  type        = bool
  default     = true
}