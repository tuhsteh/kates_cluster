# Raspberry Pi CM4 Hardware Patterns

## Storage Device Naming

On Raspberry Pi CM4 carrier boards running Raspberry Pi OS Bookworm (64-bit):

| Device | Kernel prefix | Notes |
|--------|--------------|-------|
| Boot SD card | `mmcblk*` | Always — SD slot uses MMC controller; root is `/dev/mmcblk0p2` |
| NVMe m.2 SSD | `nvme*` | e.g., `nvme0n1` — preferred carrier boards |
| SATA m.2 SSD (bridge) | `sd*` | e.g., `sda` — same prefix as USB storage |

**Critical gotcha**: `ansible_devices[*].rotational` reports `"0"` (string, not integer) for BOTH SD cards and SSDs — both are flash storage. **Never use `rotational` to distinguish the boot device from the m.2 SSD.**

### Idiomatic Ansible SSD Discovery Pattern

```yaml
# Step 1: Try NVMe first
- name: Find NVMe SSD device
  ansible.builtin.set_fact:
    ssd_device: "{{ ansible_devices.keys()
                    | select('match', '^nvme[0-9]+n[0-9]+$')
                    | list | sort | first | default('') }}"

# Step 2: SATA fallback (non-removable sd* only)
- name: Find SATA SSD device (fallback)
  ansible.builtin.set_fact:
    ssd_device: "{{ ansible_devices | dict2items
                    | selectattr('key', 'match', '^sd[a-z]+$')
                    | selectattr('value.removable', 'equalto', '0')
                    | map(attribute='key')
                    | list | sort | first | default('') }}"
  when: ssd_device == ''

# Step 3: Fail fast if not found
- name: Assert SSD was found
  ansible.builtin.fail:
    msg: "No m.2 SSD detected. Devices found: {{ ansible_devices.keys() | list }}"
  when: ssd_device == ''
```

Note: `ansible_devices` keys are bare names (no `/dev/` prefix). The `removable == "0"` filter reduces false positives from USB storage but is not foolproof if USB devices are present during provisioning.

## Filesystem Tasks on Block Devices

### Format-if-missing (idempotent)

`community.general.filesystem` is the only clean single-module option — `ansible.builtin` has no mkfs module.

```yaml
- name: Create ext4 filesystem (idempotent — skips if filesystem exists)
  community.general.filesystem:
    fstype: ext4
    dev: "/dev/{{ ssd_device }}"
    # force: false is the default — omit; never set force: true in production
```

Internally runs `blkid`; only formats if no filesystem detected. Safe to re-run.

**Gotcha**: `mkfs.ext4` without `-F` prompts interactively when operating on a whole disk (not a partition), hanging the task. `community.general.filesystem` handles this internally — but if using raw `ansible.builtin.command: mkfs.ext4`, always pass `-F`.

### UUID Extraction

```yaml
- name: Read UUID of formatted device
  ansible.builtin.command: "blkid -s UUID -o value /dev/{{ ssd_device }}"
  register: ssd_uuid_result
  changed_when: false

- name: Set UUID fact
  ansible.builtin.set_fact:
    ssd_uuid: "{{ ssd_uuid_result.stdout | trim }}"
```

### Check-mode Safety Pattern

`ansible.builtin.command` runs unconditionally in `--check` mode. When a command task depends on a preceding `community.general.filesystem` task (which correctly skips formatting in check mode), the command will operate on an unformatted device and return empty/error output, causing misleading failures.

**Fix**: gate command tasks and their dependents with `when: not ansible_check_mode`, and provide a placeholder fact for the check-mode path:

```yaml
- name: Read UUID (skip in check mode — device may not be formatted yet)
  ansible.builtin.command: "blkid -s UUID -o value /dev/{{ ssd_device }}"
  register: ssd_uuid_result
  changed_when: false
  when: not ansible_check_mode

- name: Set UUID fact (check mode placeholder)
  ansible.builtin.set_fact:
    ssd_uuid: "CHECK-MODE-PLACEHOLDER"
  when: ansible_check_mode

- name: Set UUID fact
  ansible.builtin.set_fact:
    ssd_uuid: "{{ ssd_uuid_result.stdout | trim }}"
  when: not ansible_check_mode
```

