---
name: commit-test-review
description: Commit 后测试审查。当 git commit 已完成、需要评估本次代码变更是否需要自动化测试/回归验证/生成测试记录时触发。分析最新 commit 的 diff,决策 NEED_TEST / SKIP_TEST / MANUAL_VERIFY;需要测试则优先复用已有测试、必要时新增测试并执行,最终生成 docs/test/ 测试记录;数据库密码只用 macOS Keychain,测试代码写入项目原有测试目录,绝不修改生产业务代码。
---

# Commit Test Review(Commit 自动化测试审查)

每次 `git commit` 完成后,评估本次代码变更是否有必要进行自动化测试。需要则编写/复用测试并执行、生成报告;无需则记录跳过原因;需人工验证则给建议。**无论结果如何,每个 commit 都必须生成测试记录。**

> 定位:`POST-COMMIT ASYNC QUALITY CHECK`(异步质量检查),**不是** `PRE-COMMIT QUALITY GATE`。任何失败都不得阻塞/回滚已成功的 commit。

与既有技能共同组成闭环:`dev-changelog`(写变更日志)→ `project-map`(脉络)→ `commit-test-review`(本技能,测试审查)。

## 触发方式

**方式一:全自动(git post-commit 钩子,推荐)**

```bash
# 在目标仓库根执行(本技能位于 <repo>/.claude/skills/commit-test-review/)
bash <repo>/.claude/skills/commit-test-review/scripts/install.sh
# 状态 / 卸载
bash <repo>/.claude/skills/commit-test-review/scripts/install.sh --status
bash <repo>/.claude/skills/commit-test-review/scripts/install.sh --remove
```

- `git commit` 成功后,钩子后台自动调用 `scripts/trigger.sh`,headless `claude -p` 加载本技能分析最新 commit。
- claude 未安装/登录失败/网络异常/测试失败 → 一律不影响 commit,只写本地日志。

**方式二:手动(会话内触发)**

当用户说"为这次 commit 做测试审查 / 检查这次改动要加测试吗 / 记录测试记录"时,Claude 直接:

1. `git rev-parse --show-toplevel` 定位仓库根;`git show --stat HEAD` 与 `git diff HEAD^ HEAD` 取 diff。
2. 按本技能规则做决策与测试。
3. 生成 `docs/test/` 记录。

## 测试决策(三选一)

只允许三种结果:**NEED_TEST / SKIP_TEST / MANUAL_VERIFY**。

### NEED_TEST
修改涉及实际业务行为时。典型:Service 业务逻辑、新增方法、改 `if/else`、`switch/状态判断`、数据计算、Mapper/SQL、Controller 接口/参数/返回、异常/权限/状态流转/事务/Redis/MQ、修 Bug、新增功能、数据写入、数据转换、核心工具方法。
例:`if (status == 1)` 改为 `if (status == 1 || status == 2)` → **NEED_TEST**。

### SKIP_TEST
未改变程序行为时。典型:只加/改注释、README/Markdown/docs、纯变量重命名但逻辑不变、格式化、import 整理、空行、日志文本、错别字。
例:`Long uid` → `Long userId`,后续逻辑完全不变 → **SKIP_TEST**。
*必须先搜索已有测试判断是否覆盖。

### MANUAL_VERIFY
影响程序但自动单测价值有限,更适合部署环境人工验证。典型:`application*.yml`、Nacos、Docker/`docker-compose`、Nginx、环境变量、启动/JVM 参数、部署配置。
例:改 Redis 地址 → **MANUAL_VERIFY**,给人工验证清单(连接成功/启动/功能/日志)。

## 测试代码原则

- **测试代码必须写入项目原有测试体系**(如 `src/test/java/`)。禁止创建独立测试目录如 `.ai-test/tests/`。测试代码属项目资产。
- **优先复用**:①搜索已有测试 → ②判断是否覆盖 → ③能复用则复用 → ④补充已有测试 → ⑤确实缺覆盖才新增。禁止制造重复测试(`GoalsServiceImplTest2` / `...CompleteTest` 之类)。

## 数据库设计(第一版:仅 MySQL)

- **Source Database**:多个,真实业务数据只读参考。强绑定:`forever 只读`(即使账号有写权限也不得写)。推荐账号仅 `SELECT`。禁止 `INSERT/UPDATE/DELETE/DROP/ALTER/CREATE/TRUNCATE`。
- **Test Database**:一个,专门供自动测试使用,可 `SELECT/INSERT/UPDATE/DELETE`,若涉 Schema 可 `CREATE/ALTER/DROP/TRUNCATE`。**必须为独立测试库,禁止生产库**。
- **数据流程**:Source 读必要真实数据 → 构造测试数据 → Test DB → 执行逻辑 → 验证。禁止直接在 Source 上写/改/删。
- **不是每个 NEED_TEST 都必须连库**。依赖库才读配置;纯计算(如 `calculateGrowthRate()`)直接单测,不因无库配置而无法测试。

## 密码管理(macOS Keychain)

