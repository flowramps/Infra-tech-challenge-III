output "namespace" {
  description = "Namespace of the sample application."
  value       = kubernetes_namespace_v1.this.metadata[0].name
}

output "image" {
  description = "Image deployed to the cluster."
  value       = local.image
}
