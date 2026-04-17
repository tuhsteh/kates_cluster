# Task: multi-board-support
## Branch: feature/multi-board-support
## Objective: Make the cluster playbook work on both Raspberry Pi 4B and NanoPC T-4 (RK3399) boards, detected automatically at runtime by Ansible, with board-specific behaviour gated by hardware facts.
## Folder: .context/tasks/multi-board-support/

## Phases
1. **Research** — document NanoPC T-4/RK3399 differences, OS options, Ansible detection patterns → `.context/cache/` + `.context/domains/nanopc-t4-hardware.md`
2. **Design review** — present hardware-gating approaches to user, get approval
3. **Implementation** — add board-detect role + gates to all affected roles

## Decisions
- (pending research) Which Ansible fact(s) reliably identify board type at runtime on both Pi 4B and NanoPC T-4?
- (pending research + design review) Which gating pattern to use: per-task `when:` conditions, per-platform include files, or a `board_detect` role that sets a fact used everywhere?
- (pending research) Which OS/distro for NanoPC T-4 to target (Armbian vs Ubuntu vs FriendlyElec)?

## Open Design Question: Hardware Gating Approaches

These will be formally evaluated after research, but tracked here for continuity:

### A: `board_detect` role + `when:` conditions per task (likely recommended)
- A new role runs first and sets `board_platform: pi4 | nanopc-t4` from `ansible_board_name` or `/proc/device-tree/compatible`
- Individual tasks in each role gate on `when: board_platform == 'pi4'`
- **Fits when**: Differences are scattered across many tasks within a role

### B: Per-platform task file includes
- Each role has `tasks/pi4.yaml` and `tasks/nanopc-t4.yaml`; `main.yaml` includes the right one
- **Fits when**: Roles have almost entirely different task sets per platform

### C: Inventory-driven group vars
- `board_platform` set in group_vars — requires knowing board type at inventory time
- **Fits when**: Board type is static and known; NOT dynamic runtime detection (user excluded this)

## Key Files
- `stage.yaml` — will need `board_detect` role added as first role in both plays
- `roles/board_detect/` — NEW: sets `board_platform` fact from hardware facts
- `roles/boot_opts/` — Pi-specific (`/boot/firmware/cmdline.txt`); NanoPC uses U-Boot extlinux
- `roles/print_boot_cmdline_txt/` — Pi-specific; NanoPC equivalent TBD
- `roles/ssd_mount/` — NanoPC T-4: NVMe directly on-board (PCIe), not USB adapter
- `roles/sysctl_sdcard/` — may need NanoPC eMMC tuning variant
- `roles/fake_hwclock/` — RK3399 may have RTC; verify
- `roles/cgroup/` — kernel cmdline path differs on RK3399
- `roles/apt_get/` — package list may differ (Armbian vs Raspberry Pi OS)
- `.context/domains/nanopc-t4-hardware.md` — NEW: hardware domain file

## Progress
- [x] Created branch `feature/multi-board-support` and task folder
- [ ] Research: NanoPC T-4 / RK3399 differences + Ansible detection ← IN PROGRESS (dispatched)
- [ ] Present research + design alternatives to user for approval
- [ ] Implement `board_detect` role
- [ ] Add hardware gates to all affected linux roles
- [ ] ansible-lint passes (0 failures, 0 warnings)
- [ ] Update `.context/domains/` files
- [ ] Commit + push

## Open Questions / Blockers
- What does `ansible_board_name` actually return on NanoPC T-4 hardware? (research will answer)
- Does RK3399 with Armbian report the same cgroup v2 status as Pi OS Bookworm? (research will answer)
- Does big.LITTLE scheduling require kernel cmdline flags for k3s workloads? (research will answer)
- Is `network_tmpfs` role applicable to NanoPC T-4 networking? (research will answer)
- What is the NanoPC T-4 equivalent of `/boot/firmware/cmdline.txt`? (research will answer)

## Constraints
- Detection must be dynamic at playbook runtime — no inventory-time hardcoding of board type
- Existing Pi 4B behaviour must be fully preserved — gates are additive, not replacements
- ansible-lint must pass: `ansible-lint stage.yaml` (0 failures, 0 warnings)
- Follow existing Ansible patterns (shell-based, no new collections without research justification)
