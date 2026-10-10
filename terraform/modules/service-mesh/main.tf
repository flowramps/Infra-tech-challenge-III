locals {
  repository = "https://istio-release.storage.googleapis.com/charts"
}

resource "kubernetes_namespace_v1" "istio_system" {
  metadata {
    name = "istio-system"
  }
}

resource "kubernetes_namespace_v1" "istio_ingress" {
  metadata {
    name = "istio-ingress"
  }
}

# CRDs and cluster-wide resources.
resource "helm_release" "base" {
  name       = "istio-base"
  namespace  = kubernetes_namespace_v1.istio_system.metadata[0].name
  repository = local.repository
  chart      = "base"
  version    = var.istio_version
  wait       = true

  values = [yamlencode({
    defaultRevision = "default"
  })]
}

# Control plane.
resource "helm_release" "istiod" {
  name       = "istiod"
  namespace  = kubernetes_namespace_v1.istio_system.metadata[0].name
  repository = local.repository
  chart      = "istiod"
  version    = var.istio_version
  wait       = true
  timeout    = 600

  values = [yamlencode({
    pilot = {
      autoscaleEnabled = false
      replicaCount     = 2
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { cpu = "500m", memory = "512Mi" }
      }
    }
    global = {
      proxy = {
        resources = {
          requests = { cpu = "20m", memory = "64Mi" }
          limits   = { cpu = "500m", memory = "256Mi" }
        }
      }
    }
    meshConfig = {
      accessLogFile     = "/dev/stdout"
      accessLogEncoding = "JSON"
      # Prometheus scrapes application and Envoy metrics directly, so the
      # sidecar does not need to merge them.
      enablePrometheusMerge = false
      defaultConfig = {
        holdApplicationUntilProxyStarts = true
      }
      extensionProviders = [{
        name = "tempo"
        opentelemetry = {
          service = var.tracing_otlp_host
          port    = 4317
        }
      }]
    }
  })]

  depends_on = [helm_release.base]
}

# North-south traffic entry point, published on the host via a kind port mapping.
resource "helm_release" "ingress_gateway" {
  name       = "istio-ingress"
  namespace  = kubernetes_namespace_v1.istio_ingress.metadata[0].name
  repository = local.repository
  chart      = "gateway"
  version    = var.istio_version
  wait       = true
  timeout    = 600

  values = [yamlencode({
    autoscaling = {
      enabled     = true
      minReplicas = 2
      maxReplicas = 4
    }
    podDisruptionBudget = {
      maxUnavailable = 1
    }
    resources = {
      requests = { cpu = "50m", memory = "64Mi" }
      limits   = { cpu = "500m", memory = "256Mi" }
    }
    service = {
      type = "NodePort"
      ports = [
        { name = "status-port", port = 15021, protocol = "TCP", targetPort = 15021 },
        { name = "http2", port = 80, protocol = "TCP", targetPort = 80, nodePort = var.ingress_node_port },
      ]
    }
  })]

  depends_on = [helm_release.istiod]
}

# Mesh-wide policies: strict mTLS, tracing to Tempo and Prometheus monitors.
resource "helm_release" "mesh_config" {
  name      = "mesh-config"
  namespace = kubernetes_namespace_v1.istio_system.metadata[0].name
  chart     = "${path.module}/chart"
  wait      = true

  values = [yamlencode({
    tracing = {
      provider           = "tempo"
      samplingPercentage = var.tracing_sampling_percentage
    }
  })]

  depends_on = [helm_release.istiod]
}
