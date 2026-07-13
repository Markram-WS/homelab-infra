# Troubleshooting — ปัญหาที่พบบ่อย + วิธีแก้

### 1. Helm timeout — `context deadline exceeded` (ทุก chart)

**อาการ:** Terraform apply timeout 5 นาที — pods ทุกตัว Pending

**สาเหตุ:**  
3 ปัญหาที่ทำให้เกิดอาการนี้:

| # | ปัญหา | วิธีเช็ค | วิธีแก้ |
|---|-------|---------|--------|
| A | **No CNI** — Talos ไม่มี CNI มาให้ pods ไม่มี network | `kubectl get pods -n kube-system` ไม่เห็น `kube-flannel-*` | เพิ่ม `cni.yaml.tftpl` (flannel) → `terraform state rm` → `apply -target` → reboot |
| B | **Node Taint** — control-plane taint `NoSchedule` บน single-node cluster | `kubectl describe node` เห็น Taints: `node-role.kubernetes.io/control-plane:NoSchedule` | `kubectl taint nodes --all node-role.kubernetes.io/control-plane:NoSchedule-` หรือเพิ่ม `remove-taint.yaml.tftpl` |
| C | **Helm release ค้าง** — release ยังค้างใน cluster แต่ Terraform state หาย | `helm --kubeconfig=.\kubeconfig list -A` เห็น release ชื่อเดิม | `kubectl delete secret -n <ns> -l owner=helm` แล้ว `terraform apply` |

### 2. `cannot re-use a name that is still in use`

**อาการ:** Terraform บอก release name นี้มีอยู่แล้ว

**สาเหตุ:** Helm release metadata เก็บเป็น Kubernetes Secret (`type: helm.sh/release.v1`)  
`terraform state rm` ลบ state อย่างเดียว ไม่ได้ลบ Secret → Helm เห็น release เก่า → refuse

**แก้:** ดูชื่อ secret จริง:

```bash
kubectl --kubeconfig=.kubeconfig get secret -A | grep helm
```

แล้วลบทีละตัว (ตัวอย่าง):

```bash
kubectl --kubeconfig=.kubeconfig delete secret -n platform sh.helm.release.v1.tailscale-operator.v1
kubectl --kubeconfig=.kubeconfig delete secret -n platform sh.helm.release.v1.traefik.v1
kubectl --kubeconfig=.kubeconfig delete secret -n flux-system sh.helm.release.v1.flux.v1
kubectl --kubeconfig=.kubeconfig delete secret -n vault sh.helm.release.v1.vault.v1
kubectl --kubeconfig=.kubeconfig delete secret -n external-secrets sh.helm.release.v1.external-secrets.v1
kubectl --kubeconfig=.kubeconfig get secret -A | grep helm   # verify empty
terraform apply
```

### 3. `API did not recognize GroupVersionKind` — CRD chicken-and-egg

**อาการ:** `kubernetes_manifest.flux_git_repository` error — "no matches for kind GitRepository"

**สาเหตุ:** Flux Helm chart install CRDs เฉพาะตอน `helm install` ครั้งแรก  
`helm upgrade` (จาก `terraform apply` รอบถัดไป) ไม่ re-install CRDs  
Terraform `kubernetes_manifest` ต้องการ CRD ก่อนสร้าง resource

**แก้:**

```bash
# ถ้า terraform_data.flux_crds ล้ม → install CRDs manual fallback
terraform apply -target=module.bootstrap -auto-approve
kubectl --kubeconfig=.kubeconfig apply --server-side --force-conflicts -f https://github.com/fluxcd/flux2/releases/download/v2.3.0/install.yaml
kubectl --kubeconfig=.kubeconfig wait --for=condition=established --timeout=120s crd/gitrepositories.source.toolkit.fluxcd.io crd/kustomizations.kustomize.toolkit.fluxcd.io crd/buckets.source.toolkit.fluxcd.io crd/ocirepositories.source.toolkit.fluxcd.io
# แล้ว rerun รอบ 2
terraform apply
```

### 4. Flux controllers CrashLoopBackOff — `no matches for kind "Bucket" in version "…/v1"`

**อาการ:** Pods ใน `flux-system` (source-controller, helm-controller, kustomize-controller) crash loop ด้วย error:
```
no matches for kind "Bucket" in version "source.toolkit.fluxcd.io/v1"
failed to get restmapping
```

