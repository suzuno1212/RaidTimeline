// ui/app.js — 変換ツールの画面の動き。Python 側は window.pywebview.api（ui/app.py の Api → ui/session.py）
//
// タブ 1 つ = 開いたもの 1 つ（リプレイ結果・記録ログ結果・タイムライン）。
// 画面での直しは tab.edits に持ち、解析し直しても同じイベント ID の直しはそのまま使う。
// 書き出し・プレビューは edits を Python に渡し、Python が当てて Lua にする（ui/session.py の apply_edits）。

const S = {
  info: null,
  tabs: [],          // { id, view, edits, fname, dest }
  cur: null,
  busy: 0,
};

const $ = (id) => document.getElementById(id);
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) =>
  ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const KIND_LABEL = { replay: 'リプレイ結果', record: '記録ログ結果', combined: 'リプレイ＋記録ログ結果', file: 'タイムライン' };
const KIND_BADGE = { replay: 'badge-primary', record: 'badge-secondary', combined: 'badge-info', file: 'badge-accent' };
const SLOT_KIND = {
  stable: ['安定', 'badge-success'], partial: ['一部', 'badge-warning'], branch: ['分岐', 'badge-info'],
  swap: ['入れ替わり', 'badge-error'], file: ['', ''],
};

// ------------------------------------------------------------ Python を呼ぶ
async function call(name, ...args) {
  S.busy++; $('busy').classList.remove('hidden');
  try {
    const r = await window.pywebview.api[name](...args);
    if (!r || !r.ok) { toast((r && r.error) || 'エラー', 'error'); return null; }
    return r.data;
  } catch (e) {
    toast(String(e), 'error'); return null;
  } finally {
    if (--S.busy <= 0) { S.busy = 0; $('busy').classList.add('hidden'); }
  }
}

function toast(msg, tone = 'info', ms = 6000) {
  const d = document.createElement('div');
  d.className = 'alert alert-' + tone + ' text-sm max-w-xl';
  d.textContent = msg;
  $('toasts').appendChild(d);
  setTimeout(() => d.remove(), ms);
}

// ------------------------------------------------------------ 起動
window.addEventListener('pywebviewready', async () => {
  bind();
  await refreshInfo();
  render();
  // 初めて使う PC でアドオンのフォルダが見つからなければ、設定を開いて選んでもらう（スレッド #9）
  if (S.info && !S.info.luamods_ok) openSettings();
});

async function refreshInfo() {
  const info = await call('info');
  if (!info) return;
  S.info = info;
  if ($('toolVer') && info.version) $('toolVer').textContent = 'v' + info.version;
  const n = info.names;
  $('emptyInfo').textContent = 'アドオンのフォルダ: ' + info.settings.luamods + (info.luamods_ok ? '' : '（見つかりません。設定で直してください）')
    + ' ／ 名前辞書: 技 ' + n.actions + '・敵 ' + n.npcs;
  const m = $('tlMenu');
  m.innerHTML = info.timelines.map((f) => `<li><a data-f="${esc(f)}" class="mono">${esc(f)}</a></li>`).join('')
    + '<li class="menu-title">ほか</li><li><a data-f="">ファイルを選ぶ…</a></li>';
  m.querySelectorAll('a').forEach((a) => a.onclick = () => { document.activeElement.blur(); openTimeline(a.dataset.f); });
}

function bind() {
  $('btnReplay').onclick = async () => {
    const paths = await call('pick_replays');
    if (paths && paths.length) addTab(await call('open_replays', paths));
  };
  $('btnLogs').onclick = async () => {
    const t = curTab();
    const paths = await call('pick_logs', t ? t.view.mapid : null);
    if (paths && paths.length) addTab(await call('open_logs', paths));
  };
  $('btnBoth').onclick = async () => {
    const reps = await call('pick_replays');
    if (!reps || !reps.length) return;
    // 記録ログを選ぶ画面は、リプレイのコンテンツのフォルダ（logs\<mapid>）から開く（スレッド #9）
    const mapid = await call('replay_mapid', reps);
    toast(`続けて、同じ戦闘の記録ログ（logs\\${mapid || '<mapid>'}\\<日時>.csv）を選んでください`, 'info', 4000);
    const logs = await call('pick_logs', mapid || null);
    if (!logs || !logs.length) return;
    addTab(await call('open_combined', reps, logs));
  };
  $('btnSettings').onclick = openSettings;
  $('btnSaveSettings').onclick = saveSettings;
  $('btnLuamods').onclick = async () => { const d = await call('pick_folder', $('sLuamods').value); if (d) $('sLuamods').value = d; };
  $('btnDest').onclick = async () => { const d = await call('pick_folder', $('fDest').value); if (d) { $('fDest').value = d; curTab().dest = d; } };
  $('btnPreview').onclick = preview;
  $('btnExport').onclick = () => doExport(false);
  for (const id of ['mName', 'mAuthor', 'mVersion']) {
    $(id).onchange = () => { const t = curTab(); if (!t) return; const k = { mName: 'name', mAuthor: 'author', mVersion: 'version' }[id]; t.edits.meta[k] = $(id).value; };
  }
  $('fName').onchange = () => { const t = curTab(); if (t) { t.fname = $('fName').value; fillSrc(t); } };
  $('fDest').onchange = () => { const t = curTab(); if (t) { t.dest = $('fDest').value; fillSrc(t); } };
  // プランを移す（スレッド #9）
  $('fMigrate').onchange = () => { const t = curTab(); if (!t) return; mig(t).on = $('fMigrate').checked; showMigrate(t); };
  $('fSrc').onchange = () => { const t = curTab(); if (t) mig(t).src = $('fSrc').value; };
  $('fMoveOld').onchange = () => { const t = curTab(); if (t) mig(t).moveOld = $('fMoveOld').checked; };
}

