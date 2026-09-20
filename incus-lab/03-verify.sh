#!/usr/bin/env bash
# 03-verify.sh - Kiem tra lab: 2 Incus nodes (node1, node2) + 1 QEMU VM (node3)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INC="sudo incus"
INC_NODES=(node1 node2)
ALL_NODES=(node1 node2 node3)
NODE3_IP="10.10.10.13"
PID_FILE="${SCRIPT_DIR}/qemu-node3/node3.pid"

pass(){ printf '\033[1;32m[PASS]\033[0m %s\n' "$*"; }
fail(){ printf '\033[1;31m[FAIL]\033[0m %s\n' "$*"; }
info(){ printf '\033[1;34m[i]\033[0m %s\n' "$*"; }
sec(){ printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }

sec "Trang thai Incus containers (node1, node2)"
$INC list

sec "Trang thai QEMU VM (node3)"
if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  pass "QEMU node3 dang chay (PID: $(cat "$PID_FILE"))"
else
  fail "QEMU node3 KHONG chay! (Hay khoi dong bang ./02-create-qemu-node3.sh)"
fi

sec "So CPU cac may Incus (mong doi: 1 CPU)"
for n in "${INC_NODES[@]}"; do
  c=$($INC exec "$n" -- nproc 2>/dev/null || echo "0")
  [ "$c" = "1" ] && pass "$n: nproc = $c" || fail "$n: nproc = $c (khong phai 1)"
done

sec "Dia chi IP cac may Incus"
for n in "${INC_NODES[@]}"; do
  echo "--- $n"
  $INC exec "$n" -- ip -brief -4 addr show
done

sec "Ket noi mang lab (eth1) giua cac node"
# node1 <-> node2 (Incus <-> Incus)
if $INC exec node1 -- ping -c1 -W2 -I eth1 node2 >/dev/null 2>&1; then
  pass "node1 -> node2 (Incus <-> Incus qua eth1)"
else
  fail "node1 -> node2 (Incus <-> Incus qua eth1)"
fi

if $INC exec node2 -- ping -c1 -W2 -I eth1 node1 >/dev/null 2>&1; then
  pass "node2 -> node1 (Incus <-> Incus qua eth1)"
else
  fail "node2 -> node1 (Incus <-> Incus qua eth1)"
fi

# node1/node2 -> node3 (Incus -> QEMU)
info "Cho node3 hoan tat khoi dong mang lab..."
retry=0
while [ $retry -lt 15 ]; do
  if $INC exec node1 -- ping -c1 -W2 -I eth1 "$NODE3_IP" >/dev/null 2>&1; then
    break
  fi
  sleep 2
  retry=$((retry+1))
done

if $INC exec node1 -- ping -c1 -W2 -I eth1 "$NODE3_IP" >/dev/null 2>&1; then
  pass "node1 -> node3 (Incus -> QEMU qua eth1 $NODE3_IP)"
else
  fail "node1 -> node3 (Incus -> QEMU qua eth1 $NODE3_IP - neu QEMU moi bat, can doi cloud-init nap mang)"
fi

if $INC exec node2 -- ping -c1 -W2 -I eth1 "$NODE3_IP" >/dev/null 2>&1; then
  pass "node2 -> node3 (Incus -> QEMU qua eth1 $NODE3_IP)"
else
  fail "node2 -> node3 (Incus -> QEMU qua eth1 $NODE3_IP)"
fi

sec "Kiem tra CO LAP: eth1 khong duoc ra Internet"
for n in "${INC_NODES[@]}"; do
  if $INC exec "$n" -- ping -c1 -W2 -I eth1 1.1.1.1 >/dev/null 2>&1; then
    fail "$n: eth1 VAN ra duoc Internet (mang lab chua co lap)"
  else
    pass "$n: eth1 khong ra duoc Internet (dung nhu mong doi)"
  fi
done

sec "Mang quan tri eth0 (co NAT - dung de apt install)"
for n in "${INC_NODES[@]}"; do
  if $INC exec "$n" -- ping -c1 -W3 -I eth0 1.1.1.1 >/dev/null 2>&1; then
    pass "$n: eth0 ra duoc Internet"
  else
    fail "$n: eth0 KHONG ra duoc Internet (kiem tra NAT/firewall cua WSL)"
  fi
done

echo
echo "Kiem tra hoan tat!"
echo "Muon xoa toan bo lab: ./99-destroy.sh"
