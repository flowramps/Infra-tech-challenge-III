variable "namespace" {
  description = "Namespace of the sample application (part of the mesh)."
  type        = string
  default     = "sample-app"
}

variable "argocd_namespace" {
  description = "Namespace where Argo CD runs."
  type        = string
}

variable "repo_url" {
  description = "Git repository Argo CD syncs the application chart from."
  type        = string
}

variable "target_revision" {
  description = "Branch, tag or commit Argo CD tracks."
  type        = string
  default     = "main"
}

variable "chart_path" {
  description = "Path of the application chart inside the repository."
  type        = string
  default     = "terraform/modules/sample-app/chart"
}

variable "argocd_apps_chart_version" {
  description = "argo/argocd-apps Helm chart version."
  type        = string
}

variable "monitoring_namespace" {
  description = "Namespace allowed to scrape metrics from the application."
  type        = string
}

variable "ingress_namespace" {
  description = "Namespace of the Istio ingress gateway."
  type        = string
}

variable "ingress_gateway" {
  description = "Shared Istio Gateway (<namespace>/<name>) the application attaches to."
  type        = string
}

variable "ingress_host" {
  description = "Hostname the application is published at."
  type        = string
}

variable "otlp_endpoint" {
  description = "OTLP/gRPC endpoint that receives application spans."
  type        = string
}

variable "canary_weight" {
  description = "Percentage of orders traffic routed to the v2 canary."
  type        = number
  default     = 10

  validation {
    condition     = var.canary_weight >= 0 && var.canary_weight <= 100
    error_message = "canary_weight must be between 0 and 100."
  }
}

variable "inventory_fault_rate" {
  description = "Fraction of inventory requests that fail on purpose (exercises retries and SLOs)."
  type        = number
  default     = 0.02
}

variable "developers_group" {
  description = "Group granted the sample-app developer role."
  type        = string
  default     = "sample-app-developers"
}