// ---- プランを移す（スレッド #9）
function mig(t) { return (t.mig ||= { on: false, src: '', moveOld: true }); }

function targetStem(t) {
  const f = ($('fName').value || 'draft').trim().replace(/\.lua$/i, '');
  return /^\d+_/.test(f) ? f : `${t.view.mapid || 0}_${f}`;
}

function showMigrate(t) {
  $('fMigrate').checked = mig(t).on;
  $('migrateOpts').classList.toggle('hidden', !mig(t).on);
  if (mig(t).on) fillSrc(t);
}

async function fillSrc(t) {
  if (!mig(t).on) return;
  const list = (await call('map_timelines', t.id, $('fDest').value.trim())) || [];
  const tgt = targetStem(t);
  if (!list.includes(mig(t).src)) mig(t).src = list.includes(tgt) ? tgt : (list[0] || '');
  $('fSrc').innerHTML = list.length
    ? list.map((x) => `<option value="${esc(x)}" ${x === mig(t).src ? 'selected' : ''}>${esc(x)}.lua${x === tgt ? '（上書きする）' : ''}</option>`).join('')
    : '<option value="">（このマップのタイムラインはまだありません）</option>';
}

async function migrateFlow(t) {
  const m = mig(t);
  const pv = await call('plan_preview', t.id, t.edits, t.fname, t.dest, m.src || '');
  if (!pv) return;
  const use = pv.plans.filter((p) => p.use);
  const rename = pv.src !== pv.target;
  if (!pv.src_exists || !use.length) {
    if (!confirm(`${pv.message || '移すプランがありません（' + pv.src + '.lua を使うプランが plans に無い）'}。\nタイムラインだけ書き出しますか？`)) return;
    return doExport(false, null);
  }
  const kind = { same: ['そのまま', 'badge-ghost'], moved: ['付け替え', 'badge-info'], missing: ['見つからない', 'badge-warning'] };
  let h = `<div class="mb-2">書き出し：<span class="mono">${esc(pv.target)}.lua</span>${pv.target_exists ? '（<b>上書き</b>。前の版は timelines\\backup）' : '（新しいファイル）'}<br>
    プランが今使っているタイムライン：<span class="mono">${esc(pv.src)}.lua</span>${rename ? (m.moveOld ? '（書き出した後、timelines\\backup に移す）' : '（そのまま残す。アドオンは名前の順で先に来るものを使います）') : ''}</div>`;
  h += `<div class="flex gap-2 mb-2"><span class="badge badge-ghost">そのまま ${pv.counts.same}</span><span class="badge badge-info">付け替え ${pv.counts.moved}</span><span class="badge badge-warning">見つからない ${pv.counts.missing}</span></div>`;
  for (const p of pv.plans) {
    h += `<div class="font-bold mt-2 mono">${esc(p.file)}</div>`;
    if (!p.use) { h += `<div class="text-xs opacity-70">移しません：${esc(p.reason)}</div>`; continue; }
    if (p.partial) h += '<div class="text-xs opacity-70">どのタイムラインのプランか書いていないので、元のタイムラインのイベントのエントリだけ移します（ほかのエントリと meta はそのまま）</div>';
    const rows = p.entries.filter((r) => r.kind !== 'other');
    h += '<table class="table table-xs"><thead><tr><th>エントリ</th><th>イベント</th><th></th><th>新しいイベント</th><th>説明</th></tr></thead><tbody>';
    h += rows.map((r) => `<tr><td class="mono">${esc(r.id)}</td><td class="mono">${esc(r.event)}</td>
      <td><span class="badge badge-sm ${kind[r.kind][1]} whitespace-nowrap">${kind[r.kind][0]}</span></td>
      <td class="mono">${esc(r.new || '')}</td><td class="text-xs">${esc(r.note || '')}</td></tr>`).join('');
    h += '</tbody></table>';
    for (const k of p.keys || []) h += `<div class="text-xs">${esc(k.id)}：${esc(k.where)} ${esc(k.old)} → ${esc(k.new)}（敵のキーが変わった）</div>`;
  }
  if (pv.counts.missing) h += '<div class="alert alert-warning text-xs mt-2">「見つからない」エントリは消さずに残します（アドオンでは使われません）。プラン編集で付け直してください。</div>';
  $('mgTitle').textContent = 'プランを移す：' + pv.target + '.lua';
  $('mgBody').innerHTML = h;
  const dlg = $('dlgMigrate');
  dlg.returnValue = '';
  dlg.showModal();
  dlg.onclose = () => { if (dlg.returnValue === 'ok') doExport(true, { src: pv.src, move_old: rename && m.moveOld }); };
}

async function openTimeline(f) {
  let path = f;
  if (!f) {
    const p = await call('pick_timeline');
    if (!p || !p.length) return;
    path = p[0];
  }
  addTab(await call('open_timeline', path));
}

function newEdits() { return { meta: {}, actions: {}, entities: {}, events: {}, syncs: {}, phases: {} }; }

function addTab(view) {
  if (!view) return;
  const t = { id: view.id, view, edits: newEdits(), fname: '', dest: view.dest || '' };
  if (view.kind === 'file') {
    t.fname = view.fname.replace(/^\d+_/, '').replace(/\.lua$/, '');
  } else {
    t.fname = 'draft';
  }
  S.tabs.push(t);
  S.cur = t.id;
  render();
  const n = (view.warnings || []).length;
  toast(KIND_LABEL[view.kind] + 'を開きました：' + view.title + (n ? '（注意 ' + n + ' 件）' : ''), 'success', 3500);
}

