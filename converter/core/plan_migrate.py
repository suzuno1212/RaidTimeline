"""
プランを新しいタイムラインに移す（スレッド #9）

  変換ツールで作り直したタイムラインで既存のタイムラインを上書きするとき（または別名で書き出して置き換えるとき）、
  plans/<mapid>/*.lua のエントリが指すイベント（event = "p1_45341_1"）を、新しいタイムラインのイベントに付け替える。

  対応付け（エントリごと。古いイベントは「元のタイムライン」から引く）
    same     同じ ID で、同じ敵（contentid）・同じ技                       → そのまま
    moved    ID は違うが、同じ敵・同じ技で
               (1) 同じフェーズの同じ何回目、(2) 同じフェーズで時刻がいちばん近い（MOVE_SEC 秒以内）、
               (3) タイムライン全体で同じ何回目                            → 新しい ID に付け替え
    missing  見つからない（元のタイムラインにも無いイベントを含む）         → 消さずに残す（アドオンでは使われない）
  敵のキー（target.key・satisfiedBy.on）も、同じ contentid の新しいキーが違う名前なら付け替える。
  meta.timeline と meta.timelineVersion を新しいタイムラインのものにする。

  書き換えはテキストの置き換えだけ（コメント・並び・改行 CRLF はそのまま）。書いた後に読み直して、
  変えたところ以外が同じことを確かめる。前の版はアドオンのプラン編集と同じ名前で plans/<mapid>/backup/ にとっておく
  （<名前>_<YYYYMMDD_HHMMSS>[_n].lua、10 世代。アドオンの「元に戻す」で戻せる）
"""
import copy
import datetime
import os
import re

from core.luatable import parse_file_text, LuaTableError

MOVE_SEC = 10.0
PLAN_BACKUP_KEEP = 10      # アドオンの RTL.PE.keep と同じ


class PlanMigrateError(Exception):
    pass


# ---------------------------------------------------------------- タイムラインのイベント
def _acts(a):
    if isinstance(a, (int, float)):
        return frozenset([int(a)])
    if isinstance(a, (list, tuple)):
        return frozenset(int(x) for x in a if isinstance(x, (int, float)))
    if isinstance(a, dict):
        return frozenset(int(x) for x in a.values() if isinstance(x, (int, float)))
    return frozenset()


def _list(v):
    if isinstance(v, list):
        return v
    if isinstance(v, dict):
        return [v[k] for k in sorted(v, key=lambda k: (not isinstance(k, int), k))]
    return []


def timeline_events(tl: dict) -> dict:
    """{ イベント ID: dict(id, phase, cid, key, acts, t, k, g) }。k = フェーズの中で同じ敵・技の何回目、g = 全体で何回目"""
    ents = tl.get('entities') or {}
    out = {}
    kph, kall = {}, {}
    for ph in _list(tl.get('phases')):
        pid = ph.get('id')
        for ev in sorted(_list(ph.get('events')), key=lambda e: float(e.get('t') or 0)):
            m = ev.get('match') or {}
            key = m.get('entity')
            cid = (ents.get(key) or {}).get('contentid') if isinstance(ents, dict) else None
            acts = _acts(m.get('action'))
            sig = (cid if cid is not None else key, acts)
            kph[(pid, sig)] = kph.get((pid, sig), 0) + 1
            kall[sig] = kall.get(sig, 0) + 1
            out[ev.get('id')] = dict(id=ev.get('id'), phase=pid, cid=cid, key=key, acts=acts, sig=sig,
                                     t=float(ev.get('t') or 0), k=kph[(pid, sig)], g=kall[sig],
                                     name=ev.get('name'))
    return out


def entity_key_map(old_tl: dict, new_tl: dict) -> dict:
    """古い敵のキー → 新しい敵のキー（同じ contentid で名前が違うものだけ）"""
    new_by_cid = {}
    for k, e in (new_tl.get('entities') or {}).items():
        if isinstance(e, dict) and e.get('contentid') is not None:
            new_by_cid.setdefault(e['contentid'], k)
    out = {}
    for k, e in (old_tl.get('entities') or {}).items():
        if not isinstance(e, dict):
            continue
        nk = new_by_cid.get(e.get('contentid'))
        if nk is not None and nk != k and k not in (new_tl.get('entities') or {}):
            out[k] = nk
    return out


