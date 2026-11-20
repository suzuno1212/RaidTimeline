"""
core/luatable.py — タイムライン・プランのファイル（return { ... }）を、Lua として実行せずに読む

アドオン（RTL_LT_ParseText）と同じ書き方だけを受け付ける（ファイル形式仕様 0 章）：
  数値（10 進・16 進・小数・指数・マイナス）、文字列（"..." '...' [[...]] [==[...]==]）、true・false・nil、
  表（[キー] = 値、名前 = 値、値を並べる。区切りは , か ;）、コメント（-- と --[[ ]]）。先頭の BOM は無視する。
変数・関数呼び出し・演算・local などがあれば LuaTableError（何行目か）。

  value, head = parse_file_text(text)
    value … 表は dict（キーの順番は書いた順）。キーが 1..n の並びだけなら list
    head  … return より前のコメント行（ファイルの先頭のコメント。書き出すときに残す）
"""
from __future__ import annotations

import re


class LuaTableError(ValueError):
    def __init__(self, msg, line):
        super().__init__('%d 行目: %s' % (line, msg))
        self.line = line


_NUM = re.compile(r'0[xX][0-9a-fA-F]+|(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?')
_NAME = re.compile(r'[A-Za-z_][A-Za-z0-9_]*')
_ESC = {'n': '\n', 't': '\t', 'r': '\r', 'a': '\a', 'b': '\b', 'f': '\f', 'v': '\v',
        '\\': '\\', '"': '"', "'": "'", '\n': '\n'}


