## Task: log-ramdisk
## Branch: feature/log-ramdisk
## Objective: Add a new Ansible role that mounts /var/log as a tmpfs ramdisk on every node (leader + members), preventing SD card thrashing from log writes.
## Folder: .context/tasks/log-ramdisk/

## Decisions
- **Use Ansible `mount` module (not `lineinfile` on fstab)**: The `mount` module is idempotent, manages both `/etc/fstab` persistence AND the live mount state in a single task. It won't re-mount if already mounted.
- **Mount immediately (state: mounted, not state: present)**: `present` only writes fstab without mounting. `mounted` activates it immediately — no reboot required.
- **Size 100m**: Conservative but sufficient for Raspberry Pi k3s node logs. Tmpfs only uses RAM proportional to actual data written, so 100m ceiling is a safeguard.
- **Options `defaults,noatime,nosuid,mode=0755,size=100m`**: Standard tmpfs flags — noatime prevents access-time writes; nosuid reduces attack surface; mode 0755 matches typical /var/log permissions.
- **Role extension `.yaml` (not `.yml`)**: All existing roles use `.yaml` — follow the project convention. (Exception: cgroup handler uses `.yml` — but tasks files all use `.yaml`.)
- **No dedicated handler**: Unlike the `cgroup` role, this role does not need a reboot handler because `state: mounted` handles activation immediately.
- **Add to both `stage_leader` and `stage_members`**: The SD card wear problem affects all nodes.

## Key Files
- `roles/log_ramdisk/tasks/main.yaml`: New file — the role tasks
- `stage.yaml`: Add `log_ramdisk` role to both play definitions

## Progress
- [x] Explored project structure and existing role patterns
- [x] Created branch `feature/log-ramdisk`
- [x] Created task folder `.context/tasks/log-ramdisk/`
- [x] Create `roles/log_ramdisk/tasks/main.yaml` — mount task + journald volatile task
- [x] Create `roles/log_ramdisk/handlers/main.yaml` — restart journald handler
- [x] Update `stage.yaml` — role added after `cgroup`, before `apt-get` in both plays
- [x] Code review completed — 3 moderate findings addressed (journald, leader size, opts clarity)
- [x] Commit all changes

## Open Questions / Blockers
- None. Implementation approach is clear.

## Constraints
- Raspberry Pi nodes running Raspbian/Debian — `mount` module is available
- Nodes may already have content in `/var/log` at time of playbook run; mounting tmpfs over it is intentional and safe (hides, does not delete existing on-disk logs)
- Follow existing `.yaml` extension convention for task files
