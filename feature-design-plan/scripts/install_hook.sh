# feature-design-plan / install_hook.sh
# 把 feature-design-plan 的触发指导写进仓库的 codex/cursor/claude 配置,便于 Agent 按规则调用。
#
# 用法:
#   cd <仓库> && bash ~/.claude/skills/feature-design-plan/scripts/install_hook.sh --editor codex
#   bash ~/.claude/skills/feature-design-plan/scripts/install_hook.sh --editor cursor
#   bash ~/.claude/skills/feature-design-plan/scripts/install_hook.sh --editor claude
#   bash ... --remove [--editor X] [repo]

# 注:install_hook.sh 内容已足够;这里放脚本即可

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"

# codex 分支:在 .codex/AGENTS.md 追加触发指导
install_codex() {
  local dir="$1"; local repo_root="$2"
  mkdir -p "$dir"
  local file="$dir/AGENTS.md"
  local loader="$SKILL_DIR/scripts/write_plan.sh"
  if grep -q "feature-design-plan" "$file" 2>/dev/null; then
    echo "[feature-design-plan] $file 已包含,跳过"; return 0
  fi
  cat >> "$file" <<EOF

## feature-design-plan(设计已确认后沉淀开发设计文档)
当 NEW_FEATURE 需求已梳理清楚,或 FEATURE_CHANGE 已完成 Design Delta、需要重新设计,且"产生了值得后续 AI 再次读取的设计决策"时:
1. 先写设计文档: bash $loader "中文功能简介"
   (固定路径 docs/plan/YYYY-MM-DD-中文功能简介.md,固定 7 块: 背景/开发目标/实现范围/技术设计/变更影响/开发TODO/待确认)
2. 按 SKILL.md 的 7 块结构填充;FEATURE_CHANGE 保留 原设计 vs 新设计 差异。
3. BUG_FIX 及小型改动(加字段/改校验/改SQL/改配置)不触发,直接开发 → dev-changelog。
命令参考: FEATURE_DESIGN_PLAN 用法
EOF
  echo "[feature-design-plan] 已写入 $file"
}

case "${1:-}" in
  codex|--editor)
    ed="${2:-codex}"; repo="${3:-$PWD}"
    cd "$repo" 2>/dev/null || { echo "目录/仓库无效:$repo" >&2; exit 1; }
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "不是 git 仓库" >&2; exit 1; }
    install_codex "$repo_root/.codex" "$repo_root"
    ;;
  *) echo "用法: install_hook.sh --editor codex|cursor|claude [repo] (codex 已支持)" >&2 ;;
esac