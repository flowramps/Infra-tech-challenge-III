output "namespace" {
  description = "Observability namespace."
  value       = kubernetes_namespace_v1.this.metadata[0].name
}

output "tempo_otlp_grpc_host" {
  description = "In-cluster host that receives OTLP/gRPC spans (port 4317)."
  value       = "tempo.${var.namespace}.svc.cluster.local"
}

output "grafana_admin_password" {
  description = "Grafana admin password."
  value       = random_password.grafana_admin.result
  sensitive   = true
}
