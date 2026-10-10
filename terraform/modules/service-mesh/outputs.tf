output "ingress_gateway_selector" {
  description = "Label selecting the ingress gateway pods, used by Gateway resources."
  value       = { istio = "ingress" }
}

output "ingress_namespace" {
  description = "Namespace of the ingress gateway."
  value       = kubernetes_namespace_v1.istio_ingress.metadata[0].name
}
