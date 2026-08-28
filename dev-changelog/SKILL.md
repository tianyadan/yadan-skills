---
name: dev-changelog
description: 记录 AI 开发变更台账。当用户说“记录本次变更”“记录这次开发”“记录本次改动”“写入 change-log”“记录 changelog”“同步开发记录”等指令时触发。将最近一次 git 变更(commit 或工作区改动)结构化记录到当前项目仓库的 docs/change-log/YYYY/MM/DD/<时间戳>_<uuid>.md。也可用于解释 / 安装该技能的全自动 git post-commit 钩子。
---

# Dev Changelog(全自动开发变更台账)

记录 AI 变更并写入**当前项目仓库**的 `docs/change-log/`,便于追溯"这次改了什么需求、哪些文件、实现了什么或修了什么 bug"。支持两种模式:

## 模式一:全自动(git 钩子,推荐)

改造结束后无需手动触发。每次 `git commit` 成功后,钩子后台自动调用 `scripts/record_change.sh`:

- 读取最近一次 commit 的 `git diff`
- 交给 headless `claude -p`(自动走用户代理 + 内部模型,免费)
- 生成结构化 Markdown,写入 `<仓库根>/docs/change-log/YYYY/MM/DD/<HHMMSS>_<uuid8>.md`
- 同一 diff 按 sha256 去重,不重复写

### 安装到当前项目

```bash
bash ~/.claude/skills/dev-changelog/scripts/install_hook.sh
```

卸载:

```bash
bash ~/.claude/skills/dev-changelog/scripts/install_hook.sh --remove
```

> 说明:git 钩子不能跨仓库共享,每个项目需各执行一次安装。记录内容随仓库 git 版本控制(需求背景保存在 `docs/change-log/`)。

## 模式二:手动(会话内触发)

当用户说"记录本次变更 / 记录这次开发"等时,Claude 直接执行:

1. 跑 `git rev-parse --show-toplevel` 定位仓库根;跑 `git status --short` 与 `git diff --stat` 确认最近改动。
2. 计算目标路径 `docs/change-log/YYYY/MM/DD/<HHMMSS>_<uuid8>.md`(用 `date` 与 `uuidgen`)。
3. 用 `Write` 写入结构化文档(下述模板)。
4. 向用户汇报文件路径。

### 文档模板

```md
# 变更记录

> 提交: <commit message>
> 作者: <user name>
> 日期: <YYYY-MM-DD HH:MM:SS>

## 需求背景
<这次改动要解决的问题或需求>

## 变更文件
- <文件名1 basename>
- <文件名2 basename>

## 实现功能 / 修复 Bug
- <实现了什么功能,或修复了什么 bug>

## 备注
<可选的注意事项/风险>
```

## 约定

- 变更文件只记 **basename**(不含完整路径)。
- 每个 commit/变更 = 一个独立 Markdown 文件(UUID 保证唯一)。
- 配置可在 `config.sh` 调整(开关、语种、diff 上限等)。
