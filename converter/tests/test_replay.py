"""core/replay.py のテスト"""
import os

import pytest

from conftest import ALL_REPLAYS, load
from core.replay import (Replay, OpcodeStore, KNOWN_OPCODES, OPCODE_KINDS, ENEMY_ID_MIN,
                         ReplayFormatError)


def test_not_a_replay(tmp_path):
    p = tmp_path / 'x.dat'
    p.write_bytes(b'NOTAREPLAY' + b'\0' * 2000)
    with pytest.raises(ReplayFormatError):
        Replay(str(p))


