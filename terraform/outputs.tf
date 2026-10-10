output "kubeconfig_context" {
  description = "kubectl context of the cluster."
  value       = module.cluster.kubeconfig_context
}

output "urls" {
  description = "Entry points published on the host."
  value = {
    application  = "http://localhost:${var.host_ports.ingress}"
    grafana      = "http://localhost:${var.host_ports.grafana}"
    prometheus   = "http://localhost:${var.host_ports.prometheus}"
    alertmanager = "http://localhost:${var.host_ports.alertmanager}"
  }
}

output "grafana_admin_password" {
  description = "Grafana admin password (user: admin)."
  value       = module.observability.grafana_admin_password
  sensitive   = true
}

output "sample_app_image" {
  description = "Application image loaded into the cluster."
  value       = module.sample_app.image
}
