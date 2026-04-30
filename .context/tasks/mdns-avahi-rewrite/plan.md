# Task: mdns-avahi-rewrite

**Branch**: feature/mdns-avahi-rewrite

## Problem

The existing `mdns` role is a non-functional stub:
- Installs no packages
- Has a broken OS-version check (`slurp` returns base64, not the distro name)
- Drops `60-enable-mdns.conf` (MulticastDNS=yes) which fights the Trixie TC decision
- systemd-resolved with mDNS enabled is resolver-only — cannot announce host; other nodes can't find it

## Approach

Avahi + Ansible-managed `/etc/hosts` hybrid:
- **Avahi** (`avahi-daemon` + `libnss-mdns`): `.local` announcement and resolution — TC-blessed
- **`/etc/hosts`**: Ansible-managed static entries for all cluster nodes — guaranteed inter-node resolution for k3s

## Key Constraints

- `allow-interfaces=eth0` MUST be set in avahi-daemon.conf before k3s adds CNI interfaces (flannel.1, cni0) — without this, avahi joins multicast on all interfaces and may respond with the CNI IP
- systemd-resolved mDNS must stay disabled (no conflict with avahi per Trixie TC decision)
- No board_platform gate — both pi4 and nanopc-t4 run Trixie and need this equally
- Interface variable: `mdns_physical_iface` (default `eth0`)
- FQCN modules, explicit booleans, quoted modes — standard project conventions
- ansible-lint must pass 0 failures 0 warnings (production profile)

## Files to Create/Modify

- `roles/mdns/tasks/main.yaml` — full rewrite
- `roles/mdns/handlers/main.yaml` — new file (restart avahi, restart systemd-resolved)
- `roles/mdns/defaults/main.yaml` — new file (mdns_physical_iface: eth0)
- `roles/mdns/files/60-enable-mdns.conf` — repurpose to set MulticastDNS=no (or delete; task handles it inline)

## Steps

- [ ] Implement role rewrite (coder)
- [ ] ansible-lint verify
- [ ] Review
- [ ] Commit
