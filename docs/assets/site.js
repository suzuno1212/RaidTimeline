// RaidTimeline 説明書き：目次の現在地・コードのコピー・画像の拡大
(function () {
  // コードのコピー
  document.querySelectorAll('pre').forEach(function (pre) {
    var b = document.createElement('button');
    b.className = 'copy';
    b.textContent = 'コピー';
    b.onclick = function () {
      var t = pre.querySelector('code') ? pre.querySelector('code').innerText : pre.innerText;
      navigator.clipboard.writeText(t).then(function () {
        b.textContent = 'コピーしました';
        setTimeout(function () { b.textContent = 'コピー'; }, 1400);
      });
    };
    pre.appendChild(b);
  });
  // 画像の拡大
  var z = document.createElement('div');
  z.className = 'zoom';
  z.innerHTML = '<img alt="">';
  document.body.appendChild(z);
  z.onclick = function () { z.classList.remove('on'); };
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape') z.classList.remove('on'); });
  document.querySelectorAll('figure img').forEach(function (img) {
    img.onclick = function () { z.querySelector('img').src = img.src; z.classList.add('on'); };
  });
  // 目次の現在地（見出しが画面の上に来たら、その項目を光らせる）
  var links = Array.prototype.slice.call(document.querySelectorAll('.side a[href^="#"]'));
  if (!links.length) return;
  var heads = links.map(function (a) { return document.getElementById(a.getAttribute('href').slice(1)); });
  function update() {
    var y = window.scrollY + 100, cur = 0;
    heads.forEach(function (h, i) { if (h && h.offsetTop <= y) cur = i; });
    links.forEach(function (a, i) { a.classList.toggle('on', i === cur); });
  }
  window.addEventListener('scroll', update, { passive: true });
  update();
})();
