# Ansible Playbook Structure

## Playbook Overview

`stage.yaml` is the single entry-point playbook for the entire cluster. It contains two plays that run sequentially:

| Play | Hosts | Roles run |
|------|-------|-----------|
| `Configure stage leader` | `kate0` | `linux`, `storage`, `k3s`, `registry`, `storage` (longhorn), `monitoring`, `selenium` groups |
| `Configure stage members` | `kate1`–`kate7` | `linux`, `storage` (prereqs only), `k3s` groups |

Roles within each play run in declaration order regardless of which tags are active. Tag filtering selects which roles execute, but never reorders them.

## Tag Groups

Each tag maps to a named concern. Applying a tag runs only the roles in that group, across both plays unless noted.

| Tag | Roles | Plays |
|-----|-------|-------|
| `linux` | `board_detect`, `bashrc`, `swapoff`, `date`, `mem_count`, `print_boot_cmdline_txt`, `cgroup`, `fstab`, `sysctl_sdcard`, `log_ramdisk`, `network_tmpfs`, `apt_hardening`, `services_headless`, `fake_hwclock`, `boot_opts`, `apt_get`, `ssd_mount` | both |
| `k3s` | `k3s_leader` / `k3s_member` | both |
| `storage` | `longhorn_prereqs`, `longhorn` | both — but `longhorn` only runs on `stage_leader`; members get `longhorn_prereqs` only |
| `registry` | `docker_registry` | `stage_leader` only |
| `monitoring` | `prometheus` | `stage_leader` only |
| `selenium` | `selenium_media`, `selenium_grid` | `stage_leader` only |

## Common Invocations

```bash
# Full run (all roles, all nodes)
ansible-playbook stage.yaml

# Only Selenium roles (skip OS config and k3s)
ansible-playbook stage.yaml --tags selenium

# Only leader-side Kubernetes services (registry, monitoring, selenium)
ansible-playbook stage.yaml --tags "registry,monitoring,selenium"

# Linux config only — useful after OS reinstall before k3s bootstrap
ansible-playbook stage.yaml --tags linux

# Skip linux layer — useful when cluster is already configured
ansible-playbook stage.yaml --skip-tags linux

# Storage layer only (Longhorn prereqs + install)
ansible-playbook stage.yaml --tags storage
```

## Role Ordering Within a Play

Tags filter which roles run; they do not change the order roles run in. The declaration order in `stage.yaml` is always preserved.

**`board_detect` must be first** in both plays — it sets the `board_platform` fact that all gated roles depend on. It is tagged `linux` and runs whenever the linux tag group runs.

**Example**: `--tags selenium` still executes `selenium_media` before `selenium_grid` because that is the order they appear in the `stage_leader` play. Relying on a specific execution order is safe as long as `stage.yaml` is not reordered.

This also means inter-tag dependencies are implicit. `longhorn` (tagged `storage`) runs after `k3s_leader` (tagged `k3s`) on the leader because of their relative positions in the file — not because of any explicit dependency declaration.
