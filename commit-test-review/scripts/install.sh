#!/usr/bin/env bash
# commit-test-review / install.sh
# 把全自动 post-commit 钩子片段合并进当前仓库(或指定仓库)的 .git/hooks/post-commit。
# 每次 commit 后自动触发 commit-test-review 测试审查。
# 采用"按标记块追加"策略,可与 dev-changelog 等其他技能片段共存,互不覆盖。
#
# 用法:
#   bash install.sh                # 安装到当前仓库
#   bash install.sh /path/to/repo
#   bash install.sh --remove [repo]    # 卸载(仅摘除本技能的标记块)
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

MARKER="commit-test-review"
BEGIN="^# MARKER_BEGIN $MARKER$"
END="^# MARKER_END $MARKER$"

# 摘除本技能的标记块:先删块,再清理行首即为 "#!/..." 之后全是空白/注释的"空壳"头部
strip_block() {
  local path="$1"
  awk -v b="$BEGIN" -v e="$END" \
    'BEGIN{skip=0} $0 ~ b{skip=1; next} $0 ~ e{skip=0; next} !skip{print}' \
    "$path" > "${path}.tmp"
  awk 'BEGIN{h=1} h && /^#!/{print; h=0; next} h && /^[[:space:]]*#/ {next} {print}' \
    "${path}.tmp" > "${path}.tmp2"
  mv "${path}.tmp2" "$path"
  rm -f "${path}.tmp"
}

remove_ctr() {
  if [ ! -f "$HOOK_PATH" ] || ! grep -q "$MARKER" "$HOOK_PATH" 2>/dev/null; then
    echo "[commit-test-review] 未发现本技能片段,无需卸载"
    return
  fi
  strip_block "$HOOK_PATH"
  if ! grep -v -e '^[[:space:]]*$' -e '^[[:space:]]*#' "$HOOK_PATH" | grep -q .; then
    rm -f "$HOOK_PATH"
  fi
  echo "[commit-test-review] 已从钩子中摘除本技能片段:$HOOK_PATH"
}

if [ "$MODE" = "status" ]; then
  if [ -f "$HOOK_PATH" ] && grep -q "$MARKER" "$HOOK_PATH" 2>/dev/null; then
    echo "[commit-test-review] 已安装:$HOOK_PATH"
  else
    echo "[commit-test-review] 未安装"
  fi
  exit 0
fi

if [ "$MODE" = "remove" ]; then
  remove_ctr
  exit 0
fi

# 生成本技能片段:替换占位符
FRAG="$SCRIPT_DIR/post-commit.sh"
sed "s|__SKILL_SCRIPTS__|$SCRIPT_DIR|g" "$FRAG" > "${HOOK_PATH}.ctr"

if [ ! -f "$HOOK_PATH" ]; then
  # 仓库还没有任何 post-commit 钩子:以本片段作为钩子主体,并补 shebang 与 header
  {
    printf '#!/usr/bin/env bash\n'
    printf '# 合并式 git post-commit 钩子(由多个技能片段组成,按标记块管理)\n'
    printf '# 后台运行 + 静默失败:绝不阻塞/拖慢正常 commit。\n\n'
    cat "${HOOK_PATH}.ctr"
  } > "$HOOK_PATH"
else
  if grep -q "$MARKER" "$HOOK_PATH"; then
    # 本片段已存在:先摘除旧块,再重新追加,保持内容最新
    remove_ctr
  fi
  {
    printf '\n'
    cat "${HOOK_PATH}.ctr"
  } >> "$HOOK_PATH"
fi
chmod +x "$HOOK_PATH"
rm -f "${HOOK_PATH}.ctr"

mkdir -p "$REPO_ROOT/.ai-test/logs" "$REPO_ROOT/docs/test"
if [ ! -f "$REPO_ROOT/.ai-test/.gitignore" ]; then
  printf '# ai-test 本地运行信息(不入库)\nlogs/\nruntime.lock\nvenv/\n' > "$REPO_ROOT/.ai-test/.gitignore"
fi

echo "[commit-test-review] 已合并 post-commit 片段(-# commit-test-review#-)到:$HOOK_PATH"
echo "[commit-test-review] 报告目录:$REPO_ROOT/docs/test"
echo "[commit-test-review] 本地日志:$REPO_ROOT/.ai-test/logs/commit-test-review.log"
echo "[commit-test-review] 每次 commit 后将自动触发(与其它技能片段共存,后台运行,不影响提交)。"
echo "[commit-test-review] 首次请先初始化(建 venv + 装 pymysql + 建 config):"
echo "[commit-test-review]   bash '$SCRIPT_DIR/ai-test' init"

if [ "$MODE" = "init" ]; then
  echo "[commit-test-review] --init 模式:调用 ai-test init..."
  bash "$SCRIPT_DIR/ai-test" init || echo "[commit-test-review] 注意: init 有告警,请查看上方输出"
fi
