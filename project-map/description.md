# Project Map(项目脉络分析)

充分阅读整个项目、梳理层级与整体脉络,一次性生成文档 `docs/project-map.md`(项目概览/目录层级/分层模块/核心链路/变更时间线)。此后每小时由系统 crontab 自动做增量更新:只针对 `docs/change-log/` 增量新增的开发日志所涉及的变更文件做增量分析并追加写回,既减少 AI 工作复杂度又省 token。记录上次更新时间,便于下次增量。与 dev-changelog(写)、dev-log-context(读)构成项目三件套。
