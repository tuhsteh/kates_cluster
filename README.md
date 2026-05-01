
# K8s Cluster

## Hardware

- 8 × FriendlyElec NanoPC-T4 (RK3399, 4 GB RAM, 16 GB eMMC)
- 8 × NVMe SSD (root filesystem, one per board)
- 8 × microSD cards (eflasher only — not used after provisioning)
- Network switch + CAT6 cables

Nodes are named `kate0`–`kate7`. `kate0` is the k3s leader; `kate1`–`kate7` are members.
All nodes are reachable via mDNS at `<name>.local` and by static IP (see `hosts.inv`).

**Boot layout:** each board boots from eMMC (bootloader + kernel) with the root filesystem
on the NVMe. This split is handled automatically by the eflasher UI — select the NVMe
device as the root filesystem target during the flash wizard.

---

## Flashing a board

1. Write the FriendlyElec eflasher image to a microSD card (balenaEtcher or `dd`).
2. The SD card contains `eflasher.conf` at the root and an OS image directory, e.g.:

   ```
   debian-trixie-gnome-wayland-desktop-arm64/
     MiniLoaderAll.bin   idbloader.img   uboot.img   trust.img
     kernel.img          boot.img        dtbo.img    resource.img
     misc.img            rootfs.img      userdata.img
     parameter.txt       info.conf
   ```

   `eflasher.conf` example:
   ```ini
   [General]
   autoExit=false
   autoStart=/mnt/sdcard/debian-trixie-gnome-wayland-desktop-arm64
   disableLowFormatting=false
   ```

3. Insert the SD card, power on — the eflasher UI launches automatically.
4. In the UI, **select the NVMe device as the root filesystem target** (boot must stay on eMMC).
5. Flash and reboot. Remove the SD card; the board boots from eMMC into the NVMe root.

Default credentials after flash: user `pi`, password set during first boot or per FriendlyElec defaults.

---

## Software

- **OS:** Debian 13 Trixie (FriendlyElec official image, kernel 6.6, ARM64)
- **Ansible** (macOS control node — install via [Homebrew](https://brew.sh))
- **ansible-lint** (for validating playbooks before running)

### Quick start

```bash
# Install required Ansible collections
ansible-galaxy collection install -r collections/requirements.yml

# Validate playbooks
ansible-lint

# Dry run (no changes)
ansible-playbook stage.yaml -i hosts.inv --check

# Apply linux baseline to all nodes
ansible-playbook stage.yaml -t linux
```

---

## Goals

- K3s (inspiration: https://github.com/k3s-io/k3s-ansible)
- Docker registry on the cluster
- Grafana + Prometheus
- GitHub Actions for external CI; Tekton or Argo Workflows if in-cluster pipelines are needed
- Grafana Loki + Promtail (centralized logging)
- Selenium Grid (KEDA job-based autoscaling, Chromium on ARM64, local registry)
