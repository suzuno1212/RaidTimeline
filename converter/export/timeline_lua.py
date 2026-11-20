"""
export/timeline_lua.py — タイムライン Lua（ファイル形式仕様 format = 1）の書き出し

  text = render_timeline(analysis, name="m4s")
  path = write_timeline(analysis, "out/timelines", name="m4s")   # -> out/timelines/1232_m4s.lua

決まり（ファイル形式仕様 0 章）
  - UTF-8（BOM なし）、改行 CRLF
  - ファイル名は英数字・_・- のみ
  - 秒数は小数第 1 位まで
  - イベント名は ID の仮名（例「38383 #1」）。名前辞書ができたら差し替える
"""
from __future__ import annotations

import datetime
import os
import re

from core.analyze import Analysis, Slot

FORMAT_VERSION = 1
EOL = '\r\n'
INDENT = '    '

DEFAULT_KINDS = ('stable', 'partial', 'branch', 'swap')


# ====================================================================== Lua の値

_IDENT = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*$')
_LUA_KEYWORDS = {
    'and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for', 'function', 'goto', 'if', 'in',
    'local', 'nil', 'not', 'or', 'repeat', 'return', 'then', 'true', 'until', 'while'}


def lua_str(s: str) -> str:
    out = ['"']
    for ch in s:
        if ch == '\\':
            out.append('\\\\')
        elif ch == '"':
            out.append('\\"')
        elif ch == '\n':
            out.append('\\n')
        elif ch == '\r':
            out.append('\\r')
        elif ord(ch) < 32:
            out.append('\\%03d' % ord(ch))
        else:
            out.append(ch)
    out.append('"')
    return ''.join(out)


def lua_key(k) -> str:
    if isinstance(k, str) and _IDENT.match(k) and k not in _LUA_KEYWORDS:
        return k
    if isinstance(k, str):
        return '[%s]' % lua_str(k)
    return '[%s]' % lua_value(k)


def sec(x: float) -> 'Sec':
    """秒数（小数第 1 位で書く）"""
    return Sec(x)


class Sec(float):
    pass


def lua_value(v) -> str:
    """1 行で書ける Lua の値（小さなテーブルも 1 行）"""
    if v is None:
        return 'nil'
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, Sec):
        return '%.1f' % v
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        return ('%.1f' % v) if abs(v - round(v, 1)) < 1e-9 else repr(round(v, 3))
    if isinstance(v, str):
        return lua_str(v)
    if isinstance(v, (list, tuple)):
        return '{ %s }' % ', '.join(lua_value(x) for x in v) if v else '{ }'
    if isinstance(v, dict):
        if not v:
            return '{ }'
        return '{ %s }' % ', '.join('%s = %s' % (lua_key(k), lua_value(x)) for k, x in v.items())
    raise TypeError('Lua に書けない値: %r' % (v,))


# ====================================================================== ファイル名

def safe_name(s: str, default: str = 'draft') -> str:
    """英数字・_・- のみ（仕様 0 章）"""
    s = re.sub(r'[^A-Za-z0-9_-]+', '_', s or '').strip('_')
    return s or default


def timeline_filename(analysis: Analysis, name: str) -> str:
    return '%s_%s.lua' % (analysis.mapid if analysis.mapid is not None else 0, safe_name(name))


# ====================================================================== タイムラインの組み立て

def _action_value(acts):
    acts = list(acts)
    return acts[0] if len(acts) == 1 else acts


