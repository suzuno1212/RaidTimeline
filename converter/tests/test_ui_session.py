"""
変換ツールの画面から呼ぶ関数のテスト（スレッド #8）

  - core/luatable.py（タイムラインを Lua として実行せずに読む）
  - core/names.py（名前辞書の読み書き）
  - core/recorder.py（記録モードのログ CSV を analyze に流す）
  - core/analyze.py の手で決めたフェーズの区切り（phase_splits）
  - ui/session.py（開く・解析し直す・直しを当てる・書き出す・前の版）

記録ログ・タイムラインは、アドオンのフォルダ（環境変数 RT_ADDON_DIR → C〜Z ドライブの MINIONAPP\\...\\LuaMods\\RaidTimeline）から読む。
無ければ、それを使うテストはスキップする。
"""
import glob
import os
import shutil

import pytest

from conftest import SUSANO, find, lua_runtime
from core.luatable import parse_text, parse_file_text, LuaTableError
from core.names import read_names, merge_names, render_names
from core.recorder import RecordLog, is_record_log, BASE_MS
from core.analyze import analyze, AnalyzeOptions
from export.timeline_lua import render_timeline
from ui.session import Session, SessionError, apply_edits, verify_text, write_backup, BACKUP_RE
from core.combined import combine, ReplayWithLogs, LogWithBases

from ui.session import find_luamods     # noqa: E402

# アドオンのフォルダ：RT_ADDON_DIR → C〜Z ドライブの MINIONAPP（変換ツールと同じ探し方）。無ければ実データのテストは飛ばす
ADDON = os.environ.get('RT_ADDON_DIR') or find_luamods() or ''
MIST_LOGS = sorted(p for p in glob.glob(os.path.join(ADDON, 'logs', '1314', '*.csv')) if is_record_log(p))
SUSA_LOGS = sorted(p for p in glob.glob(os.path.join(ADDON, 'logs', '674', '*.csv')) if is_record_log(p))
TIMELINES = sorted(glob.glob(os.path.join(ADDON, 'timelines', '*.lua')))
BOSS2 = 14271          # ミストウェイク 2 ボス（アムドゥシアス）


def need_logs(lst, what):
    if not lst:
        pytest.skip('%s の記録ログがありません（RT_ADDON_DIR）' % what)
    return lst


@pytest.fixture
def session(tmp_path):
    """アドオンのフォルダの写し（timelines・names）を使う Session"""
    lm = tmp_path / 'RaidTimeline'
    (lm / 'timelines').mkdir(parents=True)
    (lm / 'names').mkdir()
    for f in TIMELINES:
        shutil.copy(f, lm / 'timelines')
    for f in glob.glob(os.path.join(ADDON, 'names', '*.lua')):
        shutil.copy(f, lm / 'names')
    s = Session(settings_file=None)
    s.set_settings(luamods=str(lm), author='test')
    return s


# ====================================================================== luatable

def test_luatable_reads_spec_syntax():
    text = ('\ufeff-- 先頭のコメント\r\n--[[ 長い\r\nコメント ]]\r\nreturn {\r\n'
            '  format = 1, ["a b"] = "x\\"y\\\\z", [10] = 0x1F, n = -2.5e1; s = [[long]],\r\n'
            '  list = { 1, 2, 3, }, t = true, f = false, z = nil,\r\n'
            '  mix = { 7, k = "v" },\r\n}\r\n')
    v, head = parse_file_text(text)
    assert head == ['-- 先頭のコメント', '--[[ 長い', 'コメント ]]']
    assert v['format'] == 1 and v['a b'] == 'x"y\\z' and v[10] == 31 and v['n'] == -25.0 and v['s'] == 'long'
    assert v['list'] == [1, 2, 3] and v['t'] is True and v['f'] is False and 'z' not in v
    assert v['mix'] == {1: 7, 'k': 'v'}


@pytest.mark.parametrize('bad', [
    'return { a = b }',                    # 変数
    'return { a = f() }',                  # 関数呼び出し
    'return { a = 1 + 2 }',                # 演算
    'local x = 1 return { }',              # local
    'return { a = 1 } x = 2',              # 後ろに何か
    'return { a = "abc }',                 # 閉じていない
])
def test_luatable_rejects_code(bad):
    with pytest.raises(LuaTableError):
        parse_text(bad)


# ====================================================================== names

def test_names_read_merge(tmp_path):
    p = tmp_path / 'actions.lua'
    p.write_bytes(render_names({38383: '技"A"', 5: 'テレポ'}).encode('utf-8'))
    n, bad = read_names(str(p))
    assert n == {5: 'テレポ', 38383: '技"A"'} and bad == []
    r = merge_names(str(p), {38383: '技"A"', 777: '新しい技'})
    assert r['written'] and r['changed'] == [777]
    text = p.read_bytes().decode('utf-8')
    assert text.endswith('}\r\n') and '    [777] = "新しい技",\r\n' in text and '\\"A\\"' in text
    assert text.index('[5]') < text.index('[777]') < text.index('[38383]')       # ID の小さい順
    # 読めない行があれば書かない（手で直したものを壊さない）
    p.write_bytes(('return {\r\n    [1] = "a",\r\n    oops\r\n}\r\n').encode('utf-8'))
    r = merge_names(str(p), {2: 'b'})
    assert not r['written'] and '3 行目' in r['reason']


# ====================================================================== 記録ログ


# ====================================================================== Session


def test_backup_keeps_10(tmp_path):
    for i in range(13):
        write_backup(str(tmp_path), '1314_x.lua', b'%d' % i)
    write_backup(str(tmp_path), '1314_y.lua', b'y')
    names = os.listdir(tmp_path / 'backup')
    assert len([n for n in names if n.endswith('_1314_x.lua')]) == 10 and any(n.endswith('_1314_y.lua') for n in names)
    kept = sorted(open(tmp_path / 'backup' / n, 'rb').read() for n in names if n.endswith('_1314_x.lua'))
    assert b'0' not in kept and b'12' in kept           # 古いものから消える（-10 が -2 より前にならない）


def test_apply_edits_entity_off_and_sync_off():
    base = dict(format=1, meta=dict(name='x', mapid=1, version=1), actions={}, entities=dict(
        boss=dict(name='b', contentid=1, _comment='本物の敵'), npc2=dict(name='n', contentid=2, _comment='詠唱だけ')),
        phases=[dict(id='p1', name='p', trigger=dict(type='combat_start'), events=[
            dict(id='e1', name='1 #1', t=1.0, cast=2.0, match=dict(entity='boss', action=1), _info=dict(sync_ok=True)),
            dict(id='e2', name='2 #1', t=3.0, cast=2.0, match=dict(entity='npc2', action=2), _info=dict(sync_ok=True))],
            syncs=[dict(on=dict(type='cast_start', entity='boss', action=1), t=1.0, window=10.0, _event='e1')])])
    tl = apply_edits(base, dict(entities=dict(npc2=dict(off=True)), syncs=dict(e1=False)), {1: '技1', 2: '技2'})
    assert [e['id'] for e in tl['phases'][0]['events']] == ['e1'] and tl['phases'][0]['syncs'] == []
    assert 'npc2' not in tl['entities'] and tl['actions'] == {1: '技1'}


# ====================================================================== リプレイ＋記録ログ（core/combined.py）


