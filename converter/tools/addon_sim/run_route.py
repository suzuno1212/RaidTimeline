"""
v0.6.8（スレッド #9）：流れが枝分かれする戦闘（覚醒編零式 4 層の車型／人型の形）と、分岐の条件 onAction を確かめる

  python run_route.py
    変換ツールで、覚醒編 4 層を真似た記録ログ 4 プル（車型が先 2・人型が先 2）から、区切り「どこで来ても」で
    タイムラインを作る → アドオンでドライラン
    A：どちらの順番のプルでも、フェーズに正しく入る（p1 → 形態ブロック → 共通 → 逆の形態ブロック → フェーズ 2）
    B：形態ブロックのエントリは、そのブロックに入ったときに（⑥でも⑬でも）実行
    C：ライト／レフトのランダム（分岐イベント）のエントリに onAction：来た方だけ実行、来なかった方は「対象外（別の分岐）」
    D：onAction のエントリを詠唱より前に置いた：照合を待って、照合したときに実行（遅れとして書く）
    E：onAction のアクションがイベントに無い → 読み込みの警告
    F：火力でフェーズの長さが変わる戦闘（極エヌオーの雑魚フェーズの形。3 プルで火力が違う）：
       HP 60% 以下（hp_below）で雑魚フェーズ、ボスがターゲット可に戻ったら（targetable）後半。
       どのプルでも、フェーズの中の時刻で照合・実行。雑魚フェーズが短いプルでは、届かなかったエントリは「未到達（フェーズ移行）」
  RTL_TOOL：変換ツールのフォルダ（既定はこのフォルダの 2 つ上）
"""
import os, sys, tempfile, shutil, glob, csv, re
HERE = os.path.dirname(os.path.abspath(__file__))
TOOLDIR = os.environ.get('RTL_TOOL', os.path.dirname(os.path.dirname(HERE)))
sys.path.insert(0, TOOLDIR)
sys.path.insert(0, os.path.join(TOOLDIR, 'tests'))
from route_logs import make_route_logs, BOSS_CID, make_dps_logs, DPS_BOSS, DPS_PULLS
from core.recorder import RecordLog
from core.analyze import analyze, AnalyzeOptions
from export.timeline_lua import render_timeline

WORK = os.path.join(tempfile.gettempdir(), 'rtlsim_route')
shutil.rmtree(WORK, ignore_errors=True)
LOGDIR = os.path.join(WORK, 'logs')
TLDIR = os.path.join(WORK, 'timelines')
PLDIR = os.path.join(WORK, 'plans')
os.makedirs(TLDIR); os.makedirs(os.path.join(PLDIR, '9999'))
os.environ['RTL_LOGS'] = LOGDIR
os.environ['RTL_TIMELINES'] = TLDIR
os.environ['RTL_PLANS'] = PLDIR
from sim import *     # noqa: E402（環境変数を決めてから読む）

FAIL = []


def check(cond, msg):
    print(('  OK   ' if cond else '  NG   ') + msg)
    if not cond:
        FAIL.append(msg)


# ---- 変換ツール
paths = make_route_logs(os.path.join(LOGDIR, '9999'))
splits = [dict(type='cast_start', contentid=BOSS_CID, action=[7001], at=55, anywhere=True, name='車型'),
          dict(type='cast_start', contentid=BOSS_CID, action=[7101], at=55, anywhere=True, name='人型'),
          dict(type='cast_start', contentid=BOSS_CID, action=[2001], at=80, anywhere=True, name='岩盤崩落〜'),
          dict(type='cast_start', contentid=BOSS_CID, action=[3001], at=160, anywhere=True, name='フェーズ2')]
