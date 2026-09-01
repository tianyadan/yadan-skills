#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
commit-test-review / yamlmini.py
迷你 YAML 解析 / 生成器(仅纯标准库)。

用途:读写 .ai-test/config.yml。该文件结构简单且固定:
  version: 1
  database:
    sources:
      - name: sales
        type: mysql
        host: ...
        port: 3306
        database: sales
        username: ai_readonly
        keychain-service: ai-test
        keychain-account: sales
    test:
      name: ai-test
      type: mysql
      ...
  test:
    report-dir: docs/test

只支持本项目用到的缩进子集(映射 + 列表 + 标量),不追求通用 YAML。
避免依赖 PyYAML(部分环境未安装)。
"""

from __future__ import annotations


def _parse_scalar(s: str):
    s = s.strip()
    if not s or s in ("null", "Null", "NULL", "~"):
        return None
    if s == "[]":
        return []
    if s == "{}":
        return {}
    if len(s) >= 2 and s[0] == s[-1] and s[0] in "\"'":
        return s[1:-1]
    if s == "true":
        return True
    if s == "false":
        return False
    try:
        return int(s)
    except ValueError:
        pass
    try:
        return float(s)
    except ValueError:
        return s


def _strip_comment(line: str):
    return line.split("#", 1)[0]


def load(text: str) -> dict:
    """解析 YAML 文本为 dict。返回 (data, error)。"""
    # 行令牌: (indent, is_list_item, key, value, has_inline_value)
    tokens = []
    for raw in text.splitlines():
        code = _strip_comment(raw)
        if not code.strip():
            continue
        indent = len(code) - len(code.lstrip(" "))
        content = code.strip()
        if content.startswith("- "):
            rest = content[2:].strip()
            if ":" in rest and not rest.lower().startswith(("http://", "https://")):
                k, _, v = rest.partition(":")
                tokens.append((indent, True, k.strip(), _parse_scalar(v), bool(v.strip())))
            else:
                tokens.append((indent, True, None, _parse_scalar(rest), True))
        elif ":" in content:
            k, _, v = content.partition(":")
            tokens.append((indent, False, k.strip(), _parse_scalar(v), bool(v.strip())))
        else:
            tokens.append((indent, False, content, None, False))

    root = {}

    n = len(tokens)

    def parse_map(idx, base):
        """解析一个映射块:到缩进 < base 或同级结束。返回 (dict, next_idx)。"""
        if idx >= n:
            return {}, idx
        self_indent = tokens[idx][0]
        result = {}
        i = idx
        while i < n:
            pos, is_item, k, v, inline = tokens[i]
            if pos < base or pos != self_indent:
                break
            if is_item:
                i += 1
                continue
            if inline:
                result[k] = v
                i += 1
            else:
                child, i = parse_block(i + 1, pos)
                result[k] = child
        return result, i

    def parse_list_block(idx, base):
        """解析以 '- ' 开头的块。返回 (list, next_idx)。
        列表项形如 '- name: sales' 后跟更深兄弟键(type:/host:/...),全部并入同一 dict 项。"""
        result = []
        i = idx
        while i < n:
            pos, is_item, k, v, inline = tokens[i]
            if pos < base:
                break
            if not is_item or pos == base:
                # 遇到属于父级的键(- 项与父级同缩进?或非列表项) -> 列表到此结束
                break
            item_indent = pos
            entry = {}
            if k is not None:
                if inline:
                    entry[k] = v
                    i += 1
                else:
                    child, i = parse_block(i + 1, item_indent)
                    entry[k] = child
                # 收集后续更深兄弟键(同属此项,缩进>item_indent 且非列表项)
                while i < n and tokens[i][0] > item_indent and not tokens[i][1]:
                    _, _, kk, vv, inl = tokens[i]
                    if inl:
                        entry[kk] = vv
                        i += 1
                    else:
                        c, i = parse_block(i + 1, tokens[i][0])
                        entry[kk] = c
                result.append(entry)
            else:
                result.append(v)
                i += 1
        return result, i

    def parse_block(idx, base):
        if idx >= n:
            return {}, idx
        if tokens[idx][1]:
            return parse_list_block(idx, base)
        return parse_map(idx, base)

    data, _ = parse_block(0, -1)
    return data


def dump(data: dict) -> str:
    """把 dict 序列化为本项目风格的 YAML 文本。"""
    out = []
    _emit(data, 0, out)
    return "\n".join(out)


def _emit(node, level, out, list_item=False):
    pad = "  " * level
    if isinstance(node, dict):
        for k, v in node.items():
            if isinstance(v, dict):
                if not v:
                    out.append(f"{pad}{k}: {{}}")
                else:
                    out.append(f"{pad}{k}:")
                    _emit(v, level + 1, out)
            elif isinstance(v, list):
                if not v:
                    out.append(f"{pad}{k}: []")
                else:
                    out.append(f"{pad}{k}:")
                    _emit(v, level + 1, out)
            else:
                out.append(f"{pad}{k}: {_fmt(v)}")
    elif isinstance(node, list):
        for item in node:
            if isinstance(item, dict):
                keys = list(item.keys())
                if not keys:
                    out.append(f"{'  '*level}- {{}}")
                    continue
                for j, k in enumerate(keys):
                    v = item[k]
                    if j == 0:
                        key_pad = f"{'  '*level}- "
                    else:
                        key_pad = f"{'  '*(level+1)}"
                    if isinstance(v, dict):
                        if not v:
                            out.append(f"{key_pad}{k}: {{}}")
                        else:
                            out.append(f"{key_pad}{k}:")
                            _emit(v, level + 2, out)
                    elif isinstance(v, list):
                        if not v:
                            out.append(f"{key_pad}{k}: []")
                        else:
                            out.append(f"{key_pad}{k}:")
                            _emit(v, level + 1, out)
                    else:
                        out.append(f"{key_pad}{k}: {_fmt(v)}")
            else:
                out.append(f"{'  '*level}- {_fmt(item)}")


def _fmt(v):
    if v is None:
        return "null"
    if isinstance(v, bool):
        return "true" if v else "false"
    return str(v)


if __name__ == "__main__":
    import json
    import sys
    sample = """version: 1

database:
  sources:
    - name: sales
      type: mysql
      host: 10.0.0.21
      port: 3306
      database: sales
      username: ai_readonly
      keychain-service: ai-test
      keychain-account: sales
    - name: crm
      type: mysql
      host: 10.0.0.22
  test:
    name: ai-test
    type: mysql
    host: 10.0.0.30
    database: ai_test
    username: ai_test

test:
  report-dir: docs/test
"""
    d = load(sample)
    print(json.dumps(d, ensure_ascii=False, indent=2))
    print("---- roundtrip ----")
    print(dump(d))
