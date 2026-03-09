#!/usr/bin/env bash
# =========================================================
# Xray Minimal Stable Installer for Ubuntu 22.04
# 场景：住宅IP / CN2 / TikTok运营 / OpenClaw共存
# 协议：VLESS + TCP + REALITY + VISION
# 作者：Custom minimal stable edition
# =========================================================

set -Eeuo pipefail

# ========== 固定参数（按你的需求写死） ==========
XRAY_PORT="${XRAY_PORT:-443}"
XRAY_DOMAIN="${XRAY_DOMAIN:-www.apple.com}"
XRAY_UUID="${XRAY_UUID:-}"
XRAY_SHORT_ID="${XRAY_SHORT_ID:-}"
XRAY_EMAIL="${XRAY_EMAIL:-default}"
INSTALL_INFO_FILE="/root/xray-reality-info.txt"
CONFIG_FILE="/usr/local/etc/xray/config.json"
SERVICE_OVERRIDE_DIR="/etc/systemd/system/xray.service.d"
SYSCTL_FILE="/etc/sysctl.d/99-xray-tuning.conf"
# ===============================================

red()    { printf '\033[31m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }

trap 'red "脚本执行失败，退出。"' ERR

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    red "请使用 root 运行此脚本"
    exit 1
  fi
}

check_system() {
  if [[ ! -f /etc/os-release ]]; then
    red "无法识别系统版本"
    exit 1
  fi

  . /etc/os-release

  if [[ "${ID:-}" != "ubuntu" ]]; then
    red "当前脚本只针对 Ubuntu 22.04 优化，当前系统不是 Ubuntu"
    exit 1
  fi

  if [[ "${VERSION_ID:-}" != "22.04" ]]; then
    yellow "当前不是 Ubuntu 22.04，继续执行，但最佳适配是 Ubuntu 22.04"
  fi

  if ! command -v systemctl >/dev/null 2>&1; then
    red "未检测到 systemd，当前系统不适合本脚本"
    exit 1
  fi

  if ! command -v apt-get >/dev/null 2>&1; then
    red "未检测到 apt-get"
    exit 1
  fi
}

install_dependencies() {
  green ">>> 安装基础依赖..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y \
    curl \
    ca-certificates \
    openssl \
    uuid-runtime \
    iptables \
    iproute2 \
    lsof \
    sed \
    grep \
    awk
}

check_port() {
  green ">>> 检查端口占用..."
  if lsof -iTCP:"${XRAY_PORT}" -sTCP:LISTEN -P -n >/dev/null 2>&1; then
    red "端口 ${XRAY_PORT} 已被占用，请先释放后再安装，或者这样运行：XRAY_PORT=8443 bash 脚本名"
    lsof -iTCP:"${XRAY_PORT}" -sTCP:LISTEN -P -n || true
    exit 1
  fi
}

enable_bbr_and_tuning() {
  green ">>> 启用 BBR 和基础网络优化..."
  cat > "${SYSCTL_FILE}" <<'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
fs.file-max = 1048576
net.core.somaxconn = 4096
net.ipv4.tcp_syncookies = 1
EOF

  sysctl --system >/dev/null 2>&1 || true

  local cc
  cc="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)"
  if [[ "$cc" == "bbr" ]]; then
    green "BBR 已启用"
  else
    yellow "BBR 未确认启用成功，但脚本继续执行"
  fi
}

install_xray() {
  green ">>> 使用官方脚本安装 Xray..."
  bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root
}

generate_values() {
  green ">>> 生成配置参数..."

  if [[ -z "${XRAY_UUID}" ]]; then
    XRAY_UUID="$(uuidgen)"
  fi

  if [[ -z "${XRAY_SHORT_ID}" ]]; then
    XRAY_SHORT_ID="$(openssl rand -hex 4)"
  fi

  local key_output
  key_output="$(/usr/local/bin/xray x25519)"

  XRAY_PRIVATE_KEY="$(awk '/Private key/ {print $3}' <<<"$key_output")"
  XRAY_PUBLIC_KEY="$(awk '/Public key/ {print $3}' <<<"$key_output")"

  if [[ -z "${XRAY_PRIVATE_KEY}" || -z "${XRAY_PUBLIC_KEY}" ]]; then
    red "Reality 密钥生成失败"
    exit 1
  fi
}

