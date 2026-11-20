"""
core/analyze.py — 複数プルの比較とタイムライン下書きの材料づくり

UI に依存しない純粋な Python。入口は analyze(replays, options) / analyze_files(paths, **opts)。
結果の Analysis は to_dict() で JSON にでき、pywebview の画面からそのまま使える。

【考え方】
  1. 敵の種類 (contentid, bNpcBase) ごとに「本物の敵か（パーティから攻撃を受けたか）」を判定する
  2. フェーズ移行の候補を探す
       - hp_stop          : 本物の敵の HP が減らなくなった（その後もパーティは別の敵を攻撃している）
       - new_enemy_action : 最初の敵とは別の本物の敵が、戦闘の途中で行動（詠唱）を始めた
       - new_enemy_hit    : 別の本物の敵が、初めて攻撃を受けた（参考）
     new_enemy_action を採用して、プルをフェーズに分ける（時刻はフェーズ開始からの秒数になる）
  3. 詠唱を「瞬間」にまとめる（同じ詠唱者の種類が 1 秒以内に使ったものは 1 つ。複数アクションは集合）
  4. プル間の対応付けは「何回目か」ではなく「時刻の近さ」で行い、「枠（slot）」を作る
  5. 枠を分類する
       stable  : どのプルでも同じアクション
       partial : 同じアクションだが、届いたプルの一部にしか出ていない
       branch  : 同じ時刻に、プルによって別のアクション（ランダム分岐）
       swap    : 近くの 2 つの枠で、アクションの順番がプルによって入れ替わる
  6. 同期点の候補を提案する
       - before_unstable : ばらつきの大きい枠の直前の、安定したイベント
       - interval        : 同期点の間隔が max_sync_gap 秒を超えないように置く安定したイベント
"""
from __future__ import annotations

import math
import statistics
from dataclasses import dataclass, field, asdict
from typing import Iterable

from .replay import Replay, Entity, ENEMY_ID_MIN


# ====================================================================== 設定

@dataclass
class AnalyzeOptions:
    min_hits: int = 10              # これ以上攻撃を受けた個体がいる種類を「本物の敵」とする
    min_pull_sec: float = 10.0      # これより短いプルは無視する
    pulls: list | None = None       # 使うプルのラベル（例 ["P2", "P4"]）。None なら全部
    encounter: int | None = None    # 解析する戦闘（最初に戦う本物の敵の contentid）。None なら自動
    merge_sec: float = 1.0          # 同じ詠唱者の種類の詠唱を 1 つの「瞬間」にまとめる幅
    align_tol: float = 2.5          # プル間で同じ枠とみなす時刻の差
    swap_window: float = 30.0       # 順番入れ替わりを探す 2 枠の最大間隔
    reach_margin: float = 5.0       # プルが「その時刻まで届いた」とみなすのに必要な余裕（全滅直前は除く）
    anchor_spread: float = 0.5      # 同期点にできる枠のばらつきの上限
    unstable_spread: float = 1.0    # これより大きいばらつきの枠を「不安定」とする
    max_sync_gap: float = 60.0      # 同期点の間隔の目安
    hp_stop_min_sec: float = 15.0   # HP が止まったとみなす最短時間
    phase_hp_ratio: float = 0.3     # フェーズの主役とみなす最大HP（最も大きい本物の敵との比）
    new_enemy_min_sec: float = 5.0  # 戦闘開始からこれより後に行動を始めた敵を「途中から」とする
    split_phases: bool = True       # new_enemy_action の候補でフェーズを分けるか
    phase_splits: list | None = None  # 手で決めたフェーズの区切り（v0.4。画面から）。None でなければ自動の区切りの代わりに使う
                                    #   {'type': 'cast_start', 'contentid': 6221, 'action': [8588], 'at': 21.4}
                                    #   {'type': 'targetable', 'contentid': 6221, 'state': False, 'at': 21.4}
                                    #   at＝戦闘開始からの秒数の目安。各プルで at の split_before 秒前〜split_after 秒後の最初のもの
    split_before: float = 3.0
    split_after: float = 30.0       # HP で移る戦闘は火力でずれる（スサノオのターゲット不可：22.8〜42.3 秒）
    time_pulls: list | None = None  # 秒数を決めるプル（ラベル）。イベントがこのどれかに出ていれば、t・ばらつきはそのプルだけで決める。
                                    #   リプレイ＋記録ログ：組になったプル（記録ログの t = 0。組にならなかったリプレイのプルは
                                    #   交戦開始の取り方で 1 秒ほどずれる）。イベント・分岐・入れ替わりを見つけるのには全部のプルを使う
    time_zero: str = 'engage'       # 秒数の基準：'engage'＝最初にパーティが攻撃した時刻（アドオンの戦闘開始に合わせる）
                                    #             'chapter'＝チャプター開始（カウントダウン開始。旧方式）


# ====================================================================== 結果の型

@dataclass
class PullRef:
    label: str                      # "P1"（リプレイ 1 件）/ "R2P1"（複数件）
    replay: int
    index: int
    start_ms: int                   # チャプター開始（詠唱などを探す範囲の始まり）
    end_ms: int
    file: str
    t0_ms: int = 0                  # 秒数の基準（既定は交戦開始。AnalyzeOptions.time_zero）
    engage_offset: float | None = None   # チャプター開始から交戦開始までの秒数

    @property
    def duration(self) -> float:
        return (self.end_ms - self.start_ms) / 1000.0

    @property
    def fight_sec(self) -> float:
        """秒数の基準からプルの終わりまで"""
        return (self.end_ms - self.t0_ms) / 1000.0


@dataclass
class EnemyKind:
    contentid: int
    base: int
    key: str                        # タイムラインの entities のキー
    real: bool                      # パーティから攻撃を受けた
    max_hp: int
    hits: int
    instances: int
    attached: bool                  # 親（ボス）付きの発射役
    first_t: float | None           # 最初の行動（詠唱か被弾）の秒数の中央値（戦闘開始から）
    casts: int = 0


HP_STOP_SPREAD = 1.0     # HP が止まった % のプル間の差がこれ以下なら「HP で移る」とみなす（スレッド #9）
HP_STOP_DEAD = 1.0       # HP が止まった % がどのプルでもこれより下なら、倒しただけ（HP で分ける候補にしない）


