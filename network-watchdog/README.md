一个用于 Proxmox VE 的监控脚本。它会持续监控主机的外部网络连接和特定的内核日志。只有当两个条件**同时满足**（外部网络中断**且**日志中出现特定错误）时，脚本才会自动重启主机，从而智能地解决 `e1000e` 驱动在高负载下可能导致的硬件挂起问题。

## 脚本功能

- **双重检查**: 同时监控网络连通性和内核日志，避免因短暂网络波动而误重启。
- **自动恢复**: 当检测到特定问题时，自动重启主机，恢复服务。
- **轻量级**: 脚本非常轻量，对系统资源占用极小。
- **可配置**: 目标 IP、监控关键词和检查间隔时间都可以轻松修改。

## 使用方法

### 1. 安装脚本

将 `network-watchdog.sh` 文件保存到 `/usr/local/bin/` 目录下，并赋予执行权限。

```bash
mv network-watchdog.sh /usr/local/bin/
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

现在，`network-watchdog` 服务已在后台运行。你可以使用 `sudo systemctl status network-watchdog.service` 命令检查其状态。

## 日志管理

脚本的日志输出到 `/var/log/network-watchdog.log` 文件。为了防止日志文件无限增长，强烈建议配置 `logrotate` 来管理日志轮转。

### 1. 创建 `logrotate` 配置文件

```bash
vim /etc/logrotate.d/network-watchdog
```

### 2. 粘贴配置内容

将以下内容粘贴到文件中，这会设置日志每天轮转一次，保留 7 个历史文件，并进行压缩。

```
/var/log/network-watchdog.log {
    daily
    missingok
    rotate 7
    compress
    notifempty
    create 0640 root root
}
```

配置完成后，`logrotate` 将自动接管日志文件的管理。
