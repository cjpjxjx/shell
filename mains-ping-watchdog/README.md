# mains-ping-watchdog

通过 ping 若干由市电供电的设备，判断市电是否中断；当所有目标在连续一段时间内均不可达时，执行安全关机。脚本设计尽量简单，便于在受限环境下运行。

## 文件
- 脚本：`mains-ping-watchdog.sh`

## 运行要求
- 适用于常见 Linux（/bin/sh、ping 可用）。
- 需要 root 权限执行关机命令。
- 建议通过 systemd 长期运行。

## 快速开始
1. 使用 wget 下载脚本到 `/usr/local/bin/mains-ping-watchdog.sh`：

   ```bash
   wget -O /usr/local/bin/mains-ping-watchdog.sh 'https://git.cencs.com/cjpjxjx/shell/raw/branch/main/mains-ping-watchdog/mains-ping-watchdog.sh'
   ```

2. 编辑 `mains-ping-watchdog.sh` 中的变量：
   - `TARGETS`: 以空格分隔的目标 IP 列表（都必须是市电供电设备）。
   - `OUTAGE_SECONDS`: 市电中断判定时长（秒），默认 180（3 分钟）。
   - `CHECK_INTERVAL`: 检测间隔（秒），默认 15。
   - `PING_COUNT`: 每个目标的 ping 次数，默认 1。
   - `PING_TIMEOUT`: 单次 ping 超时（秒），默认 1。
   - `LOG_FILE`: 非空时输出到此文件，否则仅打印到标准输出（默认 `/var/log/mains-ping-watchdog.log`）。
3. 赋予可执行权限：

   ```bash
   chmod +x /usr/local/bin/mains-ping-watchdog.sh
   ```

## systemd 部署
创建单元文件 `/etc/systemd/system/mains-ping-watchdog.service`：

```ini
[Unit]
Description=Mains power watchdog via ping
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/mains-ping-watchdog.sh
Restart=always
RestartSec=10
User=root

[Install]
WantedBy=multi-user.target
```

加载并启动：

```bash
systemctl daemon-reload
systemctl enable --now mains-ping-watchdog.service
```

## 工作逻辑
- 每隔 `CHECK_INTERVAL` 秒对 `TARGETS` 中的每个 IP 执行 `ping -c PING_COUNT -W PING_TIMEOUT`。
- 只有当所有目标在持续 `OUTAGE_SECONDS` 秒内都不可达时，才视为市电中断并执行关机。
- 任一目标恢复可达则清零计时。

## 建议
- 选择至少 2-3 个不同线路/位置的市电供电设备作为目标。
- 避免使用 DNS 名称，以免受 DNS 故障影响。
- 可将日志重定向到文件或交由 journald 收集：`journalctl -u mains-ping-watchdog.service -f`。

## 升级与卸载
- 升级：替换脚本文件后 `systemctl restart mains-ping-watchdog.service`。
- 卸载：`systemctl disable --now mains-ping-watchdog.service` 并删除文件。