@dataclass
class PhaseCandidate:
    kind: str                       # 'hp_stop' / 'new_enemy_action' / 'new_enemy_hit'
    contentid: int
    base: int
    entity: str                     # entities のキー
    actions: list                   # new_enemy_action の最初のアクション（プルで違えば複数）
    times: dict                     # プルのラベル -> 戦闘開始からの秒数
    ms: dict = field(default_factory=dict)   # プルのラベル -> 戦闘開始からのミリ秒（丸めない値）
    adopted: bool = False           # フェーズ分割に採用したか
    phase: str | None = None
    hp: dict = field(default_factory=dict)   # hp_stop：プルのラベル -> 止まったときの HP%（スレッド #9。HP で区切る候補）
    nths: dict = field(default_factory=dict)  # untargetable / retargetable：プルのラベル -> 戦闘開始から同じ向きに変わった何回目か

    @property
    def nth(self) -> int | None:
        """どのプルでも同じ何回目なら、その数（「どこで来ても」で区切るときに使う）"""
        v = set(self.nths.values())
        return v.pop() if len(v) == 1 else None

    @property
    def hp_percent(self) -> float | None:
        """
        HP で区切るときの %：止まった HP% の一番高いもの（小数第 1 位に切り上げ）。どのプルでもそこで止まる前に下回る。
        プルによって止まった HP% が HP_STOP_SPREAD より違うなら None（HP ではなく時刻で移っている。1232 は 16.6% と 20.4%）
        """
        if not self.hp:
            return None
        if max(self.hp.values()) - min(self.hp.values()) > HP_STOP_SPREAD:
            return None
        if max(self.hp.values()) < HP_STOP_DEAD:      # ほぼ 0%：倒した（フェーズ移行ではない）
            return None
        return math.ceil(max(self.hp.values()) * 10 - 1e-9) / 10

    @property
    def median(self) -> float:
        return round(statistics.median(self.times.values()), 1)


@dataclass
class Moment:
    pull: str
    ms: int
    t: float                        # フェーズ開始からの秒数
    t_combat: float                 # 戦闘開始からの秒数
    source: tuple                   # (contentid, base)
    actions: dict                   # アクションID -> 回数
    cast: float                     # 最長の詠唱時間
    entity_ids: list
    targets: list
    casts: dict = field(default_factory=dict)   # アクションID -> 詠唱時間（同じ瞬間の別のアクションは詠唱時間が違う）


@dataclass
class Slot:
    id: str
    phase: str
    source: tuple
    entity: str
    moments: dict = field(default_factory=dict)   # pull label -> Moment
    kind: str = 'stable'
    reached: list = field(default_factory=list)
    partner: str | None = None
    action_set: tuple = ()          # タイムラインに書くアクション（swap は割り当て）
    event_id: str = ''
    event_name: str = ''
    sync: str | None = None         # 同期点の候補なら理由
    nth: int | None = None
    sync_ok: bool = False           # 同期点にできるか（アクションが 1 つで、何回目かがプル間で同じ）
    sync_nth: int | None = None     # 同期点にしたときの nth（戦闘で 1 回だけなら None）
    parts: list = field(default_factory=list)   # タイムラインに書くイベント（v0.4。下の _name_events）
    prefer: frozenset = frozenset()             # 秒数（t・ばらつき）を決めるプル（AnalyzeOptions.time_pulls）
    real_caster: bool = False

    @property
    def times(self) -> dict:
        """プルごとの秒数。秒数を決めるプル（prefer）に出ていれば、そのプルだけ（AnalyzeOptions.time_pulls）"""
        ms = self.moments
        if self.prefer:
            pm = {p: m for p, m in ms.items() if p in self.prefer}
            if pm:
                ms = pm
        return {p: m.t for p, m in ms.items()}

    @property
    def t(self) -> float:
        return round(statistics.median(self.times.values()), 1)

    @property
    def spread(self) -> float | None:
        ts = list(self.times.values())
        return round(max(ts) - min(ts), 1) if len(ts) > 1 else None

    @property
    def cast(self) -> float:
        return round(statistics.median(m.cast for m in self.moments.values()), 1)

    @property
    def seen(self) -> int:
        return len(self.moments)

    def sets(self) -> dict:
        return {p: tuple(sorted(m.actions)) for p, m in self.moments.items()}

    @property
    def all_actions(self) -> tuple:
        s = set()
        for m in self.moments.values():
            s.update(m.actions)
        return tuple(sorted(s))

    def to_dict(self, pulls: list[str]) -> dict:
        sets = self.sets()
        return dict(
            id=self.id, phase=self.phase, event_id=self.event_id, name=self.event_name,
            kind=self.kind, t=self.t, spread=self.spread, cast=self.cast,
            entity=self.entity, contentid=self.source[0], base=self.source[1],
            real_caster=self.real_caster, actions=list(self.action_set), all_actions=list(self.all_actions),
            seen=self.seen, reached=len(self.reached), partner=self.partner, sync=self.sync, nth=self.nth,
            sync_ok=self.sync_ok, sync_nth=self.sync_nth, parts=list(self.parts),
            t_combat=round(statistics.median(m.t_combat for m in self.moments.values()), 1),
            by_pull={p: (dict(t=self.moments[p].t, actions=list(sets[p]),
                              count=sum(self.moments[p].actions.values()))
                         if p in self.moments else None) for p in pulls},
        )


@dataclass
class Phase:
    id: str
    name: str
    trigger: dict
    starts: dict                    # pull label -> 戦闘開始からの ms（相対）
    durations: dict                 # pull label -> そのプルでのフェーズの長さ（秒）
    slots: list = field(default_factory=list)


@dataclass
class Encounter:
    contentid: int                  # そのプルで最初に戦う本物の敵
    base: int
    pulls: list                     # プルのラベル
    total_sec: float
    selected: bool = False


