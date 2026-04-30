# FriendlyElec Official Debian 13 (Trixie) Core — NanoPC-T4 Reference

**Research Date:** 2026-04-30  
**Researched By:** @researcher  
**Valid Until:** 2026-05-03 (3-day cache expiry)

**Primary Sources:**
- FriendlyElec NanoPC-T4 Wiki: https://wiki.friendlyelec.com/wiki/index.php/NanoPC-T4
- sd-fuse_rk3399 (branch: kernel-4.19): https://github.com/friendlyarm/sd-fuse_rk3399/tree/kernel-4.19
- NetworkManager wiki: https://wiki.friendlyelec.com/wiki/index.php/Use_NetworkManager_to_configure_network_settings
- kernel-rockchip repo: https://github.com/friendlyarm/kernel-rockchip (branch: nanopi4-v4.19.y)
- uboot-rockchip repo: https://github.com/friendlyarm/uboot-rockchip (branch: nanopi4-v2017.09)

---

## Table of Contents

1. [OS Image Facts](#1-os-image-facts)
2. [Boot Architecture (Critical)](#2-boot-architecture-critical)
3. [eMMC and SD Partition Layout](#3-emmc-and-sd-partition-layout)
4. [Kernel Version and cgroup Support](#4-kernel-version-and-cgroup-support)
5. [Swap Configuration](#5-swap-configuration)
6. [Network Management](#6-network-management)
7. [WiFi](#7-wifi)
8. [NVMe Storage](#8-nvme-storage)
9. [FriendlyElec vs Armbian Key Differences](#9-friendlyelec-vs-armbian-key-differences)
10. [Ansible Role Impact Analysis](#10-ansible-role-impact-analysis)
11. [Unresolved Items (Needs On-Hardware Verification)](#11-unresolved-items-needs-on-hardware-verification)

---

## 1. OS Image Facts

| Property | Value |
|----------|-------|
| OS name (directory) | `debian-trixie-core-arm64` |
| Debian version | 13 "Trixie" |
| Kernel branch | `nanopi4-v4.19.y` (FriendlyElec BSP fork of LTS 4.19) |
| U-Boot branch | `nanopi4-v2017.09` (Rockchip vendor fork) |
| Image filename pattern | `rk3399-XYZ-debian-trixie-core-4.19-arm64-YYYYMMDD.img.gz` |
| Architecture | `arm64` (AArch64) |
| First-boot tool | `sudo firstboot && sudo reboot` |
| Default user | `pi` (password: `pi`) |
| Root password | `fa` |
| Build tool repo | https://github.com/friendlyarm/sd-fuse_rk3399 branch `kernel-4.19` |

### Why Kernel 4.19 on Debian 13?
FriendlyElec maintains a BSP (board support package) kernel specifically for the RK3399 SoC. Debian 13 (Trixie) is the **userspace** only; the kernel is separately provided by FriendlyElec at version 4.19.y. This means:
- Userspace packages (systemd, libc, apt, etc.) are from Debian 13
- Kernel is FriendlyElec's vendor 4.19 with RK3399-specific drivers and patches
- systemd from Debian 13 (version ~254+) runs on kernel 4.19 — this combination can cause issues with features that require newer kernels

---

## 2. Boot Architecture (Critical)

### 2.1 Rockchip Proprietary Partition-Based Boot

**The FriendlyElec Debian 13 Core image uses Rockchip's proprietary boot scheme.** This is fundamentally different from Armbian's boot approach.

**Boot chain:**
```
ROM → Miniloader/SPL → U-Boot 2017.09 (from uboot partition)
  → Loads kernel from dedicated kernel partition (p6)
  → Loads DTB + splash from resource partition (p5)
  → Loads initrd from boot partition (p7)
  → Boots into rootfs (p8)
```

**Kernel cmdline source:**
- The kernel cmdline is **embedded in the Device Tree Source (DTS) `bootargs` property**, compiled into the `resource.img` binary in partition 5.
- There is **NO `/boot/armbianEnv.txt`** — that file is Armbian-specific and does not exist.

### 2.2 Official Methods to Change Kernel Cmdline

**Method A — Pre-install via EFlasher (recommended by FriendlyElec):**
Edit `info.conf` in the OS directory on the EFlasher SD card, adding:
```
bootargs-ext=cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory
```
This only works before installation, during the EFlasher flashing process. Not post-install.

**Method B — Recompile kernel DTS (post-install, complex):**
1. Edit `bootargs` in the board's DTS file (`arch/arm64/boot/dts/rockchip/rk3399-nanopc-t4.dts`)
2. Rebuild the kernel + resource.img
3. Flash the new `resource.img` to partition 5
This requires a cross-compilation toolchain and kernel build environment.

**Method C — `/boot/extlinux/extlinux.conf` (UNVERIFIED — check on hardware):**
FriendlyElec's U-Boot 2017.09 supports distro boot, which scans for `/boot/extlinux/extlinux.conf` in the boot partition (p7). If this file exists, it takes precedence and allows cmdline customization via a plain text APPEND line. Community sources suggest this file may exist on the running system, but this is **not documented by FriendlyElec** and must be verified on actual hardware:

```bash
# Check if extlinux.conf exists on the running system
ls -la /boot/extlinux/extlinux.conf
cat /boot/extlinux/extlinux.conf
```

If extlinux.conf exists, an example of the expected format:
```
LABEL FriendlyELEC-debian
  LINUX /Image
  INITRD /initrd.img
  FDT /rk3399-nanopc-t4.dtb
  APPEND root=/dev/mmcblk2p8 rootwait rw console=ttyFIQ0,1500000 cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory
```

**Practical implication:** The `cgroup` and `boot_opts` Ansible roles that write to `/boot/armbianEnv.txt` will NOT work on FriendlyElec images without significant modification.

### 2.3 Current Boot Parameters (Reference)

Verify actual cmdline on a running image:
```bash
cat /proc/cmdline
```

Typical expected output on FriendlyElec Debian Trixie Core:
```
console=ttyFIQ0,1500000 root=/dev/mmcblk2p8 rootwait rw earlycon=uart8250,mmio32,0xff1a0000
```

---

## 3. eMMC and SD Partition Layout

### 3.1 Device Node Assignment

| Device | Node | Notes |
|--------|------|-------|
| SD Card | `/dev/mmcblk0` | When booted from SD |
| **eMMC** | **`/dev/mmcblk2`** | ⚠️ DIFFERENT from Armbian (Armbian uses `/dev/mmcblk0`) |
| NVMe | `/dev/nvme0n1` | Same as Armbian |

### 3.2 eMMC GPT Partition Table

| Part | Name | Type | Size | Content |
|------|------|------|------|---------|
| p1 | uboot | raw | ~4 MB | U-Boot binary |
| p2 | trust | raw | ~4 MB | ARM TrustZone (BL31/BL32) |
| p3 | misc | raw | ~4 MB | Misc/recovery |
| p4 | dtbo | raw | ~4 MB | Device Tree Blob Overlays |
| p5 | resource | raw | ~4 MB | Packed DTB + boot logo (resource.img) |
| p6 | kernel | raw | ~32 MB | Kernel image |
| p7 | boot | ext4 | ~64 MB | Initrd, possibly extlinux.conf |
| **p8** | **rootfs** | **ext4** | **~2.4 GB** | **Root filesystem** |
| **p9** | **userdata** | **ext4** | **~28.8 GB** | **Remaining eMMC space** |

**Key paths:**
- Root partition: `/dev/mmcblk2p8`
- Userdata partition: `/dev/mmcblk2p9` (always present, ~28.8 GB on 32GB eMMC)
- eMMC disk: `/dev/mmcblk2`

### 3.3 SD Card Partition Layout (when booting from SD)

Same scheme but on `/dev/mmcblk0`:
- `/dev/mmcblk0p8` = rootfs
- `/dev/mmcblk0p9` = userdata

---

## 4. Kernel Version and cgroup Support

### 4.1 Kernel Details

| Property | Value |
|----------|-------|
| Version | 4.19.y (LTS) |
| Fork branch | `nanopi4-v4.19.y` |
| Source | https://github.com/friendlyarm/kernel-rockchip |
| cgroup v1 | Enabled (default) |
| cgroup v2 unified | NOT default; requires kernel cmdline `systemd.unified_cgroup_hierarchy=1` |
| Full cgroup v2 support | Requires kernel ≥ 5.2; partial on 4.19 |

### 4.2 cgroup Status for k3s

k3s requires the following kernel cmdline parameters to be active:
```
cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory
```

Optionally for swap accounting:
```
swapaccount=1
```

**Verify cgroup status on running system:**
```bash
# Check current cmdline
cat /proc/cmdline

# Check available cgroup controllers
ls /sys/fs/cgroup/

# Check if cgroup v2 is mounted
mount | grep cgroup2

# Check cgroup hierarchy used by systemd
systemctl status | head -5
```

**WARNING:** On FriendlyElec Debian 13 Core with kernel 4.19, cgroup_memory may NOT be enabled by default in the cmdline. k3s will fail at startup without it.

### 4.3 Debian 13 + Kernel 4.19 Compatibility Concern

Debian 13 (Trixie) ships systemd 254+, which expects kernel ≥ 5.x for many features. Known potential issues with this combination:
- cgroupv2 unified hierarchy may not function correctly
- Some systemd services may log warnings about unsupported kernel features
- `systemd.unified_cgroup_hierarchy=1` may not work reliably on kernel 4.19

**Recommendation for k3s:** Use cgroup v1 mode explicitly:
```
cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory systemd.unified_cgroup_hierarchy=0
```

---

## 5. Swap Configuration

### 5.1 OverlayFS on Default Image

FriendlyElec images use **OverlayFS by default** on the rootfs. The sd-fuse README explicitly notes that "Enabling Swap becomes more convenient" after disabling OverlayFS, implying swap is not easily enabled on the stock image.

**Check if OverlayFS is active:**
```bash
mount | grep overlay
cat /proc/mounts | grep overlay
```

### 5.2 Swap Status

- Default: **No swap enabled** (likely, due to OverlayFS and/or FriendlyElec's minimal OS design)
- The Debian Trixie Core "core" image is a minimal headless image that may not include zram tools
- **Not confirmed:** whether `zramswap` or `systemd-zram-generator` is installed

**Verify swap state:**
```bash
swapon --show
free -h
cat /etc/fstab | grep swap
```

**To disable swap (for k3s):**
```bash
sudo swapoff -a
sudo systemctl disable swapfile.service  # if exists
# Comment out swap lines in /etc/fstab
```

**To enable zram swap (if not present):**
```bash
sudo apt-get install zram-tools
# or
sudo apt-get install systemd-zram-generator
```

### 5.3 Disabling OverlayFS

If OverlayFS is active and interfering with swap or Docker storage drivers, disable it:
```bash
# Method depends on how FriendlyElec implements overlayfs
# Check for overlay configuration files:
ls /etc/initramfs-tools/conf.d/
cat /etc/default/overlay*  # if exists
```

---

## 6. Network Management

### 6.1 Network Manager

| Property | Value |
|----------|-------|
| Network manager | **NetworkManager** (nmcli/nmtui) |
| Ethernet interface | **`eth0`** |
| WiFi interface | `wlan0` |
| DHCP client | NetworkManager's built-in |
| dhcpcd | **NOT present** (Armbian-specific) |
| netplan | NOT present (Ubuntu-specific) |

FriendlyElec confirms all their Debian/Ubuntu images ship with NetworkManager. The wiki static IP examples use `eth0` explicitly.

### 6.2 Ethernet

- **Single GbE port** (Realtek PHY, driven by Rockchip GMAC)
- Interface: `eth0` (FriendlyElec disables predictable network names)
- Speed: 1 Gbps

### 6.3 NetworkManager Commands

```bash
# Show network status
nmcli dev status

# Show connections
nmcli connection show

# Set static IP
sudo nmcli connection modify 'Wired connection 1' \
  ipv4.method manual \
  ipv4.address "192.168.1.100/24" \
  ipv4.gateway "192.168.1.1" \
  ipv4.dns "192.168.1.1" \
  connection.autoconnect yes

# DHCP
sudo nmcli connection modify 'Wired connection 1' ipv4.method auto

# Apply
sudo nmcli connection up 'Wired connection 1'
```

---

## 7. WiFi

### 7.1 Hardware

| Property | Value |
|----------|-------|
| Chip | AP6389SV (SDIO) — Broadcom/Cypress BCM4356 |
| Standard | 802.11 a/b/g/n/ac (2.4GHz + 5GHz) |
| Bluetooth | BT 4.1 |
| Kernel driver | `brcmfmac` |
| Interface name | `wlan0` |

### 7.2 Disabling WiFi Permanently (for cluster nodes)

```bash
# Blacklist the module (survives reboots)
echo "blacklist brcmfmac" | sudo tee /etc/modprobe.d/disable-wifi.conf
echo "blacklist brcmutil" | sudo tee -a /etc/modprobe.d/disable-wifi.conf

# Update initramfs to apply blacklist at early boot
sudo update-initramfs -u

# Reboot required
sudo reboot
```

**Verify after reboot:**
```bash
lsmod | grep brcmfmac  # should return empty
ip link | grep wlan    # should return empty
```

---

## 8. NVMe Storage

### 8.1 NVMe Details

| Property | Value |
|----------|-------|
| Interface | PCIe Gen 2.1 x4, M.2 Key-M slot |
| Device node | `/dev/nvme0n1` |
| Partitions | `/dev/nvme0n1p1`, `p2`, etc. |
| Driver | Included in kernel 4.19 (native) |
| Max theoretical | ~2.5 GB/s (PCIe Gen 2 x4) |

### 8.2 NVMe Usage (Standard Linux)

```bash
# Partition
sudo fdisk /dev/nvme0n1

# Format
sudo mkfs.ext4 /dev/nvme0n1p1

# Mount
sudo mkdir -p /mnt/nvme
sudo mount /dev/nvme0n1p1 /mnt/nvme

# Persistent mount (add to /etc/fstab)
# UUID=$(sudo blkid -s UUID -o value /dev/nvme0n1p1)
# echo "UUID=$UUID /mnt/nvme ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab
```

No gotchas vs Armbian — NVMe device node is identical.

---

## 9. FriendlyElec vs Armbian Key Differences

| Feature | Armbian Bookworm | FriendlyElec Debian 13 Core |
|---------|-----------------|------------------------------|
| Kernel version | 6.6 LTS (mainline) | **4.19.y** (BSP/vendor fork) |
| U-Boot | mainline or Armbian-patched | Rockchip vendor 2017.09 |
| Boot config file | `/boot/armbianEnv.txt` | ❌ **Does NOT exist** |
| Boot partition scheme | FAT `/boot` + extlinux.conf | GPT with raw kernel/resource partitions |
| extlinux.conf | Present and used | ❓ Uncertain (may exist in p7 boot partition) |
| Kernel cmdline source | `extraargs=` in armbianEnv.txt | DTS bootargs in resource.img |
| cgroup v2 | Default (systemd + kernel 6.6) | **NOT default** (kernel 4.19 = cgroup v1) |
| eMMC device | `/dev/mmcblk0` | **`/dev/mmcblk2`** ← Critical difference |
| SD card device | `/dev/mmcblk1` | `/dev/mmcblk0` |
| Root partition | `/dev/mmcblk0p1` | `/dev/mmcblk2p8` |
| Userdata partition | N/A | `/dev/mmcblk2p9` (~28.8 GB, always present) |
| Swap | zramswap service | Likely none (OverlayFS default) |
| Network manager | NetworkManager | NetworkManager |
| Ethernet iface | `eth0` (Armbian may use predictable names) | `eth0` (FriendlyElec uses classic names) |
| WiFi iface | `wlan0` | `wlan0` |
| WiFi driver | `brcmfmac` | `brcmfmac` |
| NVMe device | `/dev/nvme0n1` | `/dev/nvme0n1` |
| `firstboot` utility | Absent | **Present** (`sudo firstboot && sudo reboot`) |
| Package manager | apt (Debian) | apt (Debian) |
| `dhcpcd` | Absent | Absent |

---

## 10. Ansible Role Impact Analysis

### Critical: `cgroup` / `boot_opts` Roles

**Problem:** These roles currently write to `/boot/armbianEnv.txt` which does NOT exist on FriendlyElec images.

**Decision tree for Ansible fix:**
```
1. On target host, check:
   stat /boot/extlinux/extlinux.conf
   
   If EXISTS:
     → Edit the APPEND line to add cgroup parameters
     → This is a plain text file, fully Ansible-compatible
   
   If NOT EXISTS:
     → Check if /boot/extlinux/ directory exists
       If dir exists but no file: create extlinux.conf from /proc/cmdline
       If dir doesn't exist: need kernel recompile (NOT Ansible-compatible)
```

**Proposed Ansible approach (with extlinux.conf):**
```yaml
- name: Check for extlinux.conf
  stat:
    path: /boot/extlinux/extlinux.conf
  register: extlinux_stat

- name: Add cgroup params to extlinux.conf
  lineinfile:
    path: /boot/extlinux/extlinux.conf
    regexp: '^\s+APPEND\s+'
    line: "  APPEND {{ current_append }} cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory"
  when: extlinux_stat.stat.exists
```

### Important: `ssd_mount` / Storage Roles

**Problem:** If Ansible hardcodes `/dev/mmcblk0` for eMMC, it will target the SD card on FriendlyElec images.

**Fix:** Use `/dev/mmcblk2` for eMMC on FriendlyElec images.

| Operation | Armbian | FriendlyElec |
|-----------|---------|--------------|
| eMMC disk | `/dev/mmcblk0` | `/dev/mmcblk2` |
| eMMC root | `/dev/mmcblk0p1` | `/dev/mmcblk2p8` |
| eMMC userdata | N/A | `/dev/mmcblk2p9` |
| NVMe | `/dev/nvme0n1` | `/dev/nvme0n1` |

### Safe Roles (No Changes Required)

| Role | Assessment | Reason |
|------|-----------|--------|
| `disable_wifi` | ✅ Safe | Same brcmfmac driver + blacklist method |
| `network_tmpfs` | ✅ Safe | Auto-skips when `dhcpcd` is absent |
| `ntp` | ✅ Safe | `chrony` or `systemd-timesyncd` work on both |
| `hostname` | ✅ Safe | Standard `/etc/hostname` method |
| `packages` | ✅ Safe | `apt` on both |
| NVMe operations | ✅ Safe | Same `/dev/nvme0n1` device node |

### Roles Requiring Changes

| Role | Problem | Required Fix |
|------|---------|--------------|
| `cgroup` | Writes `/boot/armbianEnv.txt` | Detect extlinux.conf, edit APPEND line |
| `boot_opts` | Same as above | Same fix |
| `ssd_mount` / storage | May hardcode `/dev/mmcblk0` | Use `/dev/mmcblk2` for eMMC |
| `fstab` | May reference Armbian partition paths | Update device nodes |

---

## 11. Unresolved Items (Needs On-Hardware Verification)

These items **cannot** be determined from documentation alone and must be verified on a live FriendlyElec Debian 13 Core image:

### HV-1 (HIGH PRIORITY): Does `/boot/extlinux/extlinux.conf` exist?
This is the critical gating question for Ansible k3s support.
```bash
ls -la /boot/extlinux/extlinux.conf
cat /boot/extlinux/extlinux.conf
```
**Impact:** If absent, boot parameter modification requires kernel recompilation. k3s becomes extremely difficult to configure via Ansible.

### HV-2: What does `/proc/cmdline` show?
This reveals the actual kernel cmdline on a fresh install.
```bash
cat /proc/cmdline
```
**Impact:** Tells you what cgroup parameters (if any) are already present.

### HV-3: Is OverlayFS active on the rootfs?
```bash
mount | grep overlay
# If overlay is listed with / as mountpoint, rootfs is overlayed
```
**Impact:** Affects swap, Docker storage driver choice (cannot use overlay2 on overlay2).

### HV-4: Is swap enabled by default?
```bash
swapon --show
free -h
cat /etc/fstab
```
**Impact:** Determines whether `swapoff -a` step is needed in Ansible.

### HV-5: Is zramswap or similar installed?
```bash
systemctl status zramswap 2>/dev/null || echo "not present"
systemctl status zram-config 2>/dev/null || echo "not present"
dpkg -l | grep zram
```
**Impact:** Determines disable-swap implementation in playbook.

### HV-6: Does the image have `update-initramfs`?
```bash
which update-initramfs
```
**Impact:** The `disable_wifi` role uses `update-initramfs -u`. Must be present or role needs `dracut` fallback.

---

## Appendix: Quick Reference Commands

```bash
# System info
cat /proc/cmdline               # Kernel cmdline
uname -r                        # Kernel version (should be 4.19.x)
lsb_release -a                  # Should show Debian 13 (Trixie)

# Storage
lsblk                           # Full device tree
ls /dev/mmcblk*                 # eMMC at /dev/mmcblk2
ls /dev/nvme*                   # NVMe at /dev/nvme0n1

# Network  
ip link show                    # eth0 and wlan0
nmcli dev status                # NetworkManager device status

# cgroup
ls /sys/fs/cgroup/              # Available controllers
mount | grep cgroup             # cgroup mount points
cat /proc/cgroups               # cgroup subsystems

# Boot files
ls /boot/                       # Boot directory contents
ls /boot/extlinux/ 2>/dev/null  # Check for extlinux.conf
cat /boot/extlinux/extlinux.conf 2>/dev/null || echo "not found"

# Swap
swapon --show
```
