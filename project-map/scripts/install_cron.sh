#!/usr/bin/env bash
# project-map / install_cron.sh
# 把"每小时自动增量更新项目脉络"注册为系统 crontab 任务。
#
# 用法:
#   bash install_cron.sh            # 注册每小时任务到当前仓库
#   bash install_cron.sh /path/to/repo
#   bash install_cron.sh --remove [repo]   # 卸载
#   bash install_cron.sh --list     # 查看当前 crontab 中的 project-map 行

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"

# ---- 加载配置 ----
if [ -f "$SKILL_DIR/config.sh" ]; then
  # shellcheck disable=SC1091
  source "$SKILL_DIR/config.sh"
fi

MODE="install"
TARGET="${1:-}"
if [ "$TARGET" = "--remove" ]; then
  MODE="remove"; TARGET="${2:-}"
elif [ "$TARGET" = "--list" ]; then
  MODE="list"; TARGET="${2:-}"
fi

if [ -n "$TARGET" ]; then
  cd "$TARGET" 2>/dev/null || { echo "目录不存在:$TARGET" >&2; exit 1; }
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "[project-map] 不是 git 仓库,无法安装 cron" >&2
  exit 1
}

# 文档目录(存放 cron 日志)
MAP_DIR="$REPO_ROOT/$(dirname "${PROJECT_MAP_FILE:-docs/project-map.md}")"
CRON_LOG="$MAP_DIR/${PROJECT_MAP_CRON_LOG_NAME:-project-map-cron.log}"
MINUTE="${PROJECT_MAP_CRON_MINUTE:-17}"

CRON_CMD="bash $SCRIPT_DIR/check_and_update.sh"
CRON_LINE="$MINUTE * * * *  $CRON_CMD >> $CRON_LOG 2>&1"

current_crontab() {
  crontab -l 2>/dev/null || true
}

# 检测该仓库行是否已存在(用仓库根作唯一标识)
repo_marker() { echo "$REPO_ROOT" | sed 's#/##'; }
already_installed() {
  current_crontab | grep -F "$CRON_CMD" | grep -q .
}

if [ "$MODE" = "remove" ]; then
  OLD="$(current_crontab)"
  NEW="$(printf '%s\n' "$OLD" | grep -vF "$CRON_CMD")"
  if [ "$OLD" != "$NEW" ]; then
    printf '%s\n' "$NEW" | grep -v '^$' | crontab -
    echo "[project-map] 已从 crontab 移除: $CRON_CMD"
  else
    echo "[project-map] crontab 中未找到该任务,无需卸载"
  fi
  exit 0
fi

if [ "$MODE" = "list" ]; then
  echo "[project-map] 当前 crontab 中的 project-map 任务:"
  current_crontab | grep -F "$CRON_CMD" || echo "(无)"
  exit 0
fi

mkdir -p "$MAP_DIR"

if already_installed; then
  echo "[project-map] crontab 已包含本仓库任务,跳过"
else
  ( current_crontab
    echo "$CRON_LINE"
  ) | grep -v '^$' | crontab -
  echo "[project-map] 已注册每小时任务: $CRON_LINE"
fi

echo "[project-map] 运行日志:$CRON_LOG"
echo "[project-map] 说明:每小时第 ${MINUTE} 分钟检查;仅当有新增开发日志时才对变更做增量更新,无变更则零成本跳过。"