const curTab = () => S.tabs.find((t) => t.id === S.cur);

// ------------------------------------------------------------ 描画
function render() {
  renderTabs();
  const t = curTab();
  $('empty').classList.toggle('hidden', !!t);
  $('main').classList.toggle('hidden', !t);
  if (!t) return;
  renderSources(t);
  renderPhaseCard(t);
  renderEntities(t);
  renderWarnings(t);
  renderPhases(t);
  renderExport(t);
}

function renderTabs() {
  $('tabs').innerHTML = S.tabs.map((t) => `
    <a role="tab" class="tab gap-2 ${t.id === S.cur ? 'tab-active' : ''}" data-id="${t.id}">
      <span class="badge badge-xs ${KIND_BADGE[t.view.kind]}">${KIND_LABEL[t.view.kind]}</span>
      <span class="max-w-64 truncate">${esc(t.view.title)}</span>
      <span class="opacity-60 hover:opacity-100" data-close="${t.id}">✕</span>
    </a>`).join('');
  $('tabs').querySelectorAll('[role=tab]').forEach((a) => a.onclick = (e) => {
    const c = e.target.dataset.close;
    if (c) { closeTab(c); return; }
    S.cur = a.dataset.id; render();
  });
}

async function closeTab(id) {
  await call('close_tab', id);
  S.tabs = S.tabs.filter((t) => t.id !== id);
  if (S.cur === id) S.cur = S.tabs.length ? S.tabs[S.tabs.length - 1].id : null;
  render();
}

// ---- 材料（プル・戦闘）
function renderSources(t) {
  const v = t.view;
  $('srcTitle').textContent = v.kind === 'file' ? 'ファイル'
    : (v.kind === 'record' ? '記録ログ（1 ファイル＝1 プル）' : (v.kind === 'combined' ? 'リプレイ＋記録ログ（組にしたプル）' : 'リプレイとプル'));
  if (v.kind === 'file') {
    $('srcBody').innerHTML = `<div class="mono text-xs break-all">${esc(v.paths[0])}</div>
      <div class="text-xs opacity-70 mt-2">先頭のコメント（書き出しても残ります）</div>
      <div class="mono text-xs bg-base-200 rounded p-2 whitespace-pre-wrap">${esc((v.head || []).join('\n')) || '（なし）'}</div>
      <div class="text-xs opacity-70 mt-2">イベントの後ろのコメントは、書き出すと消えます。秒数・フェーズを作り直すときは、リプレイか記録ログから作ってください。</div>`;
    return;
  }
  const encs = v.encounters || [];
  let h = '';
  if (encs.length > 1) {
    h += `<label class="text-xs opacity-70">戦闘（最初に戦う本物の敵）</label>
      <select id="encSel" class="select select-sm w-full mb-2">${encs.map((e) =>
        `<option value="${e.contentid}" ${e.selected ? 'selected' : ''}>${esc(e.name || '敵 ' + e.contentid)}（${e.contentid}）${e.pulls.length} プル・${Math.round(e.sec)} 秒</option>`).join('')}</select>`;
  }
  const sel = encs.find((e) => e.selected);
  const pulls = v.pulls.filter((p) => !sel || p.encounter === sel.contentid || p.used);
  const chosen = v.options.pulls;
  h += `<div class="flex items-center justify-between"><span class="text-xs opacity-70">使うプル（${v.pull_labels.length}）</span>
        <span class="text-xs"><a class="link" id="pullAll">全部</a></span></div>
      <div class="flex flex-col gap-1 max-h-72 overflow-auto">`;
  for (const p of pulls) {
    const on = chosen ? chosen.includes(p.label) : p.used;
    const res = p.result === 'clear' ? '<span class="badge badge-success badge-xs">clear</span>'
      : `<span class="badge badge-ghost badge-xs">${esc(p.result)}${p.pct != null ? ' ' + p.pct + '%' : ''}</span>`;
    const note = [p.when, p.no_start ? 'カウントダウンなし' : '', (v.kind === 'record' || p.src === 'log') ? p.t0 : (p.engage != null ? 'CD ' + p.engage + 's' : '')].filter(Boolean).join('・');
    h += `<label class="flex items-center gap-2 cursor-pointer" title="${esc(p.file)}">
        <input type="checkbox" class="checkbox checkbox-xs pullChk" value="${p.label}" ${on ? 'checked' : ''}>
        <span class="mono w-14">${p.label}</span><span class="w-14 text-right">${p.sec}s</span>${res}
        ${v.kind === 'combined' ? `<span class="badge badge-xs ${p.src === 'log' ? 'badge-secondary' : 'badge-primary'}">${p.src === 'log' ? 'ログだけ' : 'リプレイ'}</span>` : ''}
        <span class="text-xs opacity-60 truncate">${esc(note)}</span></label>`;
    if (p.pair && p.pair.found) {
      h += `<label class="flex items-center gap-2 ml-6 text-xs cursor-pointer ${p.pair.paired ? '' : 'opacity-50'}" title="詠唱 ${p.pair.casts} 回で確かめた組。外すと、リプレイのプルとログのプルを別々に使います">
        <input type="checkbox" class="checkbox checkbox-xs pairChk" value="${esc(p.pair.key)}" ${p.pair.paired ? 'checked' : ''}>
        <span>組：${esc(p.pair.log)}</span><span class="mono opacity-70">${p.pair.paired ? (p.pair.shift >= 0 ? '+' : '') + p.pair.shift.toFixed(2) + 's' : '外した'}</span></label>`;
    } else if (p.pair && p.src !== 'log') {
      h += `<div class="ml-6 text-xs opacity-60">組になるログなし（秒数の基準は推し量り ${(p.pair.shift >= 0 ? '+' : '') + p.pair.shift.toFixed(2)}s）</div>`;
    }
  }
  h += `</div>
    <label class="flex items-center gap-2 mt-1 cursor-pointer"><input id="optReal" type="checkbox" class="checkbox checkbox-xs" ${v.options.real_only ? 'checked' : ''}>
      <span>本物の敵（攻撃を受けた敵）の詠唱だけ</span></label>
    ${v.kind === 'combined' ? `<label class="flex items-center gap-2 cursor-pointer" title="組にならなかったリプレイのプルは、交戦開始の取り方で 1 秒ほどずれます。イベント・分岐・入れ替わりを見つけるのには全部のプルを使います">
      <input id="optTimePaired" type="checkbox" class="checkbox checkbox-xs" ${v.options.time_paired !== false ? 'checked' : ''}>
      <span>秒数は組になったプルで決める</span></label>` : ''}
    <button id="btnRe" class="btn btn-sm btn-primary mt-2">この内容で解析し直す</button>
    <p class="text-xs opacity-60">戦闘・プル・フェーズの区切りを変えたら解析し直します。名前などの直しは残ります。</p>
    ${v.kind === 'combined' ? '<p class="text-xs opacity-60">組の右の秒数は、リプレイの最初の攻撃から記録ログの戦闘開始（t = 0）までのずれです。秒数の基準を記録ログに合わせています。</p>' : ''}`;
  $('srcBody').innerHTML = h;
  if ($('encSel')) $('encSel').onchange = () => reanalyze({ encounter: Number($('encSel').value), pulls: null, splits: null });
  $('pullAll').onclick = () => document.querySelectorAll('.pullChk').forEach((c) => c.checked = true);
  $('btnRe').onclick = () => {
    const pl = [...document.querySelectorAll('.pullChk')].filter((c) => c.checked).map((c) => c.value);
    if (!pl.length) { toast('プルを 1 つ以上選んでください', 'warning'); return; }
    const opts = { pulls: pl, real_only: $('optReal').checked };
    if ($('optTimePaired')) opts.time_paired = $('optTimePaired').checked;
    if (v.kind === 'combined') {
      opts.unpair = [...document.querySelectorAll('.pairChk')].filter((c) => !c.checked).map((c) => c.value);
      opts.pulls = null;      // 組を変えるとプルの番号が変わるので、選び直しはしない
      if (JSON.stringify(opts.unpair) === JSON.stringify(v.options.unpair || [])) opts.pulls = pl;
    }
    reanalyze(opts);
  };
}

