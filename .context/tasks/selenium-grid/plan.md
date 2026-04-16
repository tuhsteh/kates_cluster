## Task: selenium-grid
## Branch: feature/selenium-grid
## Objective: Deploy Selenium Grid 4 on the k3s cluster to offload browser test execution from the user's laptop, scaling to several dozen Chromium nodes for TestNG remote WebDriver runs.
## Folder: .context/tasks/selenium-grid/

## Decisions
- **ARM64 image**: Use `selenium/node-chromium:4.43.0-20260404` — NOT `node-chrome` (Chrome has no ARM64 Linux binary). Official multi-arch support added in 4.21.0 (May 2024); `seleniarm` images are deprecated.
- **Deployment method**: Official Helm chart `docker-selenium/selenium-grid` v0.27.0 — same shell-based Helm pattern as Prometheus role
- **External access**: NodePort 30444 — user confirmed laptop is on same LAN as Pi nodes
- **`dshmVolumeSizeLimit: 1Gi` REQUIRED** — k8s pods default to 64MB /dev/shm; Chromium needs ~1GB or it crashes silently
- **Scaling strategy**: KEDA job-based (`scalingType: job`) — one pod per session, terminates on completion; matches user's current docker-compose Dynamic Grid behavior. Cold-start latency (~15–30s) accepted.
- **Node count**: `maxReplicaCount: 24` (3/Pi × 8 Pis); KEDA scales 0→N on demand; `minReplicaCount: 0`
- **KEDA**: installed via chart (`autoscaling.enabled: true`); chart pins selenium-patched KEDA 2.15.1

## Key Files
- `roles/selenium_grid/tasks/main.yaml` — role tasks (to be created)
- `roles/selenium_grid/defaults/main.yaml` — role variables (to be created)
- `roles/selenium_grid/templates/` — Helm values or k8s manifest templates (to be created)
- `stage.yaml` — add selenium_grid to stage_leader play
- `README.md` — add Selenium Grid to project goals

## Progress
- [x] Created branch `feature/selenium-grid` and task folder
- [x] Research: ARM64 image support, Helm chart, resource requirements, scaling patterns
- [x] Confirm external access pattern with user (NodePort 30444)
- [x] Architecture/design review (all decisions locked — see Decisions section)
- [x] Implement role (coder) — `roles/selenium_grid/` tasks, defaults, templates; stage.yaml; README.md
- [ ] Review (reviewer)
- [x] ansible-lint verification — 0 failures, 0 warnings (`--profile production`)
- [ ] Commit and push

## Open Questions / Blockers
- (none blocking) docker_registry role was already complete in PR #8; local registry at `kate0.local:30500`. Selenium role should use this as the image registry.
- **Persistence**: no PVC needed — grid is stateless (KEDA job pods terminate per session).

## Constraints
- All nodes are Raspberry Pi 4B ARM64 — must use ARM64-compatible container images
- k3s cluster, no kubeadm — same k3s-specific patterns as Prometheus role
- Role must pass `ansible-lint --profile production` at 0 failures
- Follow existing role structure (tasks/main.yaml, defaults/main.yaml, templates/)
- Deployment pattern: shell-based (same as Prometheus — no kubernetes.core collection)
