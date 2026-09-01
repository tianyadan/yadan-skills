# Commit Test Review(Commit 自动化测试审查)

每次 `git commit` 完成后,评估本次变更是否需要自动化测试。本技能定义规则,`ai-test` CLI 管数据库配置,post-commit 钩子触发,headless `claude -p` 负责真正思考、编写/复用测试、执行测试、生成报告。

## 角色与定位

`POST-COMMIT ASYNC QUALITY CHECK`,不是 `PRE-COMMIT QUALITY GATE`。任何失败都不阻塞/回滚 commit。

```text
Git Commit → post-commit 钩子 → 检测 claude → 加运行锁(runtime.lock)
  → claude -p <固定任务说明> → 加载本 Skill → 决策(三选一)
  → 必要时写/复用测试并执行 → 生成 docs/test 测试记录
```

三种决策:
- **NEED_TEST** —— 改了业务行为(逻辑/条件/SQL/接口/Bug/新功能/异常/权限/事务/计算)。
- **SKIP_TEST** —— 未改行为(注释/文档/纯重命名/格式化/日志)。
- **MANUAL_VERIFY** —— 改运行/部署配置(yml/Nacos/Docker/Nginx/env/启动参数)。

## 安装(在目标仓库根执行)

> **统一入口:** 所有命令都通过 `scripts/ai-test` 这个 wrapper 调用。它自动判断：
> 存在 `.ai-test/venv/bin/python` → 用它(自带 pymysql)；不存在 → 退回系统 python3(init/env 会建 venv)。
> **无需** `source venv/bin/activate`，Git hook / Claude headless / 后台 / CI 都直接可用。

```bash
# 步骤1:安装 post-commit 钩子(每个 commit 后自动触发)
bash <repo>/.claude/skills/commit-test-review/scripts/install.sh

# 步骤1b(推荐):一键装钩子 + init(建 venv、装 pymysql、建 config、建 docs/test)
bash <repo>/.claude/skills/commit-test-review/scripts/install.sh --init

# 查看 / 卸载
bash <repo>/.claude/skills/commit-test-review/scripts/install.sh --status
bash <repo>/.claude/skills/commit-test-review/scripts/install.sh --remove

# 步骤2:初始化(建 .ai-test/venv + 装 pymysql + 建 config + docs/test)
python3 <repo>/.claude/skills/commit-test-review/scripts/ai-test init
```

## 配置数据库(密码只进 macOS Keychain)

下面用 `ai-test` 代表 wrapper(即 `python3 .../scripts/ai-test`,或把 `scripts` 加进 PATH 后直接用 `ai-test`)：

```bash
ai-test db add-source            # 新增 Source DB(只读,建议仅 SELECT)
ai-test db update-source <name>  # 编辑 Source(留空保持原值,可改名/改密码)
ai-test db remove-source <name>  # 删除 Source(连同 Keychain 密码)
ai-test db set-test              # 配置 Test DB(必须独立测试库)
ai-test db update-test           # 编辑 Test(留空保持原值)
ai-test db remove-test           # 删除 Test(连同 Keychain 密码)
ai-test db list                 # 查看(绝不显示密码)
ai-test db test <name>          # 连库验证
```

- Source 支持多个；Test 只有一个(专供自动化测试的独立库)。
- 编辑/删除均有交互提示:编辑字段留空保持原值,密码留空不修改;删除需输入 `y` 确认。
- service=`ai-test`,account=数据源 name。密码交互输入,不回显,只在进程内建连。
- 依赖装在项目 venv(`.ai-test/venv/`),不入库;`.ai-test/config.yml` 含连接地址/用户名(内部敏感),建议也不入库,仅提交 `config.yml.example`。
- 真实连库测试需要 pymysql:`ai-test init` / `ai-test env` 会自动装进 venv。

## 测试代码

- 写进项目原有测试目录(如 `src/test/java/`),禁止建独立测试目录。
- 复用优先:搜已有测试 → 判覆盖 → 复用 → 补充 → 缺才新增。
- 禁止自动修改业务代码;测试失败只记录并交人工。

## 报告位置

`docs/test/YYYY/MM/DD/HH-mm-<变更简述>.md`。NEED_TEST 顶部显示 `✅ Passed / ❌ Failed / ⚪ Skipped / 最终状态`。

## 目录结构

```text
<repo>/.claude/skills/commit-test-review/
├── SKILL.md         规则主体
├── description.md  描述
├── config.sh       配置
├── README.md       本文件
└── scripts/
    ├── ai-test       统一入口 wrapper(自动用 .ai-test/venv/bin/python;所有调用都走它)
    ├── ai-test.py    数据库配置 CLI(标准库)
    ├── yamlmini.py   迷你 YAML(标准库)
    ├── keychain.py   macOS Keychain 封装
    ├── trigger.sh    post-commit 触发(锁+claude)
    ├── post-commit.sh 钩子模板(占位符)
    └── install.sh    安装/卸载钩子
<repo>/.ai-test/          不入库(见其 .gitignore)
├── venv/            项目虚拟环境(装 pymysql),不入库
├── config.yml       连接配置(含地址/用户名,建议不入库)
└── logs/ runtime.lock
```

## 安全硬规则

Source 只读 · Test 独立库 · 密码只进 Keychain · 报告/日志/终端不出现密码 · 禁止 `--password=xxx` · 禁止为让测试通过改 `src/main`。
