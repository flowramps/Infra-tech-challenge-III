locals {
  loki_url    = "http://loki.${var.namespace}.svc.cluster.local:3100"
  tempo_url   = "http://tempo.${var.namespace}.svc.cluster.local:3200"
  prometheus  = "http://kube-prometheus-stack-prometheus.${var.namespace}.svc.cluster.local:9090"
  alert_sink  = "alert-sink"
  dashboards  = fileset("${path.module}/dashboards", "*.json")
  common_helm = { timeout = 900, wait = true }
}

resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/part-of" = "observability"
    }
  }
}

# --- Grafana credentials --------------------------------------------------------
resource "random_password" "grafana_admin" {
  length  = 24
  special = false
}

resource "kubernetes_secret_v1" "grafana_admin" {
  metadata {
    name      = "grafana-admin"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  data = {
    admin-user     = "admin"
    admin-password = random_password.grafana_admin.result
  }
}

# --- Resource metrics API (required by HPA and kubectl top) -------------------
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = var.chart_versions.metrics_server
  timeout    = local.common_helm.timeout
  wait       = local.common_helm.wait

  values = [yamlencode({
    # kind kubelets use self-signed serving certificates.
    args = ["--kubelet-insecure-tls"]
    resources = {
      requests = { cpu = "50m", memory = "64Mi" }
      limits   = { cpu = "200m", memory = "128Mi" }
    }
  })]
}

# --- Metrics, alerting and dashboards ------------------------------------------
resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  namespace  = kubernetes_namespace_v1.this.metadata[0].name
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.chart_versions.kube_prometheus_stack
  timeout    = local.common_helm.timeout
  wait       = local.common_helm.wait

  values = [templatefile("${path.module}/values/kube-prometheus-stack.yaml.tftpl", {
    storage_class           = var.storage_class
    prometheus_retention    = var.retention.metrics
    prometheus_storage_size = var.storage_size.prometheus
    prometheus_node_port    = var.node_ports.prometheus
    alertmanager_node_port  = var.node_ports.alertmanager
    grafana_node_port       = var.node_ports.grafana
    grafana_admin_secret    = kubernetes_secret_v1.grafana_admin.metadata[0].name
    alert_webhook_url       = "http://${local.alert_sink}.${var.namespace}.svc.cluster.local:8080/alerts"
    loki_url                = local.loki_url
    tempo_url               = local.tempo_url
  })]
}

# --- Logs ----------------------------------------------------------------------
resource "helm_release" "loki" {
  name       = "loki"
  namespace  = kubernetes_namespace_v1.this.metadata[0].name
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = var.chart_versions.loki
  timeout    = local.common_helm.timeout
  wait       = local.common_helm.wait

  values = [templatefile("${path.module}/values/loki.yaml.tftpl", {
    storage_class = var.storage_class
    storage_size  = var.storage_size.loki
    retention     = var.retention.logs
  })]
}

resource "helm_release" "alloy" {
  name       = "alloy"
  namespace  = kubernetes_namespace_v1.this.metadata[0].name
  repository = "https://grafana.github.io/helm-charts"
  chart      = "alloy"
  version    = var.chart_versions.alloy
  timeout    = local.common_helm.timeout
  wait       = local.common_helm.wait

  values = [templatefile("${path.module}/values/alloy.yaml.tftpl", {
    loki_push_url = "${local.loki_url}/loki/api/v1/push"
  })]

  depends_on = [helm_release.loki, helm_release.kube_prometheus_stack]
}

# --- Traces --------------------------------------------------------------------
resource "helm_release" "tempo" {
  name       = "tempo"
  namespace  = kubernetes_namespace_v1.this.metadata[0].name
  repository = "https://grafana.github.io/helm-charts"
  chart      = "tempo"
  version    = var.chart_versions.tempo
  timeout    = local.common_helm.timeout
  wait       = local.common_helm.wait

  values = [templatefile("${path.module}/values/tempo.yaml.tftpl", {
    storage_class               = var.storage_class
    storage_size                = var.storage_size.tempo
    retention                   = var.retention.traces
    prometheus_remote_write_url = "${local.prometheus}/api/v1/write"
  })]

  # The chart ships a ServiceMonitor, whose CRD comes with kube-prometheus-stack.
  depends_on = [helm_release.kube_prometheus_stack]
}

# --- Grafana dashboards (loaded by the Grafana sidecar) --------------------------
resource "kubernetes_config_map_v1" "dashboards" {
  for_each = local.dashboards

  metadata {
    name      = "dashboard-${trimsuffix(each.value, ".json")}"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels = {
      grafana_dashboard = "1"
    }
    annotations = {
      grafana_folder = "Tech Challenge"
    }
  }

  data = {
    (each.value) = templatefile("${path.module}/dashboards/${each.value}", {
      cost_per_cpu_hour = var.cost_per_cpu_hour
      cost_per_gib_hour = var.cost_per_gib_hour
    })
  }
}