- 只用 `/usr/bin/security`,service 固定 `ai-test`,account = 数据源 name(`sales`/`crm`/`test-db`)。
- 禁止明文 `password.yml` / `.env` / 提交 Git / 自造 AES。密码一律以交互输入,不 `--password=xxx`。
- 密码只在进程内建连;任何输出/报告/日志/终端只显示 `Password: configured`。

## 配置 CLI `ai-test`(唯一配置入口)

配置文件 `.ai-test/config.yml`(不含密码,可提交 Git);`.ai-test/logs/` 与 `runtime.lock` 进 `.gitignore`。**AI 辅助配置也必须走 CLI,禁止直接改 config.yml。**

> 统一入口:下面所有命令都通过 `ai-test`(即 `.claude/skills/commit-test-review/scripts/ai-test`)调用。
> 它会自动使用仓库 `.ai-test/venv/bin/python`(依赖装在里面),**无需** `source activate`。

```bash
python3 scripts/ai-test init            # 初始化:建 venv + 装 pymysql + 建 config
python3 scripts/ai-test env             # 仅确保 venv + pymysql 就绪
python3 scripts/ai-test db add-source           # 添加 Source DB
python3 scripts/ai-test db update-source <name> # 编辑 Source(留空保持原值)
python3 scripts/ai-test db remove-source <name> # 删除 Source(连同 Keychain 密码)
python3 scripts/ai-test db list                 # 绝不显示密码
python3 scripts/ai-test db test <name>          # 连库验证
python3 scripts/ai-test db set-test             # 配置 Test DB(需确认独立测试库)
python3 scripts/ai-test db update-test          # 编辑 Test(留空保持原值)
python3 scripts/ai-test db remove-test          # 删除 Test(连同 Keychain 密码)
python3 scripts/ai-test db test-test
```

可用 `ai-test init` 初始化;若把 `scripts` 目录加入 PATH,则可直接用 `ai-test ...`。

## 报告格式(`docs/test/YYYY/MM/DD/HH-mm-<变更简述>.md`)

文件名 `HH-mm-简述` 由 AI 依 diff 总结,如 `09-32-修改任务完成状态校验.md`。

**NEED_TEST 报告**顶部第一时间显示结果:
```md
# 测试报告
> ✅ Passed: 7
> ❌ Failed: 2
> ⚪ Skipped: 0
> 总计: 9
> 最终状态: FAILED

## Commit 信息  (Commit / Branch / Commit Message / 测试时间)
## 本次变更
## 测试判断  (NEED_TEST + 原因)
## 测试范围
## 测试用例  (复用 / 新增)
## 测试数据  (Source 只读来源 / Test 库;禁止密码/敏感连接串/Keychain)
## 测试执行  (项目实际测试命令,依技术栈 mvn/jest/go test 等)
## 测试结果  (Tests Run / Passed / Failed / Skipped)
## 失败详情  (每个失败单独记录:测试类/目标代码/预期/实际/错误/初步分析/建议;不改业务代码)
```

**SKIP_TEST 报告**:
```md
# 测试记录
> ⚪ 测试状态: SKIPPED
## Commit 信息
## 本次变更
## 测试判断  == SKIP_TEST
## 原因      (未改条件判断/数据访问/返回/调用/异常/流程)
## 结论      无需自动测试
```

**MANUAL_VERIFY 报告**:
```md
# 测试记录
> 🟡 测试状态: MANUAL_VERIFY
## 本次变更
## 测试判断  == MANUAL_VERIFY
## 原因
## 建议人工验证
## 不为此强行生成单测
```

## 失败处理(第一版)

测试失败 → 记录失败 → 生成完整报告 → **结束**。不自动改业务代码、不自动重新 commit、不自动再测、不发邮件。开发查看报告后人工处理。

## 安全硬规则

```text
Source DB        只读,禁止任何主动写
Test DB          必须独立测试库
Password       只存 macOS Keychain
Report         禁止出现密码
Logs           禁止打印密码
Shell          禁止 --password=xxx
Product Code   禁止为让测试通过改业务代码
```

## 首次运行检查

准备执行测试前检查:`git 仓库` → `有 commit` → `.ai-test/config.yml` → `macOS` → `security` → 需要库时 Source/Test 存在 → Keychain 凭据 → 可连接 → 测试框架可识别。未初始化 → 提示 `ai-test init`。

## 配置

见 `config.sh`(`COMMIT_TEST_REVIEW_ENABLED`、`CRT_REPORT_DIR`、`CRT_CLAUDE_TIMEOUT`、`CRT_MAX_DIFF` 等)。

## 依赖 / 技术栈探测

- 测试命令依项目技术栈自动决定:Maven `./mvnw ... test`、Gradle `./gradlew test`、Node `npm/yarn test`、Go `go test` 等。
- 数据库连接测试依赖 `pymysql`,已由 `ai-test init`/`env` 装入项目 venv(`.ai-test/venv/`)。统一入口 `ai-test` 默认用该 venv,无需手动激活。
