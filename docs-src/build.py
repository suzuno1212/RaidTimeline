"""説明書き（docs/）を組み立てる：pages/*.html（本文）に、上のバー・目次・足もとを付ける"""
import os, re, html, sys
SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'pages')
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'docs')
NAV = [('index.html', 'ホーム'), ('start.html', 'はじめかた'), ('addon.html', 'アドオン'),
       ('converter.html', '変換ツール'), ('timeline.html', 'タイムラインとプラン'), ('faq.html', '困ったとき')]
LOGO = '<svg viewBox="0 0 24 24" fill="none" stroke="#0d0f26" stroke-width="2.4" stroke-linecap="round"><path d="M4 6h10M4 12h16M4 18h7"/><circle cx="18" cy="6" r="1.6" fill="#0d0f26"/><circle cx="15" cy="18" r="1.6" fill="#0d0f26"/></svg>'
HEAD = '''<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow, noarchive, noimageindex">
<meta name="googlebot" content="noindex, nofollow">
<meta name="referrer" content="no-referrer">
<title>{title}RaidTimeline</title>
<link rel="stylesheet" href="assets/style.css">
<link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'%3E%3Crect width='24' height='24' rx='6' fill='%237482ff'/%3E%3Cpath d='M5 7h9M5 12h14M5 17h6' stroke='%230d0f26' stroke-width='2.4' stroke-linecap='round'/%3E%3C/svg%3E">
</head>
<body>
<header class="topbar">
  <a class="brand" href="index.html"><span class="logo">{logo}</span>RaidTimeline</a>
  <nav class="topnav">{nav}</nav>
  <span class="spacer"></span>
  <a class="btn primary" href="https://github.com/suzuno1212/RaidTimeline/releases/latest">ダウンロード</a>
</header>
'''
FOOT = '''<footer>RaidTimeline ・ MIT License ・ 作者 suzu ・ <a href="https://github.com/suzuno1212/RaidTimeline">GitHub</a></footer>
<script src="assets/site.js"></script>
</body>
</html>
'''


def page(fn, body):
    m = re.search(r'<!--\s*title:(.*?)-->', body)
    title = (m.group(1).strip() + ' ｜ ') if m and fn != 'index.html' else ''
    nav = ''.join('<a href="%s"%s>%s</a>' % (f, ' class="on"' if f == fn else '', n) for f, n in NAV[1:])
    out = HEAD.format(title=html.escape(title), nav=nav, logo=LOGO)
    if fn == 'index.html':
        out += body
    else:
        # 目次：本文の h2（id 付き）から作る
        toc = ''.join('<a href="#%s">%s</a>' % (i, re.sub('<[^>]+>', '', t)) for i, t in re.findall(r'<h2 id="([^"]+)">(.*?)</h2>', body))
        side = '<h4>このページ</h4>' + toc + '<h4>ほかのページ</h4>' + ''.join(
            '<a href="%s">%s</a>' % (f, n) for f, n in NAV if f != fn)
        i = [f for f, _ in NAV].index(fn)
        prev = NAV[i - 1] if i > 0 else None
        nxt = NAV[i + 1] if i + 1 < len(NAV) else None
        pager = '<div class="pager">%s%s</div>' % (
            '<a href="%s"><small>前へ</small>%s</a>' % prev if prev else '<span></span>',
            '<a class="next" href="%s"><small>次へ</small>%s</a>' % nxt if nxt else '<span></span>')
        out += '<div class="layout"><aside class="side">%s</aside><main>%s%s</main></div>\n' % (side, body, pager)
    out += FOOT
    with open(os.path.join(OUT, fn), 'w', encoding='utf-8', newline='\n') as f:
        f.write(out)


for fn, _ in NAV:
    p = os.path.join(SRC, fn)
    if os.path.exists(p):
        page(fn, open(p, encoding='utf-8').read())
        print('built', fn)
