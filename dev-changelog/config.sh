#!/usr/bin/env bash
# dev-changelog 配置
# 此文件会被 record_change.sh 读取,可在此调整行为。

# 总开关:1 = 启用,0 = 关闭
export DEV_CHANGELOG_ENABLED="${DEV_CHANGELOG_ENABLED:-1}"

# 仓库内记录目录(相对仓库根)
export DEV_CHANGELOG_DIR="docs/change-log"

# 传给 claude 的最大 diff 字符数(避免传入超长参数)
export DEV_CHANGELOG_MAX_DIFF="${DEV_CHANGELOG_MAX_DIFF:-40000}"

# 生成的文档语种:zh / en
export DEV_CHANGELOG_LANG="${DEV_CHANGELOG_LANG:-zh}"
