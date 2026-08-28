---
name: project-map
description: 项目脉络分析。充分阅读整个项目、梳理层级与大体脉络,生成并维护 docs/project-map.md(项目概览/目录结构/分层模块/核心链路/变更时间线)。当用户说“分析项目脉络”“梳理项目结构”“生成项目架构文档”“梳理层级”“项目整体脉络”“project-map”等指令时触发。首次全量生成(--full),之后每小时由系统 crontab 自动增量更新:仅针对 dev-changelog 开发日志中新增的变更做增量分析并追加写回,无变更则零 token 跳过,并记录上次更新时间。
---

# Project Map(项目脉络分析)

充分阅读项目、梳理层级与整体脉络,生成并持续维护一份 **`docs/project-map.md`**,让任何 AI(或人)查看这一个文件即可快速掌握项目全貌与演进过程。

与另外两件套配合,**写 → 读 → 脉络** 闭环:
- `dev-changelog` —— commit 后写开发日志(`docs/change-log/`)。
- `dev-log-context` —— 会话前读开发日志。
- `project-map`(本技能)—— 把开发日志的增量变化持续沉淀进项目脉络文档。

## 核心机制

- **首次**: `--full` 通读项目,生成完整脉络(概览/目录结构/分层模块/核心链路/变更时间线)。
- **之后**: 每小时由系统 cron 触发 `--incremental`,只分析「上次更新时间」之后新增的开发日志;有变更才做增量分析并**追加写回**「变更时间线」、就地修订受影响的结构小节;无变更**零 token 跳过**。
- **记录上次更新时间**: meta 文件(`docs/.project-map-meta`)保存时间戳+已处理日志,保证幂等、不重复写。

## 方式一:全自动(crontab,推荐)

```bash
# 注册每小时自动增量更新(当前仓库)
bash ~/.claude/skills/project-map/scripts/install_cron.sh

# 卸载 / 查看
bash ~/.claude/skills/project-map/scripts/install_cron.sh --remove
bash ~/.claude/skills/project-map/scripts/install_cron.sh --list
```

> crontab 为用户级任务,每个仓库各装一次即可(脚本按仓库根自动去重)。

## 方式二:手动(会话内)

```bash
# 全量生成(全新项目/首次)
bash ~/.claude/skills/project-map/scripts/scan_project.sh --full

# 手动增量更新
bash ~/.claude/skills/project-map/scripts/scan_project.sh --incremental
```

## 产物结构(`docs/project-map.md`)

```
## 1. 项目概览        技术栈/定位/入口
## 2. 目录层级结构    目录树/分层,标注职责
## 3. 分层 / 模块     模块+职责+关键文件
## 4. 核心链路 / 数据流
## 5. 变更时间线      纯增量追加区(每次变更一条,含需求/文件/影响)
```

## 附带约定

技能同时强调:写代码时遵循项目现有风格,并在方法/函数名后添加一行**中文注释**简要说明方法用途。

## 配置

见 `config.sh`(输出文件 `PROJECT_MAP_FILE`、cron 分钟 `PROJECT_MAP_CRON_MINUTE`、增量依据日志目录 `PROJECT_MAP_LOG_DIR`、文本上限 `PROJECT_MAP_MAX_TEXT` 等)。

## 依赖

增量更新依赖 dev-changelog 写入的 `docs/change-log/` 开发日志;若没有日志目录,`--full` 仍可生成全量脉络,`--incremental` 会提示先全量或直接跳过。
