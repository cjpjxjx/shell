#!/bin/sh

# 配置参数
# 以空格分隔的目标 IP 列表（这些设备应为市电供电）
TARGETS="192.168.1.2 192.168.1.3"

# 连续不可达判定为市电中断的时长（秒），默认 180 秒 = 3 分钟
OUTAGE_SECONDS=180

# 检测间隔（秒），默认 15 秒
CHECK_INTERVAL=15

# 每个目标 ping 的次数与单次超时（秒），保持简单
PING_COUNT=1
PING_TIMEOUT=1

# 日志文件路径，默认 /var/log/mains-ping-watchdog.log；置空则仅输出到标准输出
LOG_FILE="/var/log/mains-ping-watchdog.log"

# 关机命令
SHUTDOWN_CMD="shutdown -h now"

log() {
    TS=`date '+%F %T'`
    MSG="$TS [mains-ping-watchdog] $*"
    if [ -n "$LOG_FILE" ]; then
        echo "$MSG" >> "$LOG_FILE"
    else
        echo "$MSG"
    fi
}

is_all_targets_down() {
    for T in $TARGETS; do
        ping -c "$PING_COUNT" -W "$PING_TIMEOUT" "$T" >/dev/null 2>&1 && return 1
    done
    return 0
}

all_down_since=0

log "启动，目标：$TARGETS，判定时长：${OUTAGE_SECONDS}s，间隔：${CHECK_INTERVAL}s"

while :; do
    if is_all_targets_down; then
        if [ "$all_down_since" -eq 0 ]; then
            all_down_since=`date +%s`
            log "所有目标均不可达，开始计时"
        else
            NOW=`date +%s`
            ELAPSED=`expr $NOW - $all_down_since`
            if [ "$ELAPSED" -ge "$OUTAGE_SECONDS" ]; then
                log "所有目标已连续不可达 ${ELAPSED}s (>=${OUTAGE_SECONDS}s)，执行关机"
                log "执行命令：$SHUTDOWN_CMD"
                $SHUTDOWN_CMD
                exit 0
            fi
        fi
    else
        if [ "$all_down_since" -ne 0 ]; then
            log "有目标恢复可达，清除不可达计时"
        fi
        all_down_since=0
    fi
    sleep "$CHECK_INTERVAL"
done


