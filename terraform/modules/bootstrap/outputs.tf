output "kubeconfig_raw" {
  value = talos_cluster_kubeconfig.this.kubeconfig_raw
}

output "talos_config" {
  value = local_file.talos_config.filename
}

output "kubernetes_host" {
  value = talos_cluster_kubeconfig.this.kubernetes_client_configuration.host
}

output "kubernetes_client_certificate" {
  value = talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_certificate
}

output "kubernetes_client_key" {
  value = talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_key
}

output "kubernetes_ca_certificate" {
  value = talos_cluster_kubeconfig.this.kubernetes_client_configuration.ca_certificate
}

output "controlplane_ip" {
  value = var.controlplane_ip
}

output "ca_certificate_b64" {
  value = talos_cluster_kubeconfig.this.kubernetes_client_configuration.ca_certificate
}
