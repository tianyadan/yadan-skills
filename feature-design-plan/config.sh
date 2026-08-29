#!/usr/bin/env bash
# feature-design-plan 配置
# 此文件会被 write_plan.sh 读取。

# Plan 文档目录(相对仓库根,固定路径,不再每次询问)
export FEATURE_DESIGN_PLAN_DIR="docs/plan"

# 可选:是否在会话开始时也把 Plan 目录纳入轻量感知
export FEATURE_DESIGN_PLAN_META_NAME=".feature-design-plan-meta"
