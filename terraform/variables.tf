variable "cluster_name" {
  description = "Name of the kind cluster."
  type        = string
}

variable "node_image" {
  description = "kindest/node image (defines the Kubernetes version)."
  type        = string
}

variable "worker_count" {
  description = "Number of worker nodes."
  type        = number
  default     = 2
}

variable "ingress_domain" {
  description = "Domain of the UIs (<name>.<domain>). *.localhost resolves to 127.0.0.1 without DNS; 127.0.0.1.nip.io is the public DNS alternative."
  type        = string
  default     = "localhost"
}

variable "ingress_host_port" {
  description = "Host port (127.0.0.1) of the ingress gateway."
  type        = number
  default     = 80
}

variable "chart_versions" {
  description = "Pinned Helm chart versions."
  type = object({
    kube_prometheus_stack = string
    loki                  = string
    tempo                 = string
    alloy                 = string
    metrics_server        = string
    istio                 = string
    argo_cd               = string
    argocd_apps           = string
  })
}

variable "retention" {
  description = "Data retention for metrics, logs and traces."
  type = object({
    metrics = string
    logs    = string
    traces  = string
  })
}

variable "tracing_sampling_percentage" {
  description = "Percentage of requests traced by the service mesh."
  type        = number
  default     = 100
}

variable "canary_weight" {
  description = "Percentage of orders traffic routed to the v2 canary."
  type        = number
  default     = 10
}

variable "inventory_fault_rate" {
  description = "Fraction of inventory requests that fail on purpose."
  type        = number
  default     = 0.02
}

variable "gitops_repo_url" {
  description = "Git repository Argo CD syncs the application from."
  type        = string
}

variable "gitops_revision" {
  description = "Branch Argo CD tracks (the Makefile passes the checked-out branch)."
  type        = string
  default     = "main"
}
