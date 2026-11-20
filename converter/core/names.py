"""
core/names.py — 名前辞書（names/actions.lua・npcs.lua・buffs.lua。ファイル形式仕様 6 章）

アドオンと同じく 1 行ずつ読む（Lua として実行しない）。書くときも同じ形：
  return {
      [ID] = "名前",        … 1 行に 1 件、ID の小さい順
  }
UTF-8（BOM なし）・CRLF。文字列の中の \\ と " は \\\\・\\" にする。
読めない行が 1 行でもあるファイルは上書きしない（手で直したものを壊さないため。アドオンと同じ）。
"""
from __future__ import annotations

import os
import re

_LINE = re.compile(r'^\s*\[\s*(\d+)\s*\]\s*=\s*"((?:[^"\\]|\\.)*)"\s*,?\s*(--.*)?$')
_SKIP = re.compile(r'^\s*(return\s*\{|\}|--.*)?\s*$')
EOL = '\r\n'


def _unescape(s: str) -> str:
    return re.sub(r'\\(.)', lambda m: {'n': '\n', 'r': '\r', 't': '\t'}.get(m.group(1), m.group(1)), s)


def _escape(s: str) -> str:
    return s.replace('\\', '\\\\').replace('"', '\\"').replace('\r', ' ').replace('\n', ' ')


def read_names(path: str) -> tuple[dict, list]:
    """(ID → 名前, 読めなかった行番号の一覧)。ファイルが無ければ ({}, [])"""
    names, bad = {}, []
    if not path or not os.path.exists(path):
        return names, bad
    with open(path, 'rb') as f:
        text = f.read().decode('utf-8', errors='replace')
    if text.startswith('\ufeff'):
        text = text[1:]
    for i, line in enumerate(text.replace('\r\n', '\n').split('\n'), 1):
        m = _LINE.match(line)
        if m:
            names[int(m.group(1))] = _unescape(m.group(2))
        elif not _SKIP.match(line):
            bad.append(i)
    return names, bad


def render_names(names: dict) -> str:
    lines = ['return {']
    for k in sorted(names):
        lines.append('    [%d] = "%s",' % (int(k), _escape(str(names[k]))))
    lines.append('}')
    return EOL.join(lines) + EOL


def merge_names(path: str, add: dict) -> dict:
    """
    add（ID → 名前）を辞書ファイルに足す・直す。
    返り値 {written: bool, changed: [ID], reason: str}
    """
    cur, bad = read_names(path)
    if bad:
        return dict(written=False, changed=[], reason='読めない行があるので書きません（%s 行目）'
                    % ','.join(map(str, bad[:5])))
    changed = []
    for k, v in add.items():
        v = (v or '').strip()
        if not v:
            continue
        k = int(k)
        if cur.get(k) != v:
            cur[k] = v
            changed.append(k)
    if not changed:
        return dict(written=False, changed=[], reason='変わったものはありません')
    text = render_names(cur)
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    tmp = path + '.tmp'
    with open(tmp, 'wb') as f:
        f.write(text.encode('utf-8'))
    os.replace(tmp, path)
    back, bad2 = read_names(path)
    if bad2 or any(back.get(k) != cur[k] for k in cur):
        return dict(written=False, changed=[], reason='書いた後に読み直すと違いました')
    return dict(written=True, changed=sorted(changed), reason='')


class NameBook:
    """names フォルダの actions / npcs をまとめて引く"""

    def __init__(self, names_dir: str | None):
        self.dir = names_dir
        self.actions, self.bad_actions = read_names(os.path.join(names_dir, 'actions.lua')) if names_dir else ({}, [])
        self.npcs, self.bad_npcs = read_names(os.path.join(names_dir, 'npcs.lua')) if names_dir else ({}, [])

    def summary(self) -> dict:
        return dict(dir=self.dir or '', actions=len(self.actions), npcs=len(self.npcs),
                    bad_actions=self.bad_actions, bad_npcs=self.bad_npcs)