def map_event(old: dict | None, new_events: dict) -> tuple[str, str | None, str]:
    """(kind, 新しい ID, 説明)"""
    if old is None:
        return 'missing', None, '元のタイムラインにもこのイベントがありません'
    same = new_events.get(old['id'])
    if same and same['sig'] == old['sig']:
        return 'same', old['id'], ''
    if same and same['sig'][0] == old['sig'][0] and same['acts'] & old['acts'] and same['phase'] == old['phase']:
        # 同じ ID で、照合する技の組だけ変わった（分岐の片方が増えた・減った）
        return 'same', old['id'], '照合する技の組が変わりました（%s → %s）' % (
            '/'.join(map(str, sorted(old['acts']))), '/'.join(map(str, sorted(same['acts']))))
    cands = [e for e in new_events.values() if e['sig'] == old['sig']]
    if not cands:
        # 技の組が少し違う（分岐の片方が増えた・減った）：同じ敵で、技が重なるもの
        cands = [e for e in new_events.values()
                 if e['sig'][0] == old['sig'][0] and e['acts'] & old['acts']]
    if not cands:
        return 'missing', None, '新しいタイムラインに、同じ敵・同じ技のイベントがありません'
    inph = [e for e in cands if e['phase'] == old['phase']]
    for e in inph:
        if e['k'] == old['k']:
            return 'moved', e['id'], '同じフェーズの %d 回目' % old['k']
    if inph:
        e = min(inph, key=lambda x: abs(x['t'] - old['t']))
        if abs(e['t'] - old['t']) <= MOVE_SEC:
            return 'moved', e['id'], '同じフェーズで時刻が近い（%+.1f 秒）' % (e['t'] - old['t'])
    for e in cands:
        if e['g'] == old['g']:
            return 'moved', e['id'], '全体で %d 回目（フェーズ %s → %s）' % (old['g'], old['phase'], e['phase'])
    return 'missing', None, '同じ敵・同じ技はあるが、どれに当たるか決められません'


# ---------------------------------------------------------------- プランを読む・書き換える
def _read(path):
    with open(path, 'rb') as f:
        data = f.read()
    try:
        text = data.decode('utf-8')
    except UnicodeDecodeError:
        raise PlanMigrateError('UTF-8 ではありません')
    if text.startswith('﻿'):
        raise PlanMigrateError('BOM 付きです（アドオンと同じく BOM なしにしてください）')
    try:
        val, _ = parse_file_text(text)
    except LuaTableError as e:
        raise PlanMigrateError('読めません（%s）' % e)
    if not isinstance(val, dict):
        raise PlanMigrateError('return { ... } ではありません')
    return text, val


def _q(s):
    return '"%s"' % str(s).replace('\\', '\\\\').replace('"', '\\"')


def plan_entries(val: dict) -> list:
    return [e for e in _list(val.get('entries')) if isinstance(e, dict)]


def preview_plan(path: str, src_stem: str, old_events: dict, new_events: dict, key_map: dict,
                 force: bool = False) -> dict:
    """1 つのプランの対応付け。use = False なら移さない（別のタイムラインのプランなど）"""
    name = os.path.basename(path)
    try:
        text, val = _read(path)
    except (OSError, PlanMigrateError) as e:
        return dict(file=name, use=False, reason=str(e), entries=[], counts={})
    meta = val.get('meta') or {}
    tlname = meta.get('timeline')
    ents = plan_entries(val)
    if tlname and tlname != src_stem and not force:
        return dict(file=name, use=False, reason='別のタイムライン（%s）のプランです' % tlname, entries=[], counts={},
                    timeline=tlname)
    # meta.timeline の無いプラン（1 つのマップの複数のタイムラインにまたがる：ミストウェイクの 3 ボスなど）：
    #   元のタイムラインにあるイベントのエントリだけ移す。ほかのエントリ（別のタイムラインのもの）と meta はそのまま
    partial = not tlname
    rows = []
    for e in ents:
        ev = e.get('event')
        if not ev:
            continue
        if partial and ev not in old_events:
            rows.append(dict(id=e.get('id'), event=ev, new=None, kind='other', note='別のタイムラインのイベント（そのまま）',
                             name=None, t=None))
            continue
        kind, nid, note = map_event(old_events.get(ev), new_events)
        o = old_events.get(ev)
        rows.append(dict(id=e.get('id'), event=ev, new=nid, kind=kind, note=note,
                         name=(o or {}).get('name'), t=(o or {}).get('t')))
    keys = []
    mine = {r['id'] for r in rows if r['kind'] != 'other'}
    for e in ents:
        if e.get('id') not in mine:
            continue
        tg = e.get('target') if isinstance(e.get('target'), dict) else {}
        sb = e.get('satisfiedBy') if isinstance(e.get('satisfiedBy'), dict) else {}
        for where, v in (('target.key', tg.get('key')), ('satisfiedBy.on', sb.get('on'))):
            if v in key_map:
                keys.append(dict(id=e.get('id'), where=where, old=v, new=key_map[v]))
    counts = {k: sum(1 for r in rows if r['kind'] == k) for k in ('same', 'moved', 'missing', 'other')}
    if partial and not (counts['same'] + counts['moved'] + counts['missing']):
        return dict(file=name, use=False, timeline=None, entries=[], counts={},
                    reason='元のタイムラインのイベントを使うエントリがありません')
    return dict(file=name, use=True, reason='', timeline=tlname, partial=partial, entries=rows, keys=keys,
                counts=counts)