**สาเหตุ:** CRD version mismatch — `terraform_data.flux_crds` เคยใช้ URL `latest` ซึ่งเปลี่ยนตามเวอร์ชันของ Flux ที่ปล่อยใหม่ ทำให้ CRDs ไม่ match กับ controller version ที่ Helm chart ติดตั้งไว้

**วิธีแก้:**

```bash
# 1. patch storedVersions เพื่อย้าย storage version
kubectl patch crd buckets.source.toolkit.fluxcd.io --subresource=status -p '{"status":{"storedVersions":["v1"]}}'
kubectl patch crd ocirepositories.source.toolkit.fluxcd.io --subresource=status -p '{"status":{"storedVersions":["v1"]}}'

# 2. re-apply install.yaml (ใช้ version fix, ไม่ใช้ latest)
kubectl apply --server-side --force-conflicts \
  -f https://github.com/fluxcd/flux2/releases/download/v2.3.0/install.yaml

# 3. ลบ pods crash เพื่อให้ deployment สร้างใหม่
kubectl delete pod -n flux-system -l app.kubernetes.io/component=source-controller
kubectl delete pod -n flux-system -l app.kubernetes.io/component=helm-controller
kubectl delete pod -n flux-system -l app.kubernetes.io/component=kustomize-controller
kubectl delete pod -n flux-system -l app.kubernetes.io/component=source-watcher
```

**ป้องกัน:** `terraform_data.flux_crds` ถูก fix ให้ใช้ version `v2.3.0` ที่ตรงกับ Helm chart แล้ว — ไม่ใช้ `latest` อีกต่อไป

### 5. `terraform_data.flux_crds` — kubectl no kubeconfig

**อาการ:** `terraform_data.flux_crds` local-exec ล้ม — CRDs ไม่ถูก install

**สาเหตุ:** local-exec รัน `kubectl` แต่ไม่มี kubeconfig

**แก้:** ใช้ `local_file.kubeconfig` + `--kubeconfig=<path>` ใน local-exec

### 6. Tailscale Operator — ปัญหา OAuth / Tag / PodSecurity

**อาการรวม:** Pod stuck `ContainerCreating`, CrashLoopBackOff, หรือ proxy pods ไม่ถูกสร้าง

#### ปัญหา A: OAuth secret `operator-oauth` ไม่มี

**เช็ค:** `kubectl describe pod` เห็น `FailedMount: secret "operator-oauth" not found`

**แก้:**

```bash
kubectl create secret generic operator-oauth -n platform --from-literal=client_id="" --from-literal=client_secret=""
```

#### ปัญหา B: OAuth client tag mismatch (`requested tags [tag:xxx] are invalid or not permitted`)

**เช็ค:** `kubectl logs -n platform deploy/operator` เห็น `requested tags [tag:k8s-operator] are invalid or not permitted`

**สาเหตุ:**  
OAuth client มีหลาย tags (เช่น `tag:k8s`, `tag:k8s-operator`, `tag:talos`) แต่ operator ขอแค่ `tag:k8s-operator`  
Tailscale API ตรวจสอบแบบ **exact match** — ถ้า OAuth client มี 3 tags ต้องขอทั้ง 3 tags ถึงจะผ่าน  
หรือต้องใช้ **ownership** ใน `tagOwners` แทน

**แก้ไข:**

1. **ACL `tagOwners` ต้องใช้ format chain (ไม่ใช่ `autogroup:admin`):**
```json
"tagOwners": {
    "tag:k8s-operator": [],
    "tag:k8s": ["tag:k8s-operator"],
    "tag:talos": ["tag:k8s-operator"]
}
```

2. **สร้าง OAuth client ใหม่ที่ https://login.tailscale.com/admin/settings/oauth:**
   - **Description:** `talos`
   - **Scopes:** `devices/core:write`, `devices/routes:write`, `auth_keys:write`
   - **Tags:** `k8s-operator` **(แค่ tag เดียว!)**

3. **อัปเดต `terraform.tfvars`:**
```hcl
tailscale_oauth_client_id     = "<client-id-ใหม่>"
tailscale_oauth_client_secret = "<client-secret-ใหม่>"
tailscale_operator_tag        = "tag:k8s-operator"
tailscale_tags                = ["tag:k8s", "tag:talos"]
```