## Persistent Mounts (`ansible.posix.mount`)

```yaml
- name: Mount SSD and write fstab entry
  ansible.posix.mount:
    path: /mnt/ssd
    src: "UUID={{ ssd_uuid }}"
    fstype: ext4
    opts: defaults,noatime   # noatime reduces write amplification on flash
    dump: "0"                # must be explicit — null causes duplicate fstab entries
    passno: "2"              # must be explicit — same reason
    state: mounted           # writes fstab AND mounts immediately; idempotent
```

`state: mounted` is idempotent — re-runs with identical parameters produce no change. The module keys fstab entries by `path`, so no duplicates are created.

**Critical**: Always specify `dump` and `passno` explicitly (even as `"0"`). Omitting them (null) causes duplicate fstab entries on subsequent runs per official ansible.posix docs.

## k3s Path Inventory (data on SSD)

k3s roles use `k3s_data_dir: /mnt/ssd/k3s` (defined in each role's `defaults/main.yaml`) to avoid path drift across tasks, templates, and handlers. **All references must use the variable — never hardcode the path.**

| Path | Owner | Notes |
|------|-------|-------|
| `{{ k3s_data_dir }}` | k3s data-dir | etcd, containerd images/snapshots, certs, tokens; auto-created by k3s but Ansible pre-creates it to prevent SD-card race |
| `{{ k3s_data_dir }}/server/token` | k3s server token | **wait_for and slurp tasks must use this path**; k3s does NOT create a symlink at the old default |
| `{{ k3s_data_dir }}/agent/kubelet` | kubelet root-dir | emptyDir volumes, pod sandbox; set via `kubelet-arg: root-dir=` because k3s deliberately excludes `/var/lib/kubelet` from `data-dir` |
| `/tmp` | OS | Already tmpfs on Bookworm (systemd `tmp.mount`, 50% RAM) — no Ansible needed |
| `/run/k3s/containerd` | OS | Always tmpfs (systemd `/run`); containerd runtime socket always here |
| `{{ k3s_data_dir }}/agent/containerd/containerd.log` | containerd log | Lands on SSD automatically; lumberjack rotation (50 MB / 3 backups) |

### k3s `/var/lib/kubelet` Exclusion

k3s deliberately does NOT move `/var/lib/kubelet` when `data-dir` is changed — this was reverted because CNI/CSI plugins hardcode this path. The only way to relocate it is `kubelet-arg: root-dir=/path`. **Warning**: Some CNI plugins (including some Flannel variants) may hardcode `/var/lib/kubelet` — verify compatibility after deploy. GitHub discussion #3802 tracks this.

### systemd Mount Ordering Drop-in

The `/mnt/ssd` systemd unit name is `mnt-ssd.mount` (systemd escaping: strip leading `/`, replace `/` with `-`). k3s roles install a drop-in at `/etc/systemd/system/k3s.service.d/override.conf` (leader) and `/etc/systemd/system/k3s-agent.service.d/override.conf` (member):

```ini
[Unit]
After=mnt-ssd.mount
Requires=mnt-ssd.mount
```

`ansible.builtin.copy` cannot create missing parent directories — always pre-create `.service.d/` with an explicit `ansible.builtin.file` task first.

### SSD Mount Guard

Pre-creation of `k3s_data_dir` includes a mount guard to prevent silent creation on the SD card when the role runs in isolation:

```yaml
when: (ansible_mounts | selectattr('mount', 'equalto', '/mnt/ssd') | list | length) > 0
```

## Longhorn Storage

### Version
Longhorn v1.11.1 (latest stable as of 2026-03-11). Minimum Kubernetes: v1.25.

### Required apt Packages (all nodes)
```bash
apt-get install -y open-iscsi nfs-common cryptsetup dmsetup
```
- `open-iscsi` — iSCSI initiator; required for all PV operations
- `nfs-common` — NFSv4 client for RWX volumes and backup
- `cryptsetup` — LUKS2 encryption (checked by preflight)
- `dmsetup` — Device Mapper userspace; **often missed but hard-required**
- `jq` is NOT in the official prerequisite list

### Kernel Modules
Persist via `/etc/modules-load.d/longhorn.conf`:
```
iscsi_tcp   # required
dm_crypt    # required for encrypted volumes
```
`systemd-modules-load.service` reads this at boot. Load immediately for current boot with `modprobe`.

### iscsid Service (Bookworm Socket Activation)
Enable `iscsid.socket` — **not** `iscsid.service`. Bookworm uses socket activation; `iscsid.service` showing inactive is correct and expected.
```yaml
- name: Enable iscsid socket (Bookworm socket-activation — iscsid.service will show inactive; this is correct)
  ansible.builtin.service:
    name: iscsid.socket
    state: started
    enabled: true
```

### multipathd Interference
If `multipathd.service` is running it will claim Longhorn block devices causing:
`mount: /dev/longhorn/pvc-xxx: already mounted or mount point busy`

Disable conditionally (do not fail if service absent):
```yaml
- name: Gather service facts
  ansible.builtin.service_facts:

- name: Disable multipathd if present and enabled
  ansible.builtin.service:
    name: multipathd
    state: stopped
    enabled: false
  when:
    - "'multipathd.service' in ansible_facts.services"
    - ansible_facts.services['multipathd.service'].status == 'enabled'
```

### k3s HelmChart CRD Deployment
Drop a `HelmChart` resource into `{{ k3s_leader_data_dir }}/server/manifests/` — k3s helm-controller handles install automatically. **`failurePolicy: abort` is critical** — default `reinstall` will silently delete Longhorn on any helm failure.

```yaml
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  annotations:
    helmcharts.cattle.io/managed-by: helm-controller
  finalizers:
    - wrangler.cattle.io/on-helm-chart-remove
  name: longhorn
  namespace: kube-system          # must be kube-system for auto-deploy
spec:
  version: "v1.11.1"
  chart: longhorn
  repo: https://charts.longhorn.io
  failurePolicy: abort            # CRITICAL — never omit
  targetNamespace: longhorn-system
  createNamespace: true
  valuesContent: |-
    defaultSettings:
      defaultDataPath: /mnt/ssd/longhorn
      defaultReplicaCount: 3
      replicaSoftAntiAffinity: true
      replicaAutoBalance: least-effort
    persistence:
      defaultClassReplicaCount: 3
```

### Cross-Role Variable Dependency
The `longhorn` role uses `k3s_leader_data_dir` from the `k3s_leader` role (both run in the same play). **Do not re-declare this variable in `longhorn/defaults/main.yaml`** — duplicating it creates a silent drift hazard if the k3s data dir ever changes.

### Data Path
`/mnt/ssd/longhorn` — created by `longhorn_prereqs` role with the SSD mount guard. Longhorn stores volume replicas here on every node.

### Known Issues on ARM64 / k3s
- **nftables/iptables conflict** (HIGH): Bookworm defaults to nftables; k3s nodes must use a consistent iptables backend or Flannel overlay traffic is silently dropped, causing replica communication failures.
- **multipathd interference** (HIGH): See above — disable before deploying Longhorn.
- **instance-manager CPU spikes** (MEDIUM): Periodic ~1h45m load spikes on RPi nodes. Mitigate with `guaranteed-instance-manager-cpu: 10`.
- **CSI + custom k3s data-dir**: Longhorn's CSI driver uses `/var/lib/kubelet` (not the k3s data-dir). Verify `longhorn-driver-deployer` DaemonSet is running if CSI fails after deploy.

## Ansible Cross-Role Variable Dependencies

When one role consumes a variable that is **owned and defaulted by another role** running in the same play, do NOT re-declare the variable as a local default. Duplicate defaults create silent drift: if the owning role's value changes, the consumer silently uses the stale copy.

**Pattern:**
```yaml
# tasks/main.yaml of the consuming role
# Depends on: k3s_leader role — provides k3s_leader_data_dir
- name: First task that uses k3s_leader_data_dir
  ansible.builtin.file:
    path: "{{ k3s_leader_data_dir }}/server/manifests"
    ...
```

**What NOT to do:**
```yaml
# consuming_role/defaults/main.yaml  ← WRONG
k3s_leader_data_dir: /mnt/ssd/k3s   # duplicates k3s_leader's default — will drift silently
```

The `# Depends on:` comment serves as self-documentation so future maintainers understand why the variable is used but not defined in the role's own defaults.

## Helm on k3s (ARM64)

### Shell-Based Helm Deployment
When `kubernetes.core` is not in `collections/requirements.yml`, deploy via `ansible.builtin.command` with `helm` installed as an ARM64 binary on the leader node. Always pass `--kubeconfig /etc/rancher/k3s/k3s.yaml` (absolute path — independent of `k3s_leader_data_dir`).

### Version-Pinned Binary Install Pattern
Do NOT use `creates: /usr/local/bin/helm` — it permanently blocks re-running when the version variable changes. Use a version-check `when` guard instead:

```yaml
- name: Check installed Helm version
  ansible.builtin.command: helm version --short
  register: <role_prefix>_helm_installed_version
  changed_when: false
  failed_when: false

- name: Download Helm tarball
  ansible.builtin.get_url:
    url: "https://get.helm.sh/helm-v{{ <role_prefix>_helm_version }}-linux-arm64.tar.gz"
    ...
  when: <role_prefix>_helm_version not in (<role_prefix>_helm_installed_version.stdout | default(''))
```

The `failed_when: false` on the version-check is required — if Helm is not yet installed, the command will fail and must not abort the play.

### Helm ansible.builtin.command Output Streams
`helm repo add` writes its idempotency message to **stdout**, not stderr:
- Already exists: `"<name>" already exists with the same configuration, skipping` → **stdout**
- First add: exit 0, stdout contains repo name → **stdout**

```yaml
changed_when: '"already exists" not in prometheus_repo_add.stdout'   # stdout ✓
failed_when: prometheus_repo_add.rc != 0 and "already exists" not in prometheus_repo_add.stdout
```

### Correct changed_when Strings for helm upgrade --install
`"has been deployed"` does **not exist** in Helm 3 output. The real strings are:
- First install: `"has been installed"`
- Subsequent runs: `"has been upgraded"`

```yaml
changed_when: >
  "has been installed" in prometheus_helm_deploy.stdout or
  "has been upgraded" in prometheus_helm_deploy.stdout
```

### kube-prometheus-stack k3s Required Overrides (v83+)
These are **silent failures** — the chart installs but produces errors, blank panels, or false alerts without them:

| Override | Reason |
|----------|--------|
| `kubeApiServer.enabled: false` | Embedded in k3s process; ServiceMonitor never matches |
| `kubeControllerManager.enabled: false` | Same — embedded |
| `kubeScheduler.enabled: false` | Same — embedded |
| `kubeProxy.enabled: false` | Absent — k3s uses Flannel/kube-proxy replacement |
| `kubeEtcd.enabled: false` | Absent — k3s uses SQLite |
| `prometheusOperator.admissionWebhooks.enabled: false` | Times out silently on ARM64 |
| `defaultRules.create: false` | Rules assume kubeadm; produces false alerts on k3s |
| `grafana.defaultDashboardsEnabled: false` | Blank panels on k3s (kubeadm-targeted queries) |
| `prometheusSpec.serviceMonitorSelectorNilUsesHelmValues: false` | Required for Longhorn/app ServiceMonitors to be scraped |

**Sub-chart key names are hyphenated** (not camelCase):
```yaml
prometheus-node-exporter:   # NOT nodeExporter:
  ...
kube-state-metrics:         # NOT kubeStateMetrics:
  ...
```

### Temp Values File Security
Values files templated to `/tmp` may contain plaintext secrets (e.g., Grafana admin password). Always:
- Set `mode: "0600"` on the template task
- Add a cleanup task (`ansible.builtin.file: state: absent`) immediately after the Helm deploy task

---

## docker-selenium/selenium-grid on ARM64 k3s

### ARM64 Browser Node — Critical
`selenium/node-chrome` has **no ARM64 Linux binary**. The only ARM64-compatible image is `selenium/node-chromium`. The legacy `seleniarm/*` namespace is deprecated (abandoned since 4.21.0, May 2024).

The Helm chart has **no `chromiumNode` key**. The browser node type is always `chromeNode`; the image is overridden via `imageName`:
```yaml
chromeNode:
  enabled: true
  imageName: node-chromium    # ← this is what makes it ARM64 Chromium
```
Helm silently ignores unknown keys — `chromiumNode: enabled: true` deploys zero browser nodes with no error.

### Chart Version / Image Tag Coupling
Chart version and image tag must come from the same release. Cross-check via the chart's `CHANGELOG.md` or `Chart.yaml` `appVersion`:

| Chart | Image tag |
|-------|-----------|
| 0.27.0 | 4.17.0-20240123 |
| 0.54.0 | 4.43.0-20260404 |

Mismatching causes hub/node protocol incompatibility — hub starts, nodes register, but sessions fail silently.

### /dev/shm — Non-Optional
k8s pods default to 64 MB `/dev/shm`. Chromium requires ~1 GB or silently crashes mid-session. Always set:
```yaml
chromeNode:
  dshmVolumeSizeLimit: "1Gi"
```

### Post-Deploy Health Check
Never use `kubectl rollout status deployment/<release>-hub` — chart naming helpers produce different names across versions. Use the HTTP readiness endpoint instead:
```yaml
- name: Verify Selenium Hub is reachable
  ansible.builtin.uri:
    url: "http://{{ ansible_host }}:{{ selenium_grid_hub_nodeport }}/readyz"
    status_code: 200
  retries: 10
  delay: 15
  until: result.status == 200
  changed_when: false
```

### KEDA Job-Based Scaling
`scalingType: job` means one pod per test session; pod terminates after the session ends; cluster scales to zero at rest. This matches the docker-compose Dynamic Grid behaviour (`selenium/node-docker` with Docker socket).

### `nodesImageTag` — Set Explicitly
`global.seleniumGrid.imageTag` overrides the hub image only. Browser nodes use `global.seleniumGrid.nodesImageTag`. Always set both to the same tag to prevent silent version mismatch:
```yaml
global:
  seleniumGrid:
    imageTag: "{{ selenium_grid_image_tag }}"
    nodesImageTag: "{{ selenium_grid_image_tag }}"
```

### Helm Timeout
KEDA controller + hub startup on ARM64 Pis pulling from a local registry can take 3-5 minutes. Use `--timeout 600s` on `helm upgrade --install`.

### First-Run Prerequisite — Pre-Push Images to Local Registry

**The playbook will fail on first run if these images are not already in `kate0.local:30500`.** The role sets `global.seleniumGrid.imageRegistry: kate0.local:30500`, so k3s will only look there — not Docker Hub.

Run these commands from any machine with Docker and access to the registry before running `ansible-playbook stage.yaml` for the first time (or after a chart/image tag upgrade):

```bash
# Pull from Docker Hub (multi-arch — ARM64 layers included)
docker pull selenium/hub:4.43.0-20260404
docker pull selenium/node-chromium:4.43.0-20260404

# Tag for local registry
docker tag selenium/hub:4.43.0-20260404 kate0.local:30500/selenium/hub:4.43.0-20260404
docker tag selenium/node-chromium:4.43.0-20260404 kate0.local:30500/selenium/node-chromium:4.43.0-20260404

# Push (registry auth uses docker_registry_htpasswd_* credentials)
docker push kate0.local:30500/selenium/hub:4.43.0-20260404
docker push kate0.local:30500/selenium/node-chromium:4.43.0-20260404
```

#### Additional pre-push: video recording + FileBrowser Quantum (selenium_media role)

```bash
# Selenium video recorder — ARM64 multi-arch (separate tag from hub/node)
docker pull --platform linux/arm64 selenium/video:ffmpeg-8.1-20260404
docker tag  selenium/video:ffmpeg-8.1-20260404 kate0.local:30500/selenium/video:ffmpeg-8.1-20260404
docker push kate0.local:30500/selenium/video:ffmpeg-8.1-20260404

# FileBrowser Quantum — ARM64 multi-arch WebDAV-enabled file browser
docker pull ghcr.io/gtsteffaniak/filebrowser:stable
docker tag  ghcr.io/gtsteffaniak/filebrowser:stable kate0.local:30500/gtsteffaniak/filebrowser:stable
docker push kate0.local:30500/gtsteffaniak/filebrowser:stable
```

KEDA images pull from `ghcr.io` directly (not mirrored) — Pi nodes need outbound internet access for those, but that is already confirmed working via Prometheus/Grafana deploys.

---

### Selenium Media — Screenshot + Video Storage (selenium_media role)

The `selenium_media` role creates a Longhorn **ReadWriteMany** PVC (`selenium-storage`, 20 Gi) and deploys FileBrowser Quantum as a WebDAV server. This shared PVC is also mounted by the Selenium Grid `videoRecorder` sidecar.

#### NodePort summary

| Service | NodePort | URL |
|---------|----------|-----|
| Selenium Grid Hub | 30444 | `http://kate0.local:30444/ui` |
| FileBrowser Quantum (WebDAV + browse) | 30081 | `http://kate0.local:30081/` |
| videoManager (read-only video browse) | 30080 | `http://kate0.local:30080/` |

#### PVC directory layout

```
selenium-storage (20 Gi, RWX)
├── screenshots/   ← TestNG writes here via WebDAV mount on laptop
└── videos/        ← videoRecorder sidecar writes one .mp4 per session
```

#### Mount WebDAV on macOS (no admin required)

```bash
# One-time (survives until reboot)
mkdir -p ~/mnt/selenium-media
mount_webdav http://kate0.local:30081/dav/ ~/mnt/selenium-media

# Create directories on first mount
mkdir -p ~/mnt/selenium-media/screenshots ~/mnt/selenium-media/videos

# Point TestNG at the mounted share
export WEBDRIVER_SCREENSHOT_DIRECTORY=~/mnt/selenium-media/screenshots
```

To auto-reconnect after reboots: add the mounted volume to **System Settings → General → Login Items** (drag the mounted Finder volume icon there).

#### Video recording settings (Pi 4B optimised)

The `videoRecorder` runs FFmpeg in software-only mode (Pi 4B has no GPU). Values are tuned to avoid saturating a Pi core:

| Setting | Value | Reason |
|---------|-------|--------|
| `SE_FRAME_RATE` | 10 | Default 30 FPS saturates one Pi core |
| `SE_SCREEN_WIDTH` | 1280 | Lower encode load vs 1920 |
| `SE_SCREEN_HEIGHT` | 720 | Same |

To disable video recording: set `selenium_grid_video_enabled: false` in group_vars.

---

## Multi-Board Ansible Detection

The cluster supports mixed Pi 4B + NanoPC T-4 nodes. Board type is detected at playbook runtime by the `board_detect` role (always first in both plays).

### `ansible_board_name` is empty on ARM SBCs

Both Raspberry Pi 4B and NanoPC T-4 return `""` for `ansible_board_name` and `ansible_product_name` — ARM boards don't expose DMI/SMBIOS data. **Do not use these facts for board detection.**

Confirmed by: https://github.com/ansible/ansible/issues/42632

### Use `/proc/device-tree/model`

```yaml
- name: Read /proc/device-tree/model
  ansible.builtin.slurp:
    src: /proc/device-tree/model
  register: board_detect_dt_model

- name: Set board_platform fact  # noqa: var-naming[no-role-prefix]
  ansible.builtin.set_fact:
    board_platform: >-
      {{ 'pi4' if 'Raspberry Pi 4' in (board_detect_dt_model.content | b64decode | trim)
         else ('nanopc-t4' if 'NanoPC-T4' in (board_detect_dt_model.content | b64decode | trim)
         else 'unknown') }}
```

| Board | `/proc/device-tree/model` |
|-------|--------------------------|
| Raspberry Pi 4B | `Raspberry Pi 4 Model B Rev 1.x` |
| NanoPC T-4 | `FriendlyARM NanoPC-T4` or `FriendlyELEC NanoPC-T4` |

Note: the string has a NUL terminator — always `| trim`.

### Gate tasks by board_platform

```yaml
when: board_platform == 'pi4'        # Pi-only tasks
when: board_platform == 'nanopc-t4'  # NanoPC-only tasks
# (no when:)                         # runs on both
```

`board_platform` is intentionally a cross-role fact (no role prefix). Suppress lint with `# noqa: var-naming[no-role-prefix]` on the set_fact task.

See `.context/domains/nanopc-t4-hardware.md` for full NanoPC T-4 reference.
