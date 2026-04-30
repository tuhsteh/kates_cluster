#!/usr/bin/env bash
# netspeed.sh — latency + throughput check for each cluster node
# Uses only tools present on Debian 13 minimal (ping, ssh, dd)
# Run from your Mac: bash netspeed.sh

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

SSH_OPTS="-F ssh.cfg -o ConnectTimeout=5 -o BatchMode=yes"
DD_SIZE="64M"   # bytes sent over ssh; increase for a longer / more accurate test

printf "\n%-14s  %10s  %12s\n" "HOST" "PING(ms)" "THROUGHPUT"
printf "%s\n" "----------------------------------------------"

for host in "${HOSTS[@]}"; do
  # --- latency: avg of 5 pings ---
  ping_ms=$(ping -c 5 -q "$host" 2>/dev/null \
    | awk -F'/' '/^round-trip/ { printf "%.1f", $5 }')
  [[ -z "$ping_ms" ]] && ping_ms="unreachable"

  # --- throughput: push DD_SIZE of zeros through ssh, measure on the remote ---
  # dd reads from /dev/zero locally, writes to /dev/null on the remote node.
  # 'time' is bash built-in; we capture elapsed seconds then compute MB/s.
  if [[ "$ping_ms" != "unreachable" ]]; then
    bytes=$((64 * 1024 * 1024))
    elapsed=$(
      { time dd if=/dev/zero bs=1M count=64 2>/dev/null \
          | ssh $SSH_OPTS "$host" 'dd of=/dev/null bs=1M' 2>/dev/null; } \
        2>&1 | awk '/real/ { split($2,a,"m"); printf "%.3f", a[1]*60 + a[2] }'
    )
    if [[ -n "$elapsed" && "$elapsed" != "0.000" ]]; then
      mbps=$(awk "BEGIN { printf \"%.1f MB/s\", $bytes / $elapsed / 1048576 }")
    else
      mbps="(error)"
    fi
  else
    mbps="—"
  fi

  printf "%-14s  %10s  %12s\n" "$host" "$ping_ms" "$mbps"
done
printf "\n"
