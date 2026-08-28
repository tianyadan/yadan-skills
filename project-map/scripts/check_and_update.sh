#!/usr/bin/env bash
# project-map / check_and_update.sh
# cron 每小时调用的入口:薄包装 scan_project.sh --incremental。
# 有新增开发日志才做增量更新;无变更零 token 跳过。静默失败,绝不打扰正常使用。
# 输出/错误由 crontab 重定向到日志文件(见 install_cron.sh)。

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 后台静默执行增量更新(其实已是增量、低开销,这里同步跑即可)
bash "$SCRIPT_DIR/scan_project.sh" --incremental >&2 || true
true
