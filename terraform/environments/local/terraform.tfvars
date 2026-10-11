cluster_name = "tech-challenge"
node_image   = "kindest/node:v1.33.4"
worker_count = 2

# UIs at http://<name>.localhost (resolved to 127.0.0.1 by the browser, no DNS).
# Where *.localhost does not resolve, use ingress_domain = "127.0.0.1.nip.io".
ingress_domain    = "localhost"
ingress_host_port = 80

chart_versions = {
  kube_prometheus_stack = "92.3.0"
  loki                  = "6.55.0"
  tempo                 = "1.24.4"
  alloy                 = "1.13.1"
  metrics_server        = "3.14.0"
  istio                 = "1.30.5"
  argo_cd               = "10.10.2"
  argocd_apps           = "2.0.6"
}

retention = {
  metrics = "7d"
  logs    = "72h"
  traces  = "72h"
}

tracing_sampling_percentage = 100
canary_weight               = 10
inventory_fault_rate        = 0.02

gitops_repo_url = "https://github.com/flowramps/Infra-tech-challenge-III.git"
