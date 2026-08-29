# Dev Task Context(开发 Agent 的 Context Router)

识别用户任务类型(NEW_FEATURE 新功能 / BUG_FIX 修 bug / FEATURE_CHANGE 改需求),并按最小必要上下文自动加载。由 AI 语义判断类型后运行 `route_context.sh` 低成本抽取 project-map / change-log / git / docs/plans,不无差别全量读取,省 token。资料可信度:当前源码 > Changelog > Git 历史 > 历史 Plan。与 dev-changelog(写)、project-map(脉络)构成闭环。
