# Domain: NanoPC T-4 Hardware (RK3399)

**Boards:** FriendlyELEC NanoPC T-4  
**SoC:** Rockchip RK3399 — 2× Cortex-A72 @ 2.0 GHz + 4× Cortex-A53 @ 1.5 GHz, AArch64  
**OS Scope:** FriendlyElec official Debian 13 Core (kernel 4.19.232, FriendlyElec BSP fork `nanopi4-v4.19.y`)  
**Reference:** `.context/cache/friendlyelec-debian13-nanopc-t4-2026-04-30.md` for full research detail

---

## OS / Distro

**Use FriendlyElec official Debian 13 Core.**  
- OS: FriendlyElec official Debian 13 Core (Debian Trixie base)  
- Kernel: 4.19.232 (FriendlyElec BSP fork, `nanopi4-v4.19.y`)  
- U-Boot: Rockchip vendor fork 2017.09  
- Image filename pattern: `rk3399-XYZ-debian-trixie-core-4.19-arm64-YYYYMMDD.img.gz`  
- Default credentials: user `pi` / password `pi`; root password `fa`  
- First-boot: `sudo firstboot && sudo reboot`  
- cgroup hierarchy: v1 (default for kernel 4.19)  
- Same Debian/APT ecosystem as Raspberry Pi OS

Download: https://download.friendlyelec.com/NanoPC-T4 (select Debian Trixie core image)

---

## Boot Parameters

### Key Difference from Pi 4B

Pi OS: `/boot/firmware/cmdline.txt` — space-separated tokens, Ansible-manageable  
FriendlyElec/NanoPC T-4: **Rockchip proprietary GPT partition-based boot** — kernel cmdline is compiled into `resource.img` (partition 5 on eMMC). **Cannot be modified via Ansible.**

Neither `/boot/armbianEnv.txt` nor `/boot/extlinux/extlinux.conf` exist on FriendlyElec Debian 13 (verified on hardware). The `boot_opts` and `cgroup` roles emit a debug no-op for NanoPC T-4.

### Boot Chain

```
ROM → Miniloader/SPL → U-Boot 2017.09
    → raw kernel (eMMC partition 6)
    → DTB from resource.img (eMMC partition 5)  ← kernel cmdline compiled here
    → initrd (eMMC partition 7, ext4)
    → rootfs (eMMC partition 8, or NVMe — see Storage section)
```

### Actual Kernel Cmdline (from hardware)

```
storagemedia=emmc androidboot.storagemedia=emmc androidboot.mode=normal
androidboot.dtbo_idx=0 earlycon=uart8250,mmio32,0xff1a0000 swiotlb=1
coherent_pool=1m rw cgroup_enable=memory cgroup_memory=1
console=ttyFIQ0 consoleblank=0 root=/dev/nvme0n1p1
rootflags=discard rootfstype=ext4 bootdev=/dev/mmcblk2
```

Note: `cgroup_enable=memory cgroup_memory=1` are already present. `cgroup_enable=cpuset` is **absent** — cannot be added without kernel recompilation.

### Diagnostic Command

```bash
cat /proc/cmdline   # only option — no file to view or modify
```

---

## Ansible Board Detection

### `ansible_board_name` is EMPTY on ARM SBCs

Both Pi 4B and NanoPC T-4 return `""` for `ansible_board_name` / `ansible_product_name` — ARM boards don't expose DMI/SMBIOS data. **Do not use these facts.**

### Use `/proc/device-tree/model`

| Board | `/proc/device-tree/model` |
|-------|--------------------------|
| Raspberry Pi 4B | `Raspberry Pi 4 Model B Rev 1.x` |
| NanoPC T-4 (FriendlyARM) | `FriendlyARM NanoPC-T4` |
| NanoPC T-4 (FriendlyELEC) | `FriendlyELEC NanoPC-T4` |

Note: the string has a NUL terminator — use `| trim` in Ansible.

