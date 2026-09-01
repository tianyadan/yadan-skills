# Commit Test Review(Commit 自动化测试审查)

每次 `git commit` 完成后评估本次变更是否需要自动化测试。决策 **NEED_TEST / SKIP_TEST / MANUAL_VERIFY**:需要则优先复用已有测试、必要时为本次变更新增测试并执行,生成测试报告;无需则记录跳过原因;需人工验证则给人工验证清单。**无论结果如何,每个 commit 都在 `docs/test/YYYY/MM/DD/HH-mm-简述.md` 留下测试记录。** 数据库密码只用 macOS Keychain(/usr/bin/security),配置唯一入口为 `ai-test` CLI(Source 永远只读,Test 必须独立测试库),测试代码写入项目原有测试目录,绝不修改生产业务代码。通常由 git post-commit 钩子(`scripts/install.sh`)后台自动触发,headless `claude -p` 加载本技能;claude 缺失/失败不阻塞 commit(异步质量检查,非质量门禁)。
