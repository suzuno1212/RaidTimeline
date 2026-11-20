"""
記録モードのログ CSV を、MMOminion を模した LuaJIT 環境で再生し、RaidTimeline.lua（v0.2.0）のドライランを確かめる。

  run_susanoo.py / run_mist.py / run_scen.py から使う（pip install lupa。LuaJIT 2.1 で動く）

再生のしかた
  - appear / disappear / targetable / hp / first_hit → 敵の状態
  - cast_start → Argus.registerOnEntityChannel、cast_end → registerOnEntityCast
  - buff_gain / buff_lose → 自分・敵のバフ。自分が自分に付けたバフは、そのアクションを使ったことにする（OnEntityCast）
  - combat_start → Player.incombat = true、wipe / clear → false
  - Gameloop.Update / Draw を 50 ms ごとに呼ぶ
"""
import csv, os, shutil, sys, glob, random, base64
import lupa.luajit21 as lj

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.dirname(HERE)
# 場所は環境変数で変えられる（既定はこのリポジトリの中）
#   RTL_LOGS      記録モードのログ（logs フォルダ）
#   RTL_ADDON     RaidTimeline.lua
#   RTL_TIMELINES タイムライン（*.lua）のフォルダ
#   RTL_PLANS     plans フォルダ
LOGS = os.environ.get('RTL_LOGS', '')
ADDON = os.environ.get('RTL_ADDON', os.path.join(TOOL, '..', '..', 'addon', 'RaidTimeline', 'RaidTimeline.lua'))
TIMELINES = os.environ.get('RTL_TIMELINES', os.path.join(TOOL, 'out'))
PLANS = os.environ.get('RTL_PLANS', os.path.join(TOOL, 'plans'))
WAVS = os.environ.get('RTL_WAVS', os.path.join(TOOL, 'wav'))
ME = 268435457
BUFF_TO_ACTION = {1191: 7531, 2674: 25746, 3829: 36920, 1362: 3540, 1209: 7548, 82: 30}


def num(s, conv=float):
    s = (s or '').strip()
    return conv(s) if s else None


