variable "namespace" {
  description = "Namespace of Argo CD."
  type        = string
  default     = "argocd"
}

variable "external_url" {
  description = "URL the Argo CD UI is published at."
  type        = string
}

variable "chart_version" {
  description = "argo/argo-cd Helm chart version."
  type        = string
}
