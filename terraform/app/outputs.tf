output "service_hostname_hint" {
  description = "As we are using LoadBalancer type, use kubectl to get the external hostname"
  value       = "Run: kubectl get svc -n ${kubernetes_namespace_v1.app_ns.metadata[0].name} ${kubernetes_service_v1.app_svc.metadata[0].name}"
}