#!/usr/bin/env bash
# dev-task-context / route_context.sh
# 核心入口:Development Agent 的 Context Router。
# 根据任务类型(AI 语义判断后传入)仅抽取"最小必要上下文",避免每次无差别读取全部日志/结构。
#
# 用法:
#   bash route_context.sh NEW_FEATURE    [keywords...]  新功能:读 project-map 概览+结构+链路,按关键词搜相似实现/plan
#   bash route_context.sh BUG_FIX       [keywords...]  修 bug:按关键词 grep changelog + git log + 当前源码,必要时读历史 plan
#   bash route_context.sh FEATURE_CHANGE [keywords...]  改需求:优先带出 docs/plans/ 原始 plan + 相关 changelog/git + 当前源码
#
# 本脚本只做"低成本抽取"(读文件/ grep / git log),不做语义分析;最终定位由 AI 基于输出完成。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"

# ---- 加载配置 ----
if [ -f "$SKILL_DIR/config.sh" ]; then
  # shellcheck disable=SC1091
  source "$SKILL_DIR/config.sh"
fi

# ---- 参数:第一个是任务类型,其余为关键词 ----
TYPE="${1:-}"
# --start:会话开始时的轻量项目感知(不确定任务类型时)只读 project-map 概览,不加载 changelog 细节
if [ "$TYPE" = "--start" ]; then
  shift || true
  TYPE="NEW_FEATURE"
  START_ONLY="1"
  set -- "$@"   # 重置位置参数为空
fi
shift || true
KEYWORDS=("${@:-}")
[ -z "$TYPE" ] && { echo "[dev-task-context] 缺少任务类型。用法: route_context.sh <NEW_FEATURE|BUG_FIX|FEATURE_CHANGE> [关键词...]" >&2; exit 1; }

# ---- 定位仓库根 ----
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "[dev-task-context] 不在 git 仓库中,跳过" >&2
  exit 0
}
cd "$REPO_ROOT" || exit 1

LOG_DIR="$REPO_ROOT/${DEV_TASK_CONTEXT_LOG_DIR:-docs/change-log}"
PLAN_DIR="$REPO_ROOT/${DEV_TASK_CONTEXT_PLAN_DIR:-docs/plans}"
MAP_FILE="$REPO_ROOT/${DEV_TASK_CONTEXT_MAP_FILE:-docs/project-map.md}"

# 拼接关键词用于提示与 grep(大小写不敏感)
KW_JOIN="$(printf '%s ' "${KEYWORDS[@]}")"

echo "# 上下文路由: $TYPE"
echo
echo "> 资料可信度(冲突时): 当前源码 > 近期 Changelog > Git 历史 > 历史 Plan"
echo

# ================= NEW_FEATURE:读 project-map + 按关键词找相似实现/plan =================
load_new_feature() {
  if [ -f "$MAP_FILE" ]; then
    echo "## 项目脉络(project-map)"
    echo "\"$(sed -n '/^## 1\. 项目概览/,/^## 3\./p' "$MAP_FILE" 2>/dev/null | head -c 4000)\""
    echo
    echo "结构/链路详见: $MAP_FILE"
  else
    echo "## 项目脉络"
    echo "(未找到 $MAP_FILE,可先运行 project-map 技能全量生成)"
  fi
  echo

  if [ "${START_ONLY:-0}" = "1" ]; then
    echo "## 会话开始(轻量感知)"
    echo "先了解任务类型后再按需调用(见 SKILL.md 三种任务类型);此处仅给出概览,不做无差别加载。"
    echo
    return 0
  fi

  if [ "${#KEYWORDS[@]}" -gt 0 ]; then
    echo "## 相似历史(按关键词: $KW_JOIN)"
    # 历史 plan 中搜相似设计
    if [ -d "$PLAN_DIR" ]; then
      HIT="$(grep -rl --include='*.md' -iF "$(printf '%s' "$KW_JOIN" | tr ' ' '\n' | head -n1)" "$PLAN_DIR" 2>/dev/null | head -n 5)"
      [ -n "$HIT" ] && { echo "docs/plans 命中:"; printf '%s\n' "$HIT"; }
    fi
    # changelog 中搜相似实现(只少量,新功能不默认读大量)
    if [ -d "$LOG_DIR" ]; then
      HIT="$(grep -rl --include='*.md' -iF "$(printf '%s' "$KW_JOIN" | tr ' ' '\n' | head -n1)" "$LOG_DIR" 2>/dev/null | head -n 3)"
      [ -n "$HIT" ] && { echo "change-log 命中(少量):"; printf '%s\n' "$HIT"; }
    fi
  fi
  echo
  echo "## 建议"
  echo "- 参考上述相似实现的代码风格;必要时用 grep -rl 在源码中找类似代码。"
  echo "- 完成需求设计后可沉淀到 $PLAN_DIR。"
}

