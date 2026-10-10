variable "namespace" {
  description = "Namespace that hosts the observability stack."
  type        = string
  default     = "monitoring"
}

variable "storage_class" {
  description = "StorageClass used by every PersistentVolumeClaim."
  type        = string
  default     = "standard"
}

variable "chart_versions" {
  description = "Pinned Helm chart versions."
  type = object({
    kube_prometheus_stack = string
    loki                  = string
    tempo                 = string
    alloy                 = string
    metrics_server        = string
  })
}

variable "external_urls" {
  description = "URLs the UIs are published at (used for links and redirects)."
  type = object({
    grafana      = string
    prometheus   = string
    alertmanager = string
  })
}

variable "retention" {
  description = "Data retention per backend."
  type = object({
    metrics = string
    logs    = string
    traces  = string
  })
  default = {
    metrics = "7d"
    logs    = "72h"
    traces  = "72h"
  }
}

variable "storage_size" {
  description = "PersistentVolumeClaim size per backend."
  type = object({
    prometheus = string
    loki       = string
    tempo      = string
  })
  default = {
    prometheus = "10Gi"
    loki       = "5Gi"
    tempo      = "5Gi"
  }
}

variable "cost_per_cpu_hour" {
  description = "Reference price (USD) of one vCPU hour, used by the cost dashboard."
  type        = number
  default     = 0.0316
}

variable "cost_per_gib_hour" {
  description = "Reference price (USD) of one GiB of memory per hour, used by the cost dashboard."
  type        = number
  default     = 0.0042
}
