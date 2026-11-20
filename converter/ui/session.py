"""
ui/session.py — 変換ツールの画面の中身（pywebview に依存しない。テストから直接呼べる）

画面（ui/app.js）は ui/app.py の Api を通して、ここの Session を呼ぶ。値はすべて JSON にできる形で返す。

  タブ（開いたもの 1 つ＝1 タブ）
    kind = 'replay'  … リプレイ（.dat）を解析した結果（「リプレイ結果」）
    kind = 'record'  … 記録モードのログ（CSV）を解析した結果（「記録ログ結果」）
    kind = 'combined' … リプレイと記録ログを組にして解析した結果（「リプレイ＋記録ログ結果」。core/combined.py）
    kind = 'file'    … 既存のタイムライン（timelines/*.lua）を開いたもの

  画面での直し（edits）は、タイムラインの元（base）とは別に持ち、書き出すときに apply_edits で当てる。
  解析をやり直しても（プル・戦闘・フェーズの区切りを変えても）、同じイベント ID の直しはそのまま使える。

  edits = {
    'meta':     {'name': 表示名, 'author': ..., 'version': 1},
    'actions':  {アクションID: 技名},                    … タイムラインの actions 表（空文字は消す）
    'entities': {キー: {'name': 表示名, 'off': True}},     … off＝その敵の詠唱を全部外す
    'events':   {イベントID: {'name': ..., 'off': True, 'tolerance': 秒 or None, 'action': [ID, ...]}},
    'syncs':    {イベントID: True / False},              … 同期点を足す・外す
    'phases':   {フェーズID: {'name': ...}},
  }
"""
from __future__ import annotations

import copy
import datetime
import json
import os
import re
import statistics
import sys

from core.replay import Replay, ReplayFormatError, OpcodeStore
from core.recorder import RecordLog, RecordLogError, is_record_log
from core.combined import combine, LogWithBases
from core.analyze import analyze, AnalyzeOptions
from core.luatable import parse_file_text, parse_text, LuaTableError
from core.luatable import parse_file as parse_luafile
from core.plan_migrate import (timeline_events, entity_key_map, preview_plan, apply_plan,
                                PlanMigrateError)
from core.names import NameBook, merge_names
from export.timeline_lua import build_timeline, render_timeline, safe_name, lua_value
from export.csv import pull_result
from ui.version import VERSION

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SETTINGS_FILE = os.path.join(HERE, 'settings.json')
# MMOminion の既定の入れ場所（LuaMods\RaidTimeline）。ドライブは C〜Z を探す（find_luamods）
_MINION_SUB = os.path.join('MINIONAPP', 'Bots', 'FFXIVMinion64', 'LuaMods', 'RaidTimeline')
DEFAULT_LUAMODS = 'C:\\' + _MINION_SUB
# リプレイ：ドキュメント\My Games\FINAL FANTASY XIV - A Realm Reborn\replay（autorenamed があればそちら）
_REPLAY_SUB = os.path.join('My Games', 'FINAL FANTASY XIV - A Realm Reborn', 'replay')
BACKUP_KEEP = 10
BACKUP_RE = re.compile(r'^bak_(\d{8}_\d{6})(?:-(\d+))?_(.+)\.lua$')
TOOL_LINE = '-- （変換ツールで書き出し：'


class SessionError(Exception):
    """画面に出すエラー（文はそのまま見せる）"""


def documents_dirs() -> list:
    """
    ドキュメントフォルダの候補（スレッド #9：どの PC でも同じに動くように）。
    1. Windows に聞く（SHGetKnownFolderPath・FOLDERID_Documents）：OneDrive に移した・D ドライブに移した、も分かる
    2. ホームの下の OneDrive\\Documents・Documents・OneDrive\\ドキュメント
    """
    out = []
    if sys.platform == 'win32':
        try:
            import ctypes
            from ctypes import wintypes

            class GUID(ctypes.Structure):
                _fields_ = [('Data1', wintypes.DWORD), ('Data2', wintypes.WORD), ('Data3', wintypes.WORD),
                            ('Data4', ctypes.c_ubyte * 8)]
            fid = GUID(0xFDD39AD0, 0x238F, 0x46AF, (ctypes.c_ubyte * 8)(0xAD, 0xB4, 0x6C, 0x85, 0x48, 0x03, 0x69, 0xC7))
            p = ctypes.c_wchar_p()
            if ctypes.windll.shell32.SHGetKnownFolderPath(ctypes.byref(fid), 0, None, ctypes.byref(p)) == 0:
                out.append(p.value)
                ctypes.windll.ole32.CoTaskMemFree(p)
        except (OSError, AttributeError, ValueError):
            pass
    home = os.path.expanduser('~')
    out += [os.path.join(home, 'OneDrive', 'Documents'), os.path.join(home, 'Documents'),
            os.path.join(home, 'OneDrive', 'ドキュメント')]
    seen, res = set(), []
    for d in out:
        k = os.path.normcase(os.path.normpath(d))
        if d and k not in seen:
            seen.add(k)
            res.append(d)
    return res


def default_replay_dir() -> str:
    """FF14 のリプレイのフォルダ。replay\autorenamed（リプレイの名前を付け直すツールを使っている人）があればそちら"""
    for doc in documents_dirs():
        d = os.path.join(doc, _REPLAY_SUB)
        if os.path.isdir(os.path.join(d, 'autorenamed')):
            return os.path.join(d, 'autorenamed')
        if os.path.isdir(d):
            return d
    return os.path.expanduser('~')


