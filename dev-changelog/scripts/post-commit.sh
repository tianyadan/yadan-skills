#!/usr/bin/env bash
# dev-changelog / post-commit.sh
# git post-commit 钩子模板:由 install_hook.sh 复制到 <仓库>/.git/hooks/post-commit
# 每次 git commit 成功后,调用 record_change.sh 自动写入变更文档。
# 后台运行 + 静默失败:绝不阻塞/报错影响正常 commit。

SKILL_SCRIPTS="__SKILL_SCRIPTS__"   # install_hook.sh 会替换为实际路径

# 后台运行,避免拖慢 commit;输出丢弃,避免污染终端
nohup bash "$SKILL_SCRIPTS/record_change.sh" >/dev/null 2>&1 &
true
