# Raspberry Pi CM4 Hardware Patterns

## Storage Device Naming

On Raspberry Pi CM4 carrier boards running Raspberry Pi OS Bookworm (64-bit):

| Device | Kernel prefix | Notes |
|--------|--------------|-------|
| Boot SD card | `mmcblk*` | Always — SD slot uses MMC controller; root is `/dev/mmcblk0p2` |
| NVMe m.2 SSD | `nvme*` | e.g., `nvme0n1` — preferred carrier boards |
| SATA m.2 SSD (bridge) | `sd*` | e.g., `sda` — same prefix as USB storage |

**Critical gotcha**: `ansible_devices[*].rotational` reports `"0"` (string, not integer) for BOTH SD cards and SSDs — both are flash storage. **Never use `rotational` to distinguish the boot device from the m.2 SSD.**

### Idiomatic Ansible SSD Discovery Pattern

```yaml
# Step 1: Try NVMe first
- name: Find NVMe SSD device
  ansible.builtin.set_fact:
    ssd_device: "{{ ansible_devices.keys()
                    | select('match', '^nvme[0-9]+n[0-9]+$')
                    | list | sort | first | default('') }}"

# Step 2: SATA fallback (non-removable sd* only)
- name: Find SATA SSD device (fallback)
  ansible.builtin.set_fact:
    ssd_device: "{{ ansible_devices | dict2items
                    | selectattr('key', 'match', '^sd[a-z]+$')
                    | selectattr('value.removable', 'equalto', '0')
                    | map(attribute='key')
                    | list | sort | first | default('') }}"
  when: ssd_device == ''

# Step 3: Fail fast if not found
- name: Assert SSD was found
  ansible.builtin.fail:
    msg: "No m.2 SSD detected. Devices found: {{ ansible_devices.keys() | list }}"
  when: ssd_device == ''
```

Note: `ansible_devices` keys are bare names (no `/dev/` prefix). The `removable == "0"` filter reduces false positives from USB storage but is not foolproof if USB devices are present during provisioning.

## Filesystem Tasks on Block Devices

### Format-if-missing (idempotent)

`community.general.filesystem` is the only clean single-module option — `ansible.builtin` has no mkfs module.

```yaml
- name: Create ext4 filesystem (idempotent — skips if filesystem exists)
  community.general.filesystem:
    fstype: ext4
    dev: "/dev/{{ ssd_device }}"
    # force: false is the default — omit; never set force: true in production
```

Internally runs `blkid`; only formats if no filesystem detected. Safe to re-run.

**Gotcha**: `mkfs.ext4` without `-F` prompts interactively when operating on a whole disk (not a partition), hanging the task. `community.general.filesystem` handles this internally — but if using raw `ansible.builtin.command: mkfs.ext4`, always pass `-F`.

### UUID Extraction

```yaml
- name: Read UUID of formatted device
  ansible.builtin.command: "blkid -s UUID -o value /dev/{{ ssd_device }}"
  register: ssd_uuid_result
  changed_when: false

- name: Set UUID fact
  ansible.builtin.set_fact:
    ssd_uuid: "{{ ssd_uuid_result.stdout | trim }}"
```

### Check-mode Safety Pattern

`ansible.builtin.command` runs unconditionally in `--check` mode. When a command task depends on a preceding `community.general.filesystem` task (which correctly skips formatting in check mode), the command will operate on an unformatted device and return empty/error output, causing misleading failures.

**Fix**: gate command tasks and their dependents with `when: not ansible_check_mode`, and provide a placeholder fact for the check-mode path:

```yaml
- name: Read UUID (skip in check mode — device may not be formatted yet)
  ansible.builtin.command: "blkid -s UUID -o value /dev/{{ ssd_device }}"
  register: ssd_uuid_result
  changed_when: false
  when: not ansible_check_mode

- name: Set UUID fact (check mode placeholder)
  ansible.builtin.set_fact:
    ssd_uuid: "CHECK-MODE-PLACEHOLDER"
  when: ansible_check_mode

- name: Set UUID fact
  ansible.builtin.set_fact:
    ssd_uuid: "{{ ssd_uuid_result.stdout | trim }}"
  when: not ansible_check_mode
```

## Persistent Mounts (`ansible.posix.mount`)

```yaml
- name: Mount SSD and write fstab entry
  ansible.posix.mount:
    path: /mnt/ssd
    src: "UUID={{ ssd_uuid }}"
    fstype: ext4
    opts: defaults,noatime   # noatime reduces write amplification on flash
    dump: "0"                # must be explicit — null causes duplicate fstab entries
    passno: "2"              # must be explicit — same reason
    state: mounted           # writes fstab AND mounts immediately; idempotent
```

`state: mounted` is idempotent — re-runs with identical parameters produce no change. The module keys fstab entries by `path`, so no duplicates are created.

**Critical**: Always specify `dump` and `passno` explicitly (even as `"0"`). Omitting them (null) causes duplicate fstab entries on subsequent runs per official ansible.posix docs.
