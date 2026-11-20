"""
スレッド #9：プランを新しいタイムラインに移す（core/plan_migrate.py・Session.plan_preview / export(migrate=...)）
"""
import os

import pytest

from core.luatable import parse_file
from core.plan_migrate import (timeline_events, map_event, entity_key_map, rewrite_plan_text, preview_plan,
                               apply_plan, save_plan_backup, PlanMigrateError)
from route_logs import make_route_logs, BOSS_CID


def _tl(phases, ents=None):
    return dict(meta=dict(mapid=9999, version=1), entities=ents or {'boss': {'contentid': 1}},
                phases=[dict(id=pid, events=[dict(id=eid, t=t, match=dict(entity=k, action=a)) for eid, t, k, a in evs])
                        for pid, evs in phases])


OLD = _tl([('p1', [('p1_10_1', 5, 'boss', 10), ('p1_11_1', 15, 'boss', 11), ('p1_10_2', 25, 'boss', 10)]),
           ('p2', [('p2_20_1', 3, 'boss', 20), ('p2_21or22_1', 9, 'boss', [21, 22]), ('p2_10_1', 30, 'boss', 10)])])


def test_map_event_kinds():
    new = timeline_events(_tl([
        ('p1', [('p1_10_1', 5.2, 'boss', 10), ('p1_11_1', 15.1, 'boss', 11), ('p1_10_2', 25, 'boss', 10)]),
        # フェーズの区切りが変わった：p2 → p3。p2 は別のきっかけで、20 はここに入る
        ('p2', [('p2_99_1', 0, 'boss', 99), ('p2_20_1', 6, 'boss', 20)]),
        ('p3', [('p3_21or22_1', 4, 'boss', [21, 22, 23]), ('p3_10_1', 25, 'boss', 10)])]))
    old = timeline_events(OLD)
    assert map_event(old['p1_10_1'], new)[:2] == ('same', 'p1_10_1')
    assert map_event(old['p2_20_1'], new)[:2] == ('same', 'p2_20_1')
    # 技の組が少し違う・フェーズが変わった：全体で何回目かで
    k, nid, note = map_event(old['p2_21or22_1'], new)
    assert (k, nid) == ('moved', 'p3_21or22_1') and '全体で 1 回目' in note
    # 10 の 3 回目：p2 → p3（全体で 3 回目）
    assert map_event(old['p2_10_1'], new)[:2] == ('moved', 'p3_10_1')
    assert map_event(None, new)[0] == 'missing'


def test_map_event_same_phase_nearest_and_missing():
    old = timeline_events(_tl([('p1', [('p1_10_1', 5, 'boss', 10), ('p1_10_2', 50, 'boss', 10)])]))
    # 新しいタイムラインには 10 が 1 回だけ（52 秒）：2 回目は「同じフェーズで時刻が近い」
    new = timeline_events(_tl([('p1', [('p1_10_1', 52, 'boss', 10)])]))
    k, nid, note = map_event(old['p1_10_2'], new)
    assert (k, nid) == ('moved', 'p1_10_1') and '時刻が近い' in note
    new2 = timeline_events(_tl([('p1', [('p1_77_1', 5, 'boss', 77)])]))
    assert map_event(old['p1_10_1'], new2)[0] == 'missing'


def test_entity_key_map():
    old = _tl([], ents={'boss': {'contentid': 1}, 'boss2': {'contentid': 2}, 'add': {'contentid': 3}})
    new = _tl([], ents={'boss': {'contentid': 1}, 'tower': {'contentid': 2}})
    assert entity_key_map(old, new) == {'boss2': 'tower'}


