# exo + Open WebUI + Python on Debian 13 Trixie ARM64

**Research Date:** 2026-05-01
**Sources:** GitHub source files (pyproject.toml, README.md, main.py, .env.example), packages.debian.org, docs.openwebui.com

---

## Table of Contents

1. [exo (exo-explore/exo)](#exo)
2. [Open WebUI](#open-webui)
3. [Python on Debian 13 Trixie ARM64](#python-on-debian-13-trixie-arm64)

---

## exo

**Version at research time:** 0.3.70 (pyproject.toml)
**Source:** https://github.com/exo-explore/exo

### Python Version Requirement

```
requires-python = "==3.13.*"
```

**Python 3.13 exactly** — not 3.12, not 3.11. The `==3.13.*` constraint means any 3.13.x release but ONLY 3.13.

This is a **recent change** from earlier versions that accepted 3.12+. As of v0.3.70, it requires 3.13.

### Build Prerequisites

exo uses **uv** (not pip) as its build/package manager. Also requires:

- **uv** >= 0.8.6 (`required-version = ">=0.8.6"` in pyproject.toml)
- **Rust nightly** (for Rust bindings: `exo-pyo3-bindings`)
- **Node.js >= 18** (for building the dashboard)

Install on Debian:

```bash
# uv
curl -LsSf https://astral.sh/uv/install.sh | sh

# Rust nightly
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
rustup toolchain install nightly

# Node.js (version 18+)
sudo apt install nodejs npm
# If Debian's nodejs is too old, use NodeSource:
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo bash -
sudo apt install nodejs
```

### Installation (Linux from source)

```bash
git clone https://github.com/exo-explore/exo
cd exo

# Build dashboard
cd dashboard && npm install && npm run build && cd ..

# Install with CPU extra (for Linux non-GPU)
uv run --extra cpu exo
# Or: uv sync --extra cpu && uv run exo
```

### Optional Extras (Linux)

| Extra  | Packages installed | Use case |
|--------|-------------------|----------|
| `cpu`  | `mlx-cpu`, `mlx-lm`, `mlx-vlm`, `torch` (CPU wheels) | CPU-only inference on Linux |
| `cuda12` | `mlx-cuda-12`, `mlx-lm`, `torch` (CUDA 12) | NVIDIA GPU with CUDA 12 |
| `cuda13` | `mlx-cuda-13`, `mlx-lm`, `torch` (CUDA 13) | NVIDIA GPU with CUDA 13 |

For ARM64 CPU-only: use **`cpu` extra**. Note: `mlx` and `mlx-cpu` on Linux ARM64 — see Known Issues.

### Running exo

```bash
# From cloned repo directory
uv run --extra cpu exo

# With specific options
uv run --extra cpu exo --api-port 52415 --libp2p-port 9000 -v
```

### CLI Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--api-port PORT` | `52415` | OpenAI-compatible API port |
| `--libp2p-port PORT` | `0` (OS-assigned) | Pin libp2p TCP port (important for firewalls) |
| `--no-api` | (API is ON by default) | Disable the HTTP API |
| `--no-worker` | (worker ON) | Coordinator-only mode — no local inference |
| `--no-downloads` | (downloads enabled) | Disable model download coordinator |
| `--bootstrap-peers MULTIADDRS` | `[]` | Comma-separated libp2p multiaddrs for manual peer seeding |
| `--force-master` | `false` | Force this node to be cluster master |
| `--offline` | `false` | Air-gapped mode, no internet calls |
| `--no-batch` | `false` | Disable continuous batching |
| `-v` | 0 | Verbose (repeat for more: `-vv`) |
| `-q` | — | Quiet |

**The API is enabled by default** (argparse `store_false` for `--no-api` means default is `True`).

### Peer Discovery

exo uses **libp2p** for peer discovery — **not mDNS, not UDP broadcast**.

- Nodes automatically discover each other on the same network via libp2p
- No manual configuration needed for LAN clusters
- For cross-subnet or non-broadcast environments: use `--bootstrap-peers`

Bootstrap peer format (libp2p multiaddr):
```
/ip4/192.168.1.100/tcp/9000/p2p/PEER_ID
```

Get peer ID from logs on startup: `Starting node <NODE_ID>`.

### Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| `52415` | TCP | OpenAI-compatible HTTP API (configurable with `--api-port`) |
| `libp2p-port` | TCP | libp2p peer communication (default: OS-assigned; pin with `--libp2p-port`) |

### API Endpoint

The OpenAI-compatible API is at:
```
http://localhost:52415
```

Compatible interfaces:
- **OpenAI Chat Completions**: `http://localhost:52415/v1/chat/completions`
- **Ollama API**: `http://localhost:52415` (Ollama-compatible endpoints)
- **Claude Messages API**: supported
- **OpenAI Responses API**: supported

Dashboard: `http://localhost:52415/` (built from `dashboard/` with npm)

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `EXO_DEFAULT_MODELS_DIR` | `~/.local/share/exo/models` | Model download/cache directory |
| `EXO_MODELS_DIRS` | none | Colon-separated additional writable model dirs |
| `EXO_MODELS_READ_ONLY_DIRS` | none | Read-only model dirs (NFS, shared storage) |
| `EXO_OFFLINE` | `false` | Air-gapped mode |
| `EXO_LIBP2P_NAMESPACE` | none | Cluster isolation namespace (prevent unintended joins) |
| `EXO_BOOTSTRAP_PEERS` | none | Comma-separated bootstrap multiaddrs (alternative to `--bootstrap-peers`) |
| `EXO_ENABLE_IMAGE_MODELS` | `false` | Enable image model support |
| `EXO_FAST_SYNCH` | auto | Control MLX_METAL_FAST_SYNCH |
| `EXO_TRACING_ENABLED` | `false` | Distributed tracing |

### File Locations (Linux — XDG spec)

| Purpose | Default Path |
|---------|-------------|
| Config | `~/.config/exo/` |
| Data | `~/.local/share/exo/` |
| Models | `~/.local/share/exo/models` |
| Cache | `~/.cache/exo/` |
| Logs | `~/.cache/exo/exo_log/` |

### No Inference Engine Flag

There is **no `--inference-engine` CLI flag**. The inference engine is selected at install time via the optional extras (`cpu`, `cuda12`, `cuda13`). On Linux with `[cpu]`, exo uses `mlx-cpu` + PyTorch CPU.

### ARM64 / RK3399 Known Issues

- **Linux is CPU-only** (official statement in README): "Currently, exo runs on CPU on Linux. GPU support for Linux platforms is under development."
- `mlx-cpu` package is required for Linux CPU inference — included in `[cpu]` extra
- **mlx-cpu ARM64 wheel availability**: mlx-cpu is a relatively new package. Check PyPI for ARM64 (aarch64) wheel availability. If no wheel exists, it will attempt to build from source, which requires Rust, CMake, and C++ build tools.
- RK3399 is Cortex-A72/A53; 4-6GB RAM typical. Only small models (1B-3B quantized) will fit.
- Expect slow inference — RK3399 is not optimized for ML workloads
- No reported show-stopping blockers specific to RK3399 as of research date

### Systemd Service

```ini
[Unit]
Description=exo distributed LLM node
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=exo
WorkingDirectory=/opt/exo
Environment="HOME=/home/exo"
Environment="EXO_LIBP2P_NAMESPACE=mycluster"
Environment="EXO_DEFAULT_MODELS_DIR=/opt/exo/models"
ExecStart=/home/exo/.local/bin/uv run --extra cpu exo --libp2p-port 9000 --api-port 52415 -v
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Note: `uv run` from a cloned repo resolves the venv/lockfile automatically. Ensure the working directory is the cloned `exo/` repo.

---

## Open WebUI

**Source:** https://github.com/open-webui/open-webui

### Python Version Requirement

```
requires-python = ">= 3.11, < 3.13.0a1"
```

**Python 3.11 or 3.12 only** — explicitly excludes 3.13+.

Since Debian 13 Trixie ships Python 3.13, **pip install on bare Debian Trixie will not work** without a separate Python 3.12 installation.

### Install Methods

#### Method 1: Docker (Recommended for Debian Trixie ARM64)

Official multi-arch images support `linux/arm64` natively:

```bash
docker pull ghcr.io/open-webui/open-webui:main
docker run -d \
  -p 3000:8080 \
  -v open-webui:/app/backend/data \
  --name open-webui \
  --restart always \
  ghcr.io/open-webui/open-webui:main
```

For exo backend (OpenAI-compatible):
```bash
docker run -d \
  -p 3000:8080 \
  -v open-webui:/app/backend/data \
  -e OPENAI_API_BASE_URL=http://host.docker.internal:52415/v1 \
  -e OPENAI_API_KEY=notneeded \
  -e OLLAMA_BASE_URL="" \
  --add-host=host.docker.internal:host-gateway \
  --name open-webui \
  --restart always \
  ghcr.io/open-webui/open-webui:main
```

Access at `http://localhost:3000`.

#### Method 2: pip install (requires Python 3.11 or 3.12)

```bash
# Must use Python 3.11 or 3.12
python3.12 -m pip install open-webui
open-webui serve
```

Serves on port **8080** by default.

### Connecting to exo

exo exposes an OpenAI-compatible API at port 52415. Open WebUI uses these env vars:

| Env Var | Value for exo | Purpose |
|---------|--------------|---------|
| `OPENAI_API_BASE_URL` | `http://localhost:52415/v1` | Point to exo API |
| `OPENAI_API_KEY` | Any non-empty string | Required by Open WebUI even if not validated |
| `OLLAMA_BASE_URL` | `""` (empty, to disable Ollama) | Disable Ollama connection |

Alternative: Since exo also exposes an Ollama-compatible API, you can use:
```
OLLAMA_BASE_URL=http://localhost:52415
```

### Default Ports

| Context | Port |
|---------|------|
| pip `open-webui serve` | `8080` |
| Docker internal | `8080` |
| Docker external (typical) | `3000` (mapped from 8080) |

### Systemd Service (Docker-based)

```ini
[Unit]
Description=Open WebUI
After=docker.service
Requires=docker.service

[Service]
Type=forking
ExecStart=/usr/bin/docker start open-webui
ExecStop=/usr/bin/docker stop open-webui
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

Or use Docker's own `--restart always` which handles restart across reboots.

### Systemd Service (pip-based, if Python 3.12 is available)

```ini
[Unit]
Description=Open WebUI
After=network.target

[Service]
Type=simple
User=openwebui
Environment="OPENAI_API_BASE_URL=http://localhost:52415/v1"
Environment="OPENAI_API_KEY=exo"
Environment="OLLAMA_BASE_URL="
ExecStart=/home/openwebui/.venv/bin/open-webui serve
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

---

## Python on Debian 13 Trixie ARM64

**Debian 13 "Trixie"** — Released/stabilized 2025. Default Python is **3.13.5**.

### What's in the Repos

| Package | Version | Available |
|---------|---------|-----------|
| `python3` | 3.13.5 | ✅ Yes |
| `python3.13` | 3.13.5 | ✅ Yes |
| `python3.12` | — | ❌ Not available |
| `python3.11` | — | ❌ Not available |

Source: https://packages.debian.org/trixie/python3.12 — returns "Package not available in this suite."

### deadsnakes PPA

**deadsnakes PPA is Ubuntu-only.** It does NOT work on Debian:
- PPAs are Ubuntu infrastructure (Launchpad)
- deadsnakes builds target Ubuntu, not Debian
- Using deadsnakes on Debian is unsupported and can break the system

### Getting Python 3.12 on Debian Trixie

**Option 1: pyenv (recommended for non-system Python)**

```bash
# Build deps
sudo apt install -y build-essential libssl-dev zlib1g-dev libbz2-dev \
  libreadline-dev libsqlite3-dev wget curl libncursesw5-dev xz-utils \
  tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev git

# Install pyenv
curl https://pyenv.run | bash
# Add to ~/.bashrc:
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

# Install Python 3.12
pyenv install 3.12.10
pyenv global 3.12.10  # or local
```

**Option 2: Build from source**

```bash
# Build deps (same as above)
wget https://www.python.org/ftp/python/3.12.10/Python-3.12.10.tgz
tar xf Python-3.12.10.tgz
cd Python-3.12.10
./configure --enable-optimizations --prefix=/usr/local
make -j$(nproc)
sudo make altinstall  # installs as python3.12
```

**Option 3: Docker** — for Open WebUI specifically, Docker is the cleanest solution.

### Ansible-idiomatic Approach

**For exo (needs 3.13):** Use `apt`:
```yaml
- name: Install Python 3.13
  ansible.builtin.apt:
    name:
      - python3
      - python3-venv
      - python3-dev
    state: present
    update_cache: true
```

**For Open WebUI (needs 3.11-3.12):** Use Docker:
```yaml
- name: Run Open WebUI container
  community.docker.docker_container:
    name: open-webui
    image: ghcr.io/open-webui/open-webui:main
    state: started
    restart_policy: always
    ports:
      - "3000:8080"
    volumes:
      - open-webui:/app/backend/data
    env:
      OPENAI_API_BASE_URL: "http://host-gateway:52415/v1"
      OPENAI_API_KEY: "exo"
      OLLAMA_BASE_URL: ""
```

**For Open WebUI non-Docker (needs Python 3.12):** Use pyenv via Ansible:
```yaml
- name: Install pyenv dependencies
  ansible.builtin.apt:
    name:
      - build-essential
      - libssl-dev
      - zlib1g-dev
      - libbz2-dev
      - libreadline-dev
      - libsqlite3-dev
      - libncursesw5-dev
      - xz-utils
      - libffi-dev
      - liblzma-dev
      - libxml2-dev
      - libxmlsec1-dev
      - git
    state: present

- name: Clone pyenv
  ansible.builtin.git:
    repo: https://github.com/pyenv/pyenv.git
    dest: "{{ pyenv_root }}"
    version: master

- name: Install Python 3.12 via pyenv
  ansible.builtin.shell:
    cmd: "{{ pyenv_root }}/bin/pyenv install -s 3.12.10"
  environment:
    PYENV_ROOT: "{{ pyenv_root }}"
    PATH: "{{ pyenv_root }}/bin:{{ ansible_env.PATH }}"
  become: true
  become_user: "{{ service_user }}"

- name: Install open-webui
  ansible.builtin.pip:
    name: open-webui
    executable: "{{ pyenv_root }}/versions/3.12.10/bin/pip3"
```
