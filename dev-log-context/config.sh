#!/usr/bin/env bash
# dev-log-context 配置
# 此文件会被 load_context.sh 读取,可在此调整行为。

# 仓库内日志目录(相对仓库根,与 dev-changelog 保持一致)
export DEV_LOG_CONTEXT_DIR="docs/change-log"

# 默认时间窗口(天):只读取最近 N 天的开发日志
export DEV_LOG_CONTEXT_DAYS="${DEV_LOG_CONTEXT_DAYS:-7}"

# 默认条数上限:最多汇总最新 N 条日志
export DEV_LOG_CONTEXT_LIMIT="${DEV_LOG_CONTEXT_LIMIT:-10}"

# 输出语种:zh / en(README/描述文案语言,日志正文保持原文)
export DEV_LOG_CONTEXT_LANG="${DEV_LOG_CONTEXT_LANG:-zh}"
