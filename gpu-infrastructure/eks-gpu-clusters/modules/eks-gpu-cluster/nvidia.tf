# -----------------------------------------------------------------------------
# NVIDIA Device Plugin
# -----------------------------------------------------------------------------

resource "kubernetes_daemonset" "nvidia_device_plugin" {
  count = var.enable_nvidia_device_plugin ? 1 : 0

  metadata {
    name      = "nvidia-device-plugin-daemonset"
    namespace = "kube-system"

    labels = {
      name = "nvidia-device-plugin-ds"
    }
  }

  spec {
    selector {
      match_labels = {
        name = "nvidia-device-plugin-ds"
      }
    }

    strategy {
      type = "RollingUpdate"
    }

    template {
      metadata {
        labels = {
          name = "nvidia-device-plugin-ds"
        }
      }

      spec {
        # Only run on GPU nodes
        node_selector = {
          "nvidia.com/gpu" = "true"
        }

        # Tolerate GPU taint
        toleration {
          key      = "nvidia.com/gpu"
          operator = "Exists"
          effect   = "NoSchedule"
        }

        # Priority for system-critical pods
        priority_class_name = "system-node-critical"

        container {
          name  = "nvidia-device-plugin-ctr"
          image = "nvcr.io/nvidia/k8s-device-plugin:v0.14.3"

          env {
            name  = "FAIL_ON_INIT_ERROR"
            value = "false"
          }

          security_context {
            allow_privilege_escalation = false
            capabilities {
              drop = ["ALL"]
            }
          }

          volume_mount {
            name       = "device-plugin"
            mount_path = "/var/lib/kubelet/device-plugins"
          }
        }

        volume {
          name = "device-plugin"
          host_path {
            path = "/var/lib/kubelet/device-plugins"
          }
        }
      }
    }
  }

  depends_on = [
    aws_eks_node_group.gpu
  ]
}

# -----------------------------------------------------------------------------
# GPU Feature Discovery (optional, for detailed GPU info)
# -----------------------------------------------------------------------------

resource "kubernetes_daemonset" "gpu_feature_discovery" {
  count = var.enable_nvidia_device_plugin ? 1 : 0

  metadata {
    name      = "gpu-feature-discovery"
    namespace = "kube-system"

    labels = {
      app = "gpu-feature-discovery"
    }
  }

  spec {
    selector {
      match_labels = {
        app = "gpu-feature-discovery"
      }
    }

    template {
      metadata {
        labels = {
          app = "gpu-feature-discovery"
        }
      }

      spec {
        node_selector = {
          "nvidia.com/gpu" = "true"
        }

        toleration {
          key      = "nvidia.com/gpu"
          operator = "Exists"
          effect   = "NoSchedule"
        }

        container {
          name  = "gpu-feature-discovery"
          image = "nvcr.io/nvidia/gpu-feature-discovery:v0.8.2"

          env {
            name  = "GFD_SLEEP_INTERVAL"
            value = "60s"
          }

          env {
            name  = "GFD_FAIL_ON_INIT_ERROR"
            value = "true"
          }

          volume_mount {
            name       = "output-dir"
            mount_path = "/etc/kubernetes/node-feature-discovery/features.d"
          }

          volume_mount {
            name       = "host-sys"
            mount_path = "/sys"
            read_only  = true
          }

          security_context {
            privileged = true
          }
        }

        volume {
          name = "output-dir"
          host_path {
            path = "/etc/kubernetes/node-feature-discovery/features.d"
          }
        }

        volume {
          name = "host-sys"
          host_path {
            path = "/sys"
          }
        }
      }
    }
  }

  depends_on = [
    aws_eks_node_group.gpu
  ]
}
