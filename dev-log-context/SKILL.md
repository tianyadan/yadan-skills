---
name: dev-log-context
description: 会话开始时自动加载项目近期开发日志。用于在没有全局 hook 的其他编辑器(或手动场景)中,让 AI 先读取近 7 天 / 最近 10 条开发变更记录,快速了解项目在做什么、近期改动过哪些文件、代码风格如何,再开始任务。当用户说“读取近期开发日志”“加载项目上下文”“看看最近改了啥”等指令时触发。也可用于解释 / 安装各编辑器(Claude Code / Codex / Cursor)的自动加载配置。
---

# Dev Log Context(会话前自动加载开发日志)

在会话开始时,自动读取项目**近期开发日志**(来源与 `dev-changelog` 技能一致,均为 `<仓库根>/docs/change-log/**/*.md`),让 AI 快速了解「项目在做什么需求、近期改了哪些文件、有哪些风险与实现细节」，再开始本次任务。

## 核心思路

- **一键读取**:运行 `bash load_context.sh` 即可得到一份 Markdown 摘要(近 7 天 / 最近 10 条,可在 `config.sh` 或命令行调整)。
- **全自动**:配合各编辑器的"会话开始"钩子/规则,无需每次显式调用。
- **与 dev-changelog 打通**:dev-changelog 负责「每次 commit 后写日志」，本技能负责「每次会话前读日志」，一写一读构成闭环。

## 方式一:全自动(推荐)

用 `install_hook.sh` 把"会话开始时自动读取日志"装到你的 AI 工具:

```bash
# 安装到当前仓库(Claude Code,项目级)
bash ~/.claude/skills/dev-log-context/scripts/install_hook.sh

# 全局(所有 Claude Code 项目生效)
bash ~/.claude/skills/dev-log-context/scripts/install_hook.sh --global

# 其他编辑器
bash ~/.claude/skills/dev-log-context/scripts/install_hook.sh --editor codex
bash ~/.claude/skills/dev-log-context/scripts/install_hook.sh --editor cursor

# 查看所有安装/卸载说明
bash ~/.claude/skills/dev-log-context/scripts/install_hook.sh --list
```

卸载:

```bash
bash ~/.claude/skills/dev-log-context/scripts/install_hook.sh --remove [--global] [--editor X]
```

各编辑器实现差异:
- **Claude Code**:写入 `hooks.SessionStart`(每次会话开始触发一次命令),项目级在 `.claude/settings.json`,全局在 `~/.claude/settings.json`。
- **Codex**:写入 `.codex/AGENTS.md` 指令「每次新会话开始时先运行 load_context.sh」。
- **Cursor**:写入 `.cursor/rules/dev-log-context.mdc` 的 alwaysApply 规则。

> 提示:SessionStart 钩子的输出会自动进入 Claude 的上下文。Codex / Cursor 通过规则文本要求 AI 主动执行一次命令。

## 方式二:手动(会话内)

未安装钩子时,Claude 也可在会话开始时直接执行:

```bash
bash ~/.claude/skills/dev-log-context/scripts/load_context.sh
# 常用变体
bash load_context.sh --days 3      # 只看近 3 天
bash load_context.sh --limit 5     # 只看最新 5 条
bash load_context.sh --all --raw   # 忽略时间过滤并输出完整文档
```

Claude 读取输出后,从中提炼:
- 项目近期的需求方向与实现细节
- 近期改动过的关键文件(便于命中相关代码)
- 代码风格约定(缩写、命名、注释习惯)
- 备注/风险点

## 附带约定(配合方法注释)

技能同时强调 AI 在改造/新增代码时遵循项目现有风格,并在方法/函数名后添加一行**中文注释**简要说明方法用途,例如:

```python
# 计算订单折扣后金额
def calc_final_amount(price, discount):
    ...
```

```ts
// 初始化图表并绑定事件,返回销毁函数
function initChart(el) { ... }
```

## 配置

见 `config.sh`(时间窗口 `DEV_LOG_CONTEXT_DAYS`、条数上限 `DEV_LOG_CONTEXT_LIMIT`、日志目录 `DEV_LOG_CONTEXT_DIR`、语种 `DEV_LOG_CONTEXT_LANG`)。

## 依赖

本技能读取 dev-changelog 写入的日志;若未安装 dev-changelog 或仓库没有 `docs/change-log/`,脚本会给出提示并无害跳过。
