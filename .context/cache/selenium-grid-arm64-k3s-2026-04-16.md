# Selenium Grid 4 on ARM64 k3s — Research Cache

**Research Date:** 2026-04-16
**Researched By:** @researcher
**Cache Expires:** 2026-04-19 (3-day TTL)
**Scope:** Selenium Grid 4 deployment on an 8-node Raspberry Pi 4B (4GB RAM) k3s cluster for offloading TestNG/RemoteWebDriver browser tests. Target: "a few dozen" Chromium nodes.

---

## Table of Contents

1. [ARM64 Image Support (CRITICAL GATE)](#1-arm64-image-support-critical-gate)
2. [Helm Chart](#2-helm-chart)
3. [Resource Requirements (ARM64 / Pi 4B)](#3-resource-requirements-arm64--pi-4b)
4. [External Access / TestNG Integration](#4-external-access--testng-integration)
5. [k3s-Specific Considerations](#5-k3s-specific-considerations)
6. [Source Documentation](#6-source-documentation)

---

## 1. ARM64 Image Support (CRITICAL GATE)

### ✅ STATUS: ARM64 IS FULLY SUPPORTED (from Selenium 4.21.0+)

### Background — seleniarm is deprecated

The `seleniarm/*` Docker Hub namespace was a community project that provided ARM64 images when the official `selenium/*` images were amd64-only. As of **May 2024 (Selenium 4.21.0)**, the `selenium/*` images became official multi-arch and `seleniarm/*` was deprecated. **Do not use `seleniarm/*` for new deployments.**

### Official Multi-Arch Image Matrix

| Image | AMD64 | ARM64 (aarch64) | Notes |
|-------|:-----:|:---------------:|-------|
| `selenium/hub` | ✅ | ✅ | Multi-arch from 4.21.0+ |
| `selenium/node-chromium` | ✅ | ✅ | Use this for ARM64 — **NOT node-chrome** |
| `selenium/node-firefox` | ✅ | ✅ | Firefox Nightly on ARM64 |
| `selenium/standalone-chromium` | ✅ | ✅ | For standalone mode |
| `selenium/node-chrome` | ✅ | ❌ | Google Chrome has no official ARM64 Linux binary |
| `selenium/node-edge` | ✅ | ❌ | Microsoft Edge has no official ARM64 Linux binary |
| `selenium/distributor` | ✅ | ✅ | Full isolated mode component |
| `selenium/router` | ✅ | ✅ | Full isolated mode component |
| `selenium/event-bus` | ✅ | ✅ | Full isolated mode component |
| `selenium/sessions` | ✅ | ✅ | Full isolated mode component |
| `selenium/session-queue` | ✅ | ✅ | Full isolated mode component |

**Source:** Official README confirmation — https://github.com/SeleniumHQ/docker-selenium/blob/trunk/README.md (section "Experimental Multi-Arch amd64/aarch64/armhf Images")

### Latest Stable Version

- **Selenium Grid / Docker image tag:** `4.43.0-20260404`
- **Image pull example (Docker auto-selects arm64):**
  ```bash
  docker pull selenium/hub:4.43.0-20260404
  docker pull selenium/node-chromium:4.43.0-20260404
  ```
- No architecture suffix needed in the tag — Docker manifest resolution handles this automatically on arm64 hosts.

### Critical ARM64 Rule

> **Always use `node-chromium`, never `node-chrome`, on ARM64.**
> Chrome for Linux ARM64 does not exist. Using `node-chrome` on ARM64 will either fail to pull or fail to start the browser process.

---

## 2. Helm Chart

### Chart Identity

| Field | Value |
|-------|-------|
| Chart name | `selenium-grid` |
| Helm repo alias | `docker-selenium` |
| Helm repo URL | `https://www.selenium.dev/docker-selenium` |
| ArtifactHub page | https://artifacthub.io/packages/helm/selenium-grid/selenium-grid |
| Latest stable version | `0.27.0` |
| Nightly version (unstable) | `1.0.0-nightly` |
| Maintained by | SeleniumHQ (official) |
| GitHub source | https://github.com/SeleniumHQ/docker-selenium/tree/trunk/charts/selenium-grid |

### Installing the Chart

```bash
helm repo add docker-selenium https://www.selenium.dev/docker-selenium
helm repo update
# Pin to stable version
helm install selenium-grid docker-selenium/selenium-grid --version 0.27.0 \
  --namespace selenium --create-namespace \
  --values my-values.yaml
```

### KEDA Autoscaling

The chart ships with **native KEDA integration** for queue-driven scaling of browser nodes. Two scaling types are supported:

- `job` (default) — spins up a new pod per queued session request; best for clean isolation
- `deployment` — scales existing Deployment replicas up/down

**Selenium ships patched KEDA images** with a custom Selenium Grid scaler:

```
selenium/keda:2.15.1-selenium-grid-20240907
selenium/keda-metrics-apiserver:2.15.1-selenium-grid-20240907
selenium/keda-admission-webhooks:2.15.1-selenium-grid-20240907
```

The chart installs these automatically when `autoscaling.enabled: true`.

### Key values.yaml Reference for This Cluster

```yaml
# ----------------------------------------------------------------
# Selenium Grid 4 — values for ARM64 k3s / Raspberry Pi 4B cluster
# ----------------------------------------------------------------

# Expose the hub/router via NodePort for LAN access
isolateComponents: false   # Use combined hub mode (simpler)

hub:
  serviceType: NodePort
  nodePort: 30444          # Access: http://<node-ip>:30444/

# Global image tag override (ARM64 multi-arch image)
global:
  seleniumGrid:
    imageTag: "4.43.0-20260404"
    # imageRegistry: docker.io  # default

# Chromium node configuration (ARM64-compatible)
chromiumNode:
  enabled: true
  replicas: 1              # baseline; KEDA will scale this
  image:
    # repository: selenium/node-chromium  # default; uncomment only to override
    tag: "4.43.0-20260404"
  # Sessions per node pod (how many parallel tabs/windows)
  # Lower this on Pi 4B to conserve memory
  maxSessions: 1

  resources:
    requests:
      cpu: "500m"
      memory: "768Mi"
    limits:
      cpu: "1500m"
      memory: "1280Mi"

  # Chromium needs /dev/shm enlarged; chart handles this with dshmVolumeSizeLimit
  dshmVolumeSizeLimit: 1Gi

  # Per-node KEDA scaling overrides
  scaledOptions:
    minReplicaCount: 0      # Scale to zero when idle
    maxReplicaCount: 20     # Cluster max (8 Pi × 2 nodes = 16 safe; 20 is burst)
    pollingInterval: 20

# KEDA autoscaling — queue-driven scaling
autoscaling:
  enabled: true
  scalingType: deployment   # 'deployment' recommended for persistent grids; 'job' for CI
  scaledOptions:
    minReplicaCount: 0
    maxReplicaCount: 20
    pollingInterval: 20

# Disable unused browser types
firefoxNode:
  enabled: false
edgeNode:
  enabled: false
chromeNode:
  enabled: false   # chromeNode = Google Chrome, not supported on ARM64; use chromiumNode

# Video recording — disable to save resources on Pi
videoRecorder:
  enabled: false
```

### Image Override for Explicit ARM64 (if needed)

If Docker doesn't auto-select ARM64 in your environment, you can force the platform:
```yaml
chromiumNode:
  image:
    repository: selenium/node-chromium
    tag: "4.43.0-20260404"
    pullPolicy: IfNotPresent
```
Or with an explicit platform flag via `docker pull --platform linux/arm64 selenium/node-chromium:4.43.0-20260404`.

### Isolated Components (Full Grid) — NodePort for Router

If using `isolateComponents: true` (Router, Distributor, EventBus, SessionMap separate):
```yaml
isolateComponents: true
components:
  router:
    serviceType: NodePort
    nodePort: 30444
```

### Chart README full reference
https://github.com/SeleniumHQ/docker-selenium/blob/trunk/charts/selenium-grid/README.md

---

## 3. Resource Requirements (ARM64 / Pi 4B)

### Per Chromium Node Pod

| Resource | Request | Limit | Notes |
|----------|---------|-------|-------|
| CPU | 500m | 1500m | Chromium spikes heavily on JS-heavy pages |
| Memory | 768Mi | 1280Mi | Headless Chromium: 300–600 MB steady-state |
| `/dev/shm` | 1Gi | 1Gi | tmpfs mount; required to prevent crashes (`--shm-size=2g` equivalent) |

### Practical Chromium Nodes per Pi 4B (4GB RAM)

| Available RAM after OS + k3s (~700MB) | ~3.3 GB |
|---|---|
| **At 768Mi request per node** | **4 pods schedulable** |
| **Conservative stable limit** | **2–3 pods** |
| Community consensus (2024) | 2 stable, 3 light-load max |

**Notes:**
- k3s itself consumes ~150–300 MB on top of the OS
- Chromium processes can spike to 600 MB+ per instance under heavy page load
- Set `maxSessions: 1` (one browser per pod) for predictable memory usage
- 8 × Pi 4B cluster → **16 safe nodes** (2 per Pi), **up to 24 under ideal conditions** (3 per Pi with very lightweight tests)
- To reach "a few dozen" nodes reliably, target 2 nodes/Pi = 16 max, or mix with 8GB Pi units

### Chromium Launch Flags to Reduce Memory

These flags are applied by the `selenium/node-chromium` image automatically in headless mode, but can be reinforced via `SE_BROWSER_ARGS_CHROMIUM`:
```
--disable-gpu
--disable-dev-shm-usage     # use /tmp instead of /dev/shm (less critical when dshmVolumeSizeLimit set)
--no-sandbox
--headless=new              # modern headless mode
--disable-extensions
--disable-background-networking
--disable-default-apps
```

### Known ARM64 Stability Issues

1. **No `/dev/shm` by default in k8s pods** — Selenium chart handles this via `dshmVolumeSizeLimit`. Do NOT omit this setting.
2. **Chrome != Chromium** — `node-chrome` will silently fail or not pull on ARM64. Use `node-chromium`.
3. **OOM kills** — ARM64 Chromium is slightly more memory-efficient than x86, but Pi 4B 4GB is still tight. Use memory limits and monitor with `kubectl top pods`.
4. **ARM64 Chromium stability** — Chromium on aarch64 is stable; the Selenium node-chromium image is regression-tested on ARM64 from 4.21.0+.

---

## 4. External Access / TestNG Integration

### Connection URL

**Recommended (Selenium Grid 4, modern):**
```
http://<any-node-ip>:<nodeport>/
```

**Legacy (always works, backward compatible):**
```
http://<any-node-ip>:<nodeport>/wd/hub
```

Both endpoints are valid in Grid 4. `/wd/hub` is retained for full backward compatibility with all Selenium 3 / legacy test frameworks.

**Admin/status API only (NOT for RemoteWebDriver):**
```
http://<any-node-ip>:<nodeport>/se/grid/status    # Grid status JSON
http://<any-node-ip>:<nodeport>/graphql            # GraphQL for KEDA scaler
http://<any-node-ip>:<nodeport>/ui/index.html      # Web console
```

### TestNG RemoteWebDriver Example (Java)

```java
// Grid 4 — modern endpoint (preferred)
WebDriver driver = new RemoteWebDriver(
    new URL("http://192.168.1.100:30444/"),
    new ChromeOptions()   // ChromeOptions maps to Chromium on ARM64
);

// Grid 4 — legacy endpoint (drop-in replacement for Grid 3 configs)
WebDriver driver = new RemoteWebDriver(
    new URL("http://192.168.1.100:30444/wd/hub"),
    new ChromeOptions()
);
```

**Note on ChromeOptions with Chromium:** `ChromeOptions` works with `node-chromium` because Chromium responds to the `chrome`/`chromium` browserName capability. If capability matching fails, explicitly set:
```java
ChromeOptions opts = new ChromeOptions();
opts.setCapability("browserName", "chromium");
// or
opts.setBrowserVersion("stable");
```

### Grid 4 Session Endpoint Details

- `POST /session` — W3C WebDriver standard; both `/` and `/wd/hub` proxy to this
- `/se/grid/` — Grid management REST API and GraphQL; **not for starting sessions**
- The chart sets `SE_GRID_GRAPHQL_ENABLED=true` by default (needed for KEDA scaler)

---

## 5. k3s-Specific Considerations

### No Known k3s-Specific Blockers for Static Grid

A static Selenium Grid (hub + fixed-count node Deployments) has **no k3s-specific issues**. k3s ships with working CNI (Flannel by default), NodePort support, and standard RBAC — all of which Selenium Grid 4 requires.

### RBAC Requirements

#### Static Grid (hub + fixed nodes)
No special RBAC needed. Default pod ServiceAccount permissions are sufficient.

#### Dynamic Grid / KEDA Autoscaling
KEDA requires a ServiceAccount with pod management permissions:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: selenium-grid
  namespace: selenium
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: selenium-grid-role
rules:
  - apiGroups: [""]
    resources: ["pods", "pods/log", "services", "configmaps"]
    verbs: ["get", "watch", "list", "create", "delete", "update", "patch"]
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets"]
    verbs: ["get", "watch", "list", "create", "delete", "update", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: selenium-grid-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: selenium-grid-role
subjects:
  - kind: ServiceAccount
    name: selenium-grid
    namespace: selenium
```

The Helm chart auto-creates a ServiceAccount and RBAC when `autoscaling.enabled: true`. Review what it creates with `helm template` before applying.

### Networking on k3s

- **Flannel (k3s default):** Works. Pods can reach other pods across nodes. Hub-to-node registration works over pod IPs.
- **NodePort:** Works natively on k3s on all node IPs. No Ingress required for LAN access.
- **No NetworkPolicy by default:** k3s Flannel does not enforce NetworkPolicy; if you add Cilium or Calico, ensure inter-pod traffic in the `selenium` namespace is allowed.
- **No Ingress needed:** For LAN-only access via NodePort, skip Ingress configuration entirely.

### Pod Scheduling on Pi Cluster

k3s runs on each Pi node. The Selenium Grid **hub pod** should be pinned to one node (or made tolerant of any node), and **node pods** should be spread across all 8 Pis for even load:

```yaml
chromiumNode:
  topologySpreadConstraints:
    - maxSkew: 1
      topologyKey: kubernetes.io/hostname
      whenUnsatisfiable: DoNotSchedule
      labelSelector:
        matchLabels:
          app.kubernetes.io/name: selenium-grid-chromium-node
```

Or use a simple `podAntiAffinity` to distribute across hosts.

### Longhorn Storage

Selenium Grid 4 does **not** require persistent storage. No PVCs are needed for a stateless grid. Longhorn does not need to be involved unless you enable video recording with uploads.

### Helm Deployment (Shell-based, ARM64 tarball — matches cluster pattern)

```bash
# Matches existing cluster Helm deployment pattern
helm repo add docker-selenium https://www.selenium.dev/docker-selenium
helm repo update
helm upgrade --install selenium-grid docker-selenium/selenium-grid \
  --version 0.27.0 \
  --namespace selenium \
  --create-namespace \
  --values /path/to/selenium-values.yaml
```

### Kubernetes Version Requirement

Selenium Grid Helm chart requires **Kubernetes v1.26.15 or later**. k3s v1.26+ is compliant.

---

## 6. Source Documentation

| Topic | URL | Version / Date |
|-------|-----|----------------|
| Official docker-selenium README (ARM64 matrix) | https://github.com/SeleniumHQ/docker-selenium/blob/trunk/README.md | 4.43.0-20260404 |
| Multi-arch announcement blog post | https://www.selenium.dev/blog/2024/multi-arch-images-via-docker-selenium/ | May 2024 |
| Helm chart README | https://github.com/SeleniumHQ/docker-selenium/blob/trunk/charts/selenium-grid/README.md | Chart 0.27.0 |
| Helm chart CONFIGURATION reference | https://github.com/SeleniumHQ/docker-selenium/blob/trunk/charts/selenium-grid/CONFIGURATION.md | Chart 0.27.0 |
| ArtifactHub chart page | https://artifacthub.io/packages/helm/selenium-grid/selenium-grid | 0.27.0 stable |
| KEDA Selenium Grid scaler docs | https://keda.sh/docs/latest/scalers/selenium-grid-scaler/ | KEDA 2.15+ |
| selenium/node-chromium Docker Hub | https://hub.docker.com/r/selenium/node-chromium | 4.43.0+ |
| selenium/keda Docker Hub | https://hub.docker.com/r/selenium/keda | 2.15.1-selenium-grid-20240907 |
| Grid endpoint changelog (GitHub issue) | https://github.com/SeleniumHQ/selenium/issues/8678 | Grid 4.x |
| Selenium Grid official docs | https://www.selenium.dev/documentation/grid/ | 4.x |

---

## Quick Reference Card

```
Image (ARM64):     selenium/node-chromium:4.43.0-20260404
Image (hub):       selenium/hub:4.43.0-20260404
Helm repo:         helm repo add docker-selenium https://www.selenium.dev/docker-selenium
Chart:             docker-selenium/selenium-grid  version: 0.27.0
NodePort access:   http://<pi-node-ip>:30444/wd/hub
Per-Pi nodes:      2 (safe) / 3 (light load)
Cluster max:       16 safe nodes (8×Pi 4B 4GB)
KEDA autoscaling:  autoscaling.enabled: true (deploys patched KEDA automatically)
SHM required:      chromiumNode.dshmVolumeSizeLimit: 1Gi
Key RBAC:          Only required if autoscaling.enabled=true (chart auto-creates)
k3s blocker:       None for static grid; RBAC needed for KEDA
```
