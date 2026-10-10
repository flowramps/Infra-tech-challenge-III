output "ingress_gateway" {
  description = "Shared Gateway (<namespace>/<name>) that VirtualServices attach to."
  value       = "${kubernetes_namespace_v1.istio_ingress.metadata[0].name}/platform"
}

output "ingress_namespace" {
  description = "Namespace of the ingress gateway."
  value       = kubernetes_namespace_v1.istio_ingress.metadata[0].name
}
