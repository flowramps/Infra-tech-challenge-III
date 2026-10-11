output "namespace" {
  description = "Namespace of Argo CD."
  value       = helm_release.argocd.namespace
}
