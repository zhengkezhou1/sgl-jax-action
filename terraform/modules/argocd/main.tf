resource "kubernetes_namespace" "argocd" {
  metadata {
    name = var.namespace
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.chart_version
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  # 原子性部署：等待所有资源就绪
  wait             = true
  create_namespace = false # 我们上面显式管理了 namespace 资源

  # 传递自定义配置
  values = [
    var.values_yaml
  ]
}
