"""テストの共通設定（公開版：データ（リプレイ・記録ログ）を使わないテストだけ）"""
import os
import sys

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

REPLAY_DIR = None
ALL_REPLAYS = []
LH4 = SUSANO = None


def find_replay_dir():
    return None


def find(pattern):
    return None


def load(path):
    from core.replay import Replay
    return Replay(path)


def need(path, what):
    if not path:
        pytest.skip('%s のデータがありません' % what)
    return path


def lua_runtime():
    """LuaJIT（Lua 5.1 系）。無ければ Lua 5.1"""
    lupa = pytest.importorskip('lupa')
    try:
        from lupa import luajit21 as mod
    except ImportError:
        try:
            from lupa import lua51 as mod
        except ImportError:
            mod = lupa
    return mod.LuaRuntime(unpack_returned_tuples=True)
