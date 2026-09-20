#!/usr/bin/env bash
# 02-create-lab.sh - Tao 3 may ao Linux (1 CPU) + 2 mang: quan tri (NAT) & lab (co lap)
set -euo pipefail

# ====== THAM SO (co the sua) ============================================
MGMT_NET="${MGMT_NET:-mgmtbr0}"          # mang quan tri, co NAT ra Internet
MGMT_CIDR="${MGMT_CIDR:-10.20.20.1/24}"
LAB_NET="${LAB_NET:-labbr0}"             # mang lab: switch L2 thuan, KHONG Internet
LAB_PREFIX="${LAB_PREFIX:-10.10.10}"
IMAGE="${IMAGE:-images:ubuntu/24.04/cloud}"
CPU="${CPU:-1}"
MEM="${MEM:-1GiB}"
TOOLS="${TOOLS:-1}"                      # 1 = cai them tcpdump/traceroute/iperf3...
NODES=(node1 node2)
# ========================================================================

info() { printf '\033[1;34m[i]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }

INC="sudo incus"

# --- 1. Mang quan tri: co DHCP + NAT ------------------------------------
if $INC network show "$MGMT_NET" >/dev/null 2>&1; then
  ok "Mang $MGMT_NET da ton tai."
else
  $INC network create "$MGMT_NET" \
      ipv4.address="$MGMT_CIDR" ipv4.nat=true ipv4.dhcp=true \
      ipv6.address=none
  ok "Da tao mang quan tri $MGMT_NET ($MGMT_CIDR, NAT)."
fi

# --- 2. Mang lab: bridge L2 thuan, khong IP host, khong DHCP, khong NAT --
if $INC network show "$LAB_NET" >/dev/null 2>&1; then
  ok "Mang $LAB_NET da ton tai."
else
  $INC network create "$LAB_NET" ipv4.address=none ipv6.address=none
  ok "Da tao mang lab $LAB_NET (co lap hoan toan, tu dat IP tinh)."
fi

# --- 3. Profile: 1 CPU, 2 NIC -------------------------------------------
if ! $INC profile show lab-node >/dev/null 2>&1; then
  $INC profile create lab-node
fi
$INC profile set lab-node limits.cpu="$CPU"
$INC profile set lab-node limits.memory="$MEM"
$INC profile device add lab-node root disk pool=default path=/            2>/dev/null || true
$INC profile device add lab-node eth0 nic network="$MGMT_NET" name=eth0   2>/dev/null || true
$INC profile device add lab-node eth1 nic network="$LAB_NET"  name=eth1   2>/dev/null || true
ok "Profile 'lab-node': ${CPU} CPU, ${MEM} RAM, eth0=$MGMT_NET, eth1=$LAB_NET."

# --- 4. Tao 3 node -------------------------------------------------------
i=0
for n in "${NODES[@]}"; do
  i=$((i+1))
  labip="${LAB_PREFIX}.1${i}"
  if $INC info "$n" >/dev/null 2>&1; then
    ok "$n da ton tai - bo qua buoc tao."
  else
    info "Dang tao $n tu $IMAGE (lan dau se tai image, hoi lau)..."
    $INC launch "$IMAGE" "$n" --profile lab-node
  fi

  info "$n: cho cloud-init hoan tat..."
  $INC exec "$n" -- cloud-init status --wait >/dev/null 2>&1 || true

  # IP tinh tren mang lab
  tmp="$(mktemp)"
  cat > "$tmp" <<EOF
network:
  version: 2
  ethernets:
    eth1:
      dhcp4: false
      dhcp6: false
      addresses: [${labip}/24]
EOF
  $INC file push "$tmp" "$n/etc/netplan/99-lab.yaml" --mode 0600
  rm -f "$tmp"
  $INC exec "$n" -- netplan apply >/dev/null 2>&1 || true
  $INC exec "$n" -- hostnamectl set-hostname "$n" >/dev/null 2>&1 || true
  ok "$n: eth1 = ${labip}/24"
done

# --- 5. /etc/hosts cho ca cac node (bao gom ca node3 QEMU) -------------
hostsfile="$(mktemp)"
{
  echo "# --- lab nodes ---"
  echo "${LAB_PREFIX}.11  node1"
  echo "${LAB_PREFIX}.12  node2"
  echo "${LAB_PREFIX}.13  node3"
} > "$hostsfile"
for n in "${NODES[@]}"; do
  $INC file push "$hostsfile" "$n/tmp/lab-hosts" --mode 0644
  $INC exec "$n" -- bash -c 'grep -q "lab nodes" /etc/hosts || cat /tmp/lab-hosts >> /etc/hosts'
done
rm -f "$hostsfile"
ok "Da cap nhat /etc/hosts (node1/node2/node3)."

# --- 6. Cai cong cu mang (qua eth0 NAT) ---------------------------------
if [ "$TOOLS" = "1" ]; then
  for n in "${NODES[@]}"; do
    info "$n: cai cong cu mang (iproute2, ping, tcpdump, traceroute, iperf3, nmap, nftables)..."
    $INC exec "$n" -- bash -c 'export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y -qq iproute2 iputils-ping tcpdump traceroute iperf3 nmap nftables netcat-openbsd dnsutils >/dev/null 2>&1' || true
  done
  ok "Da cai cong cu mang tren cac node Incus."
fi

echo
$INC list
echo
ok "Xong 2 node Incus! Vao may:  sudo incus exec node1 -- bash"
ok "Tiep theo, khoi dong node3: ./02-create-qemu-node3.sh"
