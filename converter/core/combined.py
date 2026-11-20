"""
core/combined.py — リプレイと記録モードのログを組にして、1 つの材料にする（スレッド #8）

同じ戦闘をリプレイと記録モードの両方で残したとき、プルどうしを組にして、それぞれの得意なところを使う。
  リプレイから … 詠唱の時刻（ミリ秒）・詠唱時間・対象、本体と発射役の見分け（bNpcBase）、攻撃を受けた敵（本物の敵）
  記録ログから … 秒数の基準（アドオンの戦闘開始＝ログの t = 0）、ターゲット不可（フェーズの区切りの候補）、
                 技名・敵の名前、clear・wipe と残り HP

  srcs, pairs = combine(replays, logs)
  an = analyze(srcs)

  srcs  … analyze に渡す材料。まずリプレイ（ReplayWithLogs。組になったプルは記録ログの t = 0 に合わせる）、
          その後に組にならなかった記録ログ（LogWithBases。敵の bNpcBase をリプレイから補う）
  pairs … 組の一覧（画面に出す）

組にする方法
  1. 時刻：リプレイのヘッダーの時刻（録画開始。UNIX 時刻をこの PC の現地の時刻に）＋ プルの交戦開始 と、
     記録ログのファイル名の時刻（戦闘開始）が PAIR_WINDOW_S 秒以内、mapid が同じ。
     1 つも組にならないときだけ、ちょうど何時間かの差（時間帯の設定の違い）を試し、全部の組で同じ差を使う（_match）
  2. 詠唱：記録ログの詠唱（t ≥ 0 の最初の CHECK_CASTS 回）それぞれに、リプレイの同じ contentid・アクションの詠唱で一番近いものを探し、
     （リプレイの時刻 − ログの秒数）の中央値を「ログの t = 0 にあたるリプレイの時刻」にする。
     MIN_MATCH 回以上見つかり、ばらつき（中央値からのずれの中央値）が MAX_MAD_MS 以内なら組にする
組にならなかったリプレイのプルは、同じ戦闘（交戦開始で最初に攻撃を受けた敵の contentid）の組の
「ログの t = 0 − 交戦開始」の中央値だけずらす（同じ戦闘の組が無ければずらさない）。
ずれは戦闘ごとに違う（ミストウェイク：1 ボス約 0 秒・2 ボス約 −1.0 秒・3 ボス約 −1.9 秒）。
"""
from __future__ import annotations

import copy
import datetime
import os
import re
import statistics

from .replay import ENEMY_ID_MIN
from .recorder import BASE_MS

PAIR_WINDOW_S = 20.0     # 時刻で組の候補にする幅（秒）
CHECK_CASTS = 12         # 詠唱で確かめる回数（記録ログの最初から）
SEARCH_MS = 3000         # 詠唱を探す幅（時刻から求めた t = 0 の前後）
MIN_MATCH = 3
MAX_MAD_MS = 300


def replay_start(r) -> datetime.datetime:
    """録画を始めた時刻（ヘッダーの UNIX 時刻を、この PC の現地の時刻にする。記録ログのファイル名も現地の時刻）"""
    return datetime.datetime.fromtimestamp(r.timestamp)


def _match(wrapped, logs, hours: int, unpair: set) -> list:
    """
    リプレイのプルと記録ログを組にする（時刻の差から hours 時間を除いて PAIR_WINDOW_S 秒以内 → 詠唱で確かめる）。
    返り値 [(リプレイの番号, プル番号, ログの番号, 時刻の差（秒）, (t0, 見つかった回数, ばらつき))]
    1 つのログは 1 つのプルとだけ組にする（手で外した組のログは、ほかのプルの候補にも戻さず「ログだけ」にする）
    """
    found = []
    used = set()
    for wi, w in enumerate(wrapped):
        r = w._r
        start = replay_start(r)
        for p in w.pulls:
            if p.engage_ms is None:
                continue
            eng_at = start + datetime.timedelta(milliseconds=p.engage_ms)
            best = None
            for li, lg in enumerate(logs):
                if li in used or lg.mapid != r.mapid:
                    continue
                ls = log_start(lg)
                if ls is None:
                    continue
                d = (ls - eng_at).total_seconds() - hours * 3600
                if abs(d) > PAIR_WINDOW_S:
                    continue
                res = _cast_offset(r, p, lg, p.engage_ms + int(d * 1000))
                if res and (best is None or res[1] > best[2][1] or (res[1] == best[2][1] and abs(d) < abs(best[1]))):
                    best = (li, d, res)
            if best is None:
                continue
            found.append((wi, p.index) + best)
            used.add(best[0])
    return found


