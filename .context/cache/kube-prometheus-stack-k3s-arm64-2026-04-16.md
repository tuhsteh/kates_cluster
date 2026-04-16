# kube-prometheus-stack on k3s / ARM64 — Research Cache

**Cache Date:** 2026-04-16
**Researched By:** @researcher
**Sources researched:**
- https://docs.k3s.io/reference/metrics
- https://docs.k3s.io/add-ons/helm
- https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack
- https://hodovi.cc/blog/configuring-kube-prometheus-stack-dashboards-and-alerts-for-k3s-compatibility/
- https://fabianlee.org/2022/07/02/prometheus-installing-kube-prometheus-stack-on-k3s-cluster/
- https://artifacthub.io/packages/helm/prometheus-community/kube-prometheus-stack
- https://github.com/k3s-io/helm-controller

---

## Table of Contents

1. [Chart Version](#1-chart-version)
2. [Deployment Method: HelmChart CRD vs kubernetes.core.helm](#2-deployment-method-helmchart-crd-vs-kubernetescorehelm)
3. [ARM64 Compatibility](#3-arm64-compatibility)
4. [k3s-Specific Scrape Configuration](#4-k3s-specific-scrape-configuration)
5. [Persistent Storage with Longhorn](#5-persistent-storage-with-longhorn)
6. [NodePort Access Configuration](#6-nodeport-access-configuration)
7. [Namespace](#7-namespace)
8. [Grafana Default Credentials](#8-grafana-default-credentials)
9. [Resource Requirements for RPi4 ARM64](#9-resource-requirements-for-rpi4-arm64)
10. [ARM64 / k3s Gotchas and Silent Failure Risks](#10-arm64--k3s-gotchas-and-silent-failure-risks)
11. [Complete Values YAML Reference](#11-complete-values-yaml-reference)
12. [Ansible Role Notes](#12-ansible-role-notes)

---

## 1. Chart Version

**Current latest stable:** `83.5.0` (released April 2026)
**Prior recent versions:** 83.4.2 (April 14), 83.4.1 (April 13), 83.4.0 (April 9)

**Bundled component versions (chart v83.x):**
| Component | Version |
|-----------|---------|
| Prometheus Operator | v0.90.x |
| Prometheus | v2.53.x+ |
| Grafana | 11.x |
| AlertManager | v0.27.x |
| kube-state-metrics | v2.13.x |
| prometheus-node-exporter | v1.8.x |

**Source:** https://artifacthub.io/packages/helm/prometheus-community/kube-prometheus-stack

### CRD Note
CRDs are NOT managed by Helm's normal lifecycle. They must be manually applied or updated on major chart version upgrades. This is a standard gotcha on upgrades.

---

## 2. Deployment Method: HelmChart CRD vs kubernetes.core.helm

### k3s HelmChart CRD

**How it works:** Write a `HelmChart` manifest (and optionally a `HelmChartConfig`) to the cluster. k3s's built-in helm-controller handles the actual Helm install. The HelmChart resource must live in `kube-system` namespace.

**Key fields:**
```yaml
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: kube-prometheus-stack
  namespace: kube-system
spec:
  chart: kube-prometheus-stack
  repo: https://prometheus-community.github.io/helm-charts
  version: "83.5.0"
  targetNamespace: monitoring
  createNamespace: true
  valuesContent: |-    # inline YAML values (size-limited)
  valuesSecrets:        # reference to Secret for large/confidential values
    - name: prometheus-values
      keys:
        - values.yaml
```

**⚠️ CRITICAL LIMITATION — valuesContent size:**
The `spec.valuesContent` field in the k3s HelmChart CRD is **limited to 4096 bytes** in some k3s versions (validated by the admission webhook). For kube-prometheus-stack, the required values YAML (with all k3s-specific overrides) will easily exceed 4096 bytes.

**Workaround:** Use `spec.valuesSecrets` to reference a Kubernetes `Secret` containing the values. The Secret must be in `kube-system` namespace. This adds complexity: the Ansible role must create the Secret AND the HelmChart CRD, and must sequence them correctly (Secret first).

**Pros of HelmChart CRD:**
- Consistent with existing Longhorn deployment pattern in this repo
- Self-reconciling (k3s helm-controller watches and re-applies)
- No Helm binary required on Ansible control node

**Cons of HelmChart CRD for kube-prometheus-stack:**
- `valuesContent` 4096-byte limit requires workaround (Secret)
- Debugging is harder (logs in a helm-installer Job pod in `kube-system`)
- Less visibility into dry-run / diff
- Cannot use `helm diff` for change previews

### kubernetes.core.helm Ansible Module

**How it works:** Runs `helm` CLI on the Ansible control node using the cluster kubeconfig. Fully standard Helm behavior.

**Requirements:**
- `helm` binary installed on Ansible control node
- Cluster kubeconfig accessible (k3s kubeconfig at `/etc/rancher/k3s/k3s.yaml` on server node; must be copied to control node or use `delegate_to`)
- `kubernetes.core` collection installed: `ansible-galaxy collection install kubernetes.core`

**Typical task:**
```yaml
- name: Deploy kube-prometheus-stack
  kubernetes.core.helm:
    name: kube-prometheus-stack
    chart_ref: prometheus-community/kube-prometheus-stack
    chart_version: "83.5.0"
    release_namespace: monitoring
    create_namespace: true
    values: "{{ lookup('template', 'values.yaml.j2') | from_yaml }}"
    kubeconfig: /etc/rancher/k3s/k3s.yaml
    state: present
    wait: true
    wait_timeout: 600
```

**Pros:**
- No size limit on values
- Full Helm feature set (wait, dry-run, atomic, etc.)
- Simpler Ansible task structure — no need for a separate Secret manifest
- Consistent with how Helm is typically managed in complex deployments
- Standard debugging via `helm status`, `helm history`

**Cons:**
- Requires Helm binary on control node
- Requires k3s kubeconfig accessible from control node
- Less "self-healing" than k3s helm-controller (only re-runs when Ansible runs)

### **Recommendation for this project**

**Use `kubernetes.core.helm`** for kube-prometheus-stack.

Rationale:
1. The k3s-specific values YAML will far exceed 4096 bytes
2. The valuesSecrets workaround adds complexity without benefit
3. kube-prometheus-stack is complex enough that Ansible's control-plane visibility (wait, atomic, explicit diff) is valuable
4. The Longhorn precedent used HelmChart CRD because Longhorn's values are small; kube-prometheus-stack is an order of magnitude more complex
5. The Ansible control node (wherever `stage.yaml` runs from) already has `kubectl` — adding `helm` is a small additional step

**Pre-requisite Ansible task for kubernetes.core.helm:**
```yaml
- name: Install helm (if not present)
  become: true
  ansible.builtin.shell: |
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  args:
    creates: /usr/local/bin/helm

- name: Add prometheus-community Helm repo
  kubernetes.core.helm_repository:
    name: prometheus-community
    repo_url: https://prometheus-community.github.io/helm-charts
    state: present
```

---

## 3. ARM64 Compatibility

**✅ All components have native ARM64 (linux/arm64) multi-arch images as of chart v40+ (2023+).**

| Component | Image Registry | ARM64 Support |
|-----------|---------------|---------------|
| Prometheus | `quay.io/prometheus/prometheus` | ✅ v2.41+ |
| AlertManager | `quay.io/prometheus/alertmanager` | ✅ all current |
| Grafana | `docker.io/grafana/grafana` | ✅ v10+ (v11 in chart 83.x) |
| Prometheus Operator | `quay.io/prometheus-operator/prometheus-operator` | ✅ v0.67+ |
| kube-state-metrics | `registry.k8s.io/kube-state-metrics/kube-state-metrics` | ✅ v2.10+ |
| node-exporter | `quay.io/prometheus/node-exporter` | ✅ v1.7+ |
| kube-webhook-certgen | `registry.k8s.io/ingress-nginx/kube-webhook-certgen` | ✅ |

**No image tag overrides are needed for ARM64.** Kubernetes node-affinity and container runtime automatically pull the correct architecture variant from the multi-arch manifest list.

**Verification command:**
```bash
docker manifest inspect quay.io/prometheus/prometheus:v2.53.0 | grep architecture
```

---

## 4. k3s-Specific Scrape Configuration

### ⚠️ Key Architectural Fact

**k3s runs all Kubernetes components (API server, controller-manager, scheduler, and kubelet) in a SINGLE process.** Because Kubernetes uses a single Prometheus metric registry per process, **all component metrics are available at every k3s metrics endpoint** — including the kubelet endpoint.

This means:
- Scraping `kubeControllerManager` separately → **duplicate metrics**
- Scraping `kubeScheduler` separately → **duplicate metrics**
- Scraping `kubeApiServer` separately in addition to kubelet → **duplicate metrics**
- k3s does NOT run `kube-proxy` at all — it uses Flannel/kube-router instead

**Source:** https://docs.k3s.io/reference/metrics

### Default ServiceMonitors to DISABLE

```yaml
kubeControllerManager:
  enabled: false    # k3s runs this in the k3s process, not as a separate pod

kubeScheduler:
  enabled: false    # same — embedded in k3s process

kubeProxy:
  enabled: false    # k3s does NOT run kube-proxy; uses Flannel

kubeEtcd:
  enabled: false    # k3s uses SQLite by default, not etcd
                    # (embedded etcd if HA mode, but still not scrapeable via default ServiceMonitor)

kubeApiServer:
  enabled: false    # metrics are duplicated via kubelet endpoint; disable to avoid duplication
                    # (OR keep enabled — it points to 6443 which IS valid, but duplicates kubelet)
```

### Enable kubelet (the primary scrape target)

```yaml
kubelet:
  enabled: true
  serviceMonitor:
    https: true
    cAdvisor: true
    probesMetrics: true
    resource: true
    resourcePath: /metrics/resource
    relabelings: []
    metricRelabelings: []
```

### k3s Supervisor Metrics (Optional — not required for basic monitoring)

If k3s is started with `supervisor-metrics: true` in `/etc/rancher/k3s/config.yaml`, k3s-specific metrics (cluster management, etcd snapshot, load balancer state) are exposed on port `6443` at `/metrics`. These require authentication.

```bash
kubectl get --server https://NODENAME:6443 --raw /metrics
```

This endpoint provides:
- K3s cluster management metrics (`k3s_*` prefix)
- All embedded component metrics (apiserver, scheduler, etc.)

**To scrape k3s supervisor metrics** (optional enhancement):
```yaml
prometheus:
  prometheusSpec:
    additionalScrapeConfigs:
      - job_name: 'k3s-supervisor'
        scheme: https
        tls_config:
          insecure_skip_verify: true
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
        metrics_path: /metrics
        static_configs:
          - targets:
              - '192.168.x.1:6443'   # server node IP
```

### Alternative: Expose Individual Components

If you want separate metrics for controller-manager/scheduler (e.g., for standard dashboards), configure k3s `/etc/rancher/k3s/config.yaml`:
```yaml
kube-controller-manager-arg:
  - "bind-address=0.0.0.0"
kube-scheduler-arg:
  - "bind-address=0.0.0.0"
kube-proxy-arg:
  - "metrics-bind-address=0.0.0.0"
etcd-expose-metrics: true
```

Then in kube-prometheus-stack values:
```yaml
kubeControllerManager:
  enabled: true
  endpoints: ['<server-node-ip>']
  service:
    enabled: true
    port: 10252
    targetPort: 10252
  serviceMonitor:
    enabled: true
    https: false

kubeScheduler:
  enabled: true
  endpoints: ['<server-node-ip>']
  service:
    enabled: true
    port: 10251
    targetPort: 10251
  serviceMonitor:
    enabled: true
    https: false

kubeProxy:
  enabled: true
  endpoints: ['<server-node-ip>']
  service:
    enabled: true
    port: 10249
    targetPort: 10249
```

**⚠️ Note:** Endpoints must be IPs (not hostnames). Loopback address (127.0.0.1) is rejected.

### Default Rules and Dashboards

**CRITICAL:** The default rules and Grafana dashboards assume standard kubeadm Kubernetes. They WILL produce broken dashboards and false alerts on k3s.

```yaml
grafana:
  defaultDashboardsEnabled: false   # disable — these assume standard k8s

defaultRules:
  create: false                      # disable — assumes kubeadm/etcd setup
  # OR selectively disable only the rules that don't apply:
  rules:
    etcd: false
    kubeScheduler: false
```

**Source:** https://hodovi.cc/blog/configuring-kube-prometheus-stack-dashboards-and-alerts-for-k3s-compatibility/

### ServiceMonitor Discovery

```yaml
prometheus:
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false  # CRITICAL
    podMonitorSelectorNilUsesHelmValues: false        # CRITICAL
    # Without these, Prometheus only scrapes ServiceMonitors with helm release label
    # This would cause custom ServiceMonitors (k3s components) to be ignored
```

---

## 5. Persistent Storage with Longhorn

### Prometheus Storage

```yaml
prometheus:
  prometheusSpec:
    retention: 15d              # 15 days for 8-node cluster
    retentionSize: "15GB"       # hard cap to protect against runaway metric ingestion
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: longhorn
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 20Gi    # 20Gi is reasonable for 8 nodes, 15d, standard metrics
```

**Storage sizing guidance:**
- 8 nodes, default scrape interval (30s), no custom ServiceMonitors: ~3–5 GB/week
- 20Gi with 15d retention: safe for standard cluster metrics
- Reduce to 10Gi or 7d retention if Prometheus memory usage is a concern

### AlertManager Storage

```yaml
alertmanager:
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: longhorn
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 1Gi    # AlertManager needs very little persistent storage
```

### Grafana Storage (Optional)

```yaml
grafana:
  persistence:
    enabled: true
    storageClassName: longhorn
    accessModes:
      - ReadWriteOnce
    size: 1Gi
```
Without Grafana persistence, custom dashboards and plugins are lost on pod restart. Enable for production use.

---

## 6. NodePort Access Configuration

Since Traefik is disabled and NodePort is the only access method:

```yaml
grafana:
  service:
    type: NodePort
    nodePort: 30300     # Access at http://<any-node-ip>:30300

prometheus:
  service:
    type: NodePort
    nodePort: 30090     # Access at http://<any-node-ip>:30090

alertmanager:
  alertmanagerSpec: {}
alertmanager:
  service:
    type: NodePort
    nodePort: 30093     # Access at http://<any-node-ip>:30093
```

**Port range note:** NodePorts must be in range 30000–32767 (k3s default).

**⚠️ Structure note for Prometheus:** The correct path in newer chart versions is:
```yaml
prometheus:
  service:
    type: NodePort
    nodePort: 30090
```
NOT `prometheus.prometheusSpec.service` — the service is at `prometheus.service`.

---

## 7. Namespace

**Use `monitoring` namespace.** No conflicts with k3s defaults.

k3s default namespaces:
- `kube-system`: CoreDNS, metrics-server, helm-controller, Traefik (disabled in this cluster), local-path-provisioner
- `kube-public`: read-only ClusterInfo
- `kube-node-lease`: node leases

**`monitoring` namespace is clean** — k3s does not create anything there by default.

**Note:** The k3s HelmChart CRD itself must live in `kube-system`, but its `targetNamespace: monitoring` is fine. For `kubernetes.core.helm`, deploy directly to `monitoring`.

---

## 8. Grafana Default Credentials

**Default admin username:** `admin`
**Default admin password:** **Auto-generated** — stored in a Kubernetes Secret named `<release-name>-grafana`

To retrieve the auto-generated password:
```bash
kubectl get secret kube-prometheus-stack-grafana -n monitoring \
  -o jsonpath="{.data.admin-password}" | base64 --decode
```

### Setting Password via Helm Values

```yaml
grafana:
  adminPassword: "your-password-here"   # Set explicitly; use Ansible vault
```

### Using an Existing Secret (Ansible Vault Pattern)

```yaml
grafana:
  admin:
    existingSecret: grafana-admin-secret
    userKey: admin-user
    passwordKey: admin-password
```

Pre-create the secret:
```yaml
# In Ansible: use ansible vault for password
- name: Create Grafana admin secret
  kubernetes.core.k8s:
    definition:
      apiVersion: v1
      kind: Secret
      metadata:
        name: grafana-admin-secret
        namespace: monitoring
      stringData:
        admin-user: admin
        admin-password: "{{ grafana_admin_password }}"   # from vault
```

**Recommendation:** Set `grafana.adminPassword` in Helm values as an Ansible variable sourced from vault. Default to `"prom-operator"` with a comment to override via `--extra-vars` or vault.

---

## 9. Resource Requirements for RPi4 ARM64

### Per-component Resource Recommendations (8-node cluster, RPi4 4–8GB)

```yaml
prometheus:
  prometheusSpec:
    resources:
      requests:
        cpu: 200m
        memory: 400Mi
      limits:
        cpu: 500m
        memory: 1000Mi     # Bump to 1500Mi on 8GB nodes if needed

alertmanager:
  alertmanagerSpec:
    resources:
      requests:
        cpu: 25m
        memory: 64Mi
      limits:
        cpu: 100m
        memory: 256Mi

grafana:
  resources:
    requests:
      cpu: 50m
      memory: 128Mi
    limits:
      cpu: 200m
      memory: 256Mi

prometheus-node-exporter:           # DaemonSet — runs on ALL 8 nodes
  resources:
    requests:
      cpu: 25m
      memory: 32Mi
    limits:
      cpu: 100m
      memory: 64Mi

kube-state-metrics:
  resources:
    requests:
      cpu: 30m
      memory: 64Mi
    limits:
      cpu: 100m
      memory: 128Mi

prometheusOperator:
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 100m
      memory: 128Mi
```

### Total Stack Memory Footprint (approximate, 8-node cluster)
| Component | Memory Usage |
|-----------|-------------|
| Prometheus | 400–900 Mi |
| Grafana | 128–256 Mi |
| AlertManager | 64–128 Mi |
| kube-state-metrics | 64–128 Mi |
| Prometheus Operator | 64–128 Mi |
| node-exporter × 8 | 256 Mi total |
| **TOTAL** | **~1–1.8 Gi** |

**RPi4 with 4GB RAM:** Safe to run the stack — leave 2+ GB for the OS and other workloads.
**RPi4 with 8GB RAM:** Comfortable with room to grow.

### OOM Risk Factors on ARM64
- High metric cardinality (custom ServiceMonitors, many pods)
- Long retention (>30d) with high ingest rate
- Default limits from the chart are too high for RPi4 (e.g., default Prometheus limit may be 4Gi) — always override

### Reduce Prometheus Memory Usage
```yaml
prometheus:
  prometheusSpec:
    retention: 7d                    # reduce if memory-constrained
    walCompression: true             # reduces WAL disk and memory usage
    query:
      maxConcurrency: 4              # limit concurrent queries
    enableFeatures:
      - memory-snapshot-on-shutdown  # faster restarts; less memory on startup
```

---

## 10. ARM64 / k3s Gotchas and Silent Failure Risks

### ⚠️ GOTCHA 1: Admission Webhooks timeout on ARM64 (HIGH RISK)

**Symptom:** Pods hang during deployment; `kubectl apply` of PrometheusRule objects times out.
**Cause:** The `kube-webhook-certgen` job or the prometheus-operator admission webhook pod is slow to start on ARM64 RPi4.
**Fix:** Disable admission webhooks:

```yaml
prometheusOperator:
  admissionWebhooks:
    enabled: false
    patch:
      enabled: false
```

**Note:** This disables PrometheusRule validation. Invalid rules will silently fail at the Prometheus level instead of at apply-time. For a homelab/edge cluster, this is acceptable.

### ⚠️ GOTCHA 2: Wrong values key for node-exporter (SILENT FAILURE)

`nodeExporter` key was renamed to `prometheus-node-exporter` in chart v40+. Using the old key silently ignores your overrides.

**Correct (chart v40+, current):**
```yaml
prometheus-node-exporter:
  resources: ...
  tolerations: ...
```

**Wrong (silently ignored in chart v83.x):**
```yaml
nodeExporter:           # ← DOES NOTHING in current versions
  resources: ...
```

### ⚠️ GOTCHA 3: kube-state-metrics subchart key naming

The subchart key uses dashes (to match the Helm chart name):
```yaml
kube-state-metrics:    # correct
  resources: ...
```
NOT:
```yaml
kubeStateMetrics:      # DOES NOTHING — wrong key
  resources: ...
```

### ⚠️ GOTCHA 4: serviceMonitorSelectorNilUsesHelmValues defaults to true

Default behavior: Prometheus only scrapes ServiceMonitors with the `release: <helm-release-name>` label.
Without setting this to `false`, custom ServiceMonitors (e.g., for Longhorn, other apps) will be silently ignored.

```yaml
prometheus:
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
```

### ⚠️ GOTCHA 5: Default dashboards will show blank panels on k3s

The bundled Grafana dashboards for Kubernetes components assume standard kubeadm setup with separate metrics endpoints. On k3s, panels for `kubeControllerManager`, `kubeScheduler`, and `kubeEtcd` will be blank or show "No Data."

**Fix:** Set `grafana.defaultDashboardsEnabled: false` and `defaultRules.create: false`. Install k3s-compatible dashboards manually from Grafana's dashboard gallery (ID 13770 is a popular k3s-specific dashboard).

### ⚠️ GOTCHA 6: kubeProxy is absent in k3s

k3s does NOT deploy kube-proxy. The `kubeProxy` ServiceMonitor will permanently show "0 targets" and may trigger alerts. Set `kubeProxy.enabled: false`.

### ⚠️ GOTCHA 7: etcd metrics not available in default k3s

k3s uses SQLite by default (not etcd), and the k3s-embedded etcd (HA mode) is not scraped by the standard `kubeEtcd` ServiceMonitor. Set `kubeEtcd.enabled: false` to prevent permanent scrape errors.

### ⚠️ GOTCHA 8: k3s custom data directory does not affect Prometheus deployment

The k3s data directory at `/mnt/ssd/k3s` (vs default `/var/lib/rancher/k3s`) does NOT affect kube-prometheus-stack deployment. The kubeconfig is still at `/etc/rancher/k3s/k3s.yaml` (this path is hardcoded to `/etc/rancher/k3s/`, independent of `data-dir`).

### ⚠️ GOTCHA 9: Prometheus startup on ARM64 can be slow (OOMKill risk)

On first startup, Prometheus loads its WAL (Write-Ahead Log). On RPi4, this can take several minutes and temporarily spike memory. Set the memory limit higher than the steady-state request, and increase helm install wait timeout.

```yaml
kubernetes.core.helm:
  wait: true
  wait_timeout: 600    # 10 minutes; ARM64 RPi4 is slower than x86
```

### ⚠️ GOTCHA 10: node-exporter needs hostPID and hostNetwork

node-exporter requires `hostPID: true` and `hostNetwork: true` to gather node-level metrics. The chart defaults to these correctly, but if you have a restrictive PodSecurityPolicy or OPA policy, these may be blocked.

---

## 11. Complete Values YAML Reference

This is a comprehensive `values.yaml` for kube-prometheus-stack on k3s ARM64 RPi4 with Longhorn storage, NodePort access, no Traefik:

```yaml
# kube-prometheus-stack values for k3s ARM64 (Raspberry Pi 4)
# Chart version: 83.x
# Cluster: 8-node RPi4, k3s, Longhorn storage, Traefik disabled

## ──────────────────────────────────────────────────────────────
## Global settings
## ──────────────────────────────────────────────────────────────

## CRITICAL: disable admission webhooks to avoid ARM64 timeout issues
prometheusOperator:
  admissionWebhooks:
    enabled: false
    patch:
      enabled: false
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 100m
      memory: 128Mi

## ──────────────────────────────────────────────────────────────
## Default rules and dashboards — DISABLE for k3s
## ──────────────────────────────────────────────────────────────
defaultRules:
  create: false          # k3s-incompatible; produces false alerts for etcd/scheduler
  rules:
    etcd: false          # k3s uses SQLite, not etcd

grafana:
  defaultDashboardsEnabled: false  # default dashboards assume kubeadm, not k3s

## ──────────────────────────────────────────────────────────────
## k3s component monitors — DISABLE to prevent scrape errors
## k3s runs all these components in a single process;
## metrics are available via kubelet without separate scrapes.
## ──────────────────────────────────────────────────────────────
kubeApiServer:
  enabled: false          # duplicates kubelet metrics

kubeControllerManager:
  enabled: false          # embedded in k3s process

kubeScheduler:
  enabled: false          # embedded in k3s process

kubeProxy:
  enabled: false          # k3s does NOT run kube-proxy

kubeEtcd:
  enabled: false          # k3s uses SQLite; etcd metrics not available

## ──────────────────────────────────────────────────────────────
## Kubelet — PRIMARY scrape target for all k3s metrics
## ──────────────────────────────────────────────────────────────
kubelet:
  enabled: true
  serviceMonitor:
    https: true
    cAdvisor: true
    resource: true
    probesMetrics: true

## ──────────────────────────────────────────────────────────────
## Prometheus
## ──────────────────────────────────────────────────────────────
prometheus:
  service:
    type: NodePort
    nodePort: 30090

  prometheusSpec:
    ## CRITICAL: allow custom ServiceMonitors from any namespace
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false

    retention: 15d
    retentionSize: "15GB"
    walCompression: true

    resources:
      requests:
        cpu: 200m
        memory: 400Mi
      limits:
        cpu: 500m
        memory: 1000Mi

    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: longhorn
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 20Gi

## ──────────────────────────────────────────────────────────────
## AlertManager
## ──────────────────────────────────────────────────────────────
alertmanager:
  service:
    type: NodePort
    nodePort: 30093

  alertmanagerSpec:
    resources:
      requests:
        cpu: 25m
        memory: 64Mi
      limits:
        cpu: 100m
        memory: 256Mi

    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: longhorn
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 1Gi

## ──────────────────────────────────────────────────────────────
## Grafana
## ──────────────────────────────────────────────────────────────
grafana:
  enabled: true

  adminPassword: "prom-operator"   # OVERRIDE via Ansible vault

  service:
    type: NodePort
    nodePort: 30300

  persistence:
    enabled: true
    storageClassName: longhorn
    accessModes:
      - ReadWriteOnce
    size: 1Gi

  resources:
    requests:
      cpu: 50m
      memory: 128Mi
    limits:
      cpu: 200m
      memory: 256Mi

## ──────────────────────────────────────────────────────────────
## Node Exporter — DaemonSet on all 8 nodes
## NOTE: key is "prometheus-node-exporter" (NOT "nodeExporter")
## ──────────────────────────────────────────────────────────────
prometheus-node-exporter:
  enabled: true
  resources:
    requests:
      cpu: 25m
      memory: 32Mi
    limits:
      cpu: 100m
      memory: 64Mi

## ──────────────────────────────────────────────────────────────
## kube-state-metrics
## NOTE: key is "kube-state-metrics" (NOT "kubeStateMetrics")
## ──────────────────────────────────────────────────────────────
kube-state-metrics:
  enabled: true
  resources:
    requests:
      cpu: 30m
      memory: 64Mi
    limits:
      cpu: 100m
      memory: 128Mi
```

---

## 12. Ansible Role Notes

### Role Structure

```
roles/prometheus/
├── defaults/
│   └── main.yaml        # chart version, nodeports, storage size, namespace
├── tasks/
│   └── main.yaml        # helm repo add → helm install tasks
├── templates/
│   └── values.yaml.j2   # Jinja2 template for helm values
└── README.md
```

### key defaults

```yaml
# roles/prometheus/defaults/main.yaml
prometheus_namespace: monitoring
prometheus_chart_version: "83.5.0"
prometheus_chart_repo: "https://prometheus-community.github.io/helm-charts"
prometheus_release_name: kube-prometheus-stack

prometheus_nodeport: 30090
grafana_nodeport: 30300
alertmanager_nodeport: 30093

prometheus_storage_size: 20Gi
prometheus_retention: 15d
prometheus_storage_class: longhorn

grafana_admin_password: "prom-operator"   # OVERRIDE via vault
```

### Helm prereq tasks

The role must install `helm` on the play's `become` host (the server/leader node) OR on the Ansible control machine. Since `kubernetes.core.helm` runs on the control node (where Ansible executes), the control node needs Helm.

If running from the Ansible control node directly with a kubeconfig:
```yaml
- name: Install helm binary (Ansible control node)
  ansible.builtin.shell:
    cmd: curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    creates: /usr/local/bin/helm
```

If delegating to the k3s server node (alternative pattern):
```yaml
- name: Deploy kube-prometheus-stack via helm on server
  kubernetes.core.helm:
    kubeconfig: /etc/rancher/k3s/k3s.yaml
    ...
  # delegate_to: "{{ groups['stage_leader'][0] }}"   # if running from separate control node
```

### FQCN note

All tasks must use FQCN module names (`kubernetes.core.helm`, `kubernetes.core.helm_repository`) to pass `ansible-lint`.

---

## Sources

| Source | URL | Date |
|--------|-----|------|
| k3s metrics docs | https://docs.k3s.io/reference/metrics | 2026-04-16 |
| k3s helm add-ons docs | https://docs.k3s.io/add-ons/helm | 2026-04-16 |
| Artifact Hub (chart version) | https://artifacthub.io/packages/helm/prometheus-community/kube-prometheus-stack | 2026-04-16 |
| GitHub helm-charts | https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack | 2026-04-16 |
| k3s-specific dashboard config | https://hodovi.cc/blog/configuring-kube-prometheus-stack-dashboards-and-alerts-for-k3s-compatibility/ | 2026-04-16 |
| k3s cluster Prometheus install | https://fabianlee.org/2022/07/02/prometheus-installing-kube-prometheus-stack-on-k3s-cluster/ | 2026-04-16 |