# ================= BUG_FIX:grep changelog + git log + 当前源码 =================
load_bug_fix() {
  KW1="$(printf '%s' "$KW_JOIN" | tr ' ' '\n' | head -n1)"
  echo "## 相关 Changelog(关键词: $KW_JOIN)"
  if [ -d "$LOG_DIR" ]; then
    HIT="$(grep -rl --include='*.md' -iF "$KW1" "$LOG_DIR" 2>/dev/null | head -n 8)"
    [ -n "$HIT" ] || echo "(changelog 无命中)"
    for f in $HIT; do
      echo "--- ${f#./} ---"
      T="$(grep -m1 '^> 提交:' "$f" 2>/dev/null | sed 's/^> 提交: *//')"
      N="$(awk '/^## 需求背景/{x=1;next}/^##/{x=0}x' "$f" 2>/dev/null | grep -v '^$' | head -c 500)"
      [ -n "$T" ] && echo "提交: $T"
      [ -n "$N" ] && echo "需求: $N"
      echo
    done
  else
    echo "(未找到 $LOG_DIR)"
  fi

  echo "## 相关 Git 提交"
  git log --oneline --all -i --grep="$KW1" 2>/dev/null | head -n 10 || true
  [ -z "$(git log --oneline --all -i --grep="$KW1" 2>/dev/null | head -n 1)" ] && echo "(git log 无命中)"
  echo

  echo "## 当前源码命中(关键词: $KW1)"
  SRC_HIT="$(grep -rl -iF "$KW1" --include='*.{js,ts,tsx,vue,go,py,java,rs,c,cpp}' . 2>/dev/null | grep -v -E 'node_modules|dist|build|docs/|\.git/' | head -n 10)"
  [ -n "$SRC_HIT" ] || echo "(源码无命中,可放宽关键词)"
  printf '%s\n' "${SRC_HIT:-}"
  echo

  # 必要时读历史 plan(只带关键词匹配的)
  if [ -d "$PLAN_DIR" ]; then
    HIT="$(grep -rl --include='*.md' -iF "$KW1" "$PLAN_DIR" 2>/dev/null | head -n 5)"
    [ -n "$HIT" ] && { echo "历史 Plan 命中:"; printf '%s\n' "$HIT"; }
  fi
  echo
  echo "## 建议"
  echo "- 按 当前源码 > changelog > git > plan 的可信度定位 Root Cause,做最小范围修复。"
}

# ================= FEATURE_CHANGE:原始 Plan + changelog/git + 当前源码 =================
load_feature_change() {
  KW1="$(printf '%s' "$KW_JOIN" | tr ' ' '\n' | head -n1)"
  echo "## 原始 Plan(docs/plans)"
  if [ -d "$PLAN_DIR" ]; then
    PLANS="$(find "$PLAN_DIR" -type f -name '*.md' 2>/dev/null | sort -r | head -n 10)"
    if [ -n "$KW1" ]; then
      HIT="$(grep -rl --include='*.md' -iF "$KW1" "$PLAN_DIR" 2>/dev/null | head -n 5)"
      [ -n "$HIT" ] && PLANS="$HIT"
    fi
    if [ -n "$PLANS" ]; then
      for f in $PLANS; do
        echo "--- ${f#./} ---"
        head -c 1200 "$f"
        echo
      done
    else
      echo "(docs/plans 无匹配/为空)"
    fi
  else
    echo "(未找到 $PLAN_DIR)"
  fi
  echo

  echo "## 相关 Changelog(关键词: $KW1)"
  if [ -d "$LOG_DIR" ] && [ -n "$KW1" ]; then
    HIT="$(grep -rl --include='*.md' -iF "$KW1" "$LOG_DIR" 2>/dev/null | head -n 6)"
    [ -n "$HIT" ] || echo "(无命中)"
    printf '%s\n' "${HIT:-}"
  else
    echo "(跳过或未找到 changelog)"
  fi
  echo

  echo "## 相关 Git 提交"
  if [ -n "$KW1" ]; then
    git log --oneline --all -i --grep="$KW1" 2>/dev/null | head -n 8 || true
  else
    git log --oneline -n 10 2>/dev/null || true
  fi
  echo

  echo "## 建议"
  echo "- 对比: 旧设计(plan) vs 当前实现(源码) vs 新需求 → 求 Design Delta。"
  echo "- 对比后必要时重新沉淀设计到 $PLAN_DIR;保留原 plan 作历史。"
}

case "$TYPE" in
  NEW_FEATURE)    load_new_feature ;;
  BUG_FIX)        load_bug_fix ;;
  FEATURE_CHANGE)  load_feature_change ;;
  *) echo "[dev-task-context] 未知任务类型:$TYPE(支持 NEW_FEATURE / BUG_FIX / FEATURE_CHANGE)" >&2; exit 1 ;;
esac
