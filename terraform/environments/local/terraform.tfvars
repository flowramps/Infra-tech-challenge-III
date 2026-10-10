cluster_name = "tech-challenge"
node_image   = "kindest/node:v1.33.4"
worker_count = 2

host_ports = {
  ingress      = 8080
  grafana      = 3000
  prometheus   = 9090
  alertmanager = 9093
}

chart_versions = {
  kube_prometheus_stack = "92.3.0"
  loki                  = "6.55.0"
  tempo                 = "1.24.4"
  alloy                 = "1.13.1"
  metrics_server        = "3.14.0"
  istio                 = "1.30.5"
}

retention = {
  metrics = "7d"
  logs    = "72h"
  traces  = "72h"
}

tracing_sampling_percentage = 100
canary_weight               = 10
inventory_fault_rate        = 0.02
