#!/usr/bin/env bash
set -euo pipefail

[[ $EUID -ne 0 ]] && { echo "❌ 请使用 root 身份运行"; exit 1; }

VERSION="2.2"
XRAY_DIR="/usr/local/xray"
XRAY_BIN="/usr/local/bin/xray"
CONFIG_DIR="/usr/local/etc/xray"
CONFIG_FILE="${CONFIG_DIR}/config.json"
ASSET_DIR="/usr/local/share/xray"

log() { echo "[+] $*"; }
error() { echo "[!] $*" >&2; exit 1; }

cleanup() {
    rm -f /tmp/xray.zip /tmp/xray.tar.gz
}
trap cleanup EXIT

echo "================================"
echo "   Xray SOCKS5 一键安装 v${VERSION}"
echo "================================"

# 系统检测
if command -v apk >/dev/null 2>&1; then
    OS="alpine"
elif command -v apt-get >/dev/null 2>&1; then
    OS="debian"
elif command -v dnf >/dev/null 2>&1; then
    OS="rhel"
elif command -v yum >/dev/null 2>&1; then
    OS="centos"
else
    error "不支持当前系统"
fi

echo "检测到系统：${OS}"

# 安装依赖
case "$OS" in
    alpine)
        apk update
        apk add --no-cache bash curl wget unzip jq ca-certificates
        ;;
    debian)
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y curl wget unzip jq ca-certificates
        ;;
    rhel)
        dnf install -y curl wget unzip jq ca-certificates
        ;;
    centos)
        yum install -y curl wget unzip jq ca-certificates
        ;;
esac

# 安装 Xray
if [[ "$OS" == "alpine" ]]; then
    log "Alpine detected: 使用 Xray 官方 Linux 二进制 + OpenRC"

    ARCH_RAW="$(uname -m)"
    case "$ARCH_RAW" in
        x86_64|amd64) XRAY_ARCH="64" ;;
        aarch64|arm64) XRAY_ARCH="arm64-v8a" ;;
        armv7l|armv7) XRAY_ARCH="arm32-v7a" ;;
        i386|i686) XRAY_ARCH="32" ;;
        *) error "不支持的 CPU 架构：${ARCH_RAW}" ;;
    esac

    VER="$(curl -fsSL https://api.github.com/repos/XTLS/Xray-core/releases/latest \
        | jq -r '.tag_name')"
    [[ -n "$VER" && "$VER" != "null" ]] || error "无法获取 Xray 最新版本"

    XRAY_URL="https://github.com/XTLS/Xray-core/releases/download/${VER}/Xray-linux-${XRAY_ARCH}.zip"
    log "Xray 版本：${VER}"
    log "CPU 架构：${ARCH_RAW} -> ${XRAY_ARCH}"

    wget -q --show-progress -O /tmp/xray.zip "$XRAY_URL" \
        || error "Xray 下载失败：${XRAY_URL}"

    rm -rf "$XRAY_DIR"
    mkdir -p "$XRAY_DIR" "$ASSET_DIR"
    unzip -oq /tmp/xray.zip -d "$XRAY_DIR"

    [[ -x "${XRAY_DIR}/xray" ]] || error "Xray 二进制文件不存在"
    install -m 0755 "${XRAY_DIR}/xray" "$XRAY_BIN"

    # geoip.dat / geosite.dat 等资源
    find "$XRAY_DIR" -maxdepth 1 -type f -name '*.dat' -exec cp -f {} "$ASSET_DIR/" \;

    # Alpine 使用 OpenRC
    cat >/etc/init.d/xray <<'EOF'
#!/sbin/openrc-run

name="Xray"
description="Xray SOCKS5 service"
command="/usr/local/bin/xray"
command_args="run -config /usr/local/etc/xray/config.json"
command_user="root:root"
pidfile="/run/xray.pid"
command_background="yes"

output_log="/var/log/xray.log"
error_log="/var/log/xray-error.log"

depend() {
    need net
    after firewall
}
EOF

    chmod +x /etc/init.d/xray
else
    log "${OS}: 使用 Xray 官方安装方式"
    bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