### `board_detect` Role

Reads `/proc/device-tree/model` and sets `board_platform: pi4 | nanopc-t4`. Must run first in every play.

```yaml
board_platform fact values:
  pi4       — Raspberry Pi 4 Model B
  nanopc-t4 — FriendlyARM/FriendlyELEC NanoPC-T4
  unknown   — assertion failure (playbook stops)
```

Gate tasks in roles:
```yaml
when: board_platform == 'pi4'       # Pi-only
when: board_platform == 'nanopc-t4' # NanoPC-only
# (no when:)                        # both boards
```

---

## Storage

### eMMC (boot device)

- Device: `/dev/mmcblk2` (NOT `/dev/mmcblk0` — that is the SD card)
- SD card: `/dev/mmcblk0`
- eMMC holds the bootloader and kernel partitions; the standard FriendlyElec layout puts rootfs at mmcblk2p8

#### eMMC Partition Layout

| Partition | Name | Type | Notes |
|-----------|------|------|-------|
| mmcblk2p1 | uboot | raw | U-Boot 2017.09 |
| mmcblk2p2 | trust | raw | ARM Trusted Firmware |
| mmcblk2p3 | misc | raw | |
| mmcblk2p4 | dtbo | raw | Device tree overlays |
| mmcblk2p5 | resource | raw | **Kernel cmdline compiled here** |
| mmcblk2p6 | kernel | raw | Raw kernel image |
| mmcblk2p7 | boot | ext4 | |
| mmcblk2p8 | rootfs | ext4 | ~2.4 GB — used when NOT booting to NVMe |
| mmcblk2p9 | userdata | ext4 | ~28.8 GB |

### NVMe (root filesystem in cluster setup)

⚠️ **The NVMe IS the root filesystem for this cluster.**

- Device: `/dev/nvme0n1`, PCIe x4 M.2 slot (directly on-board)
- `/dev/nvme0n1p1` is mounted at `/` (confirmed from `root=/dev/nvme0n1p1` in cmdline)
- eMMC boots the system, but all writable data including rootfs live on NVMe
- **The `ssd_mount` role does NOT format or mount the NVMe** — it only creates `/data` (NVMe is already root)
- Data directory: `/data` on the NVMe root (created by `ssd_mount` role)

#### k3s Data Directories

| Board | Path |
|-------|------|
| NanoPC T-4 | `/data` (on NVMe root) |
| Pi 4B | `/mnt/ssd` |

**Note:** Wiring the correct k3s data dir per board into k3s roles is a pending follow-on task.

### sysctl Tuning

`sysctl_sdcard` tuning applies to eMMC (mmcblk2) — same NAND flash characteristics as an SD card. No changes needed.

---

## Swap

FriendlyElec Debian 13 Core has **no swap at all**:

- `swapon` command is absent from the image  
- `zramswap` service does not exist  
- The `swapoff` role emits a debug no-op message for NanoPC T-4 — no action taken

---

## Networking

- **Single** Gigabit Ethernet port (Realtek PHY) — NOT dual  
- Interface name: `eth0`  
- Uses **NetworkManager** (no `dhcpcd`)  
- `network_tmpfs` role: auto-skips when `dhcpcd` is absent — no changes needed

### WiFi Disable (Persistent)

`ifconfig wlan0 down` does NOT persist across reboots (NetworkManager brings it back). The `disable_wifi` role uses a `modprobe.d` blacklist:

```bash
# /etc/modprobe.d/disable-wifi.conf
blacklist brcmfmac
blacklist brcmutil
```

`update-initramfs -u` is run conditionally if the binary is present on the image.

---

## k3s Requirements

### cgroup Flags

`cgroup_enable=memory` and `cgroup_memory=1` are **already compiled into the kernel image** — no Ansible action needed or possible.

