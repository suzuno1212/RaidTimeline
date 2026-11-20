"""export/ と cli.py のテスト（Lua は LuaJIT で実際に読み込んで確かめる）"""
import csv
import io
import os
import re

import pytest

from conftest import ALL_REPLAYS, LH4, load, need, lua_runtime
from core.analyze import analyze, AnalyzeOptions
from export.timeline_lua import render_timeline, write_timeline, build_timeline, safe_name, lua_str
from export.csv import (write_compare_csv, write_log_csvs, log_rows, LOG_COLUMNS,
                        pull_result)

LOG_KINDS = {'cast_start', 'cast_end', 'appear', 'disappear', 'targetable', 'hp', 'buff_gain',
             'buff_lose', 'marker', 'tether', 'map_effect', 'wipe', 'clear'}
TRIGGER_TYPES = {'combat_start', 'cast_start', 'cast_end', 'hp_below', 'entity_appear', 'entity_disappear',
                 'targetable', 'buff_gain', 'map_effect', 'all', 'any'}


def test_lua_string_escape():
    lua = lua_runtime()
    s = 'a"b\\c\nd「日本語」'
    assert lua.eval(lua_str(s)) == s


def test_safe_name():
    assert safe_name('m4s') == 'm4s'
    assert safe_name('４層 test!') == 'test'
    assert safe_name('') == 'draft'