@dataclass
class Analysis:
    replays: list
    mapid: int | None
    cfc: int | None
    builds: list
    pulls: list
    kinds: list
    entities: dict                  # key -> {contentid, name, ...}（タイムラインの entities 用）
    phase_candidates: list
    phases: list
    warnings: list
    options: AnalyzeOptions
    encounters: list = field(default_factory=list)

    # ---- 便利関数（テスト・UI 用）
    def all_slots(self) -> list[Slot]:
        return [s for ph in self.phases for s in ph.slots]

    def real_kinds(self) -> list[EnemyKind]:
        return [k for k in self.kinds if k.real]

    def branches(self) -> list[Slot]:
        return [s for s in self.all_slots() if s.kind == 'branch']

    def swaps(self) -> list[Slot]:
        return [s for s in self.all_slots() if s.kind == 'swap']

    def sync_candidates(self) -> list[Slot]:
        return [s for s in self.all_slots() if s.sync]

    def pull_labels(self) -> list[str]:
        return [p.label for p in self.pulls]

    def to_dict(self) -> dict:
        labels = self.pull_labels()
        return dict(
            replays=self.replays, mapid=self.mapid, cfc=self.cfc, builds=self.builds,
            pulls=[dict(label=p.label, file=p.file, index=p.index, duration=round(p.duration, 1),
                        engage_offset=p.engage_offset, fight_sec=round(p.fight_sec, 1))
                   for p in self.pulls],
            kinds=[asdict(k) for k in self.kinds],
            entities=self.entities,
            phase_candidates=[dict(asdict(c), median=c.median) for c in self.phase_candidates],
            phases=[dict(id=ph.id, name=ph.name, trigger=ph.trigger,
                         starts={k: round(v / 1000, 1) for k, v in ph.starts.items()},
                         durations={k: round(v, 1) for k, v in ph.durations.items()},
                         slots=[s.to_dict(labels) for s in ph.slots]) for ph in self.phases],
            warnings=self.warnings,
            options=asdict(self.options),
            encounters=[asdict(e) for e in self.encounters],
        )


# ====================================================================== 本体

def analyze_files(paths: Iterable[str], options: AnalyzeOptions | None = None, **kw) -> Analysis:
    """ファイル名から読み込んで解析する（UI・CLI の入口）"""
    store = kw.pop('store', None)
    replays = [Replay(p, store=store) for p in paths]
    return analyze(replays, options or AnalyzeOptions(**kw))


def analyze(replays: list[Replay], options: AnalyzeOptions | None = None) -> Analysis:
    opt = options or AnalyzeOptions()
    warnings = []
    for r in replays:
        warnings += ['%s: %s' % (r.file_name, w) for w in r.warnings]

    mapids = sorted({r.mapid for r in replays if r.mapid is not None})
    if len(mapids) > 1:
        # どのファイルがどの mapid か（リプレイと記録ログを分けて書く。スレッド #9：前は記録ログでも「リプレイが」と書いていた）
        by_map = {}
        for r in replays:
            if r.mapid is None:
                continue
            kind = '記録ログ' if getattr(r, 'build_hex', None) == 'recorder' else 'リプレイ'
            by_map.setdefault(r.mapid, []).append('%s %s' % (kind, r.file_name))
        warnings.append('別のコンテンツ（mapid %s）のファイルが混ざっています：%s' % (
            mapids, ' ／ '.join('%d = %s' % (m, '、'.join(by_map[m])) for m in mapids)))

    # ---------------------------------------------------------------- プル
    pulls: list[PullRef] = []
    multi = len(replays) > 1
    for ri, r in enumerate(replays):
        for p in r.pulls:
            label = ('R%dP%d' % (ri + 1, p.index + 1)) if multi else ('P%d' % (p.index + 1))
            if p.duration < opt.min_pull_sec:
                continue
            if opt.pulls and label not in opt.pulls:
                continue
            t0 = p.t0_ms if opt.time_zero == 'engage' else p.start_ms
            if opt.time_zero == 'engage' and p.engage_ms is None:
                warnings.append('%s: 攻撃の記録が無いので、チャプター開始を秒数の基準にしました' % label)
            # 交戦開始がチャプター開始より前のこともある（ダンジョン）。詠唱を探す範囲は早い方から
            pulls.append(PullRef(label, ri, p.index, min(p.start_ms, t0), p.end_ms, r.file_name,
                                 t0, p.engage_offset))

    # ---------------------------------------------------------------- 戦闘（エンカウント）の選択
    # 1 つのリプレイに別の戦闘（例：前座のボスと本命のボス）のプルが混ざることがある。
    # プルごとに「最初に戦った本物の敵」を求め、同じ敵のプルだけをまとめて解析する。
    encounters = _group_encounters(replays, pulls, opt)
    in_groups = {lbl for e in encounters for lbl in e.pulls}
    skipped = [p.label for p in pulls if p.label not in in_groups]
    if skipped and encounters:
        warnings.append('攻撃された敵がいないプルを除外しました：%s' % '/'.join(skipped))
    if encounters:
        if opt.encounter is not None:
            sel = [e for e in encounters if e.contentid == opt.encounter]
            if not sel:
                warnings.append('encounter %d のプルがありません' % opt.encounter)
        else:
            sel = [max(encounters, key=lambda e: e.total_sec)]
        for e in sel:
            e.selected = True
        if len(encounters) > 1:
            warnings.append('別の戦闘のプルが混ざっています：%s。解析したのは %s（encounter で選べます）'
                            % (', '.join('%d(%s)' % (e.contentid, '/'.join(e.pulls)) for e in encounters),
                               ', '.join(str(e.contentid) for e in sel)))
        keep = {lbl for e in sel for lbl in e.pulls}
        pulls = [p for p in pulls if p.label in keep]

    # ---------------------------------------------------------------- 詠唱をプルごとに
    casts_by_pull = {}
    for pr in pulls:
        r = replays[pr.replay]
        lst = []
        for c in r.casts():
            if pr.start_ms <= c.ms <= pr.end_ms:
                e = r.entities.get(c.entity_id)
                if e is None:
                    continue
                lst.append((c, e))
        casts_by_pull[pr.label] = lst

    # ---------------------------------------------------------------- 敵の種類
    kinds = _collect_kinds(replays, pulls, casts_by_pull, opt)
    kind_by_src = {(k.contentid, k.base): k for k in kinds}
    entities = _assign_keys(kinds, replays, pulls, opt, warnings)
    key_of_cid = {}
    for key, ent in entities.items():
        if 'select' not in ent or ent['select'].get('count') == 'all':
            key_of_cid.setdefault(ent['contentid'], key)
    for k in kinds:
        k.key = key_of_cid.get(k.contentid, k.key)

    # ---------------------------------------------------------------- フェーズ
    cands = _phase_candidates(replays, pulls, casts_by_pull, kinds, kind_by_src, opt)
    cands += _targetable_candidates(replays, pulls, kinds, key_of_cid, opt)
    if opt.phase_splits is not None:
        phases = _user_phases(replays, pulls, casts_by_pull, key_of_cid, opt, warnings)
    else:
        phases = _split_phases(pulls, cands, casts_by_pull, opt, warnings)

    # ---------------------------------------------------------------- 枠
    for ph in phases:
        ph.slots = _build_slots(ph, phases, pulls, casts_by_pull, kind_by_src, key_of_cid, opt)
        if opt.time_pulls:
            pref = frozenset(opt.time_pulls)
            for s in ph.slots:
                s.prefer = pref
        _classify(ph, pulls, opt)
        _name_events(ph)
        _sync_candidates(ph, pulls, casts_by_pull, opt)

    return Analysis(
        replays=[r.summary() for r in replays],
        mapid=mapids[0] if mapids else None,
        cfc=replays[0].cfc if replays else None,
        builds=sorted({r.build_hex for r in replays}),
        pulls=pulls, kinds=kinds, entities=entities,
        phase_candidates=cands, phases=phases, warnings=warnings, options=opt,
        encounters=encounters,
    )


