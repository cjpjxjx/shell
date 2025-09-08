#!/bin/bash
# ==============================================================================
# --- 配置区域 ---
# ==============================================================================

# 设置脚本在遇到错误时立即退出
set -e
# 设置管道中任何一个命令失败则整个管道失败
set -o pipefail

# 存放 docker-compose 项目的主目录
# 脚本会遍历此目录下的第一层子目录
COMPOSE_BASE_DIR="/data/docker-compose"

# 日志文件存放目录
# 如果目录不存在，脚本会尝试自动创建
LOG_DIR="/var/log/compose-updater"

# docker compose pull 的重试次数
PULL_RETRIES=3

# 每次重试之间的等待时间（秒）
PULL_RETRY_DELAY=10

# 项目更新间的延时时间（秒）
PROJECT_UPDATE_DELAY=3

# 每个项目有实际更新时执行的后置命令
# 注意：只有在检测到容器实际更新时才会执行此命令
# 如果不需要，留空即可，例如: PROJECT_POST_COMMAND=""
PROJECT_POST_COMMAND="docker exec nginx nginx -s reload"

# 所有项目处理完毕后执行的全局后置命令
# 如果不需要，留空即可，例如: GLOBAL_POST_COMMAND=""
GLOBAL_POST_COMMAND="docker system prune -a -f"


# ============================================================================
# --- 脚本主体 (请勿修改以下内容) ---
# ============================================================================

# --- 日志设置 ---
# 检查并创建日志目录
if [ ! -d "$LOG_DIR" ]; then
    echo "日志目录 $LOG_DIR 不存在，正在尝试创建..."
    mkdir -p "$LOG_DIR"
    if [ $? -ne 0 ]; then
        echo "错误：无法创建日志目录 $LOG_DIR。请检查权限。"
        exit 1
    fi
fi

# 设置日志文件路径
LOG_FILE="$LOG_DIR/update-$(date +'%Y-%m-%d').log"

# --- 日志函数 ---
# 带有时间和级别的日志记录
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    # 只格式化消息并输出到标准输出
    echo "[$timestamp] [$level] - $message"
}

