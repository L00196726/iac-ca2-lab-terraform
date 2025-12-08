output "kubernetes_ingress_v1_app_ingress_hostname" {
  description = "The ALB Ingress hostname to access the app"
  value       = "http://${kubernetes_ingress_v1.app_ingress.status[0].load_balancer[0].ingress[0].hostname}/"
}