async function reanalyze(opts) {
  const t = curTab();
  const v = await call('reanalyze', t.id, opts);
  if (!v) return;
  t.view = v;
  render();
}

// ---- フェーズの区切り
function currentSplits(v) {
  if (v.options.splits) return v.options.splits.slice();
  // 自動で分けたもの（採用した候補）を、手の区切りの形にする
  return (v.candidates || []).filter((c) => c.adopted).map((c) => ({ type: 'cast_start', contentid: c.contentid, action: c.actions, at: c.median }));
}

function renderPhaseCard(t) {
  const v = t.view;
  $('phaseCard').classList.toggle('hidden', v.kind === 'file');
  if (v.kind === 'file') return;
  const tlph = v.tl.phases;
  let h = '<div class="flex flex-col gap-1">';
  for (const ph of tlph) {
    const st = (v.phases_info.find((x) => x.id === ph.id) || { starts: {} }).starts;
    h += `<div class="flex items-center gap-2"><span class="badge badge-sm badge-outline mono">${ph.id}</span>
      <span class="text-xs">${esc(trigText(ph.trigger, v))}</span>
      <span class="text-xs opacity-60 ml-auto mono">${Object.entries(st).map(([k, x]) => k + '=' + x).join(' ')}</span></div>`;
  }
  h += '</div>';
  const sp = v.options.splits;
  h += `<div class="text-xs opacity-70 mt-2">${sp ? '手で決めた区切り' : '自動（途中から別の本物の敵が詠唱を始めたら次のフェーズ）'}</div>`;
  if (sp && sp.length) {
    h += sp.map((x, i) => `<div class="flex items-center gap-2"><span class="text-xs">${esc(splitText(x, v))}</span>
      ${(x.type === 'cast_start' || x.type === 'targetable') ? `<label class="label cursor-pointer gap-1 ml-auto" title="秒数に関係なく、それが来たところ（何回目か）で区切ります（プルによって来る時刻が違うとき：覚醒編 4 層の車型／人型、火力で長さが変わる雑魚フェーズなど）"><input type="checkbox" class="checkbox checkbox-xs spAny" data-i="${i}" ${x.anywhere ? 'checked' : ''}><span class="text-xs">どこで来ても</span></label>` : ''}
      <button class="btn btn-xs btn-ghost ${(x.type === 'cast_start' || x.type === 'targetable') ? '' : 'ml-auto'} spDel" data-i="${i}">外す</button></div>`).join('');
  }
  if (sp) h += '<button id="spAuto" class="btn btn-xs mt-1">自動に戻す</button>';
  const cands = (v.candidates || []).filter((c) => c.kind !== 'new_enemy_hit');
  if (cands.length) {
    h += '<div class="text-xs opacity-70 mt-2">候補</div>';
    h += cands.map((c, i) => `<div class="flex items-center gap-2">
      <span class="text-xs">${esc(candText(c))}</span>
      ${c.kind === 'hp_stop' ? (c.hp_percent != null ? `<button class="btn btn-xs ml-auto cAdd" data-i="${i}" title="この敵の HP が ${c.hp_percent}% 以下になったら次のフェーズ（火力で時刻が変わるフェーズ用）">HP ${c.hp_percent}% で分ける</button>` : '')
        : `<button class="btn btn-xs ml-auto cAdd" data-i="${i}">ここで分ける</button>`}</div>`).join('');
  }
  const seenCid = new Set();
  const ents = Object.entries(v.tl.entities || {}).filter(([k, e]) => !seenCid.has(e.contentid) && seenCid.add(e.contentid));
  if (ents.length) {
    h += `<div class="text-xs opacity-70 mt-2">HP で分ける（その敵の HP がこの % 以下になったら次のフェーズ）</div>
      <div class="flex items-center gap-1">
      <select id="hpEnt" class="select select-xs flex-1 min-w-0">${ents.map(([k, e]) => `<option value="${e.contentid}">${esc(k)}（${e.contentid}）</option>`).join('')}</select>
      <input id="hpPct" class="input input-xs w-14 mono" placeholder="%">
      <span class="text-xs whitespace-nowrap">% 以下</span><button id="hpAdd" class="btn btn-xs whitespace-nowrap">分ける</button></div>`;
  }
  h += '<p class="text-xs opacity-60 mt-2">イベントの行の「分ける」でも、その詠唱から次のフェーズにできます。分岐の行の「流れで分ける」は、来たアクションごとに別のフェーズにします（どこで来ても）。HP で区切るのは、本当に HP で移る戦闘だけにしてください（時刻で移る戦闘では、プルごとの HP がばらばらになります）。</p>';
  $('phaseBody').innerHTML = h;
  $('phaseBody').querySelectorAll('.spDel').forEach((b) => b.onclick = () => {
    const s = currentSplits(v); s.splice(Number(b.dataset.i), 1); reanalyze({ splits: s });
  });
  $('phaseBody').querySelectorAll('.spAny').forEach((c) => c.onchange = () => {
    const s = currentSplits(v); s[Number(c.dataset.i)] = { ...s[Number(c.dataset.i)], anywhere: c.checked }; reanalyze({ splits: s });
  });
  if ($('spAuto')) $('spAuto').onclick = () => reanalyze({ splits: null });
  if ($('hpAdd')) $('hpAdd').onclick = () => {
    const pct = Number($('hpPct').value);
    if (!($('hpPct').value.trim() !== '' && pct > 0 && pct < 100)) { toast('HP は 0 より大きく 100 より小さい % で入れてください', 'warning'); return; }
    const s = currentSplits(v);
    s.push({ type: 'hp_below', contentid: Number($('hpEnt').value), percent: pct, at: 0 });
    reanalyze({ splits: s });
  };
  $('phaseBody').querySelectorAll('.cAdd').forEach((b) => b.onclick = () => {
    const c = cands[Number(b.dataset.i)];
    const s = currentSplits(v);
    s.push(c.kind === 'untargetable' || c.kind === 'retargetable'
      ? { type: 'targetable', contentid: c.contentid, state: c.kind === 'retargetable', at: c.median, ...(c.nth ? { anywhere: true, nth: c.nth } : {}) }
      : c.kind === 'hp_stop'
        ? { type: 'hp_below', contentid: c.contentid, percent: c.hp_percent, at: c.median }
        : { type: 'cast_start', contentid: c.contentid, action: c.actions, at: c.median });
    reanalyze({ splits: s });
  });
}

