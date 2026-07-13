# Talos Home Lab — Enterprise Architecture ย่อส่วน

> 

โครงสร้างนี้เป็นการย่อส่วน **Enterprise Architecture** ลงมาอยู่ใน Home Lab เครื่องเดียวแบบประหยัด RAM (ไม่เกิน 4GB ก็เอาอยู่ด้วย Talos + Flux CD)

> 📘 **อยากสร้าง App ใหม่?** ดู [`CREATE_APP.md`](./CREATE_APP.md) — คู่มือสร้าง app + เชื่อม Vault แบบ step-by-step

## 📍 สรุป Endpoints ทั้งหมด

### ภายนอก (Tailscale MagicDNS)

| Service | URL | Tailscale IP |
|---------|-----|-------------|
| **MinIO Console** | `http://minio.{DNS}:9001` | `100.87.249.108` |
| **MinIO API** | `http://minio.{DNS}:9000` | `100.87.249.108` |
| **Vault UI** | `http://vault.{DNS}:8200` | `100.96.164.10` |
| **Traefik** | `http://traefik.{DNS}` | `100.121.159.17` |
| **PostgreSQL** | `postgresql.{DNS}:5432` | `100.97.0.118` |
| **Gyre (Flux UI)** | `http://flux-ui.{DNS}:9001` | — |

### Ingress (Traefik — ภายใน cluster)

| Host | Path | Backend Service | Port |
|------|------|----------------|------|
| `console.minio.${domain}` | `/` | MinIO Console | 9001 |
| `minio.${domain}` | `/` | MinIO API | 9000 |
| `vault.${domain}` | `/` | Vault UI | 8200 |
| `traefik.local` | `/` | Traefik Dashboard | (internal) |

### Internal Kubernetes Services

| Service | Namespace | Port |
|---------|-----------|------|
| `minio.minio.svc.cluster.local` | minio | 9000 (API), 9001 (Console) |
| `postgresql.database.svc.cluster.local` | database | 5432 |
| `vault.vault.svc.cluster.local` | vault | 8200 |
| `traefik.platform.svc.cluster.local` | platform | 80, 443 |
| `gyre.flux-ui.svc.cluster.local` | flux-ui | 9001 |
| `k8s-api.{DNS}` | (Tailscale proxy) | 443 |

### Kubernetes API

| Endpoint | Port | Access |
|----------|------|--------|
| `https://192.168.1.XXX:6443` | 6443 | Internal network |
| `https://k8s-api.{DNS}:443` | 443 | Tailscale MagicDNS |

---

## สารบัญ