def find_luamods() -> str | None:
    """
    アドオンのフォルダ（LuaMods\\RaidTimeline）を探す。C〜Z ドライブの MINIONAPP。
    RaidTimeline がまだ無くても LuaMods があれば、そこに置く前提でその場所を返す。見つからなければ None
    """
    if sys.platform != 'win32':
        return None
    lua_only = None
    for c in 'CDEFGHIJKLMNOPQRSTUVWXYZ':
        p = c + ':\\' + _MINION_SUB
        if os.path.isdir(p):
            return p
        if lua_only is None and os.path.isdir(os.path.dirname(p)):
            lua_only = p
    return lua_only


def _sec(x):
    return None if x is None else round(float(x), 1)


def _acts(v) -> list:
    if v is None:
        return []
    return [int(a) for a in (v if isinstance(v, (list, tuple)) else [v])]


def _actv(lst):
    lst = list(lst)
    return lst[0] if len(lst) == 1 else lst


def strip_private(v):
    """'_' で始まるキー（Lua に書かない補足）を除いた写し"""
    if isinstance(v, dict):
        return {k: strip_private(x) for k, x in v.items() if not (isinstance(k, str) and k.startswith('_'))}
    if isinstance(v, list):
        return [strip_private(x) for x in v]
    return v


def same_value(a, b) -> bool:
    """書き出した表と読み直した表が同じか（数は小数第 1 位に丸めて書くので、0.05 未満の差は同じとみなす）"""
    if isinstance(a, bool) or isinstance(b, bool):
        return a is b
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return abs(a - b) < 0.05 + 1e-9
    if isinstance(a, dict) and isinstance(b, dict):
        if set(map(str, a)) != set(map(str, b)):
            return False
        bb = {str(k): v for k, v in b.items()}
        return all(same_value(v, bb[str(k)]) for k, v in a.items())
    if isinstance(a, (list, tuple)) and isinstance(b, (list, tuple)):
        return len(a) == len(b) and all(same_value(x, y) for x, y in zip(a, b))
    if isinstance(a, dict) and isinstance(b, list) and not a:
        return not b
    if isinstance(a, list) and isinstance(b, dict) and not a:
        return not b
    return a == b


# ====================================================================== タブ

class Tab:
    def __init__(self, tid: str, kind: str, paths: list):
        self.id = tid
        self.kind = kind
        self.paths = list(paths)
        self.sources = []          # Replay / RecordLog
        self.options = dict(pulls=None, encounter=None, split=True, splits=None, real_only=False, unpair=[],
                            time_paired=True)
        self.replays = []          # combined：開いたリプレイ
        self.logs = []             # combined：開いた記録ログ
        self.pairs = []            # combined：組の一覧
        self.analysis = None
        self.base = None           # タイムラインの元（_info 付き）
        self.head = []             # file：先頭のコメント
        self.file_mtime = None     # file：開いたときの更新時刻
        self.load_warnings = []

    @property
    def title(self) -> str:
        if self.kind == 'file':
            return os.path.basename(self.paths[0])
        first = os.path.basename(self.paths[0]) if self.paths else ''
        more = ' ほか %d 件' % (len(self.paths) - 1) if len(self.paths) > 1 else ''
        return first + more


