#!/usr/bin/env bash
# commit-test-review / trigger.sh
# post-commit 触发脚本:检测 claude CLI -> 加运行锁 -> 调用 headless claude 加载
# commit-test-review skill 分析本次 commit,生成 docs/test/ 测试记录。
#
# 硬性保证:任何失败都不得影响已经成功的 git commit(异步质量检查,非质量门禁)。
#
# 用法:
#   bash trigger.sh [commit-range]
#     commit-range 默认 "HEAD~1..HEAD";一般由 post-commit 钩子自动调用。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"

if [ -f "$SKILL_DIR/config.sh" ]; then
  # shellcheck disable=SC1091
  source "$SKILL_DIR/config.sh"
fi

if [ "${COMMIT_TEST_REVIEW_ENABLED:-1}" != "1" ]; then
  exit 0
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "[commit-test-review] 不在 git 仓库中,跳过" >&2
  exit 0
}
cd "$REPO_ROOT" || exit 0

RANGE="${1:-HEAD~1..HEAD}"

LOG_DIR="$REPO_ROOT/.ai-test/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/${CRT_LOG_NAME:-commit-test-review.log}"
LOCK="$REPO_ROOT/.ai-test/${CRT_LOCK_NAME:-runtime.lock}"

tslog() {
  printf '[%s] [commit-test-review] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
  echo "[commit-test-review] $*" >&2
}

# 提交信息
COMMIT_HASH="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
COMMIT_MSG="$(git log -1 --format='%s' 2>/dev/null || true)"
CLAUDE_VERSION=""
if command -v claude >/dev/null 2>&1; then
  CLAUDE_VERSION="$(claude --version 2>/dev/null || true)"
fi

# ---- 1. 检查 claude CLI ----
if ! command -v claude >/dev/null 2>&1; then
  cat >> "$LOG_FILE" <<EOF
$(date '+%Y-%m-%d %H:%M:%S')
Commit: $COMMIT_HASH
Claude CLI: NOT_FOUND
Review: SKIPPED
Reason: Claude Code CLI is not installed.
EOF
  echo ""
  echo "────────────────────────────────────"
  echo "Commit Test Review"
  echo "⚠ Claude Code CLI not found."
  echo "Automated code review and testing skipped."
  echo "This feature currently supports Claude Code CLI only."
  echo "Install Claude Code on macOS:"
  echo "  curl -fsSL https://claude.ai/install.sh | bash"
  echo "or:"
  echo "  brew install --cask claude-code"
  echo "────────────────────────────────────"
  exit 0
fi

# ---- 2. 运行锁:防止重复/递归(mkdir 原子拿锁,兼容 macOS) ----
if [ -d "$LOCK" ]; then
  tslog "存在 runtime.lock,跳过(已有测试任务运行)"
  exit 0
fi
if ! mkdir "$LOCK" 2>/dev/null; then
  tslog "存在 runtime.lock,跳过(已有测试任务运行)"
  exit 0
fi
trap 'rm -rf "$LOCK"' EXIT

# ---- 3. 取 diff ----
DIFF_NAMES="$(git diff --name-only "$RANGE" 2>/dev/null)"
DIFF_BODY="$(git diff "$RANGE" 2>/dev/null)"
if [ -z "${DIFF_BODY// /}" ]; then
  tslog "无文件变更,跳过"
  exit 0
fi
MAX="${CRT_MAX_DIFF:-60000}"
if [ "${#DIFF_BODY}" -gt "$MAX" ]; then
  DIFF_BODY="$(printf '%s' "$DIFF_BODY" | head -c "$MAX")"$'\n...[diff 过长已截断]'
fi

REPORT_DIR="${CRT_REPORT_DIR:-docs/test}"

# ---- 4. 组装提示词并调用 claude -p ----
tslog "Commit: $COMMIT_HASH | claude: detected ($CLAUDE_VERSION) | Review: started"

# 把 diff 写入临时文件再传给 claude,避免超长参数/转义问题
PROMPT_FILE="$(mktemp)"
cat > "$PROMPT_FILE" <<PROMPT_EOF
A git commit has just completed.

Run the repository-local commit-test-review skill.

Review only the latest commit.

Commit: $COMMIT_HASH

Analyze the diff between HEAD^ and HEAD.

Follow the commit-test-review skill strictly.

Determine one of:
NEED_TEST
SKIP_TEST
MANUAL_VERIFY

If NEED_TEST:
- inspect existing tests
- reuse existing tests whenever possible
- create tests only when necessary
- write tests into the project's existing test directory
- use configured databases (via ai-test CLI / .ai-test) only when required
- run the relevant tests
- do not modify production code

Always generate the test record under:
$REPORT_DIR

Commit message: $COMMIT_MSG

Changed files:
$DIFF_NAMES

Diff:
---
$DIFF_BODY
---
PROMPT_EOF

CLAUDE_BIN="$(command -v claude)"
run_claude() {
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "${CRT_CLAUDE_TIMEOUT:-180}" "$CLAUDE_BIN" -p "$(cat "$PROMPT_FILE")" --cd "$REPO_ROOT" --permission-mode acceptEdits
  elif command -v timeout >/dev/null 2>&1; then
    timeout "${CRT_CLAUDE_TIMEOUT:-180}" "$CLAUDE_BIN" -p "$(cat "$PROMPT_FILE")" --cd "$REPO_ROOT" --permission-mode acceptEdits
  else
    "$CLAUDE_BIN" -p "$(cat "$PROMPT_FILE")" --cd "$REPO_ROOT" --permission-mode acceptEdits
  fi
}

if ! run_claude >> "$LOG_FILE" 2>&1; then
  rm -f "$PROMPT_FILE"
  tslog "Commit: $COMMIT_HASH | claude 执行失败(不影响 commit),详见日志"
  exit 0
fi
rm -f "$PROMPT_FILE"

tslog "Commit: $COMMIT_HASH | Review: finished | 详见 $REPORT_DIR 报告与日志"
exit 0
