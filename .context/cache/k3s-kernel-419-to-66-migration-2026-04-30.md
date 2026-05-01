# k3s / Kubernetes: Kernel 4.19 → 6.6 Migration Reference (ARM64 / Debian 13)

**Research Date:** 2026-04-30
**Researched By:** @researcher
**Valid Until:** 2026-05-03 (3-day cache expiry)
**Platform:** NanoPC-T4 (RK3399, ARM64), Debian 13 Trixie, k3s, FriendlyElec kernel 6.6

**Primary Sources:**
- K3s Known Issues: https://docs.k3s.io/known-issues
- K3s Requirements: https://docs.k3s.io/installation/requirements
- K3s Advanced: https://docs.k3s.io/advanced
- Kubernetes cgroup v2 docs: https://kubernetes.io/docs/concepts/architecture/cgroups/
- K3s GitHub Issue #12849 (Flannel nftables): https://github.com/k3s-io/k3s/issues/12849
- systemd 254 release: https://www.phoronix.com/news/systemd-254-Released
- systemd 255 release: https://www.theregister.com/2023/12/08/systemd_255_is_here/

---

## Table of Contents

1. [cgroup v2 in Kernel 6.6](#1-cgroup-v2-in-kernel-66)
2. [iptables-legacy vs iptables-nft](#2-iptables-legacy-vs-iptables-nft)
3. [cpuset and CPU Limits in cgroup v2](#3-cpuset-and-cpu-limits-in-cgroup-v2)
4. [Recommended sysctl Parameters for k3s on 6.6](#4-recommended-sysctl-parameters-for-k3s-on-66)
5. [systemd 254/255 Changes Relevant to Headless Server](#5-systemd-254255-changes-relevant-to-headless-server)
6. [NVMe Performance and Wear on Kernel 6.6](#6-nvme-performance-and-wear-on-kernel-66)
7. [Other k3s on Debian 13 + Kernel 6.6 Recommendations](#7-other-k3s-on-debian-13--kernel-66-recommendations)
8. [Ansible Role Impact Summary](#8-ansible-role-impact-summary)
9. [Verification Commands](#9-verification-commands)

---

## 1. cgroup v2 in Kernel 6.6

### 1.1 What Changed

| Feature | Kernel 4.19 | Kernel 6.6 |
|---------|-------------|------------|
| cgroup hierarchy | v1 (multiple hierarchies, per-controller) | v2 unified (single hierarchy at `/sys/fs/cgroup`) |
| Default mode | v1 | v2 (on systemd 232+) |
| Memory controller | Requires `cgroup_memory=1 cgroup_enable=memory` cmdline | Built in, no cmdline flag |
| cpuset controller | Requires `cgroup_enable=cpuset` cmdline | Built in as v2 controller, no cmdline flag |
| cpu controller | Available | Full `cpu.max`, `cpu.weight` interface |
| eBPF cgroup programs | Limited | Full support |
| OOM handling | Per-process | Per-cgroup with `memory.oom.group` |

### 1.2 How to Verify cgroup v2 is Active

```bash
# Method 1: filesystem type
stat -fc %T /sys/fs/cgroup/
# Returns "cgroup2fs" if v2, "tmpfs" if v1

# Method 2: mount
mount | grep cgroup
# Should show: cgroup2 on /sys/fs/cgroup type cgroup2

# Method 3: controllers
cat /sys/fs/cgroup/cgroup.controllers
# Should show: cpuset cpu io memory hugetlb pids rdma misc

# Method 4: check if memory controller is exposed
cat /proc/cgroups
# In v2 mode, this file is present but controllers are in the unified hierarchy
```

### 1.3 Cmdline Flags Relevant to cgroup Mode

| Flag | Where Used | Purpose |
|------|-----------|---------|
| `cgroup_memory=1 cgroup_enable=memory` | ONLY cgroup v1 | Enable memory controller in v1 |
| `cgroup_enable=cpuset` | ONLY cgroup v1 | Enable cpuset in v1 |
| `swapaccount=1` | ONLY cgroup v1 | Enable swap accounting in v1 |
| `systemd.unified_cgroup_hierarchy=1` | kernel cmdline | Force cgroup v2 unified mode |
| `cgroup_no_v1=all` | kernel cmdline | Disable all v1 controllers, force v2 |

**On kernel 6.6 with systemd 254+:** systemd defaults to cgroup v2 unified hierarchy. No cmdline flag is needed in most distributions. The v1-era flags (`cgroup_enable=*`) are **irrelevant and inert** in v2 mode.

**IMPORTANT:** If `/proc/cmdline` on FriendlyElec kernel 6.6 does NOT show `systemd.unified_cgroup_hierarchy=1`, check `/sys/fs/cgroup/` to confirm v2 is still active — systemd 254+ enables v2 by default even without the explicit cmdline flag if the kernel supports it.

### 1.4 k3s cgroup v2 Behavior

- k3s v1.22+ fully supports cgroup v2
- k3s + containerd auto-detect cgroup mode and set `systemd` cgroup driver automatically when v2 is active
- No explicit `--kubelet-arg=cgroup-driver=systemd` is required, but adding it explicitly is a safe configuration choice
- CPU limits (`resources.limits.cpu`) work correctly with cgroup v2 via `cpu.max` interface
- Memory limits work correctly via `memory.max` interface
- cpuset (CPU affinity) works via the `cpuset` v2 controller

### 1.5 Checking k3s cgroup Configuration

```bash
# Check what k3s reports
k3s check-config 2>&1 | grep -i cgroup

# Check containerd cgroup driver
cat /var/lib/rancher/k3s/agent/etc/containerd/config.toml | grep -i cgroup

# Verify pod-level cgroup isolation (after cluster is up)
ls /sys/fs/cgroup/kubepods.slice/
```

---

## 2. iptables-legacy vs iptables-nft

### 2.1 Official k3s Position (from docs.k3s.io/known-issues)

> "If your node uses iptables v1.6.1 or older in nftables mode you might encounter issues. We recommend utilizing newer iptables (such as 1.6.1+), or running iptables legacy mode, to avoid issues."
>
> "K3s includes a known-good version of iptables (v1.8.8) which has been tested to function properly. You can tell K3s to use its bundled version of iptables by starting K3s with the `--prefer-bundled-bin` option."

### 2.2 Current State (2025)

| Situation | Status |
|-----------|--------|
| iptables-legacy + k3s + Flannel | ✅ Fully supported, recommended |
| iptables-nft (system default) + k3s + Flannel | ⚠️ Works in theory but Flannel nftables support incomplete |
| `--prefer-bundled-bin` (k3s bundled iptables v1.8.8) | ✅ Supported, uses bundled iptables instead of system |
| Full nftables (no iptables compat layer) + Flannel | ❌ Not supported — Flannel issue #12849 still open |

**GitHub Issue #12849 ("Flannel nftables support"):** As of early 2026, k3s forces Flannel to use iptables mode even when the system uses nftables. Full nftables integration for Flannel via k3s is still in development.

### 2.3 Recommendation

**Continue using `iptables-legacy` for the NanoPC-T4 cluster.** This is still the safe and officially recommended approach.

Alternative: Add `--prefer-bundled-bin` to k3s config so k3s uses its own bundled iptables v1.8.8 regardless of system alternatives.

```yaml
# In /etc/rancher/k3s/config.yaml
prefer-bundled-bin: true
```

### 2.4 Debian 13 iptables Version

Debian 13 ships `iptables >= 1.8.9`. This is new enough for nft mode to work (1.8.5+ fixed the duplicate rules bug documented in k3s issue #3117). However, Flannel compatibility is the limiting factor, not the iptables version itself.

---

## 3. cpuset and CPU Limits in cgroup v2

### 3.1 The Problem on Kernel 4.19

On FriendlyElec kernel 4.19, `cgroup_enable=cpuset` was **absent** from the kernel cmdline. This meant:
- The cpuset controller was not enabled in cgroup v1
- Pod `resources.limits.cpu` was NOT enforced
- k3s reported warnings about missing cpuset

### 3.2 Resolution on Kernel 6.6

In cgroup v2 (unified hierarchy):
- cpuset is a built-in controller, always available
- **No cmdline flag is needed**
- `cat /sys/fs/cgroup/cgroup.controllers` should include `cpuset`
- CPU limits are enforced via `cpu.max` (the v2 equivalent, more flexible than v1)
- cpuset pin/affinity is managed per-cgroup automatically by kubelet

### 3.3 Verification

```bash
# Confirm cpuset is available in v2
cat /sys/fs/cgroup/cgroup.controllers
# Expected: cpuset cpu io memory hugetlb pids rdma misc

# After deploying a pod with CPU limits, check enforcement
# Find the pod's cgroup path
cat /sys/fs/cgroup/kubepods.slice/*/cpu.max
# Should show values like "50000 100000" for a 0.5 CPU limit
```

---

## 4. Recommended sysctl Parameters for k3s on 6.6

### 4.1 Kubernetes/k3s Mandatory

These must be set for k3s to function correctly:

```ini
# Required for Kubernetes networking
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
```

Note: `br_netfilter` module must be loaded for the bridge-nf-call parameters to take effect.

### 4.2 inotify — New Requirement for k3s (critical on 6.6)

The default inotify limits on Linux are too low for k3s. This causes "too many open files" errors and CrashLoopBackOff in controllers/operators.

```ini
# Default: 128 instances, 8192 watches — WAY too low for k3s
fs.inotify.max_user_instances = 8192    # raise from 128
fs.inotify.max_user_watches   = 524288  # raise from 8192
fs.inotify.max_queued_events  = 16384   # raise from 16384 (already fine)
```

These are especially important with cgroup v2 where the kubelet creates more cgroup hierarchies.

### 4.3 conntrack — Kernel 6.6 Improvements

Kernel 6.6 has significantly improved conntrack performance. Ensure the table is large enough:

```ini
net.netfilter.nf_conntrack_max       = 131072   # default may be too low for many pods
net.netfilter.nf_conntrack_tcp_timeout_established = 86400
net.netfilter.nf_conntrack_tcp_timeout_time_wait   = 120
```

### 4.4 Memory — vm settings

```ini
vm.overcommit_memory   = 1      # Required: k3s/kubelet expects overcommit to work
vm.overcommit_ratio    = 50     # Conservative for 4GB nodes
vm.panic_on_oom        = 0      # Don't kernel panic on OOM (let kubelet/oomd handle)
```

Note: `vm.swappiness = 0` is already in `sysctl_sdcard` conf. Keep it.

### 4.5 Kernel Panic Recovery (optional but recommended)

```ini
kernel.panic     = 10   # Auto-reboot 10s after kernel panic
kernel.panic_on_oops = 1  # Treat oops as panic to recover from hung nodes
```

### 4.6 Network Buffers (optional, for high-throughput workloads)

```ini
net.core.rmem_max          = 2097152
net.core.wmem_max          = 2097152
net.core.rmem_default      = 262144
net.core.wmem_default      = 262144
net.ipv4.tcp_rmem          = 4096 262144 2097152
net.ipv4.tcp_wmem          = 4096 262144 2097152
```

### 4.7 Parameters from sysctl_sdcard to KEEP (still valid)

```ini
vm.dirty_writeback_centisecs = 1500
vm.dirty_expire_centisecs    = 6000
vm.dirty_background_ratio    = 5
vm.dirty_ratio               = 10
vm.swappiness                = 0
```

These apply to NVMe root as much as eMMC/SD.

### 4.8 Complete Recommended /etc/sysctl.d/99-k3s.conf

```ini
# K3s / Kubernetes required settings
# Requires br_netfilter module
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1

# inotify — prevents CrashLoopBackOff in controllers
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches   = 524288
fs.inotify.max_queued_events  = 16384

# conntrack — size for larger clusters
net.netfilter.nf_conntrack_max                    = 131072
net.netfilter.nf_conntrack_tcp_timeout_established = 86400
net.netfilter.nf_conntrack_tcp_timeout_time_wait   = 120

# Memory — kubelet expects overcommit
vm.overcommit_memory = 1

# Panic recovery — auto-reboot hung nodes
kernel.panic       = 10
kernel.panic_on_oops = 1
```

---

## 5. systemd 254/255 Changes Relevant to Headless Server

### 5.1 New Services from GNOME/Wayland Image to Mask (Debian 13 / GNOME image)

In addition to services already masked (gdm, gdm3, bluetooth, triggerhappy, colord, accounts-daemon, weston):

| Service | Reason to mask |
|---------|---------------|
| `power-profiles-daemon.service` | Power profile management (GNOME Power Profiles), not needed headless |
| `fprintd.service` | Fingerprint reader daemon |
| `geoclue.service` | Geolocation service |
| `gnome-remote-desktop.service` | GNOME remote desktop, not needed |
| `packagekit.service` | GUI-driven package management |
| `gnome-initial-setup.service` | First-run GNOME wizard |
| `upower.service` | Battery/UPS monitoring |
| `ModemManager.service` | Mobile modem management |
| `cups.service` | Printing (CUPS) |
| `cups-browsed.service` | Printing discovery |
| `rtkit-daemon.service` | RealtimeKit, for audio scheduling - not needed |
| `thermald.service` | Intel thermal daemon (if present - not RK3399, skip if absent) |
| `switcheroo-control.service` | GPU switching (GNOME multi-GPU) |
| `avahi-daemon.service` | mDNS/Zeroconf (mask only if not using for cluster node discovery) |

### 5.2 Key systemd 254/255 Changes

| Change | Impact |
|--------|--------|
| SysV init scripts deprecated | Any `rc.local` or `/etc/init.d/` scripts should be converted to systemd units |
| cgroup v1 removal planned | Future systemd releases will drop v1 support — confirm v2 is active now |
| `systemctl soft-reboot` added | New: userspace-only reboot (kernel stays running), faster node recovery |
| MemoryKSM per-service | Allow KSM (Kernel Same-page Merging) per service unit, reduces RAM for similar workloads |
| Per-service memory pressure (PSI) | Granular memory pressure response per service unit |
| `systemd-oomd.service` enabled by default | OOM daemon — relevant for memory-tight nodes (RK3399 has 4 GB) |
| split-/usr removed | `/usr` merge is required — fresh Debian 13 installs have this correctly |
| PIDFD tracking | More reliable process tracking in service management |

### 5.3 systemd-oomd

`systemd-oomd.service` is now active by default on Debian 13. It uses PSI (Pressure Stall Information) to detect and kill processes/cgroups under memory pressure. Interaction with Kubernetes:

- `systemd-oomd` can kill k3s pods' cgroups if memory pressure is extreme
- Kubernetes also runs its own OOM eviction
- These can conflict on memory-constrained nodes
- **Recommendation:** Monitor `systemd-oomd` logs; consider masking it if Kubernetes OOM eviction handles memory management adequately:
  ```bash
  journalctl -u systemd-oomd -f
  ```

### 5.4 fstrim.timer

Debian 13 enables `fstrim.timer` by default. This runs TRIM weekly on all eligible filesystems. This means:
- **Do NOT add `discard` mount option** to fstab if fstrim.timer is active (double TRIM is wasteful and can add latency)
- The current fstab role uses `defaults,noatime,commit=60` — **correct, no `discard` needed**
- Verify fstrim.timer is active: `systemctl status fstrim.timer`

---

## 6. NVMe Performance and Wear on Kernel 6.6

### 6.1 I/O Scheduler

- Default scheduler for NVMe on kernel 6.6: **`none`** (bypasses I/O reordering, leaves it to hardware)
- This is optimal for NVMe SSDs and requires no configuration change
- Check: `cat /sys/block/nvme0n1/queue/scheduler` — should show `[none] mq-deadline kyber bfq`
- For latency-sensitive workloads: switch to `mq-deadline`

### 6.2 Mount Options for NVMe root (ext4)

Current fstab role applies: `defaults,noatime,commit=60`

| Option | Recommendation | Notes |
|--------|---------------|-------|
| `noatime` | ✅ Keep | Eliminates read-triggered writes |
| `commit=60` | ✅ Keep | Journal commit interval 60s (reduces NVMe writes ~5x vs default 5s) |
| `discard` | ❌ Do NOT add | fstrim.timer handles this; inline discard adds latency |
| `relatime` | (redundant) | `noatime` is stronger |
| `data=writeback` | Optional | Higher performance, less crash safety; not recommended for root |

### 6.3 Kernel 6.6 NVMe Improvements

- **io_uring `uring_cmd`:** NVMe passthrough via io_uring now supported — k3s/containerd can leverage async I/O for image operations
- **blk-mq improvements:** Multi-queue block layer CPU affinity improvements for ARM64
- **NVMe power management:** Improved APST (Autonomous Power State Transition) — relevant for power efficiency on NanoPC-T4
- **No explicit tuning needed** — these are automatic improvements

### 6.4 NVMe Write Wear Reduction

The sysctl_sdcard role settings (`vm.dirty_writeback_centisecs`, etc.) are **equally valid for NVMe** and reduce unnecessary write amplification. Keep them.

For extra wear reduction on NVMe (not SD/eMMC specific):
```ini
# Already in sysctl_sdcard, keep:
vm.dirty_background_ratio = 5
vm.dirty_ratio = 10
vm.dirty_writeback_centisecs = 1500
vm.dirty_expire_centisecs = 6000
```

---

## 7. Other k3s on Debian 13 + Kernel 6.6 Recommendations

### 7.1 Kernel Modules at Boot

k3s loads these at startup, but explicit persistence is cleaner:

```
# /etc/modules-load.d/k3s.conf
overlay
br_netfilter
```

```bash
# Verify loaded
lsmod | grep -E "overlay|br_netfilter"
```

### 7.2 containerd 2.0 (shipped with k3s v1.31.6+k3s1 and v1.32.2+k3s1)

As of February 2025 k3s releases:
- k3s includes containerd 2.0 (was 1.7)
- containerd 2.0 uses config version 3 (not version 2)
- If you have a custom containerd config template at `/var/lib/rancher/k3s/agent/etc/containerd/config-v3.toml.tmpl`, update it to v3 syntax
- If using the default template (no customization), no action needed — k3s handles this

### 7.3 k3s kubelet-arg for cgroup driver (explicit)

While auto-detected, making the cgroup driver explicit in config is recommended:

```yaml
# /etc/rancher/k3s/config.yaml (server)
kubelet-arg:
  - "cgroup-driver=systemd"   # add this
  - "container-log-max-size=10Mi"
  - "container-log-max-files=3"
  - "root-dir=/data/k3s/agent/kubelet"
```

### 7.4 Conntrack module

Ensure `nf_conntrack` is loaded (k3s loads it, but persistence matters):

```
# /etc/modules-load.d/k3s.conf
overlay
br_netfilter
nf_conntrack
```

### 7.5 Kernel Config Verification

Check that FriendlyElec kernel 6.6 has required options compiled in:

```bash
# If /proc/config.gz is available:
zcat /proc/config.gz | grep -E "CONFIG_CGROUPS|CONFIG_CGROUP_V2|CONFIG_MEMCG|CONFIG_CGROUP_CPUACCT|CONFIG_CPUSETS|CONFIG_BLK_CGROUP|CONFIG_NETFILTER|CONFIG_NF_CONNTRACK"

# Key expected values:
# CONFIG_CGROUPS=y
# CONFIG_CGROUP_V2=y  (or CONFIG_CGROUP2_FS=y)
# CONFIG_MEMCG=y
# CONFIG_CPUSETS=y
# CONFIG_CGROUP_CPUACCT=y
# CONFIG_NF_CONNTRACK=m or y
```

### 7.6 k3s check-config

k3s includes a configuration validation tool:

```bash
curl -sfL https://raw.githubusercontent.com/k3s-io/k3s/master/contrib/util/check-config.sh | bash
```

Run this before deploying on new kernel. It checks for required kernel features.

---

## 8. Ansible Role Impact Summary

| Role | Status | Required Change |
|------|--------|----------------|
| `cgroup` | ⚠️ **Update** | 1) cgroup v2 check: the warning about `cpuset` being absent is now obsolete if cgroup v2 is confirmed. 2) iptables-legacy switch: **KEEP as-is** (still correct). 3) Add cgroup v2 verification task. |
| `sysctl_sdcard` | ⚠️ **Extend** | Add a new role `sysctl_k3s` for k3s-specific parameters (inotify, conntrack, bridge-nf-call, overcommit) separate from NVMe/SD wear reduction |
| `k3s_leader` | ⚠️ **Minor update** | Add `kubelet-arg: cgroup-driver=systemd` to config template |
| `k3s_member` | ⚠️ **Minor update** | Same as k3s_leader for agent config |
| `services_headless` | ⚠️ **Extend** | Add masking of GNOME-specific services from GNOME image |
| `fstab` | ✅ **No change needed** | `noatime,commit=60` is correct. No `discard` needed (fstrim.timer handles it). |
| `boot_opts` | ✅ **No change needed** | Cmdline cannot be modified on NanoPC-T4 anyway. The v1 cgroup flags are irrelevant on 6.6. |
| `longhorn_prereqs` | ✅ **No change needed** | iscsi_tcp, dm_crypt modules still apply. |
| `swapoff` | ✅ **No change needed** | Still needed. |
| `disable_wifi` | ✅ **No change needed** | brcmfmac blacklist method unchanged. |

### New Role Candidates

| New Role | Purpose |
|----------|---------|
| `sysctl_k3s` | Deploy `/etc/sysctl.d/99-k3s.conf` with inotify, conntrack, bridge-nf-call, overcommit, panic settings |
| `kernel_modules` | Persist `overlay`, `br_netfilter`, `nf_conntrack` via `/etc/modules-load.d/k3s.conf` |

---

## 9. Verification Commands

Run these on a live node to confirm the new configuration:

```bash
# === cgroup v2 ===
stat -fc %T /sys/fs/cgroup/          # should return "cgroup2fs"
cat /sys/fs/cgroup/cgroup.controllers # should include "cpuset cpu io memory pids"
mount | grep cgroup2                  # should show cgroup2 mount

# === iptables ===
update-alternatives --display iptables | head -3  # should show iptables-legacy selected
iptables --version                                 # should show "legacy" in output

# === inotify limits ===
sysctl fs.inotify.max_user_watches    # should be >= 524288
sysctl fs.inotify.max_user_instances  # should be >= 8192

# === conntrack ===
sysctl net.netfilter.nf_conntrack_max  # should be >= 131072

# === NVMe scheduler ===
cat /sys/block/nvme0n1/queue/scheduler  # should show [none]

# === fstrim.timer ===
systemctl status fstrim.timer          # should be active

# === k3s ===
k3s check-config 2>&1 | grep -E "FAIL|WARN"  # no failures expected on 6.6

# === modules ===
lsmod | grep -E "overlay|br_netfilter"

# === systemd-oomd ===
systemctl status systemd-oomd          # note if active

# === kernel ===
uname -r                               # should show 6.6.x
cat /proc/cmdline                      # check for cgroup flags (v1 flags no longer needed)
```