fi

mkdir -p "$CONFIG_DIR"

# 用户输入
while true; do
    read -r -p "请输入 SOCKS5 端口 (默认10808): " PORT
    PORT="${PORT:-10808}"
    if [[ "$PORT" =~ ^[0-9]+$ ]] && (( PORT >= 1 && PORT <= 65535 )); then
        break
    fi
    echo "❌ 端口必须是 1-65535 之间的数字"
done

while true; do
    read -r -p "请输入用户名: " USER
    [[ "$USER" =~ ^[A-Za-z0-9._@-]{1,64}$ ]] && break
    echo "❌ 用户名只能包含字母、数字、.、_、@、-，长度 1-64"
done

while true; do
    read -r -s -p "请输入密码: " PASS
    echo
    read -r -s -p "请再次输入密码: " PASS2
    echo
    [[ -n "$PASS" ]] || { echo "❌ 密码不能为空"; continue; }
    [[ "$PASS" == "$PASS2" ]] && break
    echo "❌ 两次密码不一致，请重新输入！"
done

# 使用 jq 生成 JSON，避免用户名/密码中的特殊字符破坏配置
TMP_CONFIG="${CONFIG_FILE}.tmp"
jq -n \
    --argjson port "$PORT" \
    --arg user "$USER" \
    --arg pass "$PASS" \
    '{
      log: {loglevel: "warning"},
      inbounds: [{
        port: $port,
        protocol: "socks",
        settings: {
          auth: "password",
          accounts: [{user: $user, pass: $pass}],
          udp: true
        },
        sniffing: {
          enabled: true,
          destOverride: ["http", "tls", "quic"]
        }
      }],
      outbounds: [{protocol: "freedom"}]
    }' > "$TMP_CONFIG"

mv "$TMP_CONFIG" "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"

# Alpine 资源目录
if [[ "$OS" == "alpine" ]]; then
    mkdir -p "$ASSET_DIR"
    chown -R root:root "$ASSET_DIR" "$CONFIG_DIR"
fi

# 配置检查
log "检查 Xray 配置..."
if [[ "$OS" == "alpine" ]]; then
    "$XRAY_BIN" run -test -config "$CONFIG_FILE" \
        || error "Xray 配置检查失败"
else
    xray run -test -config "$CONFIG_FILE" \
        || error "Xray 配置检查失败"
fi

# 防火墙
if command -v ufw >/dev/null 2>&1; then
    ufw allow "${PORT}/tcp" >/dev/null 2>&1 || true
    ufw allow "${PORT}/udp" >/dev/null 2>&1 || true
fi

if command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port="${PORT}/tcp" >/dev/null 2>&1 || true
    firewall-cmd --permanent --add-port="${PORT}/udp" >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
fi

# 启动服务
if [[ "$OS" == "alpine" ]]; then
    rc-update add xray default >/dev/null 2>&1 || true
    rc-service xray restart >/dev/null 2>&1 || rc-service xray start
else
    command -v systemctl >/dev/null 2>&1 || error "未找到 systemctl，无法管理 Xray 服务"
    systemctl enable xray >/dev/null
    systemctl restart xray
fi

# 检查服务状态
if [[ "$OS" == "alpine" ]]; then
    rc-service xray status >/dev/null 2>&1 || error "Xray 启动失败，请执行：rc-service xray status"
else
    systemctl is-active --quiet xray || error "Xray 启动失败，请执行：systemctl status xray"
fi

IP="$(curl -4 -fsSL --max-time 5 https://api.ipify.org 2>/dev/null || true)"
[[ -n "$IP" ]] || IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
IP="${IP:-未知}"

# 不在屏幕上显示明文密码
MASKED_PASS="********"

echo
echo "========== 安装成功 =========="
echo "服务器 : $IP"
echo "端口   : $PORT"
echo "用户名 : $USER"
echo "密码   : $MASKED_PASS"
echo "协议   : SOCKS5"
echo "UDP    : 已开启"
echo "系统   : $OS"
echo "Xray   : $VER"
echo "=============================="
echo
echo "服务状态：正常"
