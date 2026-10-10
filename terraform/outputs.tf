output "kubeconfig_context" {
  description = "kubectl context of the cluster."
  value       = module.cluster.kubeconfig_context
}

output "urls" {
  description = "UIs published through the ingress gateway."
  value       = local.urls
}

output "grafana_admin_password" {
  description = "Grafana admin password (user: admin)."
  value       = module.observability.grafana_admin_password
  sensitive   = true
}

output "argocd_application" {
  description = "Argo CD Application that delivers the sample app."
  value       = module.sample_app.argocd_application
}
