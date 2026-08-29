#!/usr/bin/env bash
# project-map / scan_project.sh
# 核心生成器:全量或增量分析项目脉络,写入 <仓库根>/docs/project-map.md。
#
# 用法:
#   bash scan_project.sh --full         # 全量:通读项目,生成完整脉络文档
#   bash scan_project.sh --incremental # 增量(默认):只分析上次之后新增的开发日志,追加/就地更新
#
# 增量逻辑:
#   1. 读 meta 中上次扫描的 epoch;
#   2. find docs/change-log 里新于该时间戳、且未被处理过的 .md 日志;
#   3. 无 → "无新变更,跳过",退出 0(零 token);
#   4. 有 → 提取日志中的变更文件,定位其当前内容,交 headless claude -p 生成"增量更新段",
#      追加到 project-map.md 的「变更时间线」区,并对命中的模块小节就地小改;
#   5. 更新 meta 时间戳与"已处理日志"清单,保证幂等。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"

# ---- 加载配置 ----
if [ -f "$SKILL_DIR/config.sh" ]; then
  # shellcheck disable=SC1091
  source "$SKILL_DIR/config.sh"
fi

# ---- 定位仓库根 ----
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "[project-map] 不在 git 仓库中,跳过" >&2
  exit 0
}
cd "$REPO_ROOT" || exit 1

MAP_FILE="$REPO_ROOT/${PROJECT_MAP_FILE:-docs/project-map.md}"
MAP_DIR="$(dirname "$MAP_FILE")"
META_FILE="$MAP_DIR/${PROJECT_MAP_META_NAME:-.project-map-meta}"
LOG_DIR="$REPO_ROOT/${PROJECT_MAP_LOG_DIR:-docs/change-log}"

read_meta() { # 读取 meta 键值
  local key="$1"
  [ -f "$META_FILE" ] && awk -F= -v k="$key" '$1==k{print $2}' "$META_FILE" | tail -n1
}

now_epoch() { # 当前秒级时间戳(macOS / Linux 兼容)
  date +%s
}

# 带超时的 claude -p 调用: 避免 "claude -p" 在前台静默挂住导致"没反应"
# 超时(>PROJECT_MAP_CLAUDE_TIMEOUT 秒,默认 90s)仍无结果 → fallback
run_claude() { # 调用 claude -p,带 timeout + 可见 stderr;claude 缺失/超时/无 → fallback
  local prompt="$1" t="${PROJECT_MAP_CLAUDE_TIMEOUT:-90}"
  if ! command -v claude >/dev/null 2>&1; then
    echo "[project-map] ⚠️ claude 命令不可用,直接 fallback(文件清单) —— 不再等待" >&2
    printf '&__CLAUDE_FALLBACK__&'
    return
  fi
  # macOS 无 `timeout`,优先 gtimeout;/usr/bin/timeout
  if command -v gtimeout >/dev/null 2>&1; then
    T="gtimeout $t"
  elif command -v timeout >/dev/null 2>&1; then
    T="timeout $t"
  else
    T=""   # 无 timeout 工具: 不用 timeout 直接跑(有风险仍可能卡,但 bear 机会)
    echo "[project-map] ⚠️ 无 timeout/gtimeout,claude 可能仍会等待;建议 brew install coreutils" >&2
  fi
  echo "[project-map] ⏳ 调 claude -p 生成…(超时 ${t}s)" >&2   # ← 控制台可见进度
  # stderr 不再吞,让 claude 进度可见;仍放 $(...) 捕获 stdout
  local out
  out="$( { eval "$T claude -p $prompt" ; } 2>&1 )"
  if [ -z "$out" ]; then
    echo "[project-map] ⏱️ claude 未返回(超时或不可用),退化: 生成纯文件清单 project-map" >&2
    printf '&__CLAUDE_FALLBACK__&'
    return
  fi
  printf '%s' "$out"
}


