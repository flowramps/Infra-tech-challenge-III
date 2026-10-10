variable "namespace" {
  description = "Namespace of the sample application (part of the mesh)."
  type        = string
  default     = "sample-app"
}

variable "cluster_name" {
  description = "kind cluster that receives the locally built image."
  type        = string
}

variable "source_dir" {
  description = "Directory with the application Dockerfile."
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

variable "ingress_gateway_selector" {
  description = "Labels selecting the Istio ingress gateway pods."
  type        = map(string)
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
