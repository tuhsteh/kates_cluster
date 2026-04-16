# Ansible Cleanup & Normalization Plan

## Objectives
- Standardize Ansible code style across all roles using community best practices
- Use `ansible-lint` as the authoritative guide for what to fix and in what priority order
- Ensure idiomatic Ansible patterns (modules over commands, FQCNs, clean YAML booleans)

## High-Level Areas for Cleanup
1. **Module FQCN Normalization**: Convert short-form module keys to fully-qualified collection names
   - Examples: `apt:` → `ansible.builtin.apt:`, `debug:` → `ansible.builtin.debug:`, `file:` → `ansible.builtin.file:`, etc.
   - Exception: Keep `shell:` only where shell features (pipes, redirects, etc.) are genuinely needed
   
2. **Command → Module Conversion**: Replace direct command execution with idiomatic Ansible modules where applicable
   - `apt-get` commands → `ansible.builtin.apt` module
   - Simple tool calls → relevant builtin/community modules (e.g., `kubectl` commands may stay as command if no k8s module applies)
   
3. **YAML Boolean Normalization**: Use consistent `true`/`false` instead of legacy `yes`/`no`
   
4. **Module Parameter Style**: Ensure consistent use of block vs. inline parameter syntax where appropriate

5. **Ansible-Lint Compliance**: Fix any remaining lint errors/warnings that ansible-lint reports (rule priorities TBD after lint run)

## Workflow
1. Run `ansible-lint roles/` to generate baseline report
2. Prioritize fixes based on lint output (severity, frequency, type)
3. Apply fixes role-by-role, verifying no regressions
4. Document any intentional deviations from lint rules (if any)

## Scope
- **In scope**: All task/handler YAML files under `roles/`
- **Out of scope**: `stage.yaml`, `.context/`, other files with in-progress work from separate branches

## Success Criteria
- All roles pass `ansible-lint` (or justified exceptions documented)
- Consistent FQCN usage across all roles
- No unintended behavior changes
- Clear git history showing what changed and why
