## Task: k3s-ssd-data-dir
## Branch: feature/k3s-ssd-data-dir
## Objective: Configure k3s on every node to store its data on the durable m.2 SSD (/mnt/ssd) instead of the SD card, while keeping logging and other frequent-write paths on tmpfs.
## Folder: .context/tasks/k3s-ssd-data-dir/

## Decisions
- **SSD approach: data-dir config (Approach A)**: Set `data-dir: /mnt/ssd/k3s` in both k3s-leader and k3s-member config templates. Rejected symlinks (brittle, complex Ansible) and bind mounts (boot ordering risk). data-dir is the canonical k3s mechanism.
- **tmpfs scope: /var/log + /tmp + k3s scratch paths**: User confirmed they want /tmp and any identified k3s-specific scratch paths added to tmpfs, in addition to the already-configured /var/log ramdisk.
- **ssd-mount must run first**: Already enforced in stage.yaml — ssd-mount role runs before both k3s roles. data-dir configuration depends on /mnt/ssd being mounted.

## Key Files
- `roles/k3s-leader/templates/k3s-server-config.yaml.j2`: Add `data-dir` entry pointing to /mnt/ssd/k3s
- `roles/k3s-member/templates/k3s-agent-config.yaml.j2`: Add `data-dir` entry pointing to /mnt/ssd/k3s
- `roles/log-ramdisk/tasks/main.yaml`: Likely target for /tmp tmpfs and any k3s scratch tmpfs mounts (or a new companion role)
- `stage.yaml`: Verify role ordering remains correct (ssd-mount before k3s roles)

## Progress
- [x] Design approved — Approach A (data-dir) for SSD; /tmp + k3s scratch paths for tmpfs
- [x] Branch created: feature/k3s-ssd-data-dir
- [ ] Research: identify k3s-specific write-heavy/scratch paths and /tmp tmpfs pattern for Raspberry Pi OS Bookworm ← IN PROGRESS
- [ ] Implement: add data-dir to k3s config templates; ensure /mnt/ssd/k3s directory is created
- [ ] Implement: extend tmpfs config for /tmp and any identified k3s scratch paths
- [ ] Review: @reviewer over all changes
- [ ] Retrospective and .context/ updates
- [ ] Commit all artifacts and push; provide PR description

## Open Questions / Blockers
- Does k3s need a pre-created data-dir with specific permissions, or does it create it on first start? (Researcher to confirm)
- Are there k3s-specific paths under /tmp or elsewhere (beyond data-dir) that generate high write volume? (Researcher to identify)
- Does Raspberry Pi OS Bookworm already mount /tmp as tmpfs by default? If so, /tmp config may be a no-op. (Researcher to confirm)
- Where is the cleanest place to add the /tmp tmpfs mount — extend log-ramdisk role, or create a separate os-tmpfs-mounts role? (Decide after research)

## Constraints
- All FQCNs: ansible.builtin.*, ansible.posix.*, community.general.*
- .yaml extension only (never .yml)
- Conventional Commits (feat:, fix:, chore:) — no ticket IDs
- Co-authored-by trailer required on all commits
- ssd-mount role must remain a dependency of k3s roles (already in stage.yaml ordering)
- PyYAML used for local YAML validation (Ansible not installed locally); venv at /tmp/pyyaml-venv
