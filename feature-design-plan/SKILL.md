---
name: feature-design-plan
description: 把“已经讨论清楚的新需求或较大功能变更”沉淀成一份可执行的开发设计文档。输入来自已确定的 NEW_FEATURE / 已完成 Design Delta 的较大 FEATURE_CHANGE;以固定路径 docs/plan/YYYY-MM-DD-中文功能简介.md 写入,固定 7 块结构(背景/目标/范围/技术设计/变更影响/开发TODO/待确认)。当用户说“沉淀方案”“写开发计划”“生成Plan/TODO”“先设计再开发”“写设计文档”等指令时触发。
---

# Feature Design Plan(开发设计文档沉淀)

只负责把「**已讨论清楚的新需求 / 较大功能变更**」沉淀成**可执行的开发设计文档**,作为未来开发 Agent 的执行入口。

> 目的不是为了"写一篇漂亮文档",而是给后续开发 Agent 提供**执行入口**与设计意图记录。

## 固定路径与命名(以后不再问)

```
<仓库根>/docs/plan/YYYY-MM-DD-中文功能简介.md
```

例:`docs/plan/2026-08-29-业务层级重构.md`

```
# 简化: bash write_plan.sh "业务层级重构"
# 查看已有: bash write_plan.sh --list
```

## 固定 7 块结构(正文照此撰写)

```md
## 1. 背景
(为什么做: 要解决的问题或需求)

## 2. 开发目标
(最终要实现什么)

## 3. 实现范围
- 本次实现: ...
- 本次暂不实现: ...

## 4. 技术设计
- 涉及模块 / 接口 / 数据表 / 核心流程 / 关键规则: ...

## 5. 变更影响
(影响哪些已有模块/接口/数据结构)
# FEATURE_CHANGE 必须记录 原设计 vs 新设计 差异:

## 6. 开发 TODO
- [ ] ...

## 7. 待确认事项
- [ ] ...
```

## 核心流程(5 步)

```text
① 当前需求 + 已恢复上下文
② 提取已经确认的设计结论
③ 区分: 已确认 / 待确认 / 暂不实现
④ 拆成可执行 TODO
⑤ 写入 docs/plan/YYYY-MM-DD-中文功能简介.md
```

## 触发规则(只在"设计已基本确定、准备编码"时触发)

### 触发
1. **用户明确要求**: 沉淀方案 / 写开发计划 / 生成 Plan、TODO / 先设计再开发。
2. **NEW_FEATURE**: 需求、接口、数据、流程已基本明确,用户认可方案,编码前生成 Plan。
3. **FEATURE_CHANGE**: 原功能发生明显设计变化,已完成 旧设计/当前实现/新需求 对比(Design Delta),需要更新设计后再开发。

### 不触发
- **BUG_FIX 默认不触发**,直接:`恢复上下文 → 定位 Root Cause → 修复 → 验证 → dev-changelog`。
- **小型 FEATURE_CHANGE 也不触发**: 加字段、改校验、改 SQL 条件、改配置 → 直接开发。

### 判断标准(只判断一件事)
> 这次修改是否产生了**值得后续 AI 再次读取的设计决策**?
> 是 → feature-design-plan; 否 → 直接开发。

### 调用顺序
```text
用户需求 → dev-task-context → 恢复上下文 → 完成设计 → feature-design-plan → 开始编码
```

## FEATURE_CHANGE 关键点

**新 Plan 不能把旧设计完全覆盖掉** —— 必须记录变更差异:

```md
## 5. 变更影响
原设计:   region → district
新设计:   businessUnit → region → district
影响:     - SQL 分组
          - Response VO
          - Excel 表头
          - 汇总逻辑
          - 前端层级展示
```

这样未来 Agent 才知道"为什么现在代码和旧版本不一样"。

## 生成方式

AI 判断满足触发条件后:

```bash
# 1. 生成固定路径骨架(不覆盖已有)
FILE=$(bash ~/.claude/skills/feature-design-plan/scripts/write_plan.sh "中文功能简介")

# 2. 用上面 7 块结构填充正文(Write),记录 变更影响/TODO/待确认
```

关联: `dev-task-context` 负责"按任务路由读上下文";`feature-design-plan` 负责"写设计文档"。完成后按 TODO 开发,再走 `dev-changelog` 记录。
