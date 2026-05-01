# Ansible Playbook Structure

## Playbook Overview

This repository uses workload-specific top-level playbooks. Each entry point imports one or more shared playbooks from `playbooks/shared/`.

| Entry Point | Purpose | Imports |
|-------------|---------|---------|
| `minimal.yaml` | Minimal Linux baseline only | `playbooks/shared/minimal_base.yaml` |
| `exo-ai.yaml` | Linux baseline + exo/open-webui AI stack | `playbooks/shared/linux_base.yaml`, `playbooks/shared/ai_roles.yaml` |
| `k3s-cluster.yaml` | Linux baseline + full k3s platform stack | `playbooks/shared/linux_base.yaml`, `playbooks/shared/k3s_cluster_roles.yaml` |
| `selenium-grid.yaml` | Linux baseline + selenium-focused k3s stack | `playbooks/shared/linux_base.yaml`, `playbooks/shared/selenium_prereqs.yaml`, `playbooks/shared/selenium_roles.yaml` |

Shared playbooks define two plays that run sequentially:

| Play | Hosts | Roles run |
|------|-------|-----------|
| `Configure stage leader (...)` | `stage_leader` (`kate0` in current inventory) | Role groups depend on imported shared playbook |
| `Configure stage members (...)` | `stage_members` (`kate1`–`kate7` in current inventory) | Role groups depend on imported shared playbook |

Roles within each play run in declaration order regardless of which tags are active. Tag filtering selects which roles execute, but never reorders them.

## Tag Groups

Each tag maps to a named concern. Applying a tag runs only the roles in that group, across both plays unless noted. Role membership below is the current state across the shared playbooks.

| Tag | Roles | Plays |
|-----|-------|-------|
| `linux` | `board_detect`, `sudoers`, `ssh_hostkeys`, `set_hostname`, `bashrc`, `mdns`, `swapoff`, `date`, `mem_count`, `print_boot_cmdline_txt`, `cgroup` (except `minimal_base` members), `fstab`, `sysctl_sdcard`, `sysctl_k3s` (linux base only), `kernel_modules` (linux base only), `log_ramdisk`, `network_tmpfs`, `apt_hardening`, `services_headless`, `fake_hwclock`, `boot_opts`, `apt_get` | both |
| `k3s` | `k3s_leader` / `k3s_member` | both |
| `storage` | `longhorn_prereqs`, `longhorn` | both — but `longhorn` only runs on `stage_leader`; members get `longhorn_prereqs` only |
| `registry` | `docker_registry` | `stage_leader` only |
| `monitoring` | `prometheus` | `stage_leader` only |
| `selenium` | `selenium_media`, `selenium_grid` | `stage_leader` only |
| `ai` | `exo`, `open_webui` (leader only for `open_webui`) | both for `exo`, leader only for `open_webui` |
| `tools` | `iperf3` | both (`linux_base` only) |
| `ssh` | `ssh_hostkeys` | both |
| `sudoers` | `sudoers` | both |
| `mdns` | `mdns` | both |
| `mem` | `mem_count` | both |
| `tmpfs` | `log_ramdisk`, `network_tmpfs` | both |
| `headless` | `services_headless` | both |

## Common Invocations

```bash
# Minimal baseline on all nodes
ansible-playbook minimal.yaml -i hosts.inv

# AI profile (exo + open-webui)
ansible-playbook exo-ai.yaml -i hosts.inv

# Full k3s profile (storage, k3s, registry, monitoring, selenium)
ansible-playbook k3s-cluster.yaml -i hosts.inv

# Selenium profile (linux + k3s prereqs + selenium)
ansible-playbook selenium-grid.yaml -i hosts.inv

# Only Selenium roles
ansible-playbook k3s-cluster.yaml -i hosts.inv --tags selenium

# Only leader-side Kubernetes services (registry, monitoring, selenium)
ansible-playbook k3s-cluster.yaml -i hosts.inv --tags "registry,monitoring,selenium"

# Linux config only — useful after OS reinstall before k3s bootstrap
ansible-playbook k3s-cluster.yaml -i hosts.inv --tags linux

# Skip linux layer — useful when cluster is already configured
ansible-playbook k3s-cluster.yaml -i hosts.inv --skip-tags linux

# Storage layer only (Longhorn prereqs + install)
ansible-playbook k3s-cluster.yaml -i hosts.inv --tags storage
```

## Role Ordering Within a Play

Tags filter which roles run; they do not change role order. The declaration order inside each shared playbook is always preserved.

**`board_detect` must be first** in both plays — it sets the `board_platform` fact that all gated roles depend on. It is tagged `linux` and runs whenever the linux tag group runs.

**Example**: `--tags selenium` still executes `selenium_media` before `selenium_grid` because that is their order in `playbooks/shared/k3s_cluster_roles.yaml` (and in `playbooks/shared/selenium_roles.yaml` for the selenium profile).

This also means inter-tag dependencies are implicit. `longhorn` (tagged `storage`) runs after `k3s_leader` (tagged `k3s`) on the leader because of relative role order in the shared playbook, not because of an explicit dependency declaration.
