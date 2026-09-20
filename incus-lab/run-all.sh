#!/usr/bin/env bash
# run-all.sh - Chay toan bo: cai Incus -> tao node1, node2 (Incus) -> tao node3 (QEMU) -> kiem tra
set -uo pipefail
cd "$(dirname "$0")"
chmod +x ./*.sh 2>/dev/null || true
LOG="lab-setup.log"
echo "=== $(date '+%F %T') bat dau ===" | tee -a "$LOG"

./01-setup-incus.sh 2>&1 | tee -a "$LOG"
rc=${PIPESTATUS[0]}
if [ "$rc" = "78" ]; then
  echo "[!] Can khoi dong lai WSL roi chay lai script nay." | tee -a "$LOG"
  exit 78
elif [ "$rc" != "0" ]; then
  echo "[X] Buoc 1 that bai (ma loi $rc). Xem $LOG" | tee -a "$LOG"
  exit "$rc"
fi

./02-create-lab.sh 2>&1 | tee -a "$LOG"
rc=${PIPESTATUS[0]}
if [ "$rc" != "0" ]; then
  echo "[X] Buoc 2 (Incus nodes) that bai (ma loi $rc). Xem $LOG" | tee -a "$LOG"
  exit "$rc"
fi

./02-create-qemu-node3.sh 2>&1 | tee -a "$LOG"
rc=${PIPESTATUS[0]}
if [ "$rc" != "0" ]; then
  echo "[X] Buoc tao QEMU node3 that bai (ma loi $rc). Xem $LOG" | tee -a "$LOG"
  exit "$rc"
fi

./03-verify.sh 2>&1 | tee -a "$LOG"

echo
echo "=== HOAN TAT. Nhat ky: $(pwd)/$LOG ==="
echo "Vao may Incus: sudo incus exec node1 -- bash"
echo "Vao may QEMU:  ssh ubuntu@10.10.10.13 hoac ./console-node3.sh"
