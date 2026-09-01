#!/usr/bin/env bash
# commit-test-review post-commit 片段模板:由 install.sh 合并进 .git/hooks/post-commit。
# 只包含本技能的可合并片段(用 MARKER_BEGIN/END 标记整块),可与其他技能片段共存,
# 互不覆盖。后台运行 + 静默失败:绝不阻塞 / 回滚 / 拖慢正常 commit。

# MARKER_BEGIN commit-test-review
[ -x "__SKILL_SCRIPTS__/trigger.sh" ] && nohup bash "__SKILL_SCRIPTS__/trigger.sh" >/dev/null 2>&1 &
# MARKER_END commit-test-review