PLAN = '''-- テスト用のプラン
return {
    format = 1,
    meta = {
        mapid = 9999,
        job = "PLD",
        position = "MT",
    },

    entries = {
        {
            id = "e1", event = "p2_10_1", ref = "hit", offset = -1.0,
            action = { id = 7531, type = 1 }, target = { key = "boss2", type = "entity" },
            satisfiedBy = { buffs = { 1193 }, on = "boss2", owner = "any" },
            note = "p2 の 10",
        },
        {
            id = "e2", event = "p1_11_1", ref = "start", offset = 0.0,
            action = { id = 3540, type = 1 }, target = { type = "self" },
        },
    },
}
'''.replace('\n', '\r\n')


def test_rewrite_keeps_text_and_crlf(tmp_path):
    p = tmp_path / 'PLD_MT.lua'
    p.write_bytes(PLAN.encode('utf-8'))
    rows = [dict(id='e1', event='p2_10_1', new='p3_10_1', kind='moved'),
            dict(id='e2', event='p1_11_1', new='p1_11_1', kind='same')]
    keys = [dict(id='e1', where='target.key', old='boss2', new='tower'),
            dict(id='e1', where='satisfiedBy.on', old='boss2', new='tower')]
    out = rewrite_plan_text(PLAN, rows, keys, '9999_better', 3)
    assert '\r\n' in out and '\n' not in out.replace('\r\n', '')
    assert 'event = "p3_10_1"' in out and 'key = "tower"' in out and 'on = "tower"' in out
    # meta に無かった timeline / timelineVersion は mapid の行の後に足す
    assert 'mapid = 9999,\r\n        timeline = "9999_better",\r\n        timelineVersion = 3,' in out
    assert out.startswith('-- テスト用のプラン\r\n') and 'note = "p2 の 10",' in out
    pv = dict(file='PLD_MT.lua', entries=rows, keys=keys)
    r = apply_plan(str(p), pv, '9999_better', 3)
    assert r['written'] and os.path.exists(tmp_path / 'backup' / r['backup'])
    assert (tmp_path / 'backup' / r['backup']).read_bytes() == PLAN.encode('utf-8')
    v, _ = parse_file(str(p))
    assert v['entries'][0]['event'] == 'p3_10_1' and v['meta']['timeline'] == '9999_better'
    # もう一度：meta は書き換え（足さない）
    out2 = rewrite_plan_text(p.read_bytes().decode('utf-8'), [], [], '9999_best', 4)
    assert out2.count('timeline = ') == 1 and 'timeline = "9999_best"' in out2 and 'timelineVersion = 4' in out2


def test_rewrite_refuses_when_event_text_missing():
    rows = [dict(id='e1', event='p9_1_1', new='p1_1_1', kind='moved')]
    with pytest.raises(PlanMigrateError):
        rewrite_plan_text(PLAN, rows, [], '9999_x', 1)


def test_plan_backup_naming_and_keep(tmp_path):
    names = [save_plan_backup(str(tmp_path), 'PLD_MT.lua', b'x%d' % i) for i in range(12)]
    left = sorted(os.listdir(tmp_path / 'backup'))
    assert len(left) == 10
    # アドオンと同じ名前：PLD_MT_<YYYYMMDD_HHMMSS>[_n].lua。新しい方が残る
    assert all(n.startswith('PLD_MT_') for n in left) and names[-1] in left and names[0] not in left


def test_preview_skips_other_timeline_and_partial(tmp_path):
    other = PLAN.replace('mapid = 9999,', 'mapid = 9999,\r\n        timeline = "9999_other",')
    (tmp_path / 'A.lua').write_bytes(other.encode('utf-8'))
    old = timeline_events(OLD)
    pv = preview_plan(str(tmp_path / 'A.lua'), '9999_draft', old, old, {})
    assert not pv['use'] and '9999_other' in pv['reason']
    # timeline の無いプラン：元のタイムラインのイベントだけ（e1 も e2 も OLD にある）
    (tmp_path / 'B.lua').write_bytes(PLAN.encode('utf-8'))
    pv = preview_plan(str(tmp_path / 'B.lua'), '9999_draft', old, old, {})
    assert pv['use'] and pv['partial'] and pv['counts']['same'] == 2
    # 元のタイムラインに無いイベントは「別のタイムライン」としてそのまま
    small = timeline_events(_tl([('p1', [('p1_11_1', 15, 'boss', 11)])]))
    pv = preview_plan(str(tmp_path / 'B.lua'), '9999_draft', small, small, {})
    assert [r['kind'] for r in pv['entries']] == ['other', 'same']
    r = apply_plan(str(tmp_path / 'B.lua'), pv, '9999_new', 2)
    assert not r['written']       # meta.timeline の無いプランは meta を書かない・付け替えも無い


