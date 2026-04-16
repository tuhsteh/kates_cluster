## Task: longhorn-storage
## Branch: feature/longhorn-storage
## Objective: Add Longhorn distributed block storage to the k3s cluster so PersistentVolumeClaims can be satisfied. Each node's mounted SSD (`/mnt/ssd`) is the backing store — replicas live at `/mnt/ssd/longhorn` on every node.
## Folder: .context/tasks/longhorn-storage/

## Decisions
- **Two-role split**: `longhorn_prereqs` (all nodes) + `longhorn` (leader only) — mirrors k3s_leader/k3s_member pattern; clean separation of OS config from cluster deploy.
- **k3s HelmChart CRD**: Drop a HelmChart resource YAML into `/mnt/ssd/k3s/server/manifests/` — k3s built-in Helm controller handles install. No `helm` or `kubectl` binary needed. `defaultDataPath` set via `valuesContent`.
- **Longhorn version**: v1.11.1 (latest stable as of 2026-03-11)
- **Packages**: `open-iscsi nfs-common cryptsetup dmsetup` — `dmsetup` is required but often missed; `jq` is NOT in official prereqs
- **iscsid**: Enable `iscsid.socket` (NOT `iscsid.service`) — Bookworm uses socket activation; `iscsid.service` will show inactive which is correct
- **Kernel modules**: `iscsi_tcp` required; `dm_crypt` included for encrypted volume support; persisted via `/etc/modules-load.d/longhorn.conf`
- **multipathd**: Disable if running — will claim Longhorn block devices and cause volume attach failures
- **HelmChart `failurePolicy: abort`**: CRITICAL — default `reinstall` will uninstall Longhorn on any failure
- **Node labels**: Not needed — all 8 nodes have SSD; Longhorn will use all nodes at `defaultDataPath` by default (`createDefaultDiskLabeledNodes` left as default false)
- **Replica count**: 3 (standard for 8-node cluster; tolerates 2 simultaneous failures)
- Longhorn data path: `/mnt/ssd/longhorn` on every node.

## Key Files
- `roles/longhorn_prereqs/tasks/main.yaml` — OS prerequisites on all nodes (packages, iscsid, iscsi_tcp module, /mnt/ssd/longhorn dir)
- `roles/longhorn/tasks/main.yaml` — Longhorn deploy on leader only (HelmChart CRD dropped into k3s manifests dir)
- `stage.yaml` — add `longhorn_prereqs` to both plays; add `longhorn` to `stage_leader` play
- `.context/domains/raspberry-pi-hardware.md` — append Longhorn storage path and prereq patterns

## Progress
- [x] Design approval from user — Approach A approved (two roles, HelmChart CRD)
- [x] Research: Longhorn v1.11.1 ARM64 prereqs + HelmChart CRD syntax — complete (see Decisions)
- [x] Create `longhorn_prereqs` role — 8 tasks: packages, modules, iscsid.socket, multipathd, data dir
- [x] Create `longhorn` role — HelmChart CRD template + 2 deploy tasks
- [x] Wire roles into `stage.yaml` — longhorn_prereqs in both plays (after ssd_mount); longhorn last in leader play
- [x] Review — 1 moderate finding fixed (removed k3s_leader_data_dir re-declaration from longhorn defaults)
- [ ] Commit ← IN PROGRESS

## Open Questions / Blockers
- User must approve design approach before implementation begins.
- Longhorn version to pin — latest stable at time of writing is v1.7.x; should confirm.

## Constraints
- All SSD-touching tasks must include the `/mnt/ssd` mount guard pattern (from retrospectives).
- No `helm` binary available — k3s HelmChart CRD or `kubectl apply` are the practical deploy options.
- k3s data-dir is `/mnt/ssd/k3s` — manifests auto-deploy dir is `/mnt/ssd/k3s/server/manifests/`.
- All role conventions follow existing patterns: `defaults/main.yaml`, `tasks/main.yaml`, `handlers/main.yaml`.
