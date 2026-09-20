#!/usr/bin/env bash
# 02-create-qemu-node3.sh - Tao may ao QEMU node3 (Ubuntu 24.04, 1 CPU, 1GiB RAM)
# Ket noi vao 2 bridge: mgmtbr0 (NAT) va labbr0 (co lap)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QEMU_DIR="${SCRIPT_DIR}/qemu-node3"
MGMT_NET="${MGMT_NET:-mgmtbr0}"
LAB_NET="${LAB_NET:-labbr0}"
LAB_IP="${LAB_IP:-10.10.10.13}"
CPU="${CPU:-1}"
MEM="${MEM:-1024}"

info() { printf '\033[1;34m[i]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[X]\033[0m %s\n' "$*" >&2; }

# --- 1. Kiem tra mang bridge cua Incus -----------------------------------
if ! ip link show "$MGMT_NET" >/dev/null 2>&1; then
  err "Chua tim thay bridge $MGMT_NET. Hay chay ./02-create-lab.sh truoc!"
  exit 1
fi
if ! ip link show "$LAB_NET" >/dev/null 2>&1; then
  err "Chua tim thay bridge $LAB_NET. Hay chay ./02-create-lab.sh truoc!"
  exit 1
fi

# --- 2. Cai dat goi QEMU & Cloud-Init tool ------------------------------
PKGS_TO_INSTALL=()
command -v qemu-system-x86_64 >/dev/null 2>&1 || PKGS_TO_INSTALL+=(qemu-system-x86)
command -v qemu-img >/dev/null 2>&1           || PKGS_TO_INSTALL+=(qemu-utils)
command -v cloud-localds >/dev/null 2>&1      || PKGS_TO_INSTALL+=(cloud-image-utils)

if [ "${#PKGS_TO_INSTALL[@]}" -gt 0 ]; then
  info "Dang cai dat cac goi can thiet: ${PKGS_TO_INSTALL[*]}..."
  sudo apt-get update -qq
  sudo apt-get install -y -qq "${PKGS_TO_INSTALL[@]}" >/dev/null
  ok "Da cai dat xong QEMU va cloud-image-utils."
fi

mkdir -p "$QEMU_DIR"

# --- 3. Tao 2 card TAP noi vao bridge ------------------------------------
info "Cau hinh TAP interface cho QEMU..."
if ! ip link show tap-mgmt3 >/dev/null 2>&1; then
  sudo ip tuntap add dev tap-mgmt3 mode tap
fi
sudo ip link set dev tap-mgmt3 master "$MGMT_NET" up

if ! ip link show tap-lab3 >/dev/null 2>&1; then
  sudo ip tuntap add dev tap-lab3 mode tap
fi
sudo ip link set dev tap-lab3 master "$LAB_NET" up
ok "Card tap-mgmt3 -> $MGMT_NET, tap-lab3 -> $LAB_NET da san sang."

# --- 4. Tai Ubuntu 24.04 Cloud Image ------------------------------------
BASE_IMG="${QEMU_DIR}/ubuntu-24.04-minimal-cloudimg.img"
if [ ! -f "$BASE_IMG" ]; then
  info "Dang tai Ubuntu 24.04 Minimal Cloud Image (~350MB)..."
  curl -fSL "https://cloud-images.ubuntu.com/minimal/releases/noble/release/ubuntu-24.04-minimal-cloudimg-amd64.img" -o "${BASE_IMG}.tmp"
  mv "${BASE_IMG}.tmp" "$BASE_IMG"
  ok "Tai xong cloud image."
else
  ok "Cloud image da co san: $BASE_IMG"
fi

# Tao o dia overlay cho node3 neu chua co
NODE3_DISK="${QEMU_DIR}/node3.qcow2"
if [ ! -f "$NODE3_DISK" ]; then
  info "Tao disk overlay node3.qcow2..."
  qemu-img create -f qcow2 -F qcow2 -b "$BASE_IMG" "$NODE3_DISK" 10G >/dev/null
  ok "Da tao o dia overlay node3.qcow2 (10GB)."
fi

# --- 5. Tao Cloud-init Seed (user-data & meta-data) ----------------------
USER_DATA="${QEMU_DIR}/user-data"
META_DATA="${QEMU_DIR}/meta-data"
SEED_ISO="${QEMU_DIR}/seed.iso"

cat > "$META_DATA" <<EOF
instance-id: node3
local-hostname: node3
EOF

