output "namespace" {
  description = "Namespace of the sample application."
  value       = kubernetes_namespace_v1.this.metadata[0].name
}

output "argocd_application" {
  description = "Argo CD Application that delivers the sample app."
  value       = "${var.argocd_namespace}/sample-app"
}
