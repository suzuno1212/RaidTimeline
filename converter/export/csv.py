"""
export/csv.py — CSV の書き出し

  write_compare_csv(analysis, path)        … 比較表（プル × イベント）。Excel で開ける UTF-8 BOM 付き
  write_log_csvs(replays, analysis, dir)   … ファイル形式仕様 5 章のログ CSV（1 プル＝1 ファイル）

※ このファイル名は標準ライブラリの csv と同じなので、標準ライブラリは _csv として読み込む。
  （パッケージ export の中なので、`import csv` は標準ライブラリを指す）
"""
from __future__ import annotations

import csv as _csv
import datetime
import os

from core.analyze import Analysis
from core.replay import Replay, ENEMY_ID_MIN

ENCODING = 'utf-8-sig'      # Excel で文字化けしないよう BOM 付き
LINE = '\r\n'

LOG_COLUMNS = ['t', 'kind', 'entity_id', 'contentid', 'base_id', 'max_hp', 'action_id', 'cast',
               'target_id', 'v1', 'v2', 'name']


def _writer(f):
    return _csv.writer(f, lineterminator=LINE)


# ====================================================================== 比較表

def compare_rows(analysis: Analysis) -> list[list]:
    """比較表の行（見出しを含む）。UI の表にもそのまま使える"""
    labels = analysis.pull_labels()
    head = ['phase', 'event_id', 'name', 'kind', 't', 'spread', 'cast', 'entity', 'contentid', 'base',
            'actions', 'seen', 'reached', 'partner', 'sync', 'nth']
    for p in labels:
        head += ['%s_t' % p, '%s_action' % p]
    rows = [head]
    for ph in analysis.phases:
        for s in ph.slots:
            row = [ph.id, s.event_id, s.event_name, s.kind, s.t, '' if s.spread is None else s.spread,
                   s.cast, s.entity, s.source[0], s.source[1], ' '.join(map(str, s.action_set)),
                   s.seen, len(s.reached), s.partner or '', s.sync or '', '' if s.nth is None else s.nth]
            sets = s.sets()
            for p in labels:
                if p in s.moments:
                    row += [s.moments[p].t, '+'.join(map(str, sets[p]))]
                elif p in s.reached:
                    row += ['', '(なし)']
                else:
                    row += ['', '']
            rows.append(row)
    return rows


def write_compare_csv(analysis: Analysis, path: str) -> str:
    d = os.path.dirname(os.path.abspath(path))
    os.makedirs(d, exist_ok=True)
    with open(path, 'w', encoding=ENCODING, newline='') as f:
        w = _writer(f)
        for row in compare_rows(analysis):
            w.writerow(row)
    return path


# ====================================================================== ログ CSV（仕様 5 章）

def pull_result(r: Replay, pull_index: int, min_hits: int = 10) -> tuple[str, float | None]:
    """
    ('clear' | 'wipe', 最後に攻撃された本物の敵の最終HP%)。
    最後に攻撃された本物の敵の最後の HP が 0 なら clear、それ以外は wipe。
    """
    p = r.pulls[pull_index]
    last, last_e = -1, None
    for e in r.entities.values():
        if e.is_pet or e.id < ENEMY_ID_MIN:
            continue
        hs = [m for m in e.hit_ms if p.start_ms <= m <= p.end_ms]
        if len(hs) >= min_hits and hs[-1] > last:
            last, last_e = hs[-1], e
    if last_e is None:
        return 'wipe', None
    ser = [x for x in r.hp_series(last_e.id) if p.start_ms <= x[0] <= p.end_ms]
    if not ser or not ser[-1][2]:
        return 'wipe', None
    pct = round(ser[-1][1] * 100.0 / ser[-1][2], 1)
    return ('clear' if ser[-1][1] == 0 else 'wipe'), pct


