#!/usr/bin/env bash
set -e

echo "================================"
echo "      Xray SOCKS5 安装脚本"
echo "================================"

apt update
apt install -y curl unzip

bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

mkdir -p /usr/local/etc/xray

read -p "请输入 SOCKS5 端口 (默认10808): " PORT
PORT=${PORT:-10808}

read -p "请输入用户名: " USER

while true; do
    read -s -p "请输入密码: " PASS
    echo
    read -s -p "请再次输入密码: " PASS2
    echo

    if [[ "$PASS" == "$PASS2" ]]; then
        break
    else
        echo "两次密码不一致，请重新输入！"
    fi
done

cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": $PORT,
      "protocol": "socks",
      "settings": {
        "auth": "password",
        "accounts": [
          {
            "user": "$USER",
            "pass": "$PASS"
          }
        ],
        "udp": true
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOF

systemctl enable xray
systemctl restart xray

IP=$(curl -s https://api.ipify.org || echo "你的服务器IP")

echo

echo "========== 安装成功 =========="
echo "服务器 : $IP"
echo "端口   : $PORT"
echo "用户名 : $USER"
echo "密码   : $PASS"
echo "协议   : SOCKS5"
echo "UDP    : 已开启"
echo "============================="