# ====================================================================== プル内の活動

def _hits_in(e: Entity, pr) -> list:
    """そのプルの時間内に受けた被弾の時刻"""
    return [m for m in e.hit_ms if pr.start_ms <= m <= pr.end_ms]


def _real_in(r, pr, opt) -> list:
    """
    そのプルの時間内に min_hits 以上攻撃を受けた個体。
    ID の持ち主で判定しない理由：ダンジョンなどでは全滅してもボスが同じ ID のまま残り、
    複数のプルにまたがって戦うため。
    """
    return [e for e in r.entities.values()
            if not e.is_pet and e.id >= ENEMY_ID_MIN and len(_hits_in(e, pr)) >= opt.min_hits]


# ====================================================================== 戦闘のまとまり

def _pull_primary(r, pr, opt):
    """そのプルで最初に行動した、主役級（最大HPが大きい）の本物の敵。(個体, 最初の活動 ms)"""
    insts = _real_in(r, pr, opt)
    if not insts:
        return None, None
    top = max(e.max_hp for e in insts)
    major = [e for e in insts if e.max_hp >= top * opt.phase_hp_ratio]

    def first(e):
        hs = _hits_in(e, pr)
        return hs[0] if hs else 1 << 62
    e = min(major, key=first)
    return e, first(e)


def _group_encounters(replays, pulls, opt) -> list[Encounter]:
    groups = {}
    for pr in pulls:
        e, _ = _pull_primary(replays[pr.replay], pr, opt)
        if e is None:
            continue        # 攻撃された敵がいないプル（戦闘が始まらなかった等）は使わない
        key = (e.contentid, e.base)
        g = groups.setdefault(key, Encounter(key[0], key[1], [], 0.0))
        g.pulls.append(pr.label)
        g.total_sec = round(g.total_sec + pr.duration, 1)
    return sorted(groups.values(), key=lambda g: pulls.index(next(p for p in pulls if p.label == g.pulls[0])))


# ====================================================================== 敵の種類

def _collect_kinds(replays, pulls, casts_by_pull, opt) -> list[EnemyKind]:
    acc = {}
    first = {}   # src -> [各プルでの最初の行動の秒数]
    for pr in pulls:
        r = replays[pr.replay]
        seen_first = {}
        casters = {e.id for c, e in casts_by_pull[pr.label]}
        for e in r.entities.values():
            if e.is_pet or e.id < ENEMY_ID_MIN:
                continue
            hs = _hits_in(e, pr)
            # このプルで活動した個体、または活動が無くこのプルに出現した個体（攻撃されないダミーなど）
            if not hs and e.id not in casters and not (e.pull == pr.index and not e.hit_ms):
                continue
            src = (e.contentid, e.base)
            a = acc.setdefault(src, dict(max_hp=0, hits=0, inst=0, attached=0, casts=0))
            a['max_hp'] = max(a['max_hp'], e.max_hp)
            a['hits'] += len(hs)
            a['inst'] += 1
            a['attached'] += 1 if e.parent >= ENEMY_ID_MIN and e.parent != 0xE0000000 else 0
            if hs:
                seen_first[src] = min(seen_first.get(src, 1 << 62), hs[0])
        for c, e in casts_by_pull[pr.label]:
            src = (e.contentid, e.base)
            if src in acc:
                acc[src]['casts'] += 1
            seen_first[src] = min(seen_first.get(src, 1 << 62), c.ms)
        for src, ms in seen_first.items():
            first.setdefault(src, []).append((ms - pr.t0_ms) / 1000)

    # 本物の判定は「個体」単位の被弾数で行う（種類の合計ではない）
    real = set()
    for pr in pulls:
        for e in _real_in(replays[pr.replay], pr, opt):
            real.add((e.contentid, e.base))

    kinds = []
    for src, a in acc.items():
        f = first.get(src)
        kinds.append(EnemyKind(
            contentid=src[0], base=src[1], key='', real=src in real, max_hp=a['max_hp'],
            hits=a['hits'], instances=a['inst'], attached=a['attached'] * 2 > a['inst'],
            first_t=round(statistics.median(f), 1) if f else None, casts=a['casts']))
    kinds.sort(key=lambda k: (not k.real, k.first_t if k.first_t is not None else 1e9, k.contentid, k.base))
    return kinds


def _assign_keys(kinds, replays, pulls, opt, warnings) -> dict:
    """
    タイムラインの entities を作る。キーは contentid 単位（アドオンは contentid で照合するため）。
      本物の敵       : boss, boss2, boss3 …（最初に行動した順）
      詠唱だけする敵 : npc<contentid>（発射役など。詠唱の照合用）
    同じ contentid の本物の敵が同時に 2 体以上いるとき（双子）は、_1/_2 の index 指定キーも作る。
    """
    entities = {}
    n = 0
    real_cids = []
    for k in kinds:
        if k.real and k.contentid not in real_cids:
            real_cids.append(k.contentid)
    for cid in real_cids:
        n += 1
        key = 'boss' if n == 1 else 'boss%d' % n
        bases = sorted({k.base for k in kinds if k.contentid == cid and k.real})
        hp = max(k.max_hp for k in kinds if k.contentid == cid and k.real)
        ent = dict(contentid=cid, name='敵 %d' % cid, bases=bases, max_hp=hp, real=True)
        sim = _max_simultaneous(replays, pulls, cid, opt)
        if sim >= 2:
            ent['select'] = {'count': 'all'}
            entities[key] = ent
            for i in range(1, sim + 1):
                entities['%s_%d' % (key, i)] = dict(contentid=cid, name='敵 %d (%d体目)' % (cid, i),
                                                    bases=bases, max_hp=hp, real=True, select={'index': i})
            warnings.append('contentid %d の本物の敵が同時に %d 体います（%s_1〜_%d を作成）' % (cid, sim, key, sim))
        else:
            entities[key] = ent
    for k in kinds:
        if k.contentid in real_cids or k.casts == 0:
            continue
        key = 'npc%d' % k.contentid
        if key not in entities:
            entities[key] = dict(contentid=k.contentid, name='詠唱する敵 %d' % k.contentid,
                                 bases=[k.base], max_hp=k.max_hp, real=False)
        elif k.base not in entities[key]['bases']:
            entities[key]['bases'].append(k.base)
        k.key = key
    for k in kinds:
        if not k.key:
            k.key = ''
    return entities


