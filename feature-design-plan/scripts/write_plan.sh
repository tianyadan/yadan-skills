#!/usr/bin/env bash
# feature-design-plan / write_plan.sh
# 生成"已确定设计 → 开发设计文档"的骨架/追踪文件(固定路径+固定结构,避免每次问路径/格式)。
# 本脚本只负责:建固定路径、校验目录、输出可执行 TODO 追踪;正文设计内容由 AI 参考 SKILL.md 的 7 块模板撰写。
#
# 用法:
#   bash write_plan.sh <功能简介,会用于文件名>
#   bash write_plan.sh --list       # 列出 docs/plan/ 下所有 Plan
#   bash write_plan.sh --path-only <功能简介>
#
# 文档路径固定: <仓库根>/docs/plan/YYYY-MM-DD-中文功能简介.md

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
  echo "[feature-design-plan] 不在 git 仓库中,请 cd 到仓库内" >&2
  exit 1
}
cd "$REPO_ROOT" || exit 1

PLAN_DIR="$REPO_ROOT/${FEATURE_DESIGN_PLAN_DIR:-docs/plan}"

# 中文文件名中的非法字符替换为 _(保留中文/字母/数字)
sanitize() { # 清洗字符串,用于文件名,保留中文
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$1" <<'PY'
import sys,re
s=sys.argv[1]
# 保留 中文/字母/数字/_-/. ; 其余(空格/标点等)转 _
s=re.sub(r'[^0-9A-Za-z一-鿿_.-]+','_',s)
s=re.sub(r'__+','_',s).strip('_')
sys.stdout.write(s)
PY
  else
    printf '%s' "$1" | LC_ALL=C tr -c 'A-Za-z0-9_' '_' | sed 's/__*/_/g'
  fi
}

if [ "${1:-}" = "--list" ]; then
  echo "docs/plan/ 下的 Plan:"
  find "$PLAN_DIR" -maxdepth 1 -type f -name '*.md' 2>/dev/null | sort | sed "s#$REPO_ROOT/##"
  exit 0
fi

if [ "${1:-}" = "--path-only" ]; then
  NAME="$(sanitize "${2:-}")"
  echo "$REPO_ROOT/${FEATURE_DESIGN_PLAN_DIR:-docs/plan}/$(date '+%Y-%m-%d')-${NAME}.md"
  exit 0
fi

SLUG="${1:-}"
[ -z "$SLUG" ] && SLUG="待定"
SLUG="$(sanitize "$SLUG")"

mkdir -p "$PLAN_DIR"
FILE="$PLAN_DIR/$(date '+%Y-%m-%d')-${SLUG}.md"

# 已存在则直接给出路径(避免覆盖/重复),否则写骨架
if [ -f "$FILE" ]; then
  echo "[feature-design-plan] 已存在,不再覆盖: $FILE" >&2
  echo "$FILE"
else
  cat > "$FILE" <<EOF
# <功能简介>

> 状态: 已确认设计 / 待开发
> 创建: $(date '+%Y-%m-%d %H:%M:%S')
> 来源: NEW_FEATURE / FEATURE_CHANGE

## 1. 背景
(为什么做: 要解决的问题或需求)

## 2. 开发目标
(最终要实现什么: 目标结果)

## 3. 实现范围
- 本次实现:
  - ...
- 本次暂不实现:
  - ...

## 4. 技术设计
- 涉及模块:
  - ...
- 接口:
  - ...
- 数据表 / 数据结构:
  - ...
- 核心流程:
  - ...
- 关键规则:
  - ...

## 5. 变更影响
(会影响哪些已有模块 / 接口 / 数据结构。若为 FEATURE_CHANGE,记录 原设计 vs 新设计 差异,示例:
  原设计: region → district
  新设计: businessUnit → region → district
  影响: - SQL 分组, - Response VO, - Excel 表头, - 汇总逻辑, - 前端层级展示
)

## 6. 开发 TODO
- [ ] ...

## 7. 待确认事项
- [ ] ...
EOF
  echo "[feature-design-plan] 已生成: $FILE" >&2
  echo "$FILE"
fi
