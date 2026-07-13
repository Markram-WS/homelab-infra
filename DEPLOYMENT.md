# 🚀 คู่มือสร้าง App ใหม่ (Multi-Repo GitOps)

> สำหรับ deploy app ผ่าน **repo แยก** (`app-deployment`) โดยใช้ Flux + Vault

---

## 📋 ขั้นตอนโดยรวม

```
1. เพิ่ม repo ใน tfvars → terraform apply
2. สร้าง repo ใหม่ + structure
3. เขียน secret ลง Vault (optional)
4. สร้าง ExternalSecret manifest
5. push + tag → Flux sync
```

---

## 1. เพิ่ม App Repo ใน Infra Repo

### `terraform/terraform.tfvars`

```hcl
app_repos = [
  {
    name   = "app-deployment"
    url    = "https://github.com/YOUR_USER/app-deployment"
    semver = ">=1.0.0"
    path   = "./clusters/base"
  },
]
```

```bash
cd terraform
terraform apply
```

Flux จะสร้าง `GitRepository` + `Kustomization` ให้ใน cluster

---

## 2. สร้าง App Repo + โครงสร้างไฟล์

### โครงสร้าง repo

```
app-deployment/
├── clusters/
│   └── base/
│       └── kustomization.yaml        # root kustomize — รวม apps/
└── apps/
    └── <app-name>/
        ├── kustomization.yaml
        ├── namespace.yaml
        ├── deployment.yaml
        ├── service.yaml
        ├── ingress.yaml               # optional — ถ้าต้องการ expose ผ่าน Traefik
        └── externalsecret.yaml        # optional — ถ้าต้องการ secret จาก Vault
```

### 2.1 `apps/<app-name>/namespace.yaml`

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: <app-name>
```

### 2.2 `apps/<app-name>/deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: <app-name>
  namespace: <app-name>
spec:
  replicas: 1
  selector:
    matchLabels:
      app: <app-name>
  template:
    metadata:
      labels:
        app: <app-name>
    spec:
      containers:
        - name: <app-name>
          image: <your-image>:latest
          ports:
            - containerPort: 80
          env:
            - name: API_KEY
              valueFrom:
                secretKeyRef:
                  name: <app-name>-secret
                  key: api-key
```

### 2.3 `apps/<app-name>/service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: <app-name>
  namespace: <app-name>
  annotations:
    tailscale.com/expose: "true"
    tailscale.com/hostname: <app-name>
spec:
  selector:
    app: <app-name>
  ports:
    - port: 80
      targetPort: 80
```

### 2.4 `apps/<app-name>/ingress.yaml` (optional)

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: <app-name>
  namespace: <app-name>
spec:
  ingressClassName: traefik
  rules:
    - host: <app-name>.${domain}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: <app-name>
                port:
                  number: 80
```

### 2.5 `apps/<app-name>/externalsecret.yaml` (optional)

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: <app-name>-secret
  namespace: <app-name>
spec:
  refreshInterval: "1h"
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: <app-name>-secret
  data:
    - secretKey: api-key
      remoteRef:
        key: secret/<vault-path>
        property: api-key
    - secretKey: db-password
      remoteRef:
        key: secret/<vault-path>
        property: db-password
```

### 2.6 `apps/<app-name>/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: <app-name>
resources:
  - namespace.yaml
  - deployment.yaml
  - service.yaml
  - ingress.yaml
  - externalsecret.yaml
```

### 2.7 `clusters/base/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../apps/<app-name>
```

---

## 3. เขียน Secret ลง Vault (กรณี Manual)

ก่อนที่ ExternalSecret จะ sync ต้องมี key ใน Vault ก่อน:

```bash
# เช็คว่า Vault unsealed
kubectl exec -n vault vault-0 -- vault status

# เขียน secret
kubectl exec -n vault vault-0 -- vault kv put secret/<vault-path> \
  api-key=your-api-key \
  db-password=your-db-password
```

หรือผ่าน UI ที่ `http://vault.{DNS}:8200`

> ✅ **เขียนตอนไหนก็ได้** — แต่แนะนำให้เขียน **ก่อน push tag** เพื่อให้ ExternalSecret sync เสร็จทันที

---

## 4. Push + Tag → Deploy

```bash
git add .
git commit -m "feat: add <app-name>"
git tag v1.0.0
git push origin main --tags
```

> ⚠️ **ต้องมี tag เท่านั้น** — Flux ใช้ `semver` ดังนั้น commit เปล่าๆ จะถูก ignore

---

## 5. เช็คสถานะ

```bash
# เช็ค GitRepository sync
flux get sources git

# เช็ค Kustomization status
flux get kustomizations

# เช็ค ExternalSecret
kubectl get externalsecret -n <app-name>

# เช็ค K8s Secret ที่ถูกสร้าง
kubectl get secret -n <app-name> <app-name>-secret
```

---

## 🔑 เรื่อง vault-token ที่ควรรู้

- `ClusterSecretStore: vault-backend` มีอยู่แล้วใน cluster (**ไม่ต้องสร้างเอง**)
- `vault-token` ถูกเก็บใน namespace `external-secrets`  
- `ClusterSecretStore` อ่าน token จาก `external-secrets` โดยตรง (**namespace fixed**)  
- ดังนั้น **ไม่ต้อง copy vault-token ไป namespace ใหม่เลย**
- App repo แค่สร้าง `ExternalSecret` + `kind: ClusterSecretStore` → ทำงานได้ทันที