def _max_simultaneous(replays, pulls, cid, opt) -> int:
    """同じ contentid の本物の個体が、同じ時間帯に攻撃を受けていた最大数"""
    best = 0
    for pr in pulls:
        r = replays[pr.replay]
        spans = []
        for e in _real_in(r, pr, opt):
            if e.contentid == cid:
                hs = _hits_in(e, pr)
                spans.append((hs[0], hs[-1]))
        for a in spans:
            best = max(best, sum(1 for b in spans if b[0] <= a[1] and a[0] <= b[1]))
    return best


# ====================================================================== フェーズ

def _phase_candidates(replays, pulls, casts_by_pull, kinds, kind_by_src, opt) -> list[PhaseCandidate]:
    real = [k for k in kinds if k.real]
    if not real:
        return []
    top_hp = max(k.max_hp for k in real)
    major = [k for k in real if k.max_hp >= top_hp * opt.phase_hp_ratio]
    primary = min(major, key=lambda k: k.first_t if k.first_t is not None else 1e9)
    groups = {}

    def add(kind, k, action, label, rel_ms, pct=None):
        key = (kind, k.contentid, k.base)
        g = groups.get(key)
        if g is None:
            g = groups[key] = PhaseCandidate(kind, k.contentid, k.base, k.key, [], {})
        if action is not None and action not in g.actions:
            g.actions.append(action)
        if label not in g.times:
            g.times[label] = round(rel_ms / 1000, 1)
            g.ms[label] = rel_ms
            if pct is not None:
                g.hp[label] = round(pct, 2)

    for pr in pulls:
        r = replays[pr.replay]
        insts = [e for e in _real_in(r, pr, opt) if (e.contentid, e.base) in kind_by_src]
        all_hits = sorted(m for e in insts for m in _hits_in(e, pr))

        # hp_stop
        for e in insts:
            k = kind_by_src[(e.contentid, e.base)]
            if k.max_hp < top_hp * opt.phase_hp_ratio:
                continue
            ser = [x for x in r.hp_series(e.id) if pr.start_ms <= x[0] <= pr.end_ms]
            # HP が hp_stop_min_sec 以上減らなかった最初のところ（その間、パーティは別の敵を攻撃している）。
            #   スレッド #9：最後に止まったところだけでなく、途中で止まってまた減り始めたところも（雑魚フェーズの間ボスが無敵）
            own = set(e.hit_ms)
            decs, prev = [], None
            for ms, cur, mx in ser:
                if prev is not None and cur < prev:
                    decs.append((ms, cur, mx))
                prev = cur
            if not decs or prev is None:
                continue
            nexts = [d[0] for d in decs[1:]] + [pr.end_ms]
            for (ms, cur, mx), nxt in zip(decs, nexts):
                if cur <= 0 or (nxt - ms) / 1000 < opt.hp_stop_min_sec:
                    continue
                others = [m for m in all_hits if ms + 2000 < m < nxt and m not in own]
                if len(others) >= 3:
                    add('hp_stop', k, None, pr.label, ms - pr.t0_ms, cur * 100.0 / mx if mx else None)
                    break

        # new_enemy_action / new_enemy_hit（そのプルの主役より new_enemy_min_sec 以上後に動き始めた敵）
        pe, pfirst = _pull_primary(r, pr, opt)
        for e in insts:
            k = kind_by_src[(e.contentid, e.base)]
            if k is primary or k.max_hp < top_hp * opt.phase_hp_ratio:
                continue
            if pe is None or (e.contentid, e.base) == (pe.contentid, pe.base):
                continue
            e_first = min(_hits_in(e, pr)[:1] +
                          [c.ms for c, ce in casts_by_pull[pr.label] if ce.id == e.id][:1] + [1 << 62])
            if e_first - pfirst < opt.new_enemy_min_sec * 1000:
                continue
            fc = next(((c.ms, c.action) for c, ce in casts_by_pull[pr.label] if ce.id == e.id), None)
            if fc and (fc[0] - pr.t0_ms) / 1000 >= opt.new_enemy_min_sec:
                add('new_enemy_action', k, fc[1], pr.label, fc[0] - pr.t0_ms)
            hs = _hits_in(e, pr)
            if hs and (hs[0] - pr.t0_ms) / 1000 >= opt.new_enemy_min_sec:
                add('new_enemy_hit', k, None, pr.label, hs[0] - pr.t0_ms)

    order = {'hp_stop': 0, 'new_enemy_hit': 1, 'new_enemy_action': 2}
    return sorted(groups.values(), key=lambda g: (g.median, order[g.kind]))


def _split_phases(pulls, cands, casts_by_pull, opt, warnings) -> list[Phase]:
    p1 = Phase('p1', 'フェーズ1', {'type': 'combat_start'},
               {p.label: 0 for p in pulls}, {})
    phases = [p1]
    if opt.split_phases:
        n = 1
        for c in cands:
            if c.kind != 'new_enemy_action':
                continue
            n += 1
            pid = 'p%d' % n
            c.adopted, c.phase = True, pid
            act = c.actions[0] if len(c.actions) == 1 else list(c.actions)
            trig = {'type': 'cast_start', 'entity': c.entity, 'action': act}
            nth = _trigger_nth(c, pulls, casts_by_pull)
            if nth is False:
                warnings.append('%s のきっかけ（%s）は戦闘中に何度も出るのに、何回目かがプルによって違います。'
                                'きっかけを見直してください' % (pid, '/'.join(map(str, c.actions))))
            elif nth is not None:
                trig['nth'] = nth
            phases.append(Phase(pid, 'フェーズ%d' % n, trig, dict(c.ms), {}))
    _phase_durations(pulls, phases)
    return phases