an = analyze([RecordLog(p) for p in paths], AnalyzeOptions(phase_splits=splits))
print('warnings:', an.warnings)
ph = {p.name: p for p in an.phases}
ids = {n: ph[n].id for n in ph}
print('phases:', ids)
text = render_timeline(an, name='route')
open(os.path.join(TLDIR, '9999_route.lua'), 'wb').write(text.encode('utf-8'))
evs = {}
for p in an.phases:
    for s in p.slots:
        for part in s.parts:
            evs[(p.name, part['action'] if isinstance(part['action'], int) else tuple(part['action']))] = part['event_id']
car3 = evs[('車型', 7003)]
hum3 = evs[('人型', 7103)]
lr = evs[('人型', (7104, 7105))]
mid3 = evs[('岩盤崩落〜', 2003)]
print('events:', car3, hum3, lr, mid3)

plan = '''return {
    format = 1,
    meta = { mapid = 9999, job = "PLD", position = "ANY" },
    entries = {
        { id = "car_rampart", event = "%(car3)s", ref = "hit", offset = -1.0, window = 3.0,
          action = { id = 7531, type = 1 }, target = { type = "self" }, execute = false },
        { id = "hum_rampart", event = "%(hum3)s", ref = "hit", offset = -1.0, window = 3.0,
          action = { id = 7531, type = 1 }, target = { type = "self" }, execute = false },
        { id = "mid_reprisal", event = "%(mid3)s", ref = "hit", offset = -1.0, window = 3.0,
          action = { id = 7535, type = 1 }, target = { type = "self" }, execute = false },
        { id = "lr_right", event = "%(lr)s", ref = "hit", offset = 0.0, window = 3.0,
          action = { id = 3540, type = 1 }, target = { type = "self" }, execute = false, onAction = 7104 },
        { id = "lr_left", event = "%(lr)s", ref = "hit", offset = 0.0, window = 3.0,
          action = { id = 7548, type = 1 }, target = { type = "self" }, execute = false, onAction = { 7105 } },
        { id = "lr_early", event = "%(lr)s", ref = "start", offset = -2.0, window = 3.0,
          action = { id = 25746, type = 1 }, target = { type = "self" }, execute = false, onAction = 7105 },
        { id = "lr_bad", event = "%(lr)s", ref = "hit", offset = 0.0,
          action = { id = 7533, type = 1 }, target = { type = "self" }, execute = false, onAction = 1234 },
        { id = "lr_snd", event = "%(lr)s", ref = "start", offset = 0.0,
          sound = { byAction = { [7104] = "test_a.wav", [7105] = "test_b.wav" } } },
    },
}
''' % dict(car3=car3, hum3=hum3, lr=lr, mid3=mid3)
open(os.path.join(PLDIR, '9999', 'PLD_ANY.lua'), 'wb').write(plan.replace('\n', '\r\n').encode('utf-8'))

# ---- 火力で長さが変わる戦闘（F）
dps_paths = make_dps_logs(os.path.join(LOGDIR, '9998'))
an2 = analyze([RecordLog(p) for p in dps_paths])
cand = {c.kind: c for c in an2.phase_candidates}
check(cand['hp_stop'].hp_percent == 60.0, 'F 変換ツール：候補「HP 60%% で分ける」（%s）' % cand['hp_stop'].hp)
check(cand['retargetable'].nth == 1, 'F 変換ツール：候補「ボスがターゲット可に戻った」（1 回目）')
sp2 = [dict(type='hp_below', contentid=DPS_BOSS, percent=cand['hp_stop'].hp_percent, at=cand['hp_stop'].median, name='雑魚'),
       dict(type='targetable', contentid=DPS_BOSS, state=True, at=cand['retargetable'].median, anywhere=True, nth=1, name='後半')]
an2 = analyze([RecordLog(p) for p in dps_paths], AnalyzeOptions(phase_splits=sp2))
ph2 = {p.name: p for p in an2.phases}
check(len(ph2['後半'].starts) == 3, 'F 変換ツール：後半はどのプルにもある（%s）' % ph2['後半'].starts)
open(os.path.join(TLDIR, '9998_dps.lua'), 'wb').write(render_timeline(an2, name='dps').encode('utf-8'))
ev2 = {}
for p in an2.phases:
    for sl in p.slots:
        for part in sl.parts:
            ev2[(p.name, part['action'])] = part['event_id']
