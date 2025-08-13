一个用于 Proxmox VE 的监控脚本。它会持续监控主机的外部网络连接和特定的内核日志。只有当两个条件**同时满足**（外部网络中断**且**日志中出现特定错误）时，脚本才会自动重启主机，从而智能地解决 `e1000e` 驱动在高负载下可能导致的硬件挂起问题。

## 脚本功能

- **双重检查**: 同时监控网络连通性和内核日志，避免因短暂网络波动而误重启。
- **自动恢复**: 当检测到特定问题时，自动重启主机，恢复服务。
- **轻量级**: 脚本非常轻量，对系统资源占用极小。
- **可配置**: 目标 IP、监控关键词和检查间隔时间都可以轻松修改。

## 配置

默认情况下，脚本会自动将网关作为监控目标。如果无法自动获取，则会使用 `8.8.8.8` 作为备用地址。

如果需要自定义，可以直接编辑 `network-watchdog.sh` 脚本顶部的变量：

- `TARGET_IP`: **(不建议修改)** 监控的目标 IP 地址。留空时脚本会自动获取网关。
- `LOG_KEYWORD`: 内核日志中需要匹配的关键字。
- `MONITOR_INTERVAL`: 检查间隔，单位为秒。
- `LOG_FILE`: 日志文件的路径。

## 使用方法

### 依赖

本脚本依赖以下命令行工具，请确保您的系统已安装：

- `ping` (通常由 `iputils-ping` 包提供)
- `ip` (通常由 `iproute2` 包提供)
- `journalctl` (由 `systemd` 提供)

### 1. 安装脚本

将 `network-watchdog.sh` 文件下载到 `/usr/local/bin/` 目录下，并赋予执行权限。

```bash
wget -O /usr/local/bin/network-watchdog.sh https://git.cencs.com/cjpjxjx/shell/raw/branch/main/network-watchdog/network-watchdog.sh
chmod +x /usr/local/bin/network-watchdog.sh
```

### 2. 配置 `systemd` 服务

为了让脚本在系统启动时自动运行，并作为后台服务持续工作，你需要创建一个 `systemd` 服务文件。

```bash
vim /etc/systemd/system/network-watchdog.service
```

将以下内容粘贴到文件中：

```ini
[Unit]
Description=Network Watchdog Service for Proxmox
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/network-watchdog.sh
Restart=always
User=root

[Install]
WantedBy=multi-user.target
```

保存并关闭文件后，重新加载 `systemd` 并启用服务：

```bash
systemctl daemon-reload
systemctl enable network-watchdog.service
systemctl start network-watchdog.service
```

现在，`network-watchdog` 服务已在后台运行。你可以使用 `systemctl status network-watchdog.service` 命令检查其状态。

## 日志

脚本会将网络中断、内核日志检查等关键事件记录到 `/var/log/network-watchdog.log` 文件中。

你可以通过以下命令实时查看日志：

```bash
tail -f /var/log/network-watchdog.log
```