def _phase_durations(pulls, phases):
    """各プルでのフェーズの長さ（次に始まるフェーズまで。無ければプルの終わりまで）"""
    for pr in pulls:
        starts = sorted((ph.starts[pr.label], ph.id) for ph in phases if pr.label in ph.starts)
        for i, (st, pid) in enumerate(starts):
            nxt = starts[i + 1][0] if i + 1 < len(starts) else (pr.end_ms - pr.t0_ms)
            next(ph for ph in phases if ph.id == pid).durations[pr.label] = (nxt - st) / 1000


def _targetable_candidates(replays, pulls, kinds, key_of_cid, opt) -> list[PhaseCandidate]:
    """
    本物の敵がターゲット不可になった時刻（untargetable）と、ターゲット不可からターゲット可に戻った時刻（retargetable。
    スレッド #9：雑魚フェーズの終わり＝ボスに戻るところ。火力で時刻が変わる）。
    フェーズのきっかけ（targetable）の候補として出す。戦闘開始から new_enemy_min_sec 秒より後のものだけ。
    ターゲット可否は記録ログと、読めるならリプレイ（targetable_events があるもの）から
    """
    real = {k.contentid for k in kinds if k.real}
    groups = {}
    for pr in pulls:
        r = replays[pr.replay]
        fn = getattr(r, 'targetable_events', None)
        if fn is None:
            continue
        was_off = set()
        count = {}
        for ms, eid, state in fn():
            e = r.entities.get(eid)
            if e is None or e.contentid not in real or not (pr.start_ms <= ms <= pr.end_ms):
                continue
            rel = ms - pr.t0_ms
            if rel >= 0:
                count[(e.contentid, state)] = count.get((e.contentid, state), 0) + 1
            if not state:
                was_off.add(eid)
                kind = 'untargetable'
            elif eid in was_off:
                kind = 'retargetable'
            else:
                continue
            if rel < opt.new_enemy_min_sec * 1000:
                continue
            g = groups.get((kind, e.contentid))
            if g is None:
                g = groups[(kind, e.contentid)] = PhaseCandidate(kind, e.contentid, 0,
                                                                 key_of_cid.get(e.contentid, ''), [], {})
            if pr.label not in g.times:
                g.times[pr.label] = round(rel / 1000, 1)
                g.ms[pr.label] = rel
                g.nths[pr.label] = count.get((e.contentid, state), 0)
    return sorted(groups.values(), key=lambda g: g.median)


def _user_phases(replays, pulls, casts_by_pull, key_of_cid, opt, warnings) -> list[Phase]:
    """手で決めた区切り（opt.phase_splits）でフェーズを作る。時刻の順に p2, p3 …"""
    found = []
    for sp in opt.phase_splits or []:
        typ = sp.get('type')
        cid = int(sp.get('contentid') or 0)
        at_ms = float(sp.get('at') or 0) * 1000
        lo = max(0.0, at_ms - opt.split_before * 1000)
        hi = at_ms + opt.split_after * 1000
        key = sp.get('entity') or key_of_cid.get(cid, 'npc%d' % cid)
        times = {}
        if typ == 'cast_start':
            acts = sp.get('action')
            acts = set(acts if isinstance(acts, (list, tuple)) else [acts])
            acts = {int(a) for a in acts}
            # anywhere（スレッド #9）：秒数に関係なく、その詠唱が来たところ（nth 回目。省略は 1 回目）で区切る。
            #   覚醒編 4 層の車型／人型のように、同じブロックがプルによって⑥にも⑬にも来る戦闘用
            anywhere = bool(sp.get('anywhere'))
            want = int(sp.get('nth') or 1)
            for pr in pulls:
                k = 0
                for c, e in casts_by_pull[pr.label]:
                    rel = c.ms - pr.t0_ms
                    if e.contentid != cid or c.action not in acts:
                        continue
                    if anywhere:
                        if rel < 0 or c.ms > pr.end_ms:
                            continue
                        k += 1
                        if k == want:
                            times[pr.label] = rel
                            break
                    elif lo <= rel <= hi:
                        times[pr.label] = rel
                        break
            cand = PhaseCandidate('user', cid, 0, key, sorted(acts), {}, dict(times))
            trig = {'type': 'cast_start', 'entity': key,
                    'action': cand.actions[0] if len(cand.actions) == 1 else list(cand.actions)}
            if times:
                nth = _trigger_nth(cand, pulls, casts_by_pull)
                if nth is False:
                    warnings.append('きっかけ %s は戦闘中に何度も出るのに、何回目かがプルによって違います'
                                    % '/'.join(map(str, cand.actions)))
                elif nth is not None:
                    trig['nth'] = nth
        elif typ == 'hp_below':
            # HP で区切る（スレッド #9）：その種類の敵のどれかの HP% が percent 以下になった最初の時刻。
            #   秒数の範囲では探さない（HP で移るフェーズは、火力で時刻が変わるので）
            try:
                pct = float(sp.get('percent'))
            except (TypeError, ValueError):
                warnings.append('HP の区切りの %% が数ではありません（%s）' % sp.get('percent'))
                continue
            for pr in pulls:
                r = replays[pr.replay]
                best = None
                for e in r.entities.values():
                    if e.contentid != cid:
                        continue
                    for ms, cur, mx in r.hp_series(e.id):
                        if not (pr.start_ms <= ms <= pr.end_ms) or ms < pr.t0_ms or not mx:
                            continue
                        if cur * 100.0 / mx <= pct:
                            if best is None or ms < best:
                                best = ms
                            break
                if best is not None:
                    times[pr.label] = best - pr.t0_ms
            trig = {'type': 'hp_below', 'entity': key, 'percent': pct}
        elif typ == 'targetable':
            state = bool(sp.get('state', False))
            anywhere = bool(sp.get('anywhere'))      # 秒数に関係なく nth 回目（スレッド #9。雑魚フェーズの長さは火力で変わる）
            want = int(sp.get('nth') or 1)
            # nth（スレッド #9）：戦闘開始から、その種類の敵が同じ向き（state）に変わった何回目か（アドオンも同じに数える）。
            #   ターゲット可に戻る（state = true）のは何度もあり得るので、プルの中で 2 回以上あれば nth を付ける
            nths, again = set(), False
            for pr in pulls:
                r = replays[pr.replay]
                fn = getattr(r, 'targetable_events', None)
                k = 0
                for ms, eid, st in (fn() if fn else []):
                    e = r.entities.get(eid)
                    rel = ms - pr.t0_ms
                    if e is None or e.contentid != cid or st != state or rel < 0 or ms > pr.end_ms:
                        continue
                    k += 1
                    hit = (k == want) if anywhere else (lo <= rel <= hi)
                    if pr.label not in times and hit:
                        times[pr.label] = rel
                        nths.add(k)
                    elif pr.label in times:
                        again = True
                if pr.label in times and k > 1:
                    again = True
            trig = {'type': 'targetable', 'entity': key, 'state': state}
            if again and len(nths) == 1:
                trig['nth'] = nths.pop()
            elif again and len(nths) > 1:
                warnings.append('きっかけ（%s がターゲット%s）は何度も出るのに、何回目かがプルによって違います'
                                % (key, '可' if state else '不可'))
        else:
            warnings.append('フェーズの区切りの種類 %s は使えません' % typ)
            continue
        if not times:
            warnings.append('フェーズの区切り（%s %s %.1f 秒ごろ）が、どのプルにもありません'
                            % (typ, key, at_ms / 1000))
            continue
        missing = [p.label for p in pulls if p.label not in times]
        if missing:
            if typ != 'cast_start':
                why = 'そこまで届かなかったプル'
            elif sp.get('anywhere'):
                why = 'そこまで届かなかったか、別の流れのプル'
            else:
                why = 'そこまで届かなかったプル。別の流れのプルなら「どこで来ても」にしてください'
            warnings.append('フェーズの区切り（%s %s）は %s には来ていません（%s）'
                            % (typ, key, '/'.join(missing), why))
        found.append((statistics.median(times.values()), trig, times, sp))
    found.sort(key=lambda x: x[0])
    phases = [Phase('p1', 'フェーズ1', {'type': 'combat_start'}, {p.label: 0 for p in pulls}, {})]
    for i, (_, trig, times, sp) in enumerate(found):
        pid = 'p%d' % (i + 2)
        phases.append(Phase(pid, sp.get('name') or 'フェーズ%d' % (i + 2), trig, dict(times), {}))
    _phase_durations(pulls, phases)
    return phases


