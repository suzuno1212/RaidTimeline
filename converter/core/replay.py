"""
core/replay.py — FFXIV リプレイ（.dat / XIVLauncher ARealmRecorded）の読み込み

RaidTimeline 変換ツールの core。UI に依存しない純粋な Python（標準ライブラリのみ）。
claude/ffxiv_replay.py（検証済み）を元に、次を追加・修正した。

  - opcode の自動判定に「判定の確からしさ」を付け、ビルド番号ごとの既知表・保存ファイルで補う
  - InitZone パケットから mapid（TerritoryType ＝ Player.localmapid）を読む
  - 出現パケットの所有者（+84）でペット・フェアリー・召喚獣を除外する
  - 出現パケットの親（+76）で「ボスに付属する発射役」を判別できるようにする
  - 出現パケットの最大HPは +92（旧モジュールは +96 を読んでいたが、+96 は現在HP）
  - 被弾（パーティからの単体効果）の時刻を記録し、プルごとの「本物の敵」判定とフェーズ移行検出に使う

【パケット構造（3 ビルド 0xd72b61 / 0xd7ff4d / 0xd975a5、29 リプレイで確認）】
  ヘッダー 0x36C バイト。その後に {u16 opcode, u16 長さ, u32 ミリ秒, u32 対象ID, 本体} が続く
  チャプター表（0x68〜）: type 1 = プル開始, type 2 = 全滅/終了, type 5 = 入室
    ※ type 1 は「交戦開始」ではなく、その約 15 秒前（カウントダウン開始と見られる）。
      最初にパーティが敵を攻撃した時刻を Pull.engage_ms として求め、秒数の基準にする
  InitZone（136B, ファイル先頭）: +2 u16 TerritoryType（= mapid）
  出現（NpcSpawn, 600〜700B）: +64 bNpcBase, +68 bNpcName(= contentid), +76 親ID,
                               +84 所有者ID（ペットはプレイヤーID / 敵は 0xE0000000）, +92 最大HP, +96 現在HP
  詠唱（32B）: +0 u16 アクションID, +4 u32 アクションID(同値), +8 f32 詠唱時間, +12 u32 対象
  状態（384B）: +4 現在HP, +8 最大HP
  単体効果（120B）: +8 u32 アクションID, +112 u32 対象ID
"""
from __future__ import annotations

import bisect
import collections
import datetime
import json
import os
import struct
from dataclasses import dataclass, field, asdict

HEADER_SIZE = 0x36C
MAGIC = b'FFXIVREPLAY'
CH_START, CH_END = 1, 2
ENGAGE_EARLY_MS = 1500         # 開始のチャプターより前の攻撃を交戦開始とみなす幅（ダンジョン用）
OPEN_END_PAD_MS = 3000         # 終了のチャプターが無いプルを、ボスへの最後の攻撃の何 ms 後で切るか
OPEN_END_FIRST_MS = 10000      # 戦闘の敵を探す幅（交戦開始から何 ms 以内に最初の攻撃を受けた敵か）
OPEN_END_GAP_MS = 10000        # それまでの最後の攻撃から何 ms 以内に攻撃を受けた敵を、同じ戦闘の敵とみなすか

ENEMY_ID_MIN = 0x40000000      # これ以上の ID は NPC（敵・ペット・発射役を含む）
NO_ID = 0xE0000000             # 所有者・親が「なし」のときの値

# 出現パケット内のオフセット
SP_BASE, SP_NAME, SP_PARENT, SP_OWNER, SP_MAXHP, SP_CURHP = 64, 68, 76, 84, 92, 96

OPCODE_KINDS = ('init_zone', 'spawn', 'cast', 'status', 'effect1')
# 無くても読めるもの（スレッド #9）。actor_control（ActorControl・24 B）：ターゲット可否（区分 0x36）を読む。
#   決まらなければ、ターゲット可否が無いだけ（警告は出さない）
OPTIONAL_KINDS = ('actor_control',)
AC_TARGETABLE = 0x36      # ActorControl の区分：ターゲット可否（param1 = 1 で可・0 で不可。記録ログの targetable と 2 件のリプレイで照合）

