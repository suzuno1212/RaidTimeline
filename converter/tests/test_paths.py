"""
スレッド #9：フォルダの探し方（どの PC でも同じに動くように）
  - リプレイ：ドキュメント（Windows に聞く）の My Games\\FINAL FANTASY XIV - A Realm Reborn\\replay（autorenamed があればそちら）
  - アドオン：C〜Z ドライブの MINIONAPP\\Bots\\FFXIVMinion64\\LuaMods\\RaidTimeline
  - 保存した設定の場所があればそれを使う。無い（別の PC に持ってきた）ときだけ探す
"""
import json
import os

import ui.session as S


def test_replay_dir_prefers_autorenamed(tmp_path, monkeypatch):
    a = tmp_path / 'docA'
    b = tmp_path / 'docB'
    (b / S._REPLAY_SUB / 'autorenamed').mkdir(parents=True)
    (a / S._REPLAY_SUB).mkdir(parents=True)
    monkeypatch.setattr(S, 'documents_dirs', lambda: [str(a), str(b)])
    # 先の候補（docA）に replay があれば、そちら（autorenamed が無いので replay）
    assert S.default_replay_dir() == os.path.join(str(a), S._REPLAY_SUB)
    (a / S._REPLAY_SUB / 'autorenamed').mkdir()
    assert S.default_replay_dir() == os.path.join(str(a), S._REPLAY_SUB, 'autorenamed')
    monkeypatch.setattr(S, 'documents_dirs', lambda: [str(tmp_path / 'none')])
    assert S.default_replay_dir() == os.path.expanduser('~')


def test_find_luamods_drives(monkeypatch):
    have = set()
    monkeypatch.setattr(S.sys, 'platform', 'win32')
    monkeypatch.setattr(S.os.path, 'isdir', lambda p: p in have)
    sub = S._MINION_SUB
    assert S.find_luamods() is None
    # D ドライブに LuaMods だけ（RaidTimeline はまだ置いていない）→ そこに置く前提で返す
    have.add(os.path.dirname('D:\\' + sub))
    assert S.find_luamods() == 'D:\\' + sub
    # E ドライブに RaidTimeline まである → そちら
    have.add('E:\\' + sub)
    assert S.find_luamods() == 'E:\\' + sub


def test_session_keeps_saved_folders_and_searches_when_missing(tmp_path, monkeypatch):
    lm = tmp_path / 'LuaMods' / 'RaidTimeline'
    lm.mkdir(parents=True)
    rp = tmp_path / 'replay'
    rp.mkdir()
    st = tmp_path / 'settings.json'
    st.write_text(json.dumps(dict(luamods=str(lm), replay_dir=str(rp), author='suzu')), encoding='utf-8')
    monkeypatch.setattr(S, 'find_luamods', lambda: 'FOUND')
    monkeypatch.setattr(S, 'default_replay_dir', lambda: 'FOUND_REPLAY')
    s = S.Session(settings_file=str(st))
    assert s.settings['luamods'] == str(lm) and s.settings['replay_dir'] == str(rp)   # 今までどおり
    # 別の PC に設定ごと持ってきた（保存した場所が無い）→ 探す
    st.write_text(json.dumps(dict(luamods=str(tmp_path / 'no'), replay_dir=str(tmp_path / 'no2'))), encoding='utf-8')
    s = S.Session(settings_file=str(st))
    assert s.settings['luamods'] == 'FOUND' and s.settings['replay_dir'] == 'FOUND_REPLAY'
    # 設定が無い・探しても無い → 既定の場所（画面が「見つかりません」と出して設定を開く）
    monkeypatch.setattr(S, 'find_luamods', lambda: None)
    monkeypatch.setattr(S, 'DEFAULT_LUAMODS', str(tmp_path / 'default_none'))   # この PC に既定の場所があっても影響されないように
    s = S.Session(settings_file=None)
    assert s.settings['luamods'] == S.DEFAULT_LUAMODS and s.info()['luamods_ok'] is False
