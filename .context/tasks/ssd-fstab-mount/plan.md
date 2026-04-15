## Task: ssd-fstab-mount
## Branch: feature/ssd-fstab-mount
## Objective: Create an Ansible role that discovers the m.2 SSD on each cluster node (kate0–kate7), formats it ext4 if unformatted, and mounts it persistently at /mnt/ssd via UUID in /etc/fstab.
## Folder: .context/tasks/ssd-fstab-mount/

## Decisions
- **Mount point `/mnt/ssd`**: Generic; leaves k3s data dir untouched. Can be repurposed later.
- **Format if no filesystem (ext4)**: Safer for fresh nodes; idempotent — only formats when no filesystem is detected.
- **UUID-based fstab**: Block device names (sda, nvme0n1) are not stable across reboots on CM4. UUID is stable post-format.
- **Fail on no SSD found**: Explicit failure with clear error is preferable to silent skip; operator must know if hardware is missing.
- **All 8 nodes in scope**: Both stage_leader (kate0) and stage_members (kate1–kate7) get this role.
- **New branch off main**: Independent of k3s-leader-complete (already merged as PR #3).

## Key Files
- `roles/ssd-mount/tasks/main.yaml`: Core discovery, format, mount, fstab tasks
- `stage.yaml`: Add `ssd-mount` role to both plays

## Progress
- [x] Design decisions confirmed with user
- [x] Branch created: feature/ssd-fstab-mount
- [x] Task folder + plan.md created
- [x] Research: Ansible patterns for block device discovery, blkid UUID extraction, mkfs, ansible.posix.mount — see findings below
- [x] Implement: roles/ssd-mount/ and stage.yaml update — 10-task role created, both files YAML-valid
- [x] Review: @reviewer pass — 1 moderate (check-mode safety on blkid/UUID tasks), 2 minor (Jinja2 pattern consistency, setup comment); all applied
- [x] Commit + push — commits 6af8d9b + 64b4587 on feature/ssd-fstab-mount, pushed to origin
- [ ] User opens PR at github.com

## Open Questions / Blockers
- None. All design questions resolved.

## Research Findings (summary)
- **Device detection**: `ansible_devices` keyed by bare name (no /dev/). `rotational` is string "0"/"1" — BOTH SD and SSD report "0"; cannot use it. Boot SD card is always `mmcblk*`. NVMe SSD = `nvme*`; SATA SSD = `sd*` non-removable. Discovery: try NVMe first (select keys matching `^nvme[0-9]+n[0-9]+$`), fall back to `sd*` with `removable == "0"`. Fail if neither found.
- **Filesystem detection**: `community.general.filesystem` with `fstype: ext4` and default `force: false` — runs `blkid` internally, formats only if no FS detected. This is the only clean single-module approach; `ansible.builtin` has no mkfs module.
- **UUID extraction**: `ansible.builtin.command: blkid -s UUID -o value /dev/{{ ssd_device }}` with `changed_when: false`. Pipe stdout through `| trim`.
- **fstab + mount**: `ansible.posix.mount` with `state: mounted` (writes fstab AND mounts immediately). `opts: defaults,noatime`. Must specify `dump: "0"` and `passno: "2"` explicitly — null values cause duplicate fstab entries on re-runs.
- **Gotchas**: `mkfs.ext4 -F` required for whole-disk (not partition) format. `failed_when: false` not `ignore_errors: true` for blkid probe. Do NOT use `community.general.filesystem uuid` parameter (not idempotent).

## Constraints
- All module calls use `ansible.builtin.*` or `ansible.posix.*` FQCNs (project convention)
- All files use `.yaml` extension (never `.yml`)
- `creates:` or `when:` guards required for idempotency — no task should re-format or re-mount on every run
- Commit format: `feat: description` (Conventional Commits, no ticket IDs)
- Co-authored-by trailer required: `Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>`
