variable "namespace" {
  description = "The namespace to install ArgoCD into"
  type        = string
  default     = "argocd"
}

variable "chart_version" {
  description = "Version of the ArgoCD Helm chart"
  type        = string
  default     = "7.7.13"
}

variable "values_yaml" {
  description = "Custom values.yaml content"
  type        = string
  default     = ""
}