# ================= 全量模式 =================
full_scan() {
  if [ ! -d "$MAP_DIR" ]; then mkdir -p "$MAP_DIR"; fi

  # --- 收集项目结构信息(只读,不产生副作用) ---
  ROOT_FILES="$(ls -A 2>/dev/null | grep -v '^\.git$' | head -n 60)"
  TREE_MAX="${PROJECT_MAP_TREE_MAX:-300}"
  TREE_DEPTH="${PROJECT_MAP_TREE_DEPTH:-6}"
  if command -v tree >/dev/null 2>&1; then
    TREE="$(tree -L "$TREE_DEPTH" -I '.git|node_modules|dist|build|.venv|venv' 2>/dev/null | head -n "$TREE_MAX")"
  else
    TREE="$(find . -not -path './.git/*' -not -path '*/node_modules/*' -not -path '*/dist/*' \
      -not -path '*/build/*' -maxdepth "$TREE_DEPTH" 2>/dev/null | head -n "$TREE_MAX")"
  fi

  # 顶层配置文件
  TOP_DOCS=""
  for f in README.md package.json go.mod pyproject.toml Cargo.toml pom.xml build.gradle \
           docker-compose.yml Dockerfile .env.example composer.json requirements.txt; do
    if [ -f "$f" ]; then
      TOP_DOCS="$TOP_DOCS"$'\n'"===== $f ====="$'\n'"$(head -c 3000 "$f" 2>/dev/null)"
    fi
  done

  PROMPT="你是资深架构师。请充分阅读以下项目结构信息,梳理出项目的整体脉络,输出一份结构化的 Markdown 项目脉络文档。

只输出 Markdown 正文,不要包裹代码块、不要任何解释。要求包含以下小节(用 ## 标题):

## 1. 项目概览
(技术栈、项目定位、入口、如何跑起来)

## 2. 目录层级结构
(把给定结构整理成清晰的目录树/分层结构,标注每层职责)

## 3. 分层 / 模块
(按层或按模块列出,名字 + 职责 + 关键文件路径,用 - 列表)

## 4. 核心链路 / 数据流
(关键流程、模块间调用关系;若有明显的数据流/请求链路则描述)

## 5. 变更时间线
(此处保持一个空的小节,只写一个占位注释:<!-- 增量更新将追加在此 -->)

以下 开头两行是文档头部模板,请原样保留在输出最前面:
---
# 项目脉络 / 架构总览

> 最近全量分析: $(date '+%Y-%m-%d %H:%M:%S')
---

顶层文件/配置:
$TOP_DOCS

目录结构:
$TREE

根目录条目:
$ROOT_FILES"

  MAX="${PROJECT_MAP_MAX_TEXT:-60000}"
  [ "${#PROMPT}" -gt "$MAX" ] && PROMPT="$(printf '%s' "$PROMPT" | head -c "$MAX")"

  BODY="$(run_claude "$PROMPT" 2>/dev/null)"
  if [ "$BODY" = "&__CLAUDE_FALLBACK__&" ] || [ -z "$BODY" ]; then
    echo "[project-map] ⚠️ claude 不可用/超时,退化生成纯文件清单 project-map(非 AI 分析版)" >&2
    BODY="$(cat <<EOF

# 项目脉络 / 架构总览(文件清单退化版,claude 不可用时代替)

## 1. 项目概览
(技术栈/定位/入口,待 Ai 补充)

## 2. 目录层级结构
$(printf '%s' "$TREE")

## 3. 分层 / 模块
(待 Ai 补充)

## 4. 核心链路 / 数据流
(待 Ai 补充)

## 5. 变更时间线
<!-- 增量更新将追加在此 -->
EOF
)"
  fi
  # 写入文档(若未自带头部,补上)
  if ! printf '%s' "$BODY" | grep -q '^# 项目脉络'; then
    BODY="# 项目脉络 / 架构总览

> 最近全量分析: $(date '+%Y-%m-%d %H:%M:%S')

$BODY"
  fi
  cat > "$MAP_FILE" <<EOF
$BODY
EOF

  # 记录时间戳
  cat > "$META_FILE" <<EOF
last_scan_at=$(date '+%Y-%m-%d %H:%M:%S')
last_scan_epoch=$(now_epoch)
processed=
EOF
  echo "[project-map] 已全量生成 $MAP_FILE" >&2
}

