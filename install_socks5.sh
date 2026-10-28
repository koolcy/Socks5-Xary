#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

[[ ${EUID} -eq 0 ]] || { echo '请使用 root 运行' >&2; exit 1; }
VERSION=2.3
XRAY_BIN=/usr/local/bin/xray
CONFIG_DIR=/usr/local/etc/xray
CONFIG_FILE=$CONFIG_DIR/config.json
ASSET_DIR=/usr/local/share/xray
WORK_DIR=$(mktemp -d)
BACKUP_FILE=$WORK_DIR/config.backup
HAD_CONFIG=0
CONFIG_DEPLOYED=0
SERVICE_WAS_ACTIVE=0
INSTALL_COMPLETE=0
log(){ printf '[+] %s\n' "$*"; }
die(){ printf '[!] %s\n' "$*" >&2; exit 1; }

if command -v apk >/dev/null 2>&1; then OS=alpine
elif command -v apt-get >/dev/null 2>&1; then OS=debian
elif command -v dnf >/dev/null 2>&1; then OS=rhel
elif command -v yum >/dev/null 2>&1; then OS=centos
else die '不支持的系统'; fi

if [[ $OS == alpine ]]; then
  command -v rc-service >/dev/null || die '需要 OpenRC'
else
  command -v systemctl >/dev/null || die '需要 systemd'
  [[ $(cat /proc/1/comm 2>/dev/null || :) == systemd ]] || die '当前环境未运行 systemd'
fi

service_active(){
  if [[ $OS == alpine ]]; then rc-service xray status >/dev/null 2>&1
  else systemctl is-active --quiet xray; fi
}
service_restart(){
  if [[ $OS == alpine ]]; then rc-service xray restart >/dev/null 2>&1 || rc-service xray start
  else systemctl restart xray; fi
}
service_stop(){
  if [[ $OS == alpine ]]; then rc-service xray stop >/dev/null 2>&1 || :
  else systemctl stop xray >/dev/null 2>&1 || :; fi
}
cleanup(){
  local result=$?
  trap - EXIT
  if (( result != 0 && CONFIG_DEPLOYED == 1 && INSTALL_COMPLETE == 0 )); then
    printf '[!] 安装失败，尝试恢复原配置\n' >&2
    if (( HAD_CONFIG == 1 )); then
      cp -p "$BACKUP_FILE" "$CONFIG_FILE" || :
    else
      rm -f "$CONFIG_FILE"
    fi
    if (( SERVICE_WAS_ACTIVE == 1 )); then service_restart || :
    else service_stop; fi
  fi
  rm -rf "$WORK_DIR"
  exit "$result"
}
trap cleanup EXIT

printf '================================\n Xray SOCKS5 安装 v%s\n 系统: %s\n================================\n' "$VERSION" "$OS"
case $OS in
  alpine) apk update; apk add --no-cache bash curl wget unzip jq ca-certificates shadow util-linux ;;
  debian) apt-get update; DEBIAN_FRONTEND=noninteractive apt-get install -y curl wget unzip jq ca-certificates util-linux ;;
  rhel) dnf install -y curl wget unzip jq ca-certificates util-linux ;;
  centos) yum install -y curl wget unzip jq ca-certificates util-linux ;;
esac

if service_active; then SERVICE_WAS_ACTIVE=1; fi