class Session:
    def __init__(self, settings_file: str | None = SETTINGS_FILE):
        self.settings_file = settings_file
        self.settings = dict(luamods='', replay_dir='', author='')
        if settings_file and os.path.exists(settings_file):
            try:
                with open(settings_file, encoding='utf-8') as f:
                    self.settings.update(json.load(f))
            except (OSError, ValueError):
                pass
        # 保存した場所が無い（設定が無い・別の PC に持ってきた）ときは探す（スレッド #9）。
        #   保存した場所があればそのまま使う（今まで使っていた PC は今までどおり）
        if not (self.settings.get('luamods') and os.path.isdir(self.settings['luamods'])):
            self.settings['luamods'] = find_luamods() or self.settings.get('luamods') or DEFAULT_LUAMODS
        if not (self.settings.get('replay_dir') and os.path.isdir(self.settings['replay_dir'])):
            self.settings['replay_dir'] = default_replay_dir()
        self.tabs: dict[str, Tab] = {}
        self._n = 0
        # opcode の保存ファイル：exe のときは exe の隣（書き込めるところ）
        base = os.path.dirname(sys.executable) if getattr(sys, 'frozen', False) else ROOT
        self.store = OpcodeStore(os.path.join(base, 'opcodes.json'))
        self.reload_names()

    # ------------------------------------------------------------------ 設定・場所
    def save_settings(self):
        if not self.settings_file:
            return
        try:
            with open(self.settings_file, 'w', encoding='utf-8') as f:
                json.dump(self.settings, f, ensure_ascii=False, indent=1)
        except OSError:
            pass

    def set_settings(self, **kw) -> dict:
        for k in ('luamods', 'replay_dir', 'author'):
            if k in kw and kw[k] is not None:
                self.settings[k] = str(kw[k])
        self.save_settings()
        self.reload_names()
        return self.info()

    @property
    def timelines_dir(self) -> str:
        return os.path.join(self.settings['luamods'], 'timelines')

    @property
    def logs_dir(self) -> str:
        return os.path.join(self.settings['luamods'], 'logs')

    @property
    def names_dir(self) -> str:
        return os.path.join(self.settings['luamods'], 'names')

    def reload_names(self):
        self.names = NameBook(self.names_dir if os.path.isdir(self.names_dir) else None)

    def info(self) -> dict:
        return dict(version=VERSION, settings=dict(self.settings), timelines_dir=self.timelines_dir, logs_dir=self.logs_dir,
                    luamods_ok=os.path.isdir(self.settings['luamods']), names=self.names.summary(),
                    timelines=self.list_timelines())

    def list_timelines(self) -> list:
        d = self.timelines_dir
        if not os.path.isdir(d):
            return []
        return sorted(f for f in os.listdir(d) if re.match(r'^\d+_[\w-]+\.lua$', f))

    # ------------------------------------------------------------------ 開く
    def _new_tab(self, kind, paths) -> Tab:
        self._n += 1
        t = Tab('t%d' % self._n, kind, paths)
        self.tabs[t.id] = t
        return t

    def open_replays(self, paths: list) -> dict:
        if not paths:
            raise SessionError('リプレイを選んでください')
        srcs, errs = [], []
        for p in paths:
            try:
                srcs.append(Replay(p, store=self.store))
            except (OSError, ReplayFormatError) as e:
                errs.append('%s: %s' % (os.path.basename(p), e))
        if not srcs:
            raise SessionError('読めませんでした：' + ' / '.join(errs))
        self.store.save()
        t = self._new_tab('replay', [s.path for s in srcs])
        t.sources = srcs
        t.load_warnings = errs
        self._analyze(t)
        return self.view(t.id)

    def open_logs(self, paths: list) -> dict:
        paths = [p for p in paths if is_record_log(p)]
        if not paths:
            raise SessionError('記録モードのログ（logs\\<mapid>\\<日時>.csv）を選んでください'
                               '（_dryrun.csv・_actions.csv は使いません）')
        srcs, errs = [], []
        for p in sorted(paths):
            try:
                srcs.append(RecordLog(p))
            except RecordLogError as e:
                errs.append(str(e))
        if not srcs:
            raise SessionError('読めませんでした：' + ' / '.join(errs))
        t = self._new_tab('record', [s.path for s in srcs])
        t.sources = srcs
        t.load_warnings = errs
        self._analyze(t)
        return self.view(t.id)

    def replay_mapid(self, replay_paths: list) -> int | None:
        """
        選んだリプレイのコンテンツ（mapid）。記録ログを選ぶ画面を logs\\<mapid> から開くため（スレッド #9）。
        いちばん多い mapid。読めなければ None
        """
        maps = []
        for p in replay_paths or []:
            try:
                m = Replay(p, store=self.store).mapid
            except (OSError, ReplayFormatError):
                continue
            if m:
                maps.append(m)
        return max(set(maps), key=maps.count) if maps else None

    def open_combined(self, replay_paths: list, log_paths: list) -> dict:
        """リプレイと記録ログを組にして開く（「リプレイ＋記録ログ結果」）"""
        if not replay_paths:
            raise SessionError('リプレイを選んでください')
        log_paths = [p for p in (log_paths or []) if is_record_log(p)]
        if not log_paths:
            raise SessionError('記録モードのログ（logs\\<mapid>\\<日時>.csv）を選んでください')
        reps, logs, errs = [], [], []
        for p in replay_paths:
            try:
                reps.append(Replay(p, store=self.store))
            except (OSError, ReplayFormatError) as e:
                errs.append('%s: %s' % (os.path.basename(p), e))
        for p in sorted(log_paths):
            try:
                logs.append(RecordLog(p))
            except RecordLogError as e:
                errs.append(str(e))
        if not reps or not logs:
            raise SessionError('読めませんでした：' + ' / '.join(errs))
        self.store.save()
        t = self._new_tab('combined', [r.path for r in reps] + [lg.path for lg in logs])
        t.replays, t.logs = reps, logs
        t.load_warnings = errs
        self._analyze(t)
        if not any(p['paired'] for p in t.pairs):
            t.load_warnings.append('組になったプルがありません（同じ戦闘のリプレイと記録ログか、時刻を確かめてください）。'
                                   'リプレイのプルとログのプルを別々に使います')
        return self.view(t.id)

    def open_timeline(self, path: str) -> dict:
        try:
            with open(path, 'rb') as f:
                text = f.read().decode('utf-8')
            tl, head = parse_file_text(text)
        except (OSError, UnicodeDecodeError) as e:
            raise SessionError('%s: 読めません（%s）' % (os.path.basename(path), e))
        except LuaTableError as e:
            raise SessionError('%s: アドオンが読めない書き方です（%s）' % (os.path.basename(path), e))
        if not isinstance(tl, dict) or tl.get('format') != 1 or not isinstance(tl.get('phases'), list):
            raise SessionError('%s: タイムライン（format = 1、phases あり）ではありません' % os.path.basename(path))
        t = self._new_tab('file', [path])
        t.head = [h for h in head if not h.startswith(TOOL_LINE)]
        t.file_mtime = os.path.getmtime(path)
        t.base = _file_base(tl)
        return self.view(t.id)

    def close(self, tid: str) -> bool:
        return self.tabs.pop(tid, None) is not None

    # ------------------------------------------------------------------ 解析
    def reanalyze(self, tid: str, options: dict) -> dict:
        t = self._tab(tid)
        if t.kind == 'file':
            raise SessionError('タイムラインのファイルは解析し直せません')
        for k in ('pulls', 'encounter', 'split', 'splits', 'real_only', 'unpair', 'time_paired'):
            if k in options:
                t.options[k] = options[k]
        self._analyze(t)
        return self.view(tid)

    def _analyze(self, t: Tab):
        o = t.options
        time_pulls = None
        if t.kind == 'combined':
            t.sources, t.pairs = combine(t.replays, t.logs, set(o.get('unpair') or []))
            if o.get('time_paired', True):
                multi = len(t.sources) > 1
                time_pulls = [('R%dP%d' % (ri + 1, idx + 1)) if multi else ('P%d' % (idx + 1))
                              for ri, s in enumerate(t.sources) for idx in getattr(s, 'logs', {})] or None
        opt = AnalyzeOptions(pulls=o.get('pulls') or None,
                             encounter=int(o['encounter']) if o.get('encounter') not in (None, '') else None,
                             split_phases=bool(o.get('split', True)),
                             phase_splits=o.get('splits'), time_pulls=time_pulls)
        an = analyze(t.sources, opt)
        t.analysis = an
        # 選んでいる戦闘を覚えておく（プルを変えても同じ戦闘を見る）
        sel = [e for e in an.encounters if e.selected]
        if sel and o.get('encounter') in (None, ''):
            o['encounter'] = sel[0].contentid
        tl = build_timeline(an, name='draft', real_casters_only=bool(o.get('real_only')),
                            source={'record': 'recorder', 'combined': 'replay+recorder'}.get(t.kind, 'replay'))
        slots = {}
        for s in an.all_slots():
            for part in s.parts:
                slots[part['event_id']] = (s, part)
        labels = an.pull_labels()
        for ph in tl['phases']:
            for ev in ph['events']:
                if ev['id'] not in slots:
                    continue
                s, part = slots[ev['id']]
                d = s.to_dict(labels)
                partner = next((x.event_id for x in an.all_slots() if x.id == s.partner), None) if s.partner else None
                single = len(s.parts) == 1
                ev['_info'] = dict(kind=s.kind, spread=s.spread, seen=s.seen, reached=len(s.reached),
                                   real=s.real_caster, contentid=s.source[0], base=s.source[1],
                                   by_pull=d['by_pull'], partner=partner,
                                   sync_ok=part.get('sync_ok', s.sync_ok), sync_nth=part.get('sync_nth', s.sync_nth),
                                   auto_sync=bool(s.sync) and single, t_combat=d['t_combat'],
                                   all_actions=list(s.all_actions) if single else [part['action']],
                                   together=[p['event_id'] for p in s.parts if p is not part])
        t.base = tl

    # ------------------------------------------------------------------ 画面に渡す形
    def _tab(self, tid) -> Tab:
        t = self.tabs.get(tid)
        if t is None:
            raise SessionError('タブがありません（%s）' % tid)
        return t

    def view(self, tid: str) -> dict:
        t = self._tab(tid)
        tl = t.base
        mapid = tl['meta'].get('mapid') or 0
        ids = _timeline_action_ids(tl)
        names = {}
        for a in sorted(ids):
            n = self.names.actions.get(a)
            for s in t.sources:
                n = getattr(s, 'action_names', {}).get(a) or n
            if (tl.get('actions') or {}).get(a):
                n = tl['actions'][a]
            if n:
                names[a] = n
        npcs = {}
        for key, e in tl['entities'].items():
            cid = e.get('contentid')
            n = self.names.npcs.get(cid)
            for s in t.sources:
                n = getattr(s, 'npc_names', {}).get(cid) or n
            if n:
                npcs[key] = n
        out = dict(id=t.id, kind=t.kind, title=t.title, paths=t.paths, mapid=mapid,
                   tl=tl, action_names=names, npc_names=npcs, warnings=list(t.load_warnings),
                   options=dict(t.options))
        if t.kind == 'file':
            out['fname'] = os.path.basename(t.paths[0])
            out['dest'] = os.path.dirname(os.path.abspath(t.paths[0]))
            out['head'] = t.head
            return out
        an = t.analysis
        out['warnings'] += an.warnings
        used = set(an.pull_labels())
        pulls = []
        multi = len(t.sources) > 1
        for ri, s in enumerate(t.sources):
            for p in s.pulls:
                label = ('R%dP%d' % (ri + 1, p.index + 1)) if multi else ('P%d' % (p.index + 1))
                pair = None
                if t.kind == 'record' or isinstance(s, LogWithBases):
                    res, pct = s.result, s.end_pct
                    sec = s.fight_sec()
                    when = s.recorded_at[11:19]
                else:
                    res, pct = pull_result(s, p.index)
                    sec = round((p.end_ms - p.t0_ms) / 1000, 1)
                    when = ''
                    if t.kind == 'combined':
                        lg = getattr(s, 'logs', {}).get(p.index)
                        if lg:
                            res, pct = lg[0].result, lg[0].end_pct
                            when = lg[0].recorded_at[11:19]
                        key = '%s#%d' % (s.file_name, p.index)
                        pr = next((x for x in t.pairs if x['key'] == key), None)
                        pair = dict(key=key, log=pr['log'] if pr else '', paired=bool(lg),
                                    shift=round(s.shift.get(p.index, 0) / 1000, 2), found=pr is not None,
                                    casts=pr['casts'] if pr else 0)
                enc = next((e.contentid for e in an.encounters if label in e.pulls), None)
                pulls.append(dict(label=label, file=s.file_name, sec=sec, result=res, pct=pct, used=label in used,
                                  encounter=enc, no_start=getattr(p, 'no_start', False), when=when,
                                  t0=getattr(s, 't0_source', 'engage'),
                                  engage=p.engage_offset if t.kind == 'replay' else None,
                                  short=p.duration < an.options.min_pull_sec, pair=pair,
                                  src='log' if isinstance(s, LogWithBases) else t.kind))
        out['pulls'] = pulls
        out['encounters'] = [dict(contentid=e.contentid, pulls=e.pulls, sec=e.total_sec, selected=e.selected,
                                  name=self._npc(t, e.contentid)) for e in an.encounters]
        out['candidates'] = [dict(kind=c.kind, contentid=c.contentid, entity=c.entity, actions=c.actions,
                                  times=c.times, median=c.median, adopted=c.adopted, phase=c.phase,
                                  hp=c.hp, hp_percent=c.hp_percent,
                                  nth=c.nth,
                                  name=self._npc(t, c.contentid)) for c in an.phase_candidates]
        out['phases_info'] = [dict(id=ph.id, starts={k: round(v / 1000, 1) for k, v in ph.starts.items()})
                              for ph in an.phases]
        out['pull_labels'] = an.pull_labels()
        out['pairs'] = list(t.pairs)
        out['default_name'] = 'draft'
        sel = next((e for e in an.encounters if e.selected), None)
        out['default_title'] = self._npc(t, sel.contentid) if sel else ''
        out['dest'] = self.timelines_dir
        return out

    def _npc(self, t, cid):
        n = self.names.npcs.get(cid)
        for s in t.sources:
            n = getattr(s, 'npc_names', {}).get(cid) or n
        return n or ''

    # ------------------------------------------------------------------ 直しを当てる
    def build(self, tid: str, edits: dict | None) -> dict:
        t = self._tab(tid)
        v = self.view(tid)
        edits = copy.deepcopy(edits or {})
        if t.kind != 'file':
            # 名前の既定値（画面で直していなければ）：敵は名前辞書・ログの名前、表示名は戦闘の敵の名前
            ents = edits.setdefault('entities', {})
            for key, name in v['npc_names'].items():
                e = ents.setdefault(key, {})
                if not str(e.get('name') or '').strip():
                    e['name'] = name
            meta = edits.setdefault('meta', {})
            if not str(meta.get('name') or '').strip() and v.get('default_title'):
                meta['name'] = v['default_title']
        return apply_edits(t.base, edits, v['action_names'], kind=t.kind, author=self.settings.get('author', ''))

    def render(self, tid: str, edits: dict | None) -> str:
        t = self._tab(tid)
        tl = self.build(tid, edits)
        if t.kind == 'file':
            stamp = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            head = list(t.head) + [TOOL_LINE + stamp + '。エントリの中のコメントは消えます）']
            return render_timeline(tl=tl, header=head)
        return render_timeline(t.analysis, tl=tl)

    def preview(self, tid: str, edits: dict | None, fname: str | None = None, dest: str | None = None) -> dict:
        t = self._tab(tid)
        text = self.render(tid, edits)
        fname, path = self._target(t, fname, dest)
        check = verify_text(text, self.build(tid, edits))
        return dict(text=text, fname=fname, path=path, exists=os.path.exists(path), check=check)

    def _target(self, t: Tab, fname, dest):
        mapid = t.base['meta'].get('mapid') or 0
        if t.kind == 'file' and not fname:
            fname = os.path.basename(t.paths[0])
        fname = (fname or 'draft').strip()
        if fname.lower().endswith('.lua'):
            fname = fname[:-4]
        if not re.match(r'^\d+_', fname):
            fname = '%d_%s' % (mapid, fname)
        stem = safe_name(fname)
        if not re.match(r'^\d+_[A-Za-z0-9_-]+$', stem):
            raise SessionError('ファイル名は <mapid>_<英数字・_・-> にしてください（%s）' % fname)
        dest = dest or (os.path.dirname(os.path.abspath(t.paths[0])) if t.kind == 'file' else self.timelines_dir)
        return stem + '.lua', os.path.join(dest, stem + '.lua')

    # ------------------------------------------------------------------ プランを移す（スレッド #9）
    def map_timelines(self, tid: str, dest: str | None = None) -> list:
        """書き出し先のフォルダにある、同じ mapid のタイムライン（名前の順。アドオンもこの順で先頭を使う）"""
        t = self._tab(tid)
        mapid = t.base['meta'].get('mapid') or 0
        _, path = self._target(t, 'x', dest)
        d = os.path.dirname(path)
        if not os.path.isdir(d):
            return []
        return sorted(f[:-4] for f in os.listdir(d)
                      if f.startswith('%d_' % mapid) and re.match(r'^[A-Za-z0-9_-]+\.lua$', f))

    def _plans_dir(self, t: Tab, path: str) -> str:
        mapid = t.base['meta'].get('mapid') or 0
        return os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(path))), 'plans', str(mapid))

    def plan_preview(self, tid: str, edits: dict | None, fname: str | None = None, dest: str | None = None,
                     src: str | None = None) -> dict:
        """
        書き出すタイムラインに、プランを移したらどうなるか（書かない）。
        src：プランが今使っているタイムライン（名前。省略は書き出し先と同じ名前＝上書き）
        """
        t = self._tab(tid)
        new_tl = self.build(tid, edits)
        fname, path = self._target(t, fname, dest)
        new_stem = fname[:-4]
        src = (src or new_stem).strip()
        if src.lower().endswith('.lua'):
            src = src[:-4]
        src_path = os.path.join(os.path.dirname(path), src + '.lua')
        out = dict(target=new_stem, target_exists=os.path.exists(path), src=src, src_exists=os.path.exists(src_path),
                   plans_dir=self._plans_dir(t, path), plans=[], new_version=_num(new_tl['meta'].get('version')),
                   counts=dict(same=0, moved=0, missing=0), key_map={})
        if not out['src_exists']:
            out['message'] = '元のタイムライン %s.lua がありません（移すプランはありません）' % src
            return out
        try:
            old_tl, _ = parse_luafile(src_path)
        except (OSError, LuaTableError) as e:
            out['message'] = '元のタイムライン %s.lua が読めません（%s）' % (src, e)
            return out
        old_ev = timeline_events(old_tl)
        new_ev = timeline_events(new_tl)
        km = entity_key_map(old_tl, new_tl)
        d = out['plans_dir']
        if os.path.isdir(d):
            for f in sorted(os.listdir(d)):
                if f.lower().endswith('.lua') and os.path.isfile(os.path.join(d, f)):
                    out['plans'].append(preview_plan(os.path.join(d, f), src, old_ev, new_ev, km))
        out['key_map'] = km
        out['counts'] = {k: sum(p['counts'].get(k, 0) for p in out['plans'] if p['use'])
                         for k in ('same', 'moved', 'missing')}
        out['message'] = ''
        return out

    # ------------------------------------------------------------------ 書き出し
    def export(self, tid: str, edits: dict | None, fname: str | None = None, dest: str | None = None,
               write_names: bool = False, overwrite: bool = False, migrate: dict | None = None) -> dict:
        """
        migrate（スレッド #9）：{ src: プランが今使っているタイムラインの名前, move_old: 別名のとき元のタイムラインを backup に移すか }。
          タイムラインを書いた後に、plans/<mapid>/ のプランを新しいタイムラインに移す
        """
        t = self._tab(tid)
        tl = self.build(tid, edits)
        text = self.render(tid, edits)
        fname, path = self._target(t, fname, dest)
        check = verify_text(text, tl)
        if not check['ok']:
            raise SessionError('書き出す前の確かめで違いが見つかったので書きませんでした：' + check['message'])
        pv = None
        if migrate:
            # 元のタイムラインを上書きする前に、対応付けを決めておく
            pv = self.plan_preview(tid, edits, fname, dest, migrate.get('src'))
        os.makedirs(os.path.dirname(path), exist_ok=True)
        backup = None
        if os.path.exists(path):
            if t.kind == 'file' and os.path.abspath(path) == os.path.abspath(t.paths[0]) \
                    and t.file_mtime is not None and abs(os.path.getmtime(path) - t.file_mtime) > 1e-6 \
                    and not overwrite:
                raise SessionError('開いた後に、ファイルが外で変わっています（別のエディタなど）。'
                                   '開き直すか、「それでも上書き」を選んでください')
            if not overwrite and t.kind != 'file':
                return dict(ok=False, need_overwrite=True, path=path,
                            message='%s はもうあります。上書きしますか（前の版は backup にとっておきます）' % fname)
            with open(path, 'rb') as f:
                old = f.read()
            if old == text.encode('utf-8'):
                res = dict(ok=True, path=path, backup=None, unchanged=True, message='中身が同じなので書きませんでした',
                           names=None)
                if pv is not None:
                    res['plans'] = self._migrate_plans(pv, migrate, path)
                res.update(self._first_timeline(tid, dest))
                return res
            backup = write_backup(os.path.dirname(path), fname, old)
        tmp = path + '.tmp'
        with open(tmp, 'wb') as f:
            f.write(text.encode('utf-8'))
        os.replace(tmp, path)
        with open(path, 'rb') as f:
            back = f.read()
        if back != text.encode('utf-8'):
            if backup:
                with open(os.path.join(os.path.dirname(path), 'backup', backup), 'rb') as f:
                    old = f.read()
                with open(path, 'wb') as f:
                    f.write(old)
            raise SessionError('書いた後に読み戻すと違ったので、前の版に戻しました')
        if t.kind == 'file' and os.path.abspath(path) == os.path.abspath(t.paths[0]):
            t.file_mtime = os.path.getmtime(path)
        names = None
        if write_names:
            add = {int(k): v for k, v in ((edits or {}).get('actions') or {}).items() if (v or '').strip()}
            names = merge_names(os.path.join(self.names_dir, 'actions.lua'), add) if add else \
                dict(written=False, changed=[], reason='直した技名はありません')
            self.reload_names()
        res = dict(ok=True, path=path, backup=backup, unchanged=False, names=names,
                   message='書き出しました：%s%s' % (path, '（前の版 backup\\%s）' % backup if backup else ''))
        if pv is not None:
            res['plans'] = self._migrate_plans(pv, migrate, path)
        res.update(self._first_timeline(tid, dest))
        return res

    def _first_timeline(self, tid, dest) -> dict:
        """このマップでアドオンが最初に使うタイムライン（名前の順の先頭。戦闘開始のときに敵がいる方へ切り替わることはある）"""
        try:
            lst = self.map_timelines(tid, dest)
        except SessionError:
            return {}
        return dict(first=lst[0] + '.lua', others=[x + '.lua' for x in lst[1:]]) if lst else {}

    def _migrate_plans(self, pv: dict, migrate: dict, path: str) -> dict:
        """プランを書き換え、別名なら元のタイムラインを backup に移す。失敗したプランは書かずに知らせる"""
        done, errs = [], []
        for p in pv['plans']:
            if not p['use']:
                continue
            try:
                done.append(apply_plan(os.path.join(pv['plans_dir'], p['file']), p, pv['target'], pv['new_version']))
            except (OSError, PlanMigrateError) as e:
                errs.append('%s：%s' % (p['file'], e))
        moved = None
        if migrate.get('move_old') and pv['src'] != pv['target'] and pv['src_exists']:
            src_path = os.path.join(os.path.dirname(path), pv['src'] + '.lua')
            with open(src_path, 'rb') as f:
                data = f.read()
            moved = write_backup(os.path.dirname(path), pv['src'] + '.lua', data)
            os.remove(src_path)
        return dict(done=done, errors=errs, moved_old=moved, counts=pv.get('counts') or {},
                    missing=[dict(file=p['file'], **r) for p in pv['plans'] if p['use']
                             for r in p['entries'] if r['kind'] == 'missing'])


