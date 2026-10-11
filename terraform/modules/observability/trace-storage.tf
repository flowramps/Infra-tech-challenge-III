# Object storage for Tempo blocks: an S3-compatible gateway (Versity) inside
# the cluster, backed by a PersistentVolume.
#
# Why not Tempo's local filesystem backend: on Tempo 2.9 the blocklist poller
# walks the block directories while retention deletes compacted ones; a block
# removed mid-walk fails the whole poll (grafana/tempo#7712, unreleased), the
# block index stops updating and traces older than the in-memory window can no
# longer be found. Object listings are not affected, and object storage is
# what Tempo uses in production.
locals {
  trace_store      = "trace-store"
  trace_bucket     = "tempo"
  trace_store_host = "${local.trace_store}.${var.namespace}.svc.cluster.local:7070"
}

resource "random_password" "trace_store" {
  for_each = toset(["access_key", "secret_key"])

  length  = each.key == "access_key" ? 20 : 40
  special = false
}

resource "kubernetes_secret_v1" "trace_store" {
  metadata {
    name      = local.trace_store
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  data = {
    access-key = random_password.trace_store["access_key"].result
    secret-key = random_password.trace_store["secret_key"].result
  }
}

resource "kubernetes_persistent_volume_claim_v1" "trace_store" {
  metadata {
    name      = local.trace_store
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = var.storage_class
    resources {
      requests = { storage = var.storage_size.tempo }
    }
  }

  # local-path binds the volume only when the first pod is scheduled.
  wait_until_bound = false
}

resource "kubernetes_deployment_v1" "trace_store" {
  metadata {
    name      = local.trace_store
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels = {
      "app.kubernetes.io/name" = local.trace_store
    }
  }

  spec {
    replicas = 1

    # A single writer owns the volume.
    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        "app.kubernetes.io/name" = local.trace_store
      }
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name" = local.trace_store
        }
      }

      spec {
        automount_service_account_token = false

        security_context {
          run_as_non_root = true
          run_as_user     = 10001
          run_as_group    = 10001
          fs_group        = 10001
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name  = "versitygw"
          image = "versity/versitygw:v1.8.0"

          # With the posix backend a top-level directory is a bucket, so the
          # bucket is created before the gateway starts.
          command = ["/bin/sh", "-c"]
          args    = ["mkdir -p /data/${local.trace_bucket} && exec versitygw --port :7070 posix /data"]

          env {
            name = "ROOT_ACCESS_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.trace_store.metadata[0].name
                key  = "access-key"
              }
            }
          }
          env {
            name = "ROOT_SECRET_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.trace_store.metadata[0].name
                key  = "secret-key"
              }
            }
          }

          port {
            name           = "s3"
            container_port = 7070
          }

          readiness_probe {
            tcp_socket {
              port = "s3"
            }
            period_seconds = 5
          }
          liveness_probe {
            tcp_socket {
              port = "s3"
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }

          resources {
            requests = { cpu = "20m", memory = "32Mi" }
            limits   = { cpu = "500m", memory = "256Mi" }
          }

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities {
              drop = ["ALL"]
            }
          }

          volume_mount {
            name       = "data"
            mount_path = "/data"
          }
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.trace_store.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "trace_store" {
  metadata {
    name      = local.trace_store
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  spec {
    selector = {
      "app.kubernetes.io/name" = local.trace_store
    }

    port {
      name        = "s3"
      port        = 7070
      target_port = "s3"
    }
  }
}
