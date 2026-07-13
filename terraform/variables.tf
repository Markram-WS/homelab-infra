variable "cluster_name" {
  description = "Name of the Talos cluster"
  type        = string
  default     = "my-cluster"
}

variable "talos_version" {
  description = "Talos version to install"
  type        = string
  default     = "v1.7.0"
}

variable "kubernetes_version" {
  description = "Kubernetes version for Talos"
  type        = string
  default     = "1.30.0"
}

variable "controlplane_ip" {
  description = "Static IP of the control plane node"
  type        = string
}

variable "controlplane_gateway" {
  description = "Gateway for the control plane node"
  type        = string
}

variable "controlplane_dns" {
  description = "DNS servers for the control plane node"
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
}

variable "controlplane_subnet" {
  description = "Subnet mask (CIDR bits) for the control plane"
  type        = string
  default     = "24"
}

variable "controlplane_interface" {
  description = "Network interface for the control plane (e.g. eth0, enp3s0)"
  type        = string
  default     = "eth0"
}

variable "install_disk" {
  description = "Disk device for Talos installation (e.g. /dev/nvme0n1, /dev/sda)"
  type        = string
  default     = "/dev/nvme0n1"
}

variable "node_ip" {
  description = "Temporary/IPMI IP of the node for initial bootstrap"
  type        = string
}

variable "tailscale_oauth_client_id" {
  description = "Tailscale OAuth client ID (for operator-oauth secret)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "tailscale_oauth_client_secret" {
  description = "Tailscale OAuth client secret (for operator-oauth secret)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "tailscale_operator_tag" {
  description = "Tag for the Tailscale operator itself"
  type        = string
  default     = "tag:k8s-operator"
}

variable "tailscale_tags" {
  description = "Tags for Tailscale proxy devices"
  type        = list(string)
  default     = ["tag:k8s"]
}

variable "domain" {
  description = "Base domain for ingress routes"
  type        = string
  default     = "local"
}

variable "tailscale_domain" {
  description = "Tailscale MagicDNS domain (e.g. {DNS}.ts.net)"
  type        = string
  default     = ""
}

variable "backup_bucket" {
  description = "MinIO bucket name for all backups"
  type        = string
  default     = "backup"
}

variable "backup_retention_db" {
  description = "Retention days for database backups"
  type        = number
  default     = 14
}

variable "backup_retention_vault" {
  description = "Retention days for vault snapshots"
  type        = number
  default     = 30
}

variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 0
}

variable "flux_repository" {
  description = "GitHub repository URL for Flux GitOps"
  type        = string
}

variable "flux_interval" {
  description = "Flux reconciliation interval (GitRepository + Kustomization)"
  type        = string
  default     = "15m"
}

variable "vault_postgres_password" {
  description = "PostgreSQL superuser password (stored in Vault)"
  type        = string
  sensitive   = true
}

variable "vault_pguser_password" {
  description = "PostgreSQL app user password (stored in Vault)"
  type        = string
  sensitive   = true
}

variable "vault_minio_root_user" {
  description = "MinIO root user (stored in Vault)"
  type        = string
  sensitive   = true
}

variable "vault_minio_root_password" {
  description = "MinIO root password (stored in Vault)"
  type        = string
  sensitive   = true
}

variable "github_token" {
  description = "GitHub Personal Access Token for cloning private app repos"
  type        = string
  default     = ""
  sensitive   = true
}

variable "app_repos" {
  description = "List of app repositories for Flux GitOps (uses semver tags)"
  type = list(object({
    name       = string
    url        = string
    semver     = string
    path       = string
    namespaces = optional(string)
  }))
  default = []
}