⚠️ `cgroup_enable=cpuset` is **absent** from the kernel cmdline and cannot be added without kernel recompilation. This means pod CPU resource limits (`resources.limits.cpu`) are **not enforced** on NanoPC T-4 nodes. Memory limits work correctly.

- cgroup hierarchy: v1 (default on kernel 4.19)
- The `cgroup` role emits a debug warning for NanoPC T-4 documenting the cpuset gap; iptables tasks run for both boards.
- The `boot_opts` role is a no-op on NanoPC T-4 (`fsck.mode=skip` cannot be applied via Ansible).

### iptables-legacy

Same requirement as Pi. The `community.general.alternatives` tasks in the `cgroup` role apply identically to both boards.

### VXLAN Module

Verify the FriendlyElec 4.19 BSP image includes VXLAN:
```bash
zcat /proc/config.gz | grep CONFIG_VXLAN   # expect =y or =m
```

---

## big.LITTLE Scheduling

- CPU 0–3: Cortex-A53 (efficiency, 1.5 GHz)  
- CPU 4–5: Cortex-A72 (performance, 2.0 GHz)  
- **No special kernel flags required** for k3s  
- **CPU governor:** `schedutil` — optimal for mixed workloads  
- **Do NOT use `isolcpus`** on cluster worker nodes  
- EAS (Energy-Aware Scheduling) may not be fully functional on kernel 4.19 BSP — affects efficiency, not correctness

---

## Role-by-Role Impact Matrix

| Role | Pi 4B | NanoPC T-4 | Action |
|------|-------|------------|--------|
| `apt_get` | ✅ | ✅ | Unchanged |
| `apt_hardening` | ✅ | ✅ | Unchanged |
| `bashrc` | ✅ | ✅ | Unchanged |
| `boot_opts` | ✅ | ⚠️ | No-op — emits debug; boot params compiled into firmware |
| `cgroup` (cmdline) | ✅ | ⚠️ | No-op — flags pre-compiled; cpuset gap documented |
| `cgroup` (iptables) | ✅ | ✅ | Unchanged — runs on both boards |
| `date` | ✅ | ✅ | Unchanged |
| `disable_wifi` | ✅ | ✅ | modprobe.d blacklist (brcmfmac + brcmutil); update-initramfs conditional |
| `fake_hwclock` | ✅ | ✅ | Unchanged — already stat-conditional |
| `fstab` | ✅ | ✅ | Unchanged |
| `k3s_leader` | ✅ | ✅ | Unchanged |
| `k3s_member` | ✅ | ✅ | Unchanged |
| `log_ramdisk` | ✅ | ✅ | Unchanged |
| `longhorn` | ✅ | ✅ | Unchanged |
| `longhorn_prereqs` | ✅ | ✅ | Unchanged |
| `mem_count` | ✅ | ✅ | Unchanged |
| `network_tmpfs` | ✅ | ✅ | Unchanged — auto-skips without dhcpcd |
| `print_boot_cmdline_txt` | ✅ | ✅ | Shows `/proc/cmdline` only (armbianEnv.txt removed) |
| `prometheus` | ✅ | ✅ | Unchanged |
| `selenium_*` | ✅ | ✅ | Unchanged |
| `services_headless` | ✅ | ✅ | Unchanged |
| `ssd_mount` | ✅ | ✅ | Creates `/data` directory; does NOT format/mount NVMe (it is the root) |
| `swapoff` | ✅ | ✅ | No-op debug — no swap present on FriendlyElec image |
| `sysctl_sdcard` | ✅ | ✅ | Unchanged — eMMC uses same tuning |

---

## See Also

- `.context/domains/raspberry-pi-hardware.md` — Pi 4B equivalent hardware reference
- `.context/cache/friendlyelec-debian13-nanopc-t4-2026-04-30.md` — full FriendlyElec research with verified hardware facts
- `.context/cache/nanopc-t4-rk3399-k3s-ansible-2026-04-16.md` — earlier research (Armbian-era, for historical reference)