def _trigger_nth(c: PhaseCandidate, pulls, casts_by_pull):
    """
    フェーズのきっかけ（詠唱）が戦闘中にもう一度出るなら、何回目か（nth）を返す。
    出ないなら None、プルによって違うなら False。
    数え方は同期点と同じ：戦闘中に同じ contentid がそのアクションを詠唱した回数（詠唱パケット数）。
    """
    acts = set(c.actions)
    nths, again = set(), False
    for pr in pulls:
        if pr.label not in c.ms:
            continue
        at = pr.t0_ms + c.ms[pr.label]
        lst = [x.ms for x, e in casts_by_pull[pr.label] if e.contentid == c.contentid and x.action in acts]
        nths.add(sum(1 for ms in lst if ms < at) + 1)
        if len(lst) > 1:
            again = True
    if not again:
        return None
    if len(nths) != 1:
        return False
    return nths.pop()


def _phase_of(phases_sorted, rel_ms):
    cur = None
    for st, pid in phases_sorted:
        if st <= rel_ms:
            cur = pid
    return cur


# ====================================================================== 枠

def _build_slots(ph: Phase, phases, pulls, casts_by_pull, kind_by_src, key_of_cid, opt) -> list[Slot]:
    # 各プルの「瞬間」を作る
    moments_by_src = {}
    for pr in pulls:
        if pr.label not in ph.starts:
            continue
        all_starts = sorted((p.starts[pr.label], p.id) for p in phases if pr.label in p.starts)
        open_m = {}
        for c, e in casts_by_pull[pr.label]:
            rel = c.ms - pr.t0_ms
            if rel < 0:
                continue        # 交戦前（カウントダウン中）の詠唱は使わない
            if _phase_of(all_starts, rel) != ph.id:
                continue
            src = (e.contentid, e.base)
            m = open_m.get(src)
            if m is None or c.ms - m.ms > opt.merge_sec * 1000:
                m = Moment(pr.label, c.ms, round((rel - ph.starts[pr.label]) / 1000, 1),
                           round(rel / 1000, 1), src, {}, 0.0, [], [])
                open_m[src] = m
                moments_by_src.setdefault(src, []).append(m)
            m.actions[c.action] = m.actions.get(c.action, 0) + 1
            m.cast = max(m.cast, round(c.cast, 1))
            m.casts[c.action] = max(m.casts.get(c.action, 0.0), round(c.cast, 1))
            if c.entity_id not in m.entity_ids:
                m.entity_ids.append(c.entity_id)
            if c.target not in m.targets:
                m.targets.append(c.target)

    slots = []
    order = sorted([p for p in pulls if p.label in ph.durations],
                   key=lambda p: -ph.durations[p.label])
    for src, ms in moments_by_src.items():
        src_slots = []
        for pr in order:
            for m in sorted((m for m in ms if m.pull == pr.label), key=lambda m: m.t):
                cand = [s for s in src_slots if pr.label not in s.moments and abs(s.t - m.t) <= opt.align_tol]
                if cand:
                    s = min(cand, key=lambda s: abs(s.t - m.t))
                else:
                    k = kind_by_src.get(src)
                    s = Slot('', ph.id, src, key_of_cid.get(src[0], 'npc%d' % src[0]),
                             real_caster=bool(k and k.real))
                    src_slots.append(s)
                s.moments[pr.label] = m
        slots += src_slots
    order_idx = {p.label: i for i, p in enumerate(pulls)}
    for s in slots:   # プルの並びを時系列（P1, P2, …）にそろえる
        s.moments = dict(sorted(s.moments.items(), key=lambda kv: order_idx[kv[0]]))
    slots.sort(key=lambda s: (s.t, not s.real_caster, s.source))
    for i, s in enumerate(slots):
        s.id = '%s_s%03d' % (ph.id, i + 1)
    return slots


