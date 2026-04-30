# Task: nanopc-t4-data-paths

**Branch**: feature/friendlyelec-linux-review (continuing from friendlyelec-linux-review)

## Problem

Four storage-related roles (`k3s_leader`, `k3s_member`, `longhorn_prereqs`, `longhorn`) hardcode `/mnt/ssd` as their data path. On NanoPC-T4 there is no separate SSD mount — NVMe is root (`/dev/nvme0n1p1`), and `ssd_mount` creates `/data` as a plain directory on the root filesystem. Running these roles on NanoPC-T4 would silently skip data-dir creation (wrong mount guard) and write a bogus `mnt-ssd.mount` systemd dependency.

## Approach

Mirror the pattern used in `ssd_mount` and linux-tag roles: board_platform conditionals in defaults + task-level `when` guards.

## Changes Required

### k3s_leader
- `defaults/main.yaml`: `k3s_leader_data_dir: "{{ '/data/k3s' if board_platform == 'nanopc-t4' else '/mnt/ssd/k3s' }}"`
- `tasks/main.yaml`:
  - "Create k3s data directory on SSD": change `when` to `board_platform == 'nanopc-t4' or (ansible_mounts | selectattr('mount', 'equalto', '/mnt/ssd') | list | length) > 0`
  - "Add SSD mount dependency to k3s service": add `when: board_platform == 'pi4'`

### k3s_member
- `defaults/main.yaml`: `k3s_member_data_dir: "{{ '/data/k3s' if board_platform == 'nanopc-t4' else '/mnt/ssd/k3s' }}"`
- `tasks/main.yaml`:
  - "Create k3s data directory on SSD": same `when` update
  - "Add SSD mount dependency to k3s-agent service": add `when: board_platform == 'pi4'`

### longhorn_prereqs
- `defaults/main.yaml`: `longhorn_prereqs_data_dir: "{{ '/data/longhorn' if board_platform == 'nanopc-t4' else '/mnt/ssd/longhorn' }}"`
- `tasks/main.yaml`: "Create Longhorn data directory on SSD": same `when` update

### longhorn
- `defaults/main.yaml`: `longhorn_data_dir: "{{ '/data/longhorn' if board_platform == 'nanopc-t4' else '/mnt/ssd/longhorn' }}"`
- `tasks/main.yaml`: no changes needed (tasks use `k3s_leader_data_dir` for manifest placement, not `longhorn_data_dir`)

## Key Constraints
- Pi 4B behaviour must be fully preserved
- FQCN module names throughout
- `ansible-lint` must pass 0 failures, 0 warnings (production profile)
- Do not touch any tasks not listed above

## Steps
- [ ] Implement changes (4 roles)
- [ ] ansible-lint verify
- [ ] Commit
