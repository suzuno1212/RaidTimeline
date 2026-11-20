# -*- mode: python ; coding: utf-8 -*-
# RaidTimelineTool.spec - PyInstaller の設定（変換ツールの画面を exe にする）
#   build_exe.bat から使う： python -m PyInstaller --noconfirm RaidTimelineTool.spec
#   できるもの：dist\RaidTimelineTool\RaidTimelineTool.exe（フォルダごと配る。1 ファイルにしないのは起動を速くするため）
#   設定（RaidTimelineTool_settings.json）と opcodes.json は exe の隣に書く
#   画面は Edge WebView2 で描く（Windows 10/11 には入っている）

a = Analysis(
    ['ui/app.py'],
    pathex=['.'],
    datas=[
        ('ui/index.html', 'ui'),
        ('ui/app.js', 'ui'),
        ('ui/static', 'ui/static'),
        ('opcodes.json', '.'),
    ],
    hiddenimports=['ui.session', 'ui.version', 'core.replay', 'core.analyze', 'core.recorder', 'core.luatable', 'core.names',
                   'core.combined', 'core.plan_migrate', 'export.timeline_lua', 'export.csv'],
    excludes=['pytest', 'lupa', 'tkinter'],
    noarchive=False,
)
pyz = PYZ(a.pure)
exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='RaidTimelineTool',
    console=False,
    upx=False,
)
coll = COLLECT(exe, a.binaries, a.datas, name='RaidTimelineTool', upx=False)