function actName(t, a) {
  const e = t.edits.actions[a];
  return (e !== undefined && e !== '') ? e : (t.view.action_names[a] || '');
}

function trigText(tr, v) {
  if (!tr) return '';
  if (tr.type === 'combat_start') return '戦闘開始';
  const who = tr.entity || '';
  if (tr.type === 'cast_start') return `${who} が ${[].concat(tr.action).join('/')} を詠唱${tr.nth ? '（' + tr.nth + ' 回目）' : ''}`;
  if (tr.type === 'targetable') return `${who} がターゲット${tr.state ? '可' : '不可'}になった${tr.nth ? '（' + tr.nth + ' 回目）' : ''}`;
  if (tr.type === 'hp_below') return `${who} の HP が ${tr.percent}% 以下`;
  return JSON.stringify(tr);
}

function splitText(x, v) {
  const cid = x.contentid;
  if (x.type === 'targetable') return `${cid} がターゲット${x.state ? '可に戻った' : '不可'}（${x.anywhere ? (x.nth || 1) + ' 回目・どこで来ても' : x.at + ' 秒ごろ'}）`;
  if (x.type === 'hp_below') return `${cid} の HP が ${x.percent}% 以下`;
  if (x.anywhere) return `${cid} が ${[].concat(x.action).join('/')} を詠唱（${x.nth > 1 ? x.nth + ' 回目' : '1 回目'}・どこで来ても）`;
  return `${cid} が ${[].concat(x.action).join('/')} を詠唱（${x.at} 秒ごろ）`;
}

function candText(c) {
  const who = (c.name || c.contentid) + '（' + c.entity + '）';
  const tm = Object.entries(c.times).map(([k, x]) => k + '=' + x).join(' ');
  if (c.kind === 'untargetable') return `${who} がターゲット不可：${tm}`;
  if (c.kind === 'retargetable') return `${who} がターゲット可に戻った：${tm}`;
  if (c.kind === 'hp_stop') return `${who} の HP が止まった：${tm}${Object.keys(c.hp || {}).length ? '（HP ' + Object.entries(c.hp).map(([k, x]) => k + '=' + x + '%').join(' ') + '）' : ''}${Object.keys(c.hp || {}).length > 1 && c.hp_percent == null ? '。HP がプルでばらばら（HP ではなく時刻で移っている）' : ''}`;
  return `${who} が途中から詠唱 ${c.actions.join('/')}：${tm}${c.adopted ? '（採用 ' + c.phase + '）' : ''}`;
}

