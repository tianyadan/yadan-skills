---
name: dev-task-context
description: 开发 Agent 的 Context Router。识别用户任务类型(NEW_FEATURE 新功能 / BUG_FIX 修 bug / FEATURE_CHANGE 改需求),并按需自动读取最小必要上下文(project-map / change-log / git / docs/plans)。当用户说“分析这个需求”“这个问题怎么修”“改下这个功能”“恢复这个任务的上下文”“读相关文档”等指令时触发。核心原则:按任务读取,不无差别全量加载。
---

# Dev Task Context(开发 Agent 的 Context Router)

不再只是“会话开始读什么日志”,而是:

> **“用户这次要做什么?为了完成这个任务,我需要恢复哪些上下文?”**

Agent 根据用户一句自然语言(如“商务部报表同比计算有问题,修一下”)自动判断任务类型,再按类型**只加载最小必要上下文**,减少 AI 工作量与 token。

## 一、任务类型(AI 语义判断)

| 类型 | 触发场景 | 读取重点 | 明确不读 |
|---|---|---|---|
| `NEW_FEATURE` | 新功能/新模块/新接口/新能力 | Project Map、类似代码、类似 Plan(`docs/plans/`) | 不默认读大量近期 changelog |
| `BUG_FIX` | 已有功能错误(报错/计算错/重复消费/异常) | Changelog、Git、当前源码;必要时读历史 plan | 不读全量 project-map |
| `FEATURE_CHANGE` | 已有功能正常但业务需求变化 | 原始 Plan、Changelog/ Git、当前代码 → 对比 | — |

### 处理流程

**NEW_FEATURE**
```text
用户需求 → 识别 NEW_FEATURE → 读 project-map → 找类似代码/设计 → 完成需求设计 → (沉淀 feature-design-plan) → 开发
```

**BUG_FIX**
```text
用户需求 → 识别 BUG_FIX → 提取业务关键词 → 搜 changelog → 查相关 git commit → 定位当前代码
→ 必要时读历史 plan → 定位 Root Cause → 最小范围修复
```

**FEATURE_CHANGE**
```text
用户需求 → 识别 FEATURE_CHANGE → 找原始 Plan → 读相关 Changelog/Git → 查看当前代码
→ 对比: 旧设计 VS 当前实现 VS 新需求 → 得到 Design Delta → 必要时重新沉淀 Plan → 开发
```

## 二、读取策略(核心)

```text
按任务读取最小必要上下文
不要每次都全量读取开发日志和项目结构
```

由 AI 判断类型后调用低成本脚本(只 grep / 读文件,不做语义分析):

```bash
bash ~/.claude/skills/dev-task-context/scripts/route_context.sh NEW_FEATURE    [关键词]
bash ~/.claude/skills/dev-task-context/scripts/route_context.sh BUG_FIX       [关键词]
bash ~/.claude/skills/dev-task-context/scripts/route_context.sh FEATURE_CHANGE [关键词]
```

脚本输出“上下文包”后,最终定位由 AI 完成。

> 可选:install_hook.sh 仍可装 SessionStart 钩子在会话开始做轻量项目感知;但主入口是任务驱动的 `route_context.sh`。

## 三、历史资料可信度

冲突时按以下优先级:

```text
Current Source  >  Recent Changelog  >  Git History  >  Historical Plan
```

- Plan:当时想怎么做
- Changelog:后来实际改了什么
- Git:历史代码变化
- Current Source:现在真实是什么

**当前代码代表真实实现;Plan 仅用来理解设计意图。**

## 四、数据源(三件套闭环)

- `dev-changelog` → 写 `docs/change-log/`(commit 后)
- `project-map` → 维护 `docs/project-map.md`(项目脉络,全量+每小时增量)
- `dev-task-context`(本技能)→ 按任务路由读取以上 + `docs/plans/` + git

## 附带约定

写代码时遵循项目现有风格,并在方法/函数名后添加一行**中文注释**简要说明方法用途。

## 配置

见 `config.sh`(日志目录、Plan 目录、project-map 文件、文本上限 `DEV_TASK_CONTEXT_MAX_TEXT`)。

## 依赖

- 有 changelog / project-map 时读取更充分;缺失时会提示并无害跳过。
- 分类由 AI 完成;若仓库无任何资料,可回退到直接读当前代码 + git。
