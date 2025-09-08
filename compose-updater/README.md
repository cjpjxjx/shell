# Docker Compose 项目自动更新脚本 (compose-updater)

## 简介

这是一个 Shell 脚本，用于自动化更新基于 Docker Compose 部署的多个项目。它会遍历指定的目录，查找每个子目录中的 `docker-compose.yml` 文件，并执行 `pull` 和 `up -d` 命令来拉取最新的镜像并重新部署服务。

## 主要功能

- **自动发现**: 自动扫描并处理指定主目录下的所有 Docker Compose 项目
- **拉取最新镜像**: 为每个项目执行 `docker compose pull`，确保使用最新的镜像
- **智能重新部署**: 拉取镜像后，执行 `docker compose up -d` 以应用更新
- **实际更新检测**: 只有在容器真正有更新时才执行后置命令，避免不必要的操作
- **健壮的重试机制**: 在拉取镜像失败时，会自动进行多次重试
- **项目间延时**: 在处理项目之间添加延时，避免系统负载过高
- **灵活的钩子命令**:
  - 支持在检测到项目实际更新后执行指定的后置命令（例如：重载 Nginx 配置）
  - 支持在所有项目处理完毕后执行全局的后置命令（例如：清理 Docker 虚悬镜像）
- **详细的日志记录**: 记录所有操作、成功和失败信息到日志文件中，便于追踪和排错
- **执行统计**: 显示扫描项目总数、实际更新项目数等统计信息

## 工作流程

1. **初始化**: 脚本启动，设置日志文件
2. **扫描项目**: 遍历配置的 `COMPOSE_BASE_DIR` 目录下的所有第一级子目录
3. **处理单个项目**: 对于每个子目录（项目）：
   a. 在项目间添加延时（除第一个项目外）
   b. 进入项目目录
   c. 查找 `docker-compose.yml` 或 `docker-compose.yaml` 文件
   d. 如果找到文件，则执行 `docker compose pull` 拉取最新镜像。如果失败，将根据配置进行重试
   e. 如果镜像拉取成功，则执行 `docker compose up -d` 来更新服务
   f. 检测是否有实际更新（通过分析输出判断）
   g. 如果有实际更新且配置了 `PROJECT_POST_COMMAND`，则执行该命令
4. **全局收尾**: 所有项目处理完毕后，如果配置了 `GLOBAL_POST_COMMAND`，则执行该全局后置命令
5. **统计报告**: 显示本次运行的详细统计信息
6. **结束**: 脚本执行完毕

## 配置

脚本的所有配置项都在文件顶部的"配置区域"中，可以根据实际需求进行修改。

- `COMPOSE_BASE_DIR`: 存放所有 Docker Compose 项目的主目录。脚本会遍历此目录下的子目录
  - 默认值: `"/data/docker-compose"`
- `LOG_DIR`: 日志文件的存放目录
  - 默认值: `"/var/log/compose-updater"`
- `PULL_RETRIES`: `docker compose pull` 命令的失败重试次数
  - 默认值: `3`
- `PULL_RETRY_DELAY`: 每次重试之间的等待时间（秒）
  - 默认值: `10`
- `PROJECT_UPDATE_DELAY`: 项目更新间的延时时间（秒）
  - 默认值: `3`
- `PROJECT_POST_COMMAND`: 每个项目有实际更新时要执行的命令。如果不需要则留空
  - 示例: `"docker exec nginx nginx -s reload"`
  - 注意：只有在检测到容器实际更新时才会执行此命令
- `GLOBAL_POST_COMMAND`: 所有项目都处理完毕后执行的全局命令。如果不需要则留空
  - 示例: `"docker system prune -a -f"`

## 使用方法

1. **配置脚本**: 根据你的环境修改 `compose-updater.sh` 文件顶部的配置变量

2. **授予执行权限**:
   ```bash
   chmod +x compose-updater.sh
   ```

3. **直接运行**:
   ```bash
   ./compose-updater.sh
   ```

4. **定期执行 (推荐)**:
   使用 `crontab` 来设置定时任务，实现无人值守的自动更新。例如，每天凌晨3点执行一次：
   ```bash
   crontab -e
   ```
   然后添加以下行：
   ```
   0 3 * * * /path/to/your/compose-updater.sh
   ```
   请将 `/path/to/your/compose-updater.sh` 替换为脚本的实际绝对路径。

## 目录结构示例

假设你的 Docker Compose 项目目录结构如下：
```
/data/docker-compose/
├── web-app/
│   └── docker-compose.yml
├── database/
│   └── docker-compose.yml
├── monitoring/
│   └── docker-compose.yaml
└── backup-service/
    └── docker-compose.yml
```

脚本会自动发现并处理这四个项目。

## 日志

脚本的输出会同时显示在控制台并追加到日志文件中。日志文件位于配置的 `LOG_DIR` 目录下，并以 `update-YYYY-MM-DD.log` 的格式命名。

你可以通过以下命令查看当天的日志：
```bash
tail -f /var/log/compose-updater/update-$(date +'%Y-%m-%d').log
```

## 输出示例

脚本运行时会显示详细的处理过程和最终统计：
```
[2024-01-15 03:00:01] [INFO] - ====== Docker Compose 更新脚本启动 ======
[2024-01-15 03:00:01] [INFO] - --- 正在处理项目: web-app ---
[2024-01-15 03:00:02] [INFO] - 找到 Compose 文件: docker-compose.yml
[2024-01-15 03:00:02] [INFO] - 正在尝试拉取最新镜像 (最多重试 3 次)...
[2024-01-15 03:00:05] [INFO] - 镜像拉取成功。
[2024-01-15 03:00:05] [INFO] - 正在执行 'docker compose up -d'...
[2024-01-15 03:00:07] [INFO] - 检测到容器有实际更新。
[2024-01-15 03:00:07] [INFO] - 项目 web-app 有更新，正在执行后置命令: docker exec nginx nginx -s reload
[2024-01-15 03:00:08] [INFO] - 后置命令执行成功。
[2024-01-15 03:00:08] [INFO] - 等待 3 秒后处理下一个项目...
...
[2024-01-15 03:05:30] [INFO] - ====== 执行统计 ======
[2024-01-15 03:05:30] [INFO] - 扫描项目总数: 4
[2024-01-15 03:05:30] [INFO] - 实际更新项目数: 2
[2024-01-15 03:05:30] [INFO] - 无需更新项目数: 2
[2024-01-15 03:05:30] [INFO] - ====== Docker Compose 更新脚本执行完毕 ======
```

## 注意事项

- 脚本需要具备 Docker 和 Docker Compose 的执行权限
- 确保配置的目录路径存在且可访问
- 建议在生产环境中先进行测试
- 后置命令的执行失败不会影响其他项目的处理
- 脚本会自动跳过没有 docker-compose 文件的目录