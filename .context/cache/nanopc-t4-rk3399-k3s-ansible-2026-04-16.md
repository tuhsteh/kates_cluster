# NanoPC T-4 / RK3399 on k3s — Research Cache

**Research Date:** 2026-04-16
**Researched By:** @researcher
**Task:** multi-board-support — evaluate replacing Pi 4B nodes with NanoPC T-4 in k3s Ansible cluster

---

## Table of Contents

1. [Hardware Specifications](#hardware-specifications)
2. [OS / Distro Selection](#os--distro-selection)
3. [Boot Parameter Management](#boot-parameter-management)
4. [Ansible Board Detection](#ansible-board-detection)
5. [RTC / fake-hwclock](#rtc--fake-hwclock)
6. [Cgroup / k3s Configuration](#cgroup--k3s-configuration)
7. [iptables-legacy vs nftables on Armbian](#iptables-legacy-vs-nftables-on-armbian)
8. [big.LITTLE CPU Scheduling](#biglittle-cpu-scheduling)
9. [eMMC / NVMe Device Paths](#emmc--nvme-device-paths)
10. [eMMC Sysctl Tuning](#emmc-sysctl-tuning)
11. [Networking](#networking)
12. [Swap Management on Armbian](#swap-management-on-armbian)
13. [Armbian-Specific Services](#armbian-specific-services)
14. [k3s Known Issues on RK3399/Armbian](#k3s-known-issues-on-rk3399armbian)
15. [Sources](#sources)

---

## Hardware Specifications

**NanoPC T-4:**
- SoC: Rockchip RK3399 (2× Cortex-A72 @ 2.0 GHz + 4× Cortex-A53 @ 1.5 GHz)
- RAM: 4 GB dual-channel LPDDR3-1866
- Storage: 16/32/64 GB eMMC (onboard), microSD slot (up to 128 GB)
- PCIe: M.2 M-Key PCIe x4 slot (NVMe SSD support)
- Ethernet: **SINGLE** Gigabit Ethernet (Realtek PHY) — NOT dual Ethernet
- WiFi/BT: 802.11ac, Bluetooth 4.1 (AP6389SV/BCM4356 chipset)
- Power: 12 V/2 A
- RTC: RK3399 SoC has built-in RTC; board has a 2-pin JST RTC battery header (CR2032 or similar)
- No `/boot/firmware/` directory; no `/boot/cmdline.txt`

**Raspberry Pi 4B (for comparison):**
- SoC: BCM2711 (4× Cortex-A72 @ 1.8 GHz)
- RAM: 2/4/8 GB LPDDR4
- Storage: microSD card boot; USB 3.0 for external SSD
- Ethernet: Single Gigabit Ethernet (USB-attached inside BCM2711)
- WiFi/BT: 802.11ac, Bluetooth 5.0
- Power: 5 V/3 A USB-C
- No hardware RTC
- Boot via `/boot/firmware/cmdline.txt` (Bookworm) or `/boot/cmdline.txt` (older)

---

## OS / Distro Selection

### Viable Options

| OS                     | Base             | Kernel      | k3s Suitability | Notes |
|------------------------|------------------|-------------|-----------------|-------|
| **Armbian (recommended)** | Debian Bookworm / Ubuntu Noble 24.04 | 6.6–6.18 LTS | ✅ Best | Official community images, active maintenance |
| FriendlyElec FriendlyCore | Ubuntu LTS       | 4.19/5.15   | ⚠ Outdated kernel | Older kernels; lacks cgroup v2 default |
| FriendlyElec FriendlyWrt | OpenWrt          | 5.x–6.x     | ❌ Not for k3s | Router/firewall use only |
| Vanilla Debian Bookworm  | Debian 12        | 6.1.x       | ✅ Viable | Less SBC-specific patches; more DIY |
| Vanilla Ubuntu 24.04 LTS | Ubuntu Noble     | 6.8.x       | ✅ Viable | Same caveats as Vanilla Debian |

### Recommended: Armbian with Debian Bookworm or Ubuntu Noble base

**Rationale:**
- Armbian current stable uses kernel 6.6 LTS (tagged "current") which is actively maintained for RK3399
- NanoPC T-4 has official Armbian support: https://www.armbian.com/nanopc-t4/
- Matches the Debian Bookworm base of Raspberry Pi OS (same APT ecosystem)
- Armbian provides board-specific patches and device tree that mainline images lack
- FriendlyCore ships kernel 4.19 which is too old for cgroup v2 and modern k3s

**Cgroup v2 Status:**
- Armbian kernel 6.x with systemd v247+ enables cgroup v2 **by default** (unified hierarchy)
- Verify: `mount | grep cgroup2` should show `cgroup2 on /sys/fs/cgroup`
- Legacy cgroup v1 flags (`cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory`) are still required for memory accounting and cpuset controllers in both v1 and v2 modes
- On Armbian, these flags go in `/boot/armbianEnv.txt` as `extraargs=` rather than in `/boot/cmdline.txt`

---

## Boot Parameter Management

### The Key Difference: No `/boot/cmdline.txt` on Armbian

On Raspberry Pi OS (Bookworm): `/boot/firmware/cmdline.txt` or `/boot/cmdline.txt`
On Armbian/RK3399: **neither of these files exist**.

### Armbian's Two Mechanisms

**1. `/boot/armbianEnv.txt` — RECOMMENDED for Ansible**

The Armbian-native method. Contains board config variables and an `extraargs=` key for appending kernel cmdline parameters.

```
# /boot/armbianEnv.txt typical structure
verbosity=1
bootlogo=false
console=serial
overlay_prefix=rockchip
rootdev=UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
rootfstype=ext4
extraargs=cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory fsck.mode=skip
```

Armbian's boot script reads this file and appends `extraargs` to the kernel command line. Survives Armbian package upgrades. This is the **preferred and documented Armbian method**.

**2. `/boot/extlinux/extlinux.conf` — fallback/alternative**

```
# /boot/extlinux/extlinux.conf
LABEL Armbian
    LINUX /Image
    INITRD /uInitrd
    FDT /dtb/rockchip/rk3399-nanopc-t4.dtb
    APPEND root=UUID=xxxx rootwait console=tty1 console=ttyS2,1500000n8
```

If this file exists AND the U-Boot is configured to use it, the APPEND line controls the kernel cmdline directly. However, the presence of extlinux.conf does NOT mean armbianEnv.txt is ignored — behavior depends on U-Boot version.

**Precedence:** extlinux.conf APPEND > armbianEnv.txt extraargs (if both exist)

### Ansible Idiomatic Approach

Detect presence of armbianEnv.txt (primary target) and extlinux.conf (secondary):

```yaml
# Detect which boot file to modify
- name: Stat armbianEnv.txt
  ansible.builtin.stat:
    path: /boot/armbianEnv.txt
  register: nanopc_armbian_env

- name: Stat extlinux.conf
  ansible.builtin.stat:
    path: /boot/extlinux/extlinux.conf
  register: nanopc_extlinux

# Set boot parameter via armbianEnv.txt (preferred)
- name: Add cgroup params to armbianEnv.txt extraargs
  ansible.builtin.lineinfile:
    path: /boot/armbianEnv.txt
    regexp: '^extraargs='
    line: 'extraargs=cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory fsck.mode=skip'
    create: false
  when:
    - nanopc_armbian_env.stat.exists
  notify: reboot
```

**Note:** The `extraargs=` line in armbianEnv.txt is a complete replacement of all extra args. Use a single idempotent line that includes ALL required parameters. Do NOT try to do individual `backrefs` substitutions like the Pi cmdline.txt approach — it's one key=value line.

### Does `/boot/cmdline.txt` exist on Armbian?

No. The existing `boot_opts` and `cgroup` role logic (checking for `/boot/firmware/cmdline.txt`, falling back to `/boot/cmdline.txt`) will NOT find a matching file on an Armbian NanoPC T-4. The `stat` check will return `exists: false` for both paths. Adding NanoPC T-4 support requires a separate code path in those roles.

---

## Ansible Board Detection

### Critical Finding: `ansible_board_name` is UNRELIABLE on ARM Boards

ARM boards (both Pi 4B and NanoPC T-4) do not populate DMI/SMBIOS data. The file `/sys/class/dmi/id/board_name` is typically empty or absent on ARM SBCs. This means `ansible_board_name`, `ansible_product_name`, and related DMI-derived facts **will be empty** on both boards.

This has been confirmed by Ansible issue #42632 and multiple community reports.

### Reliable Detection Method: `/proc/device-tree/model`

Both boards populate `/proc/device-tree/model` from the device tree blob.

| Board | `/proc/device-tree/model` | Notes |
|-------|--------------------------|-------|
| Raspberry Pi 4B | `Raspberry Pi 4 Model B Rev 1.x` | Revision suffix varies |
| NanoPC T-4 | `FriendlyARM NanoPC-T4` | Sometimes `FriendlyELEC NanoPC-T4` depending on image |

The string includes a NUL terminator byte at the end, so use `| trim` in Ansible.

### `/proc/device-tree/compatible`

For NanoPC T-4:
```
friendlyarm,nanopc-t4\0rockchip,rk3399
```
Read as: `cat /proc/device-tree/compatible | tr '\0' '\n'`

For Raspberry Pi 4B:
```
raspberrypi,4-model-b\0brcm,bcm2711
```

### Recommended `board_detect` Role Pattern

```yaml
# roles/board_detect/tasks/main.yaml

- name: Read /proc/device-tree/model
  ansible.builtin.slurp:
    src: /proc/device-tree/model
  register: board_detect_dt_model
  failed_when: false

- name: Set board_model fact from device tree
  ansible.builtin.set_fact:
    board_detect_model: "{{ board_detect_dt_model.content | b64decode | trim }}"
  when: board_detect_dt_model.content is defined

- name: Set board_model fact fallback (no device tree)
  ansible.builtin.set_fact:
    board_detect_model: "unknown"
  when: board_detect_dt_model.content is not defined

- name: Set board_platform fact
  ansible.builtin.set_fact:
    board_platform: >-
      {%- if 'Raspberry Pi 4' in board_detect_model -%}pi4
      {%- elif 'NanoPC-T4' in board_detect_model or 'NanoPC T4' in board_detect_model -%}nanopc-t4
      {%- else -%}unknown
      {%- endif -%}

- name: Assert board_platform was detected
  ansible.builtin.assert:
    that: board_platform != 'unknown'
    fail_msg: >
      Board not recognised: '{{ board_detect_model }}'.
      Supported boards: Raspberry Pi 4, NanoPC-T4 (FriendlyARM/FriendlyELEC).
```

Then in all other roles:
```yaml
when: board_platform == 'pi4'       # Pi-only tasks
when: board_platform == 'nanopc-t4' # NanoPC-only tasks
# (omit 'when:' for tasks that apply to both)
```

---

## RTC / fake-hwclock

### NanoPC T-4 RTC Situation

- **RK3399 SoC** has a built-in hardware RTC
- **NanoPC T-4** has a 2-pin JST RTC battery header (for a CR2032 coin cell backup battery)
- **Without battery installed:** RTC loses time on power off; behaves like no functional RTC
- **With battery installed:** Full working hardware RTC; `/dev/rtc0` is present; `hwclock -r` works

### Armbian and fake-hwclock

- Armbian **does install `fake-hwclock`** by default on NanoPC T-4 (regardless of RTC battery)
- This is because fake-hwclock is a safety net for when RTC is not battery-backed
- The existing `fake_hwclock` role checks `stat /etc/cron.hourly/fake-hwclock` before acting — **already idempotent and safe on Armbian**
- The role will simply skip if fake-hwclock is not installed (exists check returns false)

### Recommendation

The `fake_hwclock` role **needs no changes** — it already uses conditional execution. Armbian likely installs fake-hwclock so the role will apply correctly.

If a battery is installed in the RTC header, the ideal follow-up would be:
1. Remove fake-hwclock: `apt remove fake-hwclock`
2. Sync RTC from NTP: `hwclock -w`

But for the Ansible playbook, the current role is safe as-is.

---

## Cgroup / k3s Configuration

### Required Kernel Parameters (same as Pi)

```
cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory
```

These are required for k3s memory accounting and cpuset management on both Pi OS and Armbian.

### How to Apply on Armbian (NanoPC T-4)

Edit `/boot/armbianEnv.txt`:
```
extraargs=cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory
```

### cgroup v2 on Armbian

Armbian with kernel 6.x + systemd v247+ uses cgroup v2 (unified hierarchy) by default. To explicitly enable:
```
extraargs=cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory systemd.unified_cgroup_hierarchy=1
```

Check active mode:
```bash
mount | grep cgroup2   # should show cgroup2 on /sys/fs/cgroup
```

### fsck.mode=skip equivalent

Same parameter applies. On Armbian add to `extraargs=` in armbianEnv.txt.

---

## iptables-legacy vs nftables on Armbian

### Default on Armbian (2024)

Armbian based on Debian Bookworm or Ubuntu Noble defaults to `iptables-nft` (nftables backend with iptables compatibility layer). The iptables binary points to iptables-nft.

```bash
sudo iptables --version
# Shows: iptables v1.x.x (nf_tables)
```

### k3s Requirement

k3s (particularly with flannel VXLAN CNI) works best with `iptables-legacy`. The existing `cgroup` role already handles this via `community.general.alternatives`. **This role works correctly on Armbian — same commands, same effect.**

```bash
sudo update-alternatives --set iptables /usr/sbin/iptables-legacy
sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
```

Verify:
```bash
sudo iptables --version
# Should show: iptables v1.x.x (legacy)
```

---

## big.LITTLE CPU Scheduling

### RK3399 Core Layout

- CPU 0–1: Cortex-A53 (LITTLE, 1.5 GHz)
- CPU 2–5: Cortex-A72 (big, 2.0 GHz)
- Wait — actual layout: CPU 0-3 = A53, CPU 4-5 = A72

Confirm on a running board:
```bash
cat /proc/cpuinfo | grep 'CPU part'
# 0xd03 = A53, 0xd08 = A72
```

### k3s Scheduling

k3s (and Kubernetes in general) is **unaware of big.LITTLE topology by default**. The scheduler will use all cores equally. No special kernel flags are required for k3s to function correctly on RK3399.

### Governor Recommendation

Use `schedutil` (default on modern kernels) which dynamically scales frequency based on scheduler hints:
```bash
cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
# Should show 'schedutil'
```

To set permanently via sysctl/udev if needed:
```bash
echo schedutil | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
```

### No `isolcpus` Needed

For a k3s worker node, `isolcpus` is not recommended — it reduces the number of CPUs available to k3s and all system processes. Skip this unless you have a specific latency-critical workload.

### Known Scheduling Issue

On some kernel versions, the EAS (Energy-Aware Scheduling) for big.LITTLE may not work optimally with all Armbian kernels. This does not affect correctness, only efficiency. `schedutil` mitigates this.

---

## eMMC / NVMe Device Paths

### eMMC

On NanoPC T-4 Armbian:
- **eMMC → `/dev/mmcblk0`** (almost always — eMMC is the first MMC controller)
- **SD Card → `/dev/mmcblk1`** (when inserted)
- Partitions: `/dev/mmcblk0p1`, `/dev/mmcblk0p2`, etc.

**Verify on running hardware:**
```bash
lsblk -o NAME,SIZE,TYPE,MODEL
```

### NVMe (M.2 PCIe)

- **NVMe → `/dev/nvme0n1`** (consistent when only one NVMe device present)
- Partitions: `/dev/nvme0n1p1`, etc.

### Impact on `ssd_mount` Role

The existing `ssd_mount` role detects `nvme[0-9]+n[0-9]+` first, then falls back to `sd[a-z]+`. **This works correctly on NanoPC T-4 with no changes required.** NVMe shows up as `nvme0n1` exactly as the role expects.

### fstab root partition

The `fstab` role regex `'^(\S+\s+/\s+ext4\s+)\S+(\s+\d+\s+\d+\s*)$'` works on any ext4 root mount. If Armbian uses ext4 for root (the default), the `noatime,commit=60` addition works correctly. Confirm Armbian root is ext4 (not btrfs):
```bash
mount | grep ' / '
```

---

## eMMC Sysctl Tuning

### Current Values (from `sysctl_sdcard` role)

```
vm.dirty_writeback_centisecs=1500   # 15s (default: 5s)
vm.dirty_expire_centisecs=1500      # 15s (default: 30s)
vm.dirty_ratio=60
vm.dirty_background_ratio=2
```

### Do These Apply to eMMC?

Yes. eMMC behaves like NAND flash and benefits from the same write-coalescing approach as SD cards. The tunings are appropriate.

**Note on `dirty_expire_centisecs=1500`:** The current value (15s) is actually lower than the default (30s). For maximum wear reduction, higher values like 30000–60000 centiseconds would be better, but introduce more data loss risk on power failure. The current values represent a balanced choice — they apply equally well to eMMC.

### Rename Suggestion (non-blocking)

The role is named `sysctl_sdcard` but applies equally to eMMC. Consider renaming to `sysctl_flash_storage` when doing the multi-board refactor, but this is cosmetic — the role is functionally correct for both.

---

## Networking

### NanoPC T-4 Network Interfaces

| Interface | Type | Details |
|-----------|------|---------|
| `eth0` (or `enp1s0`) | Gigabit Ethernet | Realtek PHY, single port |
| `wlan0` | WiFi | AP6389SV (BCM4356), 802.11ac |

**IMPORTANT:** NanoPC T-4 has ONLY ONE Ethernet port. Not dual Ethernet. There is no second physical Ethernet without adding a USB or PCIe adapter.

### Network Manager on Armbian

Armbian defaults to **NetworkManager** (not dhcpcd, not dhclient, not systemd-networkd). This matters for:

1. **`network_tmpfs` role:** The role checks `which dhcpcd` and mounts `/var/lib/dhcp` as tmpfs if dhcpcd is found. On Armbian, dhcpcd is **NOT installed** → the role's `when: network_tmpfs_dhcpcd_which.rc == 0` condition evaluates to false → **role safely skips the tmpfs mount on NanoPC T-4**. No changes needed.

2. **`disable_wifi` role:** Currently runs `ifconfig wlan0 down`. NanoPC T-4 has WiFi (`wlan0` or similar). The interface is present but the command is not idempotent and does not persist across reboots. For Armbian, the correct approach is blacklisting `brcmfmac` driver or configuring NetworkManager to ignore it. The current Pi approach (`ifconfig wlan0 down`) will work immediately but will NOT persist on reboot on Armbian. This role needs a board-specific path.

### Interface Naming

Armbian uses standard Linux predictable interface naming. The single Ethernet port is typically `eth0` on NanoPC T-4. On Raspberry Pi OS, the Ethernet is also `eth0`. Interface naming should not cause issues with k3s CNI.

---

## Swap Management on Armbian

### Key Difference from Pi OS

| System | Default Swap |
|--------|-------------|
| Raspberry Pi OS | `dphys-swapfile` (creates `/var/swap` file on storage) |
| Armbian | `zram-config` (compressed RAM, `/dev/zram0`) |

### Impact on `swapoff` Role

The current `swapoff` role:
1. `swapoff -a` — works correctly on both
2. `apt remove dphys-swapfile --purge` — dphys-swapfile is **NOT installed on Armbian** by default; `apt remove` of a non-installed package is idempotent (no-op) — safe
3. `rm -f /var/swap` — file does not exist on Armbian — safe (file task with `state: absent` is idempotent)

However, Armbian uses **zram** for swap which k3s may also want disabled. To also disable zram on NanoPC T-4:
```bash
systemctl disable armbian-zram-config
systemctl stop armbian-zram-config
swapoff /dev/zram0
```

This is a **NanoPC-specific addition** needed in the `swapoff` role.

---

## Armbian-Specific Services

### Comparison: `services_headless` Role

| Service | Pi OS | Armbian/NanoPC T-4 | Role Impact |
|---------|-------|-------------------|-------------|
| `triggerhappy.service` | Present, may run | Present on Armbian (may already be masked) | Role uses `failed_when: false` — safe |
| `bluetooth.service` | Present | Present (AP6389SV has BT) | Role uses `failed_when: false` — safe |
| `hciuart.service` | Present | May not exist on Armbian | Role uses `failed_when: false` — safe |

The `services_headless` role is already safe on Armbian due to `failed_when: false`. All three services will be masked if they exist, silently skipped if they don't.

### Armbian-Specific Services to Consider Masking (not in current roles)

- `armbian-zram-config.service` — creates zram swap (see swapoff above)
- `armbian-firstrun.service` — runs on first boot only, safe to ignore after
- `armbian-hardware-monitor.service` — harmless but not needed for k3s

---

## k3s Known Issues on RK3399/Armbian

### 1. VXLAN Kernel Module

Flannel's default backend is VXLAN. The `vxlan` kernel module must be present:
```bash
zcat /proc/config.gz | grep -i vxlan
# Should show CONFIG_VXLAN=y or CONFIG_VXLAN=m
modinfo vxlan   # confirm module is loadable
```

Armbian current (6.6 LTS) kernels for RK3399 typically include VXLAN. Verify before deploying.

### 2. Kernel Version Stability

- Kernel 5.10 LTS = historically stable for RK3399 on Armbian
- Kernel 6.x = generally works but some sub-versions have had issues (HDMI, eMMC init)
- Recommendation: Use Armbian's "current" (6.6 LTS) or "edge" with tested version. Avoid bleeding edge for cluster nodes.

### 3. eMMC Boot vs SD Card Boot

Armbian for NanoPC T-4 can boot from SD card or eMMC. Flash the image to eMMC for production use. U-Boot on eMMC is more reliable for headless cluster operation than SD card.

### 4. No Hardware Floating Point Differences

RK3399 (Cortex-A72/A53) is ARMv8 AArch64 — same architecture as BCM2711 on Pi 4B. k3s ARM64 binary runs identically on both.

---

## Sources

- Armbian NanoPC T-4 official page: https://www.armbian.com/nanopc-t4/
- Armbian Advanced Features docs: https://docs.armbian.com/User-Guide_Advanced-Features/
- FriendlyELEC NanoPC T-4 product page: https://www.friendlyelec.com/index.php?route=product/product&product_id=225
- Armbian kernel parameter guide: https://docs.armbian.com/User-Guide_Advanced-Features/#how-to-add-kernel-parameters
- k3s advanced docs (cgroups): https://rancher.com/docs/k3s/latest/en/advanced/#cgroup-management
- k3s networking docs: https://docs.k3s.io/networking/basic-network-options
- Ansible issue #42632 (board_name empty on ARM): https://github.com/ansible/ansible/issues/42632
- RK3399 device tree bindings: https://elixir.bootlin.com/linux/latest/source/Documentation/devicetree/bindings/arm/rockchip.yaml
- TechInfoDepot NanoPC T-4: https://techinfodepot.shoutwiki.com/wiki/FriendlyARM_NanoPC-T4
