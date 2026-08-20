#!/usr/bin/env bash
set -e

[[ $EUID -ne 0 ]] && { echo "请使用 root 身份运行"; exit 1; }

echo "================================"
echo "   Xray SOCKS5 一键安装 v2.1"
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
    apk add bash curl wget unzip
    ;;
debian)
    apt update
    apt install -y curl wget unzip
    ;;
rhel)
    dnf install -y curl wget unzip
    ;;
centos)
    yum install -y curl wget unzip
    ;;
esac

# 安装 Xray
if [[ "$OS" == "alpine" ]]; then
    echo "正在安装 Xray（二进制方式）..."

    VER=$(curl -fsSL https://api.github.com/repos/XTLS/Xray-core/releases/latest \
        | grep tag_name | cut -d '"' -f4)

    case "$(uname -m)" in
        x86_64) ARCH="64" ;;
        aarch64) ARCH="arm64-v8a" ;;
        armv7l) ARCH="arm32-v7a" ;;
        *)
            echo "不支持的架构"
            exit 1
        ;;
    esac

    wget -q -O /tmp/xray.zip \
    "https://github.com/XTLS/Xray-core/releases/download/${VER}/Xray-linux-${ARCH}.zip"

    mkdir -p /usr/local/xray
    unzip -oq /tmp/xray.zip -d /usr/local/xray

    install -m755 /usr/local/xray/xray /usr/local/bin/xray

    mkdir -p /usr/local/share/xray
    cp /usr/local/xray/*.dat /usr/local/share/xray/ 2>/dev/null || true

    cat >/etc/init.d/xray <<'EOF'
#!/sbin/openrc-run
name="Xray"
command="/usr/local/bin/xray"
command_args="-config /usr/local/etc/xray/config.json"
pidfile="/run/xray.pid"
command_background=true
depend() { need net; }
EOF

    chmod +x /etc/init.d/xray

else
    echo "正在安装 Xray（官方方式）..."
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
fi

mkdir -p /usr/local/etc/xray

# 用户输入
read -p "请输入 SOCKS5 端口 (默认10808): " PORT
PORT=${PORT:-10808}

read -p "请输入用户名: " USER

while true; do
    read -s -p "请输入密码: " PASS
    echo
    read -s -p "请再次输入密码: " PASS2
    echo
    [[ "$PASS" == "$PASS2" ]] && break
    echo "两次密码不一致，请重新输入！"
done

# 配置文件
cat >/usr/local/etc/xray/config.json <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "port": $PORT,
    "protocol": "socks",
    "settings": {
      "auth": "password",
      "accounts": [{
        "user": "$USER",
        "pass": "$PASS"
      }],
      "udp": true
    },
    "sniffing": {
      "enabled": true,
      "destOverride": ["http","tls","quic"]
    }
  }],
  "outbounds": [{
    "protocol": "freedom"
  }]
}
EOF

# 防火墙
if command -v ufw >/dev/null; then
    ufw allow ${PORT}/tcp || true
    ufw allow ${PORT}/udp || true
fi

if command -v firewall-cmd >/dev/null; then
    firewall-cmd --permanent --add-port=${PORT}/tcp || true
    firewall-cmd --permanent --add-port=${PORT}/udp || true
    firewall-cmd --reload || true
fi

# 启动服务
if [[ "$OS" == "alpine" ]]; then
    rc-update add xray default >/dev/null
    rc-service xray restart || rc-service xray start
else
    systemctl enable xray
    systemctl restart xray
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
