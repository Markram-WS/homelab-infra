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

variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 0
}

variable "allowed_kubernetes_namespaces" {
  description = "Namespaces allowed to access Talos API (kubernetesTalosAPIAccess) for reading logs and managing services"
  type        = list(string)
  default = [
    "kube-system",
    "flux-system",
    "platform",
    "vault",
    "external-secrets",
    "minio",
    "database",
    "local-path-storage",
  ]
}

variable "tailscale_domain" {
  description = "Tailscale MagicDNS domain"
  type        = string
  default     = ""
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

