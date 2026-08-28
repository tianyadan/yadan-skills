#!/usr/bin/env bash
# dev-changelog / record_change.sh
# 核心入口:读取最近一次 commit 的 git diff,交给 headless `claude -p`
# 生成结构化变更文档,写入 <仓库根>/docs/change-log/YYYY/MM/DD/<HHMMSS>_<uuid8>.md
#
# 使用方式(一般由 post-commit 钩子自动调用,也可手动):
#   bash record_change.sh [commit_range]
#     commit_range  默认 "HEAD~1..HEAD";可传任意范围,如 "HEAD~3..HEAD"

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"

# ---- 加载配置 ----
if [ -f "$SKILL_DIR/config.sh" ]; then
  # shellcheck disable=SC1091
  source "$SKILL_DIR/config.sh"
fi

if [ "${DEV_CHANGELOG_ENABLED:-1}" != "1" ]; then
  exit 0
fi

# ---- 定位仓库根 ----
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "[dev-changelog] 不在 git 仓库中,跳过" >&2
  exit 0
}

cd "$REPO_ROOT" || exit 1

RANGE="${1:-HEAD~1..HEAD}"

# ---- 有未提交改动时才走"当前工作区"逻辑;post-commit 场景用 commit 范围 ----
# 先取 commit 范围的 diff;若为空(如首个提交),退回工作区 diff
DIFF_NAMES="$(git diff --name-only "$RANGE" 2>/dev/null)"
if [ -z "$DIFF_NAMES" ]; then
  DIFF_NAMES="$(git diff --name-only HEAD 2>/dev/null)"
fi

if [ -z "${DIFF_NAMES// /}" ]; then
  echo "[dev-changelog] 没有可记录的改动,跳过" >&2
  exit 0
fi

DIFF_BODY="$(git diff "$RANGE" 2>/dev/null)"
[ -z "$DIFF_BODY" ] && DIFF_BODY="$(git diff HEAD 2>/dev/null)"

COMMIT_MSG="$(git log -1 --format='%s' "$RANGE"^{commit} 2>/dev/null || git log -1 --format='%s' 2>/dev/null)"
AUTHOR="$(git config user.name 2>/dev/null || echo unknown)"

# ---- 去重:对 diff 内容算 sha256,查重 ----
DIFF_HASH="$(printf '%s' "$DIFF_BODY" | shasum -a 256 | awk '{print $1}' | cut -c1-16)"
LOG_DIR="$REPO_ROOT/$DEV_CHANGELOG_DIR"
HASH_STORE="$LOG_DIR/.last-seen-hashes"
mkdir -p "$LOG_DIR"

if [ -f "$HASH_STORE" ] && grep -qF "$DIFF_HASH" "$HASH_STORE" 2>/dev/null; then
  echo "[dev-changelog] 该 diff (${DIFF_HASH}) 已记录过,去重跳过" >&2
  exit 0
fi

# ---- 生成目标路径:YYYY/MM/DD/HHMMSS_uuid8.md ----
NOW="$(date '+%Y/%m/%d')"
STAMP="$(date '+%H%M%S')"
UUID8="$(uuidgen 2>/dev/null | tr -d '-' | cut -c1-8)"
[ -z "$UUID8" ] && UUID8="$(openssl rand -hex 4 2>/dev/null)"
YEAR="$(date '+%Y')"

TARGET_DIR="$LOG_DIR/$NOW"
mkdir -p "$TARGET_DIR"
TARGET_FILE="$TARGET_DIR/${STAMP}_${UUID8}.md"

# ---- 截断 diff,避免参数过长 ----
MAX="${DEV_CHANGELOG_MAX_DIFF:-40000}"
if [ "${#DIFF_BODY}" -gt "$MAX" ]; then
  DIFF_BODY="$(printf '%s' "$DIFF_BODY" | head -c "$MAX")"$'\n...[diff 过长已截断]'
fi

# ---- 组装提示词 ----
LANG_ZHS="--"
PROMPT="你是研发变更记录助手。请阅读下面的 git diff,用简洁中文(如配置为 en 则英文)生成一份变更文档 Markdown。
只输出 Markdown 正文,不要包裹代码块、不要任何解释。

要求包含以下几个小节:
## 需求背景
(简述这次改动要解决的问题或需求)
## 变更文件
(仅列出文件名 basename,不要完整路径,用 - 列表)
## 实现功能 / 修复 Bug
(逐条列出实现了什么功能,或修复了什么 bug)
## 备注
(可选的注意事项、风险,没有则省略)

提交信息: $COMMIT_MSG
作者: $AUTHOR

以下是 git diff:
---
$DIFF_BODY
---"

# ---- 调用 headless claude -p(自动走全局代理 + 内部模型,免费) ----
# 仅要求模型读取 diff 并输出 Markdown,不需要任何工具权限,故不带权限相关 flag
# 继承调用方环境(ANTHROPIC_BASE_URL / 代理端口由用户全局设置提供)
BODY="$(claude -p "$PROMPT" 2>/dev/null)"
if [ -z "$BODY" ]; then
  echo "[dev-changelog] 生成失败(claude 未返回内容)" >&2
  exit 1
fi

# ---- 写入文档 ----
cat > "$TARGET_FILE" <<EOF
# 变更记录

> 提交: $COMMIT_MSG
> 作者: $AUTHOR
> 日期: $(date '+%Y-%m-%d %H:%M:%S')
> diff-hash: \`$DIFF_HASH\`

---

$BODY
EOF

# ---- 记录 hash 供下次去重 ----
printf '%s\n' "$DIFF_HASH" >> "$HASH_STORE"

echo "[dev-changelog] 已写入 $TARGET_FILE" >&2
