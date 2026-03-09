#!/usr/bin/env bash

set -e

PORT=${XRAY_PORT:-443}
DOMAIN=${XRAY_DOMAIN:-www.apple.com}

echo "开始安装 Xray Reality..."

apt update -y
apt install -y curl ca-certificates openssl uuid-runtime iptables lsof gawk

echo "启用BBR..."
cat > /etc/sysctl.d/99-bbr.conf <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF

sysctl --system >/dev/null 2>&1

echo "安装 Xray..."
bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh) install

UUID=$(uuidgen)
SHORT_ID=$(openssl rand -hex 4)

KEY=$(/usr/local/bin/xray x25519)

PRIVATE=$(echo "$KEY" | grep "Private key" | awk '{print $3}')
PUBLIC=$(echo "$KEY" | grep "Public key" | awk '{print $3}')

mkdir -p /usr/local/etc/xray

cat > /usr/local/etc/xray/config.json <<EOF
{
"log":{
"loglevel":"warning"
},
"inbounds":[
{
"port":$PORT,
"protocol":"vless",
"settings":{
"clients":[
{
"id":"$UUID",
"flow":"xtls-rprx-vision"
}
],
"decryption":"none"
},
"streamSettings":{
"network":"tcp",
"security":"reality",
"realitySettings":{
"dest":"$DOMAIN:443",
"serverNames":[
"$DOMAIN"
],
"privateKey":"$PRIVATE",
"shortIds":[
"$SHORT_ID"
]
}
}
}
],
"outbounds":[
{
"protocol":"freedom"
}
]
}
EOF

mkdir -p /etc/systemd/system/xray.service.d

cat > /etc/systemd/system/xray.service.d/override.conf <<EOF
[Unit]
Wants=network-online.target
After=network-online.target

[Service]
ExecStart=
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
ExecStartPre=/usr/local/bin/xray test -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576
EOF

systemctl daemon-reload
systemctl enable xray
systemctl restart xray

iptables -I INPUT -p tcp --dport $PORT -j ACCEPT

IP=$(curl -4 -s https://api.ipify.org)

echo ""
echo "======================================"
echo "安装完成"
echo ""
echo "地址: $IP"
echo "端口: $PORT"
echo "UUID: $UUID"
echo "SNI: $DOMAIN"
echo "PublicKey: $PUBLIC"
echo "ShortID: $SHORT_ID"
echo ""
echo "节点："
echo "vless://$UUID@$IP:$PORT?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$DOMAIN&fp=chrome&pbk=$PUBLIC&sid=$SHORT_ID&type=tcp#Reality"
echo "======================================"
