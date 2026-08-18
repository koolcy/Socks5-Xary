# Socks5-Xray

基于 Xray 内核的一键 SOCKS5 代理安装脚本，支持用户名/密码认证，TCP + UDP，并采用交互式配置，无需修改脚本。

## 功能特点

- 一键安装 Xray
- SOCKS5 用户名密码认证
- 支持 TCP / UDP
- 交互输入端口、用户名、密码
- 自动生成配置并启动服务

## 安装命令

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

脚本会提示输入：

- SOCKS5 端口（默认 10808）
- 用户名
- 密码（需确认两次）

示例：

```text
请输入 SOCKS5 端口 (默认10808): 10808
请输入用户名: admin
请输入密码:
请再次输入密码:
```

安装完成后会显示：

```text
服务器 : 1.2.3.4
端口   : 10808
用户名 : admin
密码   : ******
协议   : SOCKS5
```

## 管理命令

```bash
# 查看状态
systemctl status xray

# 重启服务
systemctl restart xray

# 停止服务
systemctl stop xray

# 查看实时日志
journalctl -u xray -f
```

## 客户端配置

| 项目 | 内容 |
|------|------|
| 协议 | SOCKS5 |
| 地址 | 服务器 IP |
| 端口 | 安装时设置 |
| 用户名 | 安装时设置 |
| 密码 | 安装时设置 |
| UDP | 开启 |

## 系统要求

- Debian 11+
- Ubuntu 20.04+
- Root 权限

---

**GitHub：** https://github.com/koolcy/Socks5-Xary