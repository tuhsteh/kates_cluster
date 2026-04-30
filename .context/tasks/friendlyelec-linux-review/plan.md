# Task: friendlyelec-linux-review
## Branch: feature/friendlyelec-linux-review
## Objective: Review all linux-tagged Ansible roles and verify/correct them for FriendlyElec official Debian 13 Core images on NanoPC-T4, booting from eMMC with NVMe attached for additional system storage. The existing nanopc-t4-hardware.md was written assuming Armbian — this task audits and corrects for the FriendlyElec distro.
## Folder: .context/tasks/friendlyelec-linux-review/

## Background
- Hardware: NanoPC-T4 (RK3399), cluster assembled, boards installed
- OS: FriendlyElec official Debian 13 Core (NOT Armbian)
- Boot device: eMMC (OS root)
- Storage: NVMe attached for additional system storage (k3s data, longhorn, etc.)
- Prior work: `multi-board-support` task added board_detect + NanoPC gates, but based on Armbian assumptions

## Linux-Tagged Roles to Audit
`board_detect`, `bashrc`, `swapoff`, `date`, `mem_count`, `print_boot_cmdline_txt`,
`cgroup`, `fstab`, `sysctl_sdcard`, `log_ramdisk`, `network_tmpfs`, `apt_hardening`,
`services_headless`, `fake_hwclock`, `boot_opts`, `apt_get`, `ssd_mount`

## Research Findings (2026-04-30)
See `.context/cache/friendlyelec-debian13-nanopc-t4-2026-04-30.md` for full detail.

| Area | Armbian assumption | FriendlyElec Debian 13 reality |
|------|--------------------|-------------------------------|
| Boot config file | `/boot/armbianEnv.txt` | **Does NOT exist** — Rockchip raw-partition boot scheme |
| Possible alternative | N/A | `/boot/extlinux/extlinux.conf` — **UNVERIFIED on hardware** |
| eMMC device node | `/dev/mmcblk0` | **`/dev/mmcblk2`** ← silent data-loss risk if wrong |
| SD card device node | `/dev/mmcblk1` | `/dev/mmcblk0` |
| Kernel | 6.6 LTS (cgroup v2 default) | **4.19.y BSP** (cgroup v1 default) |
| cgroup flags needed | standard 3 flags | standard 3 flags **+ `systemd.unified_cgroup_hierarchy=0`** |
| Swap | `zramswap` service | **Likely none** (OverlayFS default) |
| NetworkManager | ✅ same | ✅ same |
| Ethernet interface | `eth0` ✅ | `eth0` ✅ |
| WiFi chip/driver | `brcmfmac` ✅ | `brcmfmac` ✅ |
| WiFi disable method | modprobe.d blacklist | modprobe.d blacklist ✅ same |
| NVMe device | `/dev/nvme0n1` ✅ | `/dev/nvme0n1` ✅ |
| Default user | `pi` ✅ | `pi` ✅ (confirmed by user) |

## Decisions
- **Boot config for cgroup/boot_opts**: `/boot/extlinux/extlinux.conf` does NOT exist. Kernel cmdline CANNOT be modified via Ansible on FriendlyElec. Replace NanoPC armbianEnv.txt tasks with informational debug messages only.
- **cgroup flags**: Already compiled into FriendlyElec image: `cgroup_enable=memory cgroup_memory=1`. Missing `cgroup_enable=cpuset` — not Ansible-manageable; documented as known gap. Iptables tasks unchanged.
- **boot_opts**: `fsck.mode=skip` cannot be added. Replace NanoPC tasks with a debug notice.
- **Swap disable (NanoPC)**: No swap at all (`swapon` absent, `zramswap` absent). Replace zramswap stop with a debug no-op.
- **ssd_mount on NanoPC**: NVMe IS the root filesystem (`/dev/nvme0n1p1`). MUST NOT format/mount the NVMe device. Add NanoPC gate: skip format/mount, create `/data` directory instead.
- **k3s data dir**: Follow-on task — update k3s roles to set `k3s_data_dir = /data` when `board_platform == 'nanopc-t4'` (out of scope for this linux review).
- **print_boot_cmdline_txt**: Remove armbianEnv.txt tasks (file absent); keep existing `/proc/cmdline` tasks which already show correct output.
- **eMMC device node**: eMMC is `/dev/mmcblk2` on FriendlyElec. Roles use dynamic device detection — no hardcoded mmcblk0 references found in any linux role.