def _classify(ph: Phase, pulls, opt):
    pull_order = {p.label: i for i, p in enumerate(pulls)}
    for s in ph.slots:
        s.reached = [lbl for lbl, dur in ph.durations.items()
                     if dur >= s.t + opt.reach_margin or lbl in s.moments]
        sets = set(s.sets().values())
        if len(sets) > 1:
            s.kind = 'branch'
        elif s.seen < len(s.reached):
            s.kind = 'partial'
        else:
            s.kind = 'stable'
        s.action_set = s.all_actions if s.kind == 'branch' else next(iter(sets))

    # 順番入れ替わり：同じ詠唱者の branch 枠 2 つで、各プルのアクションの組が同じで順番だけ違う
    by_src = {}
    for s in ph.slots:
        if s.kind == 'branch':
            by_src.setdefault(s.source, []).append(s)
    for src, lst in by_src.items():
        lst.sort(key=lambda s: s.t)
        for i, a in enumerate(lst):
            if a.partner:
                continue
            for b in lst[i + 1:]:
                if b.partner or b.t - a.t > opt.swap_window:
                    continue
                common = [p for p in a.moments if p in b.moments]
                if len(common) < 2:
                    continue
                sa, sb = a.sets(), b.sets()
                pairs = {tuple(sorted((sa[p], sb[p]))) for p in common}
                if len(pairs) != 1 or any(sa[p] == sb[p] for p in common):
                    continue
                if len({sa[p] for p in common}) < 2:
                    continue
                a.kind = b.kind = 'swap'
                a.partner, b.partner = b.id, a.id
                # 多数派（同数なら先のプル）を各枠に割り当てる
                common.sort(key=lambda p: pull_order[p])
                pa = _majority([sa[p] for p in common])
                pb = next(x for x in pairs.pop() if x != pa)
                a.action_set, b.action_set = pa, pb
                break


def _majority(seq):
    cnt = {}
    for x in seq:
        cnt[x] = cnt.get(x, 0) + 1
    best = max(cnt.values())
    return next(x for x in seq if cnt[x] == best)


def _label(s: Slot) -> tuple[str, str]:
    """(表示名の元, ID に使う英数字) を返す"""
    acts = [str(a) for a in s.action_set]
    if s.kind == 'branch':
        return '/'.join(acts), 'or'.join(acts)
    return '+'.join(acts), 'and'.join(acts)


def _name_events(ph: Phase):
    """
    枠ごとに、タイムラインに書くイベント（parts）を決める。
      同じ瞬間に同じ詠唱者の種類が別々のアクションを詠唱した枠（stable / partial で 2 つ以上）は、
      アクションごとに別のイベントにする（スレッド #8）。1 つのイベントに並べると、アドオンは「どれか 1 つ」で照合するので、
      残りの詠唱が、後にある同じアクションのイベントに照合されてしまう（ミストウェイク 2 ボスの 45346+45348 → 45348 が
      1.5 秒早く照合された）。記録ログから作ったタイムライン（log_to_timeline.py）と同じ ID（p1_45341_1）になる。
      分岐・入れ替わりは、どれか 1 つが来るので、今までどおり 1 つのイベント（action を配列）。
    """
    count = {}
    for s in ph.slots:
        if s.kind in ('stable', 'partial') and len(s.action_set) > 1:
            s.parts = []
            for a in s.action_set:
                n = count[str(a)] = count.get(str(a), 0) + 1
                s.parts.append(dict(action=a, event_id='%s_%d_%d' % (ph.id, a, n), name='%d #%d' % (a, n),
                                    cast=round(statistics.median(m.casts.get(a, m.cast) for m in s.moments.values()), 1)))
        else:
            disp, idp = _label(s)
            n = count[idp] = count.get(idp, 0) + 1
            s.parts = [dict(action=s.action_set[0] if len(s.action_set) == 1 else list(s.action_set),
                            event_id='%s_%s_%d' % (ph.id, idp, n), name='%s #%d' % (disp, n), cast=s.cast)]
        s.event_id = s.parts[0]['event_id']
        s.event_name = s.parts[0]['name']


# ====================================================================== 同期点

def _nth(s: Slot, pulls, casts_by_pull, action: int | None = None) -> tuple[bool, int | None]:
    """
    同期点の nth（戦闘開始から、同じ contentid が同じアクションを詠唱した何回目か）。
    プル間で一致しなければ (False, None)。その戦闘で 1 回しか出ないなら (True, None)。
    action を渡すと、枠の中のそのアクションについて数える（アクションごとに分けたイベント）
    """
    if action is None and len(s.action_set) != 1:
        return False, None
    act, cid = (action if action is not None else s.action_set[0]), s.source[0]
    nths, totals = set(), set()
    for lbl, m in s.moments.items():
        if act not in m.actions:
            continue
        lst = [c.ms for c, e in casts_by_pull[lbl] if e.contentid == cid and c.action == act]
        nths.add(sum(1 for ms in lst if ms < m.ms) + 1)
        totals.add(len(lst))
    if len(nths) != 1:
        return False, None
    if max(totals) == 1:
        return True, None
    return True, nths.pop()


def _sync_candidates(ph: Phase, pulls, casts_by_pull, opt):
    for s in ph.slots:      # どのイベントも、同期点にできるか（画面で同期点を足すとき用）
        ok, nth = _nth(s, pulls, casts_by_pull)
        s.sync_ok, s.sync_nth = ok, nth
        for part in s.parts:
            if isinstance(part['action'], int):
                part['sync_ok'], part['sync_nth'] = _nth(s, pulls, casts_by_pull, part['action'])
            else:
                part['sync_ok'], part['sync_nth'] = False, None
    anchors = []
    for s in ph.slots:
        if s.kind != 'stable' or not s.real_caster or len(s.action_set) != 1 or s.t < 1.0:
            continue
        if s.spread is not None and s.spread > opt.anchor_spread:
            continue
        ok, nth = _nth(s, pulls, casts_by_pull)
        if not ok:
            continue
        s.nth = nth
        anchors.append(s)
    chosen = {}
    # ばらつきの大きい枠の直前
    for u in ph.slots:
        if u.spread is not None and u.spread > opt.unstable_spread:
            prev = [a for a in anchors if a.t < u.t and u.t - a.t <= opt.max_sync_gap]
            if prev:
                chosen.setdefault(prev[-1].id, 'before_unstable:%s' % u.id)
    # 間隔
    cur = 0.0
    while True:
        later = [a for a in anchors if a.t > cur + 0.05]
        if not later:
            break
        within = [a for a in later if a.t <= cur + opt.max_sync_gap]
        pick = within[-1] if within else later[0]
        chosen.setdefault(pick.id, 'interval')
        cur = pick.t
    for s in ph.slots:
        if s.id in chosen:
            s.sync = chosen[s.id]
