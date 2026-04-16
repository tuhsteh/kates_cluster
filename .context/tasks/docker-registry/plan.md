## Task: docker-registry
## Branch: feature/docker-registry
## Objective: Complete the `docker_registry` Ansible role to deploy a private Docker registry on k3s, backed by Longhorn persistent storage, with htpasswd authentication and k3s registry mirror configuration so cluster nodes can pull from it.
## Folder: .context/tasks/docker-registry/

## Decisions
- **Use Longhorn StorageClass for the PVC** — Longhorn is already deployed; `docker_registry_storage_class: longhorn`, `docker_registry_storage_size: 20Gi` (user specified)
- **HTTP + NodePort, no TLS** — Traefik is disabled in this cluster; cert-manager/IngressRoute approach from guides does not apply. NodePort 30500, `http://` endpoint in registries.yaml. User confirmed.
- **Deploy raw Kubernetes YAML via kubectl apply, not HelmChart CRD** — registry:2 has no official Helm chart; raw manifests match carpie.net pattern
- **Namespace: `default`** — existing secret `docker-registry-htpasswd` was created in `default` (no `-n` flag used); keeping everything in `default` avoids secret/namespace mismatch
- **Image: `registry:2`** — fully multi-arch; linux/arm64 pulled automatically on RPi4; no special tag needed
- **Registry hostname: `kate0.local:30500`** — leader node hostname; NodePort is accessible on all node IPs so this is just the conventional address used in image names
- **`registries.yaml` must be deployed to ALL nodes** — both leader and all 7 agents must have `/etc/rancher/k3s/registries.yaml`; must restart k3s/k3s-agent after writing it; deployment approach to members TBD by coder (options: add `docker_registry` to `stage_members` with guards, add task to `k3s_member` role, or create a separate role)
- **`REGISTRY_AUTH_HTPASSWD_PATH: /auth/htpasswd`** — secret key name is the filename (`htpasswd` from `--from-file`); mountPath must be `/auth/` so the full path is `/auth/htpasswd`
- **`REGISTRY_STORAGE_DELETE_ENABLED: "true"`** — allows image deletion from the registry

## Key Files
- `roles/docker_registry/tasks/main.yaml` — existing partial implementation; append PVC/Deployment/Service kubectl apply tasks and registries.yaml on leader
- `roles/docker_registry/templates/pvc.yaml.j2` — PVC manifest for Longhorn storage
- `roles/docker_registry/templates/deployment.yaml.j2` — registry:2 Deployment manifest
- `roles/docker_registry/templates/service.yaml.j2` — NodePort Service manifest
- `roles/docker_registry/templates/registries.yaml.j2` — k3s private registry config template (used on all nodes)
- `roles/docker_registry/defaults/main.yaml` — to be created; all registry config variables
- `stage.yaml` — `docker_registry` role listed for `stage_leader`; may need addition to `stage_members` for registries.yaml task (coder to decide approach)
- `roles/k3s_member/` — may need a `registries.yaml` task if coder chooses that approach for member nodes

## Progress
- [x] Created feature branch `feature/docker-registry`
- [x] Created task folder and plan.md
- [x] Research: carpie.net + k3s official docs reviewed; manifests, registries.yaml format, ARM64 caveats documented
- [x] Implement: complete role with defaults, templates, and remaining tasks — lint clean (0 failures); registries.yaml on members via k3s_member role
- [ ] Fix review findings (2 critical, 2 moderate) ← IN PROGRESS
- [ ] Commit and open PR

## Open Questions / Blockers
- How to deploy registries.yaml to member nodes: (a) add docker_registry to stage_members with `when` guards, (b) add to k3s_member role, or (c) new role. Coder to pick approach that best fits existing patterns.
- Longhorn timing: registry PVC can't bind until Longhorn StorageClass is ready. May need `kubectl wait` or a small delay. Coder to assess.
- k3s/k3s-agent must be restarted after registries.yaml is written — need handlers in the roles involved.

## Constraints
- All nodes are Raspberry Pi 4B+ (ARM64) — registry image must support ARM64
- k3s data dir is `/mnt/ssd/k3s` (variable: `k3s_leader_data_dir` from k3s_leader role)
- Do not re-declare `k3s_leader_data_dir` in docker_registry defaults — cross-role variable dependency pattern (see domains/raspberry-pi-hardware.md)
- Existing tasks (htpasswd, k8s secret) must be preserved
- Hardcoded password (`1qazxsw2`) in current tasks — leave as-is unless user asks to parameterize
- Password in current tasks is in plain text — do NOT expose it in new templates or defaults
