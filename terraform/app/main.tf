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

# Hard coded details for the application
locals {
  app_name  = "url-shortener"
  namespace = "url-shortener-ns"
  container_port = 5000
  container_image = "matheusmaximo/url-shortener:latest"
}

provider "aws" {
  region = var.aws_region
}

# This is to get access to the cluster. Requires ~/.kube/config
data "aws_eks_cluster" "this" {
  name = var.eks_cluster_name
}

# This is to get access to the cluster. Requires ~/.kube/config
data "aws_eks_cluster_auth" "this" {
  name = var.eks_cluster_name
}

# Once we get the access above, this will work to populate cluster details
provider "kubernetes" {
  host                    = data.aws_eks_cluster.this.endpoint
  token                   = data.aws_eks_cluster_auth.this.token
  cluster_ca_certificate  = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
}

# Namespace for the application
# This is different from the kube-system namespace used by AWS
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
    # Minimum 2 replicas to ensure AZ redundancy
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

          # 5000
          port {
            container_port = local.container_port
          }

          # Environment variables for the container to know the base URL
          # But as the base URL will be the ALB domain which is known just after deployment
          # I hardcoded this here as http://0.0.0.0:5000
          # This still needs a solution.
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

          # readiness probe to ensure the app is ready to serve traffic but for this app it is the same as liveness
          # as I have no underneath resources for the moment
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

    # As we use ALB Ingress, we do not need to expose the service as LoadBalancer
    type = "ClusterIP"

    # Port 80 on service will map to port 5000 on the container
    # This port will also map to the ALB listener port
    port {
      port        = 80
      target_port = local.container_port
      protocol    = "TCP"
    }
  }
}

# Ingress to expose the app via ALB
resource "kubernetes_ingress_v1" "app_ingress" {
  metadata {
    name      = "${local.app_name}-ingress"
    namespace = kubernetes_namespace_v1.app_ns.metadata[0].name

    # These annotations are required for ALB Ingress controller to work
    annotations = {
      "kubernetes.io/ingress.class"                  = "alb"
      # Ensure the ALB is internet-facing
      "alb.ingress.kubernetes.io/scheme"             = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"        = "ip"
      # The port the ALB will listen on
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
                # The port of the service we specified above
                number = kubernetes_service_v1.app_svc.spec[0].port[0].port
              }
            }
          }
        }
      }
    }
  }
}