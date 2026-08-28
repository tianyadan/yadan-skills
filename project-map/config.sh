#!/usr/bin/env bash
# project-map 配置
# 此文件会被 scan_project.sh / check_and_update.sh 读取,可在此调整行为。

# 输出脉络文档(相对仓库根)
export PROJECT_MAP_FILE="docs/project-map.md"

# meta 文件(记录上次扫描/更新时间)与 cron 运行日志,位于文档同目录
export PROJECT_MAP_META_NAME=".project-map-meta"
export PROJECT_MAP_CRON_LOG_NAME="project-map-cron.log"

# 开发日志目录(与 dev-changelog 一致;增量更新以此为准)
export PROJECT_MAP_LOG_DIR="docs/change-log"

# cron 每小时执行的具体分钟(避开整点 :00,减少与同类任务撞车)
export PROJECT_MAP_CRON_MINUTE="${PROJECT_MAP_CRON_MINUTE:-17}"

# 传给头less claude 的最大文本长度,避免超长参数
export PROJECT_MAP_MAX_TEXT="${PROJECT_MAP_MAX_TEXT:-60000}"

# 全量分析时,列结构参考的文件数上限 / 深度上限
export PROJECT_MAP_TREE_MAX="${PROJECT_MAP_TREE_MAX:-300}"
export PROJECT_MAP_TREE_DEPTH="${PROJECT_MAP_TREE_DEPTH:-6}"