# ================= 增量模式 =================
incremental_scan() {
  [ -f "$MAP_FILE" ] || {
    echo "[project-map] 尚无 $MAP_FILE,请先全量生成(--full)" >&2
    exit 1
  }

  LAST_EPOCH="$(read_meta last_scan_epoch)"
  LAST_EPOCH="${LAST_EPOCH:-0}"
  # 已处理过的日志路径(逗号分隔),优先按身份去重,不受同秒 mtime 影响
  PROCESSED="$(read_meta processed)"

  # --- 找本次新增/变更的开发日志(逐文件比较 mtime,兼容 macOS/Linux) ---
  NEW_LOGS=""
  if [ -d "$LOG_DIR" ]; then
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      # 排除非文档文件
      case "$f" in *.last-seen-hashes) continue ;; esac
      case "$f" in *.md) ;; *) continue ;; esac
      # 已处理过的直接跳过(身份去重,防同秒误判)
      if printf '%s' "$PROCESSED" | tr ',' '\n' | grep -qxF "$f"; then continue; fi
      MT="$(stat -f '%m' "$f" 2>/dev/null || stat -c '%Y' "$f" 2>/dev/null)"
      MT="${MT:-0}"
      if [ "$MT" -ge "$LAST_EPOCH" ]; then
        NEW_LOGS="$NEW_LOGS"$'\n'"$f"
      fi
    done <<< "$(find "$LOG_DIR" -type f 2>/dev/null | sort)"
  fi
  NEW_LOGS="$(printf '%s\n' "$NEW_LOGS" | grep -v '^$' )"

  if [ -z "$NEW_LOGS" ]; then
    echo "[project-map] 距上次(${LAST_EPOCH})无新开发日志,跳过增量(零成本)" >&2
    exit 0
  fi

  # --- 从新日志提取「需求背景 + 变更文件 basename」 ---
  LOG_SUMMARY=""
  for f in $NEW_LOGS; do
    TITLE="$(grep -m1 '^> 提交:' "$f" 2>/dev/null | sed 's/^> 提交: *//')"
    NEED="$(awk '/^## 需求背景/{x=1;next}/^##/{x=0}x' "$f" 2>/dev/null | grep -v '^$' | head -c 1200)"
    FILES="$(awk '/^## 变更文件/{x=1;next}/^##/{x=0}x' "$f" 2>/dev/null | sed 's/^- *//' | grep -v '^$' | head -c 1500)"
    LOG_SUMMARY="$LOG_SUMMARY"$'\n\n--- 日志: '"$(basename "$f")"$'\n提交: '"$TITLE"$'\n需求背景: '"$NEED"$'\n变更文件: '"$FILES"
  done

  # --- 定位变更文件在当前仓库的内容(仅取其中仍存在的文件) ---
  CHANGED_FILES_CURRENT=""
  FILES_LIST="$(printf '%s' "$LOG_SUMMARY" | grep -oE '(^|[",])[A-Za-z0-9_./-]+\.(vue|ts|tsx|js|jsx|go|py|java|rs|c|h|cpp|sh|sql|md|json|yaml|yml)' | tr -d '",' | sed 's/^ *//' | sort -u)"
  for fn in $FILES_LIST; do
    # basename 无法唯一定位;先尝试仓库内唯一匹配
    HITS="$(find . -type f -name "$(basename "$fn")" -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | head -n 3)"
    # 只取 1 个命中,避免歧义过大
    M="$(printf '%s' "$HITS" | head -n 1)"
    if [ -n "$M" ]; then
      CHANGED_FILES_CURRENT="$CHANGED_FILES_CURRENT"$'\n\n===== '"$M"$' =====\n'"$(head -c 4000 "$M" 2>/dev/null)"
    fi
  done
  [ -n "$CHANGED_FILES_CURRENT" ] && CHANGED_FILES_CURRENT="$(printf '%s' "$CHANGED_FILES_CURRENT" | head -c "${PROJECT_MAP_MAX_TEXT:-60000}")"

  # --- 需要就地刷新结构调整的锚点(第 2/3/4 节) ---
  # 读取现有结构小节作为上下文,让 claude 决定是否更新
  STRUCT_CTX="$(sed -n '/^## 2\. 目录层级结构/,/^## 5\./p' "$MAP_FILE" 2>/dev/null | head -c 8000)"

  PROMPT="你是资深架构师,维护一份项目的脉络文档(\\\"project-map\\\")。现在项目有了新变更(来自开发日志),请做一个**增量更新**:只针对这些新变更分析,不要重写全篇。

输出两部分,严格用下面两个分隔标记包围(不要额外解释):

