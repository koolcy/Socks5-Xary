# Socks5-Xray

基于 Xray 内核的一键 SOCKS5 代理安装脚本，支持用户名/密码认证、TCP + UDP，并采用交互式配置，无需修改脚本。

## v2.2

- Alpine Linux 使用 Xray 官方 Linux 二进制安装，不再调用 systemd 安装器
- Alpine 使用 OpenRC 管理 Xray 服务
- 支持 Debian / Ubuntu / RHEL / CentOS 系列
- 自动检测 CPU 架构
- 自动获取最新版 Xray
- 自动验证端口和用户名
- 密码二次确认
- 使用 `jq` 安全生成 JSON 配置
- 安装后自动执行 Xray 配置检查
- 支持 UFW / firewalld 自动放行 SOCKS5 TCP/UDP 端口
- 安装完成后自动检查 Xray 服务状态

## 支持系统

| 系统 | 服务管理 | 包管理 |
|---|---|---|
| Alpine Linux 3.x | OpenRC | apk |
| Debian 11 / 12 | systemd | apt |
| Ubuntu 20.04+ | systemd | apt |
| CentOS 7 | systemd | yum |
| Rocky Linux 8 / 9 | systemd | dnf |
| AlmaLinux 8 / 9 | systemd | dnf |

## 一键安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/koolcy/Socks5-Xary/main/install_socks5.sh)
```

或手动下载：

```bash
git clone https://github.com/koolcy/Socks5-Xary.git
cd Socks5-Xary
chmod +x install_socks5.sh
sudo ./install_socks5.sh
```

## 安装过程

脚本会自动检测操作系统，然后提示输入：

- SOCKS5 端口（默认 `10808`）
- 用户名
- 密码（需确认两次）

示例：

```text
================================
   Xray SOCKS5 一键安装 v2.2
================================
检测到系统：alpine
请输入 SOCKS5 端口 (默认10808): 10808
请输入用户名: admin
请输入密码:
请再次输入密码:
```

安装完成后会显示：

```text
========== 安装成功 ==========
服务器 : 1.2.3.4
端口   : 10808
用户名 : admin
密码   : ********
协议   : SOCKS5
UDP    : 已开启
系统   : alpine
服务状态：正常
```

密码不会在安装完成信息中明文显示。

## Alpine Linux

Alpine 默认使用 OpenRC，因此 v2.2 不使用 Xray 官方 systemd 安装脚本，而是直接下载 Xray Linux 二进制文件，并创建 OpenRC 服务。

查看状态：

```bash
rc-service xray status
```

重启：

```bash
rc-service xray restart
```

停止：

```bash
rc-service xray stop
```

查看日志：

```bash
cat /var/log/xray.log
cat /var/log/xray-error.log
```

## Debian / Ubuntu / CentOS / Rocky / AlmaLinux

查看状态：

```bash
systemctl status xray
```

重启：

```bash
systemctl restart xray
```

停止：

```bash
systemctl stop xray
```

查看日志：

```bash
journalctl -u xray -f
```

## 客户端配置

| 项目 | 内容 |
|---|---|
| 协议 | SOCKS5 |
| 地址 | 服务器 IP |
| 端口 | 安装时设置 |
| 用户名 | 安装时设置 |
| 密码 | 安装时设置 |
| UDP | 开启 |

## 注意事项

1. 请确保服务器安全组放行设置的 TCP/UDP 端口。
2. 如果服务器使用云厂商安全组，还需要在云平台控制台放行对应端口。
3. 安装脚本需要 root 权限。
4. Alpine、Debian、Ubuntu 等发行版的服务管理命令不同，请根据 README 中的系统类型使用对应命令。

---

**GitHub：** https://github.com/koolcy/Socks5-Xary