# 自動判定の結果を、ビルドごとに記録したもの（このスレッドで 29 リプレイから確認）。
# 自動判定が弱い・できないとき（短いリプレイなど）の補いに使う。手で指定する必要はない。
KNOWN_OPCODES = {
    0xd72b61: dict(init_zone=0x2cc, spawn=0x114, cast=0x301, status=0x2ce, effect1=0x0bd),
    0xd7ff4d: dict(init_zone=0x09c, spawn=0x17d, cast=0x07f, status=0x0d4, effect1=0x363, actor_control=0x229),
    0xd975a5: dict(init_zone=0x0ab, spawn=0x176, cast=0x160, status=0x15d, effect1=0x190, actor_control=0x2df),
}

# 自動判定を「確か」とみなす最低件数
CONFIDENT_MIN = 20


class ReplayFormatError(ValueError):
    """リプレイの形式が想定と違う（ARealmRecorded の形式変更の可能性）"""


# ====================================================================== データ型

@dataclass
class OpcodeInfo:
    kind: str
    opcode: int | None
    source: str                 # 'detected' / 'known' / 'store' / 'override' / 'none'
    matches: int = 0            # 構造条件を満たしたパケット数
    ratio: float = 0.0          # そのうちの割合
    detected: int | None = None  # 自動判定の結果（source が別でも参考に残す）

    def to_dict(self):
        d = asdict(self)
        d['opcode_hex'] = None if self.opcode is None else '0x%04x' % self.opcode
        return d


@dataclass
class Entity:
    id: int
    base: int                   # bNpcBase
    contentid: int              # bNpcName（MMOminion の entity.contentid）
    max_hp: int
    spawn_ms: int
    owner: int                  # 所有者 ID（ペットならプレイヤー ID）
    parent: int                 # 親 ID（ボスに付属する発射役ならボスの ID）
    hit_ms: list = field(default_factory=list)   # パーティから単体効果を受けた時刻
    pull: int | None = None     # 所属するプルの番号（0 始まり）

    @property
    def is_pet(self) -> bool:
        return 0 < self.owner < ENEMY_ID_MIN

    @property
    def hits(self) -> int:
        return len(self.hit_ms)

    def to_dict(self):
        return dict(id=self.id, base=self.base, contentid=self.contentid, max_hp=self.max_hp,
                    spawn_ms=self.spawn_ms, owner=self.owner, parent=self.parent,
                    hits=self.hits, pull=self.pull, is_pet=self.is_pet)


@dataclass
class Cast:
    ms: int
    entity_id: int
    action: int
    cast: float
    target: int


@dataclass
class Pull:
    index: int                  # 0 始まり
    start_ms: int               # プル開始（チャプター type 1。交戦開始の約 15 秒前＝カウントダウン開始）
    end_ms: int                 # 全滅・終了（チャプター type 2）
    window_start_ms: int        # このプルに属するエンティティを探す範囲の始まり（前のプルの終わり）
    engage_ms: int | None = None  # 交戦開始＝プル内で最初にパーティが敵を攻撃した時刻（無ければ None）
    no_start: bool = False      # 開始のチャプターが無い（カウントダウンなしで始めた）。start_ms は前の区切り
    open_end: bool = False      # 終了のチャプターが無く、次の開始で区切った（ダンジョン）。戦闘の最後の攻撃の 3 秒後で切る（_cut_open_end）

    @property
    def duration(self) -> float:
        return (self.end_ms - self.start_ms) / 1000.0

    @property
    def t0_ms(self) -> int:
        """秒数の基準（交戦開始。求められなければチャプター開始）"""
        return self.engage_ms if self.engage_ms is not None else self.start_ms

    @property
    def engage_offset(self) -> float | None:
        """チャプター開始から交戦開始までの秒数（カウントダウンの長さ。ふつう約 15 秒）"""
        return None if self.engage_ms is None else round((self.engage_ms - self.start_ms) / 1000, 1)

    def to_dict(self):
        return dict(index=self.index, start_ms=self.start_ms, end_ms=self.end_ms,
                    engage_ms=self.engage_ms, engage_offset=self.engage_offset,
                    duration=round(self.duration, 1), no_start=self.no_start, open_end=self.open_end)


