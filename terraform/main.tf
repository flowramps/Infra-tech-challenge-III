locals {
  # NodePorts are fixed so kind can publish them on the host at creation time.
  node_ports = {
    ingress      = 30080
    grafana      = 30030
    prometheus   = 30090
    alertmanager = 30093
  }
}

module "cluster" {
  source = "./modules/kind-cluster"

  name         = var.cluster_name
  node_image   = var.node_image
  worker_count = var.worker_count
  port_mappings = [
    for name, node_port in local.node_ports : {
      node_port = node_port
      host_port = var.host_ports[name]
    }
  ]
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
  node_ports = {
    grafana      = local.node_ports.grafana
    prometheus   = local.node_ports.prometheus
    alertmanager = local.node_ports.alertmanager
  }
  retention = var.retention
}

module "service_mesh" {
  source = "./modules/service-mesh"

  istio_version               = var.chart_versions.istio
  tracing_otlp_host           = module.observability.tempo_otlp_grpc_host
  tracing_sampling_percentage = var.tracing_sampling_percentage
  ingress_node_port           = local.node_ports.ingress

  # Mesh monitors need the Prometheus Operator CRDs and Envoy exports spans to Tempo.
  depends_on = [module.observability]
}

module "sample_app" {
  source = "./modules/sample-app"

  cluster_name             = module.cluster.name
  source_dir               = "${path.root}/../app"
  monitoring_namespace     = module.observability.namespace
  ingress_namespace        = module.service_mesh.ingress_namespace
  ingress_gateway_selector = module.service_mesh.ingress_gateway_selector
  otlp_endpoint            = "http://${module.observability.tempo_otlp_grpc_host}:4317"
  canary_weight            = var.canary_weight
  inventory_fault_rate     = var.inventory_fault_rate

  # Sidecar injection and Istio CRDs must exist before the application.
  depends_on = [module.service_mesh]
}
