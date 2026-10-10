# Least privilege access for the team that operates the application: it can
# inspect and scale workloads and read logs, but cannot read Secrets, change
# RBAC or touch mesh security policies.
resource "kubernetes_role_v1" "developer" {
  metadata {
    name      = "sample-app-developer"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "pods/log", "services", "endpoints", "configmaps", "events"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "replicasets"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments/scale"]
    verbs      = ["get", "update", "patch"]
  }

  rule {
    api_groups = ["autoscaling", "policy"]
    resources  = ["horizontalpodautoscalers", "poddisruptionbudgets"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["networking.istio.io"]
    resources  = ["virtualservices", "destinationrules", "gateways"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_role_binding_v1" "developer" {
  metadata {
    name      = "sample-app-developers"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.developer.metadata[0].name
  }

  subject {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Group"
    name      = var.developers_group
  }
}
