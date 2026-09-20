#!/usr/bin/env bash
# 99-destroy.sh - Xoa toan bo lab (2 Incus nodes + 1 QEMU VM + networks + taps)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INC="sudo incus"
NODES=(node1 node2)

read -r -p "Xoa node1/node2 (Incus) + node3 (QEMU) + profile + mang mgmtbr0/labbr0? (yes/no): " a
[ "$a" = "yes" ] || { echo "Da huy."; exit 0; }

# 1. Dung va xoa QEMU node3
if [ -f "${SCRIPT_DIR}/stop-node3.sh" ]; then
  bash "${SCRIPT_DIR}/stop-node3.sh" || true
fi
PID_FILE="${SCRIPT_DIR}/qemu-node3/node3.pid"
if [ -f "$PID_FILE" ]; then
  PID=$(cat "$PID_FILE")
  sudo kill -9 "$PID" 2>/dev/null || true
  rm -f "$PID_FILE"
fi

# Xoa TAP devices
sudo ip link delete tap-mgmt3 2>/dev/null && echo "Da xoa tap-mgmt3" || true
sudo ip link delete tap-lab3 2>/dev/null && echo "Da xoa tap-lab3" || true

# 2. Xoa Incus nodes
for n in "${NODES[@]}"; do
  $INC delete -f "$n" 2>/dev/null && echo "Da xoa $n" || true
done
$INC profile delete lab-node 2>/dev/null && echo "Da xoa profile lab-node" || true
$INC network delete labbr0   2>/dev/null && echo "Da xoa mang labbr0" || true
$INC network delete mgmtbr0  2>/dev/null && echo "Da xoa mang mgmtbr0" || true

echo "Hoan tat don dep toan bo lab."
