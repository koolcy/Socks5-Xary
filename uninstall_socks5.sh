#!/usr/bin/env bash
set -euo pipefail

[[ $EUID -ne 0 ]] && { echo "❌ 请使用 root 身份运行"; exit 1; }

echo "========================================"
echo "   Xray SOCKS5 一键卸载"
echo "========================================"
echo

# Detect the service manager used by the installer
IS_ALPINE=false
if command -v rc-service >/dev/null 2>&1 && [[ -f /etc/init.d/xray ]]; then
    IS_ALPINE=true
fi

echo "[1/6] 停止 Xray 服务..."
if [[ "$IS_ALPINE" == true ]]; then
    rc-service xray stop >/dev/null 2>&1 || true
    rc-update del xray default >/dev/null 2>&1 || true
else
    systemctl stop xray >/dev/null 2>&1 || true
    systemctl disable xray >/dev/null 2>&1 || true
fi

echo "[2/6] 删除服务文件..."
rm -f /etc/systemd/system/xray.service
rm -f /usr/lib/systemd/system/xray.service
rm -f /lib/systemd/system/xray.service
rm -f /etc/init.d/xray

if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload
    systemctl reset-failed xray >/dev/null 2>&1 || true
fi

echo "[3/6] 卸载 Xray..."
# The Debian/RHEL/CentOS installer uses the official Xray installer.
if [[ "$IS_ALPINE" == false ]] && { [[ -f /usr/local/bin/xray ]] || command -v xray >/dev/null 2>&1; }; then
    if curl -fsSL --max-time 20 \
        https://github.com/XTLS/Xray-install/raw/main/install-release.sh \
        | bash -s -- remove; then
        echo "    ✓ Xray 官方卸载完成"
    else
        echo "    ⚠ 官方卸载脚本执行失败，继续清理本地残留"
    fi
fi

echo "[4/6] 删除 Xray / SOCKS5 配置..."
rm -rf /usr/local/etc/xray
rm -rf /etc/xray

# Remove the installer-specific Alpine directories as well.
rm -rf /usr/local/xray
rm -rf /usr/local/share/xray

# Remove binaries left by either installation method.
rm -f /usr/local/bin/xray
rm -f /usr/bin/xray
rm -f /usr/bin/xray-linux-64

echo "[5/6] 删除 Xray 日志..."
rm -rf /var/log/xray
rm -f /var/log/xray.log
rm -f /var/log/xray-error.log
rm -f /var/log/xray-access.log
rm -f /var/log/xray-error.log

# Remove temporary files created by the installer.
rm -f /tmp/xray.zip
rm -f /tmp/xray.tar.gz

# Remove runtime PID files if present.
rm -f /run/xray.pid
rm -f /var/run/xray.pid

# Remove systemd drop-ins specifically belonging to Xray.
rm -rf /etc/systemd/system/xray.service.d

 echo "[6/6] 刷新服务管理器..."
if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload
    systemctl reset-failed >/dev/null 2>&1 || true
fi

if command -v rc-update >/dev/null 2>&1; then
    rc-update del xray default >/dev/null 2>&1 || true
fi

echo
echo "========================================"
echo "        ✓ Xray SOCKS5 卸载完成"
echo "========================================"
echo

echo "检查结果："

if command -v xray >/dev/null 2>&1 || [[ -e /usr/local/bin/xray ]] || [[ -e /usr/bin/xray ]]; then
    echo "⚠ Xray 程序：仍存在"
else
    echo "✓ Xray 程序：已删除"
fi

if [[ -d /usr/local/etc/xray ]] || [[ -d /etc/xray ]]; then
    echo "⚠ SOCKS5 配置：仍存在"
else
    echo "✓ SOCKS5 配置：已删除"
fi

if [[ -e /etc/systemd/system/xray.service ]] || [[ -e /usr/lib/systemd/system/xray.service ]] || [[ -e /lib/systemd/system/xray.service ]] || [[ -e /etc/init.d/xray ]]; then
    echo "⚠ 服务文件：仍存在"
else
    echo "✓ systemd/OpenRC 服务：已删除"
fi

if [[ -d /var/log/xray ]] || [[ -f /var/log/xray.log ]] || [[ -f /var/log/xray-error.log ]] || [[ -f /var/log/xray-access.log ]]; then
    echo "⚠ Xray 日志：仍存在"
else
    echo "✓ Xray 日志：已删除"
fi

if [[ -d /usr/local/xray ]] || [[ -d /usr/local/share/xray ]]; then
    echo "⚠ 安装残留：仍存在"
else
    echo "✓ 安装残留：已清理"
fi

echo
echo "注意："
echo "✓ 未修改 UFW 防火墙规则"
echo "✓ 未修改 firewalld 防火墙规则"
echo "✓ 未修改 SSH 配置"
echo "✓ 未删除系统其他软件"
echo
