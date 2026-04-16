# Docker Registry on k3s / ARM64 — Research Cache

**Cache Date:** 2026-04-14
**Sources:** https://carpie.net/articles/installing-docker-registry-on-k3s, https://docs.k3s.io/installation/private-registry, Docker Hub registry:2 manifest, community k3s + Longhorn patterns
**Note:** Medium article (geekculture) returned 403 — covered by cross-referencing other sources.

---

## Table of Contents

1. [Docker Image: registry:2 ARM64 Support](#1-docker-image-registry2-arm64-support)
2. [Kubernetes Manifests — Complete Structure](#2-kubernetes-manifests--complete-structure)
3. [k3s registries.yaml — Official Format](#3-k3s-registriesyaml--official-format)
4. [htpasswd Secret Mounting](#4-htpasswd-secret-mounting)
5. [Longhorn PVC for Registry Storage](#5-longhorn-pvc-for-registry-storage)
6. [NodePort vs Ingress — Which to Use](#6-nodeport-vs-ingress--which-to-use)
7. [TLS and Insecure HTTP Setup](#7-tls-and-insecure-http-setup)
8. [k3s-Specific Gotchas](#8-k3s-specific-gotchas)
9. [ARM64 Caveats](#9-arm64-caveats)
10. [Recommended Ansible Variable Names](#10-recommended-ansible-variable-names)

---

## 1. Docker Image: registry:2 ARM64 Support

**Image:** `registry:2` (Docker Hub official)

The `registry:2` image is a **multi-arch manifest** supporting:
- `linux/amd64`
- `linux/arm64`  ← Raspberry Pi 4B+
- `linux/arm/v7`
- `linux/ppc64le`
- `linux/s390x`

From carpie.net (authoritative for this project):
> "The `registry` image supports ARM targets automatically, so we don't have to specify that here. When we pull the image from our Pi, it will detect the ARM architecture and pull down the correct one."

**Recommendation:** Use `registry:2` (pinned to major version). No architecture suffix needed — containerd/Docker auto-selects `linux/arm64` on RPi4.

Verify live:
```bash
docker buildx imagetools inspect registry:2
```

---

## 2. Kubernetes Manifests — Complete Structure

### Namespace (optional but recommended for isolation)

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: docker-registry
```

**CRITICAL NAMESPACE NOTE:** The htpasswd secret must exist in the SAME namespace as the Deployment. If deploying to a dedicated namespace, the secret must be recreated there. The existing `docker_registry` Ansible role creates the secret in `default` (no `--namespace` flag). Either:
- Option A: Deploy registry into `default` namespace (no namespace manifest needed)
- Option B: Deploy into `docker-registry` namespace AND recreate/move the secret there

### PersistentVolumeClaim (Longhorn)

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: docker-registry-pvc
  namespace: docker-registry   # or: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 10Gi
```

Notes:
- `ReadWriteOnce` is correct — registry has `replicas: 1`, Longhorn supports RWO
- `ReadWriteMany` is NOT needed (and requires NFS on Longhorn)
- Typical size: 10–20Gi depending on expected image count/size
- Longhorn default replica count is 3 (data is replicated across nodes)

### Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: docker-registry
  namespace: docker-registry   # or: default
  labels:
    app: docker-registry
spec:
  replicas: 1
  selector:
    matchLabels:
      app: docker-registry
  template:
    metadata:
      labels:
        app: docker-registry
    spec:
      containers:
      - name: docker-registry
        image: registry:2
        ports:
        - containerPort: 5000
        volumeMounts:
        - name: storage
          mountPath: /var/lib/registry
        - name: htpasswd
          mountPath: /auth
          readOnly: true
        env:
        - name: REGISTRY_AUTH
          value: htpasswd
        - name: REGISTRY_AUTH_HTPASSWD_REALM
          value: Docker Registry
        - name: REGISTRY_AUTH_HTPASSWD_PATH
          value: /auth/htpasswd
        - name: REGISTRY_STORAGE_DELETE_ENABLED
          value: "true"
      volumes:
      - name: storage
        persistentVolumeClaim:
          claimName: docker-registry-pvc
      - name: htpasswd
        secret:
          secretName: docker-registry-htpasswd
```

Important env vars:

| Env Var | Value | Purpose |
|---------|-------|---------|
| `REGISTRY_AUTH` | `htpasswd` | Enables htpasswd-based basic auth |
| `REGISTRY_AUTH_HTPASSWD_REALM` | `Docker Registry` | Shown in browser auth prompt |
| `REGISTRY_AUTH_HTPASSWD_PATH` | `/auth/htpasswd` | Path to credentials file in container |
| `REGISTRY_STORAGE_DELETE_ENABLED` | `"true"` | Allows image deletion (private registry) |

The secret key name matters: `--from-file /home/pi/htpasswd` creates key `htpasswd`. Mount at `/auth` → file becomes `/auth/htpasswd`. This matches `REGISTRY_AUTH_HTPASSWD_PATH`.

### Service (NodePort — for clusters without Traefik/ingress)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: docker-registry-service
  namespace: docker-registry   # or: default
spec:
  type: NodePort
  selector:
    app: docker-registry
  ports:
  - protocol: TCP
    port: 5000
    targetPort: 5000
    nodePort: 30500   # any free port in 30000–32767
```

**NodePort range:** 30000–32767. Port 30500 avoids conflict with common choices.

### Ingress (ONLY if using Traefik/cert-manager — NOT applicable for this cluster)

carpie.net uses Traefik IngressRoute + cert-manager Let's Encrypt:
```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: docker-registry-tls
  namespace: default
spec:
  secretName: docker-registry-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
  - docker.example.com
---
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: docker-registry-ingress-secure
spec:
  entryPoints:
    - websecure
  routes:
  - match: Host(`docker.example.com`)
    kind: Rule
    services:
    - name: docker-registry-service
      port: 5000
  tls:
    secretName: docker-registry-tls
```

**This cluster has Traefik DISABLED.** NodePort is the correct approach.

---

## 3. k3s registries.yaml — Official Format

**Source:** https://docs.k3s.io/installation/private-registry

File location: `/etc/rancher/k3s/registries.yaml` on **every node** (server AND all agents).

### Format for HTTP (insecure) registry with basic auth

```yaml
mirrors:
  "kate0.local:30500":
    endpoint:
      - "http://kate0.local:30500"
configs:
  "kate0.local:30500":
    auth:
      username: registry
      password: <plaintext-password>
```

Notes from official docs:
- `http://` in endpoint is required for insecure registries — defaults to HTTPS if omitted
- `configs` key must match `mirrors` key exactly (hostname:port)
- `auth` credentials are plaintext in this file — protect with `chmod 600`
- After changing, must restart `k3s` (server) or `k3s-agent` (agent nodes)

### Format for HTTPS with skip verify

```yaml
mirrors:
  "registry.example.com:5000":
    endpoint:
      - "https://registry.example.com:5000"
configs:
  "registry.example.com:5000":
    auth:
      username: username
      password: password
    tls:
      insecure_skip_verify: true
```

### Wildcard (for all registries — March 2024+)

Available since v1.26.15+k3s1, v1.27.12+k3s1, v1.28.8+k3s1, v1.29.3+k3s1:
```yaml
mirrors:
  "*":
    endpoint:
      - "https://registry.example.com:5000"
configs:
  "*":
    tls:
      insecure_skip_verify: true
```

### Mirror (pull-through cache for docker.io)

```yaml
mirrors:
  docker.io:
    endpoint:
      - "http://kate0.local:30500"
```

### Important caveats

- All nodes require the file — both server (`kate0.local`) and agents (`kate1.local`–`kate7.local`)
- Restart required: `systemctl restart k3s` (server) or `systemctl restart k3s-agent` (agents)
- Debug log: `/var/lib/rancher/k3s/agent/containerd/containerd.log` (default data-dir)
  - With custom `data-dir: /mnt/ssd/k3s`: `/mnt/ssd/k3s/agent/containerd/containerd.log`
- Image names in manifests must use the registry prefix: `kate0.local:30500/myimage:tag`
- The `registries.yaml` config key name must exactly match the registry address used in image references

---

## 4. htpasswd Secret Mounting

### Secret creation (carpie.net pattern)

```bash
htpasswd -Bc htpasswd registry
kubectl create secret generic docker-registry-htpasswd --from-file ./htpasswd
```

This creates a secret with key `htpasswd` (filename is the key).

### Ansible community.general.htpasswd module

```yaml
- name: Add htpasswd entry
  community.general.htpasswd:
    state: present
    name: registry
    password: '{{ docker_registry_password }}'
    path: /home/pi/htpasswd
    mode: "0640"
    crypt_scheme: bcrypt   # use bcrypt, not md5
```

Then:
```yaml
- name: Create htpasswd secret
  ansible.builtin.command:
    cmd: kubectl create secret generic docker-registry-htpasswd --from-file /home/pi/htpasswd -n {{ docker_registry_namespace }}
```

### Deployment volumeMount

```yaml
volumes:
- name: htpasswd
  secret:
    secretName: docker-registry-htpasswd
volumeMounts:
- name: htpasswd
  mountPath: /auth
  readOnly: true
```

File becomes: `/auth/htpasswd` (matches `REGISTRY_AUTH_HTPASSWD_PATH`).

---

## 5. Longhorn PVC for Registry Storage

### Standard PVC for registry

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: docker-registry-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 10Gi
```

### Deployment volume reference

```yaml
volumes:
- name: storage
  persistentVolumeClaim:
    claimName: docker-registry-pvc
volumeMounts:
- name: storage
  mountPath: /var/lib/registry
```

`/var/lib/registry` is the default storage path for the `registry:2` image.

### Sizing guidance

| Use case | Recommended size |
|----------|-----------------|
| Dev/home lab | 10Gi |
| Small team | 20–50Gi |
| Production | 100Gi+ |

Longhorn default replica count is 3 — actual disk usage per node ≈ PVC size × 3.

---

## 6. NodePort vs Ingress — Which to Use

| Approach | Requires | TLS | Auth via |
|----------|---------|-----|---------|
| NodePort (HTTP) | Nothing extra | No (insecure) | htpasswd in registry |
| NodePort + self-signed | cert generation | Optional | htpasswd |
| Traefik IngressRoute | cert-manager, Traefik, DNS, internet | Let's Encrypt | htpasswd |

**carpie.net recommendation:** Traefik IngressRoute + cert-manager + Let's Encrypt for internet-accessible, TLS-secured registry.

**This project:** Traefik is **disabled** (`disable: [traefik, servicelb]` in k3s config). NodePort over HTTP is the pragmatic approach for an internal/LAN cluster.

NodePort standard port choices:
- `30500` — common, avoids conflicts
- `32000` — used in some tutorials
- Any in range 30000–32767

---

## 7. TLS and Insecure HTTP Setup

### HTTP (insecure) — recommended for LAN-only clusters

No TLS config needed in the registry container. Set in `registries.yaml`:
```yaml
mirrors:
  "kate0.local:30500":
    endpoint:
      - "http://kate0.local:30500"
```

Docker clients (for `docker push`/`docker pull` from external machines) also need to be told about the insecure registry:
```json
// /etc/docker/daemon.json on client machine
{
  "insecure-registries": ["kate0.local:30500"]
}
```

### HTTPS with self-signed cert

Requires:
1. Generate self-signed cert (openssl)
2. Create k8s TLS secret
3. Configure registry container with cert paths
4. Distribute CA cert to all nodes and Docker clients

**Not recommended for this project.** HTTP over LAN is fine.

---

## 8. k3s-Specific Gotchas

### Custom data-dir changes log paths

This cluster uses `data-dir: /mnt/ssd/k3s`. Containerd logs are at:
- Default: `/var/lib/rancher/k3s/agent/containerd/containerd.log`
- This cluster: `/mnt/ssd/k3s/agent/containerd/containerd.log`

`registries.yaml` path is always `/etc/rancher/k3s/registries.yaml` regardless of data-dir.

### Restart requirement

After writing `registries.yaml`:
- Server node: `systemctl restart k3s`
- Agent nodes: `systemctl restart k3s-agent`

Containerd reads `registries.yaml` at startup only — runtime changes require restart.

### Default endpoint fallback

Containerd always tries the default endpoint (`https://<REGISTRY>/v2`) as a last resort. For a local HTTP registry, this means if `registries.yaml` isn't configured, containerd will try HTTPS and fail. The `http://` endpoint in `registries.yaml` must be present.

### Disable default endpoint (optional, for truly air-gapped)

k3s v1.26.13+k3s1+:
```yaml
# in /etc/rancher/k3s/config.yaml
disable-default-registry-endpoint: true
```

### Image name must include registry prefix

Pods that should pull from the local registry must use the full address:
```yaml
image: kate0.local:30500/myimage:latest
```

If you omit the registry prefix, k3s/containerd will pull from docker.io.

### registries.yaml must be on ALL nodes

The registry Pod may be scheduled on the leader (`kate0.local`), but ALL nodes need `registries.yaml` to pull from it — each agent node independently resolves image pulls.

---

## 9. ARM64 Caveats

### registry:2 on ARM64

No known issues. `registry:2` has native `linux/arm64` variant since at least v2.6.

From carpie.net:
> "The `registry` image supports ARM targets automatically"

### Apache2-utils htpasswd on ARM64

`apache2-utils` (for `htpasswd`) is available on Debian/Ubuntu ARM64 without issue.

### Python passlib on ARM64

`pip install passlib` is available on ARM64. Required by Ansible `community.general.htpasswd` module with bcrypt. Note: `passlib` itself requires `bcrypt` package for bcrypt hashing:
```bash
pip install passlib bcrypt
```

Or use `crypt_scheme: des_crypt` (weaker) to avoid bcrypt dependency.

---

## 10. Recommended Ansible Variable Names

| Variable | Default | Purpose |
|---------|---------|---------|
| `docker_registry_namespace` | `docker-registry` | K8s namespace |
| `docker_registry_image` | `registry:2` | Container image |
| `docker_registry_storage_class` | `longhorn` | StorageClass name |
| `docker_registry_storage_size` | `10Gi` | PVC capacity |
| `docker_registry_node_port` | `30500` | NodePort (30000–32767) |
| `docker_registry_hostname` | `kate0.local` | Registry hostname for image prefix |
| `docker_registry_secret_name` | `docker-registry-htpasswd` | htpasswd secret name |
| `docker_registry_username` | `registry` | htpasswd username |
| `docker_registry_password` | (vault) | htpasswd password — use ansible-vault |
| `docker_registry_htpasswd_path` | `/home/pi/htpasswd` | Temp file path on leader |

---

## Sources

| Document | URL |
|----------|-----|
| carpie.net — Installing Docker Registry on k3s | https://carpie.net/articles/installing-docker-registry-on-k3s |
| k3s Private Registry docs (official) | https://docs.k3s.io/installation/private-registry |
| Docker Hub registry:2 | https://hub.docker.com/_/registry |