os.makedirs(os.path.join(PLDIR, '9998'))
plan2 = '''return {
    format = 1,
    meta = { mapid = 9998, job = "PLD", position = "ANY" },
    entries = {
        { id = "p1_4003", event = "%s", ref = "hit", offset = -1.0, action = { id = 7531, type = 1 }, execute = false },
        { id = "add_5001", event = "%s", ref = "hit", offset = -1.0, action = { id = 7535, type = 1 }, execute = false },
        { id = "add_5003", event = "%s", ref = "hit", offset = -1.0, action = { id = 3540, type = 1 }, execute = false },
        { id = "late_6002", event = "%s", ref = "hit", offset = -1.0, action = { id = 7548, type = 1 }, execute = false },
    },
}
''' % (ev2[('フェーズ1', 4003)], ev2[('雑魚', 5001)], ev2[('雑魚', 5003)], ev2[('後半', 6002)])
open(os.path.join(PLDIR, '9998', 'PLD_ANY.lua'), 'wb').write(plan2.replace('\n', '\r\n').encode('utf-8'))

# ---- アドオン
s = Sim(os.path.join(WORK, 'simroot'), use_folderlist=False)
s.set_map(9999)
print('loaded:', s.L.eval('RTL.tl.file'), s.L.eval('RTL.tl.planFile'))
warns = list(s.L.eval('RTL.tl.planWarn').values())
print('planWarn:', warns)
check(any('lr_bad' in w and 'onAction' in w for w in warns), 'E：onAction がイベントに無い → 警告')
check(not any(w.startswith('lr_right') or w.startswith('lr_left') or w.startswith('lr_early') for w in warns),
      'E：正しい onAction には警告なし')
for f in paths:
    s.replay(f, first_action_at=0.5)
print('errors:', s.errors())
check(s.errors()[0] is None and not s.errors()[1], 'Lua のエラーなし')

want_order = {True: ['p1', ids['車型'], ids['岩盤崩落〜'], ids['人型'], ids['フェーズ2']],
              False: ['p1', ids['人型'], ids['岩盤崩落〜'], ids['車型'], ids['フェーズ2']]}
from route_logs import PULLS
car_first = [c for c, _ in PULLS]
lr_first = [x for _, x in PULLS]
def pull_order(f):   # 同じ秒のプルは _2・_3 …（名前の順では _2 が先に来るので、番号で並べる）
    m = re.match(r'(\d+_\d+)(?:_(\d+))?_dryrun', os.path.basename(f))
    return (m.group(1), int(m.group(2) or 1))


