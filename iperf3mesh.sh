#!/usr/bin/env bash
# iperf3mesh.sh — 8×8 node-to-node iperf3 bandwidth mesh test
# Requires: iperf3 installed on all nodes (sudo apt install iperf3)
# Run from your Mac: bash iperf3mesh.sh

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

# Use ansible_host IPs from hosts.inv — mDNS can be unreliable for
# inter-node iperf3 connections between cluster members
declare -A HOST_IP
HOST_IP[kate0.local]=10.0.0.55
HOST_IP[kate1.local]=10.0.0.62
HOST_IP[kate2.local]=10.0.0.56
HOST_IP[kate3.local]=10.0.0.61
HOST_IP[kate4.local]=10.0.0.60
HOST_IP[kate5.local]=10.0.0.57
HOST_IP[kate6.local]=10.0.0.59
HOST_IP[kate7.local]=10.0.0.58

SSH_OPTS=(-F ssh.cfg -o ConnectTimeout=5 -o BatchMode=yes)

declare -A RESULT

for server in "${HOSTS[@]}"; do
  server_ip="${HOST_IP["$server"]}"

  # Start iperf3 server on target node; nohup prevents SIGHUP on SSH session exit.
  # Redirect server output to /dev/null on the remote — we detect failures via
  # client connection errors, not server stdout.
  ssh "${SSH_OPTS[@]}" "$server" 'nohup iperf3 -s >/dev/null 2>&1 &'
  sleep 1  # allow server to bind before clients connect

  for client in "${HOSTS[@]}"; do
    if [[ "$client" == "$server" ]]; then
      RESULT["$client,$server"]="—"
      continue
    fi

    printf "Testing %s → %s...\n" "$client" "$server" >&2

    # iperf3 -J emits all output as JSON to stdout; non-zero exit on connection
    # failure lets the outer if catch unreachable nodes.
    if json=$(ssh "${SSH_OPTS[@]}" "$client" iperf3 -c "$server_ip" -t 3 -J) \
        && [[ -n "$json" ]]; then
      gbps=$(printf '%s\n' "$json" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
    bps = d["end"]["sum_received"]["bits_per_second"]
    print(f"{bps/1e9:.2f}")
except Exception:
    print("—")
')
      RESULT["$client,$server"]="${gbps}"
    else
      RESULT["$client,$server"]="—"
    fi
  done

  # Kill iperf3 server before moving to the next server node.
  # pkill -x matches the exact process name; || true handles "no process found".
  ssh "${SSH_OPTS[@]}" "$server" 'pkill -x iperf3' || true

done

# ── Print results table ──────────────────────────────────────────────────────
# Layout: 8-char left-justified label column + 8 × 7-char right-justified value
# columns = 64 chars total; fits comfortably in an 80-column terminal.

printf "\niperf3 mesh — Gbps (row=client → col=server)\n\n"

# Header row: blank label, then server short names (strip .local suffix)
printf "%-8s" ""
for server in "${HOSTS[@]}"; do
  printf "%7s" "${server%.local}"
done
printf "\n"

# Data rows: client short name, then one result per server column
for client in "${HOSTS[@]}"; do
  printf "%-8s" "${client%.local}"
  for server in "${HOSTS[@]}"; do
    printf "%7s" "${RESULT["$client,$server"]}"
  done
  printf "\n"
done
printf "\n"