# --- 主逻辑 ---
main() {
    log "INFO" "====== Docker Compose 更新脚本启动 ======"

    # 检查 COMPOSE_BASE_DIR 是否存在
    if [ ! -d "$COMPOSE_BASE_DIR" ]; then
        log "ERROR" "基础目录 '$COMPOSE_BASE_DIR' 不存在，脚本退出。"
        exit 1
    fi

    local update_count=0
    local project_count=0

    # 遍历基础目录下的所有子目录
    for project_dir in "$COMPOSE_BASE_DIR"/*/; do
        # 移除末尾的斜杠
        project_dir=${project_dir%/}
        local project_name=$(basename "$project_dir")
        
        log "INFO" "--- 正在处理项目: $project_name ---"
        
        # 递增项目处理计数
        project_count=$((project_count + 1))
        
        # 如果不是第一个项目，则添加延时
        if [ $project_count -gt 1 ]; then
            log "INFO" "等待 $PROJECT_UPDATE_DELAY 秒后处理下一个项目..."
            sleep "$PROJECT_UPDATE_DELAY"
        fi

        # 切换到项目目录
        cd "$project_dir" || { log "WARN" "无法进入目录 $project_dir，跳过。"; continue; }

        # 检查是否存在 docker-compose 文件
        compose_file=""
        if [ -f "docker-compose.yml" ]; then
            compose_file="docker-compose.yml"
        elif [ -f "docker-compose.yaml" ]; then
            compose_file="docker-compose.yaml"
        else
            log "INFO" "在 $project_name 中未找到 docker-compose.yml 或 docker-compose.yaml 文件，跳过。"
            continue
        fi
        
        log "INFO" "找到 Compose 文件: $compose_file"
        
        # 1) 拉取镜像（简单逻辑：批量拉取，失败则重试，超时则重试）
        log "INFO" "正在尝试拉取最新镜像 (最多重试 $PULL_RETRIES 次)..."
        local pull_success=false
        for ((i=1; i<=PULL_RETRIES; i++)); do
            set +e
            COMPOSE_INTERACTIVE_NO_CLI=1 docker compose pull
            pull_rc=$?
            set -e

            if [ $pull_rc -eq 0 ]; then
                log "INFO" "镜像拉取成功。"
                pull_success=true
                break
            else
                log "WARN" "拉取失败(返回码 $pull_rc)。将在 $PULL_RETRY_DELAY 秒后重试..."
                sleep "$PULL_RETRY_DELAY"
            fi
        done

        if [ "$pull_success" = false ]; then
            log "ERROR" "项目 $project_name 的镜像在尝试 $PULL_RETRIES 次后仍然拉取失败/超时，跳过此项目。"
            continue
        fi

        # 2) up -d（检测是否有实际更新）
        log "INFO" "正在执行 'docker compose up -d'..."
        set +e
        up_output=$(docker compose up -d 2>&1)
        up_exit_code=$?
        set -e
        echo "$up_output"
        if [ $up_exit_code -ne 0 ]; then
            log "ERROR" "项目 $project_name 执行 'docker compose up -d' 失败(返回码 $up_exit_code)，请检查以上输出。"
            continue
        fi
        
        # 检测是否有实际更新（检查输出中是否包含重新创建或启动的容器）
        local has_updates=false
        # 检测英文和中文输出中的关键词，表示容器有实际变化
        if echo "$up_output" | grep -qEi "(Recreating|Starting|Created|Recreated|Restarting|recreated|started|restarted|重新创建|启动|已创建|重启)"; then
            has_updates=true
            log "INFO" "检测到容器有实际更新。"
            # 只有在有实际更新时才递增计数
            update_count=$((update_count + 1))
        else
            log "INFO" "未检测到容器更新（所有容器都是最新状态）。"
        fi

        # 3) 只有在有实际更新时才执行后置命令
        if [ "$has_updates" = true ] && [ -n "$PROJECT_POST_COMMAND" ]; then
            log "INFO" "项目 $project_name 有更新，正在执行后置命令: $PROJECT_POST_COMMAND"
            set +e
            eval "$PROJECT_POST_COMMAND"
            post_rc=$?
            set -e
            if [ $post_rc -eq 0 ]; then
                log "INFO" "后置命令执行成功。"
            else
                log "ERROR" "后置命令执行失败，返回码: $post_rc"
            fi
        elif [ "$has_updates" = false ] && [ -n "$PROJECT_POST_COMMAND" ]; then
            log "INFO" "项目 $project_name 无更新，跳过后置命令执行。"
        fi
    done

    # 执行全局后置命令
    if [ -n "$GLOBAL_POST_COMMAND" ]; then
        log "INFO" "====== 所有项目处理完毕，正在执行全局后置命令 ======"
        log "INFO" "执行: $GLOBAL_POST_COMMAND"
        set +e
        eval "$GLOBAL_POST_COMMAND"
        global_rc=$?
        set -e
        if [ $global_rc -eq 0 ]; then
            log "INFO" "全局后置命令执行成功。"
        else
            log "ERROR" "全局后置命令执行失败，返回码: $global_rc"
        fi
    fi
    
    log "INFO" "====== 执行统计 ======"
    log "INFO" "扫描项目总数: $project_count"
    log "INFO" "实际更新项目数: $update_count"
    if [ $project_count -gt 0 ]; then
        local no_update_count=$((project_count - update_count))
        log "INFO" "无需更新项目数: $no_update_count"
    fi
    log "INFO" "====== Docker Compose 更新脚本执行完毕 ======"
}

# 运行主函数，并将所有标准输出和错误输出都重定向
# 通过管道传递给 tee 命令，该命令会同时将输出显示在控制台并追加到日志文件
main 2>&1 | tee -a "$LOG_FILE"
