#!/usr/bin/env bash
# cleanssh.sh — clear stale ControlMaster sockets (and optionally known_hosts)
#               for all kate cluster nodes (kate0.local–kate7.local)
# Run from your Mac: bash cleanssh.sh [--known-hosts]
#   Default: socket cleanup only (needed after any node reboot/network drop)
#   --known-hosts: also scrub known_hosts entries (needed after ssh_hostkeys role)

HOSTS=(
  kate0.local
  kate1.local
  kate2.local
  kate3.local
  kate4.local
  kate5.local
  kate6.local
  kate7.local
)

SOCKET_DIR="${HOME}/.ssh/ansible"
CLEAN_KNOWN_HOSTS=0

for arg in "$@"; do
  case "$arg" in
    --known-hosts) CLEAN_KNOWN_HOSTS=1 ;;
    *) printf "Unknown argument: %s\n" "$arg" >&2; exit 1 ;;
  esac
done

# ── Column header ─────────────────────────────────────────────────────────────
if [[ "$CLEAN_KNOWN_HOSTS" -eq 1 ]]; then
  printf "\n%-14s  %-18s  %s\n" "HOST" "SOCKET" "KNOWN_HOSTS"
  printf "%s\n" "--------------------------------------------------------"
else
  printf "\n%-14s  %s\n" "HOST" "SOCKET"
  printf "%s\n" "--------------------------------"
fi

# ── Per-host cleanup ──────────────────────────────────────────────────────────
# kate0.local = 10.0.0.55, kate1.local = 10.0.0.56, …, kate7.local = 10.0.0.62
IP_BASE=55

for i in "${!HOSTS[@]}"; do
  host="${HOSTS[$i]}"
  ip="10.0.0.$((IP_BASE + i))"
  socket="${SOCKET_DIR}/${host}-22"
  socket_status="none"
  kh_status="none"

  # Graceful mux close; suppress all output — status is tracked via file test
  if [[ -S "$socket" ]]; then
    ssh -S "$socket" -O exit "$host" >/dev/null 2>&1
    # rm -f handles the case where the master ignored the exit request
    [[ -S "$socket" ]] && rm -f "$socket"
    socket_status="cleaned"
  fi

  if [[ "$CLEAN_KNOWN_HOSTS" -eq 1 ]]; then
    # Capture stdout ("Updated …" noise) so it doesn't clutter output;
    # stderr (real errors, e.g. permission denied) still reaches the terminal.
    for name in "$host" "$ip"; do
      msg=$(ssh-keygen -R "$name")
      [[ -n "$msg" ]] && kh_status="removed"
    done
    printf "%-14s  %-18s  %s\n" \
      "$host" "socket: ${socket_status}" "known_hosts: ${kh_status}"
  else
    printf "%-14s  %s\n" "$host" "socket: ${socket_status}"
  fi

done

printf "\n"
