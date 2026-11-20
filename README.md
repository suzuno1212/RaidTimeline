# RaidTimeline

ボスの技が「いつ・何が来るか」をタイムラインで先読みして、軽減のアクションや合図の音を、決めておいた時刻に出す戦闘補助の Lua アドオンと、そのタイムラインを作る Windows 用の変換ツールです。

**説明書き：https://suzuno1212.github.io/RaidTimeline/**

## ダウンロード

[Releases](https://github.com/suzuno1212/RaidTimeline/releases/latest) から：

| ファイル | 中身 |
|---|---|
| `RaidTimeline-addon-<版>.zip` | アドオン（`LuaMods` に入れる）。サンプルのタイムライン 2 つ付き |
| `RaidTimelineTool-<版>-win64.zip` | 変換ツール（Windows 10 / 11。展開して exe を起動） |

入れ方・使い方は説明書きの [はじめかた](https://suzuno1212.github.io/RaidTimeline/start.html) へ。

## できること

- タイムライン表示：次に来る技を、着弾までの秒数と残り時間のバーで
- 軽減を自動で：決めた時刻にアビリティ（oGCD）を使う。まずはドライランで確かめられる
- 合図の音：決めた時刻に wav。ランダムの技は来た技ごとに別の音
- プラン編集：ゲームの中で、技ごとに使うアクション・タイミング・音を決める
- 記録モード：戦闘を 1 プル 1 ファイルで記録して、変換ツールの材料に
- 変換ツール：リプレイと記録ログを何プル分もまとめて読み、タイムラインを書き出す

## リポジトリの中身

```
addon/RaidTimeline/      アドオン（RaidTimeline.lua・module.def・timelines/）
converter/               変換ツール（Python。ui/ が画面、core/ が解析）
docs/                    説明書き（GitHub Pages。docs-src/ から作る）
docs-src/                説明書きの元（pages/*.html → python docs-src/build.py）
.github/workflows/       テストと、タグを付けたときの Releases
```

## 変換ツールを Python から動かす

```
cd converter
pip install -r requirements-dev.txt
python ui/app.py            # 画面
python -m pytest -q         # テスト
build_exe.bat               # exe を作る（dist/RaidTimelineTool/）
```

## ライセンス

[MIT](LICENSE) © 2026 suzu

使うかどうか・どう使うかは、ご自身の判断と責任でお願いします。