cat > "$USER_DATA" <<'EOF'
#cloud-config
hostname: node3
manage_etc_hosts: false
users:
  - default
  - name: ubuntu
    gecos: Ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    plain_text_passwd: "ubuntu"
ssh_pwauth: true
write_files:
  - path: /etc/netplan/99-lab.yaml
    content: |
      network:
        version: 2
        ethernets:
          mgmt:
            match:
              macaddress: "52:54:00:12:34:01"
            set-name: eth0
            dhcp4: true
          lab:
            match:
              macaddress: "52:54:00:12:34:02"
            set-name: eth1
            dhcp4: false
            addresses:
              - 10.10.10.13/24
runcmd:
  - netplan apply
  - echo "10.10.10.11  node1" >> /etc/hosts
  - echo "10.10.10.12  node2" >> /etc/hosts
  - echo "10.10.10.13  node3" >> /etc/hosts
  - export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y -qq iproute2 iputils-ping tcpdump traceroute iperf3 nmap nftables netcat-openbsd dnsutils >/dev/null 2>&1
EOF

cloud-localds "$SEED_ISO" "$USER_DATA" "$META_DATA"
ok "Da tao cloud-init seed ISO."

# --- 6. Khoi dong node3 (QEMU) -------------------------------------------
PID_FILE="${QEMU_DIR}/node3.pid"
if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  ok "node3 QEMU da dang chay (PID: $(cat "$PID_FILE"))."
else
  # Kiem tra KVM
  ACCEL_ARGS=""
  if [ -e /dev/kvm ] && [ -w /dev/kvm ] && qemu-system-x86_64 -accel kvm -display none 2>/dev/null; then
    ACCEL_ARGS="-enable-kvm -cpu host"
    ok "Che do tang toc KVM: BAT."
  else
    ACCEL_ARGS="-accel tcg,thread=multi -cpu max"
    warn "KVM khong kha dung tren WSL nay. Chuyen sang che do TCG mo phong phan mem."
    info "(Meo: Them [wsl2] nestedVirtualization=true vao %USERPROFILE%\\.wslconfig de tang toc KVM)"
  fi

  info "Dang khoi dong may ao QEMU node3 (background)..."
  sudo qemu-system-x86_64 \
    -name node3 \
    -m "$MEM" \
    -smp "$CPU" \
    $ACCEL_ARGS \
    -drive file="$NODE3_DISK",format=qcow2,if=virtio \
    -drive file="$SEED_ISO",format=raw,if=virtio \
    -netdev tap,id=net0,ifname=tap-mgmt3,script=no,downscript=no \
    -device virtio-net-pci,netdev=net0,mac=52:54:00:12:34:01 \
    -netdev tap,id=net1,ifname=tap-lab3,script=no,downscript=no \
    -device virtio-net-pci,netdev=net1,mac=52:54:00:12:34:02 \
    -display none \
    -serial telnet:127.0.0.1:4444,server,nowait \
    -pidfile "$PID_FILE" \
    -daemonize

  sleep 2
  if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    ok "node3 QEMU khoi dong thanh cong (PID: $(cat "$PID_FILE"))."
  else
    err "Khong the khoi dong QEMU node3. Kiem tra log!"
    exit 1
  fi
fi

# --- 7. Tao cac script tien ich -----------------------------------------
cat > "${SCRIPT_DIR}/stop-node3.sh" <<'EOF'
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
EOF
chmod +x "${SCRIPT_DIR}/stop-node3.sh"

cat > "${SCRIPT_DIR}/start-node3.sh" <<'EOF'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"${SCRIPT_DIR}/02-create-qemu-node3.sh"
EOF
chmod +x "${SCRIPT_DIR}/start-node3.sh"

cat > "${SCRIPT_DIR}/console-node3.sh" <<'EOF'
#!/usr/bin/env bash
echo "Ket noi den Serial Console cua node3 qua telnet (Bam Ctrl+] roi go quit de thoat)..."
telnet 127.0.0.1 4444
EOF
chmod +x "${SCRIPT_DIR}/console-node3.sh"

echo
ok "Hoan tat khoi tao node3!"
info "Cach vao node3:"
echo "  1. SSH tu node1/node2 hoac WSL:  ssh ubuntu@10.10.10.13 (mat khau: ubuntu)"
echo "  2. Vao Serial Console truc tiep: ./console-node3.sh (hoac telnet 127.0.0.1 4444)"
echo "  3. Dung / Bat lai node3:         ./stop-node3.sh | ./start-node3.sh"