## Hardware Verifications Required
| ID | Check | Command | Impact if absent |
|----|-------|---------|------------------|
| HV-1 | `/boot/extlinux/extlinux.conf` exists? | `ls /boot/extlinux/extlinux.conf` | **Blocks `cgroup` + `boot_opts` roles** |
| HV-2 | Actual cmdline on fresh boot | `cat /proc/cmdline` | Determines cgroup baseline state |
| HV-3 | Is OverlayFS active on rootfs? | `mount \| grep overlay` | Determines if boot config edits persist |
| HV-4 | Is swap enabled by default? | `swapon --show` | Confirms swapoff role needs |
| HV-5 | Is `update-initramfs` installed? | `which update-initramfs` | Required by `disable_wifi` role |
| HV-6 | Is `zramswap` present? | `systemctl status zramswap` | Determines whether to keep/remove zramswap stop |

## Key Files
- `roles/board_detect/` — sets board_platform fact; device-tree path should still work
- `roles/boot_opts/` — Pi: cmdline.txt; NanoPC (Armbian): armbianEnv.txt; NanoPC (FriendlyElec): TBD
- `roles/cgroup/` — same: cmdline/armbianEnv; FriendlyElec equivalent TBD
- `roles/print_boot_cmdline_txt/` — diagnostic role; NanoPC path TBD
- `roles/swapoff/` — NanoPC (Armbian): zramswap; NanoPC (FriendlyElec): TBD
- `roles/disable_wifi/` — NanoPC (Armbian): modprobe.d blacklist; FriendlyElec: TBD
- `roles/network_tmpfs/` — skips when dhcpcd absent; verify FriendlyElec network manager
- `roles/fstab/` — should be fine; verify eMMC root regex still matches
- `roles/ssd_mount/` — NVMe detection unchanged; verify path assumptions
- `.context/domains/nanopc-t4-hardware.md` — needs update from Armbian to FriendlyElec facts

## Progress
- [x] Created branch `feature/friendlyelec-linux-review` and task folder
- [x] Research: FriendlyElec Debian 13 Core specifics (cache: `nanopc-t4-2026-04-30.md`)
- [x] Explore: audited all linux-tagged roles for NanoPC/Armbian assumptions
- [x] Updated plan with research + exploration findings
- [x] Hardware verification: HV-1 absent (no extlinux.conf), HV-2 cgroup flags present, HV-3 no OverlayFS, HV-4 no swap, HV-6 no zramswap
- [x] User decision: `/data` as NanoPC data directory
- [x] Implement corrections to affected roles — ansible-lint passes 0 failures, 0 warnings
- [x] Code review — two moderate findings addressed
- [x] ansible-lint passes (0 failures, 0 warnings)
- [x] Update `.context/domains/nanopc-t4-hardware.md` with FriendlyElec-specific facts
- [x] Commit + push
- [ ] Follow-on task: update k3s roles to use `/data` on NanoPC-T4

## Open Questions / Blockers
- **BLOCKER**: Does `/boot/extlinux/extlinux.conf` exist on the boards? (HV-1) — determines whether `cgroup` and `boot_opts` roles can be Ansible-automated at all
- **BLOCKER**: Is the rootfs OverlayFS-mounted? (HV-3) — if yes, writes to `/boot/extlinux/extlinux.conf` may not survive a reboot
- Confirmed safe (no changes needed): NetworkManager ✅, eth0 ✅, NVMe device ✅, WiFi driver ✅, pi user ✅, ssd_mount role ✅, network_tmpfs role ✅

## Constraints
- Existing Pi 4B behaviour must be fully preserved — changes are additive or guarded by board_platform
- ansible-lint must pass: `ansible-lint` (0 failures, 0 warnings)
- Detection must remain dynamic at playbook runtime
- Follow existing Ansible patterns (FQCN modules, explicit booleans, quoted modes)
