resource "talos_machine_secrets" "this" {}

data "talos_machine_configuration" "controlplane" {
  cluster_name     = var.cluster_name
  cluster_endpoint = "https://${var.controlplane_ip}:6443"
  machine_type     = "controlplane"
  machine_secrets  = resource.talos_machine_secrets.this.machine_secrets
  config_patches = [
    templatefile("${path.module}/../../../talos-patches/network.yaml.tftpl", {
      ip          = var.controlplane_ip
      subnet      = var.controlplane_subnet
      gateway     = var.controlplane_gateway
      dns_servers = join(",", var.controlplane_dns)
      interface   = var.controlplane_interface
    }),
    templatefile("${path.module}/../../../talos-patches/install.yaml.tftpl", {
      disk = var.install_disk
    }),
    templatefile("${path.module}/../../../talos-patches/cni.yaml.tftpl", {}),
    templatefile("${path.module}/../../../talos-patches/remove-taint.yaml.tftpl", {}),
    templatefile("${path.module}/../../../talos-patches/kubernetes-talos-api-access.yaml.tftpl", {
      namespaces = var.allowed_kubernetes_namespaces
    }),
  ]
}

data "talos_machine_configuration" "worker" {
  count            = var.worker_count
  cluster_name     = var.cluster_name
  cluster_endpoint = "https://${var.controlplane_ip}:6443"
  machine_type     = "worker"
  machine_secrets  = resource.talos_machine_secrets.this.machine_secrets
  config_patches = [
    templatefile("${path.module}/../../../talos-patches/install.yaml.tftpl", {
      disk = var.install_disk
    }),
  ]
}

resource "talos_machine_configuration_apply" "controlplane" {
  node                        = var.node_ip
  endpoint                    = var.node_ip
  apply_mode                  = "auto"
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  client_configuration        = resource.talos_machine_secrets.this.client_configuration
}

resource "talos_machine_bootstrap" "controlplane" {
  depends_on           = [talos_machine_configuration_apply.controlplane]
  node                 = var.controlplane_ip
  client_configuration = resource.talos_machine_secrets.this.client_configuration
}

resource "talos_cluster_kubeconfig" "this" {
  depends_on           = [talos_machine_configuration_apply.controlplane]
  node                 = var.controlplane_ip
  client_configuration = resource.talos_machine_secrets.this.client_configuration
}

resource "local_file" "kubeconfig" {
  content  = talos_cluster_kubeconfig.this.kubeconfig_raw
  filename = "${path.module}/.kubeconfig"
}

resource "local_file" "talos_config" {
  content = templatefile("${path.module}/../../../talos-patches/talosconfig.tftpl", {
    cluster_name = var.cluster_name
    endpoint     = var.controlplane_ip
    ca_b64       = talos_machine_secrets.this.client_configuration.ca_certificate
    crt_b64      = talos_machine_secrets.this.client_configuration.client_certificate
    key_b64      = talos_machine_secrets.this.client_configuration.client_key
  })
  filename = "${path.module}/.talosconfig"
}

resource "kubernetes_namespace" "platform" {
  depends_on = [talos_cluster_kubeconfig.this]
  metadata {
    name = "platform"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
    }
  }
}

# K8s API — expose ผ่าน Tailscale สำหรับ k9s จากเครื่องอื่น
resource "kubernetes_service_v1" "k8s_api" {
  depends_on = [kubernetes_namespace.platform]
  metadata {
    name      = "k8s-api"
    namespace = "platform"
    annotations = {
      "tailscale.com/expose"   = "true"
      "tailscale.com/hostname" = "k8s-api"
    }
  }
  spec {
    port {
      port        = 443
      target_port = 6443
    }
  }
}

resource "kubernetes_endpoints_v1" "k8s_api" {
  depends_on = [kubernetes_service_v1.k8s_api]
  metadata {
    name      = "k8s-api"
    namespace = "platform"
  }
  subset {
    address {
      ip = var.controlplane_ip
    }
    port {
      port = 6443
    }
  }
}

resource "kubernetes_secret" "operator_oauth" {
  depends_on = [kubernetes_namespace.platform]
  metadata {
    name      = "operator-oauth"
    namespace = "platform"
  }
  data = {
    client_id     = var.tailscale_oauth_client_id
    client_secret = var.tailscale_oauth_client_secret
  }
  type = "Opaque"
}

resource "helm_release" "tailscale_operator" {
  depends_on = [kubernetes_namespace.platform, kubernetes_secret.operator_oauth]
  name       = "tailscale-operator"
  repository = "https://pkgs.tailscale.com/helmcharts"
  chart      = "tailscale-operator"
  namespace  = "platform"
  version    = "1.70.0"

  values = [templatefile("${path.module}/helm-values/tailscale-operator.yaml.tftpl", {
    operator_tag = var.tailscale_operator_tag
    proxy_tags   = join(",", var.tailscale_tags)
  })]
}

resource "helm_release" "traefik" {
  depends_on = [kubernetes_namespace.platform]
  name       = "traefik"
  repository = "https://traefik.github.io/charts"
  chart      = "traefik"
  namespace  = "platform"
  version    = "27.0.0"

  values = [templatefile("${path.module}/helm-values/traefik.yaml.tftpl", {
    tailscale_domain = var.tailscale_domain
  })]
}