# ====================================================================== 既存のタイムライン

def _file_base(tl: dict) -> dict:
    """開いたタイムラインを、解析の結果と同じ形（_info 付き）にする"""
    tl = copy.deepcopy(tl)
    tl.setdefault('meta', {})
    tl['entities'] = tl.get('entities') or {}
    if isinstance(tl['entities'], list):
        tl['entities'] = {}
    tl['actions'] = {int(k): v for k, v in (tl.get('actions') or {}).items()} if isinstance(tl.get('actions'), dict) else {}
    for ph in tl['phases']:
        ph['events'] = ph.get('events') or []
        ph['syncs'] = ph.get('syncs') or []
        for ev in ph['events']:
            m = ev.get('match') or {}
            acts = _acts(m.get('action'))
            # 同期点にできるのは、アクションが 1 つで、タイムラインの中でその敵・アクションが 1 回だけのもの（nth を推し量らない）
            same = sum(1 for p in tl['phases'] for e in p.get('events') or []
                       if (e.get('match') or {}).get('entity') == m.get('entity')
                       and _acts((e.get('match') or {}).get('action')) == acts)
            ev['_info'] = dict(kind='file', sync_ok=len(acts) == 1 and same == 1, sync_nth=None, all_actions=acts,
                               auto_sync=False)
        # 今ある同期点を、同じ敵・アクションで時刻の近いイベントに結び付ける
        for sy in ph['syncs']:
            on = sy.get('on') or {}
            best = None
            for ev in ph['events']:
                m = ev.get('match') or {}
                if m.get('entity') == on.get('entity') and _acts(m.get('action')) == _acts(on.get('action')):
                    d = abs(float(ev.get('t', 0)) - float(sy.get('t', 0)))
                    if d <= 2.0 and (best is None or d < best[0]):
                        best = (d, ev)
            if best:
                sy['_event'] = best[1]['id']
                best[1]['_info']['auto_sync'] = True
                best[1]['_info']['sync_ok'] = True
    return tl


