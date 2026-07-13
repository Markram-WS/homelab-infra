output "kubeconfig" {
  description = "Kubeconfig for the cluster"
  value       = module.bootstrap.kubeconfig_raw
  sensitive   = true
}

output "kubeconfig_raw" {
  value = nonsensitive(module.bootstrap.kubeconfig_raw)
}

output "controlplane_ip" {
  description = "Control plane node IP"
  value       = var.controlplane_ip
}

output "cluster_endpoint" {
  description = "Cluster API endpoint"
  value       = "https://${var.controlplane_ip}:6443"
}

output "tailscale_operator_namespace" {
  description = "Namespace where Tailscale operator is installed"
  value       = "platform"
}

output "flux_namespace" {
  description = "Namespace where Flux CD is installed"
  value       = "flux-system"
}

output "ops_kubeconfig" {
  description = "Kubeconfig for ops-user (limited RBAC — readonly + svc-writer per app_repos.namespaces)"
  value = templatefile("${path.module}/templates/ops-kubeconfig.tftpl", {
    cluster_name           = var.cluster_name
    ca_cert_b64            = module.bootstrap.ca_certificate_b64
    server_ip              = var.tailscale_domain != "" ? "k8s-api.${var.tailscale_domain}" : var.controlplane_ip
    server_port            = var.tailscale_domain != "" ? "443" : "6443"
    token                  = kubernetes_secret_v1.ops_token.data.token
    insecure_skip_tls_verify = var.tailscale_domain != "" ? true : false
  })
  sensitive = true
}
