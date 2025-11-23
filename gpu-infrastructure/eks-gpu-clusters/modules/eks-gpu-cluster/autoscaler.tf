# -----------------------------------------------------------------------------
# Cluster Autoscaler
# -----------------------------------------------------------------------------

resource "kubernetes_service_account" "cluster_autoscaler" {
  count = var.enable_cluster_autoscaler ? 1 : 0

  metadata {
    name      = "cluster-autoscaler"
    namespace = "kube-system"

    labels = {
      "app.kubernetes.io/name" = "cluster-autoscaler"
    }

    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.cluster_autoscaler[0].arn
    }
  }
}

resource "helm_release" "cluster_autoscaler" {
  count = var.enable_cluster_autoscaler ? 1 : 0

  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  version    = "9.35.0"
  namespace  = "kube-system"

  set {
    name  = "autoDiscovery.clusterName"
    value = var.cluster_name
  }

  set {
    name  = "awsRegion"
    value = data.aws_region.current.name
  }

  set {
    name  = "rbac.serviceAccount.create"
    value = "false"
  }

  set {
    name  = "rbac.serviceAccount.name"
    value = "cluster-autoscaler"
  }

  # GPU-specific settings
  set {
    name  = "extraArgs.skip-nodes-with-local-storage"
    value = "false"
  }

  set {
    name  = "extraArgs.skip-nodes-with-system-pods"
    value = "false"
  }

  set {
    name  = "extraArgs.balance-similar-node-groups"
    value = "true"
  }

  set {
    name  = "extraArgs.expander"
    value = "least-waste"
  }

  # Scale down settings - conservative for GPU nodes
  set {
    name  = "extraArgs.scale-down-delay-after-add"
    value = "10m"
  }

  set {
    name  = "extraArgs.scale-down-delay-after-delete"
    value = "10s"
  }

  set {
    name  = "extraArgs.scale-down-delay-after-failure"
    value = "3m"
  }

  set {
    name  = "extraArgs.scale-down-unneeded-time"
    value = "10m"
  }

  set {
    name  = "extraArgs.scale-down-utilization-threshold"
    value = "0.5"
  }

  # Node group discovery
  set {
    name  = "extraArgs.node-group-auto-discovery"
    value = "asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/${var.cluster_name}"
  }

  depends_on = [
    kubernetes_service_account.cluster_autoscaler,
    aws_eks_node_group.cpu
  ]
}

data "aws_region" "current" {}
