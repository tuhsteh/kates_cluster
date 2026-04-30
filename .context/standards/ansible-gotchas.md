# Ansible Gotchas

Common mistakes surfaced during development of this playbook. Each entry states
the rule, the failure mode, and the fix.

---

## Gathering Host Facts vs. Inventory Variables in Templates

### Rule: Prefer gathered facts over inventory variables for IP addresses

**Never** use `hostvars[host]['ansible_host']` in templates or tasks as a reliable
IP address. `ansible_host` is an inventory alias — it may be a hostname, an IP, or
absent entirely, depending on how the inventory is written.

**Prefer** `hostvars[host]['ansible_default_ipv4']['address']` (a gathered fact) with
a `| default(...)` fallback:

```jinja2
{{ hostvars[host]['ansible_default_ipv4']['address']
   | default(hostvars[host].get('ansible_host', host)) }}
```

This pattern is used in the `mdns` role's `/etc/hosts` block template.

---

## `ansible.builtin.slurp` Returns Base64, Not Plain Text

**Never** compare raw `ansible.builtin.slurp` output to a plain string:

```yaml
# WRONG — slurp content is base64-encoded
- ansible.builtin.slurp:
    src: /etc/debian_version
  register: distro_file
- when: distro_file.content == 'trixie'   # always false
```

The `content` field is base64. To decode: `distro_file.content | b64decode | trim`.

**Better alternative**: Use the `ansible_distribution_release` gathered fact (set by
`ansible.builtin.setup`) — no file read needed and no encoding issues:

```yaml
- when: ansible_distribution_release == 'trixie'
```

---

## Hostname Suffix Double-Application in `/etc/hosts` Templates

When constructing `/etc/hosts` entries from inventory hostnames, check whether
hostnames already carry a domain suffix before appending one.

**Wrong** — if `inventory_hostname` is `kate0.local`, this produces `kate0.local.local`:

```jinja2
{{ inventory_hostname }}.local
```

**Correct** — inspect the suffix before appending:

```jinja2
{% if not inventory_hostname.endswith('.local') %}
{{ inventory_hostname }}.local
{% else %}
{{ inventory_hostname }}
{% endif %}
```

Or better: store short hostnames (no suffix) in inventory and apply the domain suffix
exactly once in the template.
