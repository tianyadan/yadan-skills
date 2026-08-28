#!/usr/bin/env bash
# dev-log-context / load_context.sh
# 核心入口:每次会话开始时读取近期开发变更文档,输出可直接注入上下文(或打印给 AI)的 Markdown 摘要。
# 读取来源与 dev-changelog 保持一致:<仓库根>/docs/change-log/**/*.md
#
# 用法:
#   bash load_context.sh              # 默认近 7 天、最近 10 条
#   bash load_context.sh --days 3    # 只看近 3 天
#   bash load_context.sh --limit 5   # 只取最新 5 条
#   bash load_context.sh --all        # 忽略时间过滤,只按 limit 取最新
#   bash load_context.sh --raw        # 输出完整原始文档(不截断正文)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"

# ---- 加载配置 ----
if [ -f "$SKILL_DIR/config.sh" ]; then
  # shellcheck disable=SC1091
  source "$SKILL_DIR/config.sh"
fi

# ---- 默认参数(可被 config.sh / 环境变量覆盖) ----
DAYS="${DEV_LOG_CONTEXT_DAYS:-7}"
LIMIT="${DEV_LOG_CONTEXT_LIMIT:-10}"
RAW="0"
ALL="0"

# ---- 解析命令行参数 ----
while [ $# -gt 0 ]; do
  case "$1" in
    --days)   DAYS="$2"; shift 2 ;;
    --limit)  LIMIT="$2"; shift 2 ;;
    --raw)    RAW="1"; shift ;;
    --all)    ALL="1"; shift ;;
    *) shift ;;
  esac
done

# ---- 定位仓库根 ----
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "[dev-log-context] 不在 git 仓库中,跳过" >&2
  exit 0
}

LOG_BASE="$REPO_ROOT/${DEV_LOG_CONTEXT_DIR:-docs/change-log}"
[ -d "$LOG_BASE" ] || {
  echo "[dev-log-context] 未找到开发日志目录:$LOG_BASE" >&2
  echo "[dev-log-context] 提示:配合 dev-changelog 技能,每次 commit 后会写入该目录。" >&2
  exit 0
}

# ---- 汇总要读取的所有变更文档(按文件名倒序 = 时间倒序) ----
FILES="$(find "$LOG_BASE" -type f -name '*.md' 2>/dev/null | sort -r)"

# ---- 按时间过滤:保留最近 DAYS 天内修改的文档 ----
if [ "$ALL" != "1" ]; then
  CUTOFF="$(date -v-${DAYS}d '+%Y%m%d' 2>/dev/null || date -d "-${DAYS} days" '+%Y%m%d' 2>/dev/null)"
  FILTERED=""
  while IFS= read -r f; do
    # 文档路径形如 .../docs/change-log/YYYY/MM/DD/xxx.md,直接取日期段比较
    STAMP="$(printf '%s' "$f" | sed -nE 's#.*/change-log/([0-9]{4}/[0-9]{2}/[0-9]{2})/.*#\1#p' | tr -d '/')"
    [ -z "$STAMP" ] && continue
    if [ "${STAMP:-00000000}" -ge "$CUTOFF" ]; then
      FILTERED="$FILTERED$f"$'\n'
    fi
  done <<< "$FILES"
  FILES="$(printf '%s' "$FILTERED")"
fi

# ---- 截取最新 LIMIT 条 ----
SELECTED="$(printf '%s\n' "$FILES" | grep -v '^$' | head -n "$LIMIT")"
[ -z "$SELECTED" ] && {
  echo "[dev-log-context] 近 ${DAYS} 天没有开发日志" >&2
  exit 0
}

# ---- 输出 Markdown 摘要 ----
COUNT="$(printf '%s\n' "$SELECTED" | grep -c '^')"
echo "<!-- dev-log-context:近 ${DAYS} 天 / 最新 ${LIMIT} 条开发日志,共 ${COUNT} 条 -->"
echo "# 近期开发日志概览(供会话开始了解项目上下文)"
echo
echo "> 以下是本仓库最近 ${DAYS} 天的开发变更记录摘要。可据此快速了解:项目在做什么需求、近期改动过哪些文件、是否有风险点。"
echo

I=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  I=$((I+1))
  echo "---"
  echo "## ${I}. $(basename "$f")"
  echo

  if [ "$RAW" = "1" ]; then
    # 完整原文输出
    cat "$f"
    echo
    continue
  fi

  # 精简摘要:提取提交信息、需求背景、变更文件、实现功能
  TITLE="$(grep -m1 '^> 提交:' "$f" 2>/dev/null | sed 's/^> 提交: *//')"
  [ -n "$TITLE" ] && echo "- **提交**: $TITLE"

  DATE="$(grep -m1 '^> 日期:' "$f" 2>/dev/null | sed 's/^> 日期: *//')"
  [ -n "$DATE" ] && echo "- **日期**: $DATE"

  if grep -q '^## 需求背景' "$f" 2>/dev/null; then
    echo "- **需求**: $(awk '/^## 需求背景/{f=1;next}/^## /{f=0}f' "$f" | grep -v '^$' | head -n 3 | tr '\n' ' ')"
  fi

  echo "- **文件**: $(awk '/^## 变更文件/{f=1;next}/^## /{f=0}f' "$f" | sed 's/^- //' | grep -v '^$' | head -n 8 | tr '\n' ' ')"
done <<< "$SELECTED"

echo
echo "<!-- 更多历史细节见 docs/change-log/ 目录,或运行: bash load_context.sh --all --raw -->"
