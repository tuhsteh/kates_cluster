## Task: kube-prometheus-stack
## Branch: feature/prometheus
## Objective: Deploy kube-prometheus-stack (Prometheus + Grafana + AlertManager + node-exporter) as a new Ansible role on the 8-node Raspberry Pi k3s cluster for cluster observability.
## Folder: .context/tasks/kube-prometheus-stack/

## Decisions
- **kube-prometheus-stack (not standalone)**: User confirmed deploying the full stack — Prometheus, Grafana, AlertManager, node-exporter, kube-state-metrics all bundled. Both Prometheus and Grafana are listed project goals; combined deployment is more coherent.
- **Chart version**: v83.5.0 (current stable, April 2026, no ARM64/k3s regressions).
- **Deployment method**: Shell-based Helm on the leader node — user chose this over `kubernetes.core.helm` to avoid new collection dependencies. Install Helm binary on leader via `ansible.builtin.get_url` + `ansible.builtin.unarchive` (idiomatic; avoids curl|bash). Run `helm upgrade --install` via `ansible.builtin.shell` with `--wait --timeout 600s`. No changes to `requirements.yml` or `collections/`.
- **Access method**: NodePort confirmed. Ports: 30090 (Prometheus), 30093 (AlertManager), 30300 (Grafana).
- **Storage**: Prometheus 20Gi/Longhorn, 15d retention, 15GB size cap. AlertManager 1Gi. Grafana 1Gi.
- **Namespace**: `monitoring` — no conflicts with k3s defaults.
- **k3s scrape overrides (CRITICAL)**: Must disable kubeApiServer, kubeControllerManager, kubeScheduler, kubeProxy, kubeEtcd ServiceMonitors — all are silent-fail in k3s. Only `kubelet` monitor is correct. `defaultRules.create: false`, `grafana.defaultDashboardsEnabled: false`.
- **Admission webhooks**: Must set `prometheusOperator.admissionWebhooks.enabled: false` — timeouts silently on ARM64.
- **ServiceMonitor selector**: `prometheusSpec.serviceMonitorSelectorNilUsesHelmValues: false` — so Longhorn/app ServiceMonitors are discovered.
- **Image overrides**: None needed — all components multi-arch, pull ARM64 automatically.
- **Grafana admin password**: Variable `grafana_admin_password` in `defaults/main.yaml`, default value `prom-operator`. User confirmed; can be overridden with vault.
- **Resource limits**: Conservative values required for ARM64 (Prometheus: 500m/1000Mi; total stack ~1–1.8Gi RAM). Will use values from research.

## Key Files
- `roles/prometheus/` — new role to be created
- `stage.yaml` — must add `prometheus` role to `stage_leader` play
- `.context/tasks/kube-prometheus-stack/plan.md` — this file
- `.context/cache/` — researcher will write findings cache file

## Progress
- [x] Created feature branch `feature/prometheus`
- [x] Created task folder and plan.md
- [x] Research: kube-prometheus-stack on k3s ARM64 — kubernetes.core.helm vs shell, ARM64 compat confirmed, 10 k3s gotchas documented
- [x] Confirm design decisions with user — shell-based helm on leader, prom-operator default password, NodePorts 30090/30300/30093, 20Gi/1Gi/1Gi storage
- [x] Implement `prometheus` role — defaults (all prometheus_-prefixed vars), tasks (8 tasks: namespace, helm binary, repo, values template, deploy, wait), values.yaml.j2 (all k3s overrides), stage.yaml updated
- [x] ansible-lint verification — 0 failures, 0 warnings; production profile
- [x] Code review — 4 moderate findings, 3 informational; 0 critical
- [ ] Apply review fixes ← IN PROGRESS
- [ ] Code review
- [ ] Apply review fixes
- [ ] Commit and open PR
- [ ] Task retrospective

## Open Questions / Blockers
- None — all design decisions confirmed. Proceeding to implementation.

## Constraints
- ARM64 (Raspberry Pi 4B) — all images must support linux/arm64
- Traefik is disabled — no Ingress-based access; NodePort only
- Longhorn available for persistent storage
- Ansible roles use snake_case under `roles/`; FQCN module names; `ansible-lint` must pass at 0 failures
- `stage.yaml` only has `stage_leader` and `stage_members` plays; Prometheus runs on leader (or is accessible cluster-wide via NodePort)
- No credentials in plaintext in committed files (use Ansible variables; passwords may go in defaults with a note to override via vault)
- k3s data directory: `/mnt/ssd/k3s` (not default `/var/lib/rancher/k3s`)