if [[ $OS == alpine ]]; then
  case $(uname -m) in
    x86_64|amd64) XRAY_ARCH=64 ;;
    aarch64|arm64) XRAY_ARCH=arm64-v8a ;;
    armv7l|armv7) XRAY_ARCH=arm32-v7a ;;
    i386|i686) XRAY_ARCH=32 ;;
    *) die "不支持的架构: $(uname -m)" ;;
  esac
  RELEASE=$(curl -fsSL --retry 3 https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -er '.tag_name')
  [[ $RELEASE =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die 'Xray 版本格式异常'
  URL="https://github.com/XTLS/Xray-core/releases/download/${RELEASE}/Xray-linux-${XRAY_ARCH}.zip"
  curl -fL --retry 3 "$URL" -o "$WORK_DIR/xray.zip" || die 'Xray 下载失败'
  mkdir -p "$WORK_DIR/extract" "$ASSET_DIR"
  unzip -oq "$WORK_DIR/xray.zip" -d "$WORK_DIR/extract"
  [[ -f $WORK_DIR/extract/xray ]] || die '压缩包中缺少 xray'
  install -m 0755 "$WORK_DIR/extract/xray" "$XRAY_BIN"
  find "$WORK_DIR/extract" -maxdepth 1 -type f -name '*.dat' -exec install -m 0644 {} "$ASSET_DIR/" \;
  if ! id xray >/dev/null 2>&1; then
    addgroup -S xray 2>/dev/null || :
    adduser -S -D -H -s /sbin/nologin -G xray xray
  fi
  cat >/etc/init.d/xray <<'OPENRC'
#!/sbin/openrc-run
name="Xray"
description="Xray SOCKS5 service"
command="/usr/local/bin/xray"
command_args="run -config /usr/local/etc/xray/config.json"
command_user="xray:xray"
command_background="yes"
pidfile="/run/xray.pid"
output_log="/var/log/xray.log"
error_log="/var/log/xray-error.log"
export XRAY_LOCATION_ASSET="/usr/local/share/xray"
depend() { need net; }
OPENRC
  chmod 755 /etc/init.d/xray
  rc-update add xray default >/dev/null
else
  log '执行 Xray 官方安装器（请确认信任上游脚本）'
  curl -fsSL --retry 3 https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh -o "$WORK_DIR/install-release.sh"
  bash "$WORK_DIR/install-release.sh" install
fi

[[ -x $XRAY_BIN ]] || die 'Xray 安装后未找到可执行文件'
if [[ $OS != alpine ]]; then
  id xray >/dev/null 2>&1 || die 'Xray 服务账户不存在'
  [[ -f /etc/systemd/system/xray.service ]] || die '未找到 Xray systemd 服务'
  SERVICE_USER=$(systemctl show xray -p User --value)
  [[ $SERVICE_USER == xray ]] || die "服务运行用户为 ${SERVICE_USER:-root}，脚本预期为 xray，请人工检查"
fi

while :; do
  read -r -p '请输入 SOCKS5 端口 (默认10808): ' PORT
  PORT=${PORT:-10808}
  if [[ $PORT =~ ^[0-9]{1,5}$ ]] && (( 10#$PORT >= 1 && 10#$PORT <= 65535 )); then
    PORT=$((10#$PORT)); break
  fi
  echo '端口必须是 1-65535 的整数'
done

while :; do
  read -r -p '请输入用户名: ' USERNAME
  [[ $USERNAME =~ ^[A-Za-z0-9._@-]{1,64}$ ]] && break
  echo '用户名只能包含字母、数字、._@-，长度 1-64'
done

while :; do
  read -r -s -p '请输入密码: ' PASSWORD; echo
  read -r -s -p '再次输入密码: ' PASSWORD2; echo
  [[ -n $PASSWORD ]] || { echo '密码不能为空'; continue; }
  [[ $PASSWORD == "$PASSWORD2" ]] && break
  echo '两次密码不一致'
done

# 对既有 SOCKS5 监听端口允许原服务占用；其他冲突交由启动检测。
if command -v ss >/dev/null 2>&1 && ss -H -lntup 2>/dev/null | grep -Eq "(^|[[:space:]])[^[:space:]]+:${PORT}[[:space:]]"; then
  log "提示：端口 $PORT 当前已有监听，请确认是否属于现有 Xray 服务"
fi

mkdir -p "$CONFIG_DIR"
if [[ -e $CONFIG_FILE ]]; then
  [[ -f $CONFIG_FILE && ! -L $CONFIG_FILE ]] || die '配置文件不是普通文件，拒绝覆盖'
  cp -p "$CONFIG_FILE" "$BACKUP_FILE"
  HAD_CONFIG=1
fi

jq -n --argjson port "$PORT" --arg user "$USERNAME" --arg pass "$PASSWORD" '{
  log:{loglevel:"warning"},
  inbounds:[{listen:"0.0.0.0",port:$port,protocol:"socks",settings:{auth:"password",accounts:[{user:$user,pass:$pass}],udp:true},sniffing:{enabled:true,destOverride:["http","tls","quic"]}}],
  outbounds:[{protocol:"freedom"}]
}' > "$WORK_DIR/config.json"
unset PASSWORD PASSWORD2

# 安全地赋予服务组读取权限，同时保留 root 所有权。
chown root:xray "$CONFIG_DIR"
chmod 750 "$CONFIG_DIR"
chown root:xray "$WORK_DIR/config.json"
chmod 640 "$WORK_DIR/config.json"
# 临时目录默认 0700；复制到配置目录后再以服务账户验证。
install -o root -g xray -m 0640 "$WORK_DIR/config.json" "$CONFIG_DIR/.config.json.v23.tmp"
mv -f "$CONFIG_DIR/.config.json.v23.tmp" "$CONFIG_FILE"
CONFIG_DEPLOYED=1

log '以 xray 服务账户验证配置及权限'
runuser -u xray -- test -r "$CONFIG_FILE" || die 'xray 无法读取配置'
runuser -u xray -- "$XRAY_BIN" run -test -config "$CONFIG_FILE" || die 'Xray 配置检查失败'

if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
  ufw allow "${PORT}/tcp" || log 'UFW TCP 规则添加失败'
  ufw allow "${PORT}/udp" || log 'UFW UDP 规则添加失败'
fi
if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
  firewall-cmd --permanent --add-port="${PORT}/tcp" || log 'firewalld TCP 规则添加失败'
  firewall-cmd --permanent --add-port="${PORT}/udp" || log 'firewalld UDP 规则添加失败'
  firewall-cmd --reload || log 'firewalld 重载失败'
fi

service_restart || die '服务重启失败，请查看服务日志'
service_active || die 'Xray 服务未正常运行'
INSTALL_COMPLETE=1
XRAY_VERSION=$("$XRAY_BIN" version | awk 'NR==1 {print $2}')
PUBLIC_IP=$(curl -4 -fsSL --max-time 5 https://api.ipify.org 2>/dev/null || :)
PUBLIC_IP=${PUBLIC_IP:-未知}
printf '\n========== 安装成功 ==========\n服务器 : %s\n端口   : %s\n用户名 : %s\n密码   : ********\n协议   : SOCKS5 (TCP/UDP)\n系统   : %s\nXray   : %s\n==============================\n' "$PUBLIC_IP" "$PORT" "$USERNAME" "$OS" "${XRAY_VERSION:-unknown}"
