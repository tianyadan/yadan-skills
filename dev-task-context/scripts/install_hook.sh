#!/usr/bin/env bash
# dev-task-context / install_hook.sh
# 把"会话开始时自动加载近期开发日志"配置到各 AI 编辑器产品。
#
# 支持目标:
#   claude   写入 <仓库>/.claude/settings.json 的 SessionStart 钩子(每次会话开始自动读取日志进上下文)
#   codex    写入 <仓库>/.codex/AGENTS.md(附加"会话开始时先读取日志"指令)
#   cursor   写入 <仓库>/.cursor/rules/*.mdc 规则文件
#   global   把 claude 钩子安装到用户级 ~/.claude/settings.json(所有项目生效)
#
# 用法:
#   bash install_hook.sh                # 默认 claude,装到当前仓库
#   bash install_hook.sh --editor codex
#   bash install_hook.sh --editor cursor
#   bash install_hook.sh --global      # 全局 claude SessionStart 钩子
#   bash install_hook.sh --remove [--editor X ] [--global]
#   bash install_hook.sh --list        # 查看各编辑器安装说明

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
LOADER="$SCRIPT_DIR/route_context.sh"

EDITOR="claude"
GLOBAL="0"
MODE="install"

while [ $# -gt 0 ]; do
  case "$1" in
    --editor) EDITOR="$2"; shift 2 ;;
    --global) GLOBAL="1"; shift ;;
    --remove) MODE="remove"; shift ;;
    --list)   MODE="list"; shift ;;
    *) shift ;;
  esac
done

if [ "$MODE" = "list" ]; then
  cat <<'EOF'
各编辑器安装方式:
  claude   bash install_hook.sh                 # 项目级,写 .claude/settings.json SessionStart 钩子
          bash install_hook.sh --global         # 全局,写 ~/.claude/settings.json,所有项目生效
  codex   bash install_hook.sh --editor codex   # 写 .codex/AGENTS.md 指令(会话前读取日志)
  cursor  bash install_hook.sh --editor cursor  # 写 .cursor/rules/dev-task-context.mdc 规则
卸载:
  bash install_hook.sh --remove [--editor X]
EOF
  exit 0
fi

# ---- 定位仓库根(全局模式不需要) ----
if [ "$GLOBAL" != "1" ]; then
  TARGET="${1:-}"
  [ -n "$TARGET" ] && cd "$TARGET" 2>/dev/null || true
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "[dev-task-context] 不是 git 仓库,无法安装。请 cd 到仓库内,或使用 --global。" >&2
    exit 1
  }
fi

remove_hook() {
  local cfg="$1"
  if [ -f "$cfg" ]; then
    local tmp
    tmp="$(mktemp)"
    # 移除所有引用 dev-task-context 的 SessionStart 钩子与该条 hook hook JSON(最简)。
    # 说明:settings.json 为 JSON,这里用 python3/jq 精准删除;若都不可用则提示手动。
    if command -v python3 >/dev/null 2>&1; then
      python3 - "$cfg" <<'PY'
import json,sys
p=sys.argv[1]
try:
    d=json.load(open(p))
except Exception:
    sys.exit(0)
hooks=d.get("hooks") or {}
ss=hooks.get("SessionStart") or []
hooks["SessionStart"]=[h for h in ss if "dev-task-context" not in json.dumps(h,ensure_ascii=False)]
d["hooks"]=hooks
json.dump(d,open(p,"w"),ensure_ascii=False,indent=2)
PY
      echo "[dev-task-context] 已从 $cfg 移除 SessionStart 钩子"
    else
      echo "[dev-task-context] 需要 python3 才能自动移除,请手动编辑 $cfg 删除引用 dev-task-context 的 SessionStart 钩子"
    fi
  fi
}

if [ "$MODE" = "remove" ]; then
  if [ "$GLOBAL" = "1" ]; then
    remove_hook "$HOME/.claude/settings.json"
  else
    remove_hook "$REPO_ROOT/.claude/settings.json"
  fi
  echo "[dev-task-context] 卸载完成"
  exit 0
fi

# 判断是否有 python3/jq 来安全合并 JSON
HAVE_JSON="0"
command -v python3 >/dev/null 2>&1 && HAVE_JSON="1"

case "$EDITOR" in
  claude)
    if [ "$GLOBAL" = "1" ]; then
      CFG="$HOME/.claude/settings.json"
      mkdir -p "$HOME/.claude"
    else
      CFG="$REPO_ROOT/.claude/settings.json"
      mkdir -p "$REPO_ROOT/.claude"
    fi

    if [ "$HAVE_JSON" = "1" ]; then
      python3 - "$CFG" "$LOADER" <<'PY'
import json,sys,os
cfg,loader=sys.argv[1],sys.argv[2]
d={}
if os.path.exists(cfg):
    try: d=json.load(open(cfg))
    except Exception: d={}
hooks=d.setdefault("hooks",{})
ss=hooks.setdefault("SessionStart",[])
# 避免重复
for h in ss:
    if loader in str(h):
        print(f"[dev-task-context] SessionStart 钩子已存在,跳过"); sys.exit(0)
ss.append({"matcher":"","hooks":[{"type":"command","command":f"bash {loader} --start"}]})
json.dump(d,open(cfg,"w"),ensure_ascii=False,indent=2)
print("[dev-task-context] 已写入 SessionStart 钩子 → "+cfg)
PY
    else
      echo "[dev-task-context] 需要 python3 合并 JSON,请手动在 $CFG 的 hooks.SessionStart 添加:"
      echo "  { \"matcher\": \"\", \"hooks\": [ {\"type\": \"command\", \"command\": \"bash $LOADER --start\"} ] }"
    fi
    echo "[dev-task-context] 安装完成:会话开始做轻量项目感知;任务驱动请按类型调 route_context.sh。"
    ;;

  codex)
    AGENTSDIR="$REPO_ROOT/.codex"
    mkdir -p "$AGENTSDIR"
    FILE="$AGENTSDIR/AGENTS.md"
    BLOCK="## dev-task-context(自动加载)
每次新会话开始运行时: bash $LOADER --start   # 轻量项目感知
按任务类型按需: bash $LOADER NEW_FEATURE|BUG_FIX|FEATURE_CHANGE
见技能 SKILL.md 的 Context Router 决策表,不无差别全量加载。"
    if [ -f "$FILE" ] && grep -q "dev-task-context" "$FILE" 2>/dev/null; then
      echo "[dev-task-context] $FILE 已包含 dev-task-context 指令"
    else
      { [ -f "$FILE" ] && cat "$FILE"; printf '\n%s\n' "$BLOCK"; } > "$FILE.tmp" && mv "$FILE.tmp" "$FILE"
      echo "[dev-task-context] 已写入 $FILE"
    fi
    ;;

  cursor)
    RULEDIR="$REPO_ROOT/.cursor/rules"
    mkdir -p "$RULEDIR"
    FILE="$RULEDIR/dev-task-context.mdc"
    cat > "$FILE" <<EOF
---
description: 会话开始时轻量感知项目,按任务类型读取最小必要上下文
globs:
alwaysApply: true
---
每次新会话开始运行时: bash $LOADER --start
按任务类型按需: bash $LOADER NEW_FEATURE|BUG_FIX|FEATURE_CHANGE [关键词]
按 SKILL.md 决策表路由上下文,不无差别全量加载。
EOF
    echo "[dev-task-context] 已写入 Cursor 规则 $FILE"
    ;;

  *)
    echo "[dev-task-context] 未知编辑器:$EDITOR(支持 claude / codex / cursor)" >&2
    exit 1
    ;;
esac