def build_timeline(analysis: Analysis, name: str = 'draft', title: str | None = None, author: str = '',
                   version: int = 1, kinds=DEFAULT_KINDS, real_casters_only: bool = False,
                   include_syncs: bool = True, updated: str | None = None, source: str = 'replay') -> dict:
    """
    タイムラインを Python の dict で組み立てる（UI で編集してから render するための形）。
    各イベント・同期点には、Lua に書かない補足（'_comment'）を付ける。
    """
    meta = dict(
        name=title or name,
        mapid=analysis.mapid if analysis.mapid is not None else 0,
        cfc=analysis.cfc if analysis.cfc is not None else 0,
        version=int(version),
        author=author,
        gameBuild=','.join(b for b in analysis.builds if b != 'recorder'),
        source=source,
        updated=updated or datetime.date.today().isoformat(),
    )
    if analysis.cfc is None:            # 記録ログから作ったとき（cfc・ビルドは分からない）
        meta.pop('cfc')
    if not meta['gameBuild']:
        meta.pop('gameBuild')

    used_keys = set()
    phases = []
    for ph in analysis.phases:
        events, syncs = [], []
        for s in ph.slots:
            if s.kind not in kinds:
                continue
            if real_casters_only and not s.real_caster:
                continue
            comment = _event_comment(s, analysis)
            for part in s.parts or [dict(event_id=s.event_id, name=s.event_name, cast=s.cast,
                                         action=_action_value(s.action_set))]:
                # 同じ瞬間の別々のアクションは、アクションごとに 1 イベント（core/analyze.py の _name_events）
                ev = dict(id=part['event_id'], name=part['name'], t=sec(s.t), cast=sec(part['cast']),
                          match=dict(entity=s.entity, action=part['action']))
                if s.kind == 'swap' and s.partner:
                    other = next(x for x in ph.slots if x.id == s.partner)
                    ev['tolerance'] = sec(round(abs(other.t - s.t) + 2.0, 1))
                ev['_comment'] = comment + ('（同時 %s）' % '+'.join(map(str, s.action_set)) if len(s.parts) > 1 else '')
                events.append(ev)
            used_keys.add(s.entity)
            if include_syncs and s.sync:
                on = dict(type='cast_start', entity=s.entity, action=_action_value(s.action_set))
                if s.nth is not None:
                    on['nth'] = s.nth
                syncs.append(dict(on=on, t=sec(s.t), window=sec(10.0),
                                  _comment='候補（%s）' % _sync_reason(s.sync), _event=s.event_id))
        trig = dict(ph.trigger)
        if 'entity' in trig:
            used_keys.add(trig['entity'])
        phases.append(dict(id=ph.id, name=ph.name, trigger=trig, events=events, syncs=syncs,
                           _comment=_phase_comment(ph, analysis)))

    entities = {}
    for key, e in analysis.entities.items():
        if key not in used_keys and not e.get('real'):
            continue
        ent = dict(name=e['name'], contentid=e['contentid'])
        if e.get('select'):
            ent['select'] = dict(e['select'])
        bases = ','.join(str(b) for b in e.get('bases', []))
        ent['_comment'] = ('本物の敵（攻撃を受けた）bNpcBase %s, 最大HP %d' % (bases, e.get('max_hp', 0))
                           if e.get('real') else
                           '詠唱だけする敵（発射役など・攻撃されない）bNpcBase %s' % bases)
        entities[key] = ent

    return dict(format=FORMAT_VERSION, meta=meta, entities=entities, phases=phases)


def _event_comment(s: Slot, analysis: Analysis) -> str:
    n = len(s.reached)
    parts = ['%d/%d' % (s.seen, n)]
    if s.spread is not None:
        parts.append('ばらつき %.1f' % s.spread)
    if s.kind == 'branch':
        parts.append('分岐: ' + ' / '.join('%s=%s' % (p, '+'.join(map(str, a))) for p, a in s.sets().items()))
    elif s.kind == 'swap':
        partner = next((x.event_id for ph in analysis.phases for x in ph.slots if x.id == s.partner), s.partner)
        parts.append('順番入れ替わり（相手 %s）: ' % partner +
                     ' '.join('%s=%s' % (p, '+'.join(map(str, a))) for p, a in s.sets().items()))
    elif s.kind == 'partial':
        missing = [p for p in s.reached if p not in s.moments]
        parts.append('出ないプルあり: ' + '/'.join(missing))
    if not s.real_caster:
        parts.append('詠唱者 bNpcBase %d' % s.source[1])
    return ' '.join(parts)


def _sync_reason(r: str) -> str:
    if r.startswith('before_unstable'):
        return 'ばらつきの大きい %s の直前' % r.split(':', 1)[1]
    return '間隔'


def _phase_comment(ph, analysis: Analysis) -> str:
    starts = ' '.join('%s=%.1f' % (k, v / 1000) for k, v in ph.starts.items())
    return '%s 開始（戦闘開始からの秒数）: %s' % (ph.id, starts)


# ====================================================================== 文字列にする

