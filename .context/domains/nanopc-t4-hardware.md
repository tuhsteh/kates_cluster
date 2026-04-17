# Domain: NanoPC T-4 Hardware (RK3399)

**Boards:** FriendlyELEC NanoPC T-4  
**SoC:** Rockchip RK3399 — 2× Cortex-A72 @ 2.0 GHz + 4× Cortex-A53 @ 1.5 GHz, AArch64  
**Reference:** `.context/cache/nanopc-t4-rk3399-k3s-ansible-2025-07-14.md` for full research detail

---

## OS / Distro

**Use Armbian "current" (kernel 6.6 LTS, Debian Bookworm base).**  
- Official NanoPC T-4 support; board-specific device tree included  
- cgroup v2 enabled by default  
- Same Debian/APT ecosystem as Raspberry Pi OS Bookworm  
- **Do NOT use FriendlyCore** — ships kernel 4.19, predates k3s cgroup requirements

Download: https://www.armbian.com/nanopc-t4/ (choose "current", not "edge")

---

## Boot Parameters

### Key Difference from Pi 4B

Pi OS: `/boot/firmware/cmdline.txt` — space-separated tokens on one line  
Armbian/NanoPC T-4: **`/boot/armbianEnv.txt`** — key=value format, `extraargs=` key for kernel parameters

Neither `/boot/cmdline.txt` nor `/boot/firmware/cmdline.txt` exist on Armbian. The existing `boot_opts` and `cgroup` role stat-checks will return `exists: false` on NanoPC T-4 — which is why the `board_detect` role gates are required.

### `/boot/armbianEnv.txt` Format

```ini
verbosity=1
overlay_prefix=rockchip
rootdev=UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
rootfstype=ext4
extraargs=cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory fsck.mode=skip
```

`extraargs=` is a **complete single line** — Ansible must read the current value, check for existing tokens, and write the full modified line. Do NOT blindly append.

### Diagnostic equivalent of `/boot/cmdline.txt`

```bash
cat /boot/armbianEnv.txt    # Armbian parameter file
cat /proc/cmdline           # Active kernel cmdline at runtime
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

### eMMC (OS root)

- Device: `/dev/mmcblk0`  
- OS boots from eMMC exclusively; SD card slot is available as `/dev/mmcblk1` simultaneously  
- `fstab` role regex works as-is (matches any ext4 root partition)  
- `noatime,commit=60` tuning applies equally to eMMC flash

### NVMe (data)

- PCIe x4 M.2 slot, directly on-board (no USB adapter needed)  
- Device: `/dev/nvme0n1`  
- The `ssd_mount` role detects NVMe first → works on NanoPC T-4 **unchanged**

### sysctl Tuning

`sysctl_sdcard` role values apply identically to eMMC (both are NAND flash). No changes needed.

---

## Swap

Armbian uses **zram** swap by default, not `dphys-swapfile`. The `swapoff` role needs a NanoPC-specific path:

```bash
# Disable zram swap on NanoPC T-4
systemctl stop zramswap || true
systemctl disable zramswap || true
```

---

## Networking

- **Single** Gigabit Ethernet port (Realtek PHY) — NOT dual  
- Interface name: `eth0` (standard Armbian predictable naming)  
- Armbian uses **NetworkManager** (no `dhcpcd`)  
- `network_tmpfs` role: auto-skips when `dhcpcd` is absent — no changes needed

### WiFi Disable (Persistent)

Armbian: `ifconfig wlan0 down` does NOT persist across reboots (NetworkManager brings it back). For permanent disable:

```bash
echo "blacklist brcmfmac" > /etc/modprobe.d/disable-wifi.conf
update-initramfs -u
```

The `disable_wifi` role needs a NanoPC-specific path using `modprobe.d` blacklist.

---

## k3s Requirements

### cgroup Flags

Same flags as Pi 4B, different file:
```
cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory
```
→ goes in `extraargs=` line of `/boot/armbianEnv.txt`

### iptables-legacy

Same requirement as Pi. Armbian defaults to `iptables-nft`. The `community.general.alternatives` tasks in the `cgroup` role work identically.

### VXLAN Module

Verify Armbian 6.6 LTS image includes VXLAN before deploying:
```bash
zcat /proc/config.gz | grep CONFIG_VXLAN   # expect =y or =m
```

---

## big.LITTLE Scheduling

- CPU 0–3: Cortex-A53 (efficiency, 1.5 GHz)  
- CPU 4–5: Cortex-A72 (performance, 2.0 GHz)  
- **No special kernel flags required** for k3s  
- **CPU governor:** `schedutil` (Armbian default) — optimal for mixed workloads  
- **Do NOT use `isolcpus`** on cluster worker nodes  
- EAS (Energy-Aware Scheduling) may not be fully functional on some Armbian versions — affects efficiency, not correctness

---

## Role-by-Role Impact Matrix

| Role | Pi 4B | NanoPC T-4 | Action |
|------|-------|------------|--------|
| `apt_get` | ✅ | ✅ | Unchanged |
| `apt_hardening` | ✅ | ✅ | Unchanged |
| `bashrc` | ✅ | ✅ | Unchanged |
| `boot_opts` | ✅ | ❌ | **NanoPC task** — armbianEnv.txt extraargs |
| `cgroup` (cmdline) | ✅ | ❌ | **NanoPC task** — armbianEnv.txt extraargs |
| `cgroup` (iptables) | ✅ | ✅ | Unchanged |
| `date` | ✅ | ✅ | Unchanged |
| `disable_wifi` | ✅ | ⚠️ | **Board gate** — add modprobe.d blacklist for NanoPC |
| `fake_hwclock` | ✅ | ✅ | Unchanged — already stat-conditional |
| `fstab` | ✅ | ✅ | Unchanged |
| `k3s_leader` | ✅ | ✅ | Unchanged |
| `k3s_member` | ✅ | ✅ | Unchanged |
| `log_ramdisk` | ✅ | ✅ | Unchanged |
| `longhorn` | ✅ | ✅ | Unchanged |
| `longhorn_prereqs` | ✅ | ✅ | Unchanged |
| `mem_count` | ✅ | ✅ | Unchanged |
| `network_tmpfs` | ✅ | ✅ | Unchanged — auto-skips without dhcpcd |
| `print_boot_cmdline_txt` | ✅ | ❌ | **NanoPC task** — cat armbianEnv.txt + /proc/cmdline |
| `prometheus` | ✅ | ✅ | Unchanged |
| `selenium_*` | ✅ | ✅ | Unchanged |
| `services_headless` | ✅ | ✅ | Unchanged |
| `ssd_mount` | ✅ | ✅ | Unchanged — detects nvme0n1 correctly |
| `swapoff` | ✅ | ⚠️ | **Board gate** — add zram disable for NanoPC |
| `sysctl_sdcard` | ✅ | ✅ | Unchanged — eMMC uses same tuning |

**New role required:** `board_detect` (first role in both plays)

---

## See Also

- `.context/domains/raspberry-pi-hardware.md` — Pi 4B equivalent hardware reference
- `.context/cache/nanopc-t4-rk3399-k3s-ansible-2025-07-14.md` — full research with code examples