- [ภาพรวมกระบวนการ](#-ภาพรวมกระบวนการ-high-level-process)
- [โครงสร้างโปรเจกต์](#-โครงสร้างโปรเจกต์)
- [Phase 1: เตรียมร่าง (ISO Creation & Flashdrive)](#-phase-1-เตรียมร่าง-iso-creation--flashdrive)
- [Phase 2: เบิร์นวิญญาณ (Talos Installation)](#-phase-2-เบิร์นวิญญาณ-talos-installation)
- [Phase 3: คุมบังเหียนด้วย Terraform (Infrastructure as Code)](#-phase-3-คุมบังเหียนด้วย-terraform-infrastructure-as-code)
- [🧠 Logic การ Deploy: Helm vs Flux Kustomization](#-logic-การ-deploy-helm-vs-flux-kustomization)
- [Phase 4: ปล่อย Flux CD ลุยระบบ (GitOps Deployment)](#-phase-4-ปล่อย-flux-cd-ลุยระบบ-gitops-deployment)
- [📋 Custom Resource Definitions (CRDs)](#-custom-resource-definitions-crds)
- [การใช้งานประจำวัน](#-การใช้งานประจำวัน)
- [การกู้คืนระบบ](#-การกู้คืนระบบ)

---

## 🗺️ ภาพรวมกระบวนการ (High-Level Process)

```
[ Phase 1: เตรียมร่าง ] ──> [ Phase 2: เบิร์นวิญญาณ ] ──> [ Phase 3: คุมบังเหียนด้วย TF ] ──> [ Phase 4: ปล่อย Flux CD ลุย ]
(สร้างตัวติดตั้ง ISO)        (บูตเครื่องลงดิสก์จริง)         (เสก Kubernetes / Network)      (ลง App & DB แบบ GitOps)
```

---

## 📁 โครงสร้างโปรเจกต์

```
talos/
├── README.md                         # เอกสารนี้
├── .gitignore
├── terraform/
│   ├── versions.tf                   # กำหนด provider + version
│   ├── providers.tf                  # เรียกใช้ Talos, Helm, Kubernetes provider (จาก module.bootstrap)
│   ├── variables.tf                  # ตัวแปรทั้งหมด
│   ├── bootstrap.tf                  # module.bootstrap { source = "./modules/bootstrap" }
│   ├── main.tf                       # kubernetes_manifest (GitRepository + Kustomization)
│   ├── outputs.tf                    # kubeconfig, IP endpoint
│   ├── terraform.tfvars.example      # ตัวอย่างค่าตัวแปร
│   ├── modules/
│   │   └── bootstrap/
│   │       ├── main.tf               # Talos bootstrapping + Helm charts ทั้งหมด
│   │       ├── variables.tf          # ตัวแปรสำหรับ bootstrap
│   │       ├── outputs.tf            # kubeconfig_raw + kubernetes config
│   │       ├── versions.tf           # required_providers
│   │       └── helm-values/          # Helm values สำหรับ bootstrap charts
│   ├── helm-values/                  # Helm values (ต้นทาง, module copy ไปใช้)
│       ├── tailscale-operator.yaml.tftpl
│       ├── traefik.yaml.tftpl
│       ├── vault.yaml
│       └── external-secrets.yaml
├── talos-patches/
│   ├── network.yaml.tftpl            # Patch กำหนด static IP
│   ├── install.yaml.tftpl            # Patch ระบุดิสก์ติดตั้ง
│   ├── hostname.yaml                 # Patch ตั้งชื่อโฮสต์
├── clusters/
│   └── base/
│       └── kustomization.yaml        # Flux Kustomization root
└── apps/
    ├── minio/
    │   ├── kustomization.yaml
    │   ├── namespace.yaml
    │   ├── pvc.yaml
    │   ├── deployment.yaml
    │   ├── service.yaml
    │   └── ingress.yaml
    ├── postgresql/
    │   ├── kustomization.yaml
    │   ├── namespace.yaml
    │   ├── pvc.yaml
    │   ├── statefulset.yaml
    │   └── service.yaml
    ├── cronjob-backup/
    │   ├── kustomization.yaml
    │   ├── configmap.yaml
    │   └── cronjob.yaml
    ├── gyre/
    │   ├── kustomization.yaml
    │   ├── namespace.yaml
    │   ├── helmrepository.yaml
    │   ├── helmrelease.yaml
    │   ├── service.yaml
    │   └── external-secret.yaml
    └── vault/
        ├── kustomization.yaml
        ├── cluster-secret-store.yaml
        ├── external-secret-db.yaml
        ├── external-secret-minio.yaml
        ├── ingress.yaml
        ├── cronjob-backup.yaml
        └── rbac-backup.yaml
```

---

## 📦 Phase 1 & 2: Initial Setup (One-Time — Already Done)

> ขั้นตอนนี้ทำครั้งเดียวตอนติดตั้ง Talos ครั้งแรก ถ้าเครื่องทำงานแล้วไม่ต้องทำซ้ำ

**โดยสรุป:** ดาวน์โหลด Talos ISO → เขียนลง flashdrive (GPT/UEFI/FAT32) → บูตเครื่อง → Maintenance Mode
→ `talosctl gen config` + apply config → reboot → cluster พร้อม

ดูรายละเอียดเต็มได้ที่ [Talos Docs — Bare Metal Platform](https://www.talos.dev/v1.7/talos-guides/install/bare-metal-platforms/)

Talos config patches สำหรับโปรเจกต์นี้อยู่ใน `talos-patches/`:
| File | มีไว้ทำอะไร |
|------|-------------|
| `network.yaml.tftpl` | ตั้ง Static IP, gateway, DNS |
| `install.yaml.tftpl` | ระบุ install disk + `wipe: true` |
| `cni.yaml.tftpl` | เปิด Flannel CNI |
| `remove-taint.yaml.tftpl` | ลบ control-plane taint สำหรับ single-node |

---

## 🏗️ Phase 3: คุมบังเหียนด้วย Terraform (Infrastructure as Code)

**เป้าหมาย:** ใช้ Terraform สั่งเปิดประตู Cluster และปูพรมระบบ Network

### 3.1 ติดตั้ง Terraform (Windows 11)

```powershell
# ใช้ winget
winget install HashiCorp.Terraform

# หรือใช้ Chocolatey
choco install terraform
```

### 3.2 เตรียม terraform.tfvars

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

แก้ไขค่าตาม environment ของตัวเอง:

```hcl
cluster_name           = "my-cluster"
controlplane_ip        = "192.168.1.100"
controlplane_gateway   = "192.168.1.1"
controlplane_dns       = ["1.1.1.1", "8.8.8.8"]
controlplane_subnet    = "24"
controlplane_interface = "eno1"             # เช็คชื่อ interface จริง
install_disk           = "/dev/sdb"         # เช็คชื่อ disk จาก talosctl get disks
node_ip                = "<IP_maintenance>" # IP ขณะ maintenance mode

# Tailscale OAuth Client (สร้างที่ https://login.tailscale.com/admin/settings/oauth)
tailscale_oauth_client_id     = "<client-id>"
tailscale_oauth_client_secret = "<client-secret>"
tailscale_operator_tag        = "tag:k8s-operator"
tailscale_tags                = ["tag:k8s", "tag:talos"]

# Vault secrets (จะถูก inject ลง Vault โดย terraform_data.vault_init)
vault_postgres_password = "admin"           # postgres superuser
vault_pguser_password   = "<pguser-pass>"   # postgres app user
vault_minio_root_user   = "admin"           # MinIO root user
vault_minio_root_password = "<minio-pass>"  # MinIO root password

flux_repository      = "https://github.com/YOUR_USER/homelab"
domain               = "local"
```

### 3.3 วงจร CRD — ทำไมต้อง 2 รอบ Apply

Flux CD Helm chart (`flux2`) จะ install CRDs เฉพาะตอน `helm install` ครั้งแรกเท่านั้น (ผ่าน `crds/` directory)
Terraform resource `kubernetes_manifest` ต้องการ CRD `GitRepository` / `Kustomization` ใน cluster ก่อน
จึงจะสร้าง resource ของประเภทนั้นได้ → **chicken-and-egg cycle**

**วิธีแก้:** แยกเป็น 2 module — bootstrap (`module.bootstrap`) vs flux manifest (root) + ใช้ `-target` รอบแรก

### 3.4 ลำดับการติดตั้ง (2 รอบ Apply)

```
┌─────────────────────────────────────────────────────────┐
│ รอบ 1: Bootstrap (-target=module.bootstrap)              │
│  terraform apply -target=module.bootstrap                │
│  → Talos bootstrap → Helm charts → CRDs installed        │
│  → kubeconfig + talosconfig                              │
├─────────────────────────────────────────────────────────┤
│ รอบ 2: Flux Resources                                    │
│  terraform apply                                         │
│  → CRDs มีแล้ว → GitRepository + Kustomization สร้างได้  │
│  → Flux sync → push repo → GitOps                        │
└─────────────────────────────────────────────────────────┘
```

### 3.5 ทีละขั้นตอน

#### รอบ 1: Bootstrap + Infrastructure

```bash
cd terraform
terraform init

# Deploy bootstrap module (Talos + Helm + CRDs ทั้งหมด)
terraform apply -target=module.bootstrap
```

> รอ ~3-8 นาที — Talos bootstrap → Helm charts (Tailscale, Traefik, Flux, Vault, External Secrets)
> และ `terraform_data.flux_crds` จะ download + install Flux CRDs อัตโนมัติ
>
> **ถ้า `terraform_data.flux_crds` ล้ม** → manual fallback:
> ```bash
> terraform output kubeconfig_raw > .kubeconfig
> kubectl --kubeconfig=.kubeconfig apply --server-side --force-conflicts -f https://github.com/fluxcd/flux2/releases/latest/download/install.yaml
> kubectl --kubeconfig=.kubeconfig wait --for=condition=established --timeout=120s crd/gitrepositories.source.toolkit.fluxcd.io crd/kustomizations.kustomize.toolkit.fluxcd.io
> ```

#### รอบ 2: Flux Resources (GitRepository + Kustomization)

```bash
# CRDs พร้อมแล้ว → apply ทั้ง root module
terraform apply
```

> จะสร้าง `kubernetes_manifest.flux_git_repository` + `kubernetes_manifest.flux_kustomization`
> CRD มีใน cluster แล้ว → plan pass ไม่ error

#### Push → GitOps

```bash
git add .
git commit -m "feat: init home lab"
git remote add origin https://github.com/YOUR_USER/homelab.git
git push -u origin main
```

### 3.6 คำอธิบายแต่ละ Resource / Data Source

#### Talos (bootstrap cluster)

| Resource / Data Source | Provider | อยู่ module | มีไว้ทำอะไร |
|------------------------|----------|------------|-------------|
| `talos_machine_secrets.this` | Talos | bootstrap | สร้าง TLS certificate pair สำหรับ Talos cluster |
| `data.talos_machine_configuration.controlplane` | Talos | bootstrap | gen Talos machine config + ต่อ patch |
| `talos_machine_configuration_apply.controlplane` | Talos | bootstrap | ส่ง config → install Talos ลง disk |
| `talos_machine_bootstrap.controlplane` | Talos | bootstrap | bootstrap Kubernetes — เริ่ม etcd |
| `talos_cluster_kubeconfig.this` | Talos | bootstrap | ดึง kubeconfig — ใช้โดย kubernetes + helm provider |

#### Kubernetes (base infra)

| Resource / Data Source | Provider | มีไว้ทำอะไร |
|------------------------|----------|-------------|
| `kubernetes_namespace.platform` | Kubernetes | สร้าง namespace `platform` สำหรับ base services |

#### Helm Charts (base services) — ใน `module.bootstrap`

| Resource | Chart | มีไว้ทำอะไร |
|----------|-------|-------------|
| `helm_release.tailscale_operator` | tailscale-operator | VPN tunnel — expose service ผ่าน Tailscale (ใช้ `operatorConfig.defaultTags` + `proxyConfig.defaultTags` แยกกัน) |
| `helm_release.traefik` | traefik | Ingress controller — รับ traffic HTTP/HTTPS |
| `helm_release.fluxcd` | flux2 | GitOps operator — sync manifest จาก git → cluster |
| `helm_release.vault` | vault (Raft mode, PVC 128Mi) | Secret store — เก็บ secrets (DB, MinIO) |
| `helm_release.external_secrets` | external-secrets | Sync secrets จาก Vault → K8s Secret |

> ⚠️ **Tailscale operator tags:** ใช้ `operatorConfig.defaultTags` (=`tag:k8s-operator`) แยกกับ `proxyConfig.defaultTags` (=`tag:k8s,tag:talos`)  
> ⚠️ **PodSecurity:** Talos เปิด `baseline` default — ต้อง label namespace `platform` ด้วย `pod-security.kubernetes.io/enforce=privileged`  
> ไม่งั้น proxy pods จะไม่ถูกสร้างเพราะต้องใช้ `NET_ADMIN` + `privileged` ดูเพิ่มที่ Troubleshooting #18
> อ่านเพิ่มเรื่อง tag flow และ ACL setup ได้ที่ [Tailscale OAuth Tag Troubleshooting](#)

#### Terraform Data (local-exec) — ใน `module.bootstrap`

| Resource | Provider | มีไว้ทำอะไร |
|----------|----------|-------------|
| `terraform_data.flux_crds` | Terraform | install Flux CRDs ผ่าน kubectl + wait established |
| `terraform_data.vault_init` | Terraform | init Vault (Raft) + unseal (ครั้งแรก) + inject secrets |

#### Kubernetes Manifest (root `main.tf`)

| Resource | API Version | ขึ้นกับ | มีไว้ทำอะไร |
|----------|-------------|--------|-------------|
| `kubernetes_manifest.flux_git_repository` | `source.toolkit.fluxcd.io/v1` | `module.bootstrap` | บอก Flux ว่าต้อง watch git repo ไหน |
| `kubernetes_manifest.flux_kustomization` | `kustomize.toolkit.fluxcd.io/v1` | flux_git_repository | บอก Flux ว่าต้อง sync path `./clusters/base` |

### 3.7 Config Patches (talos-patches/)

| File | มีไว้ทำอะไร |
|------|-------------|
| `network.yaml.tftpl` | ตั้ง Static IP, gateway, DNS, interface (eno1) |
| `install.yaml.tftpl` | ระบุ install disk (`/dev/sdb`) + `wipe: true` + installer image version |
| `cni.yaml.tftpl` | เปิด Flannel CNI (จำเป็น — Talos ไม่มี CNI มาให้) |
| `kubernetes-talos-api-access.yaml.tftpl` | เปิด Talos API access สำหรับ pods ใน namespaces ที่กำหนด (os:reader + os:operator) |

### 3.8 Dependency Chain (Module View)

```
┌─ module.bootstrap ──────────────────────────────────────┐
│ talos_machine_secrets                                    │
│   └─► data.talos_machine_configuration                   │
│         └─► talos_machine_configuration_apply             │
│               ├─► talos_machine_bootstrap                 │
│               └─► talos_cluster_kubeconfig                │
│                     └─► kubernetes_namespace.platform     │
│                           ├─► helm_release.tailscale_...  │
│                           ├─► helm_release.traefik        │
│                           ├─► helm_release.fluxcd         │
│                           │     └─► terraform_data.flux_crds
│                           ├─► helm_release.vault          │
│                           ├─► helm_release.external_secrets
│                           └─► terraform_data.vault_init   │  ← init + unseal ครั้งแรก
└──────────────────────────────────────────────────────────┘
                          │
              ┌─────────────────────────────┐
              │ CronJob vault-auto-unseal   │  ← auto-unseal หลัง reboot (ทุก 15m)
              │ (GitOps via apps/)          │
              └─────────────────────────────┘
                          │
              รอบ 2 apply (CRDs พร้อมแล้ว)
                          │
┌─ root (main.tf) ───────┴────────────────────────────────┐
│ kubernetes_manifest.flux_git_repository                   │
│   └─► kubernetes_manifest.flux_kustomization              │
└──────────────────────────────────────────────────────────┘
```

### 3.9 Talos API Access from Kubernetes Pods

เปิดให้ pods ใน namespaces ที่กำหนดเข้าถึง Talos API ผ่าน service account token:
- `os:reader` — อ่าน logs (`talosctl logs`), dmesg (`talosctl dmesg`)
- `os:operator` — manage services, reboot (จำกัดเฉพาะ namespace ที่ต้องการ)

Namespaces ที่อนุญาตถูกกำหนดโดย `allowed_kubernetes_namespaces` ใน bootstrap module:
- System namespaces: `kube-system`, `flux-system`, `platform`, `vault`, `external-secrets`, `minio`, `database`, `local-path-storage`
- App namespaces: ดึงจาก `var.app_repos[*].namespaces` โดยอัตโนมัติ

Patch ถูก apply ผ่่าน `kubernetes-talos-api-access.yaml.tftpl` — ถ้าต้องการเพิ่ม namespace, แก้ `terraform/tfvars` ใน field `app_repos[].namespaces` หรือเพิ่มใน `locals.talos_ns_system` ที่ `terraform/bootstrap.tf`

---

## 🧠 Logic การ Deploy: Helm vs Flux Kustomization

ในโปรเจกต์นี้มี 2 วิธีในการ deploy ลง Kubernetes โดยเลือกใช้ตามลักษณะของ service:

### วิธีที่ 1: Helm (ผ่าน Terraform `helm_release`)

ใช้กับ **base infrastructure** ที่ต้องควบคุม lifecycle และลำดับการติดตั้ง:
- Tailscale Operator — ต้องมาก่อนเพื่อเปิด tunnel เข้า cluster
- Traefik — ต้องมาก่อนเพื่อรอรับ ingress traffic
- Flux CD — ต้องมาก่อนเพื่อเริ่ม GitOps pipeline

ข้อดี: Terraform ควบคุมลำดับ dependency (`depends_on`) และ cleanup (`terraform destroy`) ได้แน่นอน
ข้อเสีย: ถ้าอยากแก้ config service ต้องรัน `terraform apply` ทุกครั้ง — ไม่เหมาะกับ app ที่อัปเดตบ่อย

### วิธีที่ 2: Flux Kustomization (GitOps)

ใช้กับ **business applications** ที่อัปเดต config บ่อย:
- MinIO — S3 storage (แก้ bucket policy, access key ผ่าน git)
- PostgreSQL — primary database (แก้ schema, env ผ่าน git)
- CronJob backup — backup script (แก้ schedule, logic ผ่าน git)

ข้อดี: push code → Flux detect → auto sync — ไม่ต้องรัน terraform อีก
ข้อเสีย: ต้องมี Git repo และ Flux ทำงานอยู่ก่อน

### สรุป Decision Tree

```
Service นี้คืออะไร?
│
├── Base infrastructure (Tailscale, Traefik, Flux)
│   └── → ใช้ Helm (Terraform)
│
├── Business app ที่อัปเดตบ่อย (MinIO, PostgreSQL, CronJob)
│   └── → ใช้ Flux Kustomization (GitOps)
│
└── ต้อง deploy ก่อน service อื่นถึงจะ work?
    └── → ใช้ Helm จับ order dependency
```

### Dependency Chain

```
[ Terraform Helm ]
    │
    ├── Tailscale Operator ──► เปิด VPN tunnel
    ├── Traefik           ──► ingress gateway
    └── Flux CD           ──► start GitOps
                              │
                         [ Flux Kustomization ]
                              │
                              ├── MinIO
                              ├── PostgreSQL
                              └── CronJob backup
```

---

## 🚀 Phase 4: ปล่อย Flux CD ลุยระบบ (GitOps Deployment)

**เป้าหมาย:** ใช้ Terraform ส่งไม้ต่อให้ Flux CD ดึงข้อมูลแอปทั้งหมดลงเครื่องแบบอัตโนมัติ

### 4.1 โครงสร้าง GitOps

```
[ GitHub Repository ]
         │
         ├── clusters/base/           ← Kustomization root (Flux เริ่มต้นที่นี้)
         │     └── kustomization.yaml  ← รวม apps/ ทั้งหมด
         │
         ├── apps/
         │     ├── minio/             ← MinIO S3 Standalone
          │     ├── postgresql/        ← PostgreSQL Primary DB
          │     ├── cronjob-backup/    ← pg_dump ตี 2 -> MinIO
            │     └── gyre/             ← Gyre Flux UI
         │
         └── talos-patches/           ← Talos config patches (อ้างอิงโดย TF)
```

### 4.2 Flux CD จะทำอะไรบ้าง?

1. **อ่านไฟล์ Manifest ใน Git** ที่ `clusters/base/kustomization.yaml`
2. **สถาปนา MinIO S3** — คลังเก็บไฟล์ (เข้าถึงผ่าน Tailscale MagicDNS)
3. **ลง PostgreSQL** — ฐานข้อมูลหลัก ใน namespace `database`
4. **ตั้งค่า CronJob** — ตอน 02:00 น. วิ่ง pg_dump -> MinIO
5. **ติดตั้ง Gyre** — UI สำหรับดูสถานะ cluster และ Flux pipeline

### 4.3 Push ไป GitHub

```bash
git init
git add .
git commit -m "feat: init home lab Talos cluster with Flux GitOps"
git remote add origin https://github.com/YOUR_USER/homelab.git
git push -u origin main
```

### 4.4 เช็คสถานะ Flux

```bash
# ติดตั้ง flux CLI
curl -s https://fluxcd.io/install.sh | bash

# เช็ค Flux status
flux check

# ดู Kustomization
flux get kustomizations

# ดู status ของ GitRepository
flux get sources git
```

### 4.5 Deploy App จาก Repo อื่น (Multi-Repo GitOps)

ใช้ `app_repos` list ใน tfvars — เพิ่ม repo ไหนก็แค่เพิ่ม object ใน list ไม่ต้องแก้ `main.tf`

#### 4.5.1 ตัวแปรใน `terraform/variables.tf`

```hcl
variable "app_repos" {
  description = "List of app repositories for Flux GitOps (uses semver tags)"
  type = list(object({
    name   = string
    url    = string
    semver = string
    path   = string
  }))
  default = []
}
```

#### 4.5.2 ค่าใน `terraform/terraform.tfvars`

```hcl
app_repos = [
  {
    name   = "app-deployment"
    url    = "https://github.com/YOUR_USER/app-deployment"
    semver = ">=1.0.0"
    path   = "./clusters/base"
  },
  {
    name   = "config-repo"
    url    = "https://github.com/YOUR_USER/config-repo"
    semver = ">=1.0.0"
    path   = "./clusters/base"
  },
]
```

> **บังคับใช้ tag** — `semver` ทำให้ ignore commit ที่ไม่มี tag, ต้อง `git tag` + `git push --tags` เท่านั้นถึงจะ sync

#### 4.5.3 ใน `terraform/main.tf` — `for_each` สร้าง resource แบบ dynamic

```hcl
resource "kubernetes_manifest" "flux_git_repository_app" {
  for_each = { for r in var.app_repos : r.name => r }
  depends_on = [module.bootstrap]
  manifest = {
    apiVersion = "source.toolkit.fluxcd.io/v1"
    kind       = "GitRepository"
    metadata = {
      name      = each.value.name
      namespace = "flux-system"
    }
    spec = {
      interval = "1m"
      url      = each.value.url
      ref = { semver = each.value.semver }
    }
  }
}

resource "kubernetes_manifest" "flux_kustomization_app" {
  for_each = { for r in var.app_repos : r.name => r }
  depends_on = [kubernetes_manifest.flux_git_repository_app]
  manifest = {
    apiVersion = "kustomize.toolkit.fluxcd.io/v1"
    kind       = "Kustomization"
    metadata = {
      name      = each.value.name
      namespace = "flux-system"
    }
    spec = {
      interval  = "5m"
      sourceRef = {
        kind = "GitRepository"
        name = each.value.name
      }
      path  = each.value.path
      prune = true
      wait  = true
      postBuild = {
        substitute = {
          domain                = var.domain
          backup_bucket         = var.backup_bucket
          backup_retention_db   = tonumber(var.backup_retention_db)
          backup_retention_vault = tonumber(var.backup_retention_vault)
        }
      }
    }
  }
}
```

#### 4.5.4 รัน Terraform

```bash
cd terraform
terraform apply
```

#### 4.5.5 โครงสร้าง App Repo

```
app-deployment/
├── clusters/
│   └── base/
│       └── kustomization.yaml    # Kustomize root
└── apps/
    ├── myapp/
    │   ├── kustomization.yaml
    │   ├── namespace.yaml
    │   ├── deployment.yaml
    │   ├── service.yaml
    │   └── ingress.yaml
    └── ...
```

**`clusters/base/kustomization.yaml`:**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../apps/myapp
```

#### 4.5.6 Deploy Flow

```bash
# ใน app-deployment repo
git add .
git commit -m "feat: myapp v2"
git tag v1.0.1
git push origin main --tags    # ต้องมี tag เท่านั้น!
```

Flux จะ sync ให้อัตโนมัติภายใน ~1-5 นาที ถ้าไม่มี tag → Flux ignore

#### 4.5.7 ตัวแปรร่วมจาก Infra Repo

`postBuild` ส่งตัวแปรให้ app repo ใช้:

| ตัวแปร | ค่า default | ใช้กับ |
|--------|-------------|-------|
| `${domain}` | `local` | ingress host |
| `${backup_bucket}` | `backup` | bucket name |
| `${backup_retention_db}` | `14` | db backup retention |
| `${backup_retention_vault}` | `30` | vault retention |

ตัวอย่าง `apps/myapp/ingress.yaml`:
```yaml
spec:
  rules:
    - host: myapp.${domain}
```

### 4.6 External App เชื่อมต่อ Secret จาก Vault (Manual)

กรณีเพิ่ม secret manual ผ่าน Vault UI/CLI แล้วต้องการให้ app จาก repo อื่น (Multi-Repo) ดึงไปใช้:

#### 4.6.1 เขียน Secret ลง Vault

```bash
# ผ่าน CLI — exec vault-0
kubectl exec -n vault vault-0 -- vault kv put secret/myapp api-key=xxx db-password=yyy

# หรือผ่าน UI ที่ http://vault.{DNS}:8200
```

#### 4.6.2 สร้าง ExternalSecret ใน App Repo

ใน `app-deployment/apps/myapp/externalsecret.yaml`:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: myapp-secret
  namespace: myapp
spec:
  refreshInterval: "1h"
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore    # Cluster-scoped — ใช้ข้าม namespace ได้
  target:
    name: myapp-secret         # K8s Secret ที่จะถูกสร้าง
  data:
    - secretKey: api-key
      remoteRef:
        key: secret/myapp
        property: api-key
    - secretKey: db-password
      remoteRef:
        key: secret/myapp
        property: db-password
```

#### 4.6.3 ClusterSecretStore — มีอยู่แล้ว ไม่ต้องสร้าง

`ClusterSecretStore: vault-backend` ถูก deploy โดย infra repo แล้ว (`apps/vault/cluster-secret-store.yaml`) — อ่าน token จาก namespace `external-secrets` โดยตรง:

```yaml
auth:
  tokenSecretRef:
    name: vault-token
    namespace: external-secrets   # fixed — ไม่ต้อง copy ไป namespace อื่น
    key: token
```

> ✅ **ไม่ต้อง copy `vault-token` ไป namespace ใหม่** — ใช้ namespace `external-secrets` เป็นศูนย์กลาง
> ✅ **ไม่ต้องเพิ่ม namespace ใน terraform_data.vault_init**
> ⚠️ ต้องใช้ External Secrets Operator v0.8+ (cluster มี v0.14.0)

#### 4.6.4 อ้างอิง Secret ใน Deployment

```yaml
env:
  - name: API_KEY
    valueFrom:
      secretKeyRef:
        name: myapp-secret
        key: api-key
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: myapp-secret
        key: db-password
```

#### 4.6.5 Deploy

```bash
# push + tag ใน app-deployment repo
git add .
git commit -m "feat: myapp with vault secret"
git tag v1.0.1
git push origin main --tags
```

### 4.7 หลัง Reboot — Vault Raft Auto-Unseal ด้วย CronJob

ต่างจาก dev mode ที่ data หายหมด, Raft mode **data อยู่ persistent** แต่ Vault จะ sealed หลัง restart

**CronJob `vault-auto-unseal`** (`apps/vault-auto-unseal/`) จะตรวจสอบสถานะ Vault ทุก 15 นาที และ unseal อัตโนมัติโดยใช้ key จาก Secret `vault-keys` — **ไม่ต้อง manual unseal อีกต่อไป**

| Component | Details |
|-----------|---------|
| Schedule | `*/15 * * * *` (ทุก 15 นาที) |
| Image | `bitnami/kubectl:latest` |
| Mechanism | exec เข้า `vault-0` → เช็ค `vault status` → ถ้า sealed → `vault operator unseal` |
| Key Source | Secret `vault-keys` (สร้างโดย `terraform_data.vault_init`) |
| RBAC | SA `vault-auto-unseal` มีสิทธิ์ get secret, get pod, create pods/exec |

> **หมายเหตุ:** Vault ใช้ PVC ขนาด 128Mi — ถ้า cluster ยังไม่มี Storage Provisioner (เช่น OpenEBS, Rook, Longhorn) PVC จะ Pending
> ดูวิธีติดตั้ง OpenEBS สำหรับ Talos ได้ที่: https://openebs.io/docs/user-guides/installation

---

## 🚀 How to Deploy a New App

โปรเจกต์นี้ deploy app ผ่าน **Flux GitOps** ด้วย Kustomize (ไม่ต้องรัน terraform ทุกครั้ง)

### ขั้นตอน

#### 1. สร้างโฟลเดอร์ `apps/<app-name>/`

สร้างไฟล์ตามนี้:

```
apps/<app-name>/
├── kustomization.yaml      # รวม resources
├── namespace.yaml          # Namespace (required)
├── deployment.yaml         # หรือ statefulset
├── service.yaml
└── ingress.yaml            # ถ้าต้องการ expose ผ่าน Traefik
```

#### 2. ตัวอย่างไฟล์

**`namespace.yaml`:**
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: myapp
```

**`deployment.yaml`:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: myapp
spec:
  replicas: 1
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
        - name: myapp
          image: nginx:alpine
          ports:
            - containerPort: 80
```

**`service.yaml`:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: myapp
  namespace: myapp
  annotations:
    tailscale.com/expose: "true"
    tailscale.com/hostname: myapp
spec:
  selector:
    app: myapp
  ports:
    - port: 80
      targetPort: 80
```

**`ingress.yaml`** (ถ้าต้องการ expose ผ่าน Traefik + domain):
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp
  namespace: myapp
spec:
  ingressClassName: traefik
  rules:
    - host: myapp.${domain}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: myapp
                port:
                  number: 80
```

**`kustomization.yaml`:**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: myapp
resources:
  - namespace.yaml
  - deployment.yaml
  - service.yaml
  - ingress.yaml
```

#### 3. เพิ่มใน `clusters/base/kustomization.yaml`

```yaml
resources:
  - ../../apps/vault
  - ../../apps/vault-auto-unseal
  - ../../apps/minio
  - ../../apps/postgresql
  - ../../apps/cronjob-backup
  - ../../apps/myapp              # ← เพิ่มตรงนี้
```

#### 4. Push + Tag → Flux sync อัตโนมัติ

```bash
git add .
git commit -m "feat: add myapp"
git tag v1.0.x           # bump version
git push origin main --tags
```

### การใช้ Secret จาก Vault

ถ้า app ต้องการ secret จาก Vault (ผ่าน External Secrets Operator):

**`externalsecret.yaml`:**
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: myapp-secret
  namespace: myapp
spec:
  refreshInterval: "1h"
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: myapp-secret
  data:
    - secretKey: api-key
      remoteRef:
        key: secret/myapp
        property: api-key
```

แล้วอ้างอิงใน `deployment.yaml`:
```yaml
env:
  - name: API_KEY
    valueFrom:
      secretKeyRef:
        name: myapp-secret
        key: api-key
```

> **หมายเหตุ:** ต้องมี SecretStore `vault-backend` ใน namespace นั้น — ถ้ายังไม่มี แก้ `cluster-secret-store.yaml` เป็น ClusterSecretStore (มีอยู่แล้ว namespace-wide) หรือสร้าง SecretStore ใหม่

### ตัวแปรที่ใช้แทนที่โดย Flux (postBuild)

| ตัวแปร | ค่า | ใช้ที่ |
|--------|-----|-------|
| `${domain}` | `local` | ingress hostname |
| `${backup_bucket}` | `backup` | backup scripts |
| `${backup_retention_db}` | `14` | database retention |
| `${backup_retention_vault}` | `30` | vault retention |

---

### สร้าง Talos Config (talosconfig)

Terraform สร้าง `.talosconfig` อัตโนมัติผ่าน `local_file.talos_config` (ใน `modules/bootstrap/`) โดยใช้ CA / client cert / key จาก `talos_machine_secrets.this`

```bash
terraform apply -target=module.bootstrap
cp modules/bootstrap/.talosconfig .talosconfig
talosctl version -e <IP> -n <IP>
```

**CA mismatch:** ถ้า bootstrap ครั้งแรกทำด้วยมือ (ก่อน Terraform) CA จะคนละตัว → error `x509: certificate signed by unknown authority`

**แก้:**

```bash
rm -f .talosconfig modules/bootstrap/.talosconfig
terraform apply -target=module.bootstrap
cp modules/bootstrap/.talosconfig .talosconfig
talosctl version -e <IP> -n <IP>
```

ตรวจสอบ `ca:` ขึ้นต้นด้วย `LS0t` (single-encoded) ไม่ใช่ `TFMw` (double-encoded)

---

## 👁️ การใช้งานประจำวัน

### เชื่อมต่อ cluster จากนอกบ้านผ่าน Tailscale

เมื่อเครื่องนอกบ้านติดตั้ง **Tailscale** และเชื่อมต่อ tailnet เดียวกันกับ cluster แล้ว:

```bash
# 1. หา Tailscale IP ของ node
tailscale status

# 2. แก้ kubeconfig ให้ใช้ Tailscale IP หรือ hostname
kubectl config set-cluster my-cluster --server=https://<tailscale-ip>:6443 --insecure-skip-tls-verify

# หรือใช้ terraform kubeconfig แล้วแก้ server: ด้วยมือ
terraform output -raw kubeconfig > ~/talos-kubeconfig
# แก้ field `server:` จาก IP ภายใน → Tailscale IP
```

> ถ้า cluster ใช้ self-signed cert ให้ใช้ `--insecure-skip-tls-verify` หรือเพิ่ม `certificate-authority-data` ที่ถูกต้อง

### ติดตาม cluster ด้วย k9s

```bash
# จากเครื่องนอกบ้านที่เชื่อม Tailscale
k9s --kubeconfig ~/talos-kubeconfig
# หรือ
export KUBECONFIG=~/talos-kubeconfig && k9s
```

### ส่องสถานะด้วย Lens (Windows 11)

เปิด **Lens** → Add Cluster → ใช้ kubeconfig + แก้ server เป็น Tailscale IP

### เข้าถึง services ผ่าน Tailscale MagicDNS

ทุก service เปิดตรงผ่าน Tailscale (MagicDNS `*.{DNS}`) — ไม่ต้อง port-forward, ไม่ต้อง ingress:

| Service | MagicDNS URL | Tailscale IP | เช็ค |
|---------|-------------|-------------|------|
| **MinIO Console** | `http://minio.{DNS}:9001` | `100.87.249.108` | ✅ Direct |
| **MinIO API** | `http://minio.{DNS}:9000` | `100.87.249.108` | ✅ Direct |
| **Vault UI** | `http://vault.{DNS}:8200` | `100.96.164.10` | ✅ Direct |
| **Traefik** | `http://traefik.{DNS}` | `100.121.159.17` | ✅ Direct |
| **PostgreSQL** | `postgresql.{DNS}:5432` | `100.97.0.118` | ✅ Direct |
| **Gyre (Flux UI)** | `http://flux-ui.{DNS}:9001` | — | ✅ Direct |

**Fallback (ถ้า browser DoH ขัดขวาง MagicDNS):** ใช้ Tailscale IP แทน

### เช็ค Tailscale status

```bash
tailscale status
# (flux-ui จะแสดงหลังจาก Tailscale proxy pod สร้างเสร็จ)
```

### 📊 Gyre (Flux UI)

**Gyre** เป็น UI สำหรับดูสถานะ cluster และ Flux pipeline แบบ visual (มาแทน Weave GitOps):

| รายการ | รายละเอียด |
|--------|-----------|
| URL | `http://flux-ui.{DNS}:9001` |
| Namespace | `flux-ui` |
| Auth | Username/Password (admin + Vault-managed password) |
| Login API | `POST /api/v1/auth/login` (JSON `{"username","password"}`) |

#### รับ Password สำหรับ Login

Username: `admin`

Password ถูกเก็บใน Vault (`secret/gyre/admin`) และ sync มายัง Secret `gyre-initial-admin-secret` โดย ExternalSecret:

```bash
kubectl get secret gyre-initial-admin-secret -n flux-ui -o jsonpath='{.data.password}' | base64 -d
```

#### การจัดการ Admin Credential ผ่าน Vault

Password ถูกคุมโดย Vault (`secret/gyre/admin`) และ sync มายัง K8s Secret `gyre-initial-admin-secret` โดย ExternalSecret (`refreshInterval: 1h`)

**สร้าง credential ครั้งแรก (ถ้ายังไม่มีใน Vault):**
```bash
PASS=$(openssl rand -base64 32)
kubectl exec -n vault vault-0 -- vault kv put secret/gyre/admin password="$PASS"
echo $PASS
```

**ดู password ปัจจุบัน:**
```bash
# ผ่าน K8s secret (ที่ ExternalSecret sync ไว้)
kubectl get secret gyre-initial-admin-secret -n flux-ui -o jsonpath='{.data.password}' | base64 -d

# หรือผ่าน Vault โดยตรง
kubectl exec -n vault vault-0 -- vault kv get -field=password secret/gyre/admin
```

**เปลี่ยน password (rotation):**
```bash
NEW_PASS=$(openssl rand -base64 32)
kubectl exec -n vault vault-0 -- vault kv put secret/gyre/admin password="$NEW_PASS"
```
ExternalSecret จะ sync อัตโนมัติภายใน ~1 ชม. ถ้าต้องการ force sync ทันที:
```bash
kubectl delete secret gyre-initial-admin-secret -n flux-ui
```

```
Flow:
Vault (secret/gyre/admin)
  └─► ExternalSecret gyre-admin (refreshInterval: 1h)
        └─► K8s Secret gyre-initial-admin-secret
              └─► Gyre chart (admin.autoGenerate=false)
```

#### หมายเหตุการ Deploy

- **Session cookies:** Gyre ใช้ Better Auth กับ `NODE_ENV=development` (override ผ่าน Flux HelmRelease `postRenderers`) — cookie `gyre_session` ไม่มี `Secure` flag และไม่มี `__Secure-` prefix เพื่อให้ทำงานบน HTTP ผ่าน Tailscale
- **TLS:** ไม่จำเป็น — cookie ใช้ได้กับ HTTP แล้ว
- **Helm chart:** ใช้ OCIRepository `oci://ghcr.io/entropy0120/charts/gyre` semver `>=0.7.0`
- **Encryption keys, metrics token, admin password:** จัดการโดย ExternalSecret ดึงจาก Vault (`secret/gyre/encryption`, `secret/gyre/metrics`, `secret/gyre/admin`)
- **Persistent storage:** PVC storageClass `local-path` ขนาด 1Gi
- **Expose ผ่าน Tailscale:** Service `gyre-tailscale` พร้อม annotation `tailscale.com/expose: "true"`, hostname `flux-ui`, port 9001 → 3000 (ตรงถึง Gyre)

#### ดู Pipeline แบบ CLI (เผื่อ UI ยังไม่พร้อม)

```bash
flux get sources git
flux get kustomizations
flux get helmreleases -A
flux logs
```

### 🔑 Ops-User — Limited RBAC สำหรับ External Tools

ServiceAccount `ops-user` ใน namespace `flux-system` ใช้สำหรับเครื่องภายนอก (k9s, Lens, CI/CD) ที่ต้องการ connect cluster โดยไม่ใช้ admin kubeconfig:

| Component | Name | Namespace |
|-----------|------|-----------|
| ServiceAccount | `ops-user` | `flux-system` |
| Token Secret | `ops-token` | `flux-system` |
| ClusterRole | `cluster-readonly` | cluster-scoped (get/list/watch ทุก resource) |
| Role (svc-writer) | `svc-writer` | per `app_repos[*].namespaces` (create/update/delete service) |

#### วิธีรับ kubeconfig

```bash
# 1. ผ่าน Terraform output
cd terraform
terraform output ops_kubeconfig > ~/ops-kubeconfig

# 2. หรือใช้ไฟล์ที่มีอยู่แล้ว
cp terraform/ops-kubeconfig ~/ops-kubeconfig
```

kubeconfig จะใช้ **Tailscale MagicDNS** (`k8s-api.{DNS}:443`) โดยอัตโนมัติ ถ้าเซ็ต `tailscale_domain` ใน tfvars

#### วิธีใช้งาน

```bash
# ใช้กับ kubectl
kubectl --kubeconfig ~/ops-kubeconfig get pods -A

# ใช้กับ k9s
k9s --kubeconfig ~/ops-kubeconfig

# ใช้กับ Lens (Windows 11)
เปิด Lens → Add Cluster → เลือกไฟล์ ~/ops-kubeconfig

# export เป็น default
export KUBECONFIG=~/ops-kubeconfig
kubectl get pods -A
```

#### ข้อจำกัด

- ✅ อ่านได้ทุก resource (get/list/watch)
- ✅ แก้ไข Service ใน namespace ที่กำหนด (`app_repos[*].namespaces`)
- ❌ ไม่สามารถแก้ Deployment, StatefulSet, Secret อื่นๆ
- ❌ ไม่สามารถลบ resource ใดๆ (ยกเว้น service ใน namespace ที่กำหนด)

#### Regenerate kubeconfig (ถ้า token หมดอายุ)

```bash
cd terraform
terraform apply
terraform output ops_kubeconfig > ~/ops-kubeconfig
```

---

## 🗄️ ระบบ Backup อัตโนมัติ

ระบบ backup แบ่งเป็น 2 CronJob ทำงานทุกคืน อัปโหลดไปยัง MinIO bucket `backup/`:

#### Database Backup — `pg-dump-backup` (namespace: database)

| รายการ | รายละเอียด |
|--------|-----------|
| Schedule | `0 2 * * *` (ตี 2) |
| File | `db-postgresql-{timestamp}.sql.gz` |
| Path | `backup/database/` |
| Retention | `${backup_retention_db}` วัน (default: 14) |

**Flow:**
1. `pg_dump` → gzip → `/tmp/db-postgresql-{timestamp}.sql.gz`
2. `mc mb` สร้าง bucket `backup` ถ้ายังไม่มี
3. `mc cp` ไป `backup/database/`
4. `mc rm --older-than` ลบไฟล์เกิน retention
5. Pod ปิดตัว คืน RAM

#### Vault Snapshot — `vault-backup` (namespace: vault)

| รายการ | รายละเอียด |
|--------|-----------|
| Schedule | `0 3 * * *` (ตี 3 หลัง db backup) |
| File | `vault-vault-{timestamp}.snap` |
| Path | `backup/vault/` |
| Retention | `${backup_retention_vault}` วัน (default: 30) |

**Flow:**
1. เช็คว่า Vault sealed → unseal อัตโนมัติ
2. `vault operator raft snapshot save -` → pipe ตรงไป `mc pipe`
3. `mc rm --older-than` ลบไฟล์เกิน retention

**Restore Vault:**
```bash
kubectl exec vault-0 -n vault -- vault operator raft snapshot restore /tmp/vault.snap
```

#### MinIO Bucket Structure
```
backup/
├── database/
│   └── db-postgresql-20260705-020000.sql.gz
└── vault/
    └── vault-vault-20260705-030000.snap
```

Bucket `backup` ถูกสร้างอัตโนมัติโดย init container ของ MinIO Deployment

#### Configurable Variables (`terraform/terraform.tfvars`)

| Variable | Default | Description |
|----------|---------|-------------|
| `backup_bucket` | `backup` | MinIO bucket name |
| `backup_retention_db` | `14` | retention days database |
| `backup_retention_vault` | `30` | retention days vault |

---

## 🔧 คำสั่งที่มีประโยชน์

```bash
# เช็ค health คลัสเตอร์
talosctl health --nodes <IP>

# อ่าน logs ของ control plane
talosctl logs controller-manager --nodes <IP>

# รีบูตเครื่อง
talosctl reboot --nodes <IP>

# อัปเกรด Talos version
talosctl upgrade --image ghcr.io/siderolabs/installer:v1.7.0 --nodes <IP>

# เข้า shell ใน Talos node
talosctl reset --nodes <IP>
```

---

## 🔁 การกู้คืนระบบ

### ถ้าเครื่องดับแล้ว IP เปลี่ยน

```bash
# หา IP ใหม่
talosctl health --insecure --nodes <IP_ใหม่>

# Apply config ซ้ำ
talosctl apply-config --insecure --nodes <IP_ใหม่> -f controlplane.yaml
```

### ถ้าต้องการ Reset Talos ทั้งหมด

```bash
talosctl reset --graceful=false --reboot --nodes <IP>
```

### ถ้าต้องการ Bootstrap ใหม่ด้วย Terraform

```bash
cd terraform
terraform destroy   # ลบ cluster resources
terraform apply     # สร้างใหม่ทั้งหมด
```

---

## 🔐 Tailscale Operator — OAuth + Tag Ownership Flow

ตอนนี้ใช้ **OAuth Client** แทน Auth Key (ไม่หมดอายุ, secure กว่า)

### โครงสร้าง Tags

| Tag | เจ้าของ (tagOwners) | ใช้กับ |
|-----|---------------------|--------|
| `tag:k8s-operator` | `[]` (root tag) | ตัว Operator เอง — ใช้ OAuth client เพื่อ authenticate |
| `tag:k8s` | `["tag:k8s-operator"]` | Proxy devices (Traefik, PostgreSQL, etc.) |
| `tag:talos` | `["tag:k8s-operator"]` | Proxy devices เพิ่มเติม |

### หลักการทำงาน

1. OAuth Client สร้างโดยมี **แค่ `tag:k8s-operator`** tag เดียว
2. Operator ใช้ OAuth client ขอ auth key ด้วย `tag:k8s-operator` → exact match สำเร็จ
3. เมื่อ operator online แล้ว จะสร้าง proxy devices ด้วย `tag:k8s`,`tag:talos` → ownership check ผ่านเพราะ `tag:k8s-operator` เป็น owner ใน `tagOwners`

### วิธีตั้งค่า OAuth Client

1. ไปที่ https://login.tailscale.com/admin/settings/oauth
2. กด **Generate OAuth Client**
3. ตั้งค่า:
   - **Description:** `talos`
   - **Scopes:** `devices/core:write`, `devices/routes:write`, `auth_keys:write`
   - **Tags:** `k8s-operator` **(แค่ tag เดียว!)**
4. แปะ `client_id` และ `client_secret` ใน `terraform.tfvars`

### ACL `tagOwners` ที่ต้องมี

```json
"tagOwners": {
    "tag:k8s-operator": [],
    "tag:k8s": ["tag:k8s-operator"],
    "tag:talos": ["tag:k8s-operator"]
}
```

> ถ้า OAuth client มีหลาย tags แต่ operator ขอแค่ tag เดียว → exact-match ล้มเหลว → ownership check ก็ล้ม เพราะ ACL format ไม่ถูก → "requested tags are invalid or not permitted"
>
> ดู Troubleshooting #17 ใน [`TROUBLESHOOTING.md`](./TROUBLESHOOTING.md)

### PodSecurity — Talos ปิดกั้น Tailscale proxy pods

Talos เปิด PodSecurity admission ไว้ที่ระดับ `baseline` แต่ Tailscale proxy pods ต้องการ `NET_ADMIN` + `privileged`
→ ถ้าไม่แก้ proxy pods จะไม่ถูกสร้าง (StatefulSet Ready = 0/1)

**วิธีแก้ — label namespace `platform`:**

```bash
kubectl label ns platform pod-security.kubernetes.io/enforce=privileged --overwrite
kubectl delete sts -n platform -l tailscale.com/managed=true
```

หรือให้ Terraform จัดการอัตโนมัติ — เพิ่ม label ใน `kubernetes_namespace.platform` ([`main.tf`](./terraform/modules/bootstrap/main.tf))
แล้วรัน `terraform apply`

---

## 📋 Custom Resource Definitions (CRDs)

CRDs ทั้งหมดที่อยู่ใน cluster หลังจาก Terraform apply เสร็จ มี 2 ประเภท:

### CRDs ที่ Terraform สร้างโดยตรง (`kubernetes_manifest`)

| CRD | API Version | สร้างเมื่อ | ใช้ทำอะไร |
|-----|-------------|-----------|-----------|
| `GitRepository` | `source.toolkit.fluxcd.io/v1` | Terraform apply | บอก Flux ว่าต้อง watch git repo ไหน |
| `Kustomization` | `kustomize.toolkit.fluxcd.io/v1` | Terraform apply | บอก Flux ว่าต้อง sync path `./clusters/base` |

### CRDs ที่ติดตั้งมาพร้อม Helm chart (มา auto ไม่ต้องเขียนเอง)

#### Tailscale Operator
| CRD | API Version | มีไว้ทำอะไร |
|-----|-------------|-----------|
| `ProxyClass` | `tailscale.com/v1alpha1` | กำหนด proxy settings สำหรับ Tailscale |
| `Connector` | `tailscale.com/v1alpha1` | เชื่อม service ใน cluster เข้า Tailscale VPN |
| `DNSConfig` | `tailscale.com/v1alpha1` | ตั้งค่า MagicDNS / split DNS ผ่าน Tailscale |

#### Traefik
| CRD | API Version | มีไว้ทำอะไร |
|-----|-------------|-----------|
| `IngressRoute` | `traefik.io/v1alpha1` | Traefik CRD version ของ Ingress (แต่เราใช้ standard Ingress แทน) |
| `Middleware` | `traefik.io/v1alpha1` | กำหนด middleware chain เช่น rate limit, auth, redirect |
| `IngressRouteTCP` | `traefik.io/v1alpha1` | TCP routing (non-HTTP เช่น PostgreSQL, Redis) |
| `IngressRouteUDP` | `traefik.io/v1alpha1` | UDP routing (DNS, syslog) |
| `TLSOption` | `traefik.io/v1alpha1` | กำหนด TLS settings |
| `TLSStore` | `traefik.io/v1alpha1` | กำหนด certificate store |
| `ServersTransport` | `traefik.io/v1alpha1` | กำหนด backend server transport |

#### Flux CD
| CRD | API Version | มีไว้ทำอะไร |
|-----|-------------|-----------|
| `GitRepository` | `source.toolkit.fluxcd.io/v1` | Source ที่ชี้ไปยัง git repo |
| `OCIRepository` | `source.toolkit.fluxcd.io/v1beta2` | Source ที่ชี้ไปยัง OCI registry |
| `HelmRepository` | `source.toolkit.fluxcd.io/v1` | Source ที่ชี้ไปยัง Helm chart repo |
| `HelmChart` | `source.toolkit.fluxcd.io/v1` | Helm chart version ที่ resolve แล้ว |
| `Bucket` | `source.toolkit.fluxcd.io/v1` | Source ที่ชี้ไปยัง S3/MinIO bucket |
| `Kustomization` | `kustomize.toolkit.fluxcd.io/v1` | **ตัว deploy จริง** — kustomize build + apply |
| `HelmRelease` | `helm.toolkit.fluxcd.io/v1` | ปล่อย Helm chart ผ่าน Flux (เหมือน helm_release ของ Terraform) |
| `Alert` | `notification.toolkit.fluxcd.io/v1` | ส่ง notification (Slack, Discord, email) |
| `Provider` | `notification.toolkit.fluxcd.io/v1` | กำหนด provider สำหรับ Alert |
| `Receiver` | `notification.toolkit.fluxcd.io/v1` | รับ webhook จาก GitHub/GitLab เพื่อ trigger sync |
| `ImageRepository` | `image.toolkit.fluxcd.io/v1alpha2` | scan image registry เพื่อหา version ล่าสุด |
| `ImagePolicy` | `image.toolkit.fluxcd.io/v1alpha2` | กำหนด policy การเลือก image version |
| `ImageUpdateAutomation` | `image.toolkit.fluxcd.io/v1alpha2` | auto-update manifests เมื่อมี image ใหม่ |

> CRDs ที่ **ใช้จริง** ในโปรเจกต์นี้: `GitRepository`, `Kustomization` (สร้างโดย Terraform)
> ส่วนที่เหลือติดตั้งมาพร้อม Helm chart พร้อมใช้เมื่อต้องการในอนาคต

---

## 💡 สรุป

จุดเด่นที่สุดของโปรเซสนี้คือ **"ความโปร่งใสและตรวจสอบได้ (No Magic)"** เพราะตั้งแต่ Phase 3 เป็นต้นไป สามารถเปิดโปรแกรม **Lens** บน Windows 11 ส่องดูสถานะของ Pods, Ingress และตรวจสอบตัวแอปพลิเคชันผ่าน Web Browser ได้อย่างเรียลไทม์ ผ่านท่อปลอดภัยของ Tailscale

```
[ Phase 1 ]       [ Phase 2 ]        [ Phase 3 ]               [ Phase 4 ]
USB ISO ──> Talos ──> Kubernetes ──> Terraform ──> Flux CD ──> Apps
                                    (IaC)          (GitOps)    (Auto Pilot)
```

---

> ดู Troubleshooting ทั้งหมดได้ที่ [`TROUBLESHOOTING.md`](./TROUBLESHOOTING.md)