# ====================================================================== opcode の保存ファイル

class OpcodeStore:
    """
    ビルド番号ごとの opcode を JSON に保存する（設計書 4.4「自動判定の結果を手で直せる」）。
    形式: { "0xd7ff4d": { "cast": "0x007f", ... }, ... }
    手で書き換えた値は override として最優先で使う（"override": true を付けたビルド）。
    """

    def __init__(self, path: str | None):
        self.path = path
        self.data = {}
        if path and os.path.exists(path):
            with open(path, 'r', encoding='utf-8') as f:
                self.data = json.load(f)

    def get(self, build: int) -> tuple[dict, bool]:
        e = self.data.get('0x%x' % build) or {}
        ops = {k: int(v, 16) for k, v in e.items() if (k in OPCODE_KINDS or k in OPTIONAL_KINDS) and v}
        return ops, bool(e.get('override'))

    def put(self, build: int, ops: dict):
        key = '0x%x' % build
        cur = self.data.get(key) or {}
        if cur.get('override'):
            return  # 手で直した値は上書きしない
        cur.update({k: '0x%04x' % v for k, v in ops.items() if v is not None})
        self.data[key] = cur

    def save(self):
        if not self.path:
            return
        d = os.path.dirname(os.path.abspath(self.path))
        os.makedirs(d, exist_ok=True)
        with open(self.path, 'w', encoding='utf-8', newline='\n') as f:
            json.dump(self.data, f, indent=2, sort_keys=True)


# ====================================================================== 本体