// ---- 敵
function renderEntities(t) {
  const v = t.view;
  const ents = Object.entries(v.tl.entities);
  let h = '<div class="flex flex-col gap-2">';
  for (const [k, e] of ents) {
    const ed = t.edits.entities[k] || {};
    const nm = ed.name !== undefined && ed.name !== '' ? ed.name : (v.kind === 'file' ? e.name : (v.npc_names[k] || e.name));
    h += `<div class="flex items-center gap-2 ${ed.off ? 'opacity-40' : ''}">
      <input type="checkbox" class="checkbox checkbox-xs entOn" data-k="${esc(k)}" ${ed.off ? '' : 'checked'} title="外すと、この敵の詠唱のイベントを全部外します">
      <span class="mono text-xs w-20 truncate" title="${esc(k)}">${esc(k)}</span>
      <span class="mono text-xs opacity-60 w-12">${e.contentid}</span>
      <input class="input input-xs flex-1 entName" data-k="${esc(k)}" value="${esc(nm)}"></div>`;
    if (e._comment) h += `<div class="text-xs opacity-50 -mt-1 ml-6">${esc(e._comment)}</div>`;
  }
  h += '</div>';
  $('entBody').innerHTML = h;
  $('entBody').querySelectorAll('.entName').forEach((i) => i.onchange = () => {
    (t.edits.entities[i.dataset.k] ||= {}).name = i.value;
  });
  $('entBody').querySelectorAll('.entOn').forEach((c) => c.onchange = () => {
    (t.edits.entities[c.dataset.k] ||= {}).off = !c.checked;
    renderEntities(t); renderPhases(t);
  });
  // 直していない名前は、書き出すときに Python 側で名前辞書・ログの名前を使う（解析し直してキーが変わっても古い名前が残らない）
}

function renderWarnings(t) {
  const w = t.view.warnings || [];
  $('warnBox').innerHTML = w.length ? `<div class="alert alert-warning text-xs flex-col items-start gap-1">
    <b>注意（${w.length}）</b>${w.map((x) => `<div>${esc(x)}</div>`).join('')}</div>` : '';
}

// ---- イベントの一覧
function renderPhases(t) {
  const v = t.view;
  const offEnt = new Set(Object.entries(t.edits.entities).filter(([, e]) => e.off).map(([k]) => k));
  let h = '';
  if (v.kind !== 'file' && v.pull_labels.length === 1) {
    h += '<div class="alert alert-info text-xs">1 プルだけです。ランダム分岐・順番の入れ替わり・時刻のばらつきは分かりません。同じコンテンツのプルを増やすと分かります。</div>';
  }
  for (const ph of v.tl.phases) {
    const pe = t.edits.phases[ph.id] || {};
    h += `<div class="card bg-base-100 shadow-sm"><div class="card-body p-3 gap-2">
      <div class="flex items-center gap-2">
        <span class="badge badge-primary mono">${ph.id}</span>
        <input class="input input-sm w-48 phName" data-p="${ph.id}" value="${esc(pe.name ?? ph.name)}">
        <span class="text-xs opacity-70">きっかけ：${esc(trigText(ph.trigger, v))}</span>
      </div>
      <div class="overflow-x-auto"><table class="table table-xs events"><thead class="sticky-head"><tr>
        <th>使う</th><th class="text-right">t</th><th class="text-right">詠唱</th><th>種類</th><th title="プル間のばらつき（秒）">ばらつき</th>
        <th title="出たプル／届いたプル">出現</th><th>詠唱者</th><th>アクション・技名</th><th>イベント名</th><th>同期点</th><th title="照合を受け付ける予定時刻からのずれ（既定 5 秒）">許容</th><th></th>
      </tr></thead><tbody>`;
    for (const ev of ph.events) h += eventRow(t, ph, ev, offEnt);
    h += '</tbody></table></div>';
    const extra = ph.syncs.filter((s) => !s._event);
    if (extra.length) {
      h += `<div class="text-xs opacity-70">イベントに結び付かない同期点（そのまま書きます）：${extra.map((s) => esc(trigText(s.on, v)) + ' t=' + s.t).join(' ／ ')}</div>`;
    }
    h += '</div></div>';
  }
  $('phasesBox').innerHTML = h;
  bindPhases(t);
}

