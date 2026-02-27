#!/bin/bash
# ==================================================
# Hysteria2 [毒脚本去后门纯净版] - 完美复刻抗封锁逻辑
# ==================================================
set -e
[[ $EUID -ne 0 ]] && echo -e "\033[31m必须使用 root 运行\033[0m" && exit 1

echo ">>> [1/5] 初始化抗封锁参数 (复刻原版)..."
SYSTEM="Debian"
PORT=$(( ( RANDOM % 7001 ) + 2000 ))
HOP_START=$((RANDOM % 5000 + 30000))
HOP_END=$((HOP_START + 99))
PORT_HOP_RANGE="${HOP_START}-${HOP_END}"
AUTH_PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
NODE_IP=$(curl -s4m5 https://api.ipify.org || curl -s4m5 https://ifconfig.me)

echo ">>> [2/5] 下载官方纯净 Hysteria2 核心..."
mkdir -p /etc/hysteria/certs
bash <(curl -fsSL https://get.hy2.sh/) > /dev/null 2>&1

echo ">>> [3/5] 生成伪装证书 (Nvidia)..."
openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -keyout /etc/hysteria/certs/key.pem \
    -out /etc/hysteria/certs/cert.pem \
    -subj "/CN=www.nvidia.com" -days 3650 > /dev/null 2>&1

echo ">>> [4/5] 写入服务器配置 (原版 Salamander 混淆)..."
cat > /etc/hysteria/config.yaml <<EOF
listen: :${PORT}
tls:
  cert: /etc/hysteria/certs/cert.pem
  key: /etc/hysteria/certs/key.pem
  sni: www.nvidia.com
obfs:
  type: salamander
  salamander:
    password: cry_me_a_r1ver
quic:
  initStreamReceiveWindow: 26843545
  maxStreamReceiveWindow: 26843545
  initConnReceiveWindow: 67108864
  maxConnReceiveWindow: 67108864
  maxIdleTimeout: 30s
bandwidth:
  up: 100 mbps
  down: 200 mbps
ignoreClientBandwidth: false
disableUDP: false
auth:
  type: password
  password: ${AUTH_PASSWORD}
masquerade:
  type: proxy
  proxy:
    url: https://www.nvidia.com
    rewriteHost: true
transport:
  type: udp
  udp:
    hopInterval: 30s
    hopPortRange: ${PORT_HOP_RANGE}
EOF

echo ">>> [5/5] 配置防火墙并启动服务..."
# 暴力放行防火墙
command -v ufw >/dev/null 2>&1 && ufw allow ${PORT}/udp && ufw allow ${HOP_START}:${HOP_END}/udp && ufw reload
iptables -I INPUT -p udp --dport ${PORT} -j ACCEPT 2>/dev/null
iptables -I INPUT -p udp --dport ${HOP_START}:${HOP_END} -j ACCEPT 2>/dev/null

systemctl enable --now hysteria-server.service > /dev/null 2>&1
systemctl restart hysteria-server.service > /dev/null 2>&1

# 生成客户端一键链接
LINK="hysteria2://${AUTH_PASSWORD}@${NODE_IP}:${PORT}/?insecure=1&sni=www.nvidia.com&mport=${PORT_HOP_RANGE}&obfs=salamander&obfs-password=cry_me_a_r1ver#Xiamen_CC_Safe"

echo -e "\n\033[32m====================================================="
echo -e "  Hysteria2 [毒脚本纯净重制版] 部署成功"
echo -e "=====================================================\033[0m"
echo -e "IP:       ${NODE_IP}"
echo -e "主端口:   ${PORT}"
echo -e "跳跃端口: ${PORT_HOP_RANGE}"
echo -e "混淆密码: cry_me_a_r1ver"
echo -e "-----------------------------------------------------"
echo -e "\033[36m👇 请复制下方链接导入客户端 (v2rayN / Shadowrocket)：\033[0m"
echo -e "\033[36m${LINK}\033[0m"
echo -e "=====================================================\n"