def render_timeline(analysis: Analysis | None = None, tl: dict | None = None, header: list | None = None,
                    **kw) -> str:
    """
    Lua の文字列（改行 CRLF）を返す。tl を渡せばそれを、無ければ analysis から組み立てる。
    header（コメント行の list）を渡すと、先頭のコメントをそれにする（既存のタイムラインを開いて直したとき）
    """
    if tl is None:
        tl = build_timeline(analysis, **kw)
    L = []
    w = L.append
    if header is not None:
        for line in header:          # 書いたとおり（--[[ ]] の中の行もあるので、-- を足さない）
            w(line)
        analysis = None
    else:
        w('-- RaidTimeline タイムライン（リプレイ変換ツールが作った下書き）')
        w('-- イベント名は ID の仮名です。名前・不要なイベント・同期点は確認して直してください')
    if analysis is not None:
        used = {p.replay for p in analysis.pulls}
        for ri, r in enumerate(analysis.replays):
            if ri not in used:
                continue
            if r['build'] == 'recorder':
                w('-- 元ログ: %s（記録モード・秒数の基準 %s・%s）' % (r['file'], r.get('t0_source', '?'),
                                                                 r.get('result', '?')))
            else:
                w('-- 元リプレイ: %s（build %s）' % (r['file'].replace('\n', ' '), r['build']))
                if r.get('paired'):
                    w('--   組にした記録ログ: %s' % ' '.join('P%d=%s' % (int(k) + 1, v) for k, v in sorted(r['paired'].items())))
        w('-- 使ったプル: %s' % ', '.join('%s(%.0fs)' % (p.label, p.fight_sec) for p in analysis.pulls))
        if all(r['build'] == 'recorder' for r in analysis.replays):
            w('-- 秒数の基準: 記録モードの戦闘開始（ログの t = 0）')
        elif any(r.get('paired') for r in analysis.replays):
            w('-- 秒数の基準: 記録モードの戦闘開始（リプレイのプルは組にした記録ログの t = 0。組にならなかったプルは推し量り）')
        elif analysis.options.time_zero == 'engage':
            w('-- 秒数の基準: 各プルで最初にパーティが敵を攻撃した時刻（チャプター開始からの差: %s）'
              % ' '.join('%s=%s' % (p.label, '-' if p.engage_offset is None else '%.1f' % p.engage_offset)
                         for p in analysis.pulls))
        else:
            w('-- 秒数の基準: チャプター開始（カウントダウン開始。アドオンの戦闘開始とずれるので注意）')
        if len(analysis.pulls) == 1:
            w('-- 注意: 1 プルだけから作りました。ランダム分岐・順番の入れ替わり・時刻のばらつきは分かりません。')
            w('--       同じコンテンツのリプレイを複数まとめて変換すると、分岐を「どれか1つ」として書き出せます。')
        for c in analysis.phase_candidates:
            w('-- フェーズ移行の候補: %s %s(contentid %d, bNpcBase %d)%s %s%s' % (
                c.kind, c.entity, c.contentid, c.base,
                (' action ' + '/'.join(map(str, c.actions))) if c.actions else '',
                ' '.join('%s=%.1f' % kv for kv in c.times.items()),
                '  → %s に採用' % c.phase if c.adopted else ''))
    w('return {')
    w(INDENT + 'format = %d,' % tl['format'])
    w('')
    w(INDENT + 'meta = {')
    width = max(len(k) for k in tl['meta'])
    for k, v in tl['meta'].items():
        w(INDENT * 2 + '%-*s = %s,' % (width, k, lua_value(v)))
    w(INDENT + '},')
    w('')
    if tl.get('actions'):
        # アクションID → 技名（表示用。仕様 2.1）
        w(INDENT + 'actions = {')
        for k in sorted(tl['actions']):
            w(INDENT * 2 + '[%d] = %s,' % (int(k), lua_str(str(tl['actions'][k]))))
        w(INDENT + '},')
        w('')
    w(INDENT + 'entities = {')
    for key, e in tl['entities'].items():
        body = {k: v for k, v in e.items() if not k.startswith('_')}
        line = INDENT * 2 + '%s = %s,' % (lua_key(key), lua_value(body))
        if e.get('_comment'):
            line += '  -- ' + e['_comment']
        w(line)
    w(INDENT + '},')
    w('')
    w(INDENT + 'phases = {')
    for ph in tl['phases']:
        w(INDENT * 2 + '{')
        if ph.get('_comment'):
            w(INDENT * 3 + '-- ' + ph['_comment'])
        w(INDENT * 3 + 'id      = %s,' % lua_str(ph['id']))
        w(INDENT * 3 + 'name    = %s,' % lua_str(ph['name']))
        w(INDENT * 3 + 'trigger = %s,' % lua_value(ph['trigger']))
        w('')
        w(INDENT * 3 + 'events = {')
        for ev in ph['events']:
            body = {k: v for k, v in ev.items() if not k.startswith('_')}
            line = INDENT * 4 + lua_value(body) + ','
            if ev.get('_comment'):
                line += '  -- ' + ev['_comment']
            w(line)
        w(INDENT * 3 + '},')
        w('')
        w(INDENT * 3 + 'syncs = {')
        for sy in ph['syncs']:
            body = {k: v for k, v in sy.items() if not k.startswith('_')}
            line = INDENT * 4 + lua_value(body) + ','
            if sy.get('_comment'):
                line += '  -- ' + sy['_comment']
            w(line)
        w(INDENT * 3 + '},')
        w(INDENT * 2 + '},')
    w(INDENT + '},')
    w('}')
    return EOL.join(L) + EOL


def write_timeline(analysis: Analysis, out_dir: str, name: str = 'draft', **kw) -> str:
    """out_dir/<mapid>_<name>.lua に書き出し、パスを返す"""
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, timeline_filename(analysis, name))
    text = render_timeline(analysis, name=name, **kw)
    with open(path, 'wb') as f:
        f.write(text.encode('utf-8'))
    return path
