"""
core/recorder.py — 記録モードのログ CSV（ファイル形式仕様 5 章）を、リプレイと同じ形で読む

  log = RecordLog(path)          … 1 ファイル＝1 プル
  an = analyze([RecordLog(p) for p in paths])

core/analyze.py は Replay の次のものだけを使うので、それをログ CSV から作る（Replay の代わりに渡せる）。
  file_name / mapid / cfc / build_hex / warnings / summary()
  pulls（Pull）/ entities（Entity）/ casts()（Cast）/ hp_series(id)
ほかに、記録ログだけにあるもの：
  targetable_events()  … [(ms, entity_id, state)]（フェーズのきっかけ「ターゲット可否」の材料）
  action_names / npc_names … ログの name 列（技名・敵の名前）

ログとリプレイの違いと、その埋め方
  - 秒数 t は戦闘開始（記録モードの first_hostile など）からの秒数。ms = BASE_MS + t * 1000 とし、
    交戦開始（t0）＝ BASE_MS にする（チャプターは無い。カウントダウン前の 30 秒もファイルに入っている）
  - 「攻撃を受けた時刻」（本物の敵の判定）はログに無い。HP の行で HP が減った時刻を代わりに使い、
    appear の v2 = 1（記録モードが本物の敵と判定した敵）で足りなければ、最初に減った時刻を補って min_hits 回にする
  - bNpcBase はゲーム内では取れない（空）。0 として扱う（本体と発射役は同じ種類 (contentid, 0) になる）
  - 親 ID は取れない（空）。0
"""
from __future__ import annotations

import csv
import os

from .replay import Entity, Cast, Pull, ENEMY_ID_MIN

BASE_MS = 1_000_000        # t = 0（戦闘開始）を表す ms。マイナスの t（戦闘開始前）も正の ms にするため
MIN_HITS = 10              # analyze の min_hits の既定と同じ（本物の敵として扱うのに足りない分を補う）


class RecordLogError(ValueError):
    """記録モードのログ CSV として読めない"""


def _num(s, conv=float):
    s = (s or '').strip()
    if s == '':
        return None
    try:
        return conv(s)
    except ValueError:
        try:
            return conv(float(s))
        except (TypeError, ValueError):
            return None


def is_record_log(path: str) -> bool:
    """記録モードのログ（<日時>.csv）か。_dryrun.csv・_actions.csv・actions_dump は違う"""
    n = os.path.basename(path).lower()
    if not n.endswith('.csv'):
        return False
    stem = n[:-4]
    for suf in ('_dryrun', '_actions', '_debug'):
        if stem.endswith(suf):
            return False
    return not stem.startswith('actions_dump')


