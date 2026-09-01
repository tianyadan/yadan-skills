#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
commit-test-review / ai-test
统一数据库配置 CLI(dp.password / Keychain 唯一入口)。

用法:
  ai-test init                       # 初始化:建 venv + 装 pymysql + 建 config
  ai-test env                        # 仅确保 venv 存在且装有 pymysql
  ai-test db add-source
  ai-test db update-source <name>   # 编辑 source(留空保持原值)
  ai-test db remove-source <name>   # 删除 source
  ai-test db list
  ai-test db test <name>
  ai-test db set-test               # 配置 test
  ai-test db update-test            # 编辑 test(留空保持原值)
  ai-test db remove-test            # 删除 test
  ai-test db test-test
  ai-test diag

规则(见 SKILL.md):
- Source Database:只读(权限应仅 SELECT)。
- Test Database:必须为独立测试数据库。
- 密码只存 macOS Keychain;config.yml 不含密码。
- CLI 是修改 .ai-test/config.yml 的唯一合法入口。

依赖:仅标准库。pymysql(可选用 venv 安装)存在时可做真实连接测试;缺失则降级为"配置 + Keychain 校验"。
统一入口:请用同目录 wrapper 脚本 `ai-test`(自动使用 .ai-test/venv/bin/python);venv 不存在时 init/env 会自动创建。
"""

from __future__ import annotations

import getpass
import os
import shutil
import subprocess
import sys

import keychain  # 同目录模块

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)
import yamlmini  # noqa: E402

SERVICE = "ai-test"


def repo_root():
    """定位当前 git 仓库根;非 git 则用当前目录。返回 (root, is_git)。"""
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=False,
        ).stdout.decode().strip()
        if out:
            return out, True
    except FileNotFoundError:
        pass
    return os.getcwd(), False


AITEST_DIR = ".ai-test"
CONFIG_FILE = os.path.join(AITEST_DIR, "config.yml")
GITIGNORE = os.path.join(AITEST_DIR, ".gitignore")
REPORT_DIR_DEFAULT = "docs/test"
VENV_DIR = os.path.join(AITEST_DIR, "venv")


def sys_exec_prefix():
    """当前 Python 的 sys.prefix(标准库也能读,无需 import sys 之外)。"""
    return os.path.dirname(os.path.dirname(os.path.abspath(sys.executable)))


def venv_python(root):
    """返回仓库 .ai-test/venv/bin/python 路径,不存在则为 None。"""
    if os.name == "nt":
        p = os.path.join(root, VENV_DIR, "Scripts", "python.exe")
    else:
        p = os.path.join(root, VENV_DIR, "bin", "python")
    return p if os.path.isfile(p) else None


def running_in_venv():
    return hasattr(sys, "real_prefix") or (getattr(sys, "base_prefix", sys.prefix) != sys.prefix)


def ensure_venv(root, quiet=False):
    """若仓库 venv 缺失则创建,返回 venv python 路径;已存在直接返回。"""
    vp = venv_python(root)
    if vp:
        return vp
    if not quiet:
        print("  .ai-test/venv 不存在 → 创建虚拟环境")
    py = sys.executable
    subprocess.run([py, "-m", "venv", os.path.join(root, VENV_DIR)], check=True)
    vp2 = venv_python(root)
    if not vp2:
        print("创建 venv 失败: 未找到 venv python", file=sys.stderr)
        sys.exit(1)
    return vp2


def pip_install(venv_py, *pkgs):
    """在指定 python 的虚拟环境(或用户级)中安装包。"""
    subprocess.run([venv_py, "-m", "pip", "install", "-U", "pip"], check=False)
    return subprocess.run([venv_py, "-m", "pip", "install", *pkgs], check=False).returncode == 0


def reexec_in_venv(root):
    """argparse/web 无关:若当前未运行在仓库 venv 且仓库 venv 已存在,则用它重跑自身。"""
    vp = venv_python(root)
    if vp and not running_in_venv():
        os.execv(vp, [vp, os.path.abspath(__file__)] + sys.argv[1:])


def load_config(root):
    cfg_path = os.path.join(root, CONFIG_FILE)
    if not os.path.isfile(cfg_path):
        return {
            "version": 1,
            "database": {"sources": [], "test": {}},
            "test": {"report-dir": REPORT_DIR_DEFAULT},
        }, {}
    with open(cfg_path, "r", encoding="utf-8") as f:
        data = yamlmini.load(f.read())
    data.setdefault("database", {})
    data["database"].setdefault("sources", [])
    data["database"].setdefault("test", {})
    data.setdefault("test", {})
    data["test"].setdefault("report-dir", REPORT_DIR_DEFAULT)
    return data, cfg_path


def save_config(root, data):
    cfg_path = os.path.join(root, CONFIG_FILE)
    with open(cfg_path, "w", encoding="utf-8") as f:
        f.write(yamlmini.dump(data))
        f.write("\n")


def _q(prompt, default=""):
    if default:
        return input(f"{prompt} [{default}]: ").strip() or default
    return input(f"{prompt}: ").strip()


def _q_secret(prompt):
    return getpass.getpass(f"{prompt}: ")


def _test_connection(entry, password):
    """pymysql 可用时真实连接;否则降级校验。返回 (ok, msg)。"""
    if not password:
        return False, "Keychain 中无密码"
    try:
        import pymysql  # 可选依赖
    except ImportError:
        # 降级:只做配置完整性校验
        missing = [k for k in ("host", "port", "database", "username") if not entry.get(k)]
        if missing:
            return False, f"缺少配置字段: {', '.join(missing)};且未安装 pymysql,无法真正连库"
        return True, "配置完整;未安装 pymysql,跳过真实连接(可选: pip install pymysql)"
    try:
        conn = pymysql.connect(
            host=entry.get("host"),
            port=int(entry.get("port") or 0),
            user=entry.get("username"),
            password=password,
            database=entry.get("database"),
            connect_timeout=6,
        )
        conn.close()
        return True, "Connection successful."
    except Exception as e:  # noqa: BLE001
        return False, f"Connection failed: {e}"


def _ask_db_fields(existing=None):
    existing = existing or {}
    entry = {}
    entry["name"] = _q("Database name", existing.get("name", ""))
    entry["type"] = _q("Database type", existing.get("type", "mysql"))
    entry["host"] = _q("Host", existing.get("host", ""))
    entry["port"] = existing.get("port", 3306)
    p = _q("Port", str(entry["port"] or 3306))
    try:
        entry["port"] = int(p)
    except ValueError:
        entry["port"] = 3306
    entry["database"] = _q("Database", existing.get("database", ""))
    entry["username"] = _q("Username", existing.get("username", ""))
    return entry


def cmd_add_source(root, cfg, cfg_path):
    print("添加 Source Database(真实业务数据,只读参考)。")
    entry = _ask_db_fields()
    name = entry["name"]
    sources = cfg["database"]["sources"]
    if any(s.get("name") == name for s in sources):
        print(f"已存在同名 source「{name}」,请用 ai-test db update-source {name} 修改。")
        sys.exit(1)
    print("Password 将保存到 macOS Keychain(不回显)。")
    pw = _q_secret("Password")
    ok, kmsg = keychain.set_password(name, pw, update=False)
    if not ok:
        print(f"Keychain 写入失败: {kmsg}")
        sys.exit(1)
    print("Testing connection...")
    good, cmsg = _test_connection(entry, pw)
    entry.setdefault("keychain-service", SERVICE)
    entry.setdefault("keychain-account", name)
    sources.append(entry)
    save_config(root, cfg)
    print(f"{cmsg}")
    if good:
        print(f'Source database "{name}" configured successfully.')
    print("(Source Database 仅作只读参考;请使用独立只读账号,权限建议仅 SELECT)")


def cmd_update_source(root, cfg, cfg_path, name):
    sources = cfg["database"]["sources"]
    entry = next((s for s in sources if s.get("name") == name), None)
    if not entry:
        print(f"未找到 source「{name}」。可用: {[s.get('name') for s in sources]}")
        sys.exit(1)
    print(f"更新 source「{name}」(留空保持原值)。")
    new = _ask_db_fields(entry)
    entry.update({k: v for k, v in new.items() if v})
    if new.get("name") and new["name"] != name:
        # 改名
        old_name = name
        entry["name"] = new["name"]
        entry["keychain-account"] = new["name"]
    pw = _q_secret("新密码(留空则不修改密码)")
    if pw:
        ok, kmsg = keychain.set_password(entry["name"], pw, update=True)
        if not ok:
            print(f"Keychain 更新失败: {kmsg}")
            sys.exit(1)
        good, cmsg = _test_connection(entry, pw)
        print(cmsg)
    save_config(root, cfg)
    print(f'Source database "{entry["name"]}" updated.')
    print("(密码已更新到 Keychain,配置文件中不含明文)")


def cmd_remove_source(root, cfg, cfg_path, name):
    sources = cfg["database"]["sources"]
    before = len(sources)
    cfg["database"]["sources"] = [s for s in sources if s.get("name") != name]
    if len(cfg["database"]["sources"]) == before:
        print(f"未找到 source「{name}」。")
        sys.exit(1)
    keychain.delete_password(name)
    save_config(root, cfg)
    print(f'已移除 source「{name}」及其 Keychain 密码。')


def cmd_list(root, cfg):
    sources = cfg["database"]["sources"]
    test = cfg["database"]["test"]
    print("SOURCE DATABASES")
    print(f"{'NAME':<12}{'TYPE':<8}{'DATABASE':<16}{'USER':<16}{'STATUS'}")
    if not sources:
        print("(无)")
    for s in sources:
        name = str(s.get("name", ""))
        acct = str(s.get("keychain-account", name))
        status = "OK" if keychain.has_password(acct) else "NO_CRED"
        print(f"{name:<12}{str(s.get('type','')):<8}{str(s.get('database','')):<16}{str(s.get('username','')):<16}{status}")
    print()
    print("TEST DATABASE")
    print(f"{'NAME':<12}{'TYPE':<8}{'DATABASE':<16}{'USER':<16}{'STATUS'}")
    if test.get("name"):
        tname = str(test.get("name", ""))
        acct = str(test.get("keychain-account", tname))
        status = "OK" if keychain.has_password(acct) else "NO_CRED"
        print(f"{tname:<12}{str(test.get('type','')):<8}{str(test.get('database','')):<16}{str(test.get('username','')):<16}{status}")
    else:
        print("(未配置)")
    print("\n(密码一律不显示;如需验证连接: ai-test db test <name>)")


def cmd_test(root, cfg, name):
    sources = cfg["database"]["sources"]
    entry = next((s for s in sources if s.get("name") == name), None)
    if not entry:
        if cfg["database"]["test"].get("name") == name:
            entry = cfg["database"]["test"]
        else:
            print(f"未找到数据库「{name}」。")
            sys.exit(1)
    pw = keychain.get_password(str(entry.get("keychain-account", name)))
    good, cmsg = _test_connection(entry, pw)
    print(cmsg)
    sys.exit(0 if good else 1)


def cmd_set_test(root, cfg, cfg_path):
    print("配置 Test Database(用于自动化测试的独立数据库)。")
    test = cfg["database"]["test"]
    entry = _ask_db_fields(test)
    print()
    print("=" * 62)
    print("WARNING")
    print()
    print("This database will be used for automated tests.")
    print("Automated tests may perform:")
    print("  INSERT  UPDATE  DELETE")
    print("  CREATE  ALTER    DROP   TRUNCATE")
    print()
    print("Do NOT use a production database.")
    print("Confirm this is a dedicated test database.")
    print("=" * 62)
    ans = input("\n这是专用测试数据库,确认继续? [y/N]: ").strip().lower()
    if ans not in ("y", "yes"):
        print("已取消。")
        sys.exit(1)
    pw = _q_secret("Password")
    ok, kmsg = keychain.set_password(entry["name"], pw, update=True)
    if not ok:
        print(f"Keychain 写入失败: {kmsg}")
        sys.exit(1)
    good, cmsg = _test_connection(entry, pw)
    print(cmsg)
    if good:
        entry.setdefault("keychain-service", SERVICE)
        entry.setdefault("keychain-account", entry["name"])
        cfg["database"]["test"] = entry
        save_config(root, cfg)
        print(f'Test Database "{entry["name"]}" configured.')


def cmd_update_test(root, cfg, cfg_path):
    test = cfg["database"]["test"]
    if not test.get("name"):
        print("尚未配置 Test Database,请先运行 ai-test db set-test")
        sys.exit(1)
    print(f"更新 Test Database「{test.get('name')}」。留空保持原值。")
    new = _ask_db_fields(test)
    old_name = test.get("name")
    test.update({k: v for k, v in new.items() if v})
    if new.get("name") and new["name"] != old_name:
        test["keychain-account"] = test["name"]
    pw = _q_secret("新密码(留空则不修改)")
    if pw:
        keychain.set_password(test["name"], pw, update=True)
    good, cmsg = _test_connection(test, pw)
    print(cmsg)
    save_config(root, cfg)
    print("Test Database updated.")


def cmd_remove_test(root, cfg, cfg_path):
    test = cfg["database"]["test"]
    if not test.get("name"):
        print("尚未配置 Test Database,无需删除。")
        sys.exit(1)
    name = test["name"]
    print(f"将删除 Test Database「{name}」及其 Keychain 密码。")
    ans = input("确认删除? [y/N]: ").strip().lower()
    if ans not in ("y", "yes"):
        print("已取消。")
        sys.exit(1)
    keychain.delete_password(name)
    cfg["database"]["test"] = {}
    save_config(root, cfg)
    print(f'已删除 Test Database「{name}」及其 Keychain 密码。')


def cmd_env(root):
    """确保项目 venv 存在且装有 pymysql(数据库连接驱动)。"""
    vp = ensure_venv(root)
    # 建好 venv 后切到 venv python 重跑,保证后续 import/验证都在 venv 内
    if not running_in_venv():
        os.execv(vp, [vp, os.path.abspath(__file__)] + ["env"])
    print("检查 ai-test Python 环境...")
    print(f"  使用 venv: {vp}")
    try:
        import pymysql  # noqa: F401
        print("  依赖检查... pymysql", getattr(pymysql, "__version__", "已安装"))
        return
    except ImportError:
        pass
    print("  依赖检查... pymysql 未安装 → 安装 pymysql")
    if pip_install(vp, "pymysql"):
        import pymysql  # noqa: F401
        print("  验证 PyMySQL... ✔ pymysql", getattr(pymysql, "__version__", "已安装"))
    else:
        print("  自动安装失败。请手动执行: {} -m pip install pymysql".format(vp), file=sys.stderr)
        sys.exit(1)


def cmd_init(root, is_git):
    if not is_git:
        print("Warning: 当前不是 git 仓库,仍会初始化 .ai-test/ 与 docs/test/。")
    os.makedirs(os.path.join(root, AITEST_DIR, "logs"), exist_ok=True)
    cfg_path = os.path.join(root, CONFIG_FILE)
    if not os.path.isfile(cfg_path):
        data = {
            "version": 1,
            "database": {"sources": [], "test": {}},
            "test": {"report-dir": REPORT_DIR_DEFAULT},
        }
        save_config(root, data)
    if not os.path.isfile(os.path.join(root, GITIGNORE)):
        with open(os.path.join(root, GITIGNORE), "w", encoding="utf-8") as f:
            f.write("# ai-test 本地运行信息(不入库)\nlogs/\nruntime.lock\nvenv/\n")
    os.makedirs(os.path.join(root, REPORT_DIR_DEFAULT), exist_ok=True)
    # 检查环境
    print("检查 macOS Keychain...")
    ok, msg = keychain.test_keychain()
    print(("  ✔ " if ok else "  ✘ ") + msg)
    claude = shutil.which("claude")
    print("检查 claude CLI...", "✔ " + claude if claude else "✘ 未安装")
    print("检查 Python...", f"✔ {sys.version.split()[0]}")
    # 建 venv + 装 pymysql
    print("检查 ai-test Python 环境(项目 venv)...")
    vp = ensure_venv(root)
    print(f"  venv: {vp}")
    try:
        import pymysql  # noqa: F401
        print("  依赖检查... pymysql", getattr(pymysql, "__version__", "已安装"))
    except ImportError:
        print("  依赖检查... pymysql 未安装 → 安装 pymysql")
        if pip_install(vp, "pymysql"):
            import pymysql  # noqa: F401
            print("  验证 PyMySQL... ✔ pymysql", getattr(pymysql, "__version__", "已安装"))
        else:
            print("  警告: pymysql 安装失败,可稍后运行 `ai-test env` 重试", file=sys.stderr)
    print()
    print("Commit Test Review 已初始化。")
    print()
    print("统一入口: ai-test(自动使用 .ai-test/venv)。")
    print("  本仓库安装后,可把 .claude/skills/commit-test-review/scripts 加入 PATH,即可直接用 `ai-test`。")
    print()
    print("下一步需要配置数据库。")
    print("Source Database: 用于读取真实业务数据。强烈建议创建只拥有 SELECT 权限的独立账号。")
    print("Test Database: 用于自动化测试。必须使用独立测试数据库,不允许使用生产数据库。")
    print()
    print("  ai-test db add-source   # 配置 Source Database")
    print("  ai-test db set-test     # 配置 Test Database")
    print("  ai-test db list        # 查看")


def main():
    args = sys.argv[1:]
    if not args or args[0] in ("-h", "--help", "help"):
        print(__doc__)
        sys.exit(0)

    root, is_git = repo_root()
    # 环境自举:若仓库 venv 已存在且当前用的不是它,自动切到 venv python 重跑自身。
    # (init/env 会在 venv 缺失时创建;其余命令在 venv 存在时自动复用,消除环境漂移)
    if args[0] not in ("init", "env"):
        reexec_in_venv(root)

    if args[0] == "init":
        cmd_init(root, is_git)
        return

    if args[0] == "env":
        cmd_env(root)
        return

    if args[0] == "diag":
        print("repo_root:", root)
        print("keychain:", "ok" if keychain.test_keychain()[0] else "unavailable")
        try:
            import pymysql
            print("pymysql:", getattr(pymysql, "__version__", "installed"))
        except ImportError:
            print("pymysql: not installed (真实连接测试将降级为配置校验)")
        return

    if args[0] != "db" or len(args) < 2:
        print("未知命令。用 ai-test --help 查看。", file=sys.stderr)
        sys.exit(1)

    sub = args[1]
    cfg, cfg_path = load_config(root)

    if sub == "add-source":
        cmd_add_source(root, cfg, cfg_path)
    elif sub == "update-source":
        if len(args) < 3:
            print("用法: ai-test db update-source <name>")
            sys.exit(1)
        cmd_update_source(root, cfg, cfg_path, args[2])
    elif sub == "remove-source":
        if len(args) < 3:
            print("用法: ai-test db remove-source <name>")
            sys.exit(1)
        cmd_remove_source(root, cfg, cfg_path, args[2])
    elif sub == "list":
        cmd_list(root, cfg)
    elif sub == "test":
        if len(args) < 3:
            print("用法: ai-test db test <name>")
            sys.exit(1)
        cmd_test(root, cfg, args[2])
    elif sub == "set-test":
        cmd_set_test(root, cfg, cfg_path)
    elif sub == "update-test":
        cmd_update_test(root, cfg, cfg_path)
    elif sub == "remove-test":
        cmd_remove_test(root, cfg, cfg_path)
    elif sub == "test-test":
        if not cfg["database"]["test"].get("name"):
            print("尚未配置 Test Database。")
            sys.exit(1)
        cmd_test(root, cfg, cfg["database"]["test"]["name"])
    else:
        print(f"未知子命令: db {sub}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
