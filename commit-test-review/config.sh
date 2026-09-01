#!/usr/bin/env bash
# commit-test-review 配置
# 此文件会被 trigger.sh / install.sh 读取,可在此调整行为。

# 总开关:1 = 启用,0 = 关闭
export COMMIT_TEST_REVIEW_ENABLED="${COMMIT_TEST_REVIEW_ENABLED:-1}"

# 测试报告目录(相对仓库根)
export CRT_REPORT_DIR="${CRT_REPORT_DIR:-docs/test}"

# ai-test CLI 主脚本(相对本 skill scripts/)
export CRT_AITEST_CLI="ai-test.py"

# 调用 headless claude 的超时时间(秒);无 timeout/gtimeout 时忽略
export CRT_CLAUDE_TIMEOUT="${CRT_CLAUDE_TIMEOUT:-180}"

# 传 diff 给 claude 的最大字符数(避免参数过长)
export CRT_MAX_DIFF="${CRT_MAX_DIFF:-60000}"

# runtime 锁文件名(相对仓库根的 .ai-test/)
export CRT_LOCK_NAME="runtime.lock"

# 本地运行日志(相对仓库根的 .ai-test/logs/)
export CRT_LOG_NAME="commit-test-review.log"