# ---------------------------------------------------------------- Session（書き出しと一緒に）
def test_session_export_migrates_plans(tmp_path):
    from ui.session import Session
    lm = tmp_path / 'RaidTimeline'
    paths = make_route_logs(str(lm / 'logs' / '9999'))
    s = Session(settings_file=None)
    s.set_settings(luamods=str(lm))
    v = s.open_logs(paths)
    tid = v['id']
    # 1. 区切りなしで書き出す（今のタイムライン）
    r = s.export(tid, {}, 'draft', None, False, False)
    assert r['ok'] and r['first'] == '9999_draft.lua'
    old, _ = parse_file(str(lm / 'timelines' / '9999_draft.lua'))
    ev = timeline_events(old)
    hit = next(e for e in ev.values() if e['acts'] == frozenset([3002]))      # フェーズ2 の 3002（区切りなしでは p1）
    plan = PLAN.replace('mapid = 9999,', 'mapid = 9999,\r\n        timeline = "9999_draft",') \
        .replace('"p2_10_1"', '"%s"' % hit['id']).replace('"p1_11_1"', '"p9_404_1"').replace('boss2', 'boss')
    (lm / 'plans' / '9999').mkdir(parents=True)
    (lm / 'plans' / '9999' / 'PLD_MT.lua').write_bytes(plan.encode('utf-8'))
    # 2. 「どこで来ても」で区切って、別名で書き出してプランを移す
    sp = [dict(type='cast_start', contentid=BOSS_CID, action=[7001], at=55, anywhere=True),
          dict(type='cast_start', contentid=BOSS_CID, action=[7101], at=55, anywhere=True),
          dict(type='cast_start', contentid=BOSS_CID, action=[2001], at=80, anywhere=True)]
    s.reanalyze(tid, {'splits': sp})
    pv = s.plan_preview(tid, {'meta': {'version': '2'}}, 'better', None, '9999_draft')
    assert pv['src_exists'] and pv['new_version'] == 2
    rows = {r['id']: r for r in pv['plans'][0]['entries']}
    assert rows['e1']['kind'] == 'moved' and rows['e1']['new'].endswith('_3002_1') and rows['e1']['new'] != hit['id']
    assert rows['e2']['kind'] == 'missing'
    r = s.export(tid, {'meta': {'version': '2'}}, 'better', None, False, False,
                 {'src': '9999_draft', 'move_old': True})
    assert r['plans']['errors'] == [] and r['plans']['moved_old'] and len(r['plans']['missing']) == 1
    assert sorted(os.listdir(lm / 'timelines')) == ['9999_better.lua', 'backup']
    assert r['first'] == '9999_better.lua' and r['others'] == []
    v2, _ = parse_file(str(lm / 'plans' / '9999' / 'PLD_MT.lua'))
    assert v2['meta']['timeline'] == '9999_better' and v2['meta']['timelineVersion'] == 2
    assert v2['entries'][0]['event'] == rows['e1']['new'] and v2['entries'][1]['event'] == 'p9_404_1'
    new, _ = parse_file(str(lm / 'timelines' / '9999_better.lua'))
    assert rows['e1']['new'] in timeline_events(new)
    assert len(os.listdir(lm / 'plans' / '9999' / 'backup')) == 1