for i, f in enumerate(sorted(s.dryrun_files(9999), key=pull_order)):
    rows = list(csv.DictReader(open(f, encoding='utf-8-sig')))
    tag = 'P%d（%s が先・%d）' % (i + 1, '車型' if car_first[i] else '人型', lr_first[i])
    order = [r['ref'] for r in rows if r['kind'] == 'phase_enter']
    check(order == want_order[car_first[i]], 'A %s：フェーズの順 %s' % (tag, order))
    sm = summary(rows)
    check(sm['nomatch'] == 0, 'A %s：未照合なし（照合 %d・平均 %.2f・最大 %.2f）' % (tag, sm['match'], sm['avg'], sm['max']))
    dry = {r['ref']: r for r in rows if r['kind'] == 'dryrun'}
    for k in ('car_rampart', 'hum_rampart', 'mid_reprisal'):
        r = dry.get(k)
        check(r is not None and r['result'].startswith('実行') and abs(float(r['diff'] or 99)) < 0.2,
              'B %s：%s → %s（diff %s・%s）' % (tag, k, r and r['result'], r and r['diff'], r and r['phase']))
    right, left, early = dry.get('lr_right'), dry.get('lr_left'), dry.get('lr_early')
    if lr_first[i] == 7104:
        check(right and right['result'].startswith('実行'), 'C %s：lr_right（7104 のとき）→ %s' % (tag, right and right['result']))
        check(left and left['result'] == '対象外（別の分岐）', 'C %s：lr_left（7105 のとき）→ %s' % (tag, left and left['result']))
        check(early and early['result'] == '対象外（別の分岐）', 'D %s：lr_early（7105 のとき・2 秒前）→ %s' % (tag, early and early['result']))
    else:
        check(left and left['result'].startswith('実行'), 'C %s：lr_left（7105 のとき）→ %s' % (tag, left and left['result']))
        check(right and right['result'] == '対象外（別の分岐）', 'C %s：lr_right（7104 のとき）→ %s' % (tag, right and right['result']))
        check(early and early['result'].startswith('実行') and '分岐の照合を待った（2.' in early['detail'],
              'D %s：lr_early（7105 のとき・2 秒前）→ %s / %s' % (tag, early and early['result'], early and early['detail'][-40:]))
    bad = dry.get('lr_bad')
    check(bad and bad['result'] == '対象外（別の分岐）', 'E %s：lr_bad → %s' % (tag, bad and bad['result']))
    snd = [r for r in rows if r['kind'] == 'sound']
    want_wav = 'test_a.wav' if lr_first[i] == 7104 else 'test_b.wav'
    check(any(want_wav in r['detail'] for r in snd), 'C %s：音の byAction → %s' % (tag, [r['detail'] for r in snd]))

# F：火力で長さが変わる戦闘
s.set_map(9998)
print('loaded:', s.L.eval('RTL.tl.file'), s.L.eval('RTL.tl.planFile'), list(s.L.eval('RTL.tl.planWarn').values()))
for f in dps_paths:
    s.replay(f, first_action_at=0.5)
check(s.errors()[0] is None and not s.errors()[1], 'F：Lua のエラーなし')
for i, f in enumerate(sorted(s.dryrun_files(9998), key=pull_order)):
    rate, kill = DPS_PULLS[i]
    tag = 'P%d（%.2f%%/秒・雑魚 %d 秒）' % (i + 1, rate, kill)
    rows = list(csv.DictReader(open(f, encoding='utf-8-sig')))
    ent = [(r['ref'], float(r['t']), r['detail'].split(' / ')[1] if ' / ' in r['detail'] else '') for r in rows if r['kind'] == 'phase_enter']
    push, back = 40.0 / rate, 40.0 / rate + 1.0 + kill + 1.0
    check([e[0] for e in ent] == ['p1', 'p2', 'p3'] and abs(ent[1][1] - ent[0][1] - push) < 1.1 and abs(ent[2][1] - ent[0][1] - back) < 0.2,
          'F %s：p2（HP %.1f 秒ごろ）・p3（ターゲット可 %.1f 秒）に入る：%s' % (tag, push, back, ent))
    sm = summary(rows)
    check(sm['nomatch'] == 0 and sm['max'] <= 1.1, 'F %s：未照合なし・ずれ最大 %.2f 秒' % (tag, sm['max']))
    dry = {r['ref']: r for r in rows if r['kind'] == 'dryrun'}
    for k in ('p1_4003', 'add_5001', 'late_6002'):
        r = dry.get(k)
        check(r is not None and r['result'].startswith('実行') and abs(float(r['diff'])) < 0.2,
              'F %s：%s → %s（diff %s）' % (tag, k, r and r['result'], r and r['diff']))
    r = dry.get('add_5003')
    want = '実行' if kill >= 28 else '未到達（フェーズ移行）'
    check(r is not None and r['result'].startswith(want), 'F %s：add_5003（雑魚フェーズの 25 秒）→ %s' % (tag, r and r['result']))

print('FAIL:', len(FAIL))
for m in FAIL:
    print('  ', m)
