# Alertmanager notification channel. In a real environment this webhook would
# be Slack, PagerDuty or Opsgenie; locally an echo server logs every
# notification to stdout, so alerts can be inspected in Loki:
#   {namespace="monitoring", app="alert-sink"}
resource "kubernetes_deployment_v1" "alert_sink" {
  metadata {
    name      = local.alert_sink
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels = {
      "app.kubernetes.io/name" = local.alert_sink
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        "app.kubernetes.io/name" = local.alert_sink
      }
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name" = local.alert_sink
        }
      }

      spec {
        automount_service_account_token = false

        container {
          name  = "echo"
          image = "mendhak/http-https-echo:42"

          env {
            name  = "HTTP_PORT"
            value = "8080"
          }
          env {
            name  = "LOG_IGNORE_PATH"
            value = "/healthz"
          }

          port {
            name           = "http"
            container_port = 8080
          }

          readiness_probe {
            http_get {
              path = "/healthz"
              port = "http"
            }
          }

          resources {
            requests = { cpu = "10m", memory = "32Mi" }
            limits   = { cpu = "100m", memory = "128Mi" }
          }

          security_context {
            allow_privilege_escalation = false
            run_as_non_root            = true
            run_as_user                = 1000
            capabilities {
              drop = ["ALL"]
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "alert_sink" {
  metadata {
    name      = local.alert_sink
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  spec {
    selector = {
      "app.kubernetes.io/name" = local.alert_sink
    }

    port {
      name        = "http"
      port        = 8080
      target_port = "http"
    }
  }
}
