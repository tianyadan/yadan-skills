# Dev Log Context

会话前自动加载项目近期开发日志:让 AI 每次会话开始时,先读取近 7 天(或最近 10 条)的开发变更记录,快速了解项目需求方向、近期改动文件与代码风格,再开始任务。数据来源与 dev-changelog 一致(各仓库 `docs/change-log/`)。支持 Claude Code SessionStart 钩子全自动加载,也可手动运行 `load_context.sh`。附带约定:写代码时遵循项目现有风格,并在方法名后加中文注释说明用途。
