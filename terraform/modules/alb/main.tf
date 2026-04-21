resource "kubernetes_namespace" "app" {
  metadata {
    name = var.app_namespace
    labels = {
      environment = var.environment
      project     = var.project_name
    }
  }
}

resource "kubernetes_service" "app" {
  metadata {
    name      = "${var.project_name}-svc"
    namespace = kubernetes_namespace.app.metadata[0].name
    labels = {
      app         = var.project_name
      environment = var.environment
    }
  }

  spec {
    selector = {
      app = var.project_name
    }

    port {
      name        = "http"
      port        = 80
      target_port = var.app_port
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_ingress_v1" "app" {
  metadata {
    name      = "${var.project_name}-ingress"
    namespace = kubernetes_namespace.app.metadata[0].name

    annotations = {
      # Use the AWS Load Balancer Controller
      "kubernetes.io/ingress.class" = "alb"

      # internet-facing ALB in public subnets
      "alb.ingress.kubernetes.io/scheme" = "internet-facing"

      # IP target mode - registers pod IPs directly
      "alb.ingress.kubernetes.io/target-type" = "ip"

      # Public subnets where the ALB will be placed
      "alb.ingress.kubernetes.io/subnets" = join(",", var.public_subnet_ids)

      # Security group for the ALB (allows 80/443 from internet)
      "alb.ingress.kubernetes.io/security-groups" = var.alb_sg_id

      # Health check on /health endpoint
      "alb.ingress.kubernetes.io/healthcheck-path"             = "/health"
      "alb.ingress.kubernetes.io/healthcheck-interval-seconds" = "15"
      "alb.ingress.kubernetes.io/healthcheck-timeout-seconds"  = "5"
      "alb.ingress.kubernetes.io/healthy-threshold-count"      = "2"
      "alb.ingress.kubernetes.io/unhealthy-threshold-count"    = "3"

      # Enable access logs to S3
      "alb.ingress.kubernetes.io/load-balancer-attributes" = "access_logs.s3.enabled=false"

      # Tags on the ALB resource
      "alb.ingress.kubernetes.io/tags" = "Environment=${var.environment},Project=${var.project_name},ManagedBy=Terraform"

      "alb.ingress.kubernetes.io/listen-ports" = "[{\"HTTP\": 80}]"
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
              name = kubernetes_service.app.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  # Wait for the LB controller to be ready before creating the Ingress
  depends_on = [var.lb_controller_depends_on]
}

data "kubernetes_ingress_v1" "app" {
  metadata {
    name      = kubernetes_ingress_v1.app.metadata[0].name
    namespace = kubernetes_ingress_v1.app.metadata[0].namespace
  }

  depends_on = [kubernetes_ingress_v1.app]
}
