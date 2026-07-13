locals {
  talos_ns_system = [
    "kube-system",
    "flux-system",
    "platform",
    "vault",
    "external-secrets",
    "minio",
    "database",
    "flux-ui",
    "local-path-storage",
  ]
  talos_ns_app = distinct(compact([
    for r in var.app_repos : try(r.namespaces, null)
  ]))
}

module "bootstrap" {
  source = "./modules/bootstrap"

  cluster_name           = var.cluster_name
  allowed_kubernetes_namespaces = concat(local.talos_ns_system, local.talos_ns_app)
  controlplane_ip        = var.controlplane_ip
  controlplane_gateway   = var.controlplane_gateway
  controlplane_dns       = var.controlplane_dns
  controlplane_subnet    = var.controlplane_subnet
  controlplane_interface = var.controlplane_interface
  install_disk           = var.install_disk
  node_ip                = var.node_ip
  worker_count           = var.worker_count
  talos_version          = var.talos_version
  kubernetes_version     = var.kubernetes_version

  tailscale_oauth_client_id     = var.tailscale_oauth_client_id
  tailscale_oauth_client_secret = var.tailscale_oauth_client_secret
  tailscale_operator_tag        = var.tailscale_operator_tag
  tailscale_tags                = var.tailscale_tags

  vault_postgres_password   = var.vault_postgres_password
  vault_pguser_password     = var.vault_pguser_password
  vault_minio_root_user     = var.vault_minio_root_user
  vault_minio_root_password = var.vault_minio_root_password

  tailscale_domain = var.tailscale_domain
}