class RecordLog:
    def __init__(self, path: str, min_hits: int = MIN_HITS):
        self.path = path
        try:
            with open(path, encoding='utf-8-sig', newline='') as f:
                rows = list(csv.DictReader(f))
        except (OSError, UnicodeDecodeError, csv.Error) as e:
            raise RecordLogError('%s: 読めません（%s）' % (os.path.basename(path), e))
        need = {'t', 'kind', 'entity_id', 'contentid', 'action_id'}
        if not rows or not need.issubset(rows[0].keys()):
            raise RecordLogError('%s: 記録モードのログ CSV ではありません（列 %s が必要）'
                                 % (os.path.basename(path), '・'.join(sorted(need))))
        self.warnings: list[str] = []
        self.rows = []
        for r in rows:
            t = _num(r.get('t'))
            if t is None:
                continue
            r['_ms'] = BASE_MS + int(round(t * 1000))
            r['_t'] = t
            r['_eid'] = _num(r.get('entity_id'), int)
            r['_cid'] = _num(r.get('contentid'), int)
            r['_aid'] = _num(r.get('action_id'), int)
            self.rows.append(r)
        self.rows.sort(key=lambda r: r['_ms'])
        if not self.rows:
            raise RecordLogError('%s: 行がありません' % os.path.basename(path))

        # mapid：combat_start の v1、無ければフォルダ名
        self.mapid = None
        for r in self.rows:
            if r['kind'] == 'combat_start':
                self.mapid = _num(r.get('v1'), int)
                if self.mapid:
                    break
        if not self.mapid:
            folder = os.path.basename(os.path.dirname(os.path.abspath(path)))
            self.mapid = int(folder) if folder.isdigit() else None
        self.cfc = None
        self.build_hex = 'recorder'

        # 秒数の基準（t = 0 の行の種類）
        self.t0_source = 'combat_start'
        for kind in ('first_action', 'first_hit', 'combat_start'):
            if any(r['kind'] == kind and abs(r['_t']) < 0.05 for r in self.rows):
                self.t0_source = kind
                if kind == 'first_action':
                    fa = next(r for r in self.rows if r['kind'] == 'first_action')
                    if (fa.get('v1') or '').strip() == '1':
                        self.t0_source = 'first_hostile'
                break
        end_row = next((r for r in self.rows if r['kind'] in ('wipe', 'clear')), None)
        self.result = end_row['kind'] if end_row else '?'
        self.end_pct = _num(end_row.get('v1')) if end_row else None
        end_ms = end_row['_ms'] if end_row else self.rows[-1]['_ms']
        start_ms = min(self.rows[0]['_ms'], BASE_MS)
        self.pulls = [Pull(0, start_ms, max(end_ms, BASE_MS + 1), start_ms, engage_ms=BASE_MS)]

        # エンティティ
        self.entities: dict[int, Entity] = {}
        self.npc_names: dict[int, str] = {}
        self.action_names: dict[int, str] = {}
        real = set()
        hp_rows = {}
        for r in self.rows:
            eid = r['_eid']
            kind = r['kind']
            if eid is not None and eid >= ENEMY_ID_MIN and r['_cid'] is not None and eid not in self.entities:
                self.entities[eid] = Entity(id=eid, base=0, contentid=r['_cid'],
                                            max_hp=_num(r.get('max_hp'), int) or 0, spawn_ms=r['_ms'],
                                            owner=0, parent=0, pull=0)
            if kind == 'appear' and (r.get('v2') or '').strip() == '1' and eid is not None:
                real.add(eid)
            if kind == 'hp' and eid in self.entities:
                hp_rows.setdefault(eid, []).append(r)
            name = (r.get('name') or '').strip()
            if name and r['_cid'] is not None and kind in ('appear', 'targetable', 'hp'):
                self.npc_names.setdefault(r['_cid'], name)
            if name and r['_aid'] is not None and kind in ('cast_start', 'cast_end'):
                self.action_names.setdefault(r['_aid'], name)
            e = self.entities.get(eid)
            if e is not None:
                mh = _num(r.get('max_hp'), int)
                if mh and mh > e.max_hp:
                    e.max_hp = mh

        # HP の列と「攻撃を受けた時刻」の代わり（HP が減った時刻）
        self._hp = {}
        for eid, lst in hp_rows.items():
            ser, prev = [], None
            e = self.entities[eid]
            for r in lst:
                cur = _num(r.get('v2'), int)
                mx = _num(r.get('max_hp'), int) or e.max_hp
                if cur is None:
                    continue
                ser.append((r['_ms'], cur, mx))
                if prev is not None and cur < prev:
                    e.hit_ms.append(r['_ms'])
                prev = cur
            self._hp[eid] = ser
        for eid in real:
            e = self.entities.get(eid)
            if e is None:
                continue
            if len(e.hit_ms) < min_hits:
                fill = e.hit_ms[0] if e.hit_ms else max(BASE_MS, e.spawn_ms)
                e.hit_ms = sorted(e.hit_ms + [fill] * (min_hits - len(e.hit_ms)))
        if not real:
            self.warnings.append('本物の敵（appear の v2 = 1）がいません')

        self._casts = []
        for r in self.rows:
            if r['kind'] != 'cast_start' or r['_eid'] is None or r['_aid'] is None:
                continue
            if r['_eid'] not in self.entities:
                continue
            self._casts.append(Cast(r['_ms'], r['_eid'], r['_aid'], _num(r.get('cast')) or 0.0,
                                    _num(r.get('target_id'), int) or 0))
        self._targetable = [(r['_ms'], r['_eid'], (r.get('v1') or '').strip() == '1')
                            for r in self.rows if r['kind'] == 'targetable' and r['_eid'] is not None]

    # ------------------------------------------------------------------ Replay と同じ形
    @property
    def file_name(self) -> str:
        return os.path.basename(self.path)

    @property
    def recorded_at(self) -> str:
        stem = os.path.splitext(self.file_name)[0]
        if len(stem) >= 15 and stem[8] == '_':
            return '%s-%s-%s %s:%s:%s' % (stem[0:4], stem[4:6], stem[6:8], stem[9:11], stem[11:13], stem[13:15])
        return ''

    @property
    def total_ms(self) -> int:
        return self.rows[-1]['_ms'] - self.rows[0]['_ms']

    def summary(self) -> dict:
        p = self.pulls[0]
        return dict(file=self.file_name, build='recorder', format=0, cfc=None, mapid=self.mapid,
                    recorded_at=self.recorded_at, total_sec=round(self.total_ms / 1000, 1), packets=len(self.rows),
                    pulls=[p.to_dict()], opcodes={}, warnings=list(self.warnings),
                    t0_source=self.t0_source, result=self.result)

    def casts(self, include_pets: bool = False) -> list[Cast]:
        return list(self._casts)

    def hp_series(self, entity_id: int) -> list[tuple[int, int, int]]:
        return self._hp.get(entity_id, [])

    def targetable_events(self) -> list[tuple[int, int, bool]]:
        return list(self._targetable)

    def fight_sec(self) -> float:
        return round((self.pulls[0].end_ms - BASE_MS) / 1000, 1)
