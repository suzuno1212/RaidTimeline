"""
cli.py — リプレイ → タイムライン Lua ＋ CSV（画面ができるまでの確認用）

使い方（例）:
  python cli.py "C:\\...\\replay\\autorenamed\\*ライトヘビー級4*.dat" -o out --name m4s
  python cli.py a.dat b.dat -o out --name m4s --pulls P2,P4
  python cli.py a.dat --info                     … 概要だけ表示（ファイルは書かない）

出力:
  <out>/timelines/<mapid>_<name>.lua     … タイムライン下書き（仕様 format = 1）
  <out>/<mapid>_<name>_compare.csv       … 比較表（Excel 用 UTF-8 BOM 付き）
  <out>/logs/<mapid>/<日時>_P<n>.csv     … ログ CSV（仕様 5 章、1 プル 1 ファイル）
  <out>/<mapid>_<name>_analysis.json     … --json を付けたとき（画面の開発用）
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

from core.replay import Replay, OpcodeStore, ReplayFormatError          # noqa: E402
from core.analyze import analyze, AnalyzeOptions                         # noqa: E402
from export.timeline_lua import write_timeline, safe_name                # noqa: E402
from export.csv import write_compare_csv, write_log_csvs, pull_result    # noqa: E402

DEFAULT_OPCODE_FILE = os.path.join(HERE, 'opcodes.json')


def expand(paths):
    out = []
    for p in paths:
        hits = sorted(glob.glob(p)) if any(c in p for c in '*?[') else [p]
        if os.path.isdir(p):
            hits = sorted(glob.glob(os.path.join(p, '*.dat')))
        out += hits
    return out


def main(argv=None):
    try:
        sys.stdout.reconfigure(errors='replace')
    except Exception:
        pass
    ap = argparse.ArgumentParser(description='FFXIV リプレイ（.dat）からタイムライン下書きを作る')
    ap.add_argument('replays', nargs='+', help='リプレイファイル（ワイルドカード・フォルダ可）')
    ap.add_argument('-o', '--out', default='out', help='出力フォルダ（既定 out）')
    ap.add_argument('--name', default='draft', help='ファイル名の短縮名（英数字・_・-）')
    ap.add_argument('--title', default=None, help='タイムラインの表示名（日本語可）')
    ap.add_argument('--author', default='', help='作成者')
    ap.add_argument('--version', type=int, default=1, help='タイムラインの改訂番号')
    ap.add_argument('--pulls', default=None, help='使うプル（例 P2,P4）')
    ap.add_argument('--encounter', type=int, default=None, help='解析する戦闘（最初に戦う敵の contentid）')
    ap.add_argument('--min-hits', type=int, default=10, help='本物の敵とみなす被弾数')
    ap.add_argument('--no-split', action='store_true', help='フェーズを分けない')
    ap.add_argument('--real-only', action='store_true', help='本物の敵の詠唱だけをイベントにする')
    ap.add_argument('--no-logs', action='store_true', help='ログ CSV を書かない')
    ap.add_argument('--json', action='store_true', help='解析結果の JSON も書く')
    ap.add_argument('--opcode-file', default=DEFAULT_OPCODE_FILE,
                    help='ビルドごとの opcode を保存するファイル（既定: cli.py と同じフォルダの opcodes.json）')
    ap.add_argument('--info', action='store_true', help='概要だけ表示する')
    a = ap.parse_args(argv)

    files = expand(a.replays)
    if not files:
        print('リプレイが見つかりません: %s' % a.replays)
        return 2

    store = OpcodeStore(a.opcode_file)
    replays = []
    for f in files:
        try:
            replays.append(Replay(f, store=store))
        except (OSError, ReplayFormatError) as e:
            print('読み込めません: %s (%s)' % (f, e))
            return 2
    store.save()

    for r in replays:
        print('■ %s' % r.file_name)
        print('  build %s  mapid %s  cfc %d  記録 %s  %.0f 秒' % (
            r.build_hex, r.mapid, r.cfc, r.recorded_at.strftime('%Y-%m-%d %H:%M'), r.total_ms / 1000))
        print('  opcode ' + '  '.join('%s=%s(%s)' % (k, ('0x%04x' % v.opcode) if v.opcode is not None else '-',
                                                     v.source) for k, v in r.opcode_info.items()))
        for p in r.pulls:
            kind, pct = pull_result(r, p.index, a.min_hits)
            print('  P%-2d %6.1f 秒  交戦 +%s 秒  %s%s' % (
                p.index + 1, p.duration, '-' if p.engage_offset is None else '%.1f' % p.engage_offset, kind,
                '' if pct is None else ' (最後の敵 %.1f%%)' % pct))

    opt = AnalyzeOptions(min_hits=a.min_hits, encounter=a.encounter, split_phases=not a.no_split,
                         pulls=[x.strip() for x in a.pulls.split(',')] if a.pulls else None)
    an = analyze(replays, opt)

    print('\n■ 解析（mapid %s, プル %s）' % (an.mapid, ', '.join(an.pull_labels())))
    print('  本物の敵:')
    for k in an.real_kinds():
        print('    %-8s contentid %-6d bNpcBase %-6d 最大HP %-11d 被弾 %d' % (k.key, k.contentid, k.base, k.max_hp, k.hits))
    excl = [k for k in an.kinds if not k.real and k.casts]
    if excl:
        print('  詠唱だけする敵（除外）: ' + ', '.join('%d/%d' % (k.contentid, k.base) for k in excl))
    print('  フェーズ移行の候補:')
    for c in an.phase_candidates:
        print('    %-17s %-6s %d/%d %s %s%s' % (c.kind, c.entity, c.contentid, c.base,
                                           ('action ' + '/'.join(map(str, c.actions))) if c.actions else '',
                                           ' '.join('%s=%.1f' % kv for kv in c.times.items()),
                                           '  → %s' % c.phase if c.adopted else ''))
    for ph in an.phases:
        print('  [%s] %s  イベント %d' % (ph.id, ph.trigger, len(ph.slots)))
        for s in ph.slots:
            if s.kind in ('branch', 'swap'):
                print('    %-6s %6.1f %-24s %s' % (s.kind, s.t, s.event_name,
                                                   ' '.join('%s=%s' % (p, '+'.join(map(str, x))) for p, x in s.sets().items())))
        for s in ph.slots:
            if s.sync:
                print('    sync   %6.1f %-24s nth=%s (%s)' % (s.t, s.event_name, s.nth, s.sync))
    for w in an.warnings:
        print('  ! ' + w)

    if a.info:
        return 0

    name = safe_name(a.name)
    out = a.out
    lua = write_timeline(an, os.path.join(out, 'timelines'), name=name, title=a.title, author=a.author,
                         version=a.version, real_casters_only=a.real_only)
    cmp_path = write_compare_csv(an, os.path.join(out, '%s_%s_compare.csv' % (an.mapid or 0, name)))
    print('\n書き出し:\n  %s\n  %s' % (lua, cmp_path))
    if not a.no_logs:
        logs = write_log_csvs(replays, out, analysis=an, min_hits=a.min_hits)
        print('  ログ CSV %d 件 → %s' % (len(logs), os.path.dirname(logs[0]) if logs else '-'))
    if a.json:
        jp = os.path.join(out, '%s_%s_analysis.json' % (an.mapid or 0, name))
        with open(jp, 'w', encoding='utf-8') as f:
            json.dump(an.to_dict(), f, ensure_ascii=False, indent=1)
        print('  ' + jp)
    return 0


if __name__ == '__main__':
    sys.exit(main())
