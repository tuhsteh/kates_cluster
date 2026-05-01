
# K8s Cluster

## Table Of Contents

- [Hardware](#hardware)
- [Flashing a board](#flashing-a-board)
- [Software](#software)
- [Goals](#goals)

## Context Docs

- [.context/domains/ansible-playbook.md](.context/domains/ansible-playbook.md)
- [.context/domains/nanopc-t4-hardware.md](.context/domains/nanopc-t4-hardware.md)
- [.context/domains/raspberry-pi-hardware.md](.context/domains/raspberry-pi-hardware.md)
- [.context/domains/rpi5-vs-nanopc-t4-llm.md](.context/domains/rpi5-vs-nanopc-t4-llm.md)
- [.context/standards/ansible-gotchas.md](.context/standards/ansible-gotchas.md)
- [.context/standards/ai-tooling-strategy.md](.context/standards/ai-tooling-strategy.md)

## Hardware

- 8 × FriendlyElec NanoPC-T4 (RK3399, 4 GB RAM, 16 GB eMMC)
- 8 × NVMe SSD (root filesystem, one per board, ~250GB each)
- 1 x microSD card (eflasher only — not used after provisioning)
- Network switch(es) + CAT6 cables

Nodes are named `kate0`–`kate7`. `kate0` is the k3s leader; `kate1`–`kate7` are members.
All nodes are reachable via mDNS at `<name>.local` and by static IP (see `hosts.inv`).

**Boot layout:** each board boots from eMMC (bootloader + kernel) with the root filesystem
on the NVMe. This split is handled automatically by the eflasher UI — select the NVMe
device as the root filesystem target during the flash wizard.

---

## Flashing a board

1. Write the FriendlyElec multi-os eflasher image (I used: [rk3399-eflasher-multiple-os-20260423-30g.img.gz](https://drive.google.com/drive/folders/18SXJZvrQA47-ygmqavXH3f2zQQX6kRDj)) to a microSD card (balenaEtcher or `dd`).
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
4. Use a [RealVNC client](https://www.realvnc.com/en/connect/download/viewer/) to connect to unsecured VNC at static address 192.168.1.231.  (see ip address note below). 
4. In the UI, **select the NVMe device as the root filesystem target** (boot must stay on eMMC).
5. Flash and reboot. Remove the SD card; the board boots from eMMC into the NVMe root.

Default credentials after flash: user `pi`, password set during first boot or per FriendlyElec defaults (sometimes `pi` also).

---

IP Address Note:  when the eflasher starts, the default is to show up on the local network with a static ip address.  You must have your remote machine in the same subnet.  You can easily add a secondary or alias IP address to e.g. your macbook to reach the node by VNC.

```bash
#  en0 is your network interface, discoverable by e.g. `ifconfig | grep inet`
#  use any desired available IP
sudo ifconfig en0 alias 192.168.1.99 255.255.255.0
#  to remove the alias, use:
sudo ifconfig en0 -alias 192.168.1.99.
```

---

## Software

- **OS:** Debian 13 Trixie with GNOME(Wayland) (FriendlyElec official image, kernel 6.6, ARM64)
- **Ansible** (macOS control node — install via [Homebrew](https://brew.sh))
- **ansible-lint** (for validating playbooks before running)

### Quick start

```bash
# Install required Ansible collections
ansible-galaxy collection install -r collections/requirements.yml

# Validate playbooks
ansible-lint

# Dry run (no changes) per workload
ansible-playbook minimal.yaml -i hosts.inv --check

# Apply minimal linux baseline to all nodes
ansible-playbook minimal.yaml -i hosts.inv
```

---

## Goals

- K3s (inspiration: https://github.com/k3s-io/k3s-ansible)
- Docker registry on the cluster
- Grafana + Prometheus
- GitHub Actions for external CI; Tekton or Argo Workflows if in-cluster pipelines are needed
- Grafana Loki + Promtail (centralized logging)

### Higher Uses

- Selenium Grid (KEDA job-based autoscaling, Chromium on ARM64, local registry)
- Locally-hosted OpenAI API compliant LLM for Coding, etc.