def _timeline_action_ids(tl: dict) -> set:
    ids = set()
    for ph in tl['phases']:
        trig = ph.get('trigger') or {}
        ids.update(_acts(trig.get('action')))
        for ev in ph['events']:
            ids.update(_acts((ev.get('match') or {}).get('action')))
            ids.update((ev.get('_info') or {}).get('all_actions') or [])
        for sy in ph['syncs']:
            ids.update(_acts((sy.get('on') or {}).get('action')))
    return ids


# ====================================================================== 直しを当てる

def apply_edits(base: dict, edits: dict, action_names: dict | None = None, kind: str = 'replay',
                author: str = '') -> dict:
    """base（_info 付き）に edits を当てて、書き出す形のタイムライン（dict）を返す"""
    tl = copy.deepcopy(base)
    meta = tl['meta']
    em = edits.get('meta') or {}
    if em.get('name'):
        meta['name'] = str(em['name'])
    if 'author' in em:
        meta['author'] = str(em.get('author') or '')
    elif kind != 'file' and author and not meta.get('author'):
        meta['author'] = author
    if em.get('version') not in (None, ''):
        meta['version'] = int(em['version'])
    if kind != 'file' or edits:
        meta['updated'] = datetime.date.today().isoformat()

    ent_ed = edits.get('entities') or {}
    off_keys = {k for k, v in ent_ed.items() if (v or {}).get('off')}
    ev_ed = edits.get('events') or {}
    sy_ed = {k: bool(v) for k, v in (edits.get('syncs') or {}).items()}
    ph_ed = edits.get('phases') or {}

    for ph in tl['phases']:
        if (ph_ed.get(ph['id']) or {}).get('name'):
            ph['name'] = str(ph_ed[ph['id']]['name'])
        kept = []
        for ev in ph['events']:
            e = ev_ed.get(ev['id']) or {}
            m = ev.setdefault('match', {})
            if e.get('off') or m.get('entity') in off_keys:
                continue
            if 'name' in e and str(e['name']).strip():
                ev['name'] = str(e['name']).strip()
            if 'tolerance' in e:
                if e['tolerance'] in (None, ''):
                    ev.pop('tolerance', None)
                else:
                    ev['tolerance'] = _sec(e['tolerance'])
            if e.get('action'):
                m['action'] = _actv(_acts(e['action']))
            kept.append(ev)
        ph['events'] = kept
        alive = {ev['id']: ev for ev in kept}
        syncs = []
        has = set()
        for sy in ph['syncs']:
            evid = sy.get('_event')
            if evid is not None:
                if evid not in alive or sy_ed.get(evid) is False:
                    continue
                has.add(evid)
                ev = alive[evid]
                # イベントのアクションを直したら、同期点も合わせる
                sy['on']['action'] = (ev.get('match') or {}).get('action', sy['on'].get('action'))
            elif (sy.get('on') or {}).get('entity') in off_keys:
                continue
            syncs.append(sy)
        for ev in kept:
            if sy_ed.get(ev['id']) and ev['id'] not in has:
                info = ev.get('_info') or {}
                if not info.get('sync_ok'):
                    continue
                on = dict(type='cast_start', entity=ev['match'].get('entity'), action=ev['match'].get('action'))
                if info.get('sync_nth') is not None:
                    on['nth'] = info['sync_nth']
                syncs.append(dict(on=on, t=_sec(ev['t']), window=10.0, _event=ev['id'], _comment='画面で追加'))
        syncs.sort(key=lambda s: float(s.get('t', 0)))
        ph['syncs'] = syncs

    # 使っている敵だけ残す（本物の敵は残す）
    used = set()
    for ph in tl['phases']:
        used.add((ph.get('trigger') or {}).get('entity'))
        for ev in ph['events']:
            used.add((ev.get('match') or {}).get('entity'))
        for sy in ph['syncs']:
            used.add((sy.get('on') or {}).get('entity'))
    ents = {}
    for k, e in tl['entities'].items():
        if k in off_keys and k not in used:
            continue
        if kind != 'file' and k not in used and not str(e.get('_comment', '')).startswith('本物'):
            continue
        en = (ent_ed.get(k) or {}).get('name')
        if en and str(en).strip():
            e['name'] = str(en).strip()
        ents[k] = e
    tl['entities'] = ents

    # 技名（actions）：このタイムラインに出てくる ID だけ。画面の直し ＞ ファイルの actions ＞ 名前辞書・ログ
    ids = set()
    for ph in tl['phases']:
        ids.update(_acts((ph.get('trigger') or {}).get('action')))
        for ev in ph['events']:
            ids.update(_acts(ev['match'].get('action')))
        for sy in ph['syncs']:
            ids.update(_acts((sy.get('on') or {}).get('action')))
    acts = {}
    known = dict(action_names or {})
    known.update({int(k): v for k, v in (tl.get('actions') or {}).items()})
    for k, v in (edits.get('actions') or {}).items():
        known[int(k)] = (v or '').strip()
    for a in sorted(ids):
        if known.get(a):
            acts[a] = known[a]
    tl['actions'] = acts

    for ph in tl['phases']:
        for ev in ph['events']:
            ev.pop('_info', None)
    # 書く順番：format・meta・actions・entities・phases（ほかのキーは後ろに）
    order = ['format', 'meta', 'actions', 'entities', 'phases']
    return {k: tl[k] for k in order if k in tl} | {k: v for k, v in tl.items() if k not in order}


