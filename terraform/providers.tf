provider "talos" {}

provider "kubernetes" {
  host                   = module.bootstrap.kubernetes_host
  client_certificate     = base64decode(module.bootstrap.kubernetes_client_certificate)
  client_key             = base64decode(module.bootstrap.kubernetes_client_key)
  cluster_ca_certificate = base64decode(module.bootstrap.kubernetes_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = module.bootstrap.kubernetes_host
    client_certificate     = base64decode(module.bootstrap.kubernetes_client_certificate)
    client_key             = base64decode(module.bootstrap.kubernetes_client_key)
    cluster_ca_certificate = base64decode(module.bootstrap.kubernetes_ca_certificate)
  }
}
