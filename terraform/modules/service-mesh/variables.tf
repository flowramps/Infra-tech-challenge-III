variable "istio_version" {
  description = "Istio Helm chart version (base, istiod and gateway)."
  type        = string
}

variable "tracing_otlp_host" {
  description = "In-cluster host of the OTLP/gRPC endpoint that receives Envoy spans."
  type        = string
}

variable "tracing_sampling_percentage" {
  description = "Percentage of requests traced by the mesh."
  type        = number
  default     = 100
}

variable "platform_routes" {
  description = "Platform UIs published through the ingress gateway, routed by hostname."
  type = list(object({
    name    = string
    host    = string
    service = string
    port    = number
  }))
  default = []
}

variable "ingress_node_port" {
  description = "NodePort of the ingress gateway HTTP listener."
  type        = number
}
