# AGENTS.md

Guidance for AI coding agents working in this repository.

## Scope
- This is an Ansible-managed Raspberry Pi cluster project.
- Top-level entry points are workload playbooks: `minimal.yaml`, `exo-ai.yaml`, `k3s-cluster.yaml`, and `selenium-grid.yaml`.

## Fast Start
- Install required collections before making or validating changes:
  - `ansible-galaxy collection install -r collections/requirements.yml`
- Validate changes with:
  - `ansible-lint`
- Optional dry run:
  - `ansible-playbook minimal.yaml -i hosts.inv --check`

## Project Conventions
- Role directories use `snake_case` under `roles/`.
- Keep role names in `playbooks/shared/*.yaml` synchronized with `roles/` directory names.
- Prefer Ansible modules over shell commands when feasible.
- Use FQCN module names (`ansible.builtin.*`, `ansible.posix.*`, `community.general.*`).
- Avoid free-form module arguments when structured arguments are available.
- Use explicit booleans (`true`/`false`) and quote file modes when needed (for example `"0644"`).

## Files To Check First
- `README.md` for project intent and hardware/software context.
- `ansible.cfg` for runtime defaults (inventory path, ssh args, temp dir).
- `hosts.inv` for leader/member host groups.
- `playbooks/shared/linux_base.yaml` for shared baseline role execution order.
- `playbooks/shared/minimal_base.yaml` for minimal baseline role execution order.
- `playbooks/shared/ai_roles.yaml`, `playbooks/shared/k3s_cluster_roles.yaml`, `playbooks/shared/selenium_prereqs.yaml`, and `playbooks/shared/selenium_roles.yaml` for workload role execution order.
- `collections/requirements.yml` for required collections.

## Change Safety Checklist
- Keep task names clear and consistently cased.
- Add `changed_when`/`failed_when` where command tasks are checks.
- Preserve idempotence when modifying tasks.
- Re-run `ansible-lint` before finishing.

## Existing Repo Docs
- Main overview: [README.md](README.md)
