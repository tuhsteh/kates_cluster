# Research Cache: Selenium Media Storage on k3s ARM64

**Date:** 2026-04-16
**Task:** selenium-media — screenshot storage, video recording, file sharing on k3s

---

## Key Findings

### selenium/video Image
- ARM64 multi-arch since Selenium 4.21.0 (May 2024)
- Current tag: `ffmpeg-8.1-20260404`
- `global.seleniumGrid.videoImageTag` must be set separately from `imageTag` in Helm values

### FileBrowser Quantum vs Classic filebrowser
- Classic `filebrowser/filebrowser` has **NO WebDAV** — chart's built-in `videoManager` uses it (read-only)
- **FileBrowser Quantum** (`ghcr.io/gtsteffaniak/filebrowser`) is a fork with WebDAV enabled by default
- ARM64 multi-arch ✅, actively maintained (2025/2026 releases)
- WebDAV endpoint: `http://<host>/dav/`
- macOS mounts with `mount_webdav` (no admin required)

### MinIO (eliminated)
- Official ARM64 image discontinued October 2025 — do not use
- Also requires S3 SDK code changes in test framework

### Longhorn RWX
- `storageClassName: longhorn-rwx` with custom StorageClass using `driver.longhorn.io`
- `nfs-common` already installed by `longhorn_prereqs` role ✅
- `accessModes: ReadWriteMany` required for concurrent pod access
- Longhorn uses internal NFS Share Manager pod for RWX

### Helm values — videoRecorder
```yaml
videoRecorder:
  enabled: true
  targetFolder: "/videos"
  extraEnvironmentVariables:
    - name: SE_FRAME_RATE
      value: "10"        # default 30 saturates Pi 4B ARM core
    - name: SE_SCREEN_WIDTH
      value: "1280"
    - name: SE_SCREEN_HEIGHT
      value: "720"
  extraVolumes:
    - name: selenium-storage
      persistentVolumeClaim:
        claimName: selenium-storage
  extraVolumeMounts:
    - name: selenium-storage
      mountPath: /videos
      subPath: videos
  resources:
    requests: { memory: "128Mi", cpu: "100m" }
    limits:   { memory: "512Mi", cpu: "500m" }
```

### Helm values — videoManager (chart built-in)
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
```

## Sources
- https://hub.docker.com/r/selenium/video
- https://www.selenium.dev/blog/2024/multi-arch-images-via-docker-selenium/
- https://github.com/gtsteffaniak/filebrowser
- https://longhorn.io/docs/latest/volumes-and-nodes/rwx-volume/
- https://github.com/SeleniumHQ/docker-selenium/blob/trunk/charts/selenium-grid/CONFIGURATION.md
