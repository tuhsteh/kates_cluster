# Task: playbook-tags
## Branch: feature/playbook-tags
## Objective: Add Ansible tags to stage.yaml so individual concern groups can be targeted with --tags / --skip-tags, avoiding a full re-run when only one layer needs updating.
## Folder: .context/tasks/playbook-tags/

## Decisions
- **Tag at role level (not play level)**: Adding `tags:` under each role entry keeps the two plays (stage_leader, stage_members) intact while still allowing per-role filtering. Play-level tags are coarser and would require duplicating plays.
- **Six tag groups**: linux, k3s, storage, registry, monitoring, selenium — matches natural concern boundaries visible in the current role list.
- **`longhorn_prereqs` tagged `storage`**: It's a dependency of Longhorn and only relevant when storage is being configured; grouping it with `longhorn` keeps `--tags storage` self-contained.

## Tag Map

| Tag | Roles (stage_leader) | Roles (stage_members) |
|-----|---------------------|----------------------|
| `linux` | bashrc, swapoff, date, mem_count, print_boot_cmdline_txt, cgroup, fstab, sysctl_sdcard, log_ramdisk, network_tmpfs, apt_hardening, services_headless, fake_hwclock, boot_opts, apt_get, ssd_mount | same set |
| `k3s` | k3s_leader | k3s_member |
| `storage` | longhorn_prereqs, longhorn | longhorn_prereqs |
| `registry` | docker_registry | — |
| `monitoring` | prometheus | — |
| `selenium` | selenium_media, selenium_grid | — |

## Key Files
- `stage.yaml` — the only file being modified; add `tags:` to each role entry

## Progress
- [x] Created task branch `feature/playbook-tags`
- [x] Add tags to stage.yaml — commit `9eadbec`; ansible-lint 0 failures, 0 warnings (39 files)
- [x] ansible-lint passes (0 failures, 0 warnings)
- [x] Created `.context/domains/ansible-playbook.md` — tag map, common invocations, ordering note — commit `cfd0a29`
- [ ] Commit task plan + push ← IN PROGRESS

## Open Questions / Blockers
- None

## Constraints
- Do not change play names, host targets, or role ordering — tags are purely additive
- ansible-lint must pass: `ansible-lint stage.yaml` (0 failures, 0 warnings)
- Follow existing Ansible patterns in the repo (no new tooling)
