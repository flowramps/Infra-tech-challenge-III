locals {
  # Single entry point: the ingress gateway NodePort is published on the host
  # and every UI is routed by hostname (<name>.<ingress_domain>).
  ingress_node_port = 30080
  ingress_url       = var.ingress_host_port == 80 ? "" : ":${var.ingress_host_port}"
  hosts = {
    application  = "app.${var.ingress_domain}"
    grafana      = "grafana.${var.ingress_domain}"
    prometheus   = "prometheus.${var.ingress_domain}"
    alertmanager = "alertmanager.${var.ingress_domain}"
    argocd       = "argocd.${var.ingress_domain}"
  }
  urls = { for name, host in local.hosts : name => "http://${host}${local.ingress_url}" }
}

module "cluster" {
  source = "./modules/kind-cluster"

  name         = var.cluster_name
  node_image   = var.node_image
  worker_count = var.worker_count
  port_mappings = [{
    node_port = local.ingress_node_port
    host_port = var.ingress_host_port
  }]
}

module "observability" {
  source = "./modules/observability"

  chart_versions = {
    kube_prometheus_stack = var.chart_versions.kube_prometheus_stack
    loki                  = var.chart_versions.loki
    tempo                 = var.chart_versions.tempo
    alloy                 = var.chart_versions.alloy
    metrics_server        = var.chart_versions.metrics_server
  }
  external_urls = {
    grafana      = local.urls.grafana
    prometheus   = local.urls.prometheus
    alertmanager = local.urls.alertmanager
  }
  retention = var.retention
  telegram = {
    bot_token = var.telegram_bot_token
    chat_id   = var.telegram_chat_id
  }
}

module "service_mesh" {
  source = "./modules/service-mesh"

  istio_version               = var.chart_versions.istio
  tracing_otlp_host           = module.observability.tempo_otlp_grpc_host
  tracing_sampling_percentage = var.tracing_sampling_percentage
  ingress_node_port           = local.ingress_node_port
  platform_routes = [
    { name = "grafana", host = local.hosts.grafana, service = "kube-prometheus-stack-grafana.monitoring.svc.cluster.local", port = 80 },
    { name = "prometheus", host = local.hosts.prometheus, service = "kube-prometheus-stack-prometheus.monitoring.svc.cluster.local", port = 9090 },
    { name = "alertmanager", host = local.hosts.alertmanager, service = "kube-prometheus-stack-alertmanager.monitoring.svc.cluster.local", port = 9093 },
    { name = "argocd", host = local.hosts.argocd, service = "argocd-server.argocd.svc.cluster.local", port = 80 },
  ]

  # Mesh monitors need the Prometheus Operator CRDs and Envoy exports spans to Tempo.
  depends_on = [module.observability]
}

module "gitops" {
  source = "./modules/gitops"

  chart_version = var.chart_versions.argo_cd
  external_url  = local.urls.argocd

  # Argo CD ServiceMonitors need the Prometheus Operator CRDs.
  depends_on = [module.observability]
}

module "sample_app" {
  source = "./modules/sample-app"

  argocd_namespace          = module.gitops.namespace
  argocd_apps_chart_version = var.chart_versions.argocd_apps
  repo_url                  = var.gitops_repo_url
  target_revision           = var.gitops_revision
  monitoring_namespace      = module.observability.namespace
  ingress_namespace         = module.service_mesh.ingress_namespace
  ingress_gateway           = module.service_mesh.ingress_gateway
  ingress_host              = local.hosts.application
  otlp_endpoint             = "http://${module.observability.tempo_otlp_grpc_host}:4317"
  canary_weight             = var.canary_weight
  inventory_fault_rate      = var.inventory_fault_rate

  # Sidecar injection and Istio CRDs must exist before the application.
  depends_on = [module.service_mesh, module.gitops]
}
