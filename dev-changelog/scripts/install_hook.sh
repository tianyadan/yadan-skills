#!/usr/bin/env bash
# dev-changelog / install_hook.sh
# 把全自动 post-commit 钩子片段合并进指定(默认当前)仓库的 .git/hooks/post-commit。
# 每次 git commit 后自动调用 record_change.sh 记录变更文档。
# 采用"按标记块追加"策略,可与 commit-test-review 等其他技能片段共存,互不覆盖。
#
# 用法:
#   bash install_hook.sh            # 安装到当前目录所在仓库
#   bash install_hook.sh /path/to/repo
#   bash install_hook.sh --remove [repo]   # 卸载(仅摘除本技能的标记块)

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
  cd "$TARGET" 2>/dev/null || { echo "目录不存在:$TARGET" >&2; exit 1; }
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

MARKER="dev-changelog"
BEGIN="^# MARKER_BEGIN $MARKER$"
END="^# MARKER_END $MARKER$"

# 摘除本技能的标记块:先删块,再清理仅剩空行/注释/残缺的头部
strip_block() {
  local path="$1"
  # 删除 BEGIN 到 END 的整块(含标记行本身)
  awk -v b="$BEGIN" -v e="$END" \
    'BEGIN{skip=0} $0 ~ b{skip=1; next} $0 ~ e{skip=0; next} !skip{print}' \
    "$path" > "${path}.tmp"
  # 清理行首即为 "#!/..." 之后全是空白/注释的"空壳"头部
  awk 'BEGIN{h=1} h && /^#!/{print; h=0; next} h && /^[[:space:]]*#/ {next} {print}' \
    "${path}.tmp" > "${path}.tmp2"
  mv "${path}.tmp2" "$path"
  rm -f "${path}.tmp"
}

remove_devchangelog() {
  if [ ! -f "$HOOK_PATH" ] || ! grep -q "$MARKER" "$HOOK_PATH" 2>/dev/null; then
    echo "[dev-changelog] 未发现本技能片段,无需卸载"
    return
  fi
  strip_block "$HOOK_PATH"
  # 摘除后若仅剩 shebang/注释/空行(空壳)则整体删除,不留空壳
  if ! grep -v -e '^[[:space:]]*$' -e '^[[:space:]]*#' "$HOOK_PATH" | grep -q .; then
    rm -f "$HOOK_PATH"
  fi
  echo "[dev-changelog] 已从钩子中摘除本技能片段:$HOOK_PATH"
}

if [ "$MODE" = "remove" ]; then
  remove_devchangelog
  exit 0
fi

# 生成本技能片段:替换占位符
FRAG="$SCRIPT_DIR/post-commit.sh"
sed "s|__SKILL_SCRIPTS__|$SCRIPT_DIR|g" "$FRAG" > "${HOOK_PATH}.devchangelog"

if [ ! -f "$HOOK_PATH" ]; then
  # 仓库还没有任何 post-commit 钩子:以本片段作为钩子主体,并补 shebang 与 header
  {
    printf '#!/usr/bin/env bash\n'
    printf '# 合并式 git post-commit 钩子(由多个技能片段组成,按标记块管理)\n'
    printf '# 后台运行 + 静默失败:绝不阻塞/拖慢正常 commit。\n\n'
    cat "${HOOK_PATH}.devchangelog"
  } > "$HOOK_PATH"
else
  if grep -q "$MARKER" "$HOOK_PATH"; then
    # 本片段已存在:先摘除旧块,再重新追加,保持内容最新
    remove_devchangelog
  fi
  # 追加本片段到末尾
  {
    printf '\n'
    cat "${HOOK_PATH}.devchangelog"
  } >> "$HOOK_PATH"
fi
chmod +x "$HOOK_PATH"
rm -f "${HOOK_PATH}.devchangelog"

mkdir -p "$REPO_ROOT/docs/change-log"

echo "[dev-changelog] 已合并 post-commit 片段(-# dev-changelog#-)到:$HOOK_PATH"
echo "[dev-changelog] 记录目录:$REPO_ROOT/docs/change-log"
echo "[dev-changelog] 每次 commit 后将自动写入变更文档(与其它技能片段共存,后台运行,不影响提交)。"
