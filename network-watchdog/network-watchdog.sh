#!/bin/bash

# 脚本名称: network-watchdog.sh
# 功能: 监测外部网络和特定内核日志，当两者都符合条件时自动重启主机

# 监测目标IP，请修改为你的网关或任何稳定的外部IP
TARGET_IP="8.8.8.8"
# 监测日志关键词
LOG_KEYWORD="Detected Hardware Unit Hang"
# 监测间隔时间（秒）
MONITOR_INTERVAL=60

# 记录日志文件
LOG_FILE="/var/log/network-watchdog.log"

# 创建或清空日志文件
echo "脚本启动时间: $(date)" > $LOG_FILE
echo "-------------------------------------" >> $LOG_FILE

while true
do
    # 步骤1: 检查外部网络连接
    ping -c 1 -W 2 $TARGET_IP > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        # ping 成功，表示网络正常，直接进入下一次循环
        echo "$(date): Network is up." >> $LOG_FILE
    else
        # ping 失败，进入步骤2: 检查日志
        echo "$(date): Network to $TARGET_IP is down. Checking logs for specific error..." >> $LOG_FILE

        # 检查最近5分钟内的内核日志是否包含指定关键词
        # 使用 -k 只查看内核日志，--since "5 minutes ago" 确保只查看最新日志
        if journalctl --since "5 minutes ago" -k | grep -q "$LOG_KEYWORD"; then
            # 两个条件都符合：网络断开 AND 日志中有特定错误
            echo "$(date): !!! CRITICAL: Found '$LOG_KEYWORD' in logs. Initiating reboot. !!!" >> $LOG_FILE
            # 立即重启系统
            /sbin/reboot
        else
            # 网络断开，但日志中没有找到特定错误，可能只是网络抖动或其他临时问题
            echo "$(date): Network is down, but '$LOG_KEYWORD' not found. Not rebooting." >> $LOG_FILE
        fi
    fi

    # 等待指定时间间隔
    sleep $MONITOR_INTERVAL
done
