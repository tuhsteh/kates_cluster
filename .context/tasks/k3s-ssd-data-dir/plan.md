## Task: k3s-ssd-data-dir
## Branch: feature/k3s-ssd-data-dir
## Objective: Configure k3s on every node to store its data on the durable m.2 SSD (/mnt/ssd) instead of the SD card, while keeping logging and other frequent-write paths on tmpfs.
## Folder: .context/tasks/k3s-ssd-data-dir/

## Decisions
- **SSD approach: data-dir config (Approach A)**: Set `data-dir: /mnt/ssd/k3s` in both k3s-leader and k3s-member config templates. Rejected symlinks (brittle, complex Ansible) and bind mounts (boot ordering risk). data-dir is the canonical k3s mechanism.
- **kubelet-arg root-dir required**: `/var/lib/kubelet` is NOT under data-dir by deliberate k3s design (reverted after breaking CNI/CSI). Must add `kubelet-arg: root-dir=/mnt/ssd/k3s/agent/kubelet` to both configs. Without this, emptyDir and pod volumes write to SD card.
- **tmpfs scope: /var/log already sufficient**: /tmp is already tmpfs on Raspberry Pi OS Bookworm (systemd tmp.mount active by default). /run/k3s/containerd is hardcoded to /run which is also tmpfs. No new tmpfs Ansible config needed. The log-ramdisk role covers /var/log. User's "other frequent-write settings" are already covered by systemd defaults.
- **systemd ordering drop-in required**: k3s.service and k3s-agent.service must declare After=mnt-ssd.mount and Requires=mnt-ssd.mount. Without this, k3s can start before the SSD is mounted and create data-dir on the SD card.
- **Pre-create /mnt/ssd/k3s**: k3s auto-creates its data-dir (os.MkdirAll with 0700) but Ansible must pre-create it to prevent a race where k3s starts before the mount is ready. Mode 0700, owner root:root.
- **ssd-mount must run first**: Already enforced in stage.yaml — ssd-mount role runs before both k3s roles. data-dir configuration depends on /mnt/ssd being mounted.

## Key Files
- `roles/k3s-leader/templates/k3s-server-config.yaml.j2`: Add `data-dir: /mnt/ssd/k3s` and `kubelet-arg: root-dir=/mnt/ssd/k3s/agent/kubelet` (in addition to existing kubelet-arg log rotation entries)
- `roles/k3s-member/templates/k3s-agent-config.yaml.j2`: Same — add data-dir and kubelet-arg root-dir
- `roles/k3s-leader/tasks/main.yaml`: Add task to pre-create /mnt/ssd/k3s (mode 0700, root:root); add systemd drop-in for mnt-ssd.mount dependency
- `roles/k3s-member/tasks/main.yaml`: Same for k3s-agent service
- `stage.yaml`: No changes needed — ssd-mount ordering already correct

## Progress
- [x] Design approved — Approach A (data-dir) for SSD; /tmp + k3s scratch paths for tmpfs
- [x] Branch created: feature/k3s-ssd-data-dir
- [x] Research complete — /tmp already tmpfs on Bookworm; kubelet root-dir gap identified; systemd ordering requirement confirmed
- [x] Implement: add data-dir + kubelet root-dir to k3s config templates; pre-create /mnt/ssd/k3s; add systemd ordering drop-in
- [x] Review: @reviewer — critical bug found (token path hardcoded) and fixed; moderate/minor findings addressed
- [x] Retrospective and .context/ updates
- [x] Commit all artifacts and push; provide PR description

## Open Questions / Blockers
- kubelet-arg root-dir change may break CNI plugins that hardcode /var/lib/kubelet (k3s maintainer warning, GitHub #3802). Test with Flannel after deploy.
- No new tmpfs role needed: /tmp and /run/k3s already tmpfs on Bookworm by systemd default.

## Constraints
- All FQCNs: ansible.builtin.*, ansible.posix.*, community.general.*
- .yaml extension only (never .yml)
- Conventional Commits (feat:, fix:, chore:) — no ticket IDs
- Co-authored-by trailer required on all commits
- ssd-mount role must remain a dependency of k3s roles (already in stage.yaml ordering)
- PyYAML used for local YAML validation (Ansible not installed locally); venv at /tmp/pyyaml-venv
