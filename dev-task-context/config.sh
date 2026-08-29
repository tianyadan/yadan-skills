#!/usr/bin/env bash
# dev-task-context 配置
# 此文件会被 route_context.sh 读取,可在此调整行为。

# 仓库内开发日志目录(相对仓库根,与 dev-changelog 保持一致)
export DEV_TASK_CONTEXT_LOG_DIR="docs/change-log"

# 历史设计/Plan 目录(FEATURE_CHANGE 优先从这里找原始设计)
export DEV_TASK_CONTEXT_PLAN_DIR="docs/plans"

# 项目脉络文件(相对仓库根,由 project-map 技能维护)
export DEV_TASK_CONTEXT_MAP_FILE="docs/project-map.md"

# 单段上下文最大字符数(避免输出过长)
export DEV_TASK_CONTEXT_MAX_TEXT="${DEV_TASK_CONTEXT_MAX_TEXT:-8000}"

# 输出语种:zh / en(说明文案,资料正文保持原文)
export DEV_TASK_CONTEXT_LANG="${DEV_TASK_CONTEXT_LANG:-zh}"