---

## 🔐 Ops-User — Limited Access สำหรับ External Tools

ServiceAccount `ops-user` (`flux-system`) สำหรับ k9s, Lens, CI/CD หรือ external tool ที่ต้องการเชื่อมต่อ Kubernetes โดยไม่ใช้ admin kubeconfig

| Component | อยู่ที่ | สิทธิ์ |
|-----------|--------|--------|
| ServiceAccount `ops-user` | `flux-system` | — |
| Secret `ops-token` | `flux-system` | Token สำหรับ authenticate |
| ClusterRole `cluster-readonly` | cluster-scoped | get/list/watch ทุก resource |
| Role `svc-writer` | per `app_repos[*].namespaces` | create/update/delete service |

### วิธีรับ kubeconfig

```bash
# ผ่าน Terraform output
cd terraform
terraform output ops_kubeconfig > ~/ops-kubeconfig

# หรือใช้ไฟล์ที่มีอยู่แล้ว
cp terraform/ops-kubeconfig ~/ops-kubeconfig
```

kubeconfig ใช้ `https://k8s-api.{DNS}:443` (ผ่าน Tailscale) โดยอัตโนมัติ

### วิธีใช้งาน

```bash
# kubectl
kubectl --kubeconfig ~/ops-kubeconfig get pods -A

# k9s
k9s --kubeconfig ~/ops-kubeconfig

# Lens (Windows 11)
Add Cluster → เลือกไฟล์ ~/ops-kubeconfig

# Export เป็นค่าเริ่มต้น
export KUBECONFIG=~/ops-kubeconfig
```

### Regenerate (เมื่อ token หมดอายุ)

```bash
cd terraform
terraform apply
terraform output ops_kubeconfig > ~/ops-kubeconfig
```

---

## 📊 Gyre (Flux UI)

Gyre ใช้ดูสถานะ cluster แบบ visual ที่ `http://flux-ui.{DNS}:9001`

```bash
# login credentials
# Username: admin
# Password: kubectl get secret gyre-initial-admin-secret -n flux-ui -o jsonpath='{.data.password}' | base64 -d
```

---

## 📦 ตัวแปร postBuild ที่ใช้ใน App Repo

| ตัวแปร | ค่า default | ใช้กับ |
|--------|-------------|-------|
| `${domain}` | `local` | ingress hostname |
| `${backup_bucket}` | `backup` | bucket name |
| `${backup_retention_db}` | `14` | db backup retention |
| `${backup_retention_vault}` | `30` | vault retention |

---

## ⚙️ Flow Diagram

```
[ Infra Repo ]
  ├── terraform.tfvars (app_repos list)
  ├── terraform/main.tf (for_each → GitRepository + Kustomization)
  └── apps/vault/cluster-secret-store.yaml (token → external-secrets ns)
                          │
                          v
[ Flux CD ] → GitRepository + Kustomization + postBuild vars
                          │
                          v
[ App Repo ] ── push + tag ──► Flux sync
  ├── apps/<app-name>/namespace.yaml
  ├── apps/<app-name>/deployment.yaml
  ├── apps/<app-name>/externalsecret.yaml ──► ClusterSecretStore vault-backend
  └── apps/<app-name>/service.yaml                │
                                                   v
                                           [ Vault ]
                                           secret/<vault-path>
```

---

## 🐛 ปัญหาที่พบบ่อย

### Git clone ลง `/app/` ไม่ได้ (fatal: destination path already exists)

```
fatal: destination path '/app/' already exists and is not an empty directory
```

**สาเหตุ:** Image มีไฟล์ `/app/requirements.txt` อยู่แล้ว ตอน `git clone` จะ error เพราะ `/app/` ไม่ใช่ empty directory

**โครงสร้างไฟล์ใน image:**
```
/app/ (จาก Dockerfile)
  └── requirements.txt     ← มีอยู่แล้ว ทำให้ git clone ลงตรงๆ ไม่ได้
```

**วิธีแก้:** clone ไป `/tmp/repo` ก่อน แล้วค่อย copy ไป `/app/`

```yaml
# initContainer
- name: clone-code
  image: alpine/git:latest
  command:
    - sh
    - -c
    - |
      git clone --depth 1 --branch centralized \
        https://<token>@github.com/YOUR_ORG/tradingsystem-settrade.git /tmp/repo
      cp -r /tmp/repo/* /app/
  volumeMounts:
    - name: app-code
      mountPath: /app

# main container
- name: app
  image: markram92/python-settrade:1.1.1   # image ที่มี Python dependencies ครบ
  command:
    - python
    - ./master/main.py
  volumeMounts:
    - name: app-code
      mountPath: /app
```

**ขั้นตอน:**
1. `git clone` → `/tmp/repo` (empty dir, git clone ได้)
2. `cp -r /tmp/repo/* /app/` — copy ทับไฟล์ image ทั้งหมด (รวม requirements.txt)
3. ใช้ `emptyDir` volume `app-code` แชร์ระหว่าง initContainer และ main container

> ทำไมไม่ใช้ `alpine/git` เป็น main container? — `alpine/git` มีแค่ git ไม่มี Python, FastAPI, numpy, pandas, Settrade SDK ที่ app ต้องใช้ จึงต้องใช้ `markram92/python-settrade:1.1.1` เป็น main container
