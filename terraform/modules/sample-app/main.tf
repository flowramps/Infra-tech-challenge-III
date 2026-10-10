resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.namespace
    labels = {
      "istio-injection" = "enabled"
    }
  }
}

# The application is delivered by Argo CD. Terraform only declares *what* to
# sync (repository, path, revision) and the environment parameters; the image
# tag lives in the chart values in Git and is bumped by the CD pipeline.
resource "helm_release" "argocd_application" {
  name       = "sample-app"
  namespace  = var.argocd_namespace
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = var.argocd_apps_chart_version
  wait       = true

  values = [yamlencode({
    projects = {
      sample-app = {
        namespace   = var.argocd_namespace
        description = "Sample application: one repository, one namespace, no cluster-scoped resources."
        sourceRepos = [var.repo_url]
        destinations = [{
          server    = "https://kubernetes.default.svc"
          namespace = kubernetes_namespace_v1.this.metadata[0].name
        }]
        clusterResourceWhitelist = []
        namespaceResourceWhitelist = [{
          group = "*"
          kind  = "*"
        }]
      }
    }

    applications = {
      sample-app = {
        namespace  = var.argocd_namespace
        project    = "sample-app"
        finalizers = ["resources-finalizer.argocd.argoproj.io"]
        source = {
          repoURL        = var.repo_url
          targetRevision = var.target_revision
          path           = var.chart_path
          helm = {
            releaseName = "sample-app"
            valuesObject = {
              otlpEndpoint = var.otlp_endpoint
              canaryWeight = var.canary_weight
              faultRate    = var.inventory_fault_rate
              network = {
                monitoringNamespace = var.monitoring_namespace
                ingressNamespace    = var.ingress_namespace
              }
              gateway = {
                selector = var.ingress_gateway_selector
              }
            }
          }
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = kubernetes_namespace_v1.this.metadata[0].name
        }
        syncPolicy = {
          # selfHeal reverts manual changes in the cluster: Git is the only
          # way to change the application.
          automated = {
            prune    = true
            selfHeal = true
          }
          syncOptions = ["ServerSideApply=true"]
          retry = {
            limit = 5
            backoff = {
              duration    = "10s"
              factor      = 2
              maxDuration = "3m"
            }
          }
        }
      }
    }
  })]
}