class Replay:
    """
    リプレイ 1 ファイル。
      r = Replay(path)                 … opcode は自動判定（必要なら既知表で補う）
      r.mapid, r.cfc, r.build, r.pulls, r.entities
      r.casts(), r.hp_series(id), r.real_enemy_kinds()
    """

    def __init__(self, path: str, opcodes: dict | None = None, store: OpcodeStore | None = None):
        self.path = path
        with open(path, 'rb') as f:
            self.d = d = f.read()
        if len(d) < HEADER_SIZE or d[:11] != MAGIC:
            raise ReplayFormatError("FFXIVREPLAY ファイルではありません: %s" % path)

        self.format = struct.unpack_from('<H', d, 0x0C)[0]
        self.build = struct.unpack_from('<I', d, 0x10)[0]
        self.timestamp = struct.unpack_from('<I', d, 0x14)[0]
        self.total_ms = struct.unpack_from('<I', d, 0x18)[0]
        self.cfc = struct.unpack_from('<H', d, 0x20)[0]
        self.party_jobs = list(d[0x38:0x40])
        datalen = struct.unpack_from('<I', d, 0x48)[0]
        nch = struct.unpack_from('<I', d, 0x68)[0]
        if nch > 64 or HEADER_SIZE + datalen > len(d):
            raise ReplayFormatError("ヘッダーの値が範囲外です（形式が変わった可能性）")
        self.chapters = [struct.unpack_from('<III', d, 0x6C + i * 12) for i in range(nch)]
        self.warnings: list[str] = []

        # パケット列
        self.segs = []
        p, end = HEADER_SIZE, HEADER_SIZE + datalen
        while p + 12 <= end:
            op, ln, ms, obj = struct.unpack_from('<HHII', d, p)
            self.segs.append((op, ln, ms, obj, p + 12))
            p += 12 + ln
        if p != end:
            raise ReplayFormatError("パケット列の終端が一致しません（形式が変わった可能性）")

        self.opcode_info = self._resolve_opcodes(opcodes or {}, store)
        self.op = {k: v.opcode for k, v in self.opcode_info.items()}
        if store is not None:
            store.put(self.build, {k: v.opcode for k, v in self.opcode_info.items()
                                   if v.source == 'detected'})

        self.mapid = self._read_mapid()
        self.pulls = self._read_pulls()
        self.entities = self._read_spawns()
        self._read_hits()
        self._status_by_obj = None      # hp_series の元（初めて使うときに作る。_read_engage でも使う）
        self._assign_pulls()
        self._read_engage()

    # ------------------------------------------------------------------ 基本情報
    @property
    def build_hex(self) -> str:
        return '0x%x' % self.build

    @property
    def recorded_at(self) -> datetime.datetime:
        return datetime.datetime.fromtimestamp(self.timestamp)

    @property
    def file_name(self) -> str:
        return os.path.basename(self.path)

    def summary(self) -> dict:
        """UI・CLI 向けの概要（JSON にできる値だけ）"""
        return dict(
            file=self.file_name, build=self.build_hex, format=self.format, cfc=self.cfc,
            mapid=self.mapid, recorded_at=self.recorded_at.strftime('%Y-%m-%d %H:%M:%S'),
            total_sec=round(self.total_ms / 1000, 1), packets=len(self.segs),
            pulls=[p.to_dict() for p in self.pulls],
            opcodes={k: v.to_dict() for k, v in self.opcode_info.items()},
            warnings=list(self.warnings),
        )

    # ------------------------------------------------------------------ opcode 自動判定
    def _detect(self) -> dict[str, tuple]:
        """構造から opcode を推定する。戻り値: kind -> (opcode, 一致数, 割合)"""
        d = self.d
        by = collections.defaultdict(list)
        for s in self.segs:
            by[(s[0], s[1])].append(s)

        def best(cands, min_count=3):
            cands = [c for c in cands if c[1] >= min_count]
            return max(cands, key=lambda c: (c[2], c[1])) if cands else (None, 0, 0.0)

        out = {}

        # InitZone: ファイル先頭付近の 136B パケット
        iz = next(((s[0], 1, 1.0) for s in self.segs[:50] if s[1] == 136), (None, 0, 0.0))
        out['init_zone'] = iz

        # 詠唱: 32B, u16@0 == u32@4 > 0, 0.3 <= f32@8 <= 30
        cast = []
        for (op, ln), rows in by.items():
            if ln != 32:
                continue
            ok = 0
            for (_, _, _, _, off) in rows:
                a16 = struct.unpack_from('<H', d, off)[0]
                a32, ct = struct.unpack_from('<If', d, off + 4)
                if a16 == a32 > 0 and 0.3 <= ct <= 30:
                    ok += 1
            cast.append((op, ok, ok / len(rows)))
        out['cast'] = best(cast)

        # 出現: 600〜700B, 現在HP == 最大HP > 0 がほとんど
        spawn = []
        for (op, ln), rows in by.items():
            if not 600 <= ln <= 700:
                continue
            ok = sum(1 for (_, _, _, _, off) in rows
                     if struct.unpack_from('<I', d, off + SP_MAXHP)[0] ==
                     struct.unpack_from('<I', d, off + SP_CURHP)[0] > 0)
            spawn.append((op, ok, ok / len(rows)))
        out['spawn'] = best(spawn)
        spawn_op = out['spawn'][0]

        maxhp = {}
        for (op, ln, ms, obj, off) in self.segs:
            if op == spawn_op:
                maxhp.setdefault(obj, struct.unpack_from('<I', d, off + SP_MAXHP)[0])

        # 状態: 384B, 最大HP@8 が出現パケットの最大HPと一致
        status = []
        for (op, ln), rows in by.items():
            if ln != 384:
                continue
            ok = sum(1 for (_, _, _, obj, off) in rows
                     if maxhp.get(obj) and struct.unpack_from('<I', d, off + 8)[0] == maxhp[obj])
            status.append((op, ok, ok / len(rows)))
        st = best(status)
        if st[0] is None:
            # 敵の状態パケットが無い短いリプレイ：0 <= 現在HP <= 最大HP の形だけで判定（弱い判定）
            weak = []
            for (op, ln), rows in by.items():
                if ln != 384:
                    continue
                ok = 0
                for (_, _, _, _, off) in rows:
                    cur, mx = struct.unpack_from('<II', d, off + 4)
                    if 0 < mx and cur <= mx:
                        ok += 1
                weak.append((op, 0, ok / len(rows)))   # 一致数 0 ＝「確かではない」として扱う
            st = max(weak, key=lambda c: c[2]) if weak else (None, 0, 0.0)
        out['status'] = st

        # 単体効果: 120B, 対象@112 が既知のエンティティ
        effect = []
        for (op, ln), rows in by.items():
            if ln != 120:
                continue
            ok = sum(1 for (_, _, _, _, off) in rows if struct.unpack_from('<I', d, off + 112)[0] in maxhp)
            effect.append((op, ok, ok / len(rows)))
        out['effect1'] = best(effect)

        # ActorControl（スレッド #9）: 24B, 区分@0 == 0x36（ターゲット可否）・param1 が 0 か 1・残りが 0、対象が出現した敵。
        #   ほかの 24B の opcode にはこの形が 1 件も無い（31 リプレイで確認）。ボス 1 体の討滅戦では 1 件しか無いこともある
        ac = []
        for (op, ln), rows in by.items():
            if ln != 24:
                continue
            ok = 0
            for (_, _, _, obj, off) in rows:
                cat, pad, p1, p2, p3, p4, p5 = struct.unpack_from('<HHIIIII', d, off)
                if cat == AC_TARGETABLE and pad == 0 and p1 in (0, 1) and p2 == p3 == p4 == p5 == 0 and obj in maxhp:
                    ok += 1
            ac.append((op, ok, ok / len(rows)))
        cands = [c for c in ac if c[1] >= 1]
        out['actor_control'] = max(cands, key=lambda c: c[1]) if cands else (None, 0, 0.0)
        return out

    def _resolve_opcodes(self, override: dict, store: OpcodeStore | None) -> dict[str, OpcodeInfo]:
        """
        優先順位:
          1. 引数 override（UI・CLI で手で指定したもの）
          2. 保存ファイルで override 指定されたビルド
          3. 自動判定（一致数が CONFIDENT_MIN 以上なら「確か」）
          4. 保存ファイル → 既知表（自動判定が弱い・できないとき）
          5. 弱い自動判定
        自動判定が確かで、既知表と食い違ったら警告を残す（パッチで opcode が変わったのにビルド番号が同じ、など）。
        """
        det = self._detect()
        stored, stored_override = store.get(self.build) if store else ({}, False)
        known = KNOWN_OPCODES.get(self.build, {})
        info = {}
        for k in OPCODE_KINDS + OPTIONAL_KINDS:
            op_d, n, ratio = det.get(k, (None, 0, 0.0))
            # actor_control：形が独特（ほかの opcode に 1 件も無い）なので 3 件で確か
            confident = op_d is not None and (n >= CONFIDENT_MIN or (k == 'init_zone' and n >= 1)
                                              or (k == 'actor_control' and n >= 3))
            fallback = stored.get(k, known.get(k))
            fsrc = 'store' if k in stored else 'known'
            if k in override and override[k] is not None:
                oi = OpcodeInfo(k, int(override[k]), 'override', n, ratio, op_d)
            elif stored_override and k in stored:
                oi = OpcodeInfo(k, stored[k], 'store', n, ratio, op_d)
            elif confident:
                oi = OpcodeInfo(k, op_d, 'detected', n, ratio, op_d)
                if fallback is not None and fallback != op_d:
                    self.warnings.append(
                        "opcode %s: 自動判定 0x%04x と %s 0x%04x が異なります（自動判定を採用）"
                        % (k, op_d, '保存値' if fsrc == 'store' else '既知表', fallback))
            elif fallback is not None:
                oi = OpcodeInfo(k, fallback, fsrc, n, ratio, op_d)
            elif op_d is not None:
                oi = OpcodeInfo(k, op_d, 'detected', n, ratio, op_d)
                if k not in OPTIONAL_KINDS:
                    self.warnings.append("opcode %s: 自動判定の根拠が少ない（%d 件）。結果を確認してください" % (k, n))
            else:
                oi = OpcodeInfo(k, None, 'none', 0, 0.0, None)
                if k not in OPTIONAL_KINDS:
                    self.warnings.append("opcode %s: 判定できませんでした" % k)
            info[k] = oi
        return info

    # ------------------------------------------------------------------ mapid
    def _read_mapid(self) -> int | None:
        op = self.op.get('init_zone')
        for (o, ln, ms, obj, off) in self.segs[:50]:
            if o == op and ln == 136:
                return struct.unpack_from('<H', self.d, off + 2)[0]
        self.warnings.append("mapid を読み取れませんでした")
        return None

    # ------------------------------------------------------------------ プル
    def _read_pulls(self) -> list[Pull]:
        """
        チャプターからプルを作る。
          開始（1）→ 終了（2）           … ふつうのプル（開始はカウントダウン開始）
          開始 → 開始（終了なし）        … 次の開始の直前まで（ダンジョンのボス戦。v0.4 で判明）
          終了だけ（開始なし）           … 前の区切りから終了まで（カウントダウンなしで始めたプル。チャプター「5」の後）
          最後の開始の後に終了が無い     … リプレイの終わりまで
        開始の無いプルで、パーティの攻撃が 1 回も無いものは作らない。
        """
        hits = None
        pulls = []
        prev_end = 0
        start = None
        for (t, off, ms) in self.chapters:
            if t == CH_START:
                if start is not None:
                    pulls.append(Pull(len(pulls), start, ms, prev_end, open_end=True))
                    prev_end = ms
                start = ms
            elif t == CH_END:
                if start is not None:
                    pulls.append(Pull(len(pulls), start, ms, prev_end))
                else:
                    if hits is None:
                        hits = self._party_hit_times()
                    if any(prev_end <= m <= ms for m in hits):
                        pulls.append(Pull(len(pulls), prev_end, ms, prev_end, no_start=True))
                prev_end = ms
                start = None
        if start is not None:
            # 録画を途中で止めたプル（4 層の P4 など）は切らない（ボスの入れ替わりの間に攻撃の無い時間が長いことがある）
            pulls.append(Pull(len(pulls), start, self.total_ms, prev_end))
        return pulls

    def _party_hit_times(self) -> list[int]:
        """パーティ（ID < 0x40000000）が単体効果を当てた時刻（相手は問わない。プルを作るときの確認用）"""
        op_ef = self.op['effect1']
        if op_ef is None:
            return []
        out = []
        for (op, ln, ms, obj, off) in self.segs:
            if op == op_ef and obj < ENEMY_ID_MIN and ln >= 116:
                if struct.unpack_from('<I', self.d, off + 112)[0] >= ENEMY_ID_MIN:
                    out.append(ms)
        return out

    def _read_engage(self):
        """
        各プルの交戦開始＝プル内で最初にパーティが（ペット以外の）敵に単体効果を当てた時刻。
        MMOminion の戦闘開始（Player.incombat の切り替わり）に最も近い時刻として使う。
        実測：チャプター開始から 15.0〜15.6 秒（20 秒・13 秒のカウントダウンもあった）。
        ボスの最初の詠唱は、この時刻からの秒数で見るとプル間でそろう（ずれ 0.2 秒程度）。
        """
        hits = sorted(m for e in self.entities.values()
                      if not e.is_pet and e.id >= ENEMY_ID_MIN for m in e.hit_ms)
        for p in self.pulls:
            # ダンジョンのボス戦では、開始のチャプターが最初の攻撃より少し後になることがある（ミストウェイク 1 ボス：0.36 秒）。
            # 開始の ENGAGE_EARLY_MS 前からの攻撃も交戦開始とみなす（前の区切りより前は見ない）
            lo = p.start_ms if p.no_start else max(p.window_start_ms, p.start_ms - ENGAGE_EARLY_MS)
            i = bisect.bisect_left(hits, lo)
            p.engage_ms = hits[i] if i < len(hits) and hits[i] <= p.end_ms else None
            if p.open_end and p.engage_ms is not None:
                self._cut_open_end(p)

    def _cut_open_end(self, p):
        """
        終了のチャプターが無く、次の開始で区切ったプル（ダンジョンのボス戦は、次のボスの開始まで区切りが無い）を、
        戦闘の続く間の最後の攻撃の OPEN_END_PAD_MS 後で切る。切らないと、ボスの後の雑魚戦の詠唱がボス戦に混ざる
        （ミストウェイク。スレッド #8）。
          戦闘の敵＝交戦開始から OPEN_END_FIRST_MS 以内に最初の攻撃を受けた敵（3 回以上攻撃を受けたもの）。
          さらに、それまでの最後の攻撃から OPEN_END_GAP_MS 以内に最初の攻撃を受けた敵も足す（ボスの入れ替わり：4 層の 2 体目）
        HP 0 は使わない（倒れる直前の HP の更新で止まり、0 が記録されないことがある：ミストウェイク 1 ボス 3%）
        """
        spans = []
        for e in self.entities.values():
            if e.is_pet or e.id < ENEMY_ID_MIN:
                continue
            hs = [m for m in e.hit_ms if p.engage_ms <= m <= p.end_ms]
            if len(hs) >= 3:
                spans.append((hs[0], hs[-1]))
        spans.sort()
        end = None
        for first, last in spans:
            if first - p.engage_ms <= OPEN_END_FIRST_MS or (end is not None and first <= end + OPEN_END_GAP_MS):
                end = last if end is None else max(end, last)
        if end is not None and end + OPEN_END_PAD_MS < p.end_ms:
            p.end_ms = end + OPEN_END_PAD_MS

    def pull_index_at(self, ms: int) -> int | None:
        """その時刻が属するプル（前のプルの終わり〜このプルの終わり）"""
        for p in self.pulls:
            if p.window_start_ms < ms <= p.end_ms or (p.index == 0 and ms <= p.end_ms):
                return p.index
        return None

    # ------------------------------------------------------------------ エンティティ
    def _read_spawns(self) -> dict[int, Entity]:
        d, ents = self.d, {}
        op_sp = self.op['spawn']
        if op_sp is None:
            return ents
        for (op, ln, ms, obj, off) in self.segs:
            if op == op_sp and obj not in ents and ln >= SP_CURHP + 4:
                base, name = struct.unpack_from('<II', d, off + SP_BASE)
                parent = struct.unpack_from('<I', d, off + SP_PARENT)[0]
                owner = struct.unpack_from('<I', d, off + SP_OWNER)[0]
                ents[obj] = Entity(id=obj, base=base, contentid=name,
                                   max_hp=struct.unpack_from('<I', d, off + SP_MAXHP)[0],
                                   spawn_ms=ms, owner=owner, parent=parent)
        return ents

    def _read_hits(self):
        """パーティ（ID < 0x40000000）から単体効果を受けた時刻＝「本物の敵」の判定材料"""
        op_ef = self.op['effect1']
        if op_ef is None:
            return
        d, ents = self.d, self.entities
        for (op, ln, ms, obj, off) in self.segs:
            if op == op_ef and obj < ENEMY_ID_MIN and ln >= 116:
                t = struct.unpack_from('<I', d, off + 112)[0]
                e = ents.get(t)
                if e is not None:
                    e.hit_ms.append(ms)

    def _assign_pulls(self):
        """
        エンティティがどのプルに属するかを決める。
        出現時刻だけでは決められない：次のプルの敵は、前のプルの「終了」チャプターより数秒前に
        出現することがある（4層で確認：終了 263.4s に対し、次のプルのボスが 256.9s に出現）。
          1. 活動（被弾・詠唱）があれば、最初の活動が入っているプル
          2. 活動が無く、親（ボス）がいれば親と同じプル
          3. それ以外は出現時刻で決め、そのプルの活動がすべて終わった後の出現なら次のプル
        """
        first_act = {}
        for e in self.entities.values():
            if e.hit_ms:
                first_act[e.id] = e.hit_ms[0]
        op_c = self.op['cast']
        if op_c is not None:
            for (op, ln, ms, obj, off) in self.segs:
                if op == op_c and obj in self.entities and ms < first_act.get(obj, 1 << 62):
                    first_act[obj] = ms

        def in_pull(ms):
            for p in self.pulls:
                if p.start_ms <= ms <= p.end_ms:
                    return p.index
            return self.pull_index_at(ms)

        last_act = {}
        for e in self.entities.values():
            if e.id in first_act:
                e.pull = in_pull(first_act[e.id])
                if e.pull is not None:
                    last = max([first_act[e.id]] + [m for m in e.hit_ms if m <= self.pulls[e.pull].end_ms])
                    last_act[e.pull] = max(last_act.get(e.pull, 0), last)
        for e in self.entities.values():
            if e.id in first_act:
                continue
            par = self.entities.get(e.parent)
            if par is not None and par.id in first_act:
                e.pull = par.pull
                continue
            i = self.pull_index_at(e.spawn_ms)
            if i is not None and i + 1 < len(self.pulls) and e.spawn_ms > last_act.get(i, 1 << 62):
                i += 1
            e.pull = i

    # ------------------------------------------------------------------ 取り出し
    def casts(self, include_pets: bool = False) -> list[Cast]:
        """敵の詠唱（ID >= 0x40000000）。ペットの詠唱は既定で除外する"""
        op_c = self.op['cast']
        if op_c is None:
            return []
        out, d, ents = [], self.d, self.entities
        for (op, ln, ms, obj, off) in self.segs:
            if op == op_c and obj >= ENEMY_ID_MIN:
                e = ents.get(obj)
                if e is not None and e.is_pet and not include_pets:
                    continue
                out.append(Cast(ms, obj, struct.unpack_from('<H', d, off)[0],
                                struct.unpack_from('<f', d, off + 8)[0],
                                struct.unpack_from('<I', d, off + 12)[0]))
        return out

    def targetable_events(self) -> list[tuple[int, int, bool]]:
        """
        ターゲット可否が変わった [(ms, entity_id, 可か)]（スレッド #9。ActorControl の区分 0x36）。
        記録ログの targetable_events と同じ形。出現したときの状態（出現パケットの中）は入らない。
        actor_control が決まらないビルドでは空
        """
        op = self.op.get('actor_control')
        if op is None:
            return []
        out = []
        for (o, ln, ms, obj, off) in self.segs:
            if o != op or ln != 24:
                continue
            cat, pad, p1 = struct.unpack_from('<HHI', self.d, off)
            if cat == AC_TARGETABLE and p1 in (0, 1):
                out.append((ms, obj, p1 == 1))
        return out

    def hp_series(self, entity_id: int) -> list[tuple[int, int, int]]:
        """(ms, 現在HP, 最大HP) の列（約 1 秒ごと）"""
        if self._status_by_obj is None:
            idx = collections.defaultdict(list)
            op_s = self.op['status']
            if op_s is not None:
                for (op, ln, ms, obj, off) in self.segs:
                    if op == op_s:
                        cur, mx = struct.unpack_from('<II', self.d, off + 4)
                        idx[obj].append((ms, cur, mx))
            self._status_by_obj = idx
        return self._status_by_obj.get(entity_id, [])

    def kind_key(self, e: Entity) -> tuple[int, int]:
        return (e.contentid, e.base)

    def real_enemy_kinds(self, min_hits: int = 10) -> set[tuple[int, int]]:
        """
        パーティから攻撃を受けた敵の種類 (contentid, bNpcBase)。
        見えない発射役・攻撃されないダミー・ペットは除外される。
        種類単位で判定する（後半フェーズに届かなかったプルの個体も「本物の種類」に含めるため）。
        """
        return {self.kind_key(e) for e in self.entities.values()
                if not e.is_pet and e.id >= ENEMY_ID_MIN and e.hits >= min_hits}

    def real_enemies(self, min_hits: int = 10) -> list[Entity]:
        """本物の敵の個体（攻撃を受けた個体）"""
        return [e for e in self.entities.values()
                if not e.is_pet and e.id >= ENEMY_ID_MIN and e.hits >= min_hits]

    def entities_in_pull(self, index: int) -> list[Entity]:
        return [e for e in self.entities.values() if e.pull == index]
