#!/usr/bin/env bash
# dev-changelog / install_hook.sh
# 把全自动 post-commit 钩子安装到指定(默认当前)仓库。
# 每次 git commit 后自动调用 record_change.sh 记录变更文档。
#
# 用法:
#   bash install_hook.sh            # 安装到当前目录所在仓库
#   bash install_hook.sh /path/to/repo
#   bash install_hook.sh --remove [repo]   # 卸载钩子

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"

MODE="install"
TARGET="${1:-}"
if [ "$TARGET" = "--remove" ]; then
  MODE="remove"
  TARGET="${2:-}"
fi

if [ -n "$TARGET" ]; then
  cd "$TARGET" || { echo "目录不存在:$TARGET" >&2; exit 1; }
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "[dev-changelog] 不是 git 仓库,无法安装钩子" >&2
  exit 1
}

GIT_DIR="$REPO_ROOT/.git"
# 支持 submodule / worktree 场景(.git 可能是文件)
if [ -f "$GIT_DIR" ]; then
  GIT_DIR="$(git rev-parse --git-dir 2>/dev/null || echo "$GIT_DIR")"
fi
HOOK_PATH="$GIT_DIR/hooks/post-commit"

if [ "$MODE" = "remove" ]; then
  if [ -f "$HOOK_PATH" ] && grep -q "dev-changelog" "$HOOK_PATH" 2>/dev/null; then
    rm -f "$HOOK_PATH"
    echo "[dev-changelog] 已卸载钩子:$HOOK_PATH"
  else
    echo "[dev-changelog] 未找到 dev-changelog 钩子,无需卸载"
  fi
  exit 0
fi

# 生成钩子:把占位符替换为 skill 实际 scripts 路径
sed "s|__SKILL_SCRIPTS__|$SCRIPT_DIR|g" "$SCRIPT_DIR/post-commit.sh" > "$HOOK_PATH"
chmod +x "$HOOK_PATH"

mkdir -p "$REPO_ROOT/docs/change-log"

echo "[dev-changelog] 已安装 post-commit 钩子到:$HOOK_PATH"
echo "[dev-changelog] 记录目录:$REPO_ROOT/docs/change-log"
echo "[dev-changelog] 每次 commit 后将自动写入变更文档(后台运行,不影响提交)。"
