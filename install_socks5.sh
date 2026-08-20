#!/usr/bin/env bash
set -e

[[ $EUID -ne 0 ]] && { echo "请使用 root 身份运行"; exit 1; }

echo "================================"
echo "   Xray SOCKS5 一键安装 v2.0"
echo "================================"

# 系统检测
if command -v apk >/dev/null 2>&1; then
    OS="alpine"
elif command -v apt >/dev/null 2>&1; then
    OS="debian"
elif command -v dnf >/dev/null 2>&1; then
    OS="rhel"
elif command -v yum >/dev/null 2>&1; then
    OS="centos"
else
    echo "❌ 不支持当前系统"
    exit 1
fi

echo "检测到系统：$OS"

# 安装依赖
case "$OS" in
alpine)
    apk update
    apk add bash curl unzip
    ;;
debian)
    apt update
    apt install -y curl unzip
    ;;
rhel)
    dnf install -y curl unzip
    ;;
centos)
    yum install -y curl unzip
    ;;
esac

# 安装 Xray
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

mkdir -p /usr/local/etc/xray

# 用户输入
read -p "请输入 SOCKS5 端口 (默认55566): " PORT
PORT=${PORT:-55566}

read -p "请输入用户名: " USER

while true; do
    read -s -p "请输入密码: " PASS
    echo
    read -s -p "请再次输入密码: " PASS2
    echo
    [[ "$PASS" == "$PASS2" ]] && break
    echo "两次密码不一致，请重新输入！"
done

# 生成配置
cat >/usr/local/etc/xray/config.json <<EOF
{
  "log":{"loglevel":"warning"},
  "inbounds":[
    {
      "port":$PORT,
      "protocol":"socks",
      "settings":{
        "auth":"password",
        "accounts":[
          {
            "user":"$USER",
            "pass":"$PASS"
          }
        ],
        "udp":true
      },
      "sniffing":{
        "enabled":true,
        "destOverride":["http","tls","quic"]
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

# 防火墙
if command -v ufw >/dev/null 2>&1; then
    ufw allow ${PORT}/tcp >/dev/null 2>&1 || true
    ufw allow ${PORT}/udp >/dev/null 2>&1 || true
fi

if command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port=${PORT}/tcp >/dev/null 2>&1 || true
    firewall-cmd --permanent --add-port=${PORT}/udp >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
fi

# 启动服务
if command -v systemctl >/dev/null 2>&1; then
    systemctl enable xray
    systemctl restart xray
elif command -v rc-service >/dev/null 2>&1; then
    rc-update add xray default
    rc-service xray restart || rc-service xray start
fi

IP=$(curl -4 -s https://api.ipify.org || hostname -I | awk '{print $1}')

echo
echo "========== 安装成功 =========="
echo "服务器 : $IP"
echo "端口   : $PORT"
echo "用户名 : $USER"
echo "密码   : $PASS"
echo "协议   : SOCKS5"
echo "UDP    : 已开启"
echo "系统   : $OS"
echo "============================="
