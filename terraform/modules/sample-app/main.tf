locals {
  # Content hash of the application: a code change produces a new tag, which
  # rebuilds the image and triggers a rolling update.
  image_tag = substr(sha1(join("", [
    for f in sort(fileset(var.source_dir, "**")) : filesha1("${var.source_dir}/${f}")
  ])), 0, 12)
  image_repository = "sample-app"
  image            = "${local.image_repository}:${local.image_tag}"
}

resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.namespace
    labels = {
      "istio-injection" = "enabled"
    }
  }
}

# kind nodes cannot pull from the local Docker daemon, so the image is built
# on the host and loaded straight into every node.
resource "terraform_data" "image" {
  triggers_replace = [local.image, var.cluster_name]

  provisioner "local-exec" {
    command = "docker build -t ${local.image} ${var.source_dir} && kind load docker-image ${local.image} --name ${var.cluster_name}"
  }
}

resource "helm_release" "this" {
  name      = "sample-app"
  namespace = kubernetes_namespace_v1.this.metadata[0].name
  chart     = "${path.module}/chart"
  wait      = true
  timeout   = 600

  values = [yamlencode({
    image = {
      repository = local.image_repository
      tag        = local.image_tag
    }
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
  })]

  depends_on = [terraform_data.image]
}