def rewrite_plan_text(text: str, rows: list, keys: list, new_stem: str | None, new_version) -> str:
    """テキストの置き換えで、event・敵のキー・meta.timeline / timelineVersion を書き換える"""
    nl = '\r\n' if '\r\n' in text else '\n'
    # エントリの場所：id = "<文字列>"（アクションの id は数なので、文字列の id はエントリだけ）
    ids = [(m.start(), m.group(1)) for m in re.finditer(r'\bid\s*=\s*"((?:[^"\\]|\\.)*)"', text)]
    spans = {}
    for i, (pos, eid) in enumerate(ids):
        end = ids[i + 1][0] if i + 1 < len(ids) else len(text)
        spans.setdefault(eid, (pos, end))
    edits = []      # (start, end, new)
    for r in rows:
        if r['kind'] != 'moved' or r['id'] not in spans:
            continue
        a, b = spans[r['id']]
        m = re.compile(r'\bevent\s*=\s*' + re.escape(_q(r['event']))).search(text, a, b)
        if not m:
            raise PlanMigrateError('%s の event が見つかりません' % r['id'])
        edits.append((m.start(), m.end(), 'event = ' + _q(r['new'])))
    for k in keys:
        if k['id'] not in spans:
            continue
        a, b = spans[k['id']]
        field = 'key' if k['where'] == 'target.key' else 'on'
        m = re.compile(r'\b' + field + r'\s*=\s*' + re.escape(_q(k['old']))).search(text, a, b)
        if m:
            edits.append((m.start(), m.end(), '%s = %s' % (field, _q(k['new']))))
    # meta（new_stem が None なら書き換えない：meta.timeline の無いプラン）
    if new_stem is not None:
        edits += _meta_edits(text, nl, new_stem, new_version)
    edits.sort()
    for x, y in zip(edits, edits[1:]):
        if x[1] > y[0]:
            raise PlanMigrateError('書き換える場所が重なりました')
    out = []
    pos = 0
    for a, b, s in edits:
        out.append(text[pos:a])
        out.append(s)
        pos = b
    out.append(text[pos:])
    return ''.join(out)


def _meta_edits(text: str, nl: str, new_stem: str, new_version) -> list:
    """meta.timeline / timelineVersion を書き換える（無ければ mapid の行の後に足す）"""
    mm = re.compile(r'\bmeta\s*=\s*\{').search(text)
    if not mm:
        raise PlanMigrateError('meta = { ... } がありません')
    depth, i = 1, mm.end()
    while i < len(text) and depth:
        c = text[i]
        if c == '"':
            i += 1
            while i < len(text) and text[i] != '"':
                i += 2 if text[i] == '\\' else 1
        elif c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
        i += 1
    ma, mb = mm.end(), i - 1          # meta の { の後 〜 } の前
    edits = []
    for field, val in (('timeline', _q(new_stem)), ('timelineVersion', None if new_version is None else str(new_version))):
        m = re.compile(r'\b' + field + r'\s*=\s*("(?:[^"\\]|\\.)*"|[-\d.]+)').search(text, ma, mb)
        if m:
            if val is not None:
                edits.append((m.start(), m.end(), '%s = %s' % (field, val)))
            continue
        if val is None:
            continue
        # 無ければ mapid の行の後に足す（無ければ meta の { の直後）
        mp = re.compile(r'\bmapid\s*=\s*[-\d]+\s*,?').search(text, ma, mb)
        if mp:
            line_start = text.rfind('\n', 0, mp.start()) + 1
            indent = re.match(r'[ \t]*', text[line_start:]).group(0)
            own_line = text[line_start:mp.start()].strip() == ''
            ins = (nl + indent if own_line else ' ') + '%s = %s,' % (field, val)
            edits.append((mp.end(), mp.end(), ins if mp.group(0).rstrip().endswith(',') else ',' + ins))
        else:
            edits.append((ma, ma, ' %s = %s,' % (field, val)))
    return edits