4. **รัน Terraform + restart operator:**
```bash
cd terraform
terraform apply
kubectl rollout restart deploy/operator -n platform
```

#### ปัญหา C: ACL `tagOwners` format ผิด

**เช็ค:** operator ขึ้น error เกี่ยวกับ permission — `tag:k8s-operator` ไม่สามารถ assign `tag:k8s` / `tag:talos` ให้ proxy devices ได้

**แก้:** ใช้ format ด้านบน โดย `tag:k8s-operator` ต้องเป็น root tag (`[]`) และเป็น owner ของ `tag:k8s` / `tag:talos`

#### ความหมายของ tag flow

| Layer | Tag | ทำงานยังไง |
|-------|-----|-----------|
| OAuth Client | `tag:k8s-operator` | exact match กับ `operatorConfig.defaultTags` → สร้าง auth key สำเร็จ |
| Operator device | `tag:k8s-operator` | device operator ถูก tagged ด้วย tag นี้ |
| Proxy devices | `tag:k8s`, `tag:talos` | operator (ที่มี `tag:k8s-operator`) เป็น owner ของ tag นี้ใน ACL → สามารถ assign ได้ |

> อ้างอิง: [GitHub Issue #15732](https://github.com/tailscale/tailscale/issues/15732), [Tailscale Docs — tag ownership](https://tailscale.com/docs/features/tags#ownership)

#### โครงสร้าง Helm values ที่ถูกต้อง

```yaml
# terraform/modules/bootstrap/helm-values/tailscale-operator.yaml.tftpl
operatorConfig:
  defaultTags:
    - ${operator_tag}      # = tag:k8s-operator (tag ตัว operator เท่านั้น)

proxyConfig:
  defaultTags: "${proxy_tags}"  # = tag:k8s,tag:talos (tag สำหรับ proxy devices)
```

### 7. `helm_release` resource — `timeouts` block ไม่ support

**อาการ:** `terraform apply` error — `Blocks of type "timeouts" are not expected here`

**สาเหตุ:** Helm Terraform provider v2.x ไม่รองรับ `timeouts` block

**แก้:** ลบ `timeouts` block ออกจาก resource — ใช้ default timeout 5 นาที

### 8. `kubectl apply --server-side` conflict กับ Helm

**อาการ:** `terraform_data.flux_crds` error — `Apply failed with conflicts with "terraform-provider-helm"`

**สาเหตุ:** Flux CRDs ถูก install โดย Helm chart แล้ว → `kubectl apply --server-side` ไม่มี `--force-conflicts` → conflict

**แก้:** ใช้ `--force-conflicts` flag:

```bash
kubectl --kubeconfig=.kubeconfig apply --server-side --force-conflicts -f https://github.com/fluxcd/flux2/releases/download/v2.3.0/install.yaml
```

### 9. MinIO / PostgreSQL — `CreateContainerConfigError` (secret "minio-secret" not found)

**อาการ:** Pod ใน namespace `minio` หรือ `database` อยู่ในสถานะ `CreateContainerConfigError` — container ไม่ start เพราะหา secret ไม่เจอ

**สาเหตุ:** `ClusterSecretStore` (global) มองหา `vault-token` ใน namespace เดียวกับ ExternalSecret ที่เรียกใช้ (เช่น `minio`, `database`) แต่ `vault-token` ถูกสร้างใน `external-secrets` เท่านั้น

**วิธีแก้ไขเร่งด่วน:**

```bash
# Copy vault-token ไปยัง namespace ที่ ExternalSecret เรียกใช้
ROOT_TOKEN=$(kubectl get secret vault-token -n external-secrets -o jsonpath='{.data.token}' | base64 -d)
kubectl create secret generic vault-token -n minio --from-literal=token="$ROOT_TOKEN" --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic vault-token -n database --from-literal=token="$ROOT_TOKEN" --dry-run=client -o yaml | kubectl apply -f -

# Restart external-secrets operator เพื่อ trigger re-sync
kubectl rollout restart deploy/external-secrets -n external-secrets
```

**ป้องกัน:** `terraform_data.vault_init` ถูกอัปเดตให้ copy `vault-token` ไปยัง `minio` และ `database` โดยอัตโนมัติทุกครั้งที่รัน `terraform apply`

 ### 10. Tailscale Proxy Pods — `violates PodSecurity "baseline:latest"` (privileged denied)

**อาการ:** Tailscale proxy pods (StatefulSet `ts-traefik-*`, `ts-postgresql-*`) ไม่ถูกสร้าง — `kubectl get sts` เห็น Ready = 0/1
```
Create Pod ts-traefik-xxx-0 failed: violates PodSecurity "baseline:latest":
non-default capabilities (container "tailscale" must not include "NET_ADMIN")
privileged (container "sysctler" must not set securityContext.privileged=true)
```

**สาเหตุ:**  
Talos เปิด PodSecurity admission ไว้ที่ระดับ `baseline` แต่ Tailscale proxy ต้องการ:
- `capabilities.add: ["NET_ADMIN"]` — เพื่อสร้าง tunnel interface
- `privileged: true` — container sysctler ต้องการปรับ kernel params

**วิธีแก้ไข:**

```bash
# เพิ่ม label ให้ namespace platform
kubectl label ns platform pod-security.kubernetes.io/enforce=privileged --overwrite

# ลบ StatefulSet เก่าให้ operator สร้างใหม่
kubectl delete sts -n platform -l tailscale.com/managed=true
```

หรือถ้าใช้ Terraform ให้เพิ่ม label ใน `kubernetes_namespace.platform`:

```hcl
resource "kubernetes_namespace" "platform" {
  metadata {
    name = "platform"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
    }
  }
}
```

แล้วรัน `terraform apply` — operator จะสร้าง proxy pods ใหม่โดยอัตโนมัติ

**ป้องกัน:** label ถูกเพิ่มใน Terraform แล้ว ([`main.tf`](./terraform/modules/bootstrap/main.tf)) — ครั้งหน้า `terraform apply` จะตั้งค่าให้อัตโนมัติ

### 11. Tailscale annotations หายหลัง Helm upgrade / Flux reconcile

**อาการ:** เคย `kubectl annotate` service ด้วย `tailscale.com/expose=true` เรียบร้อย proxy pod ทำงานได้ปกติ  
แต่พอ `terraform apply` (Helm upgrade) หรือ Flux reconcile ทีหลัง — annotation หาย proxy pod หยุดทำงาน

**สาเหตุ:**
| mechanism | annotation ถูก set ที่ไหน | persistence |
|-----------|--------------------------|-------------|
| `kubectl annotate` | บน cluster โดยตรง (imperative) | ❌ หายทันทีที่ manifest ถูก apply ซ้ำ |
| Helm values (`service.annotations`) | ใน Helm chart values | ✅ อยู่ทุกครั้งที่ Helm upgrade |
| GitOps manifest (`service.yaml`) | ใน Git repo (`apps/<svc>/service.yaml`) | ✅ อยู่ทุกครั้งที่ Flux reconcile |

**วิธีแก้ไข:**

| Service | ถูก deploy โดย | ต้องแก้ที่ |
|---------|---------------|-----------|
| **traefik** | Terraform Helm release (`modules/bootstrap`) | [`terraform/modules/bootstrap/helm-values/traefik.yaml`](./terraform/modules/bootstrap/helm-values/traefik.yaml): `service.annotations` ✅ (แก้ไว้แล้ว) |
| **vault-ui** | Terraform Helm release (`modules/bootstrap`) | [`terraform/modules/bootstrap/helm-values/vault.yaml`](./terraform/modules/bootstrap/helm-values/vault.yaml): `ui.service.annotations` |
| **minio** | Flux Kustomization (`clusters/base/`) | [`apps/minio/service.yaml`](./apps/minio/service.yaml): `metadata.annotations` |
| **postgresql** | Flux Kustomization (`clusters/base/`) | [`apps/postgresql/service.yaml`](./apps/postgresql/service.yaml): ✅ (แก้ไว้แล้ว) |

**เช็คว่า annotation อยู่จริง (หลัง sync):**
```bash
kubectl get svc -n minio minio -o jsonpath='{.metadata.annotations}' | jq .
kubectl get svc -n vault vault-ui -o jsonpath='{.metadata.annotations}' | jq .
# ต้องมี tailscale.com/expose และ tailscale.com/hostname
```

**เช็คว่า proxy pod ถูกสร้าง:**
```bash
kubectl get pods -n platform -l app.kubernetes.io/created-by=tailscale-operator
# ต้องเห็น ts-minio-xxx, ts-vault-ui-xxx, ts-traefik-xxx, ts-postgresql-xxx
```

### 12. Flux GitRepository — `no match found for semver: >=1.0.0`

**อาการ:** `kubectl get gitrepo -A` เห็น `READY=False` — `no match found for semver: >=1.0.0`
```
stored artifact for revision 'HEAD@sha1:xxx'
```

**สาเหตุ:**  
`GitRepository.spec.ref.semver` กำหนด `">=1.0.0"` แต่ git repo นี้ยังไม่มี tag version ใดๆ  
Flux ใช้ semver เพื่อเลือก commit ที่จะ sync — ถ้าไม่มี tag เลย จะ sync ไม่ได้

**แก้:**

```bash
# สร้าง tag แรก (ใช้ commit ปัจจุบัน)
git tag v1.0.0
git push origin v1.0.0

# หรือ bump version ถ้ามี tag เก่าอยู่แล้ว
git tag v1.0.1
git push origin v1.0.1

# trigger Flux reconcile
kubectl annotate gitrepository homelab -n flux-system reconcile.fluxcd.io/requestedAt=$(date +%s) --overwrite

# เช็ค
kubectl get gitrepo -n flux-system homelab -o jsonpath='{.status.artifact.revision}'
# ต้องเห็น v1.0.0@sha1:xxx หรือ v1.0.1@sha1:xxx
```

### 13. `DNS_PROBE_POSSIBLE` — MagicDNS ไม่ resolve ใน Browser

**อาการ:** เปิด browser → เข้า `http://minio.{DNS}:9001` → `DNS_PROBE_POSSIBLE`

**สาเหตุ:**  
Browser ใช้ DoH (DNS over HTTPS) ยิงไปที่ Cloudflare `1.1.1.1` โดยตรง ทำให้ **ข้าม** Tailscale DNS (`100.100.100.100`) → MagicDNS resolve ไม่เจอ

**เช็ค:**
```bash
# Tailscale DNS ต้องทำหน้าที่
scutil --dns   # macOS
systemd-resolve --status  # Linux
# ต้องเห็น xxxx.xxxx.xxxx.xxxx ใน nameserver list
```

**วิธีแก้:**
| วิธี | ทำยังไง |
|------|---------|
| **ปิด DoH ใน browser** | Chrome: Settings → Privacy → Security → Use secure DNS → **Off** |
| **ใช้ Tailscale IP แทน** | `http://xxxx.xxxx.xxxx.xxxx:9001` (MinIO), `http://xxxx.xxxx.xxxx.xxxx:8200` (Vault) |
| **เพิ่ม exception ใน DoH** | บาง browser เปิด DoH แต่ bypass สำหรับ `*.ts.net` ได้ |

### 14. Traefik Dashboard — `404 page not found` ผ่าน MagicDNS

**อาการ:** เปิด `http://traefik.{DNS}` → 404

**สาเหตุ:** ปัญหา 2 อย่าง:
1. **Host mismatch** — `matchRule` มีแค่ `Host(\`traefik.local\`)` แต่ MagicDNS ส่ง `Host: traefik.{DNS}`
2. **EntryPoint ผิด** — dashboard ใช้ `entryPoints: ["traefik"]` (port internal) แต่ request มาทาง port 80 (`web`)

**แก้ไข:** 

1. เพิ่ม `tailscale_domain` ใน `terraform/terraform.tfvars`:
```hcl
tailscale_domain = "{DNS}"
```

2. แปลง `traefik.yaml` → `traefik.yaml.tftpl` ใช้ template variable:
```yaml
ingressRoute:
  dashboard:
    enabled: true
    matchRule: Host(`traefik.local`)%{ if tailscale_domain != "" } || Host(`traefik.${tailscale_domain}`)%{ endif }
    entryPoints: ["web"]
```

3. อัปเดต `helm_release.traefik` ให้ใช้ `templatefile()`:
```hcl
values = [templatefile("${path.module}/helm-values/traefik.yaml.tftpl", {
  tailscale_domain = var.tailscale_domain
})]
```

แล้วรัน:
```bash
cd terraform
terraform apply
```