def verify_text(text: str, tl: dict) -> dict:
    """書き出す文字を、アドオンと同じ書き方の読み取りで読み直し、元の表と同じか確かめる"""
    try:
        back = parse_text(text)
    except LuaTableError as e:
        return dict(ok=False, message='読み直せません（%s）' % e)
    want = strip_private(tl)
    if not same_value(want, back):
        diff = [k for k in want if not same_value(want.get(k), back.get(k) if isinstance(back, dict) else None)]
        return dict(ok=False, message='読み直した表が違います（%s）' % ', '.join(map(str, diff)))
    n_ev = sum(len(ph['events']) for ph in want['phases'])
    n_sy = sum(len(ph['syncs']) for ph in want['phases'])
    return dict(ok=True, message='読み直して同じ表でした（フェーズ %d・イベント %d・同期点 %d・技名 %d）'
                % (len(want['phases']), n_ev, n_sy, len(want.get('actions') or {})))


def _num(v):
    """meta.version など：数なら数に（画面の入力は文字のことがある）"""
    if isinstance(v, (int, float)):
        return v
    try:
        f = float(str(v).strip())
        return int(f) if f.is_integer() else f
    except (TypeError, ValueError):
        return None


def write_backup(folder: str, fname: str, data: bytes) -> str:
    """folder/backup/bak_<日時>[-n]_<fname> に書き、同じ fname の古いものを BACKUP_KEEP 世代まで残す"""
    bdir = os.path.join(folder, 'backup')
    os.makedirs(bdir, exist_ok=True)
    stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
    # 同じ秒に何度も書いたら -2, -3 …（消した番号を使い回すと、新しいものが一番古く並んでしまうので、いちばん大きい番号の次）
    top = 0
    for b in os.listdir(bdir):
        m = BACKUP_RE.match(b)
        if m and m.group(1) == stamp and m.group(3) + '.lua' == fname:
            top = max(top, int(m.group(2) or 1))
    name = 'bak_%s_%s' % (stamp, fname) if top == 0 else 'bak_%s-%d_%s' % (stamp, top + 1, fname)
    with open(os.path.join(bdir, name), 'wb') as f:
        f.write(data)
    mine = []
    for b in os.listdir(bdir):
        m = BACKUP_RE.match(b)
        if m and m.group(3) + '.lua' == fname:
            mine.append(((m.group(1), int(m.group(2) or 1)), b))
    mine.sort()
    for _, b in mine[:-BACKUP_KEEP]:
        try:
            os.remove(os.path.join(bdir, b))
        except OSError:
            pass
    return name