class _P:
    def __init__(self, s: str):
        if s.startswith('﻿'):
            s = s[1:]
        self.s = s
        self.i = 0
        self.n = len(s)

    def line(self, i=None):
        return self.s.count('\n', 0, self.i if i is None else i) + 1

    def err(self, msg):
        raise LuaTableError(msg, self.line())

    def _long_bracket(self):
        """[[ / [=[ の開きなら (中身, 終わりの位置)。違えば None"""
        m = re.compile(r'\[(=*)\[').match(self.s, self.i)
        if not m:
            return None
        close = ']' + m.group(1) + ']'
        j = self.s.find(close, m.end())
        if j < 0:
            self.err('閉じていない [[ ]]')
        body = self.s[m.end():j]
        if body.startswith('\r\n'):
            body = body[2:]
        elif body.startswith('\n'):
            body = body[1:]
        return body, j + len(close)

    def skip(self):
        s = self.s
        while self.i < self.n:
            c = s[self.i]
            if c in ' \t\r\n':
                self.i += 1
            elif s.startswith('--', self.i):
                self.i += 2
                lb = self._long_bracket()
                if lb:
                    self.i = lb[1]
                else:
                    j = s.find('\n', self.i)
                    self.i = self.n if j < 0 else j + 1
            else:
                break

    def peek(self, t):
        self.skip()
        return self.s.startswith(t, self.i)

    def expect(self, t):
        if not self.peek(t):
            self.err('"%s" がありません' % t)
        self.i += len(t)

    def string(self):
        s = self.s
        q = s[self.i]
        self.i += 1
        out = []
        while True:
            if self.i >= self.n:
                self.err('閉じていない文字列')
            c = s[self.i]
            if c == q:
                self.i += 1
                return ''.join(out)
            if c == '\n':
                self.err('文字列の途中で改行')
            if c == '\\':
                d = s[self.i + 1:self.i + 2]
                if d.isdigit():
                    m = re.compile(r'\d{1,3}').match(s, self.i + 1)
                    out.append(chr(int(m.group(0))))
                    self.i = m.end()
                    continue
                if d == '\r' and s[self.i + 2:self.i + 3] == '\n':
                    out.append('\n')
                    self.i += 3
                    continue
                if d in _ESC:
                    out.append(_ESC[d])
                    self.i += 2
                    continue
                self.err('読めないエスケープ \\%s' % d)
            out.append(c)
            self.i += 1

    def value(self):
        self.skip()
        s = self.s
        if self.i >= self.n:
            self.err('値がありません')
        c = s[self.i]
        if c == '{':
            return self.table()
        if c in '"\'':
            return self.string()
        if c == '[':
            lb = self._long_bracket()
            if lb:
                self.i = lb[1]
                return lb[0]
            self.err('値がありません')
        neg = False
        if c == '-':
            neg = True
            self.i += 1
            self.skip()
        m = _NUM.match(s, self.i)
        if m:
            t = m.group(0)
            self.i = m.end()
            if _NAME.match(s, self.i) and not t.lower().startswith('0x'):
                self.err('数値の後に文字があります')
            if t.lower().startswith('0x'):
                v = int(t, 16)
            elif re.fullmatch(r'\d+', t):
                v = int(t)
            else:
                v = float(t)
            return -v if neg else v
        if neg:
            self.err('- の後が数値ではありません')
        m = _NAME.match(s, self.i)
        if m:
            w = m.group(0)
            if w in ('true', 'false', 'nil'):
                self.i = m.end()
                return {'true': True, 'false': False, 'nil': None}[w]
            self.err('変数・関数は書けません（%s）' % w)
        self.err('読めない文字 "%s"' % c)

    def table(self):
        self.expect('{')
        items = []         # (key, value)。key が None なら並べた値
        while True:
            self.skip()
            if self.peek('}'):
                self.i += 1
                break
            key = None
            if self.peek('[') and not self._long_bracket():
                self.i += 1
                key = self.value()
                if key is None:
                    self.err('キーに nil は使えません')
                self.expect(']')
                self.expect('=')
                items.append((key, self.value()))
            else:
                m = _NAME.match(self.s, self.i)
                if m and m.group(0) not in ('true', 'false', 'nil'):
                    j = m.end()
                    k = j
                    while k < self.n and self.s[k] in ' \t\r\n':
                        k += 1
                    if self.s.startswith('=', k) and not self.s.startswith('==', k):
                        self.i = k + 1
                        items.append((m.group(0), self.value()))
                    else:
                        items.append((None, self.value()))
                else:
                    items.append((None, self.value()))
            self.skip()
            if self.peek(',') or self.peek(';'):
                self.i += 1
                continue
            self.skip()
            if self.peek('}'):
                continue
            self.err('"," か "}" がありません')
        # 並べた値だけ → list、それ以外 → dict
        if all(k is None for k, _ in items):
            return [v for _, v in items]
        out = {}
        n = 0
        for k, v in items:
            if k is None:
                n += 1
                k = n
            if isinstance(k, float) and k.is_integer():
                k = int(k)
            if v is None:
                out.pop(k, None)
                continue
            out[k] = v
        keys = list(out)
        if keys and all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
            return [out[k] for k in range(1, len(keys) + 1)]
        return out


def parse_text(text: str):
    """return { ... } の値を返す（先頭のコメントは捨てる）"""
    return parse_file_text(text)[0]


def parse_file_text(text: str):
    p = _P(text)
    p.skip()
    head_end = p.i
    m = re.compile(r'return\b').match(p.s, p.i)
    if not m:
        p.err('"return {" で始まっていません')
    p.i = m.end()
    v = p.value()
    p.skip()
    if p.i < p.n:
        p.err('return の値の後に何か書いてあります')
    # 先頭のコメントは書いたとおりに残す（--[[ ]] の中の行もそのまま。空の行は除く）
    head = [ln.rstrip() for ln in p.s[:head_end].replace('\r\n', '\n').split('\n') if ln.strip()]
    return v, head


def parse_file(path: str):
    with open(path, 'rb') as f:
        data = f.read()
    try:
        text = data.decode('utf-8')
    except UnicodeDecodeError as e:
        raise LuaTableError('UTF-8 ではありません（%s）' % e, 1)
    return parse_file_text(text)
