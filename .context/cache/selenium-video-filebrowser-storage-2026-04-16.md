# Selenium Video Recording + File-Sharing Storage on k3s ARM64 — Research Cache

**Research Date:** 2026-04-16
**Researched By:** @researcher
**Cache Expires:** 2026-04-19 (3-day TTL)
**Scope:** Enabling Selenium Grid video recording, deploying a file-browser (WebDAV-capable) for shared screenshot/video access, and configuring a laptop to write screenshots directly to cluster storage on an 8-node ARM64 Raspberry Pi 4B k3s cluster with Longhorn.

---

## Table of Contents

1. [Helm Chart Version Clarification](#1-helm-chart-version-clarification)
2. [selenium/video Image — ARM64 Support](#2-seleniumvideo-image--arm64-support)
3. [videoRecorder Values (values.yaml)](#3-videorecorder-values-valuesyaml)
4. [videoManager — Built-in Filebrowser in the Chart](#4-videomanager--built-in-filebrowser-in-the-chart)
5. [Classic Filebrowser vs Filebrowser Quantum (WebDAV)](#5-classic-filebrowser-vs-filebrowser-quantum-webdav)
6. [MinIO ARM64 Status (October 2025+)](#6-minio-arm64-status-october-2025)
7. [NFS-based Sharing in k3s](#7-nfs-based-sharing-in-k3s)
8. [Longhorn RWX (ReadWriteMany)](#8-longhorn-rwx-readwritemany)
9. [macOS WebDAV Mounting (No Admin Required)](#9-macos-webdav-mounting-no-admin-required)
10. [Recommended Architecture](#10-recommended-architecture)
11. [Source Documentation](#11-source-documentation)

---

## 1. Helm Chart Version Clarification

**User reports using chart version 0.54.0. This version does not appear to exist as a stable release.**

- Latest stable chart (as of research date): **0.46.x** (app version 4.35.0-20250828)
- Trunk (main branch) currently pins image tag: `4.43.0-20260404`
- Chart source on trunk: https://github.com/SeleniumHQ/docker-selenium/tree/trunk/charts/selenium-grid
- The user's existing task plan references chart `0.27.0` (the version cached on 2026-04-16)
- **Likely explanation:** User may have an updated chart available from a recent `helm repo update`. If the chart is already deployed at a specific version, the values structure in this document (pulled from trunk) applies.

**Action:** Run `helm repo update docker-selenium && helm search repo docker-selenium/selenium-grid --versions | head -5` on the cluster to confirm the exact deployed/available version.

---

## 2. selenium/video Image — ARM64 Support

### ✅ STATUS: ARM64 CONFIRMED

The `selenium/video` image is part of the official multi-arch Selenium Docker image set, which became multi-arch in **May 2024 (Selenium 4.21.0)**. ARM64/aarch64 is fully supported.

| Image | ARM64 | Notes |
|-------|:-----:|-------|
| `selenium/video` | ✅ | Multi-arch from 4.21.0+ |

**Current image tag (from trunk values.yaml):**
```
selenium/video:ffmpeg-8.1-20260404
```

This tag is set globally via:
```yaml
global:
  seleniumGrid:
    videoImageTag: "ffmpeg-8.1-20260404"
```

The `selenium/video` container:
- Uses **FFmpeg** for recording via a virtual framebuffer (Xvfb)
- Bundled with **rclone** for optional upload to S3/GCS/other remotes
- Records one video file per Selenium session
- File naming includes session ID by default
- Default recording path inside container: `/videos`

**Sources:**
- https://hub.docker.com/r/selenium/video
- https://www.selenium.dev/blog/2024/multi-arch-images-via-docker-selenium/

---

## 3. videoRecorder Values (values.yaml)

### From Official Trunk values.yaml

Key fields extracted from `https://raw.githubusercontent.com/SeleniumHQ/docker-selenium/trunk/charts/selenium-grid/values.yaml` (section starting ~byte 76000):

```yaml
videoRecorder:
  # -- Enable video recording in all browser nodes
  enabled: false                          # ← SET TO true

  # -- Sidecar container mode (two containers in same pod) or single container
  sidecarContainer: false

  # -- Container name
  name: video

  # -- Image registry (defaults to global.seleniumGrid.imageRegistry = "selenium")
  imageRegistry:

  # -- Image name
  imageName: video

  # -- Image tag (defaults to global.seleniumGrid.videoImageTag = "ffmpeg-8.1-20260404")
  imageTag:

  # -- Image pull policy
  imagePullPolicy: IfNotPresent

  # -- Directory to store video files INSIDE the container
  targetFolder: "/videos"

  uploader:
    # -- Enable rclone upload after recording
    enabled: false
    # -- rclone destination e.g. "s3://mybucket/videos/"
    destinationPrefix:
    # -- Uploader type (empty = internal rclone in video container)
    name:
    configFileName: upload.conf
    entryPointFileName: upload.sh
    # -- rclone credentials as environment variables (sensitive)
    secrets:
    #  RCLONE_CONFIG_S3_TYPE: "s3"
    #  RCLONE_CONFIG_S3_ACCESS_KEY_ID: "xxx"
    #  RCLONE_CONFIG_S3_SECRET_ACCESS_KEY: "xxx"
    extraEnvFrom: []

  # -- Video recorder container port
  ports:
    - 9000

  # -- Resources for video recorder
  resources:
    requests:
      memory: "128Mi"
      cpu: "0.1"
    limits:
      memory: "1Gi"
      cpu: "0.5"

  terminationGracePeriodSeconds: 30

  # -- Mount a PVC by adding extraVolumes + extraVolumeMounts:
  extraVolumeMounts: []
  # - name: video-storage
  #   mountPath: /videos          ← maps targetFolder to PVC

  extraVolumes: []
  # - name: video-storage
  #   persistentVolumeClaim:
  #     claimName: selenium-storage  ← point to Longhorn PVC
```

### Minimal values snippet to enable recording to a PVC:

```yaml
videoRecorder:
  enabled: true
  targetFolder: "/videos"
  extraVolumes:
    - name: selenium-storage
      persistentVolumeClaim:
        claimName: selenium-storage   # RWX Longhorn PVC
  extraVolumeMounts:
    - name: selenium-storage
      mountPath: /videos
      subPath: videos                 # store videos in /videos subdir of PVC
```

### Resource impact on Pi 4B

Adding a video recorder sidecar to each browser node pod adds:
- ~128Mi RAM request (FFmpeg idle)
- ~0.1 CPU request
- FFmpeg encoding during recording: up to 0.5 CPU (ARM64 FFmpeg is software-encoded, no GPU)
- Disk I/O: ~5–20 MB/min per recording depending on resolution and FPS

**Recommendation for Pi 4B:** Set `SE_FRAME_RATE=10` and `SE_SCREEN_WIDTH=1280` / `SE_SCREEN_HEIGHT=720` to reduce I/O:
```yaml
videoRecorder:
  extraEnvironmentVariables:
    - name: SE_FRAME_RATE
      value: "10"
    - name: SE_SCREEN_WIDTH
      value: "1280"
    - name: SE_SCREEN_HEIGHT
      value: "720"
```

---

## 4. videoManager — Built-in Filebrowser in the Chart

**KEY FINDING:** The Selenium Grid Helm chart already bundles a `videoManager` component which deploys a **classic filebrowser** to browse video recordings.

From trunk values.yaml (section ~byte 84000):

```yaml
videoManager:
  # -- Enable video manager (filebrowser for video recordings)
  enabled: false                      # ← set to true to enable

  ingress:
    enabled: true
    annotations:
    paths: []

  # -- Uses classic filebrowser image
  imageRegistry: "filebrowser"        # docker.io/filebrowser/filebrowser
  imageName: "filebrowser"
  imageTag: "latest"

  imagePullPolicy: IfNotPresent
  imagePullSecret: ""

  config:
    baseurl: "/recordings"            # URL base path
    username: ""                      # default "admin"
    password: ""                      # hashed bcrypt, default "admin"
    noauth: true                      # no auth for quick setup

  port: 80
  nodePort: 30080                     # NodePort access

  serviceType: ClusterIP              # change to NodePort for LAN access

  resources:
    requests:
      cpu: "0.1"
      memory: "128Mi"
    limits:
      cpu: "1"
      memory: "1Gi"

  replicas: 1

  extraVolumeMounts: []
  # - name: srv
  #   mountPath: /srv               ← mount the same PVC as video recorder
  #   subPath: srv

  extraVolumes: []
  # - name: srv
  #   persistentVolumeClaim:
  #     claimName: selenium-storage
```

### Critical Limitation: videoManager uses CLASSIC filebrowser

`filebrowser/filebrowser:latest` is the **classic (original) filebrowser**. It has **NO WebDAV support**. WebDAV requires **FileBrowser Quantum** (`ghcr.io/gtsteffaniak/filebrowser`).

Use `videoManager` for **read-only browsing** of recordings from a browser. It cannot serve as a write target for laptop screenshots.

### To wire videoManager to the same PVC as videoRecorder:

```yaml
videoManager:
  enabled: true
  serviceType: NodePort
  nodePort: 30080
  extraVolumes:
    - name: selenium-storage
      persistentVolumeClaim:
        claimName: selenium-storage
  extraVolumeMounts:
    - name: selenium-storage
      mountPath: /srv
      # serves full PVC root; or add subPath: videos if only showing videos
```

---

## 5. Classic Filebrowser vs Filebrowser Quantum (WebDAV)

### Classic Filebrowser — `filebrowser/filebrowser` (Docker Hub)

| Feature | Status |
|---------|--------|
| ARM64 support | ✅ Multi-arch |
| WebDAV | ❌ **None** (not available, not planned in classic branch) |
| Helm chart | Community: `filebrowser-charts/filebrowser` on ArtifactHub |
| Suitable for | Read-only web UI for file browsing |

### FileBrowser Quantum — `ghcr.io/gtsteffaniak/filebrowser`

| Feature | Status |
|---------|--------|
| ARM64 support | ✅ Multi-arch (arm64, amd64, arm/v7) |
| WebDAV | ✅ **Enabled by default** (since v1.3.0-beta) |
| Helm chart | No official chart; deploy as k8s Deployment manually |
| WebDAV path | `http://<host>:<port>/dav/<source-name>/` |
| Auth | API Token as WebDAV password |
| macOS Finder | ✅ Tested and confirmed working |

**FileBrowser Quantum WebDAV configuration:**
- WebDAV is ON by default; disable with `server.disableWebDAV: true` in config
- Token-based auth: create API Token in Settings → API Tokens
- Token acts as password; username is arbitrary (ignored)
- URL format: `http://192.168.1.100:30081/dav/screenshots/`
- Sources map to directory paths on the container

**Available tags (2026):**
```
ghcr.io/gtsteffaniak/filebrowser:stable
ghcr.io/gtsteffaniak/filebrowser:beta
ghcr.io/gtsteffaniak/filebrowser:1.3.3
ghcr.io/gtsteffaniak/filebrowser:stable-slim
```

**Source:** https://filebrowserquantum.com/en/docs/features/webdav/

---

## 6. MinIO ARM64 Status (October 2025+)

### ⚠️ OFFICIAL minio/minio IMAGE DROPPED ARM64 SUPPORT IN OCTOBER 2025

The official `minio/minio` Docker image on Docker Hub **stopped providing ARM64 builds after October 2025**. This is a breaking change for ARM64 clusters.

**Community-maintained alternatives:**

| Image | Architecture | Notes |
|-------|-------------|-------|
| `ghcr.io/golithus/minio` | amd64, arm64 | Built nightly from official source |
| `bigbeartechworld/big-bear-minio` | amd64, arm64 | Actively maintained |
| `alpine/minio` | multi-arch | Alpine community maintained |

**MinIO for this use case assessment:**
- Requires code changes to write screenshots (S3 SDK, no filesystem mount)
- WebDAV: No — MinIO uses S3 protocol only
- To write from macOS without code changes: would need rclone mount or s3fs-fuse (complex)
- **Not recommended** for this use case due to ARM64 image instability and inability to mount as filesystem without additional tooling.

---

## 7. NFS-based Sharing in k3s

### NFS-Ganesha as a Pod

- Can run NFS-Ganesha as a pod in the cluster, exporting a Longhorn-backed volume
- `nfs-subdir-external-provisioner` (k8s-sigs) supports ARM64 and auto-creates PVC subdirectories
- Needs `hostNetwork: true` or LoadBalancer service for LAN access from laptop
- macOS can mount NFS: `mount -t nfs <ip>:/export ~/NFSMount` but requires sudo

**ARM64 image:** `registry.k8s.io/sig-storage/nfs-subdir-external-provisioner` — multi-arch, ARM64 supported

**Comparison vs WebDAV:**

| Factor | NFS | WebDAV (filebrowser Quantum) |
|--------|-----|------------------------------|
| macOS mount (no admin) | ❌ Requires sudo | ✅ Finder only, no admin |
| Complexity | High (kernel module, portmapper, exports config) | Low (single container) |
| Write performance | High | Moderate (HTTP overhead) |
| Browser UI for viewing | External tool needed | ✅ Built-in |
| k8s setup | Complex (privileged pod, hostNetwork) | Simple deployment |

**Verdict:** NFS is more complex than WebDAV for this use case and requires admin on macOS. Not recommended.

---

## 8. Longhorn RWX (ReadWriteMany)

### ✅ Longhorn Supports RWX (v1.1+)

Longhorn implements RWX via an **internal NFSv4 Share Manager Pod**:
- Each RWX volume gets a dedicated Share Manager pod running NFS server
- All nodes that need access mount the NFS share transparently
- Multiple pods across different nodes can concurrently write to the same PVC

**Requirements:**
- Longhorn v1.1 or later (already deployed on this cluster)
- **`nfs-common` package installed on ALL Pi nodes** (Debian-based: `apt install nfs-common`)
- Unique hostnames per node (Raspberry Pi cluster already has this)

**StorageClass for RWX:**
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-rwx
provisioner: driver.longhorn.io
parameters:
  numberOfReplicas: "2"            # 2 replicas is safe for 8-node cluster
  staleReplicaTimeout: "2880"
  nfsOptions: "vers=4.1,noresvport"
```

**PVC definition:**
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: selenium-storage
  namespace: selenium
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: longhorn-rwx
  resources:
    requests:
      storage: 20Gi               # screenshots: ~1–5 MB each; videos: ~10–100 MB each
```

**PVC sizing guidance:**
- Screenshots (PNG): ~0.5–5 MB each; 1000 screenshots ≈ 1–5 GB
- Videos (FFmpeg MP4, 10 FPS, 720p): ~10–30 MB per minute of recording
- Recommend 20Gi to start; Longhorn volumes can be expanded online

**Performance notes:**
- RWX latency is higher than RWO because of the NFS layer (Share Manager hop)
- For screenshots and videos (not databases), this latency is acceptable
- The Share Manager pod is a single point of failure; if it crashes, all PVC access pauses until it recovers (usually seconds)

---

## 9. macOS WebDAV Mounting (No Admin Required)

### ✅ No Admin Required for Finder WebDAV Mount

**Method 1: Finder GUI (easiest)**
1. Open Finder
2. `Go` → `Connect to Server...` (or ⌘K)
3. Enter: `http://<pi-node-ip>:<nodeport>/dav/<source-name>/`
4. Enter credentials (username: `admin` or anything; password: API token from filebrowser Quantum)
5. Volume appears at `/Volumes/<name>/` in macOS

**Method 2: CLI (no admin, mount to user-owned path)**
```bash
mkdir ~/mnt/selenium-storage
mount_webdav http://<pi-node-ip>:30081/dav/data/ ~/mnt/selenium-storage
# Then set in test runner:
export WEBDRIVER_SCREENSHOT_DIRECTORY=~/mnt/selenium-storage/screenshots
```

**Persistence across reboots:**
- Finder mounts are NOT persistent; add to macOS Login Items (drag mounted drive) for auto-reconnect
- Alternatively: add to `/etc/fstab` — but that requires admin

**Important Caveats:**
- macOS WebDAV client has a known performance issue with large directories; keep screenshot directory structure shallow
- `http://` (not `https://`) is fine for LAN-only use
- If filebrowser Quantum uses HTTPS, macOS may require certificate trust

---

## 10. Recommended Architecture

### Overview

```
┌─────────────────────────────────────────────┐
│               k3s cluster                   │
│                                             │
│  Namespace: selenium                        │
│                                             │
│  ┌────────────────────────────────────┐     │
│  │  Longhorn RWX PVC: selenium-storage│     │
│  │  StorageClass: longhorn-rwx        │     │
│  │  Size: 20Gi                        │     │
│  │  ├── /videos/  (video recorder)    │     │
│  │  └── /screenshots/ (laptop writes) │     │
│  └────────────────────────────────────┘     │
│           ↑                    ↑            │
│  ┌─────────────────┐   ┌──────────────────┐ │
│  │ chromium node   │   │ filebrowser      │ │
│  │ (+ video sidecar│   │ Quantum          │ │
│  │  → /videos/)    │   │ NodePort 30081   │ │
│  └─────────────────┘   │ WebDAV at /dav/  │ │
│                        └──────────────────┘ │
│  ┌─────────────────────────────────────┐    │
│  │ videoManager (chart built-in)       │    │
│  │ classic filebrowser, NodePort 30080 │    │
│  │ reads /srv → mounted to PVC         │    │
│  │ (read-only web UI for team)         │    │
│  └─────────────────────────────────────┘    │
└─────────────────────────────────────────────┘
         ↑                      ↑
 VideoRecorder writes     macOS mounts WebDAV
 session videos           writes screenshots
```

### Why Filebrowser Quantum over alternatives

| Criterion | filebrowser Quantum | videoManager (classic fb) | MinIO | NFS |
|-----------|:------------------:|:------------------------:|:-----:|:---:|
| ARM64 ✅ | ✅ | ✅ | ⚠️ community only | ✅ |
| WebDAV ✅ | ✅ | ❌ | ❌ | ❌ |
| macOS no-admin mount | ✅ | ❌ | ❌ | ❌ |
| No test code changes | ✅ | ❌ | ❌ | ✅* |
| Web browse files | ✅ | ✅ | ✅ | ❌ |
| PVC-backed | ✅ | ✅ | ✅ | ✅ |

*NFS requires macOS admin to mount

---

## 11. Source Documentation

| Topic | URL | Version / Date |
|-------|-----|----------------|
| Selenium docker-selenium trunk values.yaml (videoRecorder, videoManager) | https://raw.githubusercontent.com/SeleniumHQ/docker-selenium/trunk/charts/selenium-grid/values.yaml | 4.43.0-20260404 |
| selenium/video Docker Hub | https://hub.docker.com/r/selenium/video | ffmpeg-8.1-20260404 |
| Multi-arch Selenium announcement | https://www.selenium.dev/blog/2024/multi-arch-images-via-docker-selenium/ | May 2024 |
| FileBrowser Quantum WebDAV docs | https://filebrowserquantum.com/en/docs/features/webdav/ | v1.3.0-beta+ |
| FileBrowser Quantum GitHub | https://github.com/gtsteffaniak/filebrowser | 2026-active |
| Longhorn RWX volumes | https://longhorn.io/docs/latest/volumes-and-nodes/rwx-volume/ | Longhorn v1.1+ |
| Longhorn RWX blog (2026) | https://oneuptime.com/blog/post/2026-03-20-longhorn-readwritemany-volumes/view | 2026-03-20 |
| macOS WebDAV Finder mount | macOS built-in `mount_webdav` / Finder Connect to Server | macOS Sonoma |
| MinIO ARM64 end-of-life | https://github.com/golithus/minio-builds | Oct 2025+ |
| Helm chart CONFIGURATION.md | https://github.com/SeleniumHQ/docker-selenium/blob/trunk/charts/selenium-grid/CONFIGURATION.md | trunk |
