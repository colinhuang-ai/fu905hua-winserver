#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="${SCRIPT_DIR}/qemu-node3/node3.pid"
if [ -f "$PID_FILE" ]; then
  PID=$(cat "$PID_FILE")
  if kill -0 "$PID" 2>/dev/null; then
    echo "Dang dung QEMU node3 (PID: $PID)..."
    sudo kill "$PID" 2>/dev/null || true
    sleep 1
  fi
  rm -f "$PID_FILE"
  echo "Da dung node3."
else
  echo "node3 khong chay."
fi