<STRUCT_UPDATE>
如果新变更影响到了文档的「目录层级结构 / 分层模块 / 核心链路」这些结构性的位置,请**只输出要就地插入或修改这几节的 Markdown 片段**(按 ## 2./3./4. 组织);如果本次变更不涉及结构层面,则留空。
</STRUCT_UPDATE>

<TIMELINE_APPEND>
输出一条要**追加到「## 5. 变更时间线」末尾**的 Markdown 条目,格式:
### <YYYY-MM-DD HH:MM>
- 需求: <变更需求背景摘要>
- 涉及文件: <文件 basename 列表>
- 对脉络影响: <本次增量结论,2-3 句>
</TIMELINE_APPEND>

新变更(来自开发日志):
$LOG_SUMMARY

涉及文件当前内容(定位到的部分):
$CHANGED_FILES_CURRENT

现有脉络文档相关段落(供参考是否要就地更新结构):
$STRUCT_CTX"

  MAX="${PROJECT_MAP_MAX_TEXT:-60000}"
  [ "${#PROMPT}" -gt "$MAX" ] && PROMPT="$(printf '%s' "$PROMPT" | head -c "$MAX")"

  BODY="$(run_claude "$PROMPT" 2>/dev/null)"
  if [ "$BODY" = "&__CLAUDE_FALLBACK__&" ] || [ -z "$BODY" ]; then
    echo "[project-map] ⏱️ claude 不可用/超时,本次增量无 AI 结论,跳过(不改写文档)" >&2
    exit 1
  fi

  # --- 解析输出:python3 提取两个分块(新行安全),写入临时文件 ---
  PY_TMP="$(mktemp)"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$BODY" "$PY_TMP" <<'PY'
import sys
b,out=sys.argv[1],sys.argv[2]
def grab(a):
    o=b.split("<"+a+">",1)
    if len(o)<2: return ""
    m=o[1].split("</"+a+">",1)
    return m[0].strip() if len(m)>1 else ""
s=grab("STRUCT_UPDATE"); p=grab("TIMELINE_APPEND")
open(out,"w").write("STRUCT<<<<EOF>>>>\n"+s+"\n<<<<EOFEND>>>>\nAPPEND<<<<EOF>>>>\n"+p+"\n<<<<EOFEND>>>>\n")
PY
    STRUCT="$(awk '/^STRUCT<<<<EOF>>>>$/{f=1;next}/^<<<<EOFEND>>>>$/{f=0} f' "$PY_TMP")"
    APPEND="$(awk '/^APPEND<<<<EOF>>>>$/{f=1;next}/^<<<<EOFEND>>>>$/{f=0} f' "$PY_TMP")"
  else
    STRUCT="$(printf '%s' "$BODY" | awk '/<STRUCT_UPDATE>/{f=1;next}/<\/STRUCT_UPDATE>/{f=0}f' | sed '/^[[:space:]]*$/d')"
    APPEND="$(printf '%s' "$BODY" | awk '/<TIMELINE_APPEND>/{f=1;next}/<\/TIMELINE_APPEND>/{f=0}f' | sed '/^[[:space:]]*$/d')"
  fi
  rm -f "$PY_TMP"
  [ -z "$APPEND" ] && { echo "[project-map] 增量未产出时间线条目,跳过写入" >&2; exit 0; }

  # 用变更日志路径集合作为该批次标记,防重复
  BATCH_KEY="$(printf '%s' "$NEW_LOGS" | tr '\n' ',' | sed 's/,$//')"

  # --- 就地更新结构小节(若 claude 给出了 STRUCT_UPDATE,用 python3 在 ## 5. 前插入,新行安全) ---
  if [ -n "$STRUCT" ]; then
    python3 - "$MAP_FILE" "$STRUCT" <<'PY'
import sys
path,ins=sys.argv[1],sys.argv[2]
t=open(path).read()
marker="## 5. 变更时间线"
if marker in t:
    t=t.replace(marker, ins.rstrip()+"\n\n"+marker, 1)
else:
    t=t.rstrip()+"\n\n"+ins+"\n"
open(path,"w").write(t)
PY
  fi

  # --- 追加时间线条目到 ## 5. 区 ---
  # 若已有该批次的标记则跳过(幂等)
  if grep -qF "batch: $BATCH_KEY" "$MAP_FILE"; then
    echo "[project-map] 该批次(${BATCH_KEY})已写入,跳过" >&2
  else
    cat >> "$MAP_FILE" <<EOF

<details>
<summary>增量更新批次 batch: $BATCH_KEY</summary>

$APPEND
</details>
EOF
    echo "[project-map] 已追加增量更新到 $MAP_FILE" >&2
  fi

  # --- 记录/刷新已处理日志,更新 meta(合并新增日志身份 → processed) ---
  MERGED="$(printf '%s' "$PROCESSED" | tr ',' '\n' | grep -v '^$')"
  MERGED="$MERGED"$'\n'"$(printf '%s' "$NEW_LOGS")"
  MERGED="$(printf '%s' "$MERGED" | grep -v '^$' | sort -u | tr '\n' ',' | sed 's/,$//')"
  cat > "$META_FILE" <<EOF
last_scan_at=$(date '+%Y-%m-%d %H:%M:%S')
last_scan_epoch=$(now_epoch)
processed=$MERGED
EOF
}

# ================= 分发 =================
MODE="${1:-}"
case "$MODE" in
  --full|-f) full_scan ;;
  --incremental|-i|"") incremental_scan ;;
  *) echo "[project-map] 未知参数:$MODE(支持 --full / --incremental)" >&2; exit 1 ;;
esac
