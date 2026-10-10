locals {
  # Control-plane components bind to 127.0.0.1 by default in kind. Exposing
  # their metrics endpoints lets Prometheus monitor the whole control plane.
  control_plane_patches = [
    <<-YAML
    kind: ClusterConfiguration
    controllerManager:
      extraArgs:
        bind-address: "0.0.0.0"
    scheduler:
      extraArgs:
        bind-address: "0.0.0.0"
    etcd:
      local:
        extraArgs:
          listen-metrics-urls: "http://0.0.0.0:2381"
    YAML
    ,
    <<-YAML
    kind: KubeProxyConfiguration
    metricsBindAddress: "0.0.0.0:10249"
    YAML
  ]
}

resource "kind_cluster" "this" {
  name           = var.name
  node_image     = var.node_image
  wait_for_ready = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    networking {
      api_server_address = "127.0.0.1"
      pod_subnet         = var.pod_subnet
      service_subnet     = var.service_subnet
      kube_proxy_mode    = "iptables"
    }

    node {
      role                   = "control-plane"
      kubeadm_config_patches = local.control_plane_patches

      dynamic "extra_port_mappings" {
        for_each = var.port_mappings
        content {
          container_port = extra_port_mappings.value.node_port
          host_port      = extra_port_mappings.value.host_port
          listen_address = "127.0.0.1"
          protocol       = "TCP"
        }
      }
    }

    dynamic "node" {
      for_each = range(var.worker_count)
      content {
        role = "worker"
        # Spreads workers across two fake zones so topology spread
        # constraints behave like in a multi-AZ cluster.
        labels = {
          "topology.kubernetes.io/zone" = "zone-${node.value % 2}"
        }
      }
    }
  }
}