class Sim:
    def __init__(self, root, use_folderlist=True, addon=None):
        self.root = root
        if os.path.exists(root):
            shutil.rmtree(root)
        base = os.path.join(root, 'RaidTimeline')
        os.makedirs(os.path.join(base, 'timelines'))
        for f in glob.glob(os.path.join(TIMELINES, '*.lua')):
            shutil.copy(f, os.path.join(base, 'timelines'))
        shutil.copytree(PLANS, os.path.join(base, 'plans'))
        os.makedirs(os.path.join(base, 'names'))
        # wav（v0.4.0）：WAVS のフォルダを RaidTimeline\wav にコピーする
        if os.path.isdir(WAVS):
            shutil.copytree(WAVS, os.path.join(base, 'wav'))
        self.L = lj.LuaRuntime(unpack_returned_tuples=True)
        g = self.L.globals()
        g.SIM_ROOT = root
        g.SIM_USE_FOLDERLIST = use_folderlist
        g.PY_ISDIR = lambda p: os.path.isdir(p)
        g.PY_MKDIR = lambda p: os.makedirs(p, exist_ok=True)
        g.PY_LISTDIR = lambda p: self.L.table_from(sorted(os.listdir(p)) if os.path.isdir(p) else [])
        g.PY_B64U16DEC = lambda b: base64.b64decode(b).decode('utf-16-le')
        self.L.execute(open(os.path.join(HERE, 'mock.lua'), encoding='utf-8').read())
        src = open(addon or ADDON, 'rb').read().decode('utf-8')
        self.L.execute(src)
        self.g = g
        self.SIM = g.SIM
        self.f = {k: g[k] for k in ('SIM_Fire', 'SIM_Appear', 'SIM_Remove', 'SIM_Tg', 'SIM_Hp', 'SIM_HpDrop',
                                     'SIM_Channel', 'SIM_Cast', 'SIM_Buff', 'SIM_Party')}
        self.f['SIM_Fire']('Module.Initalize')
        self.next_tick = self.SIM.now

    @property
    def now(self):
        return self.SIM.now

    def advance(self, to_ms):
        """to_ms まで 50 ms ごとに Update / Draw を回す"""
        while self.next_tick <= to_ms:
            self.SIM.now = self.next_tick
            self.f['SIM_Fire']('Gameloop.Update')
            self.f['SIM_Fire']('Gameloop.Draw')
            self.next_tick += 50
        self.SIM.now = to_ms

    def set_map(self, mapid):
        self.g.Player.localmapid = mapid
        self.f['SIM_Party'](mapid)
        self.advance(self.now + 1000)

    def replay(self, path, shift=None, jitter=0.0, first_action_at=None, seed=1, start_gap_ms=5000, after_ms=4000, self_buff_cast=True, inject=None,
               hostile_at=None, buff_at=None):
        """hostile_at：その秒に自分の攻撃（first_hit の敵を対象。castingtargets に入る）
           buff_at  ：その秒に自分のバフ（自分が対象。敵対ではない）"""
        """ログ CSV を再生する。shift = (秒, ずらす秒)：その秒以降の詠唱をずらす"""
        rnd = random.Random(seed)
        rows = list(csv.DictReader(open(path, encoding='utf-8-sig')))
        t_min = min(float(r['t']) for r in rows)
        base = self.now + start_gap_ms - t_min * 1000
        acts = []
        for r in rows:
            t = float(r['t'])
            k = r['kind']
            if k in ('cast_start', 'cast_end'):
                if shift and t >= shift[0]:
                    t += shift[1]
                if jitter:
                    t += rnd.uniform(-jitter, jitter)
            acts.append((base + t * 1000, r))
        for (it, iid) in (inject or []):
            acts.append((base + it * 1000, {'kind': '_use', 'action_id': str(iid)}))
        if first_action_at is not None:
            acts.append((base + first_action_at * 1000, {'kind': '_first_action'}))
        if hostile_at is not None:
            tgt = next((r['entity_id'] for r in rows if r['kind'] == 'first_hit'), None)
            acts.append((base + hostile_at * 1000, {'kind': '_hostile', 'entity_id': tgt}))
        if buff_at is not None:
            acts.append((base + buff_at * 1000, {'kind': '_selfbuff'}))
        acts.sort(key=lambda x: x[0])
        end_ms = base
        F = self.f
        for ms, r in acts:
            self.advance(ms)
            k = r['kind']
            eid = num(r.get('entity_id'), int)
            if k == 'appear':
                F['SIM_Appear'](eid, num(r['contentid'], int) or 0, r['name'], num(r['max_hp'], int) or 1, False)
            elif k == 'disappear':
                F['SIM_Remove'](eid)
            elif k == 'targetable':
                F['SIM_Tg'](eid, r['v1'] == '1')
            elif k == 'hp':
                F['SIM_Hp'](eid, num(r['v2'], int), float(r['v1']))
            elif k == 'first_hit':
                F['SIM_HpDrop'](eid)
            elif k == 'cast_start':
                F['SIM_Channel'](eid, num(r['action_id'], int), num(r['target_id'], int) or 0, num(r['cast']) or 0)
            elif k == 'cast_end':
                F['SIM_Cast'](eid, num(r['action_id'], int))
            elif k in ('buff_gain', 'buff_lose'):
                bid = num(r['action_id'], int)
                owner = num(r['v2'], int) or 0
                F['SIM_Buff'](eid, bid, owner, num(r['v1']) or 0, k == 'buff_gain')
                if self_buff_cast and k == 'buff_gain' and eid == ME and owner == ME and bid in BUFF_TO_ACTION:
                    F['SIM_Cast'](ME, BUFF_TO_ACTION[bid])
            elif k == 'combat_start':
                self.g.Player.incombat = True
            elif k in ('wipe', 'clear'):
                if k == 'clear' and eid:
                    F['SIM_Hp'](eid, 0, 0.0)   # ログの clear 行は「最後に攻撃された敵の HP が 0」
                self.g.Player.incombat = False
                end_ms = ms
            elif k == '_use':
                self.g.SIM_Use(int(r['action_id']))   # 自分のアクション（RaidTimeline 以外：ACR・手動の代わり）
            elif k == '_first_action':
                F['SIM_Cast'](ME, 9)   # 自分の攻撃（パーティのアクション）
            elif k == '_hostile':
                F['SIM_Cast'](ME, 24, eid)   # 敵を対象にした自分のアクション（シールドロブ）
            elif k == '_selfbuff':
                F['SIM_Cast'](ME, 20)   # 自分が対象（ファイト・オア・フライト。敵対ではない）
        self.g.Player.incombat = False
        self.SIM.queue = self.L.table()
        self.advance(max(self.now, end_ms) + after_ms)
        # 敵を片付ける（次のプルのため）
        for eid in list(self.SIM.ents.keys()):
            F['SIM_Remove'](eid)
        return base

    def dryrun_files(self, mapid):
        return sorted(glob.glob(os.path.join(self.root, 'RaidTimeline', 'logs', str(mapid), '*_dryrun.csv')))

    def errors(self):
        L = self.L.eval('RTL.lastError')
        logs = [s for s in self.SIM.log.values() if 'error' in s]
        return L, logs


def show(path, kinds=None, limit=200):
    rows = list(csv.DictReader(open(path, encoding='utf-8-sig')))
    print('---', os.path.basename(path), len(rows), 'rows')
    for r in rows[:limit]:
        if kinds and r['kind'] not in kinds:
            continue
        print('  %6s %7s %-3s %-12s %-22s %-6s %7s %7s %6s %s | %s' % (
            r['t'], r['clock'], r['phase'], r['kind'], r['ref'][:22], r['action'], r['planned'], r['actual'],
            r['diff'], r['result'], r['detail']))
    return rows


def summary(rows):
    m = [abs(float(r['diff'])) for r in rows if r['kind'] == 'match']
    return {'match': len(m), 'avg': sum(m) / len(m) if m else 0, 'max': max(m) if m else 0,
            'sync': sum(1 for r in rows if r['kind'] == 'sync'),
            'sync_skip': sum(1 for r in rows if r['kind'] == 'sync_skip'),
            'nomatch': sum(1 for r in rows if r['kind'] == 'nomatch'),
            'cast': sum(1 for r in rows if r['kind'] == 'cast'),
            'phases': [(r['ref'], r['t']) for r in rows if r['kind'] == 'phase_enter'],
            'dry': [(r['ref'], r['result']) for r in rows if r['kind'] == 'dryrun']}
