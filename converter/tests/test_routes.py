"""
スレッド #9：流れが枝分かれする戦闘（覚醒編零式 4 層の車型／人型の形）・HP で区切るフェーズ
  記録ログは tests/route_logs.py で作る（実データが無いため）
"""
from collections import Counter

from core.analyze import analyze, AnalyzeOptions
from core.recorder import RecordLog
from route_logs import make_route_logs, BOSS_CID, PULLS

ROUTE_SPLITS = [dict(type='cast_start', contentid=BOSS_CID, action=[7001], at=55, anywhere=True, name='車型'),
                dict(type='cast_start', contentid=BOSS_CID, action=[7101], at=55, anywhere=True, name='人型'),
                dict(type='cast_start', contentid=BOSS_CID, action=[2001], at=80, anywhere=True, name='共通'),
                dict(type='cast_start', contentid=BOSS_CID, action=[3001], at=160, anywhere=True, name='フェーズ2')]


def _logs(tmp_path):
    return [RecordLog(p) for p in make_route_logs(str(tmp_path / 'logs' / '9999'))]


def test_route_without_splits_mixes_pulls(tmp_path):
    """区切りなしでは、ルートの違うプルを時刻で並べてしまう（偽の分岐がたくさん出る）"""
    an = analyze(_logs(tmp_path))
    kinds = Counter(s.kind for s in an.phases[0].slots)
    assert len(an.phases) == 1 and kinds['branch'] >= 8


def test_route_anywhere_splits(tmp_path):
    an = analyze(_logs(tmp_path), AnalyzeOptions(phase_splits=ROUTE_SPLITS))
    assert an.warnings == []
    ph = {p.name: p for p in an.phases}
    assert list(ph) == ['フェーズ1', '共通', '人型', '車型', 'フェーズ2']
    labels = [p.label for p in an.pulls]
    for (car_first, _), lbl in zip(PULLS, labels):
        # 形態ブロックは、プルによって⑥（55 秒）にも⑬にも来る
        first, second = (ph['車型'], ph['人型']) if car_first else (ph['人型'], ph['車型'])
        assert first.starts[lbl] == 55000 and second.starts[lbl] > ph['共通'].starts[lbl] > 55000
    # 形態ブロック・共通の中は全部そろう。人型ブロックのライト／レフトだけが分岐
    for name in ('フェーズ1', '共通', '車型', 'フェーズ2'):
        assert {s.kind for s in ph[name].slots} == {'stable'}, name
    assert Counter(s.kind for s in ph['人型'].slots) == Counter(stable=3, branch=1)
    br = next(s for s in ph['人型'].slots if s.kind == 'branch')
    assert br.t == 26.0 and set(br.all_actions) == {7104, 7105}
    # きっかけは 1 回目（何度も出ないので nth なし）
    assert ph['車型'].trigger == {'type': 'cast_start', 'entity': 'boss', 'action': 7001}


def test_route_time_window_split_warns(tmp_path):
    """秒数の範囲で探す区切り（今までどおり）は、⑬で来たプルを拾えない → 「どこで来ても」を勧める警告"""
    sp = [dict(x, anywhere=False) for x in ROUTE_SPLITS[:2]]
    an = analyze(_logs(tmp_path), AnalyzeOptions(phase_splits=sp))
    assert len(an.warnings) == 2 and all('「どこで来ても」' in w for w in an.warnings)


def test_route_anywhere_nth(tmp_path):
    """nth：2 回目の詠唱で区切る（共通の 2001 は 1 回しか無いので、2 回目はどのプルにも無い）"""
    sp = [dict(ROUTE_SPLITS[2], nth=2)]
    an = analyze(_logs(tmp_path), AnalyzeOptions(phase_splits=sp))
    assert len(an.phases) == 1 and any('どのプルにもありません' in w for w in an.warnings)


# ---------------------------------------------------------------------
# 火力でフェーズの長さが変わる戦闘（極エヌオーの雑魚フェーズの形）
from route_logs import make_dps_logs, DPS_BOSS, DPS_PULLS   # noqa: E402


def _dps(tmp_path):
    return [RecordLog(p) for p in make_dps_logs(str(tmp_path / 'logs' / '9998'))]


def test_dps_candidates(tmp_path):
    an = analyze(_dps(tmp_path))
    c = {x.kind: x for x in an.phase_candidates}
    # HP が止まった（雑魚フェーズの間ボスは無敵）：どのプルでも 60% → 「HP 60% で分ける」
    assert c['hp_stop'].hp_percent == 60.0 and set(c['hp_stop'].hp.values()) == {60.0}
    # ボスがターゲット可に戻った（雑魚を倒した）：火力で 112 / 93.7 / 73.3 秒、どれも 1 回目
    assert c['retargetable'].times == {'R1P1': 112.0, 'R2P1': 93.7, 'R3P1': 73.3} and c['retargetable'].nth == 1
    assert c['untargetable'].nth == 1


def test_dps_hp_and_retarget_splits(tmp_path):
    sp = [dict(type='hp_below', contentid=DPS_BOSS, percent=60.0, at=66.7, name='雑魚'),
          dict(type='targetable', contentid=DPS_BOSS, state=True, at=93.7, anywhere=True, nth=1, name='後半')]
    an = analyze(_dps(tmp_path), AnalyzeOptions(phase_splits=sp))
    ph = {p.name: p for p in an.phases}
    assert ph['雑魚'].trigger == {'type': 'hp_below', 'entity': 'boss', 'percent': 60.0}
    assert ph['後半'].trigger == {'type': 'targetable', 'entity': 'boss', 'state': True}
    assert {k: round(v / 1000, 1) for k, v in ph['雑魚'].starts.items()} == {'R1P1': 80.0, 'R2P1': 66.7, 'R3P1': 53.3}
    assert len(ph['後半'].starts) == 3
    # フェーズの中の時刻はそろう（雑魚フェーズの 25 秒の詠唱は、長いプルにだけある＝届かなかったプル）
    assert {s.kind for p in an.phases for s in p.slots} == {'stable'}


def test_dps_time_window_misses_fast_pull(tmp_path):
    """秒数の範囲で探すと（今までどおり）、火力の高いプルの「ターゲット可に戻った」を拾えない"""
    sp = [dict(type='targetable', contentid=DPS_BOSS, state=True, at=93.7)]
    an = analyze(_dps(tmp_path), AnalyzeOptions(phase_splits=sp))
    assert any('R3P1' in w for w in an.warnings)


def test_mixed_map_warning_names_files(tmp_path):
    """別のコンテンツが混ざったときの警告：記録ログを「リプレイ」と書かない。どのファイルがどの mapid か書く"""
    import shutil
    a = make_route_logs(str(tmp_path / 'logs' / '9999'))[:1]
    b = make_dps_logs(str(tmp_path / 'logs' / '9998'))[:1]
    an = analyze([RecordLog(p) for p in a + b])
    w = next(x for x in an.warnings if 'mapid' in x)
    assert 'リプレイ' not in w and '9998 = 記録ログ 20261116_110000.csv' in w and '9999 = 記録ログ 20261116_100000.csv' in w