def log_start(lg) -> datetime.datetime | None:
    """記録ログのファイル名（<YYYYMMDD_HHMMSS>.csv）の時刻＝戦闘開始"""
    m = re.match(r'^(\d{8})_(\d{6})', os.path.basename(lg.path))
    if not m:
        return None
    return datetime.datetime.strptime(m.group(1) + m.group(2), '%Y%m%d%H%M%S')


class ReplayWithLogs:
    """Replay の代わりに analyze に渡す。組になったプルは記録ログの t = 0 を交戦開始にし、記録ログの情報を足す"""

    def __init__(self, replay):
        self._r = replay
        self.pulls = [copy.copy(p) for p in replay.pulls]
        self.logs = {}            # プル番号 → (RecordLog, ログの t = 0 にあたるリプレイの ms)
        self.shift = {}           # プル番号 → 交戦開始からのずらし（ms）
        self.action_names = {}
        self.npc_names = {}
        self.warnings = list(replay.warnings)

    def __getattr__(self, name):            # ほかは Replay と同じ
        return getattr(self._r, name)

    def summary(self) -> dict:
        d = self._r.summary()
        d['paired'] = {p: os.path.basename(lg.path) for p, (lg, _) in self.logs.items()}
        return d

    def targetable_events(self):
        """組になったプルは記録ログのもの、組にならなかったプルはリプレイのもの（ActorControl。スレッド #9）"""
        out = []
        for idx, (lg, t0) in self.logs.items():
            for ms, eid, st in lg.targetable_events():
                out.append((t0 + (ms - BASE_MS), eid, st))
        paired = [self._r.pulls[i] for i in self.logs if i < len(self._r.pulls)]
        for ms, eid, st in self._r.targetable_events():
            if not any(p.start_ms <= ms <= p.end_ms for p in paired):
                out.append((ms, eid, st))
        return sorted(out)


class LogWithBases:
    """組にならなかった記録ログ。敵の bNpcBase（ログでは 0）をリプレイから補う（同じ種類として数えるため）"""

    def __init__(self, log, bases: dict):
        self._l = log
        self.entities = {}
        for eid, e in log.entities.items():
            e2 = copy.copy(e)
            e2.hit_ms = list(e.hit_ms)
            cand = bases.get(e.contentid)
            if cand:
                e2.base = cand['real'] if (e.hit_ms and cand.get('real')) else (cand.get('other') or cand.get('real') or 0)
            self.entities[eid] = e2

    def __getattr__(self, name):
        return getattr(self._l, name)


def _cast_offset(replay, pull, log, t0_guess_ms):
    """ログの t = 0 にあたるリプレイの ms を、詠唱を突き合わせて求める。(ms, 見つかった回数, ばらつき) か None"""
    rc = {}
    for c in replay.casts():
        e = replay.entities.get(c.entity_id)
        if e is None or not (pull.window_start_ms <= c.ms <= pull.end_ms):
            continue
        rc.setdefault((e.contentid, c.action), []).append(c.ms)
    diffs = []
    # 戦闘開始より前（ログの t < 0）の詠唱は、近くの雑魚のものなど、リプレイのプルに入っていないことがあるので使わない
    for c in [c for c in log.casts() if c.ms >= BASE_MS][:CHECK_CASTS]:
        e = log.entities.get(c.entity_id)
        if e is None:
            continue
        rel = c.ms - BASE_MS
        want = t0_guess_ms + rel
        best = None
        for ms in rc.get((e.contentid, c.action), []):
            if abs(ms - want) <= SEARCH_MS and (best is None or abs(ms - want) < abs(best - want)):
                best = ms
        if best is not None:
            diffs.append(best - rel)
    if len(diffs) < MIN_MATCH:
        return None
    med = statistics.median(diffs)
    mad = statistics.median(abs(d - med) for d in diffs)
    if mad > MAX_MAD_MS:
        return None
    return int(round(med)), len(diffs), int(round(mad))