write_config() {
  green ">>> 写入 Xray 配置文件..."
  mkdir -p /usr/local/etc/xray /var/log/xray

  cat > "${CONFIG_FILE}" <<EOF
{
  "log": {
    "loglevel": "warning",
    "error": "/var/log/xray/error.log",
    "access": "none"
  },
  "inbounds": [
    {
      "tag": "vless-reality",
      "listen": "::",
      "port": ${XRAY_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${XRAY_UUID}",
            "flow": "xtls-rprx-vision",
            "email": "${XRAY_EMAIL}"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${XRAY_DOMAIN}:443",
          "xver": 0,
          "serverNames": [
            "${XRAY_DOMAIN}"
          ],
          "privateKey": "${XRAY_PRIVATE_KEY}",
          "shortIds": [
            "${XRAY_SHORT_ID}"
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "blocked"
    }
  ]
}
EOF
}

optimize_systemd() {
  green ">>> 写入 systemd 优化配置..."
  mkdir -p "${SERVICE_OVERRIDE_DIR}"

  cat > "${SERVICE_OVERRIDE_DIR}/override.conf" <<EOF
[Unit]
Wants=network-online.target
After=network-online.target

[Service]
ExecStart=
ExecStart=/usr/local/bin/xray run -config ${CONFIG_FILE}
ExecStartPre=/usr/local/bin/xray test -config ${CONFIG_FILE}
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576
EOF

  systemctl daemon-reload
}

open_firewall() {
  green ">>> 放行 ${XRAY_PORT}/tcp ..."

  iptables -C INPUT -p tcp --dport "${XRAY_PORT}" -j ACCEPT 2>/dev/null || \
  iptables -I INPUT -p tcp --dport "${XRAY_PORT}" -j ACCEPT

  if command -v ufw >/dev/null 2>&1; then
    ufw allow "${XRAY_PORT}/tcp" >/dev/null 2>&1 || true
  fi
}

start_xray() {
  green ">>> 启动 Xray..."
  /usr/local/bin/xray test -config "${CONFIG_FILE}"
  systemctl enable xray >/dev/null 2>&1
  systemctl restart xray
  sleep 2

  if ! systemctl is-active --quiet xray; then
    red "Xray 启动失败，请执行：journalctl -u xray -n 50 --no-pager"
    exit 1
  fi
}

get_public_ip() {
  local ip=""
  ip="$(curl -4fsSL --max-time 5 https://api.ipify.org 2>/dev/null || true)"
  if [[ -z "$ip" ]]; then
    ip="$(hostname -I | awk '{print $1}')"
  fi
  echo "$ip"
}

save_info() {
  local server_ip
  server_ip="$(get_public_ip)"

  cat > "${INSTALL_INFO_FILE}" <<EOF
==================================================
Xray Reality 安装信息
==================================================
服务器IP: ${server_ip}
端口: ${XRAY_PORT}
UUID: ${XRAY_UUID}
SNI: ${XRAY_DOMAIN}
Public Key: ${XRAY_PUBLIC_KEY}
Short ID: ${XRAY_SHORT_ID}

VLESS 链接:
vless://${XRAY_UUID}@${server_ip}:${XRAY_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${XRAY_DOMAIN}&fp=chrome&pbk=${XRAY_PUBLIC_KEY}&sid=${XRAY_SHORT_ID}&type=tcp&headerType=none#VLESS-Reality-${server_ip}

常用命令:
systemctl status xray
journalctl -u xray -n 50 --no-pager
/usr/local/bin/xray test -config ${CONFIG_FILE}
cat ${INSTALL_INFO_FILE}
==================================================
EOF
}

show_result() {
  green "=================================================="
  green "安装完成"
  green "=================================================="
  cat "${INSTALL_INFO_FILE}"
}

main() {
  require_root
  check_system
  install_dependencies
  check_port
  enable_bbr_and_tuning
  install_xray
  generate_values
  write_config
  optimize_systemd
  open_firewall
  start_xray
  save_info
  show_result
}

main "$@"
