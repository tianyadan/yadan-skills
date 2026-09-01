#!/usr/bin/env bash
# commit-test-review / post-commit.sh
# git post-commit 钩子模板:由 install.sh 复制到 <仓库>/.git/hooks/post-commit
# 每次 git commit 成功后,后台调用 trigger.sh 触发 commit-test-review。
# 后台运行 + 静默失败:绝不阻塞 / 回滚 / 拖慢正常 commit。

SKILL_SCRIPTS="__SKILL_SCRIPTS__"   # install.sh 会替换为实际路径

# 检测 claude 不存在时不启动(真正判断在 trigger.sh 内),直接放行
nohup bash "$SKILL_SCRIPTS/trigger.sh" >/dev/null 2>&1 &
true
