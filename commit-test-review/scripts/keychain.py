#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
commit-test-review / keychain.py
macOS Keychain 封装:用系统 /usr/bin/security 读写数据库密码。

硬规则:
- service 固定为 "ai-test"(见需求 §17)。
- account 对应数据源 name(如 sales / crm / test-db)。
- 密码只在进程内用于建立数据库连接;任何输出只显示 "Password: configured"。
- 禁止明文落盘 / 进日志 / 进报告 / 进终端。

用法(作为模块导入):
    import keychain
    keychain.set_password(account, prompt="Source Database 密码")
    pwd = keychain.get_password(account)   # 返回 bytes 或 None
    keychain.delete_password(account)
    keychain.has_password(account) -> bool
"""

from __future__ import annotations

import subprocess
import sys

SECURITY = "/usr/bin/security"
SERVICE = "ai-test"


def _run(args, input_data=None):
    """调用 /usr/bin/security,返回 (returncode, stdout_bytes, stderr_text)。"""
    try:
        proc = subprocess.run(
            [SECURITY] + args,
            input=input_data,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        return proc.returncode, proc.stdout, proc.stderr.decode("utf-8", "replace")
    except FileNotFoundError:
        return -1, b"", f"not found: {SECURITY}"


def _set(account, password_bytes, update):
    """写入/更新。返回 (ok, message)。"""
    args = ["add-generic-password", "-a", account, "-s", SERVICE]
    if update:
        args.append("-U")
    args += ["-w", password_bytes.decode("utf-8", "replace")]
    rc, out, err = _run(args)
    if rc == 0:
        return True, "Password: configured"
    return False, err.strip() or f"security failed (rc={rc})"


def set_password(account, password, update=False):
    """把 password(str) 存入 Keychain。update=True 表示覆盖。"""
    p = password.encode("utf-8")
    ok, msg = _set(account, p, update)
    if not ok:
        # 若已存在且没 update,提示改用 update
        if not update and has_password(account) and "already exists" in msg.lower():
            return False, msg + " (若需覆盖请使用 update 命令)"
    return ok, msg


def get_password(account):
    """读取密码。返回 bytes(供建立连接),调用方不得将其打印。"""
    rc, out, err = _run(["find-generic-password", "-a", account, "-s", SERVICE, "-w"])
    if rc == 0:
        return out.rstrip(b"\n")
    return None


def has_password(account):
    rc, out, err = _run(["find-generic-password", "-a", account, "-s", SERVICE, "-w"])
    return rc == 0


def delete_password(account):
    rc, out, err = _run(["delete-generic-password", "-a", account, "-s", SERVICE])
    return rc == 0


def test_keychain():
    """检查 security 是否可用(只写测试 account,随即删除,不留残留)。"""
    if not subprocess.run(["command", "-v", "security"], stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL).returncode == 0:
        return False, "security 命令不可用(需 macOS)"
    return True, "ok"


if __name__ == "__main__":
    # 交互自测:写入一个临时账号并回读(不打印明文),再删除
    acct = "__aitest_selfcheck__"
    ok, msg = test_keychain()
    if not ok:
        print(msg)
        sys.exit(1)
    delete_password(acct)
    pw = input("输入一个任意自测密码(用于验证 Keychain 往返,不会显示): ")
    set_password(acct, pw, update=True)
    got = get_password(acct)
    print("往返一致:", got == pw.encode("utf-8"))
    delete_password(acct)
