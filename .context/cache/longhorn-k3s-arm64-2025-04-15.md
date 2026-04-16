# Longhorn on k3s / ARM64 — Research Cache

**Cache Date:** 2025-04-15
**Source versions researched:** Longhorn v1.11.1 (latest stable as of April 2026)
**Primary sources:** https://longhorn.io/docs/1.11.1/, https://github.com/longhorn/longhorn/releases

---

## Table of Contents

1. [Latest Stable Version](#1-latest-stable-version)
2. [ARM64 / Debian Package Prerequisites](#2-arm64--debian-package-prerequisites)
3. [Kernel Modules](#3-kernel-modules)
4. [iscsid Service Configuration](#4-iscsid-service-configuration)
5. [k3s HelmChart CRD YAML](#5-k3s-helmchart-crd-yaml)
6. [Node Labels and Annotations](#6-node-labels-and-annotations)
7. [Known Issues — ARM64 and k3s](#7-known-issues--arm64-and-k3s)
8. [longhornctl Preflight Tool](#8-longhornctl-preflight-tool)

---

## 1. Latest Stable Version

**v1.11.1** — released 2026-03-11

Release timeline:
- v1.9.0 — May 2025
- v1.10.0 — September 2025
- v1.11.0 — January 2026
- **v1.11.1** — March 11, 2026 (current latest stable)
- v1.12.0 — in development, expected ~May 2026

Key fixes in v1.11.1:
- Critical memory leak in `longhorn-instance-manager` proxy connections (#12575)
- S3 backup compatibility fix (aws-go-sdk v2)
- V2 Data Engine (SPDK) fast replica rebuild and clone fixes

Minimum Kubernetes version: **v1.25**

Source: https://github.com/longhorn/longhorn/releases

---

## 2. ARM64 / Debian Package Prerequisites

Official docs (https://longhorn.io/docs/1.11.1/deploy/install/) list the following for **Debian/Ubuntu**:

### Required packages (apt)

| Package | Purpose | apt command |
|---------|---------|-------------|
| `open-iscsi` | iSCSI initiator — Longhorn relies on `iscsiadm` for PV provision | `apt-get install open-iscsi` |
| `nfs-common` | NFSv4 client — required for RWX volumes and backup | `apt-get install nfs-common` |
| `cryptsetup` | LUKS2 disk encryption | `apt-get install cryptsetup` |
| `dmsetup` | Device Mapper userspace tool — required for dm-crypt and V2 volumes | `apt-get install dmsetup` |

### Required utilities (usually already present in Debian)

The official docs state: **`bash`, `curl`, `findmnt`, `grep`, `awk`, `blkid`, `lsblk` must be installed.**

- `findmnt`, `blkid`, `lsblk` come from `util-linux` (already in Debian Bookworm base)
- `mawk` ships as `awk` in Debian Bookworm (satisfies the `awk` requirement)
- `jq` is **NOT** in the official requirement list; it is a convenience tool only

### Notes

- `device-mapper` is listed as a checked package in the `longhornctl check preflight` output (as `Package device-mapper is installed`)
- On a minimal Bookworm install, `dmsetup` may not be present — the official docs now list it explicitly
- The preflight check output (from official docs v1.11.1) shows:
  ```
  - Package nfs-client is installed     ← this is the nfs-common package
  - Package open-iscsi is installed
  - Package cryptsetup is installed
  - Package device-mapper is installed
  - Module dm_crypt is loaded
  ```

### ARM64-specific notes

- No ARM64-specific package differences documented for Debian/Ubuntu
- The `longhornctl` binary has an ARM64 variant: `longhornctl-linux-arm64`
- Download: `curl -sSfL -o longhornctl https://github.com/longhorn/cli/releases/download/v1.11.1/longhornctl-linux-arm64`

---

## 3. Kernel Modules

### Officially required module

The official Longhorn docs (v1.11.1) explicitly state only one module by name:

> "Please ensure `iscsi_tcp` module has been loaded before iscsid service starts."

```bash
modprobe iscsi_tcp
```

### Module seen in preflight output (dm_crypt)

The `longhornctl check preflight` example output lists:
```
- Module dm_crypt is loaded
```
This indicates `dm_crypt` is checked (though it may not be strictly required unless using encrypted volumes).

### Persisting modules on Bookworm (systemd-modules-load)

Create `/etc/modules-load.d/longhorn.conf`:
```
# Required for Longhorn
iscsi_tcp
# Required if using encrypted volumes
dm_crypt
```

systemd's `systemd-modules-load.service` reads files in `/etc/modules-load.d/` at boot.

### ARM64 module availability

The `iscsi_tcp` module is present in the Raspberry Pi OS Bookworm kernel (kernel 6.x). No special kernel compilation is needed for CM4.

For encrypted volumes on ARM64, the following acceleration modules may improve performance (load if available, not required):
- `aes_arm64` / `aes_neon_bs`
- `sha256_arm64`
- `xts`

---

## 4. iscsid Service Configuration

### Debian/Ubuntu official guidance

The official Longhorn docs for Debian only say:
```bash
apt-get install open-iscsi
```

Unlike SUSE, there is **no explicit `systemctl enable iscsid`** instruction for Debian — this is because modern Debian packages use socket activation.

### Socket activation on Bookworm

Debian Bookworm uses `iscsid.socket` for socket-activated startup:

```bash
# Enable the socket unit (preferred on Bookworm)
sudo systemctl enable --now iscsid.socket
```

Notes:
- `iscsid.service` may show **inactive** — this is normal with socket activation
- The socket unit (`iscsid.socket`) starts the daemon when needed
- Port 3260 is standard for iSCSI

### Verification

```bash
systemctl status iscsid.socket  # Should show: active (listening)
iscsiadm -m session              # Shows active iSCSI sessions when Longhorn is running
```

### ARM64 / k3s known quirks

- No ARM64-specific open-iscsi quirks documented for Bookworm in Longhorn v1.11.1 docs
- On some systems, both `iscsid.socket` and `iscsid.service` should be enabled:
  ```bash
  systemctl enable --now open-iscsi iscsid
  ```
- After Longhorn installation, if volumes fail to attach: check `journalctl -u iscsid` and `journalctl -u iscsid.socket`

---

## 5. k3s HelmChart CRD YAML

### Official example (from Longhorn v1.11.1 docs)

Source: https://longhorn.io/docs/1.11.1/deploy/install/install-with-helm-controller/

```yaml
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  annotations:
    helmcharts.cattle.io/managed-by: helm-controller
  finalizers:
  - wrangler.cattle.io/on-helm-chart-remove
  generation: 1
  name: longhorn-install
  namespace: default
spec:
  version: v1.11.1
  chart: longhorn
  repo: https://charts.longhorn.io
  failurePolicy: abort
  targetNamespace: longhorn-system
  createNamespace: true
```

**IMPORTANT**: `spec.failurePolicy: abort` — must be set. The default `reinstall` will trigger an uninstall of Longhorn on failure.

### Using spec.set for values

Source: https://longhorn.io/docs/1.11.1/advanced-resources/deploy/customizing-default-settings/#using-helm-controller

```yaml
spec:
  ...
  set:
    defaultSettings.priorityClass: system-node-critical
    defaultSettings.replicaAutoBalance: least-effort
    defaultSettings.storageOverProvisioningPercentage: "200"
    persistence.defaultClassReplicaCount: "2"
```

### Using valuesContent for values

Alternatively, use `valuesContent` (multiline YAML values block):

```yaml
spec:
  version: v1.11.1
  chart: longhorn
  repo: https://charts.longhorn.io
  failurePolicy: abort
  targetNamespace: longhorn-system
  createNamespace: true
  valuesContent: |-
    defaultSettings:
      defaultDataPath: /mnt/ssd/longhorn
      createDefaultDiskLabeledNodes: true
      defaultReplicaCount: 3
      replicaSoftAntiAffinity: true
    persistence:
      defaultClassReplicaCount: 3
```

### Key Helm values reference

| Helm key | Description | Default |
|----------|-------------|---------|
| `defaultSettings.defaultDataPath` | Path for volume data on nodes | `/var/lib/longhorn` |
| `defaultSettings.defaultReplicaCount` | Number of replicas per volume | `3` |
| `defaultSettings.createDefaultDiskLabeledNodes` | Only create disks on labeled nodes | `false` |
| `defaultSettings.replicaSoftAntiAffinity` | Allow replicas on same zone | `true` |
| `defaultSettings.replicaAutoBalance` | Auto-balance replicas across nodes | `disabled` |
| `persistence.defaultClassReplicaCount` | Default StorageClass replica count | `3` |

### Namespace notes

- `metadata.namespace` should be `kube-system` or `default` (for k3s bootstrapping, use `kube-system`)
- `spec.targetNamespace` should be `longhorn-system` (Longhorn's own namespace)
- `spec.createNamespace: true` — Longhorn will create `longhorn-system` automatically

---

## 6. Node Labels and Annotations

Source: https://longhorn.io/docs/1.11.1/nodes-and-volumes/nodes/default-disk-and-node-config/

### Prerequisite: Enable setting

Set `defaultSettings.createDefaultDiskLabeledNodes: true` (in HelmChart values or Longhorn UI).

When this setting is **disabled** (default), Longhorn creates a disk on ALL new nodes using `default-data-path`. When **enabled**, Longhorn only creates disks on nodes with the label.

### Label: node.longhorn.io/create-default-disk

| Value | Effect |
|-------|--------|
| `"true"` | Create default disk at `settings.default-data-path` |
| `"config"` | Create disk(s) according to the `default-disks-config` annotation |

```bash
# Simple default disk at defaultDataPath
kubectl label node <NODE> node.longhorn.io/create-default-disk=true

# Custom disk path via annotation
kubectl label node <NODE> node.longhorn.io/create-default-disk=config
```

### Annotation: node.longhorn.io/default-disks-config

JSON array of disk configs. Only takes effect when label is `"config"` AND the setting is enabled AND the node has no existing disks.

```bash
kubectl annotate node <NODE> node.longhorn.io/default-disks-config='[
  {
    "path": "/mnt/ssd/longhorn",
    "allowScheduling": true
  }
]'
```

Full field reference per disk entry:
- `path` (string, required) — absolute path on host
- `allowScheduling` (bool) — whether Longhorn schedules replicas here
- `storageReserved` (int) — bytes to reserve (not usable by Longhorn)
- `name` (string) — unique disk name (must be unique per node)
- `tags` ([]string) — disk tags for volume scheduling constraints

### Annotation: node.longhorn.io/default-node-tags

```bash
kubectl annotate node <NODE> node.longhorn.io/default-node-tags='["fast","storage"]'
```

Only applied if node has NO existing tags. Tags are used for affinity scheduling of volumes.

### Important caveats

- Labels and annotations are **only processed once** on new nodes — Longhorn does NOT keep them in sync afterward
- If node already has disks, the disk config annotation is ignored
- Invalid annotation JSON causes the **entire annotation to be ignored** (no partial application)

---

## 7. Known Issues — ARM64 and k3s

### CPU/load spikes (instance-manager)

**Issue**: Periodic high load spikes (~every 1h45m) after Longhorn install on RPi nodes.
**GitHub**: https://github.com/longhorn/longhorn/issues/9735
**Workaround**: Disable Longhorn scheduling on control-plane nodes. Consider tuning `guaranteed-instance-manager-cpu` setting.

### nftables vs. iptables (Debian Bookworm)

**Issue**: Debian Bookworm defaults to nftables. k3s uses iptables (or iptables-nft). Mixed modes can silently drop cross-node VXLAN/Flannel traffic, causing Longhorn `CrashLoopBackOff`.
**Fix**: 
```bash
# Ensure iptables uses legacy mode or nft mode consistently with k3s
# Check which mode k3s is using:
ls -la /usr/sbin/iptables  # should be iptables-nft or iptables-legacy
# Ensure consistency across all nodes
```
Source: https://www.jonathanclarke.ie/2026/02/16/longhorn-crashloopbackoff-fix.html

### multipathd conflict

**Issue**: `multipathd.service` running on nodes causes Longhorn volumes to be grabbed by multipath, preventing attachment.
**longhornctl preflight warning**: `multipathd.service is running. Please refer to https://longhorn.io/kb/troubleshooting-volume-with-multipath/ for more information.`
**Fix**: Blacklist Longhorn devices in `/etc/multipath.conf`, or disable multipathd if not needed:
```ini
blacklist {
    devnode "^sd[a-z0-9]+"
}
```
Source: https://longhorn.io/kb/troubleshooting-volume-with-multipath/

### Stale webhook configurations on upgrade

**Issue**: `ValidatingWebhookConfiguration` and `MutatingWebhookConfiguration` from old Longhorn versions block upgrades.
**Fix**: Delete and let them regenerate:
```bash
kubectl delete validatingwebhookconfiguration longhorn-webhook-validator
kubectl delete mutatingwebhookconfiguration longhorn-mutating-webhook-configuration
```

### k3s kubelet root dir

**Issue**: If k3s is configured with a custom `--data-dir`, Longhorn may fail to find kubelet root.
**Fix**: For k3s v0.10.0+, the kubelet root is always `/var/lib/kubelet` — this should auto-detect. If CSI fails:
```bash
# Check k3s data-dir
ps aux | grep k3s | grep data-dir
```
If custom, set `KUBELET_ROOT_DIR` env var in the `longhorn-driver-deployer` deployment.
Source: https://longhorn.io/docs/1.11.1/advanced-resources/os-distro-specific/csi-on-k3s/

### Missing device-mapper on minimal installs

**Issue**: Minimal Bookworm installs may not have `dmsetup` installed. Required for V2 data engine and dm-crypt encryption.
**Fix**: `apt-get install dmsetup`

### SD card / storage media

**Note**: SD cards are not recommended as Longhorn storage targets due to high write amplification and wear. Use SSD or USB 3.0+ attached storage.

---

## 8. longhornctl Preflight Tool

Official tool for checking prerequisites before install.

```bash
# Download for ARM64
curl -sSfL -o longhornctl \
  https://github.com/longhorn/cli/releases/download/v1.11.1/longhornctl-linux-arm64
chmod +x longhornctl

# Check environment
./longhornctl check preflight

# Install missing prerequisites automatically
./longhornctl install preflight
```

The tool checks and reports:
- Service `iscsid` running status
- NFS4 kernel support
- Package: `nfs-common` / `nfs-client`
- Package: `open-iscsi`
- Package: `cryptsetup`
- Package: `device-mapper`
- Module: `dm_crypt`
- multipathd warnings

---

## Sources

| Document | URL |
|----------|-----|
| Longhorn v1.11.1 Install Requirements | https://longhorn.io/docs/1.11.1/deploy/install/ |
| Longhorn v1.11.1 Helm Controller Install | https://longhorn.io/docs/1.11.1/deploy/install/install-with-helm-controller/ |
| Longhorn v1.11.1 Customizing Default Settings | https://longhorn.io/docs/1.11.1/advanced-resources/deploy/customizing-default-settings/ |
| Longhorn v1.11.1 Default Disk and Node Config | https://longhorn.io/docs/1.11.1/nodes-and-volumes/nodes/default-disk-and-node-config/ |
| Longhorn v1.11.1 CSI on k3s | https://longhorn.io/docs/1.11.1/advanced-resources/os-distro-specific/csi-on-k3s/ |
| Longhorn KB: multipath | https://longhorn.io/kb/troubleshooting-volume-with-multipath/ |
| GitHub Releases | https://github.com/longhorn/longhorn/releases |
| Instance manager CPU issue #9735 | https://github.com/longhorn/longhorn/issues/9735 |
| nftables CrashLoopBackOff fix | https://www.jonathanclarke.ie/2026/02/16/longhorn-crashloopbackoff-fix.html |
