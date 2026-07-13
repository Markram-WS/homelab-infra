resource "local_file" "kubeconfig" {
  depends_on      = [module.bootstrap]
  content         = module.bootstrap.kubeconfig_raw
  filename        = "${path.module}/kubeconfig"
  file_permission = "0600"
}

resource "kubernetes_manifest" "flux_git_repository" {
  depends_on = [module.bootstrap]
  manifest = {
    apiVersion = "source.toolkit.fluxcd.io/v1"
    kind       = "GitRepository"
    metadata = {
      name      = "homelab"
      namespace = "flux-system"
    }
    spec = {
      interval = var.flux_interval
      url      = var.flux_repository
      ref = {
        semver = ">=1.0.0"
      }
    }
  } 
}

resource "kubernetes_manifest" "flux_kustomization" {
  depends_on = [kubernetes_manifest.flux_git_repository]
  manifest = {
    apiVersion = "kustomize.toolkit.fluxcd.io/v1"
    kind       = "Kustomization"
    metadata = {
      name      = "homelab-apps"
      namespace = "flux-system"
    }
    spec = {
      interval = var.flux_interval
      sourceRef = {
        kind = "GitRepository"
        name = "homelab"
      }
      path    = "./clusters/base"
      prune   = true
      wait    = true
      timeout = "5m"
      postBuild = {
        substitute = {
          domain                 = var.domain
          backup_bucket          = var.backup_bucket
          backup_retention_db    = tonumber(var.backup_retention_db)
          backup_retention_vault = tonumber(var.backup_retention_vault)
        }
      }
    }
  }
}

# ======== GitHub Auth Secret (for private app repos) ========
resource "kubernetes_secret" "github_auth" {
  count      = var.github_token != "" ? 1 : 0
  depends_on = [module.bootstrap]
  metadata {
    name      = "github-auth"
    namespace = "flux-system"
  }
  type = "Opaque"
  data = {
    username = "git"
    password = var.github_token
  }
}

# ======== App Repositories (Dynamic via app_repos list) ========
resource "kubernetes_manifest" "flux_git_repository_app" {
  for_each   = { for r in var.app_repos : r.name => r }
  depends_on = [module.bootstrap]
  manifest = {
    apiVersion = "source.toolkit.fluxcd.io/v1"
    kind       = "GitRepository"
    metadata = {
      name      = each.value.name
      namespace = "flux-system"
    }
    spec = {
      interval = var.flux_interval
      url      = each.value.url
      ref      = { semver = each.value.semver }
      secretRef = var.github_token != "" ? {
        name = "github-auth"
      } : null
    }
  }
}

resource "kubernetes_manifest" "flux_kustomization_app" {
  for_each   = { for r in var.app_repos : r.name => r }
  depends_on = [kubernetes_manifest.flux_git_repository_app]
  manifest = {
    apiVersion = "kustomize.toolkit.fluxcd.io/v1"
    kind       = "Kustomization"
    metadata = {
      name      = each.value.name
      namespace = "flux-system"
    }
    spec = {
      interval = var.flux_interval
      sourceRef = {
        kind = "GitRepository"
        name = each.value.name
      }
      path  = each.value.path
      prune = true
      wait  = true
      postBuild = {
        substitute = {
          domain                 = var.domain
          backup_bucket          = var.backup_bucket
          backup_retention_db    = tonumber(var.backup_retention_db)
          backup_retention_vault = tonumber(var.backup_retention_vault)
        }
      }
    }
  }
}

# ======== RBAC สำหรับ ops-user (เครื่องอื่น monitor + deploy service) ========

locals {
  repos_with_ns = { for r in var.app_repos : r.name => r if r.namespaces != null }
}

resource "kubernetes_cluster_role_v1" "cluster_readonly" {
  metadata {
    name = "cluster-readonly"
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "pods/log", "services", "endpoints", "events", "configmaps", "namespaces", "nodes", "persistentvolumes", "persistentvolumeclaims", "replicationcontrollers", "resourcequotas"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "statefulsets", "daemonsets", "replicasets"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["batch"]
    resources  = ["cronjobs", "jobs"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses", "networkpolicies"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["storage.k8s.io"]
    resources  = ["storageclasses"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["traefik.io"]
    resources  = ["ingressroutes", "middlewares", "tlsoptions"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["tailscale.com"]
    resources  = ["proxyclasses", "connectors", "dnsconfigs"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_service_account_v1" "ops_user" {
  depends_on = [module.bootstrap]

  metadata {
    name      = "ops-user"
    namespace = "flux-system"
  }
}

resource "kubernetes_secret_v1" "ops_token" {
  metadata {
    name      = "ops-token"
    namespace = "flux-system"
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account_v1.ops_user.metadata[0].name
    }
  }
  type = "kubernetes.io/service-account-token"
}

resource "kubernetes_cluster_role_binding_v1" "cluster_readonly" {
  depends_on = [
    kubernetes_cluster_role_v1.cluster_readonly,
    kubernetes_service_account_v1.ops_user,
  ]

  metadata {
    name = "cluster-readonly"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.cluster_readonly.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.ops_user.metadata[0].name
    namespace = "flux-system"
  }
}

resource "kubernetes_role_v1" "svc_writer" {
  for_each = local.repos_with_ns

  metadata {
    name      = "svc-writer"
    namespace = each.value.namespaces
  }

  rule {
    api_groups = [""]
    resources  = ["services"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
}

resource "kubernetes_role_binding_v1" "svc_writer" {
  for_each = local.repos_with_ns

  metadata {
    name      = "svc-writer"
    namespace = each.value.namespaces
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.svc_writer[each.key].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.ops_user.metadata[0].name
    namespace = "flux-system"
  }
}