def verify_rewrite(old_val: dict, new_text: str, rows: list, keys: list, new_stem: str, new_version) -> None:
    """読み直して、変えたところ以外が同じか確かめる"""
    try:
        new_val, _ = parse_file_text(new_text)
    except LuaTableError as e:
        raise PlanMigrateError('書き換えたら読めなくなりました（%s）' % e)
    want = copy.deepcopy(old_val)
    if new_stem is not None:
        want.setdefault('meta', {})
        want['meta']['timeline'] = new_stem
        if new_version is not None:
            want['meta']['timelineVersion'] = new_version
    moved = {r['id']: r['new'] for r in rows if r['kind'] == 'moved'}
    km = {(k['id'], k['where']): k['new'] for k in keys}
    for e in plan_entries(want):
        if e.get('id') in moved:
            e['event'] = moved[e['id']]
        if (e.get('id'), 'target.key') in km:
            e['target']['key'] = km[(e['id'], 'target.key')]
        if (e.get('id'), 'satisfiedBy.on') in km:
            e['satisfiedBy']['on'] = km[(e['id'], 'satisfiedBy.on')]
    if _norm(want) != _norm(new_val):
        raise PlanMigrateError('書き換えた結果を読み直すと、変えたところ以外も違っていました')


def _norm(v):
    if isinstance(v, dict):
        return {str(k): _norm(x) for k, x in v.items()}
    if isinstance(v, list):
        return [_norm(x) for x in v]
    if isinstance(v, float) and v.is_integer():
        return int(v)
    return v


def save_plan_backup(plan_dir: str, fname: str, data: bytes) -> str:
    """アドオンのプラン編集と同じ：plans/<mapid>/backup/<名前>_<YYYYMMDD_HHMMSS>[_n].lua、10 世代"""
    bdir = os.path.join(plan_dir, 'backup')
    os.makedirs(bdir, exist_ok=True)
    stem = fname[:-4] if fname.lower().endswith('.lua') else fname
    base = '%s_%s' % (stem, datetime.datetime.now().strftime('%Y%m%d_%H%M%S'))
    pat = re.compile(r'^' + re.escape(stem) + r'_(\d{8})_(\d{6})(?:_(\d+))?\.lua$')
    have = [b for b in os.listdir(bdir) if pat.match(b)]
    # 同じ秒にもうあれば、いちばん大きい番号の次（消えた番号を使い回すと、新しいものが一番古く並ぶため）
    stamp = base[len(stem) + 1:]
    top = 0
    for b in have:
        m = pat.match(b)
        if m.group(1) + '_' + m.group(2) == stamp:
            top = max(top, int(m.group(3) or 1))
    name = base + '.lua' if top == 0 else '%s_%d.lua' % (base, top + 1)
    with open(os.path.join(bdir, name), 'wb') as f:
        f.write(data)
    have.append(name)

    def key(b):
        m = pat.match(b)
        return m.group(1) + m.group(2) + '%04d' % int(m.group(3) or 1)
    have.sort(key=key)
    for b in have[:-PLAN_BACKUP_KEEP]:
        try:
            os.remove(os.path.join(bdir, b))
        except OSError:
            pass
    return name


def apply_plan(path: str, pv: dict, new_stem: str, new_version) -> dict:
    """1 つのプランを書き換える（前の版をとってから）。書き換えるところが無ければ meta だけ直す"""
    text, val = _read(path)
    if pv.get('partial'):
        new_stem, new_version = None, None
    new_text = rewrite_plan_text(text, pv['entries'], pv.get('keys') or [], new_stem, new_version)
    verify_rewrite(val, new_text, pv['entries'], pv.get('keys') or [], new_stem, new_version)
    if new_text == text:
        return dict(file=pv['file'], written=False, backup=None)
    bak = save_plan_backup(os.path.dirname(path), os.path.basename(path), text.encode('utf-8'))
    tmp = path + '.tmp'
    with open(tmp, 'wb') as f:
        f.write(new_text.encode('utf-8'))
    os.replace(tmp, path)
    with open(path, 'rb') as f:
        if f.read() != new_text.encode('utf-8'):
            with open(path, 'wb') as g:
                g.write(text.encode('utf-8'))
            raise PlanMigrateError('%s：書いた後に読み戻すと違ったので、前の版に戻しました' % pv['file'])
    return dict(file=pv['file'], written=True, backup=bak)
