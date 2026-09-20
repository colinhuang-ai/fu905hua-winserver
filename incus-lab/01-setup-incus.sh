#!/usr/bin/env bash
# 01-setup-incus.sh - Cai dat & khoi tao Incus tren Ubuntu WSL
set -euo pipefail

info() { printf '\033[1;34m[i]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[X]\033[0m %s\n' "$*" >&2; }

# --- 1. Kiem tra moi truong ---------------------------------------------
if grep -qi microsoft /proc/version; then
  info "Dang chay trong WSL."
else
  info "Khong phai WSL (van chay duoc tren Ubuntu thuong)."
fi

if [ ! -d /run/systemd/system ]; then
  err "systemd CHUA duoc bat trong WSL. Incus can systemd."
  info "Dang ghi cau hinh systemd vao /etc/wsl.conf..."
  if ! grep -q "systemd=true" /etc/wsl.conf 2>/dev/null; then
    sudo mkdir -p /etc
    if grep -q "^\[boot\]" /etc/wsl.conf 2>/dev/null; then
      sudo sed -i "/^\[boot\]/a systemd=true" /etc/wsl.conf
    else
      printf "[boot]\nsystemd=true\n" | sudo tee -a /etc/wsl.conf >/dev/null
    fi
  fi
  ok "Da bat systemd trong /etc/wsl.conf."
  cat <<'HINT'

  >>> CAN KHOI DONG LAI WSL MOT LAN:
      - Neu ban chay bang RUN-LAB.cmd: script se tu lam, chi can doi.
      - Neu chay tay: mo PowerShell tren Windows, go:  wsl --shutdown
        roi mo lai Ubuntu va chay lai ./run-all.sh

HINT
  exit 78
fi
ok "systemd dang chay."

# --- 2. Cai dat Incus ----------------------------------------------------
if command -v incus >/dev/null 2>&1; then
  ok "Incus da co san: $(incus --version)"
else
  . /etc/os-release
  info "Ubuntu ${VERSION_ID} (${VERSION_CODENAME}) - bat dau cai Incus..."
  sudo apt-get update -qq
  if dpkg --compare-versions "${VERSION_ID}" ge "24.04"; then
    sudo apt-get install -y incus incus-client
  else
    info "Ubuntu < 24.04 -> dung kho zabbly (upstream Incus)."
    sudo apt-get install -y curl gpg
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://pkgs.zabbly.com/key.asc | sudo tee /etc/apt/keyrings/zabbly.asc >/dev/null
    sudo tee /etc/apt/sources.list.d/zabbly-incus-stable.sources >/dev/null <<EOF
Enabled: yes
Types: deb
URIs: https://pkgs.zabbly.com/incus/stable
Suites: ${VERSION_CODENAME}
Components: main
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/zabbly.asc
EOF
    sudo apt-get update -qq
    sudo apt-get install -y incus
  fi
  ok "Da cai: $(incus --version)"
fi

# --- 3. Bat dich vu ------------------------------------------------------
sudo systemctl enable --now incus.socket >/dev/null 2>&1 || true
sudo systemctl enable --now incus.service >/dev/null 2>&1 || true
sudo systemctl start incus >/dev/null 2>&1 || true
sleep 2
if ! sudo incus info >/dev/null 2>&1; then
  err "Khong ket noi duoc incus daemon. Kiem tra: sudo systemctl status incus"
  exit 1
fi
ok "Incus daemon dang chay."

# --- 4. Cho phep user hien tai dung incus khong can sudo ------------------
if getent group incus-admin >/dev/null; then
  if ! id -nG "$USER" | grep -qw incus-admin; then
    sudo usermod -aG incus-admin "$USER"
    info "Da them $USER vao nhom incus-admin (can dang xuat/mo lai WSL de co hieu luc)."
    info "Tam thoi cac script deu dung 'sudo incus' nen van chay duoc ngay."
  fi
fi

# --- 5. Khoi tao storage pool + profile default --------------------------
if sudo incus storage list --format csv 2>/dev/null | grep -q '^default,'; then
  ok "Storage pool 'default' da ton tai."
else
  info "Khoi tao Incus voi storage backend 'dir' (an toan nhat cho WSL)..."
  sudo incus admin init --preseed <<'PRESEED'
config: {}
networks: []
storage_pools:
  - name: default
    driver: dir
profiles:
  - name: default
    devices:
      root:
        path: /
        pool: default
        type: disk
PRESEED
  ok "Da khoi tao storage pool 'default' (driver: dir)."
fi

echo
ok "Buoc 1 hoan tat. Chay tiep:  ./02-create-lab.sh"
