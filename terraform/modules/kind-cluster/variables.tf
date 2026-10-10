variable "name" {
  description = "Cluster name (also used for the kubeconfig context: kind-<name>)."
  type        = string
}

variable "node_image" {
  description = "kindest/node image that defines the Kubernetes version."
  type        = string
}

variable "worker_count" {
  description = "Number of worker nodes."
  type        = number
  default     = 2

  validation {
    condition     = var.worker_count >= 2
    error_message = "The challenge requires at least 2 worker nodes."
  }
}

variable "pod_subnet" {
  description = "CIDR used for pod IPs."
  type        = string
  default     = "10.244.0.0/16"
}

variable "service_subnet" {
  description = "CIDR used for ClusterIP services."
  type        = string
  default     = "10.96.0.0/16"
}

variable "port_mappings" {
  description = "NodePorts published on the host through the control-plane container."
  type = list(object({
    node_port = number
    host_port = number
  }))
  default = []
}