function eventRow(t, ph, ev, offEnt) {
  const v = t.view;
  const info = ev._info || {};
  const ed = t.edits.events[ev.id] || {};
  const off = ed.off || offEnt.has((ev.match || {}).entity);
  const acts = [].concat(ed.action || (ev.match || {}).action || []);
  const [kl, kb] = SLOT_KIND[info.kind] || ['', ''];
  const syncOn = t.edits.syncs[ev.id] !== undefined ? t.edits.syncs[ev.id] : !!info.auto_sync;
  const syncBox = info.sync_ok
    ? `<input type="checkbox" class="toggle toggle-xs evSync" data-e="${ev.id}" ${syncOn ? 'checked' : ''} title="${info.sync_nth ? 'nth = ' + info.sync_nth : 'この戦闘で 1 回だけ'}">`
    : '<span class="opacity-30" title="アクションが 1 つでない・何回目かがプルで違う・同じ技が複数回（ファイルから開いたとき）">—</span>';
  const tol = ed.tolerance !== undefined ? ed.tolerance : (ev.tolerance ?? '');
  const byPull = info.by_pull ? Object.entries(info.by_pull).map(([k, x]) => k + ': ' + (x ? x.t + 's ' + x.actions.join('+') : '—')).join('\n') : '';
  const editableActs = ['branch', 'swap', 'file'].includes(info.kind);
  const actCells = acts.map((a) => `<div class="flex items-center gap-1">
      <span class="mono text-xs opacity-70 w-12">${a}</span>
      <input class="input input-xs w-52 actName" data-a="${a}" value="${esc(actName(t, a))}" placeholder="技名"></div>`).join('');
  return `<tr class="${off ? 'ev-off' : ''}" title="${esc(byPull)}">
    <td><input type="checkbox" class="checkbox checkbox-xs evOn" data-e="${ev.id}" ${off ? '' : 'checked'}></td>
    <td class="text-right mono">${Number(ev.t).toFixed(1)}</td>
    <td class="text-right mono opacity-70">${ev.cast != null ? Number(ev.cast).toFixed(1) : ''}</td>
    <td>${kl ? `<span class="badge badge-xs ${kb}">${kl}</span>` : ''}${info.partner ? `<div class="text-xs opacity-60 mono">↔${esc(info.partner)}</div>` : ''}</td>
    <td class="mono text-xs ${info.spread > 1 ? 'text-warning' : 'opacity-70'}">${info.spread ?? ''}</td>
    <td class="mono text-xs opacity-70">${info.seen != null ? info.seen + '/' + info.reached : ''}</td>
    <td class="mono text-xs">${esc((ev.match || {}).entity || '')}${info.real === false ? '<div class="opacity-50">発射役など</div>' : ''}</td>
    <td class="ev-act">${actCells}${editableActs ? `<input class="input input-xs w-full mono mt-1 evActs" data-e="${ev.id}" value="${acts.join(',')}" title="照合するアクション（カンマ区切り。どれか 1 つが来れば照合）">` : ''}</td>
    <td class="ev-name"><input class="input input-xs w-44 evName" data-e="${ev.id}" value="${esc(ed.name ?? (isProvisional(ev.name) ? '' : ev.name))}" placeholder="${esc(ev.name)}"></td>
    <td>${syncBox}</td>
    <td><input class="input input-xs w-14 mono evTol" data-e="${ev.id}" value="${esc(tol)}" placeholder="5"></td>
    <td><div class="flex flex-col items-start gap-0.5">${v.kind !== 'file' && ph.events.indexOf(ev) > 0 ? `<button class="btn btn-ghost btn-xs evSplit whitespace-nowrap" data-e="${ev.id}" title="この詠唱から次のフェーズにする">分ける</button>` : ''}${v.kind !== 'file' && info.kind === 'branch' ? `<button class="btn btn-ghost btn-xs evRoute whitespace-nowrap" data-e="${ev.id}" title="来たアクションごとに別のフェーズにする（秒数に関係なく、そのアクションが来たところから）。流れが枝分かれする戦闘用。ランダムで技が変わるだけなら使わない">流れで分ける</button>` : ''}</div></td>
  </tr>`;
}

// 「38383 #1」「36335/38513 #1」「38345+38346 #1」の形（変換ツールが付けた仮名）
const isProvisional = (n) => /^[\d/+]+ #\d+$/.test(String(n || ''));

function bindPhases(t) {
  const box = $('phasesBox');
  const ev = (id) => (t.edits.events[id] ||= {});
  box.querySelectorAll('.phName').forEach((i) => i.onchange = () => { (t.edits.phases[i.dataset.p] ||= {}).name = i.value; });
  box.querySelectorAll('.evOn').forEach((c) => c.onchange = () => { ev(c.dataset.e).off = !c.checked; renderPhases(t); });
  box.querySelectorAll('.evName').forEach((i) => i.onchange = () => { ev(i.dataset.e).name = i.value; });
  box.querySelectorAll('.evTol').forEach((i) => i.onchange = () => {
    const x = i.value.trim();
    if (x !== '' && !(Number(x) > 0)) { toast('許容は 0 より大きい秒数で入れてください', 'warning'); i.value = ''; return; }
    ev(i.dataset.e).tolerance = x === '' ? null : Number(x);
  });
  box.querySelectorAll('.evActs').forEach((i) => i.onchange = () => {
    const xs = i.value.split(/[,\s/]+/).filter(Boolean).map(Number);
    if (!xs.length || xs.some((x) => !Number.isInteger(x) || x <= 0)) { toast('アクション ID をカンマ区切りの数で入れてください', 'warning'); return; }
    ev(i.dataset.e).action = xs; renderPhases(t);
  });
  box.querySelectorAll('.actName').forEach((i) => i.onchange = () => {
    t.edits.actions[i.dataset.a] = i.value;
    box.querySelectorAll(`.actName[data-a="${i.dataset.a}"]`).forEach((o) => { if (o !== i) o.value = i.value; });
  });
  box.querySelectorAll('.evSync').forEach((c) => c.onchange = () => { t.edits.syncs[c.dataset.e] = c.checked; });
  box.querySelectorAll('.evSplit').forEach((b) => b.onclick = () => {
    const v = t.view;
    const e = v.tl.phases.flatMap((p) => p.events).find((x) => x.id === b.dataset.e);
    const info = e._info;
    const s = currentSplits(v);
    s.push({ type: 'cast_start', contentid: info.contentid, action: info.all_actions, at: info.t_combat });
    reanalyze({ splits: s });
  });
  box.querySelectorAll('.evRoute').forEach((b) => b.onclick = () => {
    const v = t.view;
    const e = v.tl.phases.flatMap((p) => p.events).find((x) => x.id === b.dataset.e);
    const info = e._info;
    const s = currentSplits(v);
    // どのプルにも来るアクション（分岐していない方）は外す
    const seen = Object.values(info.by_pull || {}).filter(Boolean);
    let acts = info.all_actions.filter((a) => !seen.every((p) => p.actions.includes(a)));
    if (!acts.length) acts = info.all_actions;
    for (const a of acts) s.push({ type: 'cast_start', contentid: info.contentid, action: [a], at: info.t_combat, anywhere: true });
    reanalyze({ splits: s });
  });
}