def log_rows(r: Replay, pull_index: int, min_hits: int = 10) -> list[list]:
    """
    1 プル分のログ行（見出しを含む）。t は戦闘開始（プル開始）からの秒数。
      appear     : v1 = 親 ID（発射役ならボスの ID）, v2 = 1 なら本物の敵（攻撃を受けた）
      cast_start : action_id, cast, target_id
      hp         : v1 = HP%, v2 = 現在HP（本物の敵のみ。約 1 秒ごと）
      wipe/clear : v1 = 最後に攻撃された本物の敵の最終HP%
    リプレイからは名前が取れないので name は空。
    t の基準は交戦開始（最初にパーティが敵を攻撃した時刻）。カウントダウン中の出現はマイナスになる。
    """
    p = r.pulls[pull_index]
    t0 = p.t0_ms

    def t(ms):
        return round((ms - t0) / 1000, 1)

    rows = []
    real_ids = set()
    for e in r.entities.values():
        if e.is_pet or e.id < ENEMY_ID_MIN:
            continue
        if len([m for m in e.hit_ms if p.start_ms <= m <= p.end_ms]) >= min_hits:
            real_ids.add(e.id)
    for e in sorted(r.entities.values(), key=lambda e: (e.spawn_ms, e.id)):
        if e.is_pet or e.id < ENEMY_ID_MIN or e.pull != pull_index:
            continue
        par = e.parent if ENEMY_ID_MIN <= e.parent < 0xE0000000 else ''
        rows.append([t(e.spawn_ms), 'appear', e.id, e.contentid, e.base, e.max_hp, '', '', '',
                     par, 1 if e.id in real_ids else 0, ''])
    for c in r.casts():
        if p.start_ms <= c.ms <= p.end_ms:
            e = r.entities.get(c.entity_id)
            rows.append([t(c.ms), 'cast_start', c.entity_id, e.contentid if e else '', e.base if e else '',
                         e.max_hp if e else '', c.action, round(c.cast, 1), c.target, '', '', ''])
    for eid in sorted(real_ids):
        e = r.entities[eid]
        for ms, cur, mx in r.hp_series(eid):
            if p.start_ms <= ms <= p.end_ms and mx:
                rows.append([t(ms), 'hp', eid, e.contentid, e.base, mx, '', '', '',
                             round(cur * 100.0 / mx, 1), cur, ''])
    kind, pct = pull_result(r, pull_index, min_hits)
    rows.append([t(p.end_ms), kind, '', '', '', '', '', '', '', '' if pct is None else pct, '', ''])
    order = {'appear': 0, 'cast_start': 1, 'hp': 2, 'wipe': 3, 'clear': 3}
    rows.sort(key=lambda x: (x[0], order[x[1]]))
    return [LOG_COLUMNS] + rows


def log_filename(r: Replay, pull_index: int) -> str:
    """<日時>.csv（交戦開始の日時。英数字と _ のみ）"""
    p = r.pulls[pull_index]
    dt = r.recorded_at + datetime.timedelta(milliseconds=p.t0_ms)
    return '%s_P%d.csv' % (dt.strftime('%Y%m%d_%H%M%S'), pull_index + 1)


def write_log_csvs(replays: list[Replay], out_dir: str, analysis: Analysis | None = None,
                   min_hits: int = 10) -> list[str]:
    """
    out_dir/logs/<mapid>/<日時>_P<n>.csv に書き出す。analysis を渡すと、解析に使ったプルだけ。
    """
    use = None
    if analysis is not None:
        use = {(p.replay, p.index) for p in analysis.pulls}
    paths = []
    for ri, r in enumerate(replays):
        d = os.path.join(out_dir, 'logs', str(r.mapid if r.mapid is not None else 0))
        os.makedirs(d, exist_ok=True)
        for p in r.pulls:
            if use is not None and (ri, p.index) not in use:
                continue
            path = os.path.join(d, log_filename(r, p.index))
            with open(path, 'w', encoding=ENCODING, newline='') as f:
                w = _writer(f)
                for row in log_rows(r, p.index, min_hits):
                    w.writerow(row)
            paths.append(path)
    return paths
