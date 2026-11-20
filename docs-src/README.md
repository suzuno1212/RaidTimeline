# 説明書きの元

`pages/*.html` が本文。`python build.py` で `../docs/` に、上のバー・目次・前後のリンクを付けた HTML を書きます。
画像は `../docs/img/`（webp）、見た目は `../docs/assets/style.css`。
ページを足すときは `build.py` の `NAV` にも足してください。どのページにも検索よけ（robots noindex）が付きます。
