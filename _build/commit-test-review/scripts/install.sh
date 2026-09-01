#!/usr/bin/env bash
# commit-test-review / install.sh
# 把全自动 post-commit 钩子安装到当前仓库(或指定仓库)的 .git/hooks/post-commit。
#
# 用法:
#   bash install.sh                # 安装到当前仓库
#   bash install.sh /path/to/repo
#   bash install.sh --remove [repo]    # 卸载
#   bash install.sh --status [repo]     # 查看是否已安装
#   bash install.sh --init [repo]       # 安装钩子 + 初始化 .ai-test + docs/test

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"

if [ -f "$SKILL_DIR/config.sh" ]; then
  # shellcheck disable=SC1091
  source "$SKILL_DIR/config.sh"
fi

MODE="install"
TARGET="${1:-}"
if [ "$TARGET" = "--remove" ]; then MODE="remove"; TARGET="${2:-}"; fi
if [ "$TARGET" = "--status" ]; then MODE="status"; TARGET="${2:-}"; fi
if [ "$TARGET" = "--init" ]; then MODE="init"; TARGET="${2:-}"; fi

if [ -n "$TARGET" ]; then
  cd "$TARGET" 2>/dev/null || { echo "目录不存在:$TARGET" >&2; exit 1; }
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "[commit-test-review] 不是 git 仓库,无法安装钩子" >&2
  echo "[commit-test-review] 仍可手动运行 bash '$SCRIPT_DIR/ai-test' init" >&2
  exit 1
}

GIT_DIR="$REPO_ROOT/.git"
if [ -f "$GIT_DIR" ]; then  # submodule / worktree(.git 是文件)
  GIT_DIR="$(git -C "$REPO_ROOT" rev-parse --git-dir 2>/dev/null || echo "$GIT_DIR")"
fi
HOOK_PATH="$GIT_DIR/hooks/post-commit"

if [ "$MODE" = "status" ]; then
  if [ -f "$HOOK_PATH" ] && grep -q "commit-test-review" "$HOOK_PATH" 2>/dev/null; then
    echo "[commit-test-review] 已安装:$HOOK_PATH"
  else
    echo "[commit-test-review] 未安装"
  fi
  exit 0
fi

if [ "$MODE" = "remove" ]; then
  if [ -f "$HOOK_PATH" ] && grep -q "commit-test-review" "$HOOK_PATH" 2>/dev/null; then
    rm -f "$HOOK_PATH"
    echo "[commit-test-review] 已卸载钩子:$HOOK_PATH"
  else
    echo "[commit-test-review] 未找到 commit-test-review 钩子,无需卸载"
  fi
  exit 0
fi

# 安装:替换占位符
sed "s|__SKILL_SCRIPTS__|$SCRIPT_DIR|g" "$SCRIPT_DIR/post-commit.sh" > "$HOOK_PATH"
chmod +x "$HOOK_PATH"

mkdir -p "$REPO_ROOT/.ai-test/logs" "$REPO_ROOT/docs/test"
if [ ! -f "$REPO_ROOT/.ai-test/.gitignore" ]; then
  printf '# ai-test 本地运行信息(不入库)\nlogs/\nruntime.lock\nvenv/\n' > "$REPO_ROOT/.ai-test/.gitignore"
fi

echo "[commit-test-review] 已安装 post-commit 钩子到:$HOOK_PATH"
echo "[commit-test-review] 报告目录:$REPO_ROOT/docs/test"
echo "[commit-test-review] 本地日志:$REPO_ROOT/.ai-test/logs/commit-test-review.log"
echo "[commit-test-review] 每次 commit 后将自动触发(后台运行,不影响提交)。"
echo "[commit-test-review] 首次请先初始化(建 venv + 装 pymysql + 建 config):"
echo "[commit-test-review]   bash '$SCRIPT_DIR/ai-test' init"

if [ "$MODE" = "init" ]; then
  echo "[commit-test-review] --init 模式:调用 ai-test init..."
  bash "$SCRIPT_DIR/ai-test" init || echo "[commit-test-review] 注意: init 有告警,请查看上方输出"
fi
