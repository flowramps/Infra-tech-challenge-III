output "name" {
  description = "Cluster name."
  value       = kind_cluster.this.name
}

output "endpoint" {
  description = "Kubernetes API server URL."
  value       = kind_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  description = "API server CA certificate (PEM)."
  value       = kind_cluster.this.cluster_ca_certificate
}

output "client_certificate" {
  description = "Admin client certificate (PEM)."
  value       = kind_cluster.this.client_certificate
}

output "client_key" {
  description = "Admin client key (PEM)."
  value       = kind_cluster.this.client_key
  sensitive   = true
}

output "kubeconfig_context" {
  description = "kubectl context created for this cluster."
  value       = "kind-${kind_cluster.this.name}"
}
