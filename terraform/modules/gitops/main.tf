resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.namespace
  }
}

# Argo CD reconciles the application from Git (pull model). Nothing outside
# the cluster needs credentials to reach the Kubernetes API.
resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = kubernetes_namespace_v1.this.metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.chart_version
  wait       = true
  timeout    = 600

  values = [
    file("${path.module}/values.yaml"),
    yamlencode({ configs = { cm = { url = var.external_url } } }),
  ]
}
