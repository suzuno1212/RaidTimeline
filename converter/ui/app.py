"""
ui/app.py — 変換ツールの画面（pywebview ＋ daisyUI）

起動:  python ui\\app.py        （--debug で開発者ツール）

画面（index.html・app.js）から window.pywebview.api.<名前>() で呼ばれる。中身は ui/session.py の Session。
  リプレイ（.dat）・記録モードのログ（CSV）・既存のタイムライン（timelines\\*.lua）を開き、
  それぞれ別のタブ（「リプレイ結果」「記録ログ結果」「タイムライン」）で直して、タイムラインを書き出す。
  リプレイと記録ログを組にして開くこともできる（「リプレイ＋記録ログ結果」。core/combined.py）。

daisyUI（CSS）と Tailwind（ブラウザ版）は ui/static に同梱しているので、オフラインで動く。
pywebview の注意：js_api に渡すオブジェクトの公開属性は pywebview がすべてたどるので、
ウィンドウ・Session は _window・_s のように _ 付きで持つ。
"""
from __future__ import annotations

import os
import sys
import threading
import traceback

if getattr(sys, 'frozen', False):          # PyInstaller の exe：同梱したファイルは sys._MEIPASS の下
    ROOT = sys._MEIPASS
    HERE = os.path.join(ROOT, 'ui')
else:
    HERE = os.path.dirname(os.path.abspath(__file__))
    ROOT = os.path.dirname(HERE)
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

import webview                                             # noqa: E402

from ui.session import Session, SessionError               # noqa: E402
from ui.version import VERSION                             # noqa: E402


def _settings_path() -> str:
    """設定ファイル：exe のときは exe の隣、それ以外は ui\\settings.json"""
    if getattr(sys, 'frozen', False):
        return os.path.join(os.path.dirname(sys.executable), 'RaidTimelineTool_settings.json')
    return os.path.join(HERE, 'settings.json')


class Api:
    """JavaScript から呼ばれる関数。戻り値は {ok: true, ...} か {ok: false, error: 文}"""

    def __init__(self):
        self._window = None
        self._s = Session(_settings_path())
        self._lock = threading.Lock()

    def _call(self, fn, *a, **kw):
        with self._lock:
            try:
                return dict(ok=True, data=fn(*a, **kw))
            except SessionError as e:
                return dict(ok=False, error=str(e))
            except Exception as e:      # 想定外：画面に出して、詳しくはコンソールに
                traceback.print_exc()
                return dict(ok=False, error='%s: %s' % (type(e).__name__, e))

    # ------------------------------------------------------------ 設定
    def info(self):
        return self._call(self._s.info)

    def set_settings(self, values: dict):
        return self._call(lambda: self._s.set_settings(**(values or {})))

    # ------------------------------------------------------------ ダイアログ
    def _dialog(self, kind_name, directory, multiple=False, types=()):
        fd = getattr(webview, 'FileDialog', None)
        kind = getattr(fd, kind_name, None) if fd else None
        if kind is None:
            kind = {'OPEN': webview.OPEN_DIALOG, 'FOLDER': webview.FOLDER_DIALOG}[kind_name]
        kw = dict(directory=directory or '', allow_multiple=multiple)
        if types:
            kw['file_types'] = types
        res = self._window.create_file_dialog(kind, **kw)
        return list(res or [])

    def pick_replays(self):
        return self._call(lambda: self._dialog('OPEN', self._s.settings['replay_dir'], True,
                                               ('リプレイ (*.dat)', 'すべてのファイル (*.*)')))

    def pick_logs(self, mapid=None):
        d = self._s.logs_dir
        if mapid and os.path.isdir(os.path.join(d, str(mapid))):
            d = os.path.join(d, str(mapid))
        return self._call(lambda: self._dialog('OPEN', d, True, ('記録ログ (*.csv)', 'すべてのファイル (*.*)')))

    def pick_timeline(self):
        return self._call(lambda: self._dialog('OPEN', self._s.timelines_dir, False,
                                               ('タイムライン (*.lua)', 'すべてのファイル (*.*)')))

    def pick_folder(self, start=''):
        return self._call(lambda: (self._dialog('FOLDER', start or self._s.settings['luamods']) or [''])[0])

    def open_path(self, path: str):
        def go():
            if path and os.path.exists(path) and hasattr(os, 'startfile'):
                os.startfile(path)
            return True
        return self._call(go)

    # ------------------------------------------------------------ タブ
    def open_replays(self, paths: list):
        r = self._call(self._s.open_replays, paths)
        if r['ok'] and paths:
            self._s.settings['replay_dir'] = os.path.dirname(paths[0])
            self._s.save_settings()
        return r

    def open_logs(self, paths: list):
        return self._call(self._s.open_logs, paths)

    def replay_mapid(self, replays: list):
        return self._call(self._s.replay_mapid, replays)

    def open_combined(self, replays: list, logs: list):
        r = self._call(self._s.open_combined, replays, logs)
        if r['ok'] and replays:
            self._s.settings['replay_dir'] = os.path.dirname(replays[0])
            self._s.save_settings()
        return r

    def open_timeline(self, path: str):
        if path and not os.path.isabs(path):
            path = os.path.join(self._s.timelines_dir, path)
        return self._call(self._s.open_timeline, path)

    def reanalyze(self, tid: str, options: dict):
        return self._call(self._s.reanalyze, tid, options or {})

    def close_tab(self, tid: str):
        return self._call(self._s.close, tid)

    def preview(self, tid: str, edits: dict, fname: str = '', dest: str = ''):
        return self._call(self._s.preview, tid, edits or {}, fname or None, dest or None)

    def export(self, tid: str, edits: dict, fname: str = '', dest: str = '', write_names: bool = False,
               overwrite: bool = False, migrate: dict | None = None):
        return self._call(self._s.export, tid, edits or {}, fname or None, dest or None, bool(write_names),
                          bool(overwrite), migrate or None)

    def map_timelines(self, tid: str, dest: str = ''):
        return self._call(self._s.map_timelines, tid, dest or None)

    def plan_preview(self, tid: str, edits: dict, fname: str = '', dest: str = '', src: str = ''):
        return self._call(self._s.plan_preview, tid, edits or {}, fname or None, dest or None, src or None)


def main():
    api = Api()
    api._window = webview.create_window(
        'RaidTimeline 変換ツール v' + VERSION, url=os.path.join(HERE, 'index.html'), js_api=api,
        width=1400, height=900, min_size=(1000, 640), background_color='#1d232a')
    webview.start(debug='--debug' in sys.argv)


if __name__ == '__main__':
    main()
