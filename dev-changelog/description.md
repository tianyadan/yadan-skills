# Dev Changelog

全自动开发变更台账:每次 git commit 后在后台把 diff 交给 Claude,生成结构化 Markdown 写入当前项目仓库 `docs/change-log/YYYY/MM/DD/<时间戳>_<uuid>.md`,含需求背景、变更文件(basename)、实现功能/修复 Bug。支持 git 钩子全自动或会话内手动触发,同 diff 自动去重。