// ---- 書き出し
function renderExport(t) {
  const v = t.view;
  const meta = v.tl.meta;
  $('mName').value = t.edits.meta.name ?? (v.default_title || meta.name || '');
  // 作成者：画面で直した値 → タイムラインの値 → 設定の作成者（新しく作るときだけ）。空の文字は「無い」として次へ
  $('mAuthor').value = t.edits.meta.author ?? (meta.author || (v.kind !== 'file' ? (S.info?.settings.author || '') : ''));
  $('mVersion').value = t.edits.meta.version ?? meta.version ?? 1;
  $('fPrefix').textContent = (v.mapid || 0) + '_';
  $('fName').value = t.fname;
  $('fDest').value = t.dest || v.dest || '';
  $('exportMsg').innerHTML = t.msg || '';
  showMigrate(t);
  if (v.kind !== 'file' && !t.edits.meta.author && S.info?.settings.author) t.edits.meta.author = S.info.settings.author;
}

function collectMeta(t) {
  const v = t.view;
  const def = v.kind === 'file' ? v.tl.meta.name : (v.default_title || v.tl.meta.name);
  if ($('mName').value === (def || '')) delete t.edits.meta.name; else t.edits.meta.name = $('mName').value;
  t.edits.meta.author = $('mAuthor').value;
  t.edits.meta.version = $('mVersion').value;
  t.fname = $('fName').value.trim();
  t.dest = $('fDest').value.trim();
}

async function preview() {
  const t = curTab(); if (!t) return;
  collectMeta(t);
  const r = await call('preview', t.id, t.edits, t.fname, t.dest);
  if (!r) return;
  $('pvTitle').textContent = 'プレビュー：' + r.path + (r.exists ? '（上書き）' : '（新しいファイル）');
  $('pvCheck').innerHTML = `<div class="alert ${r.check.ok ? 'alert-success' : 'alert-error'} text-xs">${esc(r.check.message)}</div>`;
  $('preview').textContent = r.text;
  $('dlgPreview').showModal();
}

async function doExport(overwrite, migrate) {
  const t = curTab(); if (!t) return;
  collectMeta(t);
  if (migrate === undefined && mig(t).on) return migrateFlow(t);
  const r = await call('export', t.id, t.edits, t.fname, t.dest, $('fNames').checked, overwrite, migrate || null);
  if (!r) return;
  if (r.need_overwrite) {
    if (confirm(r.message)) return doExport(true, migrate || null);
    return;
  }
  let msg = `<div class="alert ${r.unchanged ? 'alert-info' : 'alert-success'} text-xs break-all">${esc(r.message)}</div>`;
  if (r.names) {
    msg += `<div class="text-xs mt-1 ${r.names.written ? '' : 'opacity-70'}">names\\actions.lua：${r.names.written ? r.names.changed.length + ' 件を書きました' : esc(r.names.reason)}</div>`;
  }
  if (r.plans) {
    const p = r.plans;
    const w = p.done.filter((x) => x.written);
    msg += `<div class="text-xs mt-1">プラン：${w.length ? w.map((x) => esc(x.file) + '（前の版 backup\\' + esc(x.backup) + '）').join('、') + ' を書き換えました' : '書き換えるところはありませんでした'}${p.moved_old ? '。元のタイムラインを timelines\\backup\\' + esc(p.moved_old) + ' に移しました' : ''}</div>`;
    if (p.missing.length) msg += `<div class="text-xs text-warning">見つからないエントリ ${p.missing.length} 件：${p.missing.map((x) => esc(x.file + ' ' + x.id)).join('、')}</div>`;
    for (const e of p.errors) msg += `<div class="text-xs text-error">${esc(e)}</div>`;
  }
  if (r.first) msg += `<div class="text-xs opacity-70 mt-1">このマップでアドオンが最初に使うタイムライン：${esc(r.first)}${r.others && r.others.length ? '（ほかに ' + r.others.map(esc).join('、') + '）' : ''}</div>`;
  t.msg = msg;
  $('exportMsg').innerHTML = msg;
  toast(r.message, r.unchanged ? 'info' : 'success');
  refreshInfo();
}

// ---- 設定
function openSettings() {
  const s = S.info?.settings || {};
  $('sFirst').classList.toggle('hidden', !!S.info?.luamods_ok);
  $('sLuamods').value = s.luamods || '';
  $('sReplay').value = s.replay_dir || '';
  $('sAuthor').value = s.author || '';
  const n = S.info?.names || {};
  $('sInfo').textContent = `timelines: ${S.info?.timelines_dir}\n名前辞書: 技 ${n.actions ?? 0}・敵 ${n.npcs ?? 0}` +
    ((n.bad_actions || []).length ? `（actions.lua に読めない行 ${n.bad_actions.join(',')}）` : '');
  $('dlgSettings').showModal();
}

async function saveSettings() {
  const info = await call('set_settings', { luamods: $('sLuamods').value, replay_dir: $('sReplay').value, author: $('sAuthor').value });
  if (!info) return;
  S.info = info;
  $('dlgSettings').close();
  await refreshInfo();
  render();
  toast('設定を保存しました', 'success', 2500);
}