def combine(replays: list, logs: list, unpair: set | None = None):
    """
    unpair … 組にしないリプレイのプル（'<リプレイのファイル名>#<プル番号>'）。手で組を外したもの
    返り値 (srcs, pairs)
    """
    unpair = unpair or set()
    wrapped = [ReplayWithLogs(r) for r in replays]
    first_cid = {}           # (リプレイの番号, プル番号) → 交戦開始で最初に攻撃を受けた敵の contentid
    for wi, w in enumerate(wrapped):
        for p in w.pulls:
            if p.engage_ms is not None:
                e = next((e for e in w._r.entities.values() if p.engage_ms in e.hit_ms), None)
                first_cid[(wi, p.index)] = e.contentid if e else None
    # 組にする：まず時刻の差そのまま（ふつうはこれ）。1 つも組にならなければ、ちょうど何時間かの差（PC の時間帯の設定が
    # 録画したときと違う）を試し、一番多く組になる差を 1 つだけ使う（組ごとに違う差は使わない。1 時間後の同じボスの
    # 別のプルを組にしないため。同じボスのプルは詠唱の順番・間隔が同じなので、詠唱では見分けられない）
    hours = 0
    found = _match(wrapped, logs, 0, unpair)
    if not found:
        best = []
        for h in sorted(range(-14, 15), key=abs):
            if h == 0:
                continue
            f = _match(wrapped, logs, h, unpair)
            if len(f) > len(best):
                hours, best = h, f
        found = best
    used_logs = set()
    pairs = []
    for wi, pidx, li, d, (t0, n, mad) in found:
        w = wrapped[wi]
        r = w._r
        p = w.pulls[pidx]
        key = '%s#%d' % (r.file_name, p.index)
        lg = logs[li]
        entry = dict(key=key, replay=r.file_name, pull=p.index, log=os.path.basename(lg.path),
                     shift_ms=t0 - p.engage_ms, casts=n, mad_ms=mad, paired=key not in unpair,
                     result=lg.result, pct=lg.end_pct, hours=hours)
        pairs.append(entry)
        if key in unpair:
            continue
        used_logs.add(li)
        w.logs[p.index] = (lg, t0)
        w.shift[p.index] = t0 - p.engage_ms
        p.engage_ms = t0
        w.action_names.update({k: v for k, v in lg.action_names.items() if k not in w.action_names})
        w.npc_names.update({k: v for k, v in lg.npc_names.items() if k not in w.npc_names})
    if hours and wrapped:
        wrapped[0].warnings.append('記録ログの時刻が、リプレイの時刻とちょうど %d 時間ずれていました（PC の時間帯の設定が、'
                                   '録画したときと違う？）。%d 時間ずらして組にしました' % (hours, hours))
    # 組にならなかったリプレイのプル：同じ戦闘の組のずらしの中央値だけずらす
    by_cid = {}
    for wi, w in enumerate(wrapped):
        for idx, sh in w.shift.items():
            by_cid.setdefault(first_cid.get((wi, idx)), []).append(sh)
    for wi, w in enumerate(wrapped):
        for p in w.pulls:
            if p.index in w.logs or p.engage_ms is None:
                continue
            cid = first_cid.get((wi, p.index))
            lst = by_cid.get(cid) if cid is not None else None
            if not lst:
                continue
            typical = int(round(statistics.median(lst)))
            p.engage_ms += typical
            w.shift[p.index] = typical
            w.warnings.append('P%d は記録ログと組になりませんでした。秒数の基準は、同じ戦闘（敵 %d）の組のずれ（%+.2f 秒）で推し量りました'
                              % (p.index + 1, cid, typical / 1000))
    # 組にならなかった記録ログ：bNpcBase をリプレイから補う
    bases = {}
    for r in replays:
        for e in r.entities.values():
            if e.is_pet or e.id < ENEMY_ID_MIN or not e.base:
                continue
            b = bases.setdefault(e.contentid, {})
            if len(e.hit_ms) >= 10:
                b.setdefault('real', e.base)
            else:
                b.setdefault('other', e.base)
    rest = [LogWithBases(lg, bases) for li, lg in enumerate(logs) if li not in used_logs]
    for w in wrapped:        # 記録ログの名前を、組にならなかったログからも
        for lg in logs:
            w.action_names.update({k: v for k, v in lg.action_names.items() if k not in w.action_names})
            w.npc_names.update({k: v for k, v in lg.npc_names.items() if k not in w.npc_names})
    return wrapped + rest, pairs
