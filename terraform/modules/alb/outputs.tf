output "alb_dns_name" {
  description = "DNS name of the ALB provisioned by the AWS Load Balancer Controller"
  value = try(
    data.kubernetes_ingress_v1.app.status[0].load_balancer[0].ingress[0].hostname,
    "ALB provisioning — run terraform refresh to get DNS name"
  )
}

output "alb_arn_suffix" {
  description = "ARN suffix of the ALB — used by CloudWatch alarms (format: app/name/id)"
  # Derived from the hostname: xxx.region.elb.amazonaws.com → app/xxx/id
  # Falls back to empty string if ALB is not yet provisioned (alarms are skipped when empty)
  value = try(
    regex("app/[^.]+/[^.]+",
      data.kubernetes_ingress_v1.app.status[0].load_balancer[0].ingress[0].hostname
    ),
    ""
  )
}

output "app_namespace" {
  description = "Kubernetes namespace where the app Ingress and Service are deployed"
  value       = kubernetes_namespace.app.metadata[0].name
}

output "service_name" {
  description = "Kubernetes Service name for the app"
  value       = kubernetes_service.app.metadata[0].name
}

output "ingress_name" {
  description = "Kubernetes Ingress name"
  value       = kubernetes_ingress_v1.app.metadata[0].name
}
