variable "namespace" {
  description = "Namespace of Argo CD."
  type        = string
  default     = "argocd"
}

variable "chart_version" {
  description = "argo/argo-cd Helm chart version."
  type        = string
}