resource "helm_release" "fluxcd" {
  depends_on       = [kubernetes_namespace.platform]
  name             = "flux"
  repository       = "https://fluxcd-community.github.io/helm-charts"
  chart            = "flux2"
  namespace        = "flux-system"
  version          = "2.18.4"
  create_namespace = true

  set {
    name  = "watchAllNamespaces"
    value = "true"
  }

  set {
    name  = "extraEnvs[0].name"
    value = "TZ"
  }
  set {
    name  = "extraEnvs[0].value"
    value = "Asia/Bangkok"
  }
}

resource "terraform_data" "flux_crds" {
  depends_on = [helm_release.fluxcd, local_file.kubeconfig]

  provisioner "local-exec" {
    command = "kubectl --kubeconfig=.kubeconfig apply --server-side --force-conflicts -f https://github.com/fluxcd/flux2/releases/download/v2.8.8/install.yaml && kubectl --kubeconfig=.kubeconfig wait --for=condition=established --timeout=120s crd/gitrepositories.source.toolkit.fluxcd.io crd/kustomizations.kustomize.toolkit.fluxcd.io crd/buckets.source.toolkit.fluxcd.io crd/ocirepositories.source.toolkit.fluxcd.io"
  }
}

resource "helm_release" "vault" {
  depends_on       = [kubernetes_namespace.platform]
  name             = "vault"
  repository       = "https://helm.releases.hashicorp.com"
  chart            = "vault"
  namespace        = "vault"
  version          = "0.28.1"
  create_namespace = true
  values           = [file("${path.module}/helm-values/vault.yaml")]
}

resource "helm_release" "external_secrets" {
  depends_on       = [kubernetes_namespace.platform]
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  version          = "0.14.0"
  create_namespace = true
  values           = [file("${path.module}/helm-values/external-secrets.yaml")]
}

# ติดตั้ง local-path-provisioner (StorageClass) + label namespace ให้ผ่าน PodSecurity
resource "terraform_data" "storage_provisioner" {
  provisioner "local-exec" {
    command = <<-EOT
      kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.28/deploy/local-path-storage.yaml
      kubectl label ns local-path-storage pod-security.kubernetes.io/enforce=privileged --overwrite 2>/dev/null || true
      kubectl label ns local-path-storage pod-security.kubernetes.io/warn=privileged --overwrite 2>/dev/null || true
    EOT
  }
}

resource "terraform_data" "vault_init" {
  depends_on = [helm_release.vault, helm_release.external_secrets]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      echo "Waiting for Vault pod..."
      kubectl wait --for=condition=ready pod -n vault -l app.kubernetes.io/name=vault --timeout=120s 2>/dev/null || true
      sleep 5

      VAULT_POD=$(kubectl get pods -n vault -l app.kubernetes.io/name=vault -o jsonpath='{.items[0].metadata.name}')

      INIT_STATUS=$(kubectl exec "$VAULT_POD" -n vault -- vault status -format=json 2>/dev/null | jq -r '.initialized')
      if [ "$INIT_STATUS" = "true" ]; then
        echo "Vault already initialized. Skipping init."
        ROOT_TOKEN=$(kubectl get secret vault-keys -n vault -o jsonpath='{.data.root_token}' | base64 -d)
        if [ -z "$ROOT_TOKEN" ]; then
          echo "ERROR: vault-keys secret not found. Cannot recover root token."
          exit 1
        fi
      else
        echo "Initializing Vault (Raft mode)..."
        INIT_OUTPUT=$(kubectl exec "$VAULT_POD" -n vault -- vault operator init -key-shares=1 -key-threshold=1 -format=json)

        UNSEAL_KEY=$(echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[0]')
        ROOT_TOKEN=$(echo "$INIT_OUTPUT" | jq -r '.root_token')

        echo "Unsealing Vault..."
        kubectl exec "$VAULT_POD" -n vault -- vault operator unseal "$UNSEAL_KEY"

        echo "Storing unseal key and root token..."
        kubectl create secret generic vault-keys \
          -n vault \
          --from-literal=unseal_key="$UNSEAL_KEY" \
          --from-literal=root_token="$ROOT_TOKEN" \
          --dry-run=client -o yaml | kubectl apply -f -
      fi

      echo "Logging into Vault..."
      kubectl exec "$VAULT_POD" -n vault -- vault login "$ROOT_TOKEN" > /dev/null

      echo "Enabling KV v2 secrets engine at secret/..."
      kubectl exec "$VAULT_POD" -n vault -- vault secrets enable -path=secret kv-v2 2>/dev/null || echo "Already enabled"

      echo "Writing PostgreSQL secrets..."
      kubectl exec "$VAULT_POD" -n vault -- \
        vault kv put secret/database/postgresql \
          postgres-password="${var.vault_postgres_password}" \
          pguser=homelab \
          pguser-password="${var.vault_pguser_password}"

      echo "Writing MinIO secrets..."
      kubectl exec "$VAULT_POD" -n vault -- \
        vault kv put secret/minio \
          root-user="${var.vault_minio_root_user}" \
          root-password="${var.vault_minio_root_password}"

      echo "Storing Vault token for External Secrets..."
      kubectl create secret generic vault-token \
        -n external-secrets \
        --from-literal=token="$ROOT_TOKEN" \
        --dry-run=client -o yaml | kubectl apply -f -

      for ns in minio database; do
        kubectl create secret generic vault-token \
          -n "$ns" \
          --from-literal=token="$ROOT_TOKEN" \
          --dry-run=client -o yaml | kubectl apply -f -
      done

      echo "Vault initialized successfully!"
    EOT
  }
}
