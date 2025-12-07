terraform {
  # Minimal version required by "terraform-aws-modules/vpc/aws"
  required_version = ">= 1.5.7"

  # Minimal version required by "terraform-aws-modules/eks/aws"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.25"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
  }
}

locals {
  app_name  = "url-shortener"
  namespace = "url-shortener-ns"
  container_port = 5000
  container_image = "matheusmaximo/url-shortener:latest"
}

provider "aws" {
  region = var.aws_region
}

data "aws_eks_cluster" "this" {
  name = var.eks_cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = var.eks_cluster_name
}

provider "kubernetes" {
  host                    = data.aws_eks_cluster.this.endpoint
  token                   = data.aws_eks_cluster_auth.this.token
  cluster_ca_certificate  = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
}

# Namespace for the application
resource "kubernetes_namespace_v1" "app_ns" {
  metadata {
    name = local.namespace
  }
}

# Deployment for url-shortener
resource "kubernetes_deployment_v1" "app" {
  metadata {
    name      = local.app_name
    namespace = kubernetes_namespace_v1.app_ns.metadata[0].name
    labels = {
      app = local.app_name
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = local.app_name
      }
    }

    template {
      metadata {
        labels = {
          app = local.app_name
        }
      }

      spec {
        container {
          name  = local.app_name
          image = local.container_image

          port {
            container_port = local.container_port
          }

          env {
            name  = "BASE_URL"
            value = "http://0.0.0.0:${local.container_port}/"
          }

          # basic health check (relies on /health)
          liveness_probe {
            http_get {
              path = "/health"
              port = local.container_port
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = local.container_port
            }
            initial_delay_seconds = 3
            period_seconds        = 5
          }
        }
      }
    }
  }
}

# Service to expose the app
resource "kubernetes_service_v1" "app_svc" {
  metadata {
    name      = "${local.app_name}-svc"
    namespace = kubernetes_namespace_v1.app_ns.metadata[0].name

    labels = {
      app = local.app_name
    }
  }

  spec {
    selector = {
      app = local.app_name
    }

    type = "ClusterIP"

    port {
      port        = 80
      target_port = local.container_port
      protocol    = "TCP"
    }
  }
}

resource "kubernetes_ingress_v1" "app_ingress" {
  metadata {
    name      = "${local.app_name}-ingress"
    namespace = kubernetes_namespace_v1.app_ns.metadata[0].name

    annotations = {
      "kubernetes.io/ingress.class"                  = "alb"
      "alb.ingress.kubernetes.io/scheme"             = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"        = "ip"
      "alb.ingress.kubernetes.io/listen-ports"       = "[{\"HTTP\": 80}]"
    }
  }

  spec {
    rule {
      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service_v1.app_svc.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}