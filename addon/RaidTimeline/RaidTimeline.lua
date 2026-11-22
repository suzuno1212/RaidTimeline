-- =====================================================================
-- RaidTimeline（仮称）  v0.6.9  記録モード ＋ ドライラン ＋ 実行（oGCD） ＋ 音（wav） ＋ タイムライン表示 ＋ プラン編集
--
-- v0.6.9：同じマップに前半・後半などのタイムラインが複数あるとき（1327_x_p1.lua・1327_x_p2.lua など）：
--         ・戦闘開始のとき、パーティが最初に攻撃した敵（ターゲット）が、どのタイムラインの「始まりの敵」かで選ぶ
--           （始まりの敵＝戦闘開始のフェーズで最初の 30 秒に詠唱する敵。v0.6.8 までは entities の敵がいる最初のものだったので、
--           前半のタイムラインに後半のボスが entities に入っていると、後半でも前半のタイムラインのままだった）
--         ・戦闘の途中で、ほかのタイムラインの始まりの敵の HP が初めて減ったら、そのタイムラインに引き継ぐ
--           （前半から後半へ続けて進んだとき。ドライランのログは <日時>_2_dryrun.csv に分かれる）
--         ・プランの meta.timeline がこのマップのほかのタイムラインなら、「違います」の注意を出さない
--         ・ドライランの「読み直す」・プラン編集の「読み直す」で、プラン編集のタイムラインの一覧も作り直す
-- v0.6.8：分岐（match.action が配列）のイベントのエントリに onAction（来たアクションがこれのときだけ使う）。
--         照合を待ってから判定する（照合が予定より遅ければ、照合したときに判定）。来なかった方は「対象外（別の分岐）」。
--         プラン編集の編集欄に「分岐」の行（どれが来ても／アクションごと）。音の byAction（v0.4.0）はそのまま。
--         フェーズのきっかけ targetable に nth（戦闘開始から同じ向きに変わった何回目か。雑魚フェーズの後にボスに戻るところ用）
-- v0.6.7：プラン編集で、エントリが 1 つも無いタイムライン（作ったばかりのプランなど）は、全部のイベントを出す
--         （v0.6.6 までは「エントリの無いイベントも出す」を ON にしないと、タイムラインの名前しか出なかった）
-- v0.6.6：プラン編集の「プランを選ぶ」に、タイムラインがあってプランがまだ無いマップも出し、今のジョブのプランを作れるようにした
--         （「<ジョブ>_<ポジション> を作る」「<ジョブ>_ANY を作る」。コンテンツの外でも。中身はエントリなし）
-- v0.6.5：プラン編集のアクションの一覧から、level が 0 のジョブのアクション（PvP のアクション。実機の一覧で 18 件）を外した
-- v0.6.4：プラン編集で、エントリを消した瞬間のエラー（attempt to index local 'e'）を直した（消すのを次のフレームに回す）。
--         ほかのジョブのプランで「追加」が音だけのとき、理由を出す
-- v0.6.3：プラン編集で、エントリの音を wav フォルダの wav から選ぶ・試す・外す、音だけのエントリを足す、基準（詠唱開始／着弾）を選ぶ
-- v0.6.2：プラン編集で、イベントにエントリを足す（「追加」）・消す、offset を数で入れる、対象（自分・今のターゲット・
--         タイムラインの敵）を選べるようにした
-- v0.6.1：プラン編集で、plans\<mapid>\ のプランを選んで直せるようにした（コンテンツの外でも。「プランを選ぶ」）
--         アクションの一覧を、今のジョブ（job が一致）＋ロールアクション・スプリント（ID の表）だけにした（v0.6.0 は usable で
--         敵のアクションまで出ていた）。調査用に「一覧をログに書く」（logs\actions_dump_<job>.csv）
-- v0.6.0：プランを画面で編集する別ウィンドウ（RTL_PE_*。メニュー「RaidTimeline → Plan」、ドライランの画面の「編集」）
--         エントリのアクション（今のジョブのアクション一覧から。GCD と oGCD は別の区分・色。GCD は未対応と出すだけ）・
--         offset（0.5 秒ずつ）・使う／使わない（execute = false）を変える。変えたら 0.7 秒後に保存（戦闘中も）し、
--         ポジション変更と同じく今のフェーズの残りから並べ直す。書く前の版を plans/<mapid>/backup/ に 10 世代とっておき、
--         「元に戻す」で 1 つ前の版に戻す。書き出したものは読み直して確かめる。ドライランのログに kind = plan_edit
--         設定（settings.lua）：planWindow（プラン編集の画面を開いておく）
-- v0.5.1：タイムライン表示で、技名の後ろのバッジ・右の秒数がずれていたのを直した（文字の幅の取り方の誤り。RTL_UI_TextW）
--         まとめた行では、名前の取れない技（#ID）を名前のある技と並べない。画面の「→」はゲームの文字に無いので「->」にした
-- v0.5.0：画面の部品（テーマ・カード・バッジ・バー・ボタン。RTL_UI_*）を 1 か所にまとめ、記録モード・ドライランの画面を作り直した
--         （表示する内容は v0.4.1 と同じ。ダークテーマ、背景の透明度・文字の大きさは設定で変える）
--         タイムライン表示（別ウィンドウ。RTL_TV_*）：次に来る技を、技名・残り秒数（着弾まで）・バーで並べる。
--         分岐は照合まで「A / B」、照合したら実際の技名。技の下に自分のアクション・音と判定の結果。戦闘外・道中は見出しだけ
--         設定（settings.lua）：tvShow・tvLock・tvX・tvY・tvWidth・tvCount・tvRange・tvBar・tvCast・tvOwn・tvMerge・tvSteps・tvFar・
--         tvAlpha・uiAlpha・uiScale（ドライランの画面の「タイムライン表示の設定」「見た目」で変える。戦闘中でもすぐ反映）
-- v0.4.1：記録モードの戦闘開始が first_hostile を取りこぼすことがあった（ドライランが先に始まると、パーティのアクションの
--         一覧を消していた）のを直した
-- v0.4.0：戦闘開始（t0）を「incombat の hostileSec 秒前までの、敵を対象にした最初のパーティのアクション」（first_hostile）にした
--         （リプレイの攻撃パケットと比べて決めた。ボス 6 戦で ±0.02 秒。旧 first_action は最大 +0.83 秒遅れていた）
--         無ければ旧 first_action（直前 1.5 秒以内の最後のパーティのアクション）→ first_hit → combat_start。記録モード・ドライランの両方
--         プランのエントリに sound（wav を鳴らす。分岐ごとに別の音は byAction）。ファイルの後ろの「音」の節
--         鳴らし方：常駐させた PowerShell に 1 行ずつ送る（ゲームは待たない）。予備に「毎回起動」
--         音の ON/OFF（実行の ON/OFF・一時停止とは別）、早めに鳴らす秒数、wav の置き場所（既定 RaidTimeline\wav）
-- v0.3.0：実行エンジン（oGCD。対象は自分・ターゲット・ボス）を追加（ファイル後半の「実行」の節）
--         実行のスイッチ（既定 OFF）・一時停止（画面のボタン／MMOminion のショートカット「RaidTimeline Pause」）
--         プランのエントリに execute（false ならドライランだけ）・priority（"weave" 既定／"now"）
--         衝突の検証ログ：logs/<mapid>/<日時>_actions.csv（自分のアクションを全部。成功・応答なし・他が先に使用・
--         二重使用の疑い・GCD 遅れの疑い・GCD の間隔）。実行が OFF でも記録する
--         記録モードの技名を ActionList:Get(1, ID)（種類が先）で取る（names/actions.lua と CSV の name 列に入る）
--         戦闘開始の直前のパーティのアクションの対象（castinginfo.castingtargets）を調べてドライランのログに残す（fa_probe）
-- v0.2.2：ドライランのクリア／全滅を自分で判定する。イベント名が仮名なら、ゲームの技名（ActionList:Get(1, ID)）で表示する
-- v0.2.1：ドライランの判定で ActionList:Get の引数を（種類, ID）の順に直した（実機で「アクションがない」になっていた）
--         プルの最初の照合で、敵のアクション名が ActionList:Get(1, ID) で取れるかをログに残す（api_probe）
-- v0.2.0：タイムラインの読み込み・フェーズ判定・時計と同期点・イベントの照合・ドライランを追加
--   （ファイル後半の「ドライラン」の節。記録モードの処理は v0.1.5 のまま）
--   timelines/<mapid>_*.lua と plans/<mapid>/<job>_<pos>.lua は、Lua として実行せずに表として読む
--   ドライランのログ：logs/<mapid>/<日時>_dryrun.csv
--
-- 戦闘中のイベントを「ログ CSV」（ファイル形式仕様 5 章）に書き、
-- 見かけた ID と名前を「名前辞書」（仕様 6 章）に追記する。
--
--   logs/<mapid>/<YYYYMMDD_HHMMSS>.csv        1 プル＝1 ファイル（UTF-8 BOM 付き・CRLF）
--   logs/<mapid>/<YYYYMMDD_HHMMSS>_debug.txt  戦闘開始のずれ・API の確認用メモ
--   names/actions.lua / npcs.lua / buffs.lua  ID → 名前（UTF-8 BOM なし・CRLF）
--
-- 秒数 t の基準：変換ツールと同じ「最初にパーティが敵を攻撃した時刻」に近いものを、次の順で使う
--   0. first_hostile：incombat が切り替わる前 hostileSec 秒以内の、敵を対象にした最初のパーティのアクション（v0.4.0）
--                     （発動時の castinginfo.castingtargets に攻撃できる敵がいるもの。CSV には first_action 行・v1 = 1 で書く）
--   1. first_action：incombat が切り替わる直前（1.5 秒以内）に、パーティのアクションが発動した時刻（CSV の v1 = 0）
--   2. first_hit   ：そのプルの本物の敵の HP が最初に減った時刻（combat_start の 3 秒前〜5 秒後に限る）
--   3. combat_start：Player.incombat が切り替わった時刻
--   （スサノオの実測：攻撃パケット → incombat が +0.42 秒、HP が減る → +0.85 秒）
--
-- 仕様 5 章に加えた kind（記録モードだけが書く）
--   combat_start : incombat が切り替わった時刻。v1 = Player.localmapid、v2 = パーティ一覧の mapid
--   first_hit    : 最初に敵の HP が減った時刻。entity_id = その敵
--   first_action : 戦闘開始直前のパーティのアクション。entity_id = 使った人、action_id = アクションID
--   targetable   : v1 = 1（ターゲット可）／0（不可）
--   buff_gain / buff_lose : entity_id = 付いている人、action_id = バフID、v1 = 残り秒数、v2 = 付けた人の ID
--   marker       : entity_id = 付いた人、action_id = マーカーID、v1 = ジョブID（プレイヤーのとき）
--   tether       : entity_id = 線の元、target_id = 線の先、action_id = 線の種類、v1 = 1（付いた）／0（消えた）
--   cast_end     : cast = 対応する詠唱開始からの経過秒数（分からなければ空）
--   map_effect   : v1 = 番号、v2 = "状態1/状態2"（Argus のコールバックは 3 つの数値を渡す）
--
-- 決まり：main.Draw などから呼ぶ関数は local function にしない（すべて RTL_ で始まるグローバル関数）
-- =====================================================================

RTL = RTL or {}

RTL.version = "0.6.9"
RTL.path = GetLuaModsPath().."\\RaidTimeline"

-- 設定（settings.lua に保存されるのは record・window・dryrun・execute・position・dryWindow・sound・soundLead・soundMode・soundDir と、
--       v0.5.0 の tv*（タイムライン表示）・uiAlpha・uiScale だけ）
RTL.settings = {
    record      = true,   -- 記録する
    dryrun      = true,   -- ドライランする
    execute     = false,  -- 実行する（ドライランの判定が「実行」になったアクションを実際に使う。既定 OFF）
    position    = nil,    -- 自分のポジション（MT/ST/H1/H2/D1〜D4。nil なら <job>_ANY だけ）
    sound       = true,   -- 音を鳴らす（プランの sound。実行の ON/OFF・一時停止とは別。v0.4.0）
    soundLead   = 0.0,    -- 早めに鳴らす秒数（再生までの遅れの補正。画面で 0.05 秒ずつ変えられる）
    soundMode   = "resident", -- "resident"（PowerShell を常駐させて 1 行ずつ送る）／"oneshot"（鳴らすたびに起動）
    soundDir    = "",     -- wav の置き場所（空なら RaidTimeline\wav）
    hostileSec  = 2.5,    -- incombat のこの秒数前までの「敵を対象にしたパーティのアクション」を t0 にする（v0.4.0）
    tickSec     = 0.05,   -- Update の最短間隔
    scanSec     = 0.10,   -- エンティティ走査（出現・消滅・ターゲット可否・HP・詠唱の予備検出）
    idleScanSec = 0.50,   -- 戦闘していないときに敵が多い場所（idleManyEnts 体より多い）での走査間隔
    idleManyEnts = 80,
    slowSec     = 0.25,   -- バフ・線の走査
    hpSec       = 1.0,    -- HP の行を書く間隔
    autosaveSec = 30,     -- 記録中にファイルを書き直す間隔
    preSec      = 30,     -- 戦闘開始前の何秒分をファイルに含めるか
    endSec      = 2.0,    -- 戦闘フラグが消えてから、戦闘終了と判断するまでの秒数
    firstHitSec = 30,     -- first_hit と combat_start がこれ以上離れていたら first_hit を基準にしない
    firstActSec = 1.5,    -- combat_start のこの秒数前までのパーティのアクションを first_action とする
    hitBeforeSec = 3.0,   -- first_hit として認める範囲（combat_start の何秒前から）
    hitAfterSec  = 5.0,   --                         （combat_start の何秒後まで）
    realDrops   = 3,      -- HP の減少をこの回数以上見た敵を「本物の敵」とする
    minCasts    = 1,      -- 敵の詠唱がこの数より少ないプルは保存しない（フィールドの雑魚戦など）
    -- タイムライン表示・見た目（v0.5.0。settings.lua に保存）
    tvShow      = true,   -- タイムライン表示を出す
    tvLock      = false,  -- 位置を固定する（クリックを通す）
    tvX         = 60,     -- 位置
    tvY         = 260,
    tvWidth     = 320,    -- 幅
    tvCount     = 5,      -- 表示する件数
    tvRange     = 60,     -- 表示する秒数の範囲（着弾まで）
    tvBar       = "range",-- バーの減り方："range"（範囲に対する残り時間）／"each"（技ごとに 100% から）
    tvCast      = "cast", -- 詠唱中："cast"（詠唱バーに切り替える）／"keep"（そのまま）
    tvOwn       = true,   -- 自分のアクション・音を出す
    tvMerge     = true,   -- 同じ時刻（0.5 秒以内）の技を 1 行にまとめる
    tvSteps     = "5:F59E3B,10:4A9BF0",  -- 残り時間の区切りと色（秒:色）。この中に無い残り時間は tvFar
    tvFar       = "34C584",
    tvAlpha     = 0.80,   -- タイムライン表示の背景の透明度（0＝透明）
    uiAlpha     = 0.94,   -- 記録モード・ドライランの画面の背景の透明度
    uiScale     = 1.0,    -- 文字の大きさ
}
RTL.TV_DEFAULT = { tvX = 60, tvY = 260 }

RTL.window = RTL.window or { open = true, visible = true }

-- 実行時の状態
RTL.mapid       = RTL.mapid or 0
RTL.ents        = {}      -- [entity_id] = 今いるエンティティの記録
RTL.dead        = {}      -- 消えたエンティティの記録（プルの出現行を作るため、しばらく残す）
RTL.events      = {}      -- 記録したイベント（ms は Now() の絶対時刻）
RTL.seq         = 0
RTL.pull        = nil     -- 記録中のプル
RTL.lastPull    = nil     -- 直前のプルの結果（画面表示用）
RTL.firstHitMs  = nil
RTL.firstHitId  = nil
RTL.partyAct    = nil     -- 直近のパーティのアクション { ms, id, spell }
RTL.partySet    = {}
RTL.nameProbe   = nil
RTL.outSince    = nil
RTL.tethers     = {}
RTL.buffStore   = {}
RTL.last        = { tick = 0, scan = 0, slow = 0 }
RTL.names       = { actions = {}, npcs = {}, buffs = {} }
RTL.namesDirty  = { actions = false, npcs = false, buffs = false }
RTL.actionCache = {}
RTL.api         = RTL.api or { registered = false, counts = {}, dumps = {}, dumpCount = {} }
RTL.errors      = {}
RTL.initDone    = false

RTL.COLUMNS = "t,kind,entity_id,contentid,base_id,max_hp,action_id,cast,target_id,v1,v2,name"
RTL.KIND_ORDER = {
    appear = 0, targetable = 1, first_action = 2, combat_start = 2, first_hit = 2,
    cast_start = 3, cast_end = 4, buff_gain = 5, buff_lose = 5, marker = 5, tether = 5, map_effect = 5,
    hp = 6, disappear = 7, wipe = 9, clear = 9,
}

-- =====================================================================
-- 小道具
-- =====================================================================

function RTL_Now()
    if (type(Now) == "function") then
        return Now()
    end
    if (ml_global_information and ml_global_information.Now) then
        return ml_global_information.Now
    end
    return os.clock() * 1000
end

function RTL_Msg(msg)
    d("[RaidTimeline] "..tostring(msg))
end

-- エラーで止まらないように包む。同じ場所のエラーは最初の 3 回だけ表示する
function RTL_Safe(where, fn, ...)
    local ok, err = pcall(fn, ...)
    if (not ok) then
        local n = (RTL.errors[where] or 0) + 1
        RTL.errors[where] = n
        if (n <= 3) then
            RTL_Msg("error in "..where..": "..tostring(err))
        end
        RTL.lastError = where..": "..tostring(err)
    end
    return ok
end

function RTL_EnsureFolder(p)
    if (type(FolderExists) == "function" and type(FolderCreate) == "function") then
        if (not FolderExists(p)) then
            FolderCreate(p)
        end
    end
end

function RTL_WriteFile(path, text)
    local f = io.open(path, "wb")
    if (f) then
        f:write(text)
        f:close()
        return true
    end
    RTL_Msg("cannot open for write: "..path)
    return false
end

function RTL_ReadFile(path)
    local f = io.open(path, "rb")
    if (not f) then
        return nil
    end
    local s = f:read("*a")
    f:close()
    return s
end

-- 整数は %d、それ以外は小数第1位。nil は空
function RTL_Num(x)
    if (x == nil) then
        return ""
    end
    if (type(x) ~= "number") then
        return tostring(x)
    end
    if (x == math.floor(x) and math.abs(x) < 1e15) then
        return string.format("%d", x)
    end
    return RTL_Dec1(x)
end

-- 小数第1位（-0.0 にならないようにする）
function RTL_Dec1(x)
    if (x == nil) then
        return ""
    end
    local s = string.format("%.1f", x)
    if (s == "-0.0") then
        s = "0.0"
    end
    return s
end

function RTL_CsvField(s)
    s = tostring(s or "")
    if (s:find('[,"\r\n]')) then
        s = '"'..s:gsub('"', '""')..'"'
    end
    return s
end

function RTL_LuaString(s)
    s = tostring(s)
    s = s:gsub("\\", "\\\\")
    s = s:gsub('"', '\\"')
    s = s:gsub("\r", "\\r")
    s = s:gsub("\n", "\\n")
    return '"'..s..'"'
end

function RTL_Count(t)
    local n = 0
    for _ in pairs(t) do
        n = n + 1
    end
    return n
end

-- =====================================================================
-- 設定・名前辞書のファイル
-- =====================================================================

function RTL_LoadSettings()
    if (type(FileLoad) ~= "function") then
        return
    end
    local ok, t = pcall(FileLoad, RTL.path.."\\settings.lua")
    if (ok and type(t) == "table") then
        if (t.record ~= nil) then RTL.settings.record = (t.record == true) end
        if (t.window ~= nil) then RTL.window.open = (t.window == true) end
        if (t.dryrun ~= nil) then RTL.settings.dryrun = (t.dryrun == true) end
        if (t.execute ~= nil) then RTL.settings.execute = (t.execute == true) end
        if (type(t.position) == "string" and t.position ~= "") then RTL.settings.position = t.position end
        if (t.dryWindow ~= nil and RTL.window2) then RTL.window2.open = (t.dryWindow == true) end
        if (t.planWindow ~= nil and RTL.pe) then RTL.pe.open = (t.planWindow == true) end
        if (t.sound ~= nil) then RTL.settings.sound = (t.sound == true) end
        if (type(t.soundLead) == "number" and t.soundLead >= 0 and t.soundLead <= 2) then RTL.settings.soundLead = t.soundLead end
        if (t.soundMode == "resident" or t.soundMode == "oneshot") then RTL.settings.soundMode = t.soundMode end
        if (type(t.soundDir) == "string") then RTL.settings.soundDir = t.soundDir end
        RTL_LoadUiSettings(t)
    end
end

-- タイムライン表示・見た目の設定（v0.5.0）。範囲の外の値は使わない
function RTL_LoadUiSettings(t)
    local S = RTL.settings
    local function num(k, lo, hi, int)
        local v = t[k]
        if (type(v) == "number" and v >= lo and v <= hi) then
            S[k] = int and math.floor(v + 0.5) or v
        end
    end
    local function bool(k)
        if (t[k] ~= nil) then S[k] = (t[k] == true) end
    end
    bool("tvShow") bool("tvLock") bool("tvOwn") bool("tvMerge")
    num("tvX", -10000, 20000, true) num("tvY", -10000, 20000, true)
    num("tvWidth", 160, 1200, true) num("tvCount", 1, 50, true) num("tvRange", 5, 600, true)
    num("tvAlpha", 0, 1) num("uiAlpha", 0.1, 1) num("uiScale", 0.5, 2.5)
    if (t.tvBar == "range" or t.tvBar == "each") then S.tvBar = t.tvBar end
    if (t.tvCast == "cast" or t.tvCast == "keep") then S.tvCast = t.tvCast end
    if (type(t.tvSteps) == "string" and (t.tvSteps == "" or #RTL_TV_ParseSteps(t.tvSteps) > 0)) then S.tvSteps = t.tvSteps end
    if (RTL_UI_Hex(t.tvFar)) then S.tvFar = t.tvFar end
end

function RTL_SaveSettings()
    if (type(FileSave) ~= "function") then
        return
    end
    pcall(FileSave, RTL.path.."\\settings.lua", {
        record = RTL.settings.record, window = RTL.window.open,
        dryrun = RTL.settings.dryrun, execute = (RTL.settings.execute == true), position = RTL.settings.position or "",
        dryWindow = (RTL.window2 == nil) or RTL.window2.open,
        planWindow = (RTL.pe ~= nil and RTL.pe.open == true),
        sound = (RTL.settings.sound == true), soundLead = RTL.settings.soundLead, soundMode = RTL.settings.soundMode,
        soundDir = RTL.settings.soundDir or "",
        tvShow = (RTL.settings.tvShow ~= false), tvLock = (RTL.settings.tvLock == true),
        tvX = RTL.settings.tvX, tvY = RTL.settings.tvY, tvWidth = RTL.settings.tvWidth,
        tvCount = RTL.settings.tvCount, tvRange = RTL.settings.tvRange, tvBar = RTL.settings.tvBar, tvCast = RTL.settings.tvCast,
        tvOwn = (RTL.settings.tvOwn ~= false), tvMerge = (RTL.settings.tvMerge ~= false),
        tvSteps = RTL.settings.tvSteps, tvFar = RTL.settings.tvFar,
        tvAlpha = RTL.settings.tvAlpha, uiAlpha = RTL.settings.uiAlpha, uiScale = RTL.settings.uiScale,
    })
end

-- names/*.lua（return { [id] = "名前", ... }）を読む。
--   MMOminion では環境を差し替える関数が使えないため、Lua として実行せず、1 行ずつ [id] = "名前" を読む。
--   ファイルが無ければ空の表、読めない行があれば nil（そのときは上書きしない）
function RTL_UnescapeLua(s)
    s = s:gsub('\\(.)', function(c)
        if (c == "n") then return "\n" end
        if (c == "r") then return "\r" end
        return c
    end)
    return s
end

function RTL_ParseNameText(s)
    if (s:sub(1, 3) == "\239\187\191") then
        s = s:sub(4)
    end
    local t, bad = {}, 0
    for line in (s.."\n"):gmatch("([^\n]*)\n") do
        line = line:gsub("\r$", "")
        if (line:find("%[")) then
            local id, body = line:match('^%s*%[(%d+)%]%s*=%s*"(.*)"%s*,?%s*$')
            if (id) then
                t[tonumber(id)] = RTL_UnescapeLua(body)
            else
                bad = bad + 1
            end
        end
    end
    if (bad > 0) then
        return nil, bad
    end
    return t, 0
end

function RTL_LoadNameFile(kind)
    local s = RTL_ReadFile(RTL.path.."\\names\\"..kind..".lua")
    if (not s) then
        return {}
    end
    local t, bad = RTL_ParseNameText(s)
    if (not t) then
        RTL_Msg("names/"..kind..".lua: "..bad.." line(s) could not be read (file kept as is, new names are not saved)")
    end
    return t
end

function RTL_SaveNameFile(kind)
    local t = RTL.names[kind]
    if (not t) then
        return
    end
    local keys = {}
    for k in pairs(t) do
        if (type(k) == "number") then
            keys[#keys + 1] = k
        end
    end
    table.sort(keys)
    local lines = { "return {" }
    for _, k in ipairs(keys) do
        lines[#lines + 1] = "    ["..string.format("%d", k).."] = "..RTL_LuaString(t[k])..","
    end
    lines[#lines + 1] = "}"
    if (RTL_WriteFile(RTL.path.."\\names\\"..kind..".lua", table.concat(lines, "\r\n").."\r\n")) then
        RTL.namesDirty[kind] = false
    end
end

function RTL_SaveNames()
    for kind, dirty in pairs(RTL.namesDirty) do
        if (dirty and RTL.names[kind]) then
            RTL_SaveNameFile(kind)
        end
    end
end

-- 名前を追加（すでにある ID は書き換えない）
function RTL_AddName(kind, id, name)
    local t = RTL.names[kind]
    if (not t or type(id) ~= "number" or id <= 0) then
        return
    end
    if (type(name) ~= "string" or name == "") then
        return
    end
    if (t[id] == nil) then
        t[id] = name
        RTL.namesDirty[kind] = true
    end
end

-- アクション名。ActionList:Get(1, id)（種類が先。v0.3.0 で直した）で取れなければ空（結果はキャッシュする）
function RTL_ActionName(id)
    if (type(id) ~= "number" or id <= 0) then
        return ""
    end
    local c = RTL.actionCache[id]
    if (c ~= nil) then
        return c or ""
    end
    local name = false
    local ok, a = pcall(function() return ActionList:Get(1, id) end)
    if (ok and type(a) == "table") then
        local n = a.name
        if (type(n) == "string" and n ~= "") then
            name = n
            RTL_ApiCount("actionNameVia_ActionList")
        end
    end
    if (not name) then
        name = RTL_ActionNameLib(id) or false
    end
    RTL.actionCache[id] = name
    if (name) then
        RTL_AddName("actions", id, name)
        RTL.api.counts.actionNameHit = (RTL.api.counts.actionNameHit or 0) + 1
    else
        RTL.api.counts.actionNameMiss = (RTL.api.counts.actionNameMiss or 0) + 1
    end
    return name or ""
end

-- FFXIVLib.API.Action にあるそれらしい関数を試す（敵のアクション名用。実機で使えるか確認中）
RTL.NAME_FUNCS = { "GetActionById", "GetById", "GetAction", "GetActionName", "GetName" }

function RTL_PickName(v)
    if (type(v) == "string" and v ~= "") then
        return v
    end
    if (type(v) == "table") then
        for _, k in ipairs({ "name", "Name", "name_ja", "Name_ja", "ja", "jp", "name_en", "Name_en", "en" }) do
            if (type(v[k]) == "string" and v[k] ~= "") then
                return v[k]
            end
        end
    end
    return nil
end

function RTL_ActionNameLib(id)
    local lib = FFXIVLib and FFXIVLib.API and FFXIVLib.API.Action
    if (type(lib) ~= "table") then
        return nil
    end
    for _, fname in ipairs(RTL.NAME_FUNCS) do
        local fn = lib[fname]
        if (type(fn) == "function") then
            local ok, v = pcall(fn, id)
            if (ok and v == nil) then
                ok, v = pcall(fn, id, "ja")
            end
            if (ok) then
                RTL_ApiDump("FFXIVLib.API.Action."..fname, id, v)
                local n = RTL_PickName(v)
                if (n) then
                    RTL_ApiCount("actionNameVia_"..fname)
                    return n
                end
            end
        end
    end
    return nil
end

-- 値を短い文字列に（表はキーを 12 個まで）
function RTL_Describe(v)
    if (type(v) ~= "table") then
        return type(v)..":"..tostring(v)
    end
    local ks, n = {}, 0
    for k, x in pairs(v) do
        n = n + 1
        if (#ks < 12) then
            ks[#ks + 1] = tostring(k).."="..(type(x) == "table" and "{..}" or tostring(x))
        end
    end
    return "table("..n.."){"..table.concat(ks, ", ").."}"
end

function RTL_ProbeCall(lines, label, fn, ...)
    if (type(fn) ~= "function") then
        lines[#lines + 1] = label.." -> (no function)"
        return
    end
    local ok, v = pcall(fn, ...)
    lines[#lines + 1] = label.." -> "..(ok and RTL_Describe(v) or ("error: "..tostring(v)))
end

-- 名前を引けそうな API を調べて、確認用メモに残す（FFXIVLib が見つかった最初の 1 回だけ）
function RTL_ProbeNameApi()
    if (RTL.nameProbe) then
        return RTL.nameProbe
    end
    local lines = {}
    local api = FFXIVLib and FFXIVLib.API
    if (type(api) ~= "table") then
        return { "FFXIVLib.API: not found (yet)" }
    end
    local subs = {}
    for k in pairs(api) do subs[#subs + 1] = tostring(k) end
    table.sort(subs)
    lines[#lines + 1] = "FFXIVLib.API: "..table.concat(subs, " ")
    local A = api.Action
    if (type(A) == "table") then
        local fns = {}
        for k, v in pairs(A) do fns[#fns + 1] = tostring(k)..(type(v) == "function" and "()" or "") end
        table.sort(fns)
        lines[#lines + 1] = "FFXIVLib.API.Action: "..table.concat(fns, " ")
        -- 中のデータ（_byId が空なら、初期化前の可能性）
        lines[#lines + 1] = "Action._byId = "..RTL_Describe(A._byId)
        lines[#lines + 1] = "Action._dataTables = "..RTL_Describe(A._dataTables)
        if (type(A._dataTables) == "table") then
            for k, v in pairs(A._dataTables) do
                lines[#lines + 1] = "  _dataTables."..tostring(k).." = "..RTL_Describe(v)
            end
        end
        -- プレイヤーのアクション（ランパート 7531）と敵のアクション（870 = 攻撃）で、引数を変えて試す
        for _, id in ipairs({ 7531, 870 }) do
            RTL_ProbeCall(lines, "GetActionName("..id..")", A.GetActionName, id)
            RTL_ProbeCall(lines, "GetActionName("..id..",\"ja\")", A.GetActionName, id, "ja")
            RTL_ProbeCall(lines, "GetActionName("..id..",\"en\")", A.GetActionName, id, "en")
            RTL_ProbeCall(lines, "GetActionById("..id..")", A.GetActionById, id)
            RTL_ProbeCall(lines, "A:GetActionName("..id..")", A.GetActionName, A, id)
            RTL_ProbeCall(lines, "SearchActions(\""..id.."\")", A.SearchActions, tostring(id))
        end
        RTL_ProbeCall(lines, "ActionList:Get(870)", function() return ActionList:Get(870) end)
        RTL_ProbeCall(lines, "ActionList:Get(7531,1)", function() return ActionList:Get(7531, 1) end)
    end
    for _, sub in ipairs({ "Strings", "NPC", "Status" }) do
        local t = api[sub]
        if (type(t) == "table") then
            local fns = {}
            for k, v in pairs(t) do fns[#fns + 1] = tostring(k)..(type(v) == "function" and "()" or "") end
            table.sort(fns)
            lines[#lines + 1] = "FFXIVLib.API."..sub..": "..table.concat(fns, " ")
        end
    end
    RTL.nameProbe = lines
    return lines
end

-- =====================================================================
-- イベントとエンティティ
-- =====================================================================

function RTL_AddEvent(ev)
    RTL.seq = RTL.seq + 1
    ev.seq = RTL.seq
    RTL.events[#RTL.events + 1] = ev
    if (RTL.pull) then
        local c = RTL.pull.counts
        c[ev.kind] = (c[ev.kind] or 0) + 1
    end
    return ev
end

-- 敵として扱うか（type=2 の中から、プレイヤー・ペットを除く）
function RTL_IsTrackable(e)
    if (not e or not e.id) then
        return false
    end
    if (Player and e.id == Player.id) then
        return false
    end
    local ct = e.chartype
    if (ct == 4 or ct == 3) then   -- 4 = プレイヤー、3 = ペット（ffxivminion 本体の判定に合わせる）
        return false
    end
    return true
end

function RTL_NewEnt(e, now)
    local hp = e.hp
    local r = {
        id        = e.id,
        cid       = e.contentid or 0,
        name      = e.name or "",
        maxhp     = (hp and hp.max) or 0,
        seenMs    = now,
        goneMs    = nil,
        missing   = 0,
        targetable = (e.targetable == true),
        lastHp    = hp and hp.current,
        drops     = 0,
        firstDropMs = nil,
        lastDropMs  = nil,
        hpLogMs   = 0,
        hpLogged  = nil,
        cast      = nil,
    }
    RTL.ents[e.id] = r
    RTL_AddName("npcs", r.cid, r.name)
    -- 最初からターゲット可能なものだけ、出現と同時刻に targetable=1 を書く（発射役は書かない）
    if (r.targetable) then
        RTL_AddEvent({ ms = now, kind = "targetable", id = r.id, cid = r.cid, maxhp = r.maxhp, v1 = 1, name = r.name })
    end
    return r
end

-- 最初に敵の HP が減った時刻（＝戦闘開始の基準）
function RTL_OnHpDrop(r, now)
    r.drops = r.drops + 1
    r.lastDropMs = now
    if (not r.firstDropMs) then
        r.firstDropMs = now
    end
    if (not RTL.firstHitMs) then
        RTL.firstHitMs = now
        RTL.firstHitId = r.id
    end
end

function RTL_CastStart(id, spell, target, castSec, ms, src)
    local r = RTL.ents[id]
    if (not r) then
        local e = EntityList:Get(id)
        if (e and RTL_IsTrackable(e)) then
            r = RTL_NewEnt(e, ms)
        end
    end
    local ev = RTL_AddEvent({
        ms = ms, kind = "cast_start", id = id,
        cid = r and r.cid, maxhp = r and r.maxhp,
        action = spell, cast = castSec, target = target,
        name = RTL_ActionName(spell),
        src = src,
    })
    if (src == "cb") then ev.cbMs = ms else ev.pollMs = ms end
    if (r) then
        r.cast = { spell = spell, ms = ms, ev = ev }
    end
    return ev
end

-- =====================================================================
-- Argus のコールバック
--   登録は 1 回だけ（解除の手段がないため）。中身は RTL_On* を名前で呼ぶので、リロード後も新しい中身が動く
-- =====================================================================

function RTL_Active()
    return RTL.settings.record and RTL.mapid ~= 0 and RTL.initDone
end

function RTL_ApiCount(name)
    RTL.api.counts[name] = (RTL.api.counts[name] or 0) + 1
end

-- 実機で引数の形を確認するためのメモ（コールバックごとに最初の 20 回）
function RTL_ApiDump(name, ...)
    local n = (RTL.api.dumpCount[name] or 0) + 1
    RTL.api.dumpCount[name] = n
    if (n > 20) then
        return
    end
    local parts = {}
    local cnt = select("#", ...)
    for i = 1, cnt do
        local v = select(i, ...)
        local s = type(v)..":"..tostring(v)
        if (type(v) == "table") then
            local kv = {}
            for k, x in pairs(v) do
                kv[#kv + 1] = tostring(k).."="..tostring(x)
                if (#kv >= 8) then break end
            end
            s = "table{"..table.concat(kv, ",").."}"
        end
        parts[#parts + 1] = s
    end
    local dumps = RTL.api.dumps
    dumps[#dumps + 1] = os.date("%H:%M:%S").." "..name.."("..cnt.."): "..table.concat(parts, ", ")
    if (#dumps > 200) then
        table.remove(dumps, 1)
    end
end

function RTL_RegisterArgus()
    if (RTL.api.registered or RTL_ArgusRegistered) then
        RTL.api.registered = true
        return
    end
    if (type(Argus) ~= "table") then
        return
    end
    local function reg(fname, handler)
        if (type(Argus[fname]) == "function") then
            local ok, err = pcall(Argus[fname], handler)
            if (not ok) then
                RTL_Msg("Argus."..fname.." failed: "..tostring(err))
            end
        else
            RTL_Msg("Argus."..fname.." not found")
        end
    end
    reg("registerOnEntityChannel", function(...)
        if (RTL_OnChannel) then RTL_Safe("OnChannel", RTL_OnChannel, ...) end
    end)
    reg("registerOnEntityCast", function(...)
        if (RTL_OnCast) then RTL_Safe("OnCast", RTL_OnCast, ...) end
    end)
    reg("registerOnMarkerAdd", function(...)
        if (RTL_OnMarker) then RTL_Safe("OnMarker", RTL_OnMarker, ...) end
    end)
    reg("registerOnMapEffect", function(...)
        if (RTL_OnMapEffect) then RTL_Safe("OnMapEffect", RTL_OnMapEffect, ...) end
    end)
    reg("registerOnTetherChange", function(...)
        if (RTL_OnTetherChange) then RTL_Safe("OnTetherChange", RTL_OnTetherChange, ...) end
    end)
    RTL.api.registered = true
    RTL_ArgusRegistered = true
    RTL_Msg("Argus callbacks registered")
end

-- 詠唱開始（entityID, spellID, targetID, channelTimeMax）
function RTL_OnChannel(entityID, spellID, targetID, castMax)
    RTL_ApiCount("channel")
    if (RTL_TL_OnChannel) then RTL_Safe("TL_OnChannel", RTL_TL_OnChannel, entityID, spellID, targetID, castMax) end
    if (not RTL_Active()) then return end
    local e = EntityList:Get(entityID)
    if (e and not RTL_IsTrackable(e)) then return end
    RTL_ApiDump("OnEntityChannel", entityID, spellID, targetID, castMax)
    local now = RTL_Now()
    local r = RTL.ents[entityID]
    if (r and r.cast and r.cast.spell == spellID and math.abs(now - r.cast.ms) < 1000) then
        -- 予備検出（ポーリング）で先に見つけていた
        r.cast.ev.cbMs = now
        if (castMax and (r.cast.ev.cast == nil or r.cast.ev.cast == 0)) then r.cast.ev.cast = castMax end
        return
    end
    RTL_CastStart(entityID, spellID, targetID, castMax, now, "cb")
end

-- 詠唱完了・即時アクション（entityID, spellID, pos）
function RTL_OnCast(entityID, spellID, pos)
    RTL_ApiCount("cast")
    if (RTL_TL_OnCast) then RTL_Safe("TL_OnCast", RTL_TL_OnCast, entityID, spellID) end
    if (not RTL_Active()) then return end
    if (RTL.partySet[entityID]) then
        -- 戦闘開始の基準用に、パーティのアクションの時刻だけ控える（ファイルには first_action として 1 行だけ）
        if (not RTL.pull) then
            RTL.partyAct = { ms = RTL_Now(), id = entityID, spell = spellID }
            RTL_ApiDump("OnEntityCast(party)", entityID, spellID, pos)
        end
        return
    end
    local e = EntityList:Get(entityID)
    if (e and not RTL_IsTrackable(e)) then return end
    if (not e and not RTL.ents[entityID]) then return end   -- 分からないものは書かない（プレイヤーの可能性）
    RTL_ApiDump("OnEntityCast", entityID, spellID, pos)
    local now = RTL_Now()
    local r = RTL.ents[entityID]
    if (not r and e) then
        r = RTL_NewEnt(e, now)
    end
    local castSec = nil
    if (r and r.cast and r.cast.spell == spellID and not r.cast.ended) then
        castSec = (now - r.cast.ms) / 1000
        r.cast.ended = true
    end
    RTL_AddEvent({ ms = now, kind = "cast_end", id = entityID, cid = r and r.cid, maxhp = r and r.maxhp,
                   action = spellID, cast = castSec, name = RTL_ActionName(spellID) })
end

-- ヘッドマーカー（entityID, markerType）
function RTL_OnMarker(entityID, markerType)
    RTL_ApiCount("marker")
    if (not RTL_Active()) then return end
    RTL_ApiDump("OnMarkerAdd", entityID, markerType)
    local e = EntityList:Get(entityID)
    local ev = { ms = RTL_Now(), kind = "marker", id = entityID, action = markerType }
    if (e) then
        if (e.chartype == 4) then
            ev.v1 = e.job            -- プレイヤーは名前を書かず、ジョブID だけ
        else
            ev.cid = e.contentid
            ev.name = e.name
        end
    end
    RTL_AddEvent(ev)
end

-- マップエフェクト（実機では 3 つの数値：番号, 状態1, 状態2。例 6, 1, 2）
--   v1 = 番号、v2 = "状態1/状態2"
function RTL_OnMapEffect(...)
    RTL_ApiCount("mapeffect")
    if (not RTL_Active()) then return end
    RTL_ApiDump("OnMapEffect", ...)
    local a, b, c = ...
    local v2 = RTL_Num(b)
    if (c ~= nil) then
        v2 = v2.."/"..RTL_Num(c)
    end
    RTL_AddEvent({ ms = RTL_Now(), kind = "map_effect", v1 = a, v2 = v2 })
end

-- 線の変化：引数の形が分からないので、記録はポーリング（RTL_ScanTethers）で行い、ここでは形だけ控える
function RTL_OnTetherChange(...)
    RTL_ApiCount("tetherchange")
    if (not RTL_Active()) then return end
    RTL_ApiDump("OnTetherChange", ...)
end

-- =====================================================================
-- 走査
-- =====================================================================

function RTL_UpdatePartySet()
    local set = {}
    if (Player and Player.id) then
        set[Player.id] = true
    end
    local pml = EntityList.myparty
    if (pml) then
        for _, m in pairs(pml) do
            if (m and m.id) then
                set[m.id] = true
            end
        end
    end
    RTL.partySet = set
end

function RTL_ScanEntities(now)
    RTL_UpdatePartySet()
    local el = EntityList("type=2")
    local seen = {}
    if (el) then
        for id, e in pairs(el) do
            if (RTL_IsTrackable(e)) then
                seen[id] = true
                local r = RTL.ents[id]
                if (not r) then
                    r = RTL_NewEnt(e, now)
                end
                r.missing = 0
                r.lastSeenMs = now
                RTL_UpdateEnt(r, e, now)
            end
        end
    end
    local cnt = 0
    for _ in pairs(seen) do cnt = cnt + 1 end
    RTL.entCount = cnt
    -- 2 回続けて見つからなければ消滅（最初に見つからなかった時刻で記録）
    for id, r in pairs(RTL.ents) do
        if (not seen[id]) then
            r.missing = r.missing + 1
            if (r.missing == 1) then
                r.missingMs = now
            end
            if (r.missing >= 2) then
                r.goneMs = r.missingMs
                RTL_AddEvent({ ms = r.goneMs, kind = "disappear", id = id, cid = r.cid, maxhp = r.maxhp, name = r.name })
                RTL.dead[#RTL.dead + 1] = r
                RTL.ents[id] = nil
            end
        end
    end
end

function RTL_UpdateEnt(r, e, now)
    if ((r.name == "" or r.cid == 0) and e.name) then
        r.name = e.name
        r.cid = e.contentid or r.cid
        RTL_AddName("npcs", r.cid, r.name)
    end
    -- ターゲット可否
    local tg = (e.targetable == true)
    if (tg ~= r.targetable) then
        r.targetable = tg
        RTL_AddEvent({ ms = now, kind = "targetable", id = r.id, cid = r.cid, maxhp = r.maxhp, v1 = tg and 1 or 0, name = r.name })
    end
    -- HP
    local hp = e.hp
    if (hp) then
        local cur, mx = hp.current, hp.max
        if (mx and mx > r.maxhp) then
            r.maxhp = mx
        end
        if (cur) then
            if (r.lastHp and cur < r.lastHp) then
                RTL_OnHpDrop(r, now)
            end
            r.lastHp = cur
            if (r.drops >= 1 and cur ~= r.hpLogged
                and (now - r.hpLogMs >= RTL.settings.hpSec * 1000 or cur == 0)) then
                r.hpLogMs = now
                r.hpLogged = cur
                local pct = (r.maxhp > 0) and (cur * 100 / r.maxhp) or 0
                RTL_AddEvent({ ms = now, kind = "hp", id = r.id, cid = r.cid, maxhp = r.maxhp, v1 = RTL_Dec1(pct), v2 = cur, name = r.name })
            end
        end
    end
    -- 詠唱の予備検出（コールバックを取りこぼしたとき用）
    local ci = e.castinginfo
    if (ci) then
        local sid = ci.channelingid
        if (sid and sid ~= 0) then
            local ch = ci.channeltime or 0
            local startMs = now - ch * 1000
            local c = r.cast
            if ((not c) or c.spell ~= sid or (startMs - c.ms) > 1000) then
                RTL_CastStart(r.id, sid, ci.channeltargetid, ci.casttime, startMs, "poll")
            elseif (not c.ev.pollMs) then
                c.ev.pollMs = startMs
            end
        end
    end
end

-- バフ：自分と「敵らしいもの」（HP が減った敵、またはターゲット可能かつ攻撃可能な敵）
function RTL_ScanBuffs(now)
    local holders = {}
    if (Player and Player.id) then
        holders[Player.id] = true
    end
    for id, r in pairs(RTL.ents) do
        if (r.drops >= 1 or r.targetable) then
            holders[id] = true
        end
    end
    for id in pairs(holders) do
        local e = EntityList:Get(id)
        if (e) then
            if (id == Player.id or e.attackable or RTL.ents[id].drops >= 1) then
                RTL_DiffBuffs(id, e, now)
            end
        end
    end
    -- いなくなった人のバフ記録は捨てる
    for id in pairs(RTL.buffStore) do
        if (not holders[id]) then
            RTL.buffStore[id] = nil
        end
    end
end

function RTL_DiffBuffs(id, e, now)
    local store = RTL.buffStore[id]
    local first = (store == nil)
    store = store or {}
    local cur = {}
    local buffs = e.buffs
    if (buffs) then
        for _, b in pairs(buffs) do
            if (type(b) == "table" and b.id and b.id ~= 0) then
                local key = tostring(b.id)..":"..tostring(b.ownerid or 0)
                cur[key] = { id = b.id, owner = b.ownerid or 0, name = b.name }
                if (not store[key]) then
                    RTL_AddName("buffs", b.id, b.name)
                    -- 最初に見たときに付いていたものも buff_gain として書く（その時点で付いていた印）
                    RTL_AddEvent({ ms = now, kind = "buff_gain", id = id, cid = RTL.ents[id] and RTL.ents[id].cid,
                                   action = b.id, v1 = b.duration and RTL_Dec1(b.duration) or "", v2 = b.ownerid,
                                   name = b.name, initial = first or nil })
                end
            end
        end
    end
    for key, b in pairs(store) do
        if (not cur[key]) then
            RTL_AddEvent({ ms = now, kind = "buff_lose", id = id, cid = RTL.ents[id] and RTL.ents[id].cid,
                           action = b.id, v2 = b.owner, name = b.name })
        end
    end
    RTL.buffStore[id] = cur
end

function RTL_ScanTethers(now)
    if (type(Argus) ~= "table" or type(Argus.getCurrentTethers) ~= "function") then
        return
    end
    local ok, all = pcall(Argus.getCurrentTethers)
    if (not ok) then
        return
    end
    local cur = {}
    if (type(all) == "table") then
        for from, list in pairs(all) do
            if (type(list) == "table") then
                for i = 1, #list do
                    local x = list[i]
                    if (type(x) == "table" and x.type ~= nil) then
                        local to = x.targetid or x.partnerid or 0
                        local key = tostring(from)..">"..tostring(x.type)..">"..tostring(to)
                        cur[key] = { from = from, type = x.type, to = to }
                        if (not RTL.tethers[key]) then
                            local r = RTL.ents[from]
                            RTL_AddEvent({ ms = now, kind = "tether", id = from, cid = r and r.cid,
                                           action = x.type, target = to, v1 = 1, name = r and r.name })
                        end
                    end
                end
            end
        end
    end
    for key, t in pairs(RTL.tethers) do
        if (not cur[key]) then
            local r = RTL.ents[t.from]
            RTL_AddEvent({ ms = now, kind = "tether", id = t.from, cid = r and r.cid,
                           action = t.type, target = t.to, v1 = 0, name = r and r.name })
        end
    end
    RTL.tethers = cur
end

-- =====================================================================
-- 戦闘の開始・終了
-- =====================================================================

-- パーティ一覧から mapid と incombat を読む（EntityList.myparty → EntityList:Get で取り直す）
function RTL_PartyInfo()
    local mapid, incombat = nil, false
    local pml = EntityList.myparty
    if (pml) then
        for _, m in pairs(pml) do
            if (m) then
                if (mapid == nil and m.mapid) then
                    mapid = m.mapid
                end
                local e = EntityList:Get(m.id)
                if (e and e.incombat) then
                    incombat = true
                end
            end
        end
    end
    return mapid, incombat
end

function RTL_InCombat()
    if (Player.incombat) then
        return true, "player"
    end
    local _, pinc = RTL_PartyInfo()
    if (pinc) then
        return true, "party"
    end
    return false, nil
end

function RTL_StartPull(now, src)
    local mapid = RTL.mapid
    local partyMapid = RTL_PartyInfo()
    local stamp = os.date("%Y%m%d_%H%M%S")
    local dir = RTL.path.."\\logs\\"..tostring(mapid)
    RTL_EnsureFolder(RTL.path.."\\logs")
    RTL_EnsureFolder(dir)
    -- 同じ秒に始まったプルがあれば _2, _3 … を付ける
    local base, n = stamp, 1
    while (RTL_ReadFile(dir.."\\"..stamp..".csv")) do
        n = n + 1
        stamp = base.."_"..n
    end
    -- 古すぎる first_hit は今回の戦闘のものではない
    if (RTL.firstHitMs and (now - RTL.firstHitMs) > RTL.settings.firstHitSec * 1000) then
        RTL.firstHitMs, RTL.firstHitId = nil, nil
    end
    RTL.pull = {
        startMs = now, src = src, stamp = stamp, mapid = mapid, partyMapid = partyMapid,
        file = dir.."\\"..stamp..".csv", debugFile = dir.."\\"..stamp.."_debug.txt",
        counts = {}, savedMs = now,
    }
    for _, r in pairs(RTL.ents) do
        r.tgAtStart = r.targetable
    end
    -- 戦闘開始の基準（v0.4.0）：敵を対象にした最初のパーティのアクション → 直前の最後のパーティのアクション
    local pa = RTL.partyAct
    local lastOk = (pa and now - pa.ms >= 0 and now - pa.ms <= RTL.settings.firstActSec * 1000)
    if (lastOk) then
        RTL.pull.lastActMs = pa.ms
    end
    local h = RTL_FirstHostile(now)
    if (h) then
        RTL.pull.firstActMs, RTL.pull.t0Kind = h.ms, "first_hostile"
        RTL_AddEvent({ ms = h.ms, kind = "first_action", id = h.id, action = h.spell, v1 = 1 })
    elseif (lastOk) then
        RTL.pull.firstActMs, RTL.pull.t0Kind = pa.ms, "first_action"
        RTL_AddEvent({ ms = pa.ms, kind = "first_action", id = pa.id, action = pa.spell, v1 = 0 })
    end
    RTL.partyAct = nil
    RTL_AddEvent({ ms = now, kind = "combat_start", v1 = mapid, v2 = partyMapid })
    RTL_Msg("recording started: map="..tostring(mapid).." party.mapid="..tostring(partyMapid).." by "..tostring(src))
end

-- 最後に攻撃された本物の敵
function RTL_LastAttacked()
    local best = nil
    local function check(r)
        if (r.drops >= RTL.settings.realDrops and r.lastDropMs and (not best or r.lastDropMs > best.lastDropMs)) then
            best = r
        end
    end
    for _, r in pairs(RTL.ents) do check(r) end
    for _, r in ipairs(RTL.dead) do check(r) end
    return best
end

function RTL_EndPull(endMs, reason)
    local p = RTL.pull
    if (not p) then
        return
    end
    local last = RTL_LastAttacked()
    local kind, pct = "wipe", nil
    if (last) then
        if (last.maxhp > 0 and last.lastHp) then
            pct = last.lastHp * 100 / last.maxhp
        end
        if (last.lastHp == 0) then
            kind = "clear"
        end
    end
    RTL_AddEvent({ ms = endMs, kind = kind, id = last and last.id, cid = last and last.cid, v1 = pct and RTL_Dec1(pct) or "" })
    p.endMs = endMs
    p.result = kind
    local casts = p.counts.cast_start or 0
    if (casts < RTL.settings.minCasts) then
        RTL_Msg("pull discarded (enemy casts="..casts..")")
        RTL.lastPull = { file = "(破棄：敵の詠唱なし)", result = kind }
        if (p.saved) then
            pcall(os.remove, p.file)
            pcall(os.remove, p.debugFile)
        end
    else
        RTL_SavePull(endMs, true)
        RTL_Msg("recording saved: "..p.file.." ("..kind..")")
    end
    RTL_SaveNames()
    RTL_ResetAfterPull(endMs)
end

function RTL_ResetAfterPull(endMs)
    RTL.pull = nil
    RTL.outSince = nil
    RTL.firstHitMs, RTL.firstHitId = nil, nil
    for _, r in pairs(RTL.ents) do
        r.drops, r.firstDropMs, r.lastDropMs = 0, nil, nil
        r.hpLogMs, r.hpLogged = 0, nil
    end
    RTL.dead = {}
    -- プルの後に起きたことは次のプルの「開始前」として残す
    local keep = {}
    for _, ev in ipairs(RTL.events) do
        if (ev.ms > endMs) then
            keep[#keep + 1] = ev
        end
    end
    RTL.events = keep
end

-- 戦闘していない間は、古いイベント・消えたエンティティを捨てる
function RTL_Prune(now)
    local limit = now - RTL.settings.preSec * 1000 - 5000
    if (#RTL.events > 0 and RTL.events[1].ms < limit) then
        local keep = {}
        for _, ev in ipairs(RTL.events) do
            if (ev.ms >= limit) then
                keep[#keep + 1] = ev
            end
        end
        RTL.events = keep
    end
    if (#RTL.dead > 0) then
        local keep = {}
        for _, r in ipairs(RTL.dead) do
            if (r.goneMs >= limit) then
                keep[#keep + 1] = r
            end
        end
        RTL.dead = keep
    end
    if (RTL.firstHitMs and (now - RTL.firstHitMs) > RTL.settings.firstHitSec * 1000) then
        RTL.firstHitMs, RTL.firstHitId = nil, nil
    end
end

-- =====================================================================
-- ファイルに書く
-- =====================================================================

-- そのプルの本物の敵の HP が最初に減った時刻（ダンジョンで、前の戦闘の残りを拾わないように絞る）
function RTL_PullFirstHit(p)
    local best, bestId = nil, nil
    local lo = p.startMs - RTL.settings.hitBeforeSec * 1000
    local hi = p.startMs + RTL.settings.hitAfterSec * 1000
    local function check(r)
        local m = r.firstDropMs
        if (m and r.drops >= RTL.settings.realDrops and m >= lo and m <= hi and (not best or m < best)) then
            best, bestId = m, r.id
        end
    end
    for _, r in pairs(RTL.ents) do check(r) end
    for _, r in ipairs(RTL.dead) do check(r) end
    return best, bestId
end

-- 秒数の基準（first_hostile → first_action → first_hit → combat_start の順）
function RTL_PullT0(p)
    if (p.firstActMs) then
        return p.firstActMs, p.t0Kind or "first_action"
    end
    local fh = RTL_PullFirstHit(p)
    if (fh) then
        return fh, "first_hit"
    end
    return p.startMs, "combat_start"
end

-- 今いる、またはこのプル中に消えたエンティティの記録
function RTL_FindLife(id)
    if (id == nil) then
        return nil
    end
    if (RTL.ents[id]) then
        return RTL.ents[id]
    end
    for i = #RTL.dead, 1, -1 do
        if (RTL.dead[i].id == id) then
            return RTL.dead[i]
        end
    end
    return nil
end

function RTL_BuildRows(p, t0, winStart, winEnd)
    local rows = {}
    local realSet = {}
    local lives = {}
    for _, r in pairs(RTL.ents) do lives[#lives + 1] = r end
    for _, r in ipairs(RTL.dead) do lives[#lives + 1] = r end
    for _, r in ipairs(lives) do
        if (r.drops >= RTL.settings.realDrops) then
            realSet[r.id] = true
        end
    end
    -- 出現：プルの時間内にいたものすべて（戦闘開始前からいたものはマイナスの時刻）
    for _, r in ipairs(lives) do
        if (r.seenMs <= winEnd and (r.goneMs == nil or r.goneMs >= winStart)) then
            rows[#rows + 1] = { ms = r.seenMs, kind = "appear", seq = 0, id = r.id, cid = r.cid, maxhp = r.maxhp,
                                v1 = "", v2 = realSet[r.id] and 1 or 0, name = r.name }
        end
    end
    local fhMs, fhId = RTL_PullFirstHit(p)
    if (fhMs) then
        local r = RTL_FindLife(fhId)
        rows[#rows + 1] = { ms = fhMs, kind = "first_hit", seq = 0, id = fhId,
                            cid = r and r.cid, maxhp = r and r.maxhp, name = r and r.name }
    end
    local tgInWin = {}
    for _, ev in ipairs(RTL.events) do
        if (ev.ms >= winStart and ev.ms <= winEnd) then
            if (ev.kind ~= "hp" or realSet[ev.id]) then
                rows[#rows + 1] = ev
            end
            if (ev.kind == "targetable") then
                tgInWin[ev.id] = true
            end
        end
    end
    -- 前のプルから残っている敵：範囲内にターゲット可否の行がなければ、プル開始時の状態（可のときだけ）を出現時刻に書く
    for _, r in ipairs(lives) do
        if (r.seenMs < winStart and r.tgAtStart and not tgInWin[r.id]
            and (r.goneMs == nil or r.goneMs >= winStart)) then
            rows[#rows + 1] = { ms = r.seenMs, kind = "targetable", seq = 0, id = r.id, cid = r.cid,
                                maxhp = r.maxhp, v1 = 1, name = r.name }
        end
    end
    table.sort(rows, function(a, b)
        if (a.ms ~= b.ms) then return a.ms < b.ms end
        local oa, ob = RTL.KIND_ORDER[a.kind] or 5, RTL.KIND_ORDER[b.kind] or 5
        if (oa ~= ob) then return oa < ob end
        return (a.seq or 0) < (b.seq or 0)
    end)
    return rows, realSet
end

function RTL_RowToCsv(ev, t0)
    local f = {
        RTL_Dec1((ev.ms - t0) / 1000),
        ev.kind,
        RTL_Num(ev.id),
        RTL_Num(ev.cid),
        "",                                   -- base_id（ゲーム内では取れない）
        RTL_Num(ev.maxhp),
        RTL_Num(ev.action),
        (type(ev.cast) == "number") and RTL_Dec1(ev.cast) or "",
        RTL_Num(ev.target),
        RTL_Num(ev.v1),
        RTL_Num(ev.v2),
        RTL_CsvField(ev.name),
    }
    return table.concat(f, ",")
end

function RTL_SavePull(now, final)
    local p = RTL.pull
    if (not p) then
        return
    end
    local t0, t0src = RTL_PullT0(p)
    local winStart = math.min(p.startMs, t0) - RTL.settings.preSec * 1000
    local winEnd = final and (p.endMs or now) or now
    local rows, realSet = RTL_BuildRows(p, t0, winStart, winEnd)
    local out = { RTL.COLUMNS }
    for _, ev in ipairs(rows) do
        out[#out + 1] = RTL_RowToCsv(ev, t0)
    end
    if (RTL_WriteFile(p.file, "\239\187\191"..table.concat(out, "\r\n").."\r\n")) then
        p.saved = true
    end
    RTL_WriteFile(p.debugFile, RTL_DebugText(p, t0, t0src, rows, realSet, final))
    p.savedMs = now
    p.t0src = t0src
    RTL.lastPull = {
        file = p.stamp..".csv", result = final and p.result or "(記録中)",
        offsetMs = (t0src ~= "combat_start") and (p.startMs - t0) or nil, t0src = t0src, rows = #rows,
    }
    RTL_SaveNames()
end

function RTL_DebugText(p, t0, t0src, rows, realSet, final)
    local L = {}
    local function add(s) L[#L + 1] = s end
    add("[RaidTimeline "..RTL.version.."] "..p.stamp..(final and " (final)" or " (autosave)"))
    add("Player.localmapid = "..tostring(p.mapid))
    add("party mapid (EntityList.myparty) = "..tostring(p.partyMapid))
    add("combat_start by = "..tostring(p.src))
    add("t0 = "..t0src)
    local fhMs, fhId = RTL_PullFirstHit(p)
    if (fhMs) then
        local r = RTL_FindLife(fhId)
        add(string.format("first_hit -> combat_start = %+d ms  (entity %s contentid %s)",
            p.startMs - fhMs, tostring(fhId), tostring(r and r.cid)))
    else
        add("first_hit: not found")
    end
    if (p.firstActMs) then
        add(string.format("first_action -> combat_start = %+d ms", p.startMs - p.firstActMs))
        if (fhMs) then
            add(string.format("first_action -> first_hit    = %+d ms", fhMs - p.firstActMs))
        end
    else
        add("first_action: not found")
    end
    if (p.lastActMs) then
        add(string.format("last party action (old first_action) -> combat_start = %+d ms  (t0 %+d ms)",
            p.startMs - p.lastActMs, p.lastActMs - t0))
    end
    if (p.endMs) then
        add(string.format("duration = %.1f s  result = %s", (p.endMs - t0) / 1000, tostring(p.result)))
    end
    -- 本物の敵
    local reals = {}
    for id in pairs(realSet) do
        local r = RTL_FindLife(id)
        if (r) then
            reals[#reals + 1] = string.format("  %d contentid=%d maxhp=%d drops=%d name=%s", r.id, r.cid, r.maxhp, r.drops, r.name)
        end
    end
    add("real enemies:")
    for _, s in ipairs(reals) do add(s) end
    -- 行数
    local kinds = {}
    for _, ev in ipairs(rows) do kinds[ev.kind] = (kinds[ev.kind] or 0) + 1 end
    local ks = {}
    for k, n in pairs(kinds) do ks[#ks + 1] = k.."="..n end
    table.sort(ks)
    add("rows: "..table.concat(ks, " "))
    -- 詠唱の検出：コールバックとポーリングの差
    local both, cbOnly, pollOnly, lagSum, lagMax = 0, 0, 0, 0, 0
    for _, ev in ipairs(rows) do
        if (ev.kind == "cast_start") then
            if (ev.cbMs and ev.pollMs) then
                both = both + 1
                local lag = ev.cbMs - ev.pollMs
                lagSum = lagSum + lag
                if (math.abs(lag) > math.abs(lagMax)) then lagMax = lag end
            elseif (ev.cbMs) then
                cbOnly = cbOnly + 1
            else
                pollOnly = pollOnly + 1
            end
        end
    end
    add(string.format("cast_start detect: both=%d callback_only=%d poll_only=%d  (callback - poll) avg=%d ms max=%d ms",
        both, cbOnly, pollOnly, both > 0 and math.floor(lagSum / both) or 0, lagMax))
    -- API の呼ばれた回数
    local cs = {}
    for k, n in pairs(RTL.api.counts) do cs[#cs + 1] = k.."="..n end
    table.sort(cs)
    add("api counts: "..table.concat(cs, " "))
    add("argus registered: "..tostring(RTL.api.registered))
    if (RTL.lastError) then
        add("last error: "..RTL.lastError)
    end
    add("")
    add("--- name API probe ---")
    for _, s in ipairs(RTL_ProbeNameApi()) do add(s) end
    add("")
    add("--- callback arguments (first 20 per callback) ---")
    for _, s in ipairs(RTL.api.dumps) do add(s) end
    return table.concat(L, "\r\n").."\r\n"
end

-- =====================================================================
-- メインループ
-- =====================================================================

function RTL_OnMapChange(mapid, now)
    if (RTL.pull) then
        RTL_EndPull(now, "mapchange")
    end
    RTL.mapid = mapid
    RTL.ents, RTL.dead, RTL.events = {}, {}, {}
    RTL.tethers, RTL.buffStore = {}, {}
    RTL.firstHitMs, RTL.firstHitId, RTL.outSince = nil, nil, nil
    RTL.partyAct = nil
end

function RTL_Tick()
    local now = RTL_Now()
    if (now - RTL.last.tick < RTL.settings.tickSec * 1000) then
        return
    end
    RTL.last.tick = now
    if (not Player or not Player.id) then
        return
    end
    RTL_RegisterArgus()
    local mapid = Player.localmapid or 0
    if (mapid ~= RTL.mapid) then
        RTL_OnMapChange(mapid, now)
    end
    if (not RTL.settings.record) then
        if (RTL.pull) then
            RTL_EndPull(now, "stopped")
        end
        return
    end
    -- 戦闘の開始・終了
    local inc, src = RTL_InCombat()
    if (inc) then
        RTL.outSince = nil
        if (not RTL.pull) then
            RTL_StartPull(now, src)
        end
    elseif (RTL.pull) then
        RTL.outSince = RTL.outSince or now
        if (now - RTL.outSince >= RTL.settings.endSec * 1000) then
            RTL_EndPull(RTL.outSince, "end")
        end
    end
    -- 走査
    local scanSec = RTL.settings.scanSec
    if (not RTL.pull and RTL.entCount and RTL.entCount > RTL.settings.idleManyEnts) then
        scanSec = RTL.settings.idleScanSec
    end
    if (now - RTL.last.scan >= scanSec * 1000) then
        RTL.last.scan = now
        RTL_ScanEntities(now)
    end
    if (now - RTL.last.slow >= RTL.settings.slowSec * 1000) then
        RTL.last.slow = now
        RTL_ScanBuffs(now)
        RTL_ScanTethers(now)
    end
    -- 途中保存
    if (RTL.pull and now - RTL.pull.savedMs >= RTL.settings.autosaveSec * 1000) then
        RTL_SavePull(now, false)
    end
    if (not RTL.pull) then
        RTL_Prune(now)
    end
end

function RTL_Update(event, ticks)
    if (not RTL.initDone) then
        return
    end
    RTL_Safe("Update", RTL_Tick)
    RTL_Safe("TL", RTL_TL_Tick)
    RTL_Safe("UISave", RTL_UI_SaveTick, RTL_Now())
    RTL_Safe("PE", RTL_PE_Tick, RTL_Now())
end

-- =====================================================================
-- 画面の部品（v0.5.0）：テーマ（色・角丸・余白・背景の透明度・文字の大きさ）と部品を 1 か所にまとめる
--
--   色は daisyUI のダークテーマ（dark / night）に近いもの。背景の透明度は settings.uiAlpha（記録・ドライランの画面）と
--   settings.tvAlpha（タイムライン表示）、文字の大きさは settings.uiScale で変える
--   描き方：ImGui の PushStyleVar / PushStyleColor と、ウィンドウの描画リスト（GUI:AddRectFilled・AddText など。SpellTimer と同じ）
--   部品：RTL_UI_Window（ウィンドウ）・RTL_UI_Card（カード）・RTL_UI_Badge / RTL_UI_PillAt（バッジ）・RTL_UI_Bar / RTL_UI_BarAt（バー）・
--         RTL_UI_Button（ボタン。色・選択中）・RTL_UI_Toggle（チェック）・RTL_UI_Text / RTL_UI_Muted / RTL_UI_KV（文字）
--   決まり：GUI.StyleVar_* / GUI.Col_* / GUI.WindowFlags_* は、ある定数だけを使う（版によって無いものがあっても止まらない）。
--           積んだ（Push した）数だけ必ず戻す（Pop する）。部品の中身は pcall で包み、途中でエラーになっても積み残さない
-- =====================================================================

RTL.UI = {
    col = {
        base100 = { 0.114, 0.137, 0.165 },  -- ウィンドウの背景 #1D232A
        base200 = { 0.153, 0.180, 0.216 },  -- カード #272E37
        base300 = { 0.212, 0.247, 0.290 },  -- 枠・バーの下地・ボタン #363F4A
        hover   = { 0.270, 0.310, 0.360 },
        text    = { 0.870, 0.894, 0.925 },
        muted   = { 0.580, 0.620, 0.670 },
        primary = { 0.455, 0.510, 1.000 },  -- #7482FF
        onPrimary = { 0.050, 0.060, 0.150 },
        info    = { 0.290, 0.608, 0.941 },  -- #4A9BF0
        success = { 0.204, 0.773, 0.518 },  -- #34C584
        warning = { 0.961, 0.620, 0.231 },  -- #F59E3B
        error   = { 0.973, 0.443, 0.475 },  -- #F87179
        accent  = { 0.769, 0.659, 1.000 },  -- #C4A8FF（分岐）
        neutral = { 0.600, 0.640, 0.690 },
        own     = { 0.490, 0.769, 1.000 },  -- 自分のアクション #7DC4FF
    },
    rounding = { window = 12, child = 10, frame = 6, grab = 6, scrollbar = 8, card = 10 },
    pad      = { window = { 12, 10 }, frame = { 8, 4 }, item = { 8, 6 }, card = 10 },
}
RTL.ui = RTL.ui or {}
RTL.ui.cards = RTL.ui.cards or {}

-- 色：名前（RTL.UI.col のキー）か { r, g, b }
function RTL_UI_Rgb(tone)
    if (type(tone) == "table") then
        return tone
    end
    return RTL.UI.col[tone or "text"] or RTL.UI.col.text
end

function RTL_UI_U32(tone, a)
    local c = RTL_UI_Rgb(tone)
    return GUI:ColorConvertFloat4ToU32(c[1], c[2], c[3], a or 1)
end

-- "F59E3B" → { r, g, b }（読めなければ nil）
function RTL_UI_Hex(s)
    if (type(s) ~= "string") then
        return nil
    end
    local r, g, b = s:match("^#?(%x%x)(%x%x)(%x%x)$")
    if (not r) then
        return nil
    end
    return { tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255 }
end

function RTL_UI_ToHex(c)
    local function h(v)
        v = math.floor(math.max(0, math.min(1, tonumber(v) or 0)) * 255 + 0.5)
        return string.format("%02X", v)
    end
    return h(c[1])..h(c[2])..h(c[3])
end

-- ウィンドウのフラグ（ある定数だけを足す）
function RTL_UI_Flags(...)
    local f = 0
    for _, name in ipairs({ ... }) do
        local v = GUI["WindowFlags_"..name]
        if (type(v) == "number") then
            f = f + v
        end
    end
    return f
end

-- 設定を変えたら、少し待ってから settings.lua に書く（スライダーを動かしている間に毎フレーム書かないため）
function RTL_UI_SaveLater()
    RTL.ui.saveAt = RTL_Now() + 700
end

function RTL_UI_SaveTick(now)
    if (RTL.ui.saveAt and now >= RTL.ui.saveAt) then
        RTL.ui.saveAt = nil
        RTL_SaveSettings()
    end
end

-- テーマを積む。戻り値は（積んだ StyleVar の数, 積んだ Color の数）
function RTL_UI_PushTheme(alpha)
    local U = RTL.UI
    local C = U.col
    local a = tonumber(alpha) or 0.94
    local nv, nc = 0, 0
    local function var(k, x, y)
        local id = GUI["StyleVar_"..k]
        if (type(id) == "number") then
            if (y ~= nil) then
                GUI:PushStyleVar(id, x, y)
            else
                GUI:PushStyleVar(id, x)
            end
            nv = nv + 1
        end
    end
    local function col(k, c, ca)
        local id = GUI["Col_"..k]
        if (type(id) == "number") then
            GUI:PushStyleColor(id, c[1], c[2], c[3], ca or 1)
            nc = nc + 1
        end
    end
    var("WindowRounding", U.rounding.window)
    var("ChildWindowRounding", U.rounding.child)
    var("FrameRounding", U.rounding.frame)
    var("GrabRounding", U.rounding.grab)
    var("ScrollbarRounding", U.rounding.scrollbar)
    var("PopupRounding", U.rounding.frame)
    var("WindowPadding", U.pad.window[1], U.pad.window[2])
    var("FramePadding", U.pad.frame[1], U.pad.frame[2])
    var("ItemSpacing", U.pad.item[1], U.pad.item[2])
    var("WindowBorderSize", 1)
    var("FrameBorderSize", 0)
    col("WindowBg", C.base100, a)
    col("ChildWindowBg", C.base200, a)
    col("Border", C.base300, math.min(1, a + 0.05))
    col("BorderShadow", C.base100, 0)
    col("TitleBg", C.base100, a)
    col("TitleBgCollapsed", C.base100, a)
    col("TitleBgActive", C.base200, math.min(1, a + 0.04))
    col("MenuBarBg", C.base200, a)
    col("FrameBg", C.base300, 1)
    col("FrameBgHovered", C.hover, 1)
    col("FrameBgActive", C.hover, 1)
    col("Button", C.base300, 1)
    col("ButtonHovered", C.hover, 1)
    col("ButtonActive", C.primary, 1)
    col("CheckMark", C.primary, 1)
    col("SliderGrab", C.primary, 1)
    col("SliderGrabActive", C.accent, 1)
    col("Header", C.base300, 1)
    col("HeaderHovered", C.hover, 1)
    col("HeaderActive", C.hover, 1)
    col("Column", C.base300, 1)
    col("Text", C.text, 1)
    col("TextDisabled", C.muted, 1)
    col("ScrollbarBg", C.base100, 0)
    col("ScrollbarGrab", C.base300, 1)
    col("ScrollbarGrabHovered", C.hover, 1)
    col("ScrollbarGrabActive", C.primary, 1)
    col("ResizeGrip", C.base300, 0.5)
    col("ResizeGripHovered", C.hover, 0.8)
    col("ResizeGripActive", C.primary, 1)
    col("TooltipBg", C.base200, 0.97)
    col("TextSelectedBg", C.primary, 0.35)
    return nv, nc
end

function RTL_UI_PopTheme(nv, nc)
    if (nc and nc > 0) then GUI:PopStyleColor(nc) end
    if (nv and nv > 0) then GUI:PopStyleVar(nv) end
end

-- ウィンドウ：テーマを積む → Begin → 中身（RTL_Safe） → End → テーマを戻す
--   opt.alpha（背景の透明度）・opt.scale（文字の大きさ）・opt.where（エラーの場所）
function RTL_UI_Window(name, open, flags, bodyFn, opt)
    opt = opt or {}
    local nv, nc = RTL_UI_PushTheme(opt.alpha)
    local visible, newOpen
    if (flags and flags ~= 0) then
        visible, newOpen = GUI:Begin(name, open, flags)
    else
        visible, newOpen = GUI:Begin(name, open)
    end
    if (visible) then
        local sc = tonumber(opt.scale) or 1
        if (sc ~= 1) then
            GUI:SetWindowFontScale(sc)
        end
        RTL_Safe(opt.where or name, bodyFn)
    end
    GUI:End()
    RTL_UI_PopTheme(nv, nc)
    return visible, newOpen
end

-- ---------------------------------------------------------------------
-- 文字
-- ---------------------------------------------------------------------

function RTL_UI_Text(s, tone)
    local c = RTL_UI_Rgb(tone or "text")
    GUI:TextColored(c[1], c[2], c[3], 1, tostring(s))
end

function RTL_UI_Muted(s)
    RTL_UI_Text(s, "muted")
end

-- 見出し（カードの中の小さい見出し）
function RTL_UI_Title(s)
    RTL_UI_Text(s, "primary")
end

-- 「ラベル 値」を 1 行に（ラベルは薄い色）
function RTL_UI_KV(label, value, tone)
    RTL_UI_Muted(label)
    GUI:SameLine()
    RTL_UI_Text(value, tone)
end

-- 文字の幅（GUI:CalcTextSize は幅と高さの 2 つを返す。tonumber(GUI:CalcTextSize(s)) と書くと高さが基数として渡り、
--   幅が別の数に化ける（v0.5.0 の実機で、技名の後ろのバッジ・秒数が右にずれた原因）。必ずこれで 1 つ目だけを取る）
function RTL_UI_TextW(s)
    local w = GUI:CalcTextSize(tostring(s))
    return tonumber(w) or 0
end

-- 長い文字を幅に収める（UTF-8 の文字の途中で切らない）。毎フレーム測り直さないように、結果を覚えておく
function RTL_UI_Fit(text, maxW)
    text = tostring(text)
    local key = text.."\0"..math.floor(maxW).."\0"..tostring(RTL.settings.uiScale)
    local fc = RTL.ui.fit
    if (not fc or RTL.ui.fitN > 400) then
        fc = {}
        RTL.ui.fit, RTL.ui.fitN = fc, 0
    end
    local c = fc[key]
    if (c) then
        return c[1], c[2]
    end
    local s, w = RTL_UI_FitCalc(text, maxW)
    fc[key] = { s, w }
    RTL.ui.fitN = RTL.ui.fitN + 1
    return s, w
end

function RTL_UI_FitCalc(text, maxW)
    local tw = GUI:CalcTextSize(text)
    if (type(tw) ~= "number" or tw <= maxW) then
        return text, tw
    end
    local s = text
    while (#s > 0) do
        local i = #s
        while (i > 1) do
            local b = s:byte(i)
            if (b < 0x80 or b >= 0xC0) then break end
            i = i - 1
        end
        s = s:sub(1, i - 1)
        local w = GUI:CalcTextSize(s.."…")
        if (type(w) ~= "number" or w <= maxW) then
            return s.."…", w
        end
    end
    return "…", 0
end

-- ---------------------------------------------------------------------
-- バッジ・バー（描画リストに直接描く）
-- ---------------------------------------------------------------------

-- (x, y) にバッジを描いて幅を返す
function RTL_UI_PillAt(x, y, text, tone)
    local tw, th = GUI:CalcTextSize(text)
    tw, th = tonumber(tw) or 0, tonumber(th) or 0
    local px = 6
    local w = tw + px * 2
    GUI:AddRectFilled(x, y - 1, x + w, y + th + 1, RTL_UI_U32(tone, 0.20), (th + 2) * 0.5)
    GUI:AddText(x + px, y, RTL_UI_U32(tone, 1), text)
    return w
end

-- 文字の流れの中にバッジを置く（前の部品の横に置くときは、呼ぶ前に GUI:SameLine()）
function RTL_UI_Badge(text, tone)
    local x, y = GUI:GetCursorScreenPos()
    local w = RTL_UI_PillAt(x, y, text, tone)
    local _, th = GUI:CalcTextSize(text)
    GUI:Dummy(w, tonumber(th) or 0)
end

-- (x, y) から幅 w・高さ h のバー（frac = 0〜1）
function RTL_UI_BarAt(x, y, w, h, frac, tone)
    frac = math.max(0, math.min(1, tonumber(frac) or 0))
    local r = h * 0.5
    GUI:AddRectFilled(x, y, x + w, y + h, RTL_UI_U32("base300", 0.9), r)
    if (frac > 0) then
        local fx = x + math.max(h, w * frac)
        GUI:AddRectFilled(x, y, fx, y + h, RTL_UI_U32(tone, 0.95), r)
        GUI:AddRectFilled(x + 1, y + 1, fx - 1, y + h * 0.45, RTL_UI_U32({ 1, 1, 1 }, 0.16), r)
    end
end

function RTL_UI_Bar(frac, tone, w, h)
    local x, y = GUI:GetCursorScreenPos()
    w = w or GUI:GetContentRegionAvailWidth()
    h = h or 6
    RTL_UI_BarAt(x, y, w, h, frac, tone)
    GUI:Dummy(w, h)
end

-- ---------------------------------------------------------------------
-- ボタン・チェック
-- ---------------------------------------------------------------------

-- tone：nil（ふつう）／"primary" などの色（塗りつぶし）。selected = true なら primary
--   small = true なら SmallButton。w / h は Button のときだけ
function RTL_UI_Button(label, tone, small, w, h)
    local C = RTL.UI.col
    if (tone == true) then
        tone = "primary"
    end
    local n = 0
    local function col(k, c, a)
        local id = GUI["Col_"..k]
        if (type(id) == "number") then
            GUI:PushStyleColor(id, c[1], c[2], c[3], a or 1)
            n = n + 1
        end
    end
    if (tone) then
        local c = RTL_UI_Rgb(tone)
        col("Button", c, 0.90)
        col("ButtonHovered", c, 1.0)
        col("ButtonActive", c, 0.75)
        col("Text", C.onPrimary, 1)
    end
    local ok, pressed
    if (small) then
        ok, pressed = pcall(GUI.SmallButton, GUI, label)
    elseif (w) then
        ok, pressed = pcall(GUI.Button, GUI, label, w, h or 0)
    else
        ok, pressed = pcall(GUI.Button, GUI, label)
    end
    if (n > 0) then
        GUI:PopStyleColor(n)
    end
    if (not ok) then
        error(pressed, 0)
    end
    return pressed == true
end

-- 選んだものが塗りつぶしになるボタンの並び（items = { { value, label }, ... }）。押されたら value を返す
function RTL_UI_Segmented(id, items, current, small)
    local picked = nil
    for i, it in ipairs(items) do
        if (i > 1) then
            GUI:SameLine(0, 4)
        end
        if (RTL_UI_Button(tostring(it[2]).."##"..id..i, (it[1] == current) and "primary" or nil, small ~= false)) then
            picked = it[1]
        end
    end
    return picked
end

function RTL_UI_Toggle(label, v)
    local nv, pressed = GUI:Checkbox(label, v == true)
    return nv == true, pressed == true
end

-- ---------------------------------------------------------------------
-- カード：背景（角丸の四角）の上に中身を置く
--   ImGui では後から背景を敷けないので、前のフレームで測った高さで先に背景を描く（1 フレーム遅れるが、見た目は変わらない）
--   tone を渡すと枠がその色になる（エラーなど）
-- ---------------------------------------------------------------------
function RTL_UI_Card(id, bodyFn, tone)
    local U = RTL.UI
    local pad = U.pad.card
    local x, y = GUI:GetCursorScreenPos()
    local w = GUI:GetContentRegionAvailWidth()
    if (type(x) ~= "number" or type(w) ~= "number") then
        RTL_Safe("Card:"..id, bodyFn)
        return
    end
    local h = RTL.ui.cards[id]
    if (h and h > 0) then
        GUI:AddRectFilled(x, y, x + w, y + h, RTL_UI_U32("base200", 0.92), U.rounding.card)
        GUI:AddRect(x, y, x + w, y + h, RTL_UI_U32(tone or "base300", tone and 0.75 or 1), U.rounding.card)
    end
    local wx = GUI:GetWindowPos()
    local wrap = (type(wx) == "number") and (x + w - pad - wx) or nil
    GUI:SetCursorScreenPos(x + pad, y + pad)
    GUI:BeginGroup()
    if (wrap) then GUI:PushTextWrapPos(wrap) end
    RTL_Safe("Card:"..id, bodyFn)
    if (wrap) then GUI:PopTextWrapPos() end
    GUI:EndGroup()
    local _, maxY = GUI:GetItemRectMax()
    if (type(maxY) == "number") then
        RTL.ui.cards[id] = maxY - y + pad
        GUI:SetCursorScreenPos(x, y + RTL.ui.cards[id])
    end
    GUI:Dummy(w, 0)
end

-- =====================================================================
-- 画面
-- =====================================================================

function RTL_Draw(event, ticks)
    if (not RTL.window.open) then
        return
    end
    GUI:SetNextWindowSize(400, 300, GUI.SetCond_FirstUseEver)
    local wasOpen = RTL.window.open
    local _, open = RTL_UI_Window("RaidTimeline", RTL.window.open, nil, RTL_DrawBody,
        { alpha = RTL.settings.uiAlpha, scale = RTL.settings.uiScale, where = "Draw" })
    RTL.window.open = open
    if (wasOpen ~= RTL.window.open) then
        RTL_SaveSettings()
    end
end

function RTL_ResultTone(result)
    result = tostring(result or "")
    if (result == "clear") then return "success" end
    if (result == "wipe") then return "error" end
    return "neutral"
end

function RTL_DrawBody()
    local now = RTL_Now()
    local v, pressed = RTL_UI_Toggle("記録する (record)", RTL.settings.record)
    if (pressed) then
        RTL.settings.record = v
        RTL_SaveSettings()
    end
    local partyMapid = RTL_PartyInfo()
    RTL_UI_Card("rec_state", function()
        RTL_UI_KV("mapid", tostring(Player and Player.localmapid))
        GUI:SameLine()
        RTL_UI_KV("  party", tostring(partyMapid))
        RTL_UI_Muted("incombat")
        GUI:SameLine()
        local inc = (Player and Player.incombat) == true
        RTL_UI_Badge(tostring(Player and Player.incombat), inc and "warning" or "neutral")
        GUI:SameLine()
        RTL_UI_Muted("  Argus")
        GUI:SameLine()
        RTL_UI_Badge(RTL.api.registered and "OK" or "未登録", RTL.api.registered and "success" or "error")
    end)
    local p = RTL.pull
    RTL_UI_Card("rec_pull", function()
        if (p) then
            RTL_UI_Badge("記録中", "error")
            GUI:SameLine()
            RTL_UI_Text(string.format("%.1f 秒", (now - p.startMs) / 1000))
            GUI:SameLine()
            RTL_UI_Muted(p.stamp..".csv")
            local c = p.counts
            RTL_UI_Muted(string.format("詠唱 %d / 完了 %d / HP %d / バフ %d / マーカー %d / 線 %d / MapEffect %d",
                c.cast_start or 0, c.cast_end or 0, c.hp or 0, (c.buff_gain or 0) + (c.buff_lose or 0),
                c.marker or 0, c.tether or 0, c.map_effect or 0))
            if (p.firstActMs) then
                RTL_UI_Text(string.format("%s -> combat_start = %+d ms", tostring(p.t0Kind or "first_action"), p.startMs - p.firstActMs))
            else
                RTL_UI_Text("first_action: なし（first_hit か combat_start を基準にします）", "warning")
            end
            if (RTL_UI_Button("今すぐ保存", "primary", false, 120, 0)) then
                RTL_SavePull(now, false)
            end
        else
            RTL_UI_Badge("待機中", "neutral")
            GUI:SameLine()
            RTL_UI_Muted("戦闘が始まると記録します")
            RTL_UI_KV("追跡中の敵", tostring(RTL_Count(RTL.ents)))
            if (RTL.firstHitMs) then
                RTL_UI_Text(string.format("first_hit 検出済み（%.1f 秒前）", (now - RTL.firstHitMs) / 1000), "info")
            end
        end
    end)
    local lp = RTL.lastPull
    if (lp) then
        RTL_UI_Card("rec_last", function()
            RTL_UI_Muted("前回")
            GUI:SameLine()
            RTL_UI_Text(tostring(lp.file))
            GUI:SameLine()
            RTL_UI_Badge(tostring(lp.result), RTL_ResultTone(lp.result))
            if (lp.offsetMs) then
                RTL_UI_Muted(string.format("%s -> combat_start = %+d ms", tostring(lp.t0src), lp.offsetMs))
            end
        end)
    end
    local hit, miss = RTL.api.counts.actionNameHit or 0, RTL.api.counts.actionNameMiss or 0
    RTL_UI_Card("rec_names", function()
        RTL_UI_Muted("名前辞書")
        GUI:SameLine()
        RTL_UI_Text(string.format("アクション %d / 敵 %d / バフ %d", RTL_Count(RTL.names.actions or {}),
            RTL_Count(RTL.names.npcs or {}), RTL_Count(RTL.names.buffs or {})))
        RTL_UI_Muted(string.format("名前取得 成功 %d・失敗 %d", hit, miss))
    end)
    if (RTL.lastError) then
        RTL_UI_Card("rec_err", function()
            RTL_UI_Text("エラー: "..RTL.lastError, "error")
        end, "error")
    end
end

-- =====================================================================
-- タイムライン・プランの読み込み（Lua の表として「読む」だけ。実行しない）
--
--   ファイルは他人が書いたものを受け取ることがある。MMOminion の Lua では setfenv が使えず、
--   実行すると中に書かれたコードが何でも動いてしまうので、return { ... } の表だけを自前で解釈する。
--   読めるもの：数値（10 進・16 進・小数・指数・マイナス）、文字列（"..." '...' [[...]]）、
--               true / false / nil、表（[キー] = 値、名前 = 値、並べた値。区切りは , か ;）、コメント
--   それ以外（変数・関数呼び出し・演算・local など）が 1 つでもあれば、ファイル全体を読み込まない
-- =====================================================================

RTL.LT_MAX_DEPTH = 40
RTL.LT_MAX_BYTES = 2 * 1024 * 1024

-- 読めないところで止める（何行目かを付ける）
function RTL_LT_Fail(P, msg)
    local line = 1
    for _ in P.s:sub(1, P.i - 1):gmatch("\n") do
        line = line + 1
    end
    error({ rtlParse = true, msg = line.." 行目: "..msg }, 0)
end

-- 空白とコメントを飛ばす
function RTL_LT_Skip(P)
    local s = P.s
    while (true) do
        local i = s:find("[^ \t\r\n\f\v]", P.i)
        if (not i) then
            P.i = #s + 1
            return
        end
        P.i = i
        if (s:sub(i, i + 1) ~= "--") then
            return
        end
        local eq = s:match("^%[(=*)%[", i + 2)
        if (eq) then
            local close = "]"..eq.."]"
            local e = s:find(close, i + 4 + #eq, true)
            if (not e) then
                RTL_LT_Fail(P, "コメント --[[ が閉じていません")
            end
            P.i = e + #close
        else
            local e = s:find("\n", i + 2, true)
            P.i = e and (e + 1) or (#s + 1)
        end
    end
end

RTL.LT_ESC = { a = "\a", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", v = "\v",
               ["\\"] = "\\", ['"'] = '"', ["'"] = "'", ["\n"] = "\n", ["\r"] = "\n" }

function RTL_LT_String(P)
    local s = P.s
    local q = s:sub(P.i, P.i)
    local i = P.i + 1
    local out = {}
    local cls = "[\\\r\n"..q.."]"
    while (true) do
        local j = s:find(cls, i)
        if (not j) then
            RTL_LT_Fail(P, "文字列が閉じていません")
        end
        out[#out + 1] = s:sub(i, j - 1)
        local c = s:sub(j, j)
        if (c == q) then
            P.i = j + 1
            return table.concat(out)
        end
        if (c == "\r" or c == "\n") then
            P.i = j
            RTL_LT_Fail(P, "文字列の途中で改行しています")
        end
        local e = s:sub(j + 1, j + 1)
        if (RTL.LT_ESC[e]) then
            out[#out + 1] = RTL.LT_ESC[e]
            i = j + 2
            if (e == "\r" and s:sub(i, i) == "\n") then
                i = i + 1
            end
        elseif (e:match("%d")) then
            local d = s:match("^%d%d?%d?", j + 1)
            local n = tonumber(d)
            if (n > 255) then
                P.i = j
                RTL_LT_Fail(P, "文字コードが大きすぎます \\"..d)
            end
            out[#out + 1] = string.char(n)
            i = j + 1 + #d
        elseif (e == "x") then
            local h = s:match("^%x%x", j + 2)
            if (not h) then
                P.i = j
                RTL_LT_Fail(P, "\\x の後ろは 16 進 2 桁")
            end
            out[#out + 1] = string.char(tonumber(h, 16))
            i = j + 4
        elseif (e == "z") then
            i = s:find("[^ \t\r\n\f\v]", j + 2) or (#s + 1)
        else
            P.i = j
            RTL_LT_Fail(P, "使えないエスケープ \\"..e)
        end
    end
end

function RTL_LT_LongString(P)
    local s = P.s
    local eq = s:match("^%[(=*)%[", P.i)
    local start = P.i + #eq + 2
    if (s:sub(start, start + 1) == "\r\n") then
        start = start + 2
    elseif (s:sub(start, start) == "\n" or s:sub(start, start) == "\r") then
        start = start + 1
    end
    local close = "]"..eq.."]"
    local e = s:find(close, start, true)
    if (not e) then
        RTL_LT_Fail(P, "文字列 [[ が閉じていません")
    end
    P.i = e + #close
    return s:sub(start, e - 1)
end

function RTL_LT_Number(P, neg)
    local s, i = P.s, P.i
    local m = s:match("^0[xX]%x+", i)
        or s:match("^%d+%.?%d*[eE][%+%-]?%d+", i)
        or s:match("^%.%d+[eE][%+%-]?%d+", i)
        or s:match("^%d+%.?%d*", i)
        or s:match("^%.%d+", i)
    if (not m) then
        RTL_LT_Fail(P, "数値が読めません")
    end
    local nx = s:sub(i + #m, i + #m)
    if (nx ~= "" and nx:match("[%w_%.]")) then
        RTL_LT_Fail(P, "数値が読めません")
    end
    local v = tonumber(m)
    if (v == nil) then
        RTL_LT_Fail(P, "数値が読めません")
    end
    P.i = i + #m
    if (neg) then
        return -v
    end
    return v
end

-- 値を 1 つ読む。nil は RTL.LT_NIL を返す（表の位置を数えるため）
RTL.LT_NIL = RTL.LT_NIL or {}

function RTL_LT_Value(P, depth)
    RTL_LT_Skip(P)
    local s, i = P.s, P.i
    local c = s:sub(i, i)
    if (c == "") then
        RTL_LT_Fail(P, "ファイルが途中で終わっています")
    end
    if (c == "{") then
        return RTL_LT_Table(P, depth + 1)
    end
    if (c == '"' or c == "'") then
        return RTL_LT_String(P)
    end
    if (c == "[" and s:match("^%[=*%[", i)) then
        return RTL_LT_LongString(P)
    end
    if (c == "-") then
        P.i = i + 1
        RTL_LT_Skip(P)
        local c2 = s:sub(P.i, P.i)
        if (c2 ~= "" and c2:match("[%d%.]")) then
            return RTL_LT_Number(P, true)
        end
        RTL_LT_Fail(P, "「-」の後ろには数値だけ書けます")
    end
    if (c:match("[%d%.]")) then
        return RTL_LT_Number(P, false)
    end
    local w = s:match("^[%a_][%w_]*", i)
    if (w == "true") then
        P.i = i + 4
        return true
    elseif (w == "false") then
        P.i = i + 5
        return false
    elseif (w == "nil") then
        P.i = i + 3
        return RTL.LT_NIL
    elseif (w) then
        RTL_LT_Fail(P, "「"..w.."」は読めません（変数・関数呼び出し・式は使えません）")
    end
    RTL_LT_Fail(P, "読めない文字「"..c.."」")
end

function RTL_LT_Expect(P, ch, what)
    RTL_LT_Skip(P)
    if (P.s:sub(P.i, P.i) ~= ch) then
        RTL_LT_Fail(P, what)
    end
    P.i = P.i + 1
end

function RTL_LT_Table(P, depth)
    if (depth > RTL.LT_MAX_DEPTH) then
        RTL_LT_Fail(P, "表の入れ子が深すぎます")
    end
    P.i = P.i + 1   -- {
    local t, n = {}, 0
    while (true) do
        RTL_LT_Skip(P)
        local s, i = P.s, P.i
        local c = s:sub(i, i)
        if (c == "}") then
            P.i = i + 1
            return t
        end
        if (c == "") then
            RTL_LT_Fail(P, "「}」がありません")
        end
        local key, haskey = nil, false
        if (c == "[" and not s:match("^%[=*%[", i)) then
            P.i = i + 1
            key = RTL_LT_Value(P, depth)
            if (type(key) ~= "number" and type(key) ~= "string") then
                RTL_LT_Fail(P, "キーには数値か文字列だけ使えます")
            end
            if (key ~= key) then
                RTL_LT_Fail(P, "キーが数値ではありません")
            end
            RTL_LT_Expect(P, "]", "「]」がありません")
            RTL_LT_Expect(P, "=", "「=」がありません")
            haskey = true
        else
            local w = s:match("^[%a_][%w_]*", i)
            if (w and w ~= "true" and w ~= "false" and w ~= "nil") then
                local k = s:find("[^ \t\r\n\f\v]", i + #w)
                if (k and s:sub(k, k) == "=" and s:sub(k + 1, k + 1) ~= "=") then
                    key, haskey = w, true
                    P.i = k + 1
                end
            end
        end
        local val = RTL_LT_Value(P, depth)
        if (haskey) then
            if (val ~= RTL.LT_NIL) then
                t[key] = val
            end
        else
            n = n + 1
            if (val ~= RTL.LT_NIL) then
                t[n] = val
            end
        end
        RTL_LT_Skip(P)
        c = P.s:sub(P.i, P.i)
        if (c == "," or c == ";") then
            P.i = P.i + 1
        elseif (c ~= "}") then
            RTL_LT_Fail(P, "「,」か「}」が必要です")
        end
    end
end

-- 文字列 → 表。失敗したら nil, メッセージ
function RTL_LT_ParseText(s)
    if (type(s) ~= "string") then
        return nil, "ファイルが読めません"
    end
    if (s:sub(1, 3) == "\239\187\191") then
        s = s:sub(4)
    end
    if (#s > RTL.LT_MAX_BYTES) then
        return nil, "ファイルが大きすぎます"
    end
    local P = { s = s, i = 1 }
    local ok, res = pcall(function()
        RTL_LT_Skip(P)
        if (not s:match("^return[^%w_]", P.i)) then
            RTL_LT_Fail(P, "ファイルは return { ... } で始めてください")
        end
        P.i = P.i + 6
        local v = RTL_LT_Value(P, 0)
        if (type(v) ~= "table" or v == RTL.LT_NIL) then
            RTL_LT_Fail(P, "return の後ろには表 { ... } だけ書けます")
        end
        RTL_LT_Skip(P)
        if (s:sub(P.i, P.i) == ";") then
            P.i = P.i + 1
            RTL_LT_Skip(P)
        end
        if (P.i <= #s) then
            RTL_LT_Fail(P, "表の後ろに余計なものがあります")
        end
        return v
    end)
    if (ok) then
        return res
    end
    if (type(res) == "table" and res.rtlParse) then
        return nil, res.msg
    end
    return nil, tostring(res)
end

function RTL_LT_ParseFile(path)
    local s = RTL_ReadFile(path)
    if (not s) then
        return nil, "ファイルがありません"
    end
    return RTL_LT_ParseText(s)
end

-- =====================================================================
-- ドライラン：タイムライン読み込み・フェーズ判定・時計と同期点・イベントの照合
--
--   アクションは使わない。プランの各エントリについて「実行時刻＝イベント予定時刻（ref = start / hit）＋ offset」
--   を計算し、その時刻に設計書 3.1 の 1〜5 の判定結果だけを画面とログ（logs/<mapid>/<日時>_dryrun.csv）に出す。
--
--   戦闘開始（t0）：first_hostile → first_action → first_hit → combat_start（仕様 0 章。記録モードと同じ順。v0.4.0）
--   詠唱の照合・cast_start トリガー・同期点：contentid ＋ アクションID だけで見る（仕様 2.4）
--   nth：戦闘開始から、同じ contentid がそのアクションを詠唱した回数（1 体ずつ数える）
--   同じフェーズには 1 プルで 1 回だけ入る。新しいフェーズに入ったら、前のフェーズの残りのエントリは打ち切る
--   全滅・戦闘終了（2 秒続けて誰も戦闘中でない）でリセット
-- =====================================================================

RTL.tl = {
    mapid     = nil,     -- 読み込んだときの mapid
    job       = nil,
    cands     = {},      -- 読み込んだタイムラインの候補
    files     = {},      -- timelines/<mapid>_*.lua の一覧
    listVia   = nil,     -- 一覧の取り方（FolderList / dir）
    file      = nil,     -- 読み込んだタイムラインのファイル名
    timeline  = nil,
    tlErr     = nil,
    tlWarn    = {},
    plan      = nil,
    planFile  = nil,
    planErr   = nil,
    planWarn  = {},
    entityCid = {},      -- entities のキー → contentid
    cidSet    = {},      -- 見る contentid
    events    = {},      -- イベント ID → { ev, phase }
    pull      = nil,
    outSince  = nil,
    partyAct  = nil,
    selfUse   = {},      -- 自分のアクション → 最後に使った時刻（ms）
    preCasts  = {},      -- 戦闘開始前の数秒の詠唱（cidSet のものだけ）
    cidOf     = {},      -- entity_id → contentid（詠唱のたびに引かないように）
    tgState   = {},      -- [entity_id] = ターゲット可否（targetable トリガー用）
    hpLast    = {},      -- [entity_id] = 直前の HP（first_hit 用）
    preDropMs = nil,     -- 戦闘開始前に見た最初の HP 減少
    last      = { scan = 0, party = 0, save = 0 },
    lastPull  = nil,     -- 前回のプルのまとめ（画面用）
    recent    = {},      -- 画面の「直近の結果」
    actionNames = {},    -- 自分のアクション名のキャッシュ
}

RTL.TL = {
    format       = 1,
    scanSec      = 0.10,   -- 戦闘中の走査（HP・ターゲット可否）
    idleScanSec  = 0.50,   -- 戦闘外の走査
    autosaveSec  = 30,
    momentSec    = 1.0,    -- 同じ contentid・同じアクションの詠唱を 1 つの「瞬間」とみなす幅
    preCastSec   = 3.0,    -- 戦闘開始前の詠唱を何秒分とっておくか
    tolerance    = 5.0,    -- 照合の既定の許容（秒）
    syncWindow   = 10.0,
    entryWindow  = 3.0,    -- エントリの window の既定
    recentSec    = 10.0,   -- recentSec の既定
    recentRows   = 8,      -- 画面に出す直近の結果の数
    openSec      = 30.0,   -- 始まりの敵：戦闘開始のフェーズで、最初の詠唱から何秒までに詠唱する敵か（v0.6.9）
    handoffLeadSec = 1.3,  -- 引き継ぎ：HP が初めて減った時刻の何秒前を t0 にするか（記録ログ：最初の攻撃から HP が減るまで 1.2〜1.4 秒）
    positions    = { "MT", "ST", "H1", "H2", "D1", "D2", "D3", "D4" },
    COLUMNS      = "t,clock,phase,kind,ref,action,planned,actual,diff,result,detail",
}

-- ジョブ ID → 略称（Player.job）
RTL.TL_JOBS = {
    [1] = "GLA", [2] = "PGL", [3] = "MRD", [4] = "LNC", [5] = "ARC", [6] = "CNJ", [7] = "THM",
    [19] = "PLD", [20] = "MNK", [21] = "WAR", [22] = "DRG", [23] = "BRD", [24] = "WHM", [25] = "BLM",
    [26] = "ACN", [27] = "SMN", [28] = "SCH", [29] = "ROG", [30] = "NIN", [31] = "MCH", [32] = "DRK",
    [33] = "AST", [34] = "SAM", [35] = "RDM", [36] = "BLU", [37] = "GNB", [38] = "DNC", [39] = "RPR",
    [40] = "SGE", [41] = "VPR", [42] = "PCT",
}

function RTL_TL_Enabled()
    return RTL.settings.dryrun ~= false
end

function RTL_TL_JobName()
    local j = Player and Player.job
    return RTL.TL_JOBS[j or -1] or ("JOB"..tostring(j))
end

-- =====================================================================
-- 読み込み
-- =====================================================================

-- timelines/<mapid>_*.lua の一覧（FolderList があれば使い、無ければ dir /b）
function RTL_TL_ListTimelines(mapid)
    local dir = RTL.path.."\\timelines"
    local prefix = tostring(mapid).."_"
    local names, seen = {}, {}
    local function add(p)
        if (type(p) ~= "string") then return end
        local base = p:match("([^\\/]+)$") or p
        if (base:sub(1, #prefix) == prefix and base:match("^[%w_%-]+%.lua$") and not seen[base]) then
            seen[base] = true
            names[#names + 1] = base
        end
    end
    local via = nil
    if (type(FolderList) == "function") then
        local ok, list = pcall(FolderList, dir, prefix..".*%.lua", false)
        if (ok and type(list) == "table") then
            for _, p in pairs(list) do add(p) end
            if (#names > 0) then
                via = "FolderList"
            end
        end
    end
    -- FolderList が無い・1 件も返さないときは dir /b（引数の形が分からないため、両方試す）
    if (not via and FolderExists and FolderExists(dir) and io.popen) then
        local ok, f = pcall(io.popen, 'dir /b /a-d "'..dir..'\\'..prefix..'*.lua" 2>nul')
        if (ok and f) then
            via = "dir"
            for line in f:lines() do add((line:gsub("[\r\n]", ""))) end
            f:close()
        end
    end
    table.sort(names)
    RTL.tl.listVia = via
    return names
end

function RTL_TL_IsNumList(v)
    if (type(v) == "number") then return true end
    if (type(v) ~= "table") then return false end
    local n = 0
    for _, x in pairs(v) do
        if (type(x) ~= "number") then return false end
        n = n + 1
    end
    return n > 0
end

function RTL_TL_ActionSet(v)
    local set = {}
    if (type(v) == "number") then
        set[v] = true
    elseif (type(v) == "table") then
        for _, x in pairs(v) do set[x] = true end
    end
    return set
end

RTL.TL_TRIGGERS = { combat_start = true, cast_start = true, hp_below = true, targetable = true }

-- タイムラインを調べて、実行時に使う形に直す。致命的な誤りがあれば nil, メッセージ
function RTL_TL_Prepare(tl, mapid)
    local warn = {}
    if (tl.format ~= RTL.TL.format) then
        return nil, "format が "..tostring(tl.format).."（このアドオンは "..RTL.TL.format.." だけ読めます）"
    end
    if (type(tl.meta) ~= "table" or type(tl.meta.mapid) ~= "number") then
        return nil, "meta.mapid がありません"
    end
    if (tl.meta.mapid ~= mapid) then
        return nil, "meta.mapid ("..tl.meta.mapid..") が今のマップ ("..tostring(mapid)..") と違います"
    end
    if (type(tl.entities) ~= "table") then
        return nil, "entities がありません"
    end
    local entityCid, cidSet = {}, {}
    for key, e in pairs(tl.entities) do
        if (type(e) ~= "table" or type(e.contentid) ~= "number") then
            return nil, "entities."..tostring(key).." に contentid がありません"
        end
        entityCid[key] = e.contentid
        cidSet[e.contentid] = true
    end
    if (type(tl.phases) ~= "table" or #tl.phases == 0) then
        return nil, "phases がありません"
    end
    local events, phaseIds = {}, {}
    local function checkTrigger(tr, where)
        if (type(tr) ~= "table" or type(tr.type) ~= "string") then
            return where.." の type がありません"
        end
        if (tr.entity ~= nil and not entityCid[tr.entity]) then
            return where.." の entity「"..tostring(tr.entity).."」が entities にありません"
        end
        if (tr.type == "cast_start" and (not tr.entity or not RTL_TL_IsNumList(tr.action))) then
            return where.." の cast_start には entity と action が必要です"
        end
        if (tr.type == "hp_below" and (not tr.entity or (type(tr.percent) ~= "number" and type(tr.value) ~= "number"))) then
            return where.." の hp_below には entity と percent（または value）が必要です"
        end
        if (tr.type == "targetable" and not tr.entity) then
            return where.." の targetable には entity が必要です"
        end
        if (not RTL.TL_TRIGGERS[tr.type]) then
            warn[#warn + 1] = where.." の type「"..tr.type.."」にはまだ対応していません（無視します）"
        end
        return nil
    end
    for pi, ph in ipairs(tl.phases) do
        if (type(ph) ~= "table" or type(ph.id) ~= "string") then
            return nil, "phases["..pi.."] に id がありません"
        end
        if (phaseIds[ph.id]) then
            return nil, "フェーズ ID「"..ph.id.."」が重複しています"
        end
        phaseIds[ph.id] = true
        local err = checkTrigger(ph.trigger, ph.id..".trigger")
        if (err) then return nil, err end
        ph.trigger.actionSet = RTL_TL_ActionSet(ph.trigger.action)
        ph.events = ph.events or {}
        ph.syncs = ph.syncs or {}
        for ei, ev in ipairs(ph.events) do
            if (type(ev) ~= "table" or type(ev.id) ~= "string" or type(ev.t) ~= "number") then
                return nil, ph.id..".events["..ei.."] に id か t がありません"
            end
            if (events[ev.id]) then
                return nil, "イベント ID「"..ev.id.."」が重複しています"
            end
            if (ev.match ~= nil) then
                if (type(ev.match) ~= "table" or not entityCid[ev.match.entity] or not RTL_TL_IsNumList(ev.match.action)) then
                    return nil, "イベント「"..ev.id.."」の match が正しくありません"
                end
                ev.match.cid = entityCid[ev.match.entity]
                ev.match.actionSet = RTL_TL_ActionSet(ev.match.action)
            end
            ev.cast = (type(ev.cast) == "number") and ev.cast or 0
            ev.tolerance = (type(ev.tolerance) == "number") and ev.tolerance or RTL.TL.tolerance
            events[ev.id] = { ev = ev, phase = ph }
        end
        for si, sy in ipairs(ph.syncs) do
            if (type(sy) ~= "table" or type(sy.t) ~= "number") then
                return nil, ph.id..".syncs["..si.."] に t がありません"
            end
            local err2 = checkTrigger(sy.on, ph.id..".syncs["..si.."].on")
            if (err2) then return nil, err2 end
            if (sy.on.type ~= "cast_start") then
                warn[#warn + 1] = ph.id..".syncs["..si.."] は cast_start 以外なので使いません"
            end
            sy.on.actionSet = RTL_TL_ActionSet(sy.on.action)
            sy.window = (type(sy.window) == "number") and sy.window or RTL.TL.syncWindow
        end
    end
    if (type(tl.actions) ~= "table") then
        tl.actions = {}
    end
    return { entityCid = entityCid, cidSet = cidSet, events = events, warn = warn }
end

-- timelines/<mapid>_*.lua をすべて読んでおく（ダンジョンなど 1 つのマップに複数のボスがいるため）。
--   使うのは 1 つ：ボタンで選んだもの、選んでいなければ戦闘開始のときに、entities の敵が
--   ターゲット可能・攻撃可能でそこにいる最初のもの（RTL_TL_AutoPick）
function RTL_TL_LoadTimeline(mapid, fileName)
    local T = RTL.tl
    T.timeline, T.file, T.tlErr, T.tlWarn = nil, nil, nil, {}
    T.entityCid, T.cidSet, T.events = {}, {}, {}
    T.cands, T.manualPick = {}, (fileName ~= nil)
    T.files = RTL_TL_ListTimelines(mapid)
    local first = nil
    for _, f in ipairs(T.files) do
        local c = { file = f }
        local tl, err = RTL_LT_ParseFile(RTL.path.."\\timelines\\"..f)
        if (tl) then
            local prep, perr = RTL_TL_Prepare(tl, mapid)
            if (prep) then
                c.tl, c.prep = tl, prep
                for cid in pairs(prep.cidSet) do T.cidSet[cid] = true end
                first = first or c
            else
                c.err = perr
            end
        else
            c.err = err
        end
        if (c.err) then
            RTL_Msg("timeline "..f..": "..tostring(c.err))
        end
        T.cands[#T.cands + 1] = c
    end
    RTL_Msg("timelines for map "..tostring(mapid)..": "..#T.files.." file(s) via "..tostring(T.listVia))
    local pick = first
    for _, c in ipairs(T.cands) do
        if (fileName and c.file == fileName) then pick = c end
    end
    if (pick) then
        RTL_TL_UseTimeline(pick)
    elseif (#T.cands > 0) then
        T.file, T.tlErr = T.cands[1].file, T.cands[1].err
    end
end

-- 候補の 1 つを使うタイムラインにする（読み込み済みのものを切り替えるだけ）
function RTL_TL_UseTimeline(c)
    local T = RTL.tl
    T.file = c.file
    if (not c.tl) then
        T.timeline, T.tlErr = nil, c.err
        return
    end
    T.timeline, T.tlErr = c.tl, nil
    T.entityCid, T.events, T.tlWarn = c.prep.entityCid, c.prep.events, c.prep.warn
    RTL_Msg("timeline: "..c.file.."  phases="..#c.tl.phases)
end

-- 戦闘が始まったとき：タイムラインの敵（entities のどれか）が、ターゲット可能・攻撃可能でそこにいるか。
--   いれば true（ボタンで選んでいなければ、いる敵のタイムラインに切り替える）。
--   いなければ false（ダンジョンの道中など。ドライランしない）
function RTL_TL_Present(c)
    for _, cid in pairs(c.prep.entityCid) do
        local el = EntityList("contentid="..cid)
        if (el) then
            for _, e in pairs(el) do
                if (e.targetable and e.attackable) then
                    return true
                end
            end
        end
    end
    return false
end

-- 始まりの敵（v0.6.9）：戦闘開始のフェーズで、最初の詠唱から openSec 秒までに詠唱する敵の contentid。
--   詠唱が 1 つも無ければ entities の全部
function RTL_TL_OpeningCids(c)
    if (c.openCids) then
        return c.openCids
    end
    local set, minT = {}, nil
    for _, ph in ipairs(c.tl.phases) do
        if (ph.trigger.type == "combat_start") then
            for _, ev in ipairs(ph.events) do
                if (ev.match and ev.match.cid and (minT == nil or ev.t < minT)) then minT = ev.t end
            end
        end
    end
    if (minT) then
        for _, ph in ipairs(c.tl.phases) do
            if (ph.trigger.type == "combat_start") then
                for _, ev in ipairs(ph.events) do
                    if (ev.match and ev.match.cid and ev.t <= minT + RTL.TL.openSec) then set[ev.match.cid] = true end
                end
            end
        end
    end
    if (next(set) == nil) then
        for _, cid in pairs(c.prep.entityCid) do set[cid] = true end
    end
    c.openCids = set
    return set
end

-- 戦闘開始のときにパーティが攻撃している敵の contentid（v0.6.9）：最初の敵対アクションの対象・HP が減った敵・自分のターゲット
function RTL_TL_EngagedCids(now)
    local T = RTL.tl
    local set = {}
    local h = RTL_FirstHostile(now)
    if (h and h.hcid) then set[h.hcid] = true end
    if (T.preDropCid and T.preDropMs and now - T.preDropMs <= 5000) then set[T.preDropCid] = true end
    local t = nil
    pcall(function() t = Player:GetTarget() end)
    if (type(t) == "table" and t.attackable and type(t.contentid) == "number") then set[t.contentid] = true end
    return set
end

-- 始まりの敵が、ターゲット可能・攻撃可能でそこにいるか
function RTL_TL_OpeningPresent(c)
    for cid in pairs(RTL_TL_OpeningCids(c)) do
        local el = EntityList("contentid="..cid)
        if (el) then
            for _, e in pairs(el) do
                if (e.targetable and e.attackable) then
                    return true
                end
            end
        end
    end
    return false
end

-- 戦闘開始のとき、使うタイムラインを決める（v0.6.9）。
--   1. 攻撃している敵が始まりの敵のタイムライン（今のもの → ほか）
--   2. 始まりの敵がいるタイムライン（今のもの → ほか。ボタンで選んだときは今のものだけ）
--   3. entities の敵がいるタイムライン（v0.6.8 までと同じ）
function RTL_TL_PickForCombat(now)
    local T = RTL.tl
    now = now or RTL_Now()
    local curc = nil
    for _, c in ipairs(T.cands) do
        if (c.tl and c.file == T.file) then curc = c end
    end
    local function use(c)
        if (c ~= curc) then
            RTL_TL_UseTimeline(c)
            RTL_TL_LoadPlan()
        end
        return true
    end
    local eng = RTL_TL_EngagedCids(now)
    local function engaged(c)
        for cid in pairs(RTL_TL_OpeningCids(c)) do
            if (eng[cid]) then return true end
        end
        return false
    end
    if (curc and engaged(curc)) then return true end
    for _, c in ipairs(T.cands) do
        if (c.tl and c ~= curc and engaged(c)) then return use(c) end
    end
    if (curc and RTL_TL_OpeningPresent(curc)) then return true end
    if (not T.manualPick) then
        for _, c in ipairs(T.cands) do
            if (c.tl and c ~= curc and RTL_TL_OpeningPresent(c)) then return use(c) end
        end
    end
    if (curc and RTL_TL_Present(curc)) then
        return true
    end
    if (T.manualPick) then
        return false
    end
    for _, c in ipairs(T.cands) do
        if (c.tl and c ~= curc and RTL_TL_Present(c)) then return use(c) end
    end
    return false
end

-- 引き継ぎ先（v0.6.9）：HP が初めて減った敵（cid）が、ほかのタイムラインの始まりの敵で、今のタイムラインの始まりの敵ではない
function RTL_TL_HandoffTarget(cid)
    local T = RTL.tl
    local pull = T.pull
    if (not pull or #T.cands < 2) then
        return nil
    end
    local curc = nil
    for _, c in ipairs(T.cands) do
        if (c.tl and c.file == T.file) then curc = c end
    end
    if (not curc or RTL_TL_OpeningCids(curc)[cid]) then
        return nil
    end
    for _, c in ipairs(T.cands) do
        if (c.tl and c ~= curc and not (pull.chain and pull.chain[c.file]) and RTL_TL_OpeningCids(c)[cid]) then
            return c
        end
    end
    return nil
end

-- 戦闘の途中でタイムラインを引き継ぐ（v0.6.9。前半から後半へ続けて進んだとき）：
--   今のプルを「引き継ぎ」で終え、そのタイムラインとプランで新しいプルを始める（t0 = HP が減った時刻 − handoffLeadSec）
function RTL_TL_Handoff(c, ms, why)
    local T = RTL.tl
    local old = T.pull
    local chain = {}
    for f in pairs(old.chain or {}) do chain[f] = true end
    chain[T.file] = true
    local n = (old.part or 1) + 1
    local base = old.baseStamp or old.stamp
    local hitIds = old.hitIds
    RTL_TL_Row("handoff", { ms = ms, ref = c.file, result = "handoff", detail = why })
    RTL_TL_Recent(string.format("[%s] %s に引き継ぎ（%s）", RTL_TL_FmtT(ms), c.file, why))
    RTL_TL_EndPull(ms, "handoff")
    RTL_TL_UseTimeline(c)
    RTL_TL_LoadPlan()
    RTL_TL_StartPull(ms, { t0Ms = ms - RTL.TL.handoffLeadSec * 1000, t0src = "handoff",
        stamp = base.."_"..n, baseStamp = base, part = n, chain = chain, hitIds = hitIds })
    RTL_Msg("timeline handoff -> "..c.file.."  ("..why..")")
end

function RTL_TL_LoadPlan()
    local T = RTL.tl
    T.plan, T.planFile, T.planErr, T.planWarn = nil, nil, nil, {}
    T.planSounds = 0
    RTL.snd.files = {}           -- wav の有無を見直す
    if (not T.timeline) then
        return
    end
    local mapid = T.timeline.meta.mapid
    local job = RTL_TL_JobName()
    local tries = {}
    if (RTL.settings.position) then
        tries[#tries + 1] = job.."_"..RTL.settings.position..".lua"
    end
    tries[#tries + 1] = job.."_ANY.lua"
    local dir = RTL.path.."\\plans\\"..tostring(mapid).."\\"
    for _, name in ipairs(tries) do
        local s = RTL_ReadFile(dir..name)
        if (s) then
            T.planFile = name
            local plan, err = RTL_LT_ParseText(s)
            if (not plan) then
                T.planErr = err
                return
            end
            if (plan.format ~= RTL.TL.format) then
                T.planErr = "format が "..tostring(plan.format)
                return
            end
            if (type(plan.entries) ~= "table") then
                T.planErr = "entries がありません"
                return
            end
            local meta = plan.meta or {}
            local stem = T.file and T.file:gsub("%.lua$", "")
            -- このマップのほかのタイムライン（前半・後半など）を指すプランは、そのまま使う（v0.6.9）
            local sibling = false
            for _, c in ipairs(T.cands or {}) do
                if (meta.timeline and c.file:gsub("%.lua$", "") == meta.timeline) then sibling = true end
            end
            if (meta.timeline and stem and meta.timeline ~= stem and not sibling) then
                T.planWarn[#T.planWarn + 1] = "プランのタイムライン「"..tostring(meta.timeline).."」と読み込んだ「"..stem.."」が違います"
            end
            if (meta.timeline == stem and meta.timelineVersion and T.timeline.meta.version and meta.timelineVersion ~= T.timeline.meta.version) then
                T.planWarn[#T.planWarn + 1] = "タイムラインの改訂番号が違います（プラン "..tostring(meta.timelineVersion)..
                    "・タイムライン "..tostring(T.timeline.meta.version).."）"
            end
            local missing = 0
            local snd = { entries = 0, all = 0, missingFiles = {} }
            for i, e in ipairs(plan.entries) do
                e.id = e.id or ("entry"..i)
                local ok = true
                -- 音（v0.4.0）：sound = "x.wav" か sound = { file = "x.wav", byAction = { [ID] = "y.wav", ... } }
                e.snd = RTL_SND_ParseEntry(e, T.planWarn)
                e.hasAction = (type(e.action) == "table" and type(e.action.id) == "number")
                if (e.snd) then snd.all = snd.all + 1 end
                if (not e.hasAction and not e.snd) then
                    T.planWarn[#T.planWarn + 1] = e.id..": action.id も sound もありません（使いません）"
                    ok = false
                elseif (not T.events[e.event]) then
                    missing = missing + 1
                    ok = false
                end
                if (ok and e.snd) then
                    snd.entries = snd.entries + 1
                    for _, f in ipairs(RTL_SND_EntryFiles(e.snd)) do
                        if (not RTL_SND_Exists(f, true) and not snd.missingFiles[f]) then
                            snd.missingFiles[f] = true
                            T.planWarn[#T.planWarn + 1] = e.id..": wav が見つかりません: "..RTL_SND_Path(f)
                        end
                    end
                end
                e.disabled = not ok
                e.ref = (e.ref == "start") and "start" or "hit"
                e.offset = (type(e.offset) == "number") and e.offset or 0
                e.window = (type(e.window) == "number") and e.window or RTL.TL.entryWindow
                e.recentSec = (type(e.recentSec) == "number") and e.recentSec or RTL.TL.recentSec
                e.target = (type(e.target) == "table") and e.target or { type = "self" }
                e.execute = (e.execute ~= false)                          -- false ならドライランだけ（v0.3.0）
                e.priority = (e.priority == "now") and "now" or "weave"   -- 実行の優先（v0.3.0）
                -- 分岐の条件（v0.6.8）：onAction = ID か { ID, ... }。照合したアクションがこの中のときだけ使う
                e.onSet = nil
                if (e.onAction ~= nil) then
                    local set = RTL_TL_IsNumList(e.onAction) and RTL_TL_ActionSet(e.onAction) or nil
                    if (not set) then
                        T.planWarn[#T.planWarn + 1] = e.id..": onAction は ID か { ID, ... } で書いてください（条件なしで使います）"
                    else
                        e.onSet = set
                        local evref = T.events[e.event]
                        local aset = evref and evref.ev.match and evref.ev.match.actionSet
                        if (aset) then
                            local any = false
                            for id in pairs(set) do if (aset[id]) then any = true end end
                            if (not any) then
                                T.planWarn[#T.planWarn + 1] = e.id..": onAction のアクションが、イベント "..tostring(e.event)..
                                    " で照合するアクションにありません（このエントリは使われません）"
                            end
                        end
                    end
                end
            end
            if (missing > 0) then
                T.planWarn[#T.planWarn + 1] = missing.." 件のエントリは、このタイムラインに無いイベントを指しています（使いません）"
            end
            T.plan = plan
            T.planSounds = snd.entries
            RTL_SND_OnPlanLoaded(snd.all)   -- 今のタイムラインに無いイベントの音も数える（ダンジョンはボスごとにタイムラインが変わる）
            RTL_Msg("plan loaded: plans\\"..tostring(mapid).."\\"..name.."  entries="..#plan.entries.."  sounds="..snd.entries)
            return
        end
    end
end

-- マップ・ジョブ・ポジションが変わったとき、ボタンで読み直すとき
function RTL_TL_Reload(mapid, fileName)
    local T = RTL.tl
    if (T.pull) then
        RTL_TL_EndPull(RTL_Now(), "reload")
    end
    T.mapid = mapid
    T.job = Player and Player.job
    T.tgState, T.hpLast, T.cidOf, T.preCasts, T.preDropMs = {}, {}, {}, {}, nil
    RTL_TL_LoadTimeline(mapid, fileName)
    RTL_TL_LoadPlan()
    -- プラン編集のタイムライン・プランの一覧も作り直す（タイムラインを足した・消したとき。v0.6.9）
    if (RTL.pe) then
        RTL.pe.planList, RTL.pe.tlCache = nil, nil
    end
end

-- =====================================================================
-- 表示用の名前
-- =====================================================================

-- イベントの表示名：events の name が仮名（「38383 #1」）なら、技名（タイムラインの actions ＞ names/actions.lua）に置き換える
function RTL_TL_EventLabel(ev)
    local name = ev.name or ev.id
    local num, k = tostring(name):match("^(%d+) #(%d+)$")
    if (num) then
        local a = tonumber(num)
        local tl = RTL.tl.timeline
        local tech = (tl and tl.actions and tl.actions[a]) or (RTL.names.actions and RTL.names.actions[a])
            or RTL_TL_GameActionName(a)
        if (tech) then
            return tech.." #"..k
        end
    end
    return tostring(name)
end

-- ゲームの技名（ActionList:Get(1, ID).name。敵のアクションでも取れる：v0.2.1 の api_probe で確認）
function RTL_TL_GameActionName(id)
    local T = RTL.tl
    T.gameNames = T.gameNames or {}
    local c = T.gameNames[id]
    if (c == nil) then
        c = false
        local ok, act = pcall(function() return ActionList:Get(1, id) end)
        if (ok and type(act) == "table" and type(act.name) == "string" and act.name ~= "") then
            c = act.name
        end
        T.gameNames[id] = c
    end
    return c or nil
end

-- 自分のアクション名（プレイヤーのアクションなら取れる見込み。取れなければ note か ID）
function RTL_TL_ActionLabel(entry)
    local a = entry.action or {}
    local id = a.id
    local c = RTL.tl.actionNames[id]
    if (c == nil) then
        c = false
        local ok, act = pcall(function() return ActionList:Get(a.type or 1, id) end)
        if (ok and type(act) == "table" and type(act.name) == "string" and act.name ~= "") then
            c = act.name
        end
        RTL.tl.actionNames[id] = c
    end
    if (c) then
        return c
    end
    return entry.note or ("#"..tostring(id))
end

-- =====================================================================
-- 敵の選び方（仕様 2.2）：HP トリガーと対象選びだけで使う
-- =====================================================================

function RTL_TL_Select(key)
    local T = RTL.tl
    local def = T.timeline and T.timeline.entities[key]
    if (not def) then
        return {}
    end
    local sel = (type(def.select) == "table") and def.select or {}
    local pull = T.pull
    local lock = pull and pull.locks[key]
    if (lock) then
        local out = {}
        for _, id in ipairs(lock) do
            local e = EntityList:Get(id)
            if (e) then out[#out + 1] = e end
        end
        if (#out > 0) then
            return out
        end
        pull.locks[key] = nil
    end
    local cands = {}
    local el = EntityList("contentid="..def.contentid)
    if (el) then
        for id, e in pairs(el) do
            local ok = true
            if (sel.targetable ~= false and not e.targetable) then ok = false end
            if (sel.attackable ~= false and not e.attackable) then ok = false end
            if (ok and sel.model and Argus and Argus.getEntityModel) then
                local okm, m = pcall(Argus.getEntityModel, id)
                if (not okm or m ~= sel.model) then ok = false end
            end
            if (ok) then cands[#cands + 1] = e end
        end
    end
    table.sort(cands, function(a, b) return a.id < b.id end)
    local out = {}
    if (sel.count == "all") then
        out = cands
    else
        local e = cands[sel.index or 1]
        if (e) then out[1] = e end
    end
    if (pull and sel.lock ~= false and #out > 0) then
        local ids = {}
        for i, e in ipairs(out) do ids[i] = e.id end
        pull.locks[key] = ids
    end
    return out
end

-- =====================================================================
-- プル（戦闘）の開始・終了
-- =====================================================================

function RTL_TL_Row(kind, f)
    local pull = RTL.tl.pull
    if (not pull) then
        return
    end
    f = f or {}
    f.kind = kind
    f.ms = f.ms or RTL_Now()
    f.phase = f.phase or pull.cur
    if (f.clock == nil and pull.cur) then
        local ph = pull.phases[pull.cur]
        if (ph) then f.clock = (f.ms - ph.startMs) / 1000 end
    end
    pull.rows[#pull.rows + 1] = f
    return f
end

function RTL_TL_Recent(text)
    local r = RTL.tl.recent
    table.insert(r, 1, text)
    while (#r > RTL.TL.recentRows) do
        table.remove(r)
    end
end

function RTL_TL_StartPull(now, opt)
    local T = RTL.tl
    local mapid = T.mapid
    local stamp = (opt and opt.stamp) or (RTL.pull and RTL.pull.stamp) or os.date("%Y%m%d_%H%M%S")
    local dir = RTL.path.."\\logs\\"..tostring(mapid)
    local pull = {
        startMs = now, t0Ms = now, t0src = "combat_start", stamp = stamp,
        file = dir.."\\"..stamp.."_dryrun.csv",
        rows = {}, counts = {}, lastCast = {}, phases = {}, entered = {}, cur = nil,
        matches = {}, nomatch = {}, syncsDone = {}, entries = {}, locks = {}, hitIds = {}, sounds = {},
        savedMs = now, stats = { matched = 0, absSum = 0, absMax = 0, syncs = 0, syncSkip = 0, nomatch = 0, dry = {} },
    }
    pull.ex = RTL_EX_NewPull(dir, stamp)
    if (opt) then
        pull.baseStamp, pull.part, pull.chain = opt.baseStamp, opt.part, opt.chain
        pull.hitIds = opt.hitIds or pull.hitIds
    end
    T.pull = pull
    T.recent = {}
    -- 戦闘開始（v0.4.0）：敵を対象にした最初のパーティのアクション → 直前の最後のパーティのアクション → first_hit → combat_start
    local pa = T.partyAct
    local lastOk = (pa and now - pa.ms >= 0 and now - pa.ms <= RTL.settings.firstActSec * 1000)
    pull.lastActMs = lastOk and pa.ms or nil
    local h = (not opt) and RTL_FirstHostile(now) or nil
    if (opt and opt.t0Ms) then
        pull.t0Ms, pull.t0src = opt.t0Ms, opt.t0src or "handoff"
    elseif (h) then
        pull.t0Ms, pull.t0src = h.ms, "first_hostile"
    elseif (lastOk) then
        pull.t0Ms, pull.t0src = pa.ms, "first_action"
    elseif (T.preDropMs and now - T.preDropMs <= RTL.settings.hitBeforeSec * 1000) then
        pull.t0Ms, pull.t0src = T.preDropMs, "first_hit"
    end
    T.partyAct = nil
    RTL_TL_Row("combat_start", { ms = pull.t0Ms, result = pull.t0src, ref = T.file,
        detail = string.format("t0 -> combat_start %+d ms / plan %s / 実行 %s", now - pull.t0Ms, tostring(T.planFile),
            RTL_EX_ModeText()) })
    RTL_TL_ProbeFirstAction(now)
    RTL_SND_PullInfo()
    -- combat_start のフェーズ
    for _, ph in ipairs(T.timeline.phases) do
        if (ph.trigger.type == "combat_start") then
            RTL_TL_EnterPhase(ph, pull.t0Ms, "combat_start")
            break
        end
    end
    -- 戦闘開始より前に受け取っていた詠唱（t0 以降のもの）を流し直す
    local pre = T.preCasts
    T.preCasts = {}
    for _, c in ipairs(pre) do
        if (c.ms >= pull.t0Ms) then
            RTL_TL_HandleCast(c.id, c.cid, c.spell, c.castMax, c.ms)
        end
    end
    RTL_Msg("dry-run started: t0="..pull.t0src..string.format(" (%+d ms)", now - pull.t0Ms))
end

-- t0 を first_hit に合わせ直す（first_action が無く、combat_start の後で最初に HP が減ったとき）
function RTL_TL_RebaseFirstHit(ms)
    local pull = RTL.tl.pull
    if (not pull or pull.t0src ~= "combat_start") then
        return
    end
    if (ms < pull.startMs - RTL.settings.hitBeforeSec * 1000 or ms > pull.startMs + RTL.settings.hitAfterSec * 1000) then
        return
    end
    local shift = ms - pull.t0Ms
    pull.t0Ms, pull.t0src = ms, "first_hit"
    for id, ph in pairs(pull.phases) do
        if (ph.trigger == "combat_start" and not ph.synced) then
            ph.startMs = ms
        end
    end
    RTL_TL_Row("t0_first_hit", { ms = ms, result = "first_hit", diff = shift / 1000,
        detail = string.format("t0 を first_hit に合わせた（%+d ms）", shift) })
end

function RTL_TL_EndPull(endMs, reason)
    local T = RTL.tl
    local pull = T.pull
    if (not pull) then
        return
    end
    -- まだ判定していないエントリ
    for _, rt in ipairs(pull.entries) do
        if (rt.status == "wait" or rt.status == "retry") then
            RTL_TL_Finish(rt, endMs, "未到達（戦闘終了）", "")
        elseif (rt.status == "casting") then
            RTL_TL_Finish(rt, endMs, "未確認（戦闘終了）", "Cast から使用の確認が来る前に戦闘が終わった")
        end
    end
    RTL_SND_CutPull(pull, nil, endMs, "未到達（戦闘終了）", "")
    local exSummary = RTL_EX_EndPull(pull, endMs)
    local st = pull.stats
    local result = reason
    -- クリア／全滅：プル中に HP が減ったタイムラインの敵のどれかが HP 0 ならクリア
    if (reason == "end") then
        local any, dead = false, false
        for id in pairs(pull.hitIds) do
            any = true
            if (T.hpLast[id] == 0) then dead = true end
        end
        if (dead) then
            result = "clear"
        elseif (any) then
            result = "wipe"
        end
    end
    RTL_TL_Row("end", { ms = endMs, result = result,
        detail = string.format("照合 %d 件 平均ずれ %.2f 秒 最大 %.2f 秒 / 同期 %d 回（範囲外 %d）/ 未照合 %d / 音 %d 回（鳴らせない %d）",
            st.matched, st.matched > 0 and st.absSum / st.matched or 0, st.absMax, st.syncs, st.syncSkip, st.nomatch,
            st.sounds or 0, st.soundFail or 0) })
    RTL_TL_Save(true)
    T.lastPull = {
        file = pull.stamp.."_dryrun.csv", result = result, matched = st.matched,
        avg = st.matched > 0 and st.absSum / st.matched or 0, max = st.absMax,
        syncs = st.syncs, syncSkip = st.syncSkip, nomatch = st.nomatch, dry = st.dry,
        dur = (endMs - pull.t0Ms) / 1000, ex = exSummary,
    }
    T.pull = nil
    T.outSince = nil
    T.preCasts = {}
    T.preDropMs = nil
    RTL_Msg("dry-run saved: "..pull.file)
    RTL_Msg("actions: "..exSummary)
end

-- =====================================================================
-- フェーズ・時計
-- =====================================================================

function RTL_TL_EnterPhase(ph, ms, why)
    local T = RTL.tl
    local pull = T.pull
    if (pull.phases[ph.id]) then
        return
    end
    local old = pull.cur
    pull.phases[ph.id] = { startMs = ms, enterMs = ms, trigger = ph.trigger.type, synced = false, def = ph }
    pull.entered[#pull.entered + 1] = ph.id
    pull.cur = ph.id
    -- 前のフェーズの残りは打ち切り
    if (old) then
        for _, rt in ipairs(pull.entries) do
            if (rt.phase == old and (rt.status == "wait" or rt.status == "retry")) then
                RTL_TL_Finish(rt, ms, "未到達（フェーズ移行）", ph.id.." に移行")
            end
        end
        RTL_SND_CutPull(pull, old, ms, "未到達（フェーズ移行）", ph.id.." に移行")
    end
    RTL_TL_Row("phase_enter", { ms = ms, phase = ph.id, clock = 0, ref = ph.id,
        detail = (ph.name or "").." / "..why..((old and (" / 前 "..old)) or "") })
    RTL_TL_Recent(string.format("[%s] フェーズ %s（%s）", RTL_TL_FmtT(ms), ph.id, why))
    RTL_TL_AddEntries(ph, ms)
end

-- そのフェーズのイベントを基準にするエントリを並べる（すでに過ぎたものは「途中から」として飛ばす）
function RTL_TL_AddEntries(ph, now)
    local T = RTL.tl
    local pull = T.pull
    if (not T.plan) then
        return
    end
    for _, e in ipairs(T.plan.entries) do
        local evref = (not e.disabled) and T.events[e.event]
        if (evref and evref.phase == ph) then
            if (e.hasAction) then
                local done = false
                for _, rt in ipairs(pull.entries) do
                    if (rt.entry.id == e.id and rt.phase == ph.id) then done = true end
                end
                if (not done) then
                    local rt = { entry = e, ev = evref.ev, phase = ph.id, status = "wait" }
                    pull.entries[#pull.entries + 1] = rt
                end
            end
            -- 音（v0.4.0）：アクションとは別に並べる（アクションの判定・実行とは独立）
            if (e.snd) then
                local done = false
                for _, sr in ipairs(pull.sounds) do
                    if (sr.entry.id == e.id and sr.phase == ph.id) then done = true end
                end
                if (not done) then
                    pull.sounds[#pull.sounds + 1] = { entry = e, ev = evref.ev, phase = ph.id, status = "wait" }
                end
            end
        end
    end
end

function RTL_TL_Clock(phaseId, ms)
    local pull = RTL.tl.pull
    local ph = pull and pull.phases[phaseId]
    if (not ph) then
        return nil
    end
    return ((ms or RTL_Now()) - ph.startMs) / 1000
end

-- 戦闘開始からの秒数（画面・ログの見出し用）
function RTL_TL_FmtT(ms)
    local pull = RTL.tl.pull
    if (not pull) then
        return "-"
    end
    return string.format("%.1f", (ms - pull.t0Ms) / 1000)
end

-- イベントの詠唱開始・着弾の時刻（ms）。照合済みなら実測値
function RTL_TL_EventTimes(ev, phaseId)
    local pull = RTL.tl.pull
    local m = pull.matches[ev.id]
    if (m) then
        return m.ms, m.ms + (m.cast or ev.cast) * 1000, true
    end
    local ph = pull.phases[phaseId]
    if (not ph) then
        return nil
    end
    local st = ph.startMs + ev.t * 1000
    return st, st + ev.cast * 1000, false
end

function RTL_TL_ExecMs(rt)
    local st, hit = RTL_TL_EventTimes(rt.ev, rt.phase)
    if (not st) then
        return nil
    end
    local base = (rt.entry.ref == "start") and st or hit
    return base + rt.entry.offset * 1000
end

-- =====================================================================
-- 詠唱（Argus.registerOnEntityChannel から）
-- =====================================================================

function RTL_TL_OnChannel(entityID, spellID, targetID, castMax)
    local T = RTL.tl
    if (not RTL_TL_Enabled() or not T.timeline) then
        return
    end
    local cid = T.cidOf[entityID]
    if (cid == nil) then
        local e = EntityList:Get(entityID)
        cid = (e and e.contentid) or false
        if (e) then T.cidOf[entityID] = cid end
    end
    if (not cid or not T.cidSet[cid]) then
        return
    end
    local now = RTL_Now()
    if (not T.pull) then
        -- 戦闘開始の直前の詠唱はとっておく（t0 が incombat より前になるため）
        local pre = T.preCasts
        pre[#pre + 1] = { id = entityID, cid = cid, spell = spellID, castMax = castMax, ms = now }
        while (#pre > 0 and now - pre[1].ms > RTL.TL.preCastSec * 1000) do
            table.remove(pre, 1)
        end
        return
    end
    RTL_TL_HandleCast(entityID, cid, spellID, castMax, now)
end

function RTL_TL_TriggerMatchCast(tr, cid, spell, n)
    if (tr.type ~= "cast_start") then return false end
    if (RTL.tl.entityCid[tr.entity] ~= cid) then return false end
    if (not tr.actionSet[spell]) then return false end
    if (tr.nth and tr.nth ~= n) then return false end
    return true
end

function RTL_TL_HandleCast(entityID, cid, spell, castMax, ms)
    local T = RTL.tl
    local pull = T.pull
    local key = cid..":"..spell
    local n = (pull.counts[key] or 0) + 1
    pull.counts[key] = n
    local lastMs = pull.lastCast[key]
    local dup = (lastMs ~= nil and ms - lastMs <= RTL.TL.momentSec * 1000)
    if (not dup) then
        pull.lastCast[key] = ms
    end
    -- 1. フェーズのきっかけ（まだ入っていないフェーズだけ）
    for _, ph in ipairs(T.timeline.phases) do
        if (not pull.phases[ph.id] and RTL_TL_TriggerMatchCast(ph.trigger, cid, spell, n)) then
            RTL_TL_EnterPhase(ph, ms, "cast_start "..spell.." #"..n)
        end
    end
    local cur = pull.cur and pull.phases[pull.cur]
    if (not cur) then
        return
    end
    local phDef = cur.def
    -- 2. イベントの照合（同じ瞬間の 2 体目以降は見ない。同期点より先に、同期前の時計で比べる）
    if (not dup) then
        RTL_TL_MatchEvent(pull, cur, phDef, cid, spell, castMax, ms, n)
    end
    -- 3. 同期点（今のフェーズのもの。1 プルで 1 回ずつ）
    for si, sy in ipairs(phDef.syncs) do
        local sk = phDef.id..":"..si
        if (not pull.syncsDone[sk] and RTL_TL_TriggerMatchCast(sy.on, cid, spell, n)) then
            local clock = (ms - cur.startMs) / 1000
            local diff = clock - sy.t
            if (math.abs(diff) <= sy.window) then
                pull.syncsDone[sk] = true
                cur.startMs = ms - sy.t * 1000
                cur.synced = true
                pull.stats.syncs = pull.stats.syncs + 1
                RTL_TL_Row("sync", { ms = ms, clock = clock, ref = phDef.id.."#"..si, action = spell,
                    planned = sy.t, actual = clock, diff = -diff,
                    detail = string.format("時計を %+.2f 秒合わせた", -diff) })
                RTL_TL_Recent(string.format("[%s] 同期 %s #%d  %+.2f 秒", RTL_TL_FmtT(ms), phDef.id, si, -diff))
            elseif (not pull.syncsDone[sk.."skip"..n]) then
                pull.syncsDone[sk.."skip"..n] = true
                pull.stats.syncSkip = pull.stats.syncSkip + 1
                RTL_TL_Row("sync_skip", { ms = ms, clock = clock, ref = phDef.id.."#"..si, action = spell,
                    planned = sy.t, actual = clock, diff = -diff, detail = "window の外なので合わせない" })
            end
        end
    end
end

-- 予定時刻＋ tolerance 以内で、まだ照合していない一番近いイベントに結びつける
function RTL_TL_MatchEvent(pull, cur, phDef, cid, spell, castMax, ms, n)
    local best, bestD = nil, nil
    for _, ev in ipairs(phDef.events) do
        local mt = ev.match
        if (mt and not pull.matches[ev.id] and mt.cid == cid and mt.actionSet[spell]) then
            local pred = cur.startMs + ev.t * 1000
            local d = (ms - pred) / 1000
            if (math.abs(d) <= ev.tolerance and (not bestD or math.abs(d) < math.abs(bestD))) then
                best, bestD = ev, d
            end
        end
    end
    if (best) then
        local predClock = best.t
        local actClock = (ms - cur.startMs) / 1000
        pull.matches[best.id] = { ms = ms, cast = (type(castMax) == "number" and castMax > 0) and castMax or best.cast,
                                  diff = bestD, spell = spell }
        local st = pull.stats
        st.matched = st.matched + 1
        st.absSum = st.absSum + math.abs(bestD)
        if (math.abs(bestD) > st.absMax) then st.absMax = math.abs(bestD) end
        RTL_TL_Row("match", { ms = ms, ref = best.id, action = spell, planned = predClock, actual = actClock,
            diff = bestD, detail = RTL_TL_EventLabel(best) })
        -- 調査：敵のアクション名が ActionList:Get(1, ID)（種類が先）で取れるか（プルの最初の照合で 1 回だけ）
        if (st.matched == 1) then
            local okn, an = pcall(function() local x = ActionList:Get(1, spell) return x and x.name end)
            RTL_TL_Row("api_probe", { ms = ms, action = spell, detail = "ActionList:Get(1, "..spell..").name = "..
                (okn and tostring(an) or ("error: "..tostring(an))) })
        end
    else
        RTL_TL_Row("cast", { ms = ms, ref = tostring(cid), action = spell,
            detail = "照合するイベントなし（#"..n.."）" })
    end
end

-- 自分・パーティのアクション（Argus.registerOnEntityCast から）
function RTL_TL_OnCast(entityID, spellID)
    local T = RTL.tl
    local now = RTL_Now()
    if (Player and entityID == Player.id) then
        T.selfUse[spellID] = now
        RTL_Safe("EX_OnSelfCast", RTL_EX_OnSelfCast, spellID, now)
    end
    if (not T.pull and RTL.partySet[entityID]) then
        T.partyAct = { ms = now, id = entityID, spell = spellID }
        RTL_Safe("TL_NoteParty", RTL_TL_NotePartyAct, entityID, spellID, now)
    end
end

-- 調査（v0.3.0）：戦闘開始の直前のパーティのアクションが、敵を対象にしたものか。
--   発動した瞬間の castinginfo（castingid・castingtargets・channeltargetid。ffxivminion 本体が使っている）を控える。
--   戦闘開始の取り方はまだ変えない（結果はドライランのログの fa_probe 行）
function RTL_TL_NotePartyAct(entityID, spellID, now)
    local T = RTL.tl
    local e = (Player and entityID == Player.id) and Player or EntityList:Get(entityID)
    local ci = e and e.castinginfo
    local tg, hostile, nt, hcid = {}, nil, 0, nil
    if (type(ci) == "table") then
        local targets = ci.castingtargets
        if (type(targets) == "table") then
            for _, tid in pairs(targets) do
                if (type(tid) == "number") then
                    nt = nt + 1
                    if (nt <= 4) then tg[#tg + 1] = tostring(tid) end
                    if (not RTL.partySet[tid]) then
                        local te = EntityList:Get(tid)
                        if (te and te.attackable) then
                            hostile = true
                            hcid = hcid or te.contentid
                        end
                    end
                end
            end
        end
        if (hostile == nil and type(ci.channeltargetid) == "number" and ci.channeltargetid ~= 0
            and not RTL.partySet[ci.channeltargetid]) then
            local te = EntityList:Get(ci.channeltargetid)
            if (te and te.attackable) then
                hostile = true
                hcid = hcid or te.contentid
            end
        end
    end
    local list = T.partyActs or {}
    T.partyActs = list
    list[#list + 1] = { ms = now, id = entityID, spell = spellID, self = (Player and entityID == Player.id),
        castingid = type(ci) == "table" and ci.castingid or nil,
        chtarget = type(ci) == "table" and ci.channeltargetid or nil,
        targets = table.concat(tg, " ")..((nt > 4) and (" +"..(nt - 4)) or ""), ntargets = nt,
        hostile = hostile or false, hcid = hcid }
    local keepMs = math.max(3000, (RTL.settings.hostileSec or 2.5) * 1000 + 500)
    while (#list > 0 and (now - list[1].ms > keepMs or #list > 32)) do
        table.remove(list, 1)
    end
end

-- 戦闘開始（v0.4.0）：incombat の hostileSec 秒前までの、敵を対象にした最初のパーティのアクション（無ければ nil）
--   記録モードとドライランの両方が使う。一覧（RTL.tl.partyActs）は消さない（消すのはドライランの ProbeFirstAction）
function RTL_FirstHostile(now)
    local list = RTL.tl and RTL.tl.partyActs
    if (type(list) ~= "table") then
        return nil
    end
    local lim = (RTL.settings.hostileSec or 2.5) * 1000
    for _, a in ipairs(list) do
        if (a.hostile and now - a.ms >= 0 and now - a.ms <= lim) then
            return a
        end
    end
    return nil
end

function RTL_TL_ProbeFirstAction(now)
    local T = RTL.tl
    -- 一覧は消さない（v0.4.1）。記録モードの戦闘開始は 0.05 秒ごとなので、ドライランが同じ瞬間に先に始まることがあり、
    -- 消すと記録モードが敵対アクションを見つけられなかった（実機：1・3 ボスで記録ログの t0 が 0.7〜0.9 秒遅れた）。
    -- 古いものは時刻で外す（RTL_FirstHostile・下の範囲）
    local list = T.partyActs or {}
    local firstHostile = nil
    for _, a in ipairs(list) do
        if (now - a.ms <= RTL.settings.firstActSec * 1000 + 1500) then
            local act = nil
            pcall(function() act = ActionList:Get(1, a.spell) end)
            local nm = (type(act) == "table" and act.name) or ""
            local info = (type(act) == "table") and string.format("range %s radius %s cast %s recast %s",
                tostring(act.range), tostring(act.radius), tostring(act.casttime), tostring(act.recasttime)) or "-"
            if (a.hostile and not firstHostile) then firstHostile = a end
            RTL_TL_Row("fa_probe", { ms = a.ms, ref = a.self and "self" or tostring(a.id), action = a.spell,
                result = a.hostile and "hostile" or "-",
                detail = string.format("%s / castingid %s / targets [%s] / channeltarget %s / %s / combat_start %+d ms",
                    nm, tostring(a.castingid), a.targets, tostring(a.chtarget), info, now - a.ms) })
        end
    end
    local pull = T.pull
    if (firstHostile and pull and pull.t0src ~= "first_hostile") then
        RTL_TL_Row("fa_probe", { ms = firstHostile.ms, ref = "hostile_t0", action = firstHostile.spell,
            diff = (firstHostile.ms - pull.t0Ms) / 1000,
            detail = string.format("敵を対象にした最初のアクションを t0 にすると %+d ms", firstHostile.ms - pull.t0Ms) })
    end
    -- 旧 first_action（直前の最後のパーティのアクション）との差（v0.4.0。引き続き確かめるため）
    if (pull and pull.lastActMs and pull.t0src == "first_hostile") then
        RTL_TL_Row("fa_probe", { ms = pull.lastActMs, ref = "last_t0",
            diff = (pull.lastActMs - pull.t0Ms) / 1000,
            detail = string.format("旧 first_action（直前の最後のパーティのアクション）なら t0 が %+d ms", pull.lastActMs - pull.t0Ms) })
    end
end

-- =====================================================================
-- 走査（HP・ターゲット可否）
-- =====================================================================

function RTL_TL_Scan(now)
    local T = RTL.tl
    local pull = T.pull
    local handTo, handWhy = nil, nil
    for cid in pairs(T.cidSet) do
        local el = EntityList("contentid="..cid)
        if (el) then
            for id, e in pairs(el) do
                -- ターゲット可否
                local tg = (e.targetable == true)
                local old = T.tgState[id]
                T.tgState[id] = tg
                if (pull and old ~= tg and (old ~= nil or tg)) then
                    RTL_TL_OnTargetable(cid, id, tg, now)
                end
                -- HP（first_hit 用）
                local hp = e.hp and e.hp.current
                if (hp) then
                    local lastHp = T.hpLast[id]
                    if (lastHp and hp < lastHp) then
                        if (pull) then
                            local first = not pull.hitIds[id]
                            pull.hitIds[id] = true
                            RTL_TL_RebaseFirstHit(now)
                            if (first and not handTo) then
                                handTo = RTL_TL_HandoffTarget(cid)
                                handWhy = "contentid "..tostring(cid).." の HP が初めて減った"
                            end
                        elseif (not T.preDropMs) then
                            T.preDropMs, T.preDropCid = now, cid
                        end
                    end
                    T.hpLast[id] = hp
                end
            end
        end
    end
    if (T.preDropMs and not pull and now - T.preDropMs > 30000) then
        T.preDropMs, T.preDropCid = nil, nil
    end
    if (handTo) then
        RTL_TL_Handoff(handTo, now, handWhy)
        return
    end
    if (pull) then
        RTL_TL_CheckHp(now)
    end
end

function RTL_TL_OnTargetable(cid, id, tg, now)
    local T = RTL.tl
    local pull = T.pull
    -- 何回目か（v0.6.8）：戦闘開始から、その contentid が同じ向きに変わった回数（ターゲット可に戻るのは何度もあり得る）
    local key = "tg:"..cid..":"..tostring(tg)
    local n = (pull.counts[key] or 0) + 1
    pull.counts[key] = n
    for _, ph in ipairs(T.timeline.phases) do
        local tr = ph.trigger
        if (not pull.phases[ph.id] and tr.type == "targetable" and T.entityCid[tr.entity] == cid
            and (tr.state ~= false) == tg and (tr.nth == nil or tr.nth == n)) then
            RTL_TL_EnterPhase(ph, now, "targetable "..tostring(tg).." #"..n.." ("..tostring(id)..")")
        end
    end
end

function RTL_TL_CheckHp(now)
    local T = RTL.tl
    local pull = T.pull
    for _, ph in ipairs(T.timeline.phases) do
        local tr = ph.trigger
        if (not pull.phases[ph.id] and tr.type == "hp_below") then
            local ents = RTL_TL_Select(tr.entity)
            if (#ents > 0) then
                local fire = false
                local mode = tr.mode or "any"
                local function below(cur, mx, pct)
                    if (tr.value) then return cur <= tr.value end
                    return pct <= tr.percent
                end
                if (mode == "sum") then
                    local c, m = 0, 0
                    for _, e in ipairs(ents) do
                        c = c + (e.hp.current or 0)
                        m = m + (e.hp.max or 0)
                    end
                    fire = m > 0 and below(c, m, c * 100 / m)
                else
                    local all, any = true, false
                    for _, e in ipairs(ents) do
                        local h = e.hp
                        local b = h and h.max and h.max > 0 and below(h.current, h.max, h.current * 100 / h.max)
                        if (b) then any = true else all = false end
                    end
                    fire = (mode == "all") and all or any
                end
                if (fire) then
                    RTL_TL_EnterPhase(ph, now, "hp_below "..tostring(tr.percent or tr.value))
                end
            end
        end
    end
end

-- =====================================================================
-- ドライランの判定（設計書 3.1 の 1〜5。結果だけ出す）
-- =====================================================================

function RTL_TL_ResolveEntity(spec)
    if (spec == nil or spec == "self") then
        return { EntityList:Get(Player.id) or Player }
    end
    if (spec == "target") then
        local t = Player:GetTarget()
        return t and { t } or {}
    end
    local T = RTL.tl
    if (type(spec) == "string" and T.entityCid[spec]) then
        return RTL_TL_Select(spec)
    end
    return {}   -- ポジション指定の味方は、まだ割り当て表がない
end

function RTL_TL_TargetOf(entry)
    local tg = entry.target
    if (tg.type == "self") then return RTL_TL_ResolveEntity("self"), "自分" end
    if (tg.type == "target") then return RTL_TL_ResolveEntity("target"), "ターゲット" end
    if (tg.type == "entity") then return RTL_TL_ResolveEntity(tg.key), tostring(tg.key) end
    if (tg.type == "position") then return {}, "ポジション "..tostring(tg.pos) end
    return {}, tostring(tg.type)
end

-- 効果が出ているか：found（誰かのものがある）, mine（自分が付けたものがある）
function RTL_TL_FindBuff(ents, buffs)
    local set = RTL_TL_ActionSet(buffs)
    local found, mine, info = false, false, nil
    for _, e in ipairs(ents) do
        local bl = e.buffs
        if (bl) then
            for _, b in pairs(bl) do
                if (type(b) == "table" and b.id and set[b.id]) then
                    found = true
                    info = string.format("バフ %d 残り %.1f 秒", b.id, b.duration or 0)
                    if (b.ownerid == Player.id) then
                        mine = true
                    end
                end
            end
        end
    end
    return found, mine, info
end

function RTL_TL_Finish(rt, ms, result, detail, planned)
    local pull = RTL.tl.pull
    rt.status = "done"
    rt.result = result
    rt.doneMs = ms
    local st = pull.stats.dry
    st[result] = (st[result] or 0) + 1
    local execMs = planned or RTL_TL_ExecMs(rt)
    if (rt.waitNote) then       -- 分岐の照合を待った（v0.6.8）
        detail = ((detail and detail ~= "") and (detail.." / ") or "")..rt.waitNote
    end
    local clockExec = execMs and RTL_TL_Clock(rt.phase, execMs)
    local clockNow = RTL_TL_Clock(rt.phase, ms)
    RTL_TL_Row("dryrun", { ms = ms, phase = rt.phase, clock = clockNow, ref = rt.entry.id, action = rt.entry.action.id,
        planned = clockExec, actual = clockNow, diff = (execMs and (ms - execMs) / 1000) or nil, result = result,
        detail = RTL_TL_ActionLabel(rt.entry).." → "..RTL_TL_EventLabel(rt.ev)..
                 string.format("（%s %+.1f）", rt.entry.ref, rt.entry.offset)..((detail and detail ~= "") and (" / "..detail) or "") })
    RTL_TL_Recent(string.format("[%s] %s：%s", RTL_TL_FmtT(ms), RTL_TL_ActionLabel(rt.entry), result))
end

function RTL_TL_Judge(rt, now, execMs)
    local e = rt.entry
    if (Player.alive == false) then
        return RTL_TL_Finish(rt, now, "何もしない（戦闘不能）", "", execMs)
    end
    local ents, tname = RTL_TL_TargetOf(e)
    if (#ents == 0) then
        return RTL_TL_Finish(rt, now, "未実行：対象なし", tname, execMs)
    end
    -- 1・2. 効果がすでに出ている
    local sb = e.satisfiedBy
    if (type(sb) == "table" and sb.buffs) then
        local holders = RTL_TL_ResolveEntity(sb.on or "self")
        local found, mine, info = RTL_TL_FindBuff(holders, sb.buffs)
        if (mine) then
            RTL_EX_MarkOtherFirst(rt, now)
            return RTL_TL_Finish(rt, now, "達成済み（他が使用）", info, execMs)
        end
        if (found and sb.owner == "any") then
            return RTL_TL_Finish(rt, now, "同等効果あり", info, execMs)
        end
    end
    -- 3. 実行時刻の少し前に自分が使っていた
    local last = RTL.tl.selfUse[e.action.id]
    if (last and execMs - last <= e.recentSec * 1000 and last <= now) then
        RTL_EX_MarkOtherFirst(rt, now)
        return RTL_TL_Finish(rt, now, "直前に使用済み", string.format("%.1f 秒前", (execMs - last) / 1000), execMs)
    end
    -- 4・5. リキャスト
    --   ActionList:Get は（種類, ID）の順（ffxivminion 本体の ActionIsReady と同じ）。
    --   cd は経過秒数、cdmax はリキャスト時間（残り = cdmax - cd。ffxiv_skillmgr と同じ）
    local act = nil
    pcall(function() act = ActionList:Get(e.action.type or 1, e.action.id) end)
    if (type(act) ~= "table" or act.id == nil) then
        return RTL_TL_Finish(rt, now, "未実行：アクションがない", "ActionList:Get("..tostring(e.action.type or 1)..", "..e.action.id..") = "..type(act), execMs)
    end
    local cdv, cdmax = tonumber(act.cd) or 0, tonumber(act.cdmax) or 0
    local ready = nil
    pcall(function() ready = act:IsReady(Player.id) end)
    local cdinfo = string.format("残り %.1f 秒（cd %.1f / %.1f）IsReady=%s", act.isoncd and math.max(cdmax - cdv, 0) or 0,
        cdv, cdmax, tostring(ready))
    if (act.isoncd) then
        if (now < execMs + e.window * 1000) then
            rt.status = "retry"
            rt.retryInfo = cdinfo
            return
        end
        return RTL_TL_Finish(rt, now, "未実行：リキャスト中", cdinfo, execMs)
    end
    -- 5. 実行（v0.3.0）：実行が ON・一時停止でない・エントリの execute が false でなければ、実際に使う
    local mode = RTL_EX_EntryMode(e)
    if (mode == "exec") then
        return RTL_EX_Try(rt, now, execMs, act, ents, cdinfo)
    end
    local late = (now - execMs) / 1000
    local tag = (mode == "paused") and "ドライラン・一時停止中" or ((mode == "entry") and "ドライラン・エントリの設定" or "ドライラン")
    local res = "実行（"..tag.."）"
    if (late > 0.5) then
        res = string.format("実行（%s・%.1f 秒遅れ）", tag, late)
    end
    return RTL_TL_Finish(rt, now, res, cdinfo, execMs)
end

function RTL_TL_RunEntries(now)
    local pull = RTL.tl.pull
    RTL_EX_Tick(pull, now)
    for _, rt in ipairs(pull.entries) do
        if (rt.status == "casting") then
            RTL_EX_CheckCasting(rt, now)
        end
        if (rt.phase == pull.cur and (rt.status == "wait" or rt.status == "retry")) then
            local execMs = RTL_TL_ExecMs(rt)
            if (execMs and now >= execMs) then
                if (rt.entry.onSet and rt.status == "wait") then
                    RTL_TL_JudgeBranch(rt, now, execMs)
                else
                    RTL_TL_Judge(rt, now, execMs)
                end
            end
        end
    end
end

-- 分岐の条件（v0.6.8）：onAction のあるエントリ。照合したアクションで、使うか決める。まだ照合していなければ待つ
function RTL_TL_JudgeBranch(rt, now, execMs)
    local pull = RTL.tl.pull
    local m = pull.matches[rt.ev.id]
    local function ids()
        local l = {}
        for id in pairs(rt.entry.onSet) do l[#l + 1] = id end
        table.sort(l)
        return table.concat(l, "/")
    end
    if (m) then
        if (not rt.entry.onSet[m.spell]) then
            return RTL_TL_Finish(rt, now, "対象外（別の分岐）", "来た "..tostring(m.spell).." / 条件 "..ids(), execMs)
        end
        local at = execMs
        if (rt.waitMatch) then
            at = math.max(execMs, m.ms)    -- 照合を待った：照合した時刻から遅れを数える
            rt.waitNote = string.format("分岐の照合を待った（%.1f 秒）", (at - execMs) / 1000)
        end
        rt.branchOk = true
        return RTL_TL_Judge(rt, now, at)
    end
    if (pull.nomatch[rt.ev.id]) then
        return RTL_TL_Finish(rt, now, "未実行：分岐が分からない（未照合）", "条件 "..ids(), execMs)
    end
    if (not rt.waitMatch) then
        rt.waitMatch = true
        RTL_TL_Recent(string.format("[%s] %s：分岐の照合を待つ（%s）", RTL_TL_FmtT(now), RTL_TL_ActionLabel(rt.entry),
            RTL_TL_EventLabel(rt.ev)))
    end
end

-- 予定時刻＋ tolerance を過ぎても照合できなかったイベント
function RTL_TL_CheckNoMatch(now)
    local pull = RTL.tl.pull
    local cur = pull.cur and pull.phases[pull.cur]
    if (not cur) then
        return
    end
    for _, ev in ipairs(cur.def.events) do
        if (ev.match and not pull.matches[ev.id] and not pull.nomatch[ev.id]) then
            local pred = cur.startMs + ev.t * 1000
            if (now > pred + ev.tolerance * 1000) then
                pull.nomatch[ev.id] = true
                pull.stats.nomatch = pull.stats.nomatch + 1
                RTL_TL_Row("nomatch", { ms = now, ref = ev.id, planned = ev.t, detail = RTL_TL_EventLabel(ev) })
            end
        end
    end
end

-- =====================================================================
-- 実行（v0.3.0）：ドライランの判定が「実行」になったエントリを、実際に使う（oGCD。対象は自分・ターゲット・ボス）
--
--   使い方は ffxivminion 本体の QueueAction と同じ：ActionList:Get(種類, ID) → :IsReady(対象) → :Cast(対象ID)
--   成功の確認：Cast の後 confirmSec 以内に、自分の使用（registerOnEntityCast の Player.id）が届いたか。
--               lockSec を過ぎてリキャストに入っていれば、それでも成功とみなす（二重発動の防止：確認までは再試行しない）
--   ACR との競合：詠唱中（castinginfo.channelingid ≠ 0）は待つ。priority = "weave"（既定）は、
--               自分の直前のアクションから animLockSec たち、次の GCD まで gcdMarginSec 以上ある隙間でだけ使う。
--               window の最後の forceLastSec は GCD の直前でも使う。priority = "now" は隙間を待たない
--   GCD か oGCD か：ffxivminion 本体の SkillMgr と同じく、ジョブの代表 GCD（FFXIVMinionAction.GetRepresentativeGCD）の
--               recasttime と 0.1 秒以内なら GCD
--   衝突の検証（設計書 3.2）：logs/<mapid>/<日時>_actions.csv に、プル中の自分のアクションを全部書く（実行が OFF でも）
-- =====================================================================

RTL.EX = {
    lockSec      = 0.5,   -- Cast の後、この秒数はリキャスト開始を見ない（確認までは再試行しない）
    confirmSec   = 1.0,   -- これ以内に自分の使用が届かなければ「応答なし」
    animLockSec  = 0.6,   -- 自分の直前のアクションからこの秒数は待つ（アニメーションロック）
    gcdMarginSec = 0.6,   -- 次の GCD までこの秒数以上あるときだけ挟む
    gcdIdleSec   = 1.0,   -- GCD が使える状態のまま、いつもの GCD ＋この秒数 GCD が来なければ「ACR は GCD を使っていない」
    forceLastSec = 0.5,   -- priority = "weave" でも、window の最後のこの秒数は GCD の直前でも使う
    retrySec     = 0.1,   -- Cast が false を返したときの再試行の間隔
    gcdDelaySec  = 0.3,   -- GCD の遅れの疑い：いつもの GCD の間隔より、これ以上延びた（ユーザーの決定）
    gcdBreakMul  = 2.0,   -- GCD の間隔がいつもの何倍を超えたら「途切れ」（ボスがいない間など。平均に入れない）
    doubleSec    = 2.5,   -- 同じアクションを自分がこの秒数以内に 2 回使った → 二重使用の疑い
    autoAttack   = { [7] = true, [8] = true },   -- オートアタック（アニメーションロック・GCD の計算に入れない）
    COLUMNS      = "t,clock,phase,kind,action,name,gcd,source,entry,result,gcd_interval,state,detail",
    gcdFallback  = { [1] = 9, [19] = 9, [3] = 31, [21] = 31, [32] = 3617, [37] = 16137 },
}

RTL.ex = RTL.ex or { paused = false }
RTL.ex.infoCache = {}      -- [job..":"..spell] = { name, kind, recast }

-- 実行するか：exec（使う）／off（実行 OFF）／paused（一時停止中）／entry（エントリが execute = false）
function RTL_EX_EntryMode(e)
    if (RTL.settings.execute ~= true) then return "off" end
    if (RTL.ex.paused) then return "paused" end
    if (e and e.execute == false) then return "entry" end
    return "exec"
end

function RTL_EX_ModeText()
    if (RTL.settings.execute ~= true) then return "OFF（ドライランだけ）" end
    if (RTL.ex.paused) then return "一時停止中" end
    return "ON"
end

function RTL_EX_TogglePause()
    RTL.ex.paused = not RTL.ex.paused
    RTL_Msg("execute "..(RTL.ex.paused and "paused" or "resumed"))
    if (RTL.tl.pull) then
        RTL_TL_Row("ex_pause", { detail = RTL.ex.paused and "一時停止" or "再開" })
        RTL_TL_Recent(string.format("[%s] 実行を%s", RTL_TL_FmtT(RTL_Now()), RTL.ex.paused and "一時停止" or "再開"))
    end
end

-- MMOminion のショートカット管理に「RaidTimeline Pause」を登録する（キーは MMOminion の画面で割り当てる。1 回だけ）
function RTL_EX_RegisterHotkey()
    if (RTL_HotkeyRegistered) then
        RTL.ex.hotkey = true
        return
    end
    if (type(ml_input_mgr) == "table" and type(ml_input_mgr.registerFunction) == "function") then
        local ok, err = pcall(ml_input_mgr.registerFunction, {
            name = "RaidTimeline Pause",
            func = function() if (RTL_EX_TogglePause) then RTL_Safe("EX_Pause", RTL_EX_TogglePause) end end,
            toggle = true,
        })
        if (ok) then
            RTL_HotkeyRegistered = true
            RTL.ex.hotkey = true
            RTL_Msg("hotkey registered: RaidTimeline Pause")
        else
            RTL_Msg("hotkey register failed: "..tostring(err))
        end
    else
        RTL_Msg("ml_input_mgr.registerFunction not found (no hotkey)")
    end
end

-- ジョブの代表 GCD のアクション（ffxivminion 本体と同じもの）
function RTL_EX_GcdAction()
    local job = Player and Player.job
    local id = nil
    if (type(FFXIVMinionAction) == "table" and type(FFXIVMinionAction.GetRepresentativeGCD) == "function") then
        local ok, v = pcall(FFXIVMinionAction.GetRepresentativeGCD, job, false, Player.level)
        if (ok and type(v) == "number") then id = v end
    end
    id = id or RTL.EX.gcdFallback[job or -1]
    if (not id) then
        return nil
    end
    local act = nil
    pcall(function() act = ActionList:Get(1, id) end)
    if (type(act) ~= "table" or act.id == nil) then
        return nil
    end
    return act
end

-- 代表 GCD の recasttime（GCD の見分け用。0 なら 2.5）
function RTL_EX_GcdBase()
    local a = RTL_EX_GcdAction()
    local rc = a and tonumber(a.recasttime) or 0
    if (rc <= 0) then rc = 2.5 end
    return rc
end

-- 次の GCD までの秒数（GCD が使える状態なら 0）と、そのときの cdmax（スキルスピード込みの GCD の長さ）
function RTL_EX_GcdRemain()
    local a = RTL_EX_GcdAction()
    if (not a) then
        return 0, nil
    end
    local cdmax = tonumber(a.cdmax) or 0
    if (a.isoncd) then
        return math.max(cdmax - (tonumber(a.cd) or 0), 0), (cdmax > 0) and cdmax or nil
    end
    return 0, nil
end

-- 自分のアクションの名前と種類（GCD / oGCD / auto / ?）
function RTL_EX_ActionInfo(spell)
    local key = tostring(Player and Player.job)..":"..tostring(spell)
    local c = RTL.ex.infoCache[key]
    if (c) then
        return c
    end
    c = { name = "", kind = "?", recast = nil }
    local act = nil
    pcall(function() act = ActionList:Get(1, spell) end)
    if (type(act) == "table") then
        c.name = (type(act.name) == "string") and act.name or ""
        c.recast = tonumber(act.recasttime)
    end
    if (RTL.EX.autoAttack[spell]) then
        c.kind = "auto"
    elseif (c.recast and c.recast > 0) then
        c.kind = (math.abs(c.recast - RTL_EX_GcdBase()) <= 0.1) and "GCD" or "oGCD"
    end
    RTL.ex.infoCache[key] = c
    return c
end

-- プルごとの記録
function RTL_EX_NewPull(dir, stamp)
    return {
        file = dir.."\\"..stamp.."_actions.csv",
        rows = {}, pending = {}, lastUse = {}, lastUseRow = {},
        lastGcdMs = nil, rtlSinceGcd = nil, gcdMax = nil,
        stats = { use = 0, rtl = 0, success = 0, noresp = 0, otherFirst = 0, double = 0, gcdDelay = 0,
                  castFalse = 0, calls = 0, gcdN = 0, gcdSum = 0, gcdAfterN = 0, gcdAfterSum = 0,
                  gcdSlowOther = 0, gcdBreak = 0 },
    }
end

function RTL_EX_Row(X, f)
    local pull = RTL.tl.pull
    f.ms = f.ms or RTL_Now()
    if (pull and pull.cur) then
        f.phase = f.phase or pull.cur
        local ph = pull.phases[pull.cur]
        if (ph and f.clock == nil) then f.clock = (f.ms - ph.startMs) / 1000 end
    end
    X.rows[#X.rows + 1] = f
    return f
end

-- いつもの GCD の長さ（プル中に見た代表 GCD の cdmax。まだ見ていなければ recasttime）
function RTL_EX_GcdLen(X)
    return X.gcdMax or RTL_EX_GcdBase()
end

-- 毎回の更新（GCD の長さを控える）
function RTL_EX_Tick(pull, now)
    local X = pull.ex
    if (not X) then
        return
    end
    local _, cdmax = RTL_EX_GcdRemain()
    if (cdmax and cdmax > 0.5 and cdmax < 5) then
        X.gcdMax = cdmax
    end
end

-- 自分のアクションが届いた（registerOnEntityCast の Player.id。ACR・TensorReactions・手動・RaidTimeline のどれでも）
function RTL_EX_OnSelfCast(spell, now)
    local info = RTL_EX_ActionInfo(spell)
    local isAuto = (info.kind == "auto")
    if (not isAuto) then
        RTL.ex.lastSelfMs = now
    end
    local pull = RTL.tl.pull
    local X = pull and pull.ex
    local source = "他"
    local entryId, results, rt = "", {}, nil
    if (X) then
        -- RaidTimeline が呼んだものか（Cast の後 confirmSec ＋ 0.5 秒以内に同じアクション）
        local call = X.pending[spell]
        if (call and now - call.ms <= (RTL.EX.confirmSec + 0.5) * 1000) then
            source = "RaidTimeline"
            rt = call.rt
            entryId = rt and rt.entry.id or ""
            X.pending[spell] = nil
            results[#results + 1] = "成功"
            if (not call.counted) then
                X.stats.success = X.stats.success + 1
                call.counted = true
            end
            X.stats.rtl = X.stats.rtl + 1
        elseif (call) then
            X.pending[spell] = nil
        end
    end
    local name = info.name
    RTL.ex.last = { ms = now, id = spell, name = name, source = source }
    if (not X or isAuto) then
        if (X and isAuto) then
            RTL_EX_Row(X, { ms = now, kind = "use", action = spell, name = name, gcd = info.kind, source = source })
        end
        if (rt) then RTL_EX_Confirmed(rt, now, "使用を確認") end
        return
    end
    X.stats.use = X.stats.use + 1
    -- 二重使用の疑い：同じ oGCD を短い間に 2 回（GCD は毎回続けて使うので見ない）
    local prev = X.lastUse[spell]
    if (info.kind ~= "GCD" and prev and now - prev <= RTL.EX.doubleSec * 1000) then
        results[#results + 1] = string.format("二重使用の疑い（%.2f 秒前にも使用）", (now - prev) / 1000)
        X.stats.double = X.stats.double + 1
    end
    -- GCD の間隔
    local intervalTxt = ""
    if (info.kind == "GCD") then
        if (X.lastGcdMs) then
            local iv = (now - X.lastGcdMs) / 1000
            local len = RTL_EX_GcdLen(X)
            intervalTxt = string.format("%.2f", iv)
            if (iv > len * RTL.EX.gcdBreakMul) then
                results[#results + 1] = "GCD の途切れ"
                X.stats.gcdBreak = X.stats.gcdBreak + 1
            else
                X.stats.gcdN = X.stats.gcdN + 1
                X.stats.gcdSum = X.stats.gcdSum + iv
                local slow = iv > len + RTL.EX.gcdDelaySec
                if (X.rtlSinceGcd) then
                    X.stats.gcdAfterN = X.stats.gcdAfterN + 1
                    X.stats.gcdAfterSum = X.stats.gcdAfterSum + iv
                    if (slow) then
                        results[#results + 1] = string.format("GCD 遅れの疑い（いつも %.2f 秒、直前に %s）", len, X.rtlSinceGcd)
                        X.stats.gcdDelay = X.stats.gcdDelay + 1
                    else
                        results[#results + 1] = "RaidTimeline の直後の GCD"
                    end
                elseif (slow) then
                    results[#results + 1] = string.format("延びた（RaidTimeline とは無関係。いつも %.2f 秒）", len)
                    X.stats.gcdSlowOther = X.stats.gcdSlowOther + 1
                end
            end
        end
        X.lastGcdMs = now
        X.rtlSinceGcd = nil
    elseif (source == "RaidTimeline") then
        X.rtlSinceGcd = name ~= "" and name or tostring(spell)
    end
    X.lastUse[spell] = now
    local row = RTL_EX_Row(X, { ms = now, kind = "use", action = spell, name = name, gcd = info.kind, source = source,
        entry = entryId, result = table.concat(results, " / "), gcd_interval = intervalTxt,
        detail = info.recast and string.format("recast %.2f", info.recast) or "" })
    X.lastUseRow[spell] = row
    if (rt) then RTL_EX_Confirmed(rt, now, "使用を確認") end
end

-- 「他が先に使った」：エントリが「直前に使用済み」「達成済み」で終わり、その元が RaidTimeline 以外の自分の使用
function RTL_EX_MarkOtherFirst(rt, now)
    local pull = RTL.tl.pull
    local X = pull and pull.ex
    if (not X) then
        return
    end
    local row = X.lastUseRow[rt.entry.action.id]
    if (row and row.source ~= "RaidTimeline" and not row.otherFirst) then
        row.otherFirst = true
        row.result = ((row.result ~= "" and row.result) and (row.result.." / ") or "").."他が先に使用（"..rt.entry.id.."）"
        X.stats.otherFirst = X.stats.otherFirst + 1
    end
end

-- 隙間があるか（ACR の GCD を邪魔しないか）。true / false, 理由, 状態の文字列
function RTL_EX_CanWeave(e, now, endMs)
    local ci = Player.castinginfo
    local chan = (type(ci) == "table" and tonumber(ci.channelingid)) or 0
    local rem = RTL_EX_GcdRemain()
    local since = RTL.ex.lastSelfMs and (now - RTL.ex.lastSelfMs) / 1000 or 99
    local state = string.format("詠唱 %d / GCD 残り %.2f / 直前の自分のアクションから %.2f 秒", chan, rem, math.min(since, 99))
    if (chan ~= 0) then
        return false, "詠唱中", state
    end
    if (e.priority == "now") then
        return true, "now", state
    end
    if (since < RTL.EX.animLockSec) then
        return false, "アニメーションロック", state
    end
    if (now >= endMs - RTL.EX.forceLastSec * 1000) then
        return true, "window の最後", state
    end
    if (rem >= RTL.EX.gcdMarginSec) then
        return true, "隙間", state
    end
    -- GCD が使える状態のまま GCD が来ない（ACR が GCD を使っていない：ボスがいない・ACR が止まっているなど）
    if (rem <= 0) then
        local X = RTL.tl.pull and RTL.tl.pull.ex
        local lastG = X and X.lastGcdMs
        local idle = RTL_EX_GcdLen(X or {}) + RTL.EX.gcdIdleSec
        if ((lastG and now - lastG >= idle * 1000) or (not lastG and since >= RTL.EX.gcdIdleSec)) then
            return true, "GCD を使っていない", state
        end
    end
    return false, "GCD の直前", state
end

-- 使う。rt.status は retry（待つ）／casting（確認待ち）／done
function RTL_EX_Try(rt, now, execMs, act, ents, cdinfo)
    local e = rt.entry
    local X = RTL.tl.pull.ex
    local endMs = execMs + e.window * 1000
    local spell = e.action.id
    if (rt.nextTryMs and now < rt.nextTryMs) then
        rt.status = "retry"
        return
    end
    -- 対象：自分なら Player.id。ボス・ターゲットに使えず、自分になら使えるとき（リプライザルのような自分中心の範囲）は自分
    local tid = (e.target.type == "self") and Player.id or (ents[1] and ents[1].id) or Player.id
    local rdT, rdS = nil, nil
    pcall(function() rdT = act:IsReady(tid) end)
    local useTid, tnote = tid, ""
    if (not rdT and tid ~= Player.id) then
        pcall(function() rdS = act:IsReady(Player.id) end)
        if (rdS) then
            useTid, tnote = Player.id, "（対象には使えないので自分に）"
        end
    end
    local readyTxt = string.format("IsReady(対象 %s)=%s%s", tostring(tid), tostring(rdT),
        (rdS ~= nil) and (" IsReady(自分)="..tostring(rdS)) or "")
    if (not rdT and not rdS) then
        rt.waitWhy = "使えない（"..readyTxt.."）"
        if (now < endMs) then
            rt.status = "retry"
            return
        end
        return RTL_TL_Finish(rt, now, "未実行：使えない", readyTxt.." / "..cdinfo, execMs)
    end
    local ok, why, state = RTL_EX_CanWeave(e, now, endMs)
    if (not ok) then
        rt.waitWhy = why
        rt.waitCount = (rt.waitCount or 0) + 1
        if (now < endMs) then
            rt.status = "retry"
            return
        end
        return RTL_TL_Finish(rt, now, "未実行：隙間なし（"..why.."）", state, execMs)
    end
    local isCasting = nil
    pcall(function() isCasting = ActionList:IsCasting() end)
    local okc, ret = pcall(function() return act:Cast(useTid) end)
    X.stats.calls = X.stats.calls + 1
    rt.attempts = (rt.attempts or 0) + 1
    local callState = string.format("%s / IsCasting=%s / %s%s / %s", state, tostring(isCasting), readyTxt, tnote, why)
    if (okc and ret ~= false) then
        rt.status = "casting"
        rt.castMs = now
        rt.castExecMs = execMs
        rt.castInfo = callState
        X.pending[spell] = { ms = now, rt = rt }
        RTL_EX_Row(X, { ms = now, kind = "call", action = spell, name = RTL_TL_ActionLabel(e), gcd = RTL_EX_ActionInfo(spell).kind,
            source = "RaidTimeline", entry = e.id, result = "Cast="..tostring(ret), state = callState,
            detail = string.format("%d 回目 / 予定から %+.2f 秒 / priority %s", rt.attempts, (now - execMs) / 1000, e.priority) })
        return
    end
    X.stats.castFalse = X.stats.castFalse + 1
    RTL_EX_Row(X, { ms = now, kind = "cast_false", action = spell, name = RTL_TL_ActionLabel(e), source = "RaidTimeline",
        entry = e.id, result = okc and "Cast=false" or ("error: "..tostring(ret)), state = callState })
    rt.nextTryMs = now + RTL.EX.retrySec * 1000
    if (now < endMs) then
        rt.status = "retry"
        return
    end
    return RTL_TL_Finish(rt, now, "未実行：Cast 失敗", callState, execMs)
end

-- 確認待ちのエントリ：lockSec を過ぎてリキャストに入っていれば成功、confirmSec を過ぎても来なければ「応答なし」
function RTL_EX_CheckCasting(rt, now)
    local e = rt.entry
    local X = RTL.tl.pull.ex
    local spell = e.action.id
    local el = now - rt.castMs
    if (el >= RTL.EX.lockSec * 1000) then
        local act = nil
        pcall(function() act = ActionList:Get(e.action.type or 1, spell) end)
        if (type(act) == "table" and act.isoncd) then
            local call = X.pending[spell]
            if (call and not call.counted) then
                call.counted = true
                X.stats.success = X.stats.success + 1
            end
            return RTL_EX_Confirmed(rt, now, "リキャスト開始を確認")
        end
    end
    if (el >= RTL.EX.confirmSec * 1000) then
        X.pending[spell] = nil
        X.stats.noresp = X.stats.noresp + 1
        RTL_EX_Row(X, { ms = now, kind = "noresp", action = spell, name = RTL_TL_ActionLabel(e), source = "RaidTimeline",
            entry = e.id, result = "応答なし", state = rt.castInfo,
            detail = string.format("Cast から %.2f 秒、自分の使用もリキャスト開始も来ない", el / 1000) })
        local endMs = rt.castExecMs + e.window * 1000
        if (now < endMs) then
            rt.status = "retry"
            rt.nextTryMs = now
            return
        end
        return RTL_TL_Finish(rt, now, "未実行：応答なし", rt.castInfo, rt.castExecMs)
    end
end

function RTL_EX_Confirmed(rt, now, how)
    if (rt.status ~= "casting") then
        return
    end
    local late = (rt.castMs - rt.castExecMs) / 1000
    local res = "実行（成功）"
    if (late > 0.5) then
        res = string.format("実行（成功・%.1f 秒遅れ）", late)
    end
    RTL_TL_Finish(rt, now, res, string.format("%s %.2f 秒後 / %d 回目 / %s", how, (now - rt.castMs) / 1000,
        rt.attempts or 1, rt.castInfo or ""), rt.castExecMs)
end

-- 戦闘終了：まとめ（ドライランのログ・画面・actions.csv）
function RTL_EX_Summary(X)
    local s = X.stats
    return string.format("成功 %d / 応答なし %d / 他が先に使用 %d / 二重使用の疑い %d / GCD 遅れの疑い %d / Cast 失敗 %d"..
        "  ｜ GCD %d 回 平均 %.2f 秒（RaidTimeline の直後 %d 回 平均 %.2f 秒、それ以外で延びた %d・途切れ %d）"..
        "  ｜ 自分のアクション %d（RaidTimeline %d）",
        s.success, s.noresp, s.otherFirst, s.double, s.gcdDelay, s.castFalse,
        s.gcdN, s.gcdN > 0 and s.gcdSum / s.gcdN or 0, s.gcdAfterN, s.gcdAfterN > 0 and s.gcdAfterSum / s.gcdAfterN or 0,
        s.gcdSlowOther, s.gcdBreak, s.use, s.rtl)
end

function RTL_EX_EndPull(pull, endMs)
    local X = pull.ex
    if (not X) then
        return ""
    end
    local text = RTL_EX_Summary(X)
    RTL_EX_Row(X, { ms = endMs, kind = "summary", result = RTL_EX_ModeText(),
        detail = text..string.format(" ｜ いつもの GCD %.2f 秒", RTL_EX_GcdLen(X)) })
    RTL_TL_Row("ex_summary", { ms = endMs, result = RTL_EX_ModeText(), detail = text })
    X.summary = text
    return text
end

function RTL_EX_Save(pull)
    local X = pull.ex
    if (not X) then
        return
    end
    local out = { RTL.EX.COLUMNS }
    local function n(x)
        if (type(x) == "number") then return string.format("%.2f", x) end
        return ""
    end
    for _, r in ipairs(X.rows) do
        out[#out + 1] = table.concat({
            RTL_Dec1((r.ms - pull.t0Ms) / 1000), n(r.clock), r.phase or "", r.kind, RTL_Num(r.action),
            RTL_CsvField(r.name or ""), r.gcd or "", RTL_CsvField(r.source or ""), RTL_CsvField(r.entry or ""),
            RTL_CsvField(r.result or ""), r.gcd_interval or "", RTL_CsvField(r.state or ""), RTL_CsvField(r.detail or ""),
        }, ",")
    end
    RTL_WriteFile(X.file, "\239\187\191"..table.concat(out, "\r\n").."\r\n")
end

-- =====================================================================
-- ファイルに書く
-- =====================================================================

function RTL_TL_Save(final)
    local pull = RTL.tl.pull
    if (not pull) then
        return
    end
    local dir = RTL.path.."\\logs\\"..tostring(RTL.tl.mapid)
    RTL_EnsureFolder(RTL.path.."\\logs")
    RTL_EnsureFolder(dir)
    local out = { RTL.TL.COLUMNS }
    local function n(x)
        if (type(x) == "number") then return string.format("%.2f", x) end
        return ""
    end
    for _, r in ipairs(pull.rows) do
        out[#out + 1] = table.concat({
            RTL_Dec1((r.ms - pull.t0Ms) / 1000), n(r.clock), r.phase or "", r.kind, RTL_CsvField(r.ref or ""),
            RTL_Num(r.action), n(r.planned), n(r.actual), n(r.diff), RTL_CsvField(r.result or ""), RTL_CsvField(r.detail or ""),
        }, ",")
    end
    RTL_WriteFile(pull.file, "\239\187\191"..table.concat(out, "\r\n").."\r\n")
    RTL_EX_Save(pull)
    pull.savedMs = RTL_Now()
end

-- =====================================================================
-- メインループ（RTL_Update から毎回呼ぶ）
-- =====================================================================

function RTL_TL_Tick()
    local T = RTL.tl
    local now = RTL_Now()
    if (not Player or not Player.id) then
        return
    end
    local mapid = Player.localmapid or 0
    if (mapid ~= T.mapid) then
        RTL_TL_Reload(mapid)
    elseif (Player.job ~= T.job) then
        T.job = Player.job
        RTL_TL_LoadPlan()
    end
    RTL_Safe("SND_Tick", RTL_SND_Tick, now)
    if (not RTL_TL_Enabled() or not T.timeline) then
        if (T.pull) then
            RTL_TL_EndPull(now, "stopped")
        end
        return
    end
    -- パーティの一覧（記録モードが止まっているときは、こちらで更新する）
    if (not RTL_Active() and now - T.last.party >= 500) then
        T.last.party = now
        RTL_UpdatePartySet()
    end
    -- 戦闘の開始・終了
    local inc = RTL_InCombat()
    if (inc) then
        T.outSince = nil
        if (not T.pull and now >= (T.skipUntil or 0)) then
            if (RTL_TL_PickForCombat(now)) then
                T.skipUntil, T.skipped = nil, nil
                RTL_TL_StartPull(now)
            else
                -- タイムラインの敵がいない戦闘：0.5 秒ごとに見直す（途中でボスが出ることがあるため）
                T.skipUntil, T.skipped = now + 500, true
            end
        end
    else
        T.skipUntil, T.skipped = nil, nil
    end
    if (not inc and T.pull) then
        T.outSince = T.outSince or now
        if (now - T.outSince >= RTL.settings.endSec * 1000) then
            RTL_TL_EndPull(T.outSince, "end")
            return
        end
    end
    -- 走査
    local scanSec = T.pull and RTL.TL.scanSec or RTL.TL.idleScanSec
    if (now - T.last.scan >= scanSec * 1000) then
        T.last.scan = now
        RTL_TL_Scan(now)
    end
    if (T.pull) then
        RTL_TL_RunEntries(now)
        RTL_TL_CheckNoMatch(now)
        RTL_Safe("SND_Run", RTL_SND_Run, now)
        if (now - T.pull.savedMs >= RTL.TL.autosaveSec * 1000) then
            RTL_TL_Save(false)
        end
    end
end

-- =====================================================================
-- 画面（ドライラン）
-- =====================================================================

RTL.window2 = RTL.window2 or { open = true, visible = true }

function RTL_TL_DrawWindow(event, ticks)
    if (not RTL.initDone or not RTL.window2.open) then
        return
    end
    GUI:SetNextWindowSize(470, 600, GUI.SetCond_FirstUseEver)
    local wasOpen = RTL.window2.open
    local _, open = RTL_UI_Window("RaidTimeline ドライラン", RTL.window2.open, nil, RTL_TL_DrawBody,
        { alpha = RTL.settings.uiAlpha, scale = RTL.settings.uiScale, where = "DrawDry" })
    RTL.window2.open = open
    if (wasOpen ~= RTL.window2.open) then
        RTL_SaveSettings()
    end
end

-- 次のイベント（今のフェーズで、まだ詠唱が始まっていないもの）
function RTL_TL_NextEvent(now)
    local pull = RTL.tl.pull
    local cur = pull and pull.cur and pull.phases[pull.cur]
    if (not cur) then
        return nil
    end
    local best, bestMs = nil, nil
    for _, ev in ipairs(cur.def.events) do
        if (not pull.matches[ev.id]) then
            local st = cur.startMs + ev.t * 1000
            if (st >= now - 500 and (not bestMs or st < bestMs)) then
                best, bestMs = ev, st
            end
        end
    end
    return best, bestMs
end

function RTL_TL_NextEntry(now)
    local pull = RTL.tl.pull
    if (not pull) then
        return nil
    end
    local best, bestMs = nil, nil
    for _, rt in ipairs(pull.entries) do
        if (rt.phase == pull.cur and rt.status == "wait") then
            local ms = RTL_TL_ExecMs(rt)
            if (ms and (not bestMs or ms < bestMs)) then
                best, bestMs = rt, ms
            end
        end
    end
    return best, bestMs
end

-- 実行の ON / OFF・一時停止・最後に使ったアクション（v0.3.0。v0.5.0 から部品で描く）
function RTL_EX_DrawControls(now)
    local st = RTL_EX_ModeText()
    RTL_UI_Title("実行")
    GUI:SameLine()
    if (RTL.settings.execute == true and not RTL.ex.paused) then
        RTL_UI_Badge(st, "success")
    elseif (RTL.ex.paused and RTL.settings.execute == true) then
        RTL_UI_Badge(st, "warning")
    else
        RTL_UI_Badge(st, "neutral")
    end
    GUI:SameLine()
    if (RTL_UI_Button((RTL.ex.paused and "再開" or "一時停止").."##expause", RTL.ex.paused and "warning" or nil, true)) then
        RTL_EX_TogglePause()
    end
    if (RTL.settings.execute == true and not RTL.ex.paused and not RTL_TL_Enabled()) then
        RTL_UI_Text("ドライランが OFF なので動きません", "warning")
    elseif (RTL.ex.paused and RTL.settings.execute == true) then
        RTL_UI_Text("判定はドライランとして続けます", "warning")
    end
    RTL_UI_Muted(RTL.ex.hotkey and "ショートカット: RaidTimeline Pause" or "ショートカット: なし")
    local la = RTL.ex.last
    if (la) then
        RTL_UI_Muted("最後に使ったアクション")
        GUI:SameLine()
        RTL_UI_Text((la.name ~= "" and la.name) or ("#"..tostring(la.id)), "own")
        GUI:SameLine()
        RTL_UI_Muted(string.format("%s・%.1f 秒前", tostring(la.source), (now - la.ms) / 1000))
    end
end

-- スイッチ（ドライラン・実行・音）を 1 行に
function RTL_TL_DrawSwitches()
    local v, pressed = RTL_UI_Toggle("ドライラン##dryon", RTL_TL_Enabled())
    if (pressed) then
        RTL.settings.dryrun = v
        RTL_SaveSettings()
    end
    GUI:SameLine()
    v, pressed = RTL_UI_Toggle("実行する（oGCD）##exon", RTL.settings.execute == true)
    if (pressed) then
        RTL.settings.execute = (v == true)
        RTL_SaveSettings()
        RTL_Msg("execute = "..tostring(RTL.settings.execute))
        if (RTL.tl.pull) then
            RTL_TL_Row("ex_switch", { detail = "実行 "..RTL_EX_ModeText() })
        end
    end
    GUI:SameLine()
    v, pressed = RTL_UI_Toggle("音を鳴らす##sndon", RTL.settings.sound == true)
    if (pressed) then
        RTL.settings.sound = (v == true)
        RTL_SaveSettings()
        if (RTL.settings.sound and (RTL.tl.planSounds or 0) > 0) then RTL.snd.wantStart = true end
        if (RTL.tl.pull) then
            RTL_TL_Row("snd_switch", { detail = "音 "..(RTL.settings.sound and "ON" or "OFF") })
        end
    end
    GUI:SameLine()
    v, pressed = RTL_UI_Toggle("タイムライン表示##tvshow2", RTL.settings.tvShow ~= false)
    if (pressed) then
        RTL_TV_SetSetting("tvShow", v)
    end
end

function RTL_TL_DrawBody()
    local T = RTL.tl
    local now = RTL_Now()
    RTL_TL_DrawSwitches()
    RTL_UI_Card("dry_ex", function() RTL_EX_DrawControls(now) end)
    RTL_UI_Card("dry_snd", function() RTL_SND_DrawControls(now) end)
    -- タイムライン・ポジション・プラン
    RTL_UI_Card("dry_tl", function()
        RTL_UI_Title("タイムライン")
        GUI:SameLine()
        if (T.timeline) then
            local m = T.timeline.meta
            RTL_UI_Text(tostring(m.name))
            GUI:SameLine()
            RTL_UI_Muted(string.format("%s  v%s", tostring(T.file), tostring(m.version)))
            if (#T.files > 1) then
                RTL_UI_Muted(T.manualPick and "手動で選択" or "戦闘開始時に自動で選択")
            end
        elseif (T.tlErr) then
            RTL_UI_Text(tostring(T.file).." 読めません", "error")
            RTL_UI_Text(T.tlErr, "error")
        else
            RTL_UI_Muted("なし（timelines\\"..tostring(T.mapid).."_*.lua）")
        end
        if (#T.files > 1) then
            for i, f in ipairs(T.files) do
                if (i > 1) then GUI:SameLine(0, 4) end
                if (RTL_UI_Button(f.."##tlfile"..i, (f == T.file) and "primary" or nil, true)) then
                    RTL_TL_Reload(T.mapid, f)
                end
            end
        end
        for _, w in ipairs(T.tlWarn) do
            RTL_UI_Text("注意: "..w, "warning")
        end
        -- ポジション
        RTL_UI_Muted("ジョブ")
        GUI:SameLine()
        RTL_UI_Badge(RTL_TL_JobName(), "info")
        GUI:SameLine()
        RTL_UI_Muted("ポジション")
        local items = {}
        for _, pos in ipairs(RTL.TL.positions) do
            items[#items + 1] = { pos, pos }
        end
        local pick = RTL_UI_Segmented("pos", items, RTL.settings.position)
        if (pick) then
            RTL.settings.position = (RTL.settings.position == pick) and nil or pick
            RTL_SaveSettings()
            RTL_TL_ChangePlan()
        end
        RTL_UI_Title("プラン")
        GUI:SameLine()
        if (T.plan) then
            RTL_UI_Text("plans\\"..tostring(T.mapid).."\\"..tostring(T.planFile))
            GUI:SameLine()
            RTL_UI_Badge(#T.plan.entries.." 件", "neutral")
            if ((T.planSounds or 0) > 0) then
                GUI:SameLine()
                RTL_UI_Badge("音 "..T.planSounds.." 件", "accent")
            end
        elseif (T.planErr) then
            RTL_UI_Text(tostring(T.planFile).." 読めません: "..T.planErr, "error")
        else
            RTL_UI_Muted("なし（"..RTL_TL_JobName().."_"..tostring(RTL.settings.position or "ANY")..".lua -> "..RTL_TL_JobName().."_ANY.lua）")
        end
        for _, w in ipairs(T.planWarn) do
            RTL_UI_Text("注意: "..w, "warning")
        end
        if (RTL_UI_Button("読み直す##tlreload", nil, true)) then
            RTL_TL_Reload(Player and Player.localmapid or 0, T.manualPick and T.file or nil)
        end
        GUI:SameLine()
        if (RTL_UI_Button("編集##peopen", RTL.pe.open and "primary" or nil, true)) then
            RTL.pe.open = not RTL.pe.open
            RTL_SaveSettings()
        end
    end)
    -- 戦闘
    local pull = T.pull
    RTL_UI_Card("dry_pull", function()
        if (pull) then
            local cur = pull.cur and pull.phases[pull.cur]
            RTL_UI_Title("フェーズ")
            GUI:SameLine()
            if (cur) then
                RTL_UI_Badge(pull.cur, "primary")
                GUI:SameLine()
                RTL_UI_Text(string.format("%s  時計 %.1f 秒", tostring(cur.def.name or ""), (now - cur.startMs) / 1000))
                if (cur.synced) then
                    GUI:SameLine()
                    RTL_UI_Badge("同期済み", "success")
                end
            else
                RTL_UI_Muted("（まだ入っていません）")
            end
            RTL_UI_Muted(string.format("戦闘開始から %.1f 秒（t0 = %s）   照合 %d / 同期 %d / 未照合 %d",
                (now - pull.t0Ms) / 1000, pull.t0src, pull.stats.matched, pull.stats.syncs, pull.stats.nomatch))
            local ev, evMs = RTL_TL_NextEvent(now)
            RTL_UI_Muted("次のイベント")
            GUI:SameLine()
            if (ev) then
                RTL_UI_Text(RTL_TL_EventLabel(ev))
                GUI:SameLine()
                RTL_UI_Muted(string.format("あと %.1f 秒（着弾 %.1f 秒）", (evMs - now) / 1000, (evMs - now) / 1000 + ev.cast))
            else
                RTL_UI_Muted("なし")
            end
            local rt, rtMs = RTL_TL_NextEntry(now)
            RTL_UI_Muted("次のアクション")
            GUI:SameLine()
            if (rt) then
                RTL_UI_Text(RTL_TL_ActionLabel(rt.entry), "own")
                GUI:SameLine()
                RTL_UI_Muted(string.format("-> %s  あと %.1f 秒%s", RTL_TL_EventLabel(rt.ev), (rtMs - now) / 1000,
                    (RTL_EX_EntryMode(rt.entry) == "exec") and "" or "（ドライラン）"))
            else
                RTL_UI_Muted("なし")
            end
            for _, w in ipairs(pull.entries) do
                if (w.status == "retry" and w.waitWhy) then
                    RTL_UI_Text(string.format("待っている: %s（%s）", RTL_TL_ActionLabel(w.entry), w.waitWhy), "warning")
                elseif (w.status == "casting") then
                    RTL_UI_Text(string.format("確認待ち: %s（Cast から %.1f 秒）", RTL_TL_ActionLabel(w.entry), (now - w.castMs) / 1000), "info")
                end
            end
            if (pull.ex) then
                local s = pull.ex.stats
                RTL_UI_Muted(string.format("自分のアクション %d（RaidTimeline %d）  成功 %d / 応答なし %d / 他が先 %d / 二重 %d / GCD 遅れ %d",
                    s.use, s.rtl, s.success, s.noresp, s.otherFirst, s.double, s.gcdDelay))
            end
        else
            if (T.skipped) then
                RTL_UI_Badge("道中", "neutral")
                GUI:SameLine()
                RTL_UI_Muted("戦闘中：タイムラインの敵がいないので、ドライランしていません")
            else
                RTL_UI_Badge("待機中", "neutral")
                GUI:SameLine()
                RTL_UI_Muted("戦闘が始まり、タイムラインの敵がいればドライランします")
            end
            local lp = T.lastPull
            if (lp) then
                RTL_UI_Muted("前回")
                GUI:SameLine()
                RTL_UI_Text(lp.file)
                GUI:SameLine()
                RTL_UI_Badge(tostring(lp.result), RTL_ResultTone(lp.result))
                GUI:SameLine()
                RTL_UI_Muted(string.format("%.0f 秒", lp.dur))
                RTL_UI_Muted(string.format("照合 %d 件  平均ずれ %.2f 秒  最大 %.2f 秒 / 同期 %d（範囲外 %d）/ 未照合 %d",
                    lp.matched, lp.avg, lp.max, lp.syncs, lp.syncSkip, lp.nomatch))
                for k, n in pairs(lp.dry) do
                    RTL_UI_Text(k..": "..n)
                end
                if (lp.ex and lp.ex ~= "") then
                    RTL_UI_Muted("アクション: "..lp.ex)
                end
            end
        end
    end)
    if (#T.recent > 0) then
        RTL_UI_Card("dry_recent", function()
            RTL_UI_Title("直近の結果")
            for _, s in ipairs(T.recent) do
                RTL_UI_Muted(s)
            end
        end)
    end
    -- タイムライン表示・見た目の設定
    if (GUI:CollapsingHeader("タイムライン表示の設定##tvset")) then
        RTL_UI_Card("dry_tvset", RTL_TV_DrawSettings)
    end
    if (GUI:CollapsingHeader("見た目（背景の透明度・文字の大きさ）##lookset")) then
        RTL_UI_Card("dry_look", RTL_UI_DrawLookSettings)
    end
end

-- ポジション・ジョブを変えたとき：プランを読み直し、戦闘中なら今のフェーズの残りから並べ直す
function RTL_TL_ChangePlan()
    local T = RTL.tl
    RTL_TL_LoadPlan()
    local pull = T.pull
    if (not pull) then
        return
    end
    local now = RTL_Now()
    local keep = {}
    for _, rt in ipairs(pull.entries) do
        if (rt.status == "done" or rt.status == "casting") then
            keep[#keep + 1] = rt
        end
    end
    pull.entries = keep
    local skeep = {}
    for _, sr in ipairs(pull.sounds) do
        if (sr.status == "done") then
            skeep[#skeep + 1] = sr
        end
    end
    pull.sounds = skeep
    local cur = pull.cur and pull.phases[pull.cur]
    if (cur) then
        RTL_TL_AddEntries(cur.def, now)
        -- すでに実行時刻を過ぎたものは、新しいプランでは扱わない
        for _, rt in ipairs(pull.entries) do
            if (rt.status == "wait") then
                local ms = RTL_TL_ExecMs(rt)
                if (ms and ms < now) then
                    rt.status = "done"
                    rt.result = "途中から（プラン変更）"
                end
            end
        end
        for _, sr in ipairs(pull.sounds) do
            if (sr.status == "wait") then
                local ms = RTL_TL_ExecMs(sr)
                if (ms and ms < now) then
                    sr.status = "done"
                    sr.result = "途中から（プラン変更）"
                end
            end
        end
    end
    RTL_TL_Row("plan_change", { ms = now, detail = tostring(T.planFile) })
end

-- =====================================================================
-- タイムライン表示（v0.5.0。設計書 10.3）：次に来る技を、技名・残り秒数・バーで並べる別ウィンドウ
--
--   データはドライランのもの（今のフェーズの時計・イベントの予定時刻（照合したら実測）・詠唱時間・照合・自分のエントリ）
--   残り秒数は「着弾」（詠唱開始 ＋ cast）まで。0 になったら消えて次が詰まる
--   表示する件数（tvCount）と秒数の範囲（tvRange）の、先に当たった方で打ち切る
--   バーの減り方（tvBar）："range"＝範囲に対する残り時間（長さで比べられる）／"each"＝技ごとに、表示に入ったときを 100% として減る
--   詠唱中（tvCast）："cast"＝詠唱が始まったら、詠唱時間に対する残りのバーに変える（バッジ「詠唱中」）／"keep"＝そのまま
--   分岐（match.action が配列）：照合するまでは「A / B」、照合したら実際に来た方の技名（バッジ「分岐」は照合まで）
--   同じ時刻の技（tvMerge）：詠唱開始が 0.5 秒以内のイベントは 1 行にまとめる（発射役が同時に詠唱するもの）
--   色（tvSteps・tvFar）：残り時間の区切りと色（初期値 5 秒以内オレンジ・10 秒以内ブルー・それより先グリーン）
--   自分のアクション（tvOwn）：技の行の下に、その技を基準にするエントリ（アクション・音）と判定の結果（技の行が消えるまで出す）
--   戦闘外・道中（ドライランしていないとき）は見出しだけ
--   位置（tvX / tvY）と幅（tvWidth）は settings.lua に保存。「位置を固定」（tvLock）でクリックを通し、動かなくする
-- =====================================================================

RTL.TV = {
    mergeSec   = 0.5,
    steps      = "5:F59E3B,10:4A9BF0",
    far        = "34C584",
    barH       = 6,
}
RTL.tv = RTL.tv or { seen = {}, stamp = nil, posApplied = false }

-- 残り時間の区切り（"5:F59E3B,10:4A9BF0" → { { sec = 5, rgb = {...} }, ... } 秒の小さい順）
function RTL_TV_ParseSteps(s)
    local out = {}
    if (type(s) == "string") then
        for sec, hex in s:gmatch("([%d%.]+):#?(%x%x%x%x%x%x)") do
            local n = tonumber(sec)
            local c = RTL_UI_Hex(hex)
            if (n and n > 0 and c) then
                out[#out + 1] = { sec = n, rgb = c }
            end
        end
    end
    table.sort(out, function(a, b) return a.sec < b.sec end)
    return out
end

function RTL_TV_StepsText(steps)
    local t = {}
    for _, st in ipairs(steps) do
        t[#t + 1] = RTL_Dec1(st.sec):gsub("%.0$", "")..":"..RTL_UI_ToHex(st.rgb)
    end
    return table.concat(t, ",")
end

function RTL_TV_Steps()
    local s = RTL.settings.tvSteps or RTL.TV.steps
    local tv = RTL.tv
    if (tv.stepsSrc ~= s) then
        tv.stepsSrc = s
        tv.steps = RTL_TV_ParseSteps(s)
    end
    return tv.steps
end

function RTL_TV_Color(remainSec)
    for _, st in ipairs(RTL_TV_Steps()) do
        if (remainSec <= st.sec) then
            return st.rgb
        end
    end
    return RTL_UI_Hex(RTL.settings.tvFar or RTL.TV.far) or RTL.UI.col.success
end

-- 技名：タイムラインの actions ＞ names/actions.lua ＞ ゲームの技名 ＞ "#ID"
function RTL_TV_ActName(id)
    local tl = RTL.tl.timeline
    return (tl and tl.actions and tl.actions[id]) or (RTL.names.actions and RTL.names.actions[id])
        or RTL_TL_GameActionName(id) or ("#"..tostring(id))
end

-- イベントの表示名と、分岐（照合前）かどうか
--   仮名（「38383 #1」「45341/45336 #1」「38345+38346 #1」）なら技名で出す。役割名（手で付けた名前）はそのまま
--   分岐は、照合前は「A / B」、照合したら実際の技名。役割名の分岐は「役割名（A / B）」
function RTL_TV_EventName(ev, m)
    local name = tostring(ev.name or ev.id)
    local prov = name:match("^[%d/%+]+ #%d+$") ~= nil
    local acts = ev.match and ev.match.action
    local list = (type(acts) == "table") and acts or (acts and { acts }) or {}
    local together = name:find("+", 1, true) ~= nil or tostring(ev.id):find("and", 1, true) ~= nil
    local branch = (#list > 1) and not together
    local tech
    if (m and m.spell and not together) then
        tech = RTL_TV_ActName(m.spell)
    elseif (#list > 0) then
        local names, seen = {}, {}
        for _, a in ipairs(list) do
            local n = RTL_TV_ActName(a)
            if (not seen[n]) then
                seen[n] = true
                names[#names + 1] = n
            end
        end
        tech = table.concat(names, together and " + " or " / ")
    end
    local isBranch = branch and not m
    if (prov) then
        return tech or name, isBranch
    end
    if (branch and tech) then
        return name.."（"..tech.."）", isBranch
    end
    return name, isBranch
end

-- 自分のエントリの状態 → バッジの文字と色
function RTL_TV_EntryBadge(rt)
    local st = rt.status
    if (st == "wait") then
        local mode = RTL_EX_EntryMode(rt.entry)
        return (mode == "exec") and "予定" or "予定（ドライラン）", "neutral"
    elseif (st == "retry") then
        return rt.waitWhy and ("待機："..rt.waitWhy) or "リキャスト待ち", "warning"
    elseif (st == "casting") then
        return "確認待ち", "info"
    end
    local r = tostring(rt.result or "")
    if (r:find("^実行")) then
        return r, "success"
    elseif (r:find("^達成済み") or r:find("^同等効果") or r:find("^直前に使用済み")) then
        return r, "info"
    elseif (r:find("^未実行") or r:find("^未確認")) then
        return r, "error"
    end
    return r, "neutral"
end

function RTL_TV_SoundBadge(sr)
    local st = sr.status
    if (st == "wait") then
        return "予定", "neutral"
    elseif (st == "waitmatch") then
        return "照合を待つ", "accent"
    end
    local r = tostring(sr.result or "")
    if (r:find("^鳴らした")) then
        return r, "success"
    elseif (r:find("^鳴らせない")) then
        return r, "error"
    end
    return r, "neutral"
end

-- 音のエントリの表示：分岐の音は、照合するまで「a.wav / b.wav」、照合したら鳴らす（鳴らした）ファイル
function RTL_TV_SoundName(sr, m)
    local snd = sr.entry.snd
    if (not snd) then
        return "音"
    end
    if (snd.byAction and m and m.spell) then
        return "音 "..tostring(snd.byAction[m.spell] or snd.file or "なし")
    end
    return "音 "..table.concat(RTL_SND_EntryFiles(snd), " / ")
end

-- 表示する内容を作る（描画とは分ける：模擬環境で中身を確かめられるように）
--   戻り値 { state = "none"/"off"/"idle"/"skip"/"pull", title, phase, clock, synced, rows = { ... } }
function RTL_TV_Build(now)
    local T = RTL.tl
    local S = RTL.settings
    local view = { rows = {} }
    local tl = T.timeline
    view.title = (tl and tl.meta and tl.meta.name) or T.file or "RaidTimeline"
    if (not RTL_TL_Enabled()) then
        view.state = "off"
        return view
    end
    if (not tl) then
        view.state = "none"
        view.title = "RaidTimeline"
        return view
    end
    local pull = T.pull
    if (not pull) then
        view.state = T.skipped and "skip" or "idle"
        return view
    end
    view.state = "pull"
    -- プルが変わったら「表示に入った時刻」を忘れる
    local tv = RTL.tv
    if (tv.stamp ~= pull) then
        tv.stamp = pull
        tv.seen = {}
    end
    local cur = pull.cur and pull.phases[pull.cur]
    view.t = (now - pull.t0Ms) / 1000
    if (not cur) then
        return view
    end
    view.phase = pull.cur
    view.phaseName = cur.def.name
    view.clock = (now - cur.startMs) / 1000
    view.synced = cur.synced
    local range = (tonumber(S.tvRange) or 60) * 1000
    local count = math.max(1, math.floor(tonumber(S.tvCount) or 5))
    -- 今のフェーズのイベントで、まだ着弾していないもの
    local items = {}
    for _, ev in ipairs(cur.def.events) do
        local st, hit, matched = RTL_TL_EventTimes(ev, pull.cur)
        if (st and hit > now and hit - now <= range) then
            items[#items + 1] = { ev = ev, st = st, hit = hit, matched = matched }
        end
    end
    table.sort(items, function(a, b)
        if (a.st ~= b.st) then return a.st < b.st end
        return a.hit < b.hit
    end)
    -- 同じ時刻の技をまとめる
    local groups = {}
    local mergeMs = (S.tvMerge ~= false) and RTL.TV.mergeSec * 1000 or -1
    for _, it in ipairs(items) do
        local g = groups[#groups]
        if (g and it.st - g.st <= mergeMs) then
            g.items[#g.items + 1] = it
            if (it.hit < g.hit) then g.hit = it.hit end
        else
            groups[#groups + 1] = { st = it.st, hit = it.hit, items = { it } }
        end
    end
    local castBar = (S.tvCast ~= "keep")
    for gi, g in ipairs(groups) do
        if (#view.rows >= count) then
            break
        end
        local names, seenName, branch, matchedAny = {}, {}, false, false
        local ids = {}
        for _, it in ipairs(g.items) do
            local m = pull.matches[it.ev.id]
            local n, isBranch = RTL_TV_EventName(it.ev, m)
            if (not seenName[n]) then
                seenName[n] = true
                names[#names + 1] = n
            end
            if (isBranch) then branch = true end
            if (m) then matchedAny = true end
            ids[it.ev.id] = true
        end
        -- 名前の取れない技（#ID。発射役など）は、名前のある技と一緒なら出さない
        if (#names > 1) then
            local named = {}
            for _, n in ipairs(names) do
                if (not n:match("^[#%d%s/%+]+$")) then named[#named + 1] = n end
            end
            if (#named > 0) then names = named end
        end
        local key = g.items[1].ev.id
        local seenMs = tv.seen[key]
        if (not seenMs) then
            seenMs = now
            tv.seen[key] = now
        end
        local remain = (g.hit - now) / 1000
        local casting = matchedAny and now >= g.st
        local frac
        if (casting and castBar and g.hit > g.st) then
            frac = (g.hit - now) / (g.hit - g.st)
        elseif (S.tvBar == "each") then
            frac = (g.hit - now) / math.max(1, g.hit - seenMs)
        else
            frac = (g.hit - now) / range
        end
        local row = {
            label = table.concat(names, " + "), remain = remain, frac = math.max(0, math.min(1, frac)),
            color = RTL_TV_Color(remain), casting = casting, branch = branch, matched = matchedAny,
            late = (not matchedAny) and now > g.st + 500 and g.items[1].ev.match ~= nil,
            ids = ids, own = {},
        }
        -- 自分のアクション・音
        if (S.tvOwn ~= false) then
            for _, rt in ipairs(pull.entries) do
                if (ids[rt.ev.id] and rt.phase == pull.cur) then
                    local execMs = RTL_TL_ExecMs(rt)
                    local text, tone = RTL_TV_EntryBadge(rt)
                    row.own[#row.own + 1] = { kind = "action", label = RTL_TL_ActionLabel(rt.entry),
                        remain = execMs and (execMs - now) / 1000 or nil, badge = text, tone = tone, status = rt.status }
                end
            end
            for _, sr in ipairs(pull.sounds or {}) do
                if (ids[sr.ev.id] and sr.phase == pull.cur) then
                    local execMs = RTL_TL_ExecMs(sr)
                    local text, tone = RTL_TV_SoundBadge(sr)
                    row.own[#row.own + 1] = { kind = "sound", label = RTL_TV_SoundName(sr, pull.matches[sr.ev.id]),
                        remain = execMs and (execMs - now) / 1000 or nil, badge = text, tone = tone, status = sr.status }
                end
            end
        end
        view.rows[#view.rows + 1] = row
    end
    return view
end

-- ---------------------------------------------------------------------
-- 描画
-- ---------------------------------------------------------------------

function RTL_TV_Draw(event, ticks)
    if (not RTL.initDone or RTL.settings.tvShow == false) then
        return
    end
    local S = RTL.settings
    local tv = RTL.tv
    local flags = RTL_UI_Flags("NoTitleBar", "NoResize", "NoScrollbar", "NoCollapse", "AlwaysAutoResize", "NoFocusOnAppearing")
    if (S.tvLock == true) then
        flags = flags + RTL_UI_Flags("NoInputs", "NoMove", "NoBringToFrontOnFocus")
        GUI:SetNextWindowPos(S.tvX, S.tvY, GUI.SetCond_Always)
        tv.posApplied = false
    elseif (not tv.posApplied) then
        GUI:SetNextWindowPos(S.tvX, S.tvY, GUI.SetCond_Always)
        tv.posApplied = true
    end
    RTL_UI_Window("RaidTimeline##timelineview", true, flags, RTL_TV_DrawBody,
        { alpha = S.tvAlpha, scale = S.uiScale, where = "DrawTV" })
end

function RTL_TV_DrawBody()
    local S = RTL.settings
    local now = RTL_Now()
    -- 位置を固定していないときは、動かした位置を覚える（マウスを放してから）
    if (S.tvLock ~= true) then
        local wx, wy = GUI:GetWindowPos()
        if (type(wx) == "number" and (math.abs(wx - S.tvX) > 0.5 or math.abs(wy - S.tvY) > 0.5) and not GUI:IsMouseDown(0)) then
            S.tvX, S.tvY = math.floor(wx + 0.5), math.floor(wy + 0.5)
            RTL_UI_SaveLater()
        end
    end
    local view = RTL_TV_Build(now)
    RTL.tv.last = view
    local w = math.max(160, tonumber(S.tvWidth) or 320)
    local lineH = tonumber(GUI:GetTextLineHeight()) or 14
    -- 見出し：タイトル・バッジ・右に時計
    local x, y = GUI:GetCursorScreenPos()
    local right
    local badges = {}
    if (view.state == "pull") then
        if (view.phase) then
            badges[#badges + 1] = { view.phase, "primary" }
            if (view.synced) then badges[#badges + 1] = { "同期済み", "success" } end
            right = string.format("%.1f", view.clock)
        else
            badges[#badges + 1] = { "フェーズ待ち", "neutral" }
        end
    elseif (view.state == "idle") then
        badges[#badges + 1] = { "待機中", "neutral" }
    elseif (view.state == "skip") then
        badges[#badges + 1] = { "道中", "neutral" }
    elseif (view.state == "off") then
        badges[#badges + 1] = { "ドライラン OFF", "warning" }
    else
        badges[#badges + 1] = { "タイムラインなし", "neutral" }
    end
    local rightW = right and (RTL_UI_TextW(right) or 0) or 0
    local badgeW = 0
    for _, b in ipairs(badges) do
        badgeW = badgeW + (RTL_UI_TextW(b[1]) or 0) + 18
    end
    local title = RTL_UI_Fit(view.title, math.max(40, w - badgeW - rightW - 12))
    GUI:AddText(x, y, RTL_UI_U32("text"), title)
    local bx = x + (RTL_UI_TextW(title) or 0) + 8
    for _, b in ipairs(badges) do
        bx = bx + RTL_UI_PillAt(bx, y, b[1], b[2]) + 6
    end
    if (right) then
        GUI:AddText(x + w - rightW, y, RTL_UI_U32("muted"), right)
    end
    GUI:Dummy(w, lineH)
    if (view.state ~= "pull" or not view.phase) then
        return
    end
    if (#view.rows == 0) then
        RTL_UI_Muted(string.format("%d 秒以内に来る技はありません", math.floor(tonumber(S.tvRange) or 60)))
        return
    end
    GUI:Dummy(w, 2)
    for i, r in ipairs(view.rows) do
        RTL_TV_DrawRow(r, w, lineH)
    end
end

function RTL_TV_DrawRow(r, w, lineH)
    local x, y = GUI:GetCursorScreenPos()
    local sec = string.format("%.1f", math.max(0, r.remain))
    local secW = RTL_UI_TextW(sec) or 0
    -- バッジ
    local badges = {}
    if (r.casting) then badges[#badges + 1] = { "詠唱中", "warning" } end
    if (r.branch) then badges[#badges + 1] = { "分岐", "accent" } end
    if (r.late) then badges[#badges + 1] = { "遅れ", "neutral" } end
    local badgeW = 0
    for _, b in ipairs(badges) do
        badgeW = badgeW + (RTL_UI_TextW(b[1]) or 0) + 18
    end
    local name = RTL_UI_Fit(r.label, math.max(40, w - secW - badgeW - 12))
    GUI:AddText(x, y, RTL_UI_U32("text"), name)
    local bx = x + (RTL_UI_TextW(name) or 0) + 8
    for _, b in ipairs(badges) do
        bx = bx + RTL_UI_PillAt(bx, y, b[1], b[2]) + 6
    end
    GUI:AddText(x + w - secW, y, RTL_UI_U32(r.color), sec)
    local barH = RTL.TV.barH
    local by = y + lineH + 3
    RTL_UI_BarAt(x, by, w, barH, r.frac, r.color)
    local h = lineH + 3 + barH + 6
    -- 自分のアクション・音
    for _, o in ipairs(r.own) do
        local oy = y + h
        local ox = x + 12
        local label = o.label
        local tone = (o.kind == "sound") and "accent" or "own"
        local rem = ""
        if (o.remain and o.status ~= "done" and o.remain > -0.05) then
            rem = string.format("あと %.1f", math.max(0, o.remain))
        end
        local bw = (RTL_UI_TextW(o.badge) or 0) + 12
        local remW = (rem ~= "") and ((RTL_UI_TextW(rem) or 0) + 8) or 0
        local lab = RTL_UI_Fit(label, math.max(30, w - 12 - bw - remW - 8))
        GUI:AddText(ox, oy, RTL_UI_U32(tone), lab)
        local lx = ox + (RTL_UI_TextW(lab) or 0) + 8
        if (rem ~= "") then
            GUI:AddText(lx, oy, RTL_UI_U32("muted"), rem)
        end
        RTL_UI_PillAt(x + w - bw, oy, o.badge, o.tone)
        h = h + lineH + 4
    end
    GUI:Dummy(w, h)
end

-- ---------------------------------------------------------------------
-- 設定（ドライランの画面の「タイムライン表示」）
-- ---------------------------------------------------------------------

function RTL_TV_SetSetting(k, v)
    if (RTL.settings[k] ~= v) then
        RTL.settings[k] = v
        RTL_UI_SaveLater()
    end
end

function RTL_TV_DrawSettings()
    local S = RTL.settings
    local v, p = RTL_UI_Toggle("表示する##tvshow", S.tvShow ~= false)
    if (p) then RTL_TV_SetSetting("tvShow", v) end
    GUI:SameLine()
    v, p = RTL_UI_Toggle("位置を固定（クリックを通す）##tvlock", S.tvLock == true)
    if (p) then RTL_TV_SetSetting("tvLock", v) end
    GUI:SameLine()
    if (RTL_UI_Button("位置を戻す##tvpos", nil, true)) then
        S.tvX, S.tvY = RTL.TV_DEFAULT.tvX, RTL.TV_DEFAULT.tvY
        RTL.tv.posApplied = false
        RTL_UI_SaveLater()
    end
    -- 件数
    RTL_UI_Muted("件数")
    GUI:SameLine()
    local pick = RTL_UI_Segmented("tvcnt", { { 3, "3" }, { 5, "5" }, { 10, "10" } }, S.tvCount)
    if (pick) then RTL_TV_SetSetting("tvCount", pick) end
    GUI:SameLine()
    GUI:PushItemWidth(120)
    local n, ch = GUI:SliderInt("##tvcount", math.floor(tonumber(S.tvCount) or 5), 1, 20)
    GUI:PopItemWidth()
    if (ch and type(n) == "number") then RTL_TV_SetSetting("tvCount", n) end
    -- 範囲
    RTL_UI_Muted("範囲")
    GUI:SameLine()
    pick = RTL_UI_Segmented("tvrng", { { 30, "30 秒" }, { 60, "60 秒" }, { 120, "120 秒" } }, S.tvRange)
    if (pick) then RTL_TV_SetSetting("tvRange", pick) end
    GUI:SameLine()
    GUI:PushItemWidth(120)
    n, ch = GUI:SliderInt("##tvrange", math.floor(tonumber(S.tvRange) or 60), 10, 300, "%d 秒")
    GUI:PopItemWidth()
    if (ch and type(n) == "number") then RTL_TV_SetSetting("tvRange", n) end
    -- バーの減り方・詠唱中
    RTL_UI_Muted("バー")
    GUI:SameLine()
    pick = RTL_UI_Segmented("tvbar", { { "range", "範囲に対する残り時間" }, { "each", "技ごとに 100% から" } }, S.tvBar)
    if (pick) then RTL_TV_SetSetting("tvBar", pick) end
    RTL_UI_Muted("詠唱中")
    GUI:SameLine()
    pick = RTL_UI_Segmented("tvcast", { { "cast", "詠唱バーに切り替える" }, { "keep", "そのまま" } }, S.tvCast)
    if (pick) then RTL_TV_SetSetting("tvCast", pick) end
    v, p = RTL_UI_Toggle("自分のアクションを出す##tvown", S.tvOwn ~= false)
    if (p) then RTL_TV_SetSetting("tvOwn", v) end
    GUI:SameLine()
    v, p = RTL_UI_Toggle("同じ時刻の技をまとめる##tvmerge", S.tvMerge ~= false)
    if (p) then RTL_TV_SetSetting("tvMerge", v) end
    GUI:PushItemWidth(180)
    n, ch = GUI:SliderInt("幅##tvwidth", math.floor(tonumber(S.tvWidth) or 320), 200, 640)
    GUI:PopItemWidth()
    if (ch and type(n) == "number") then RTL_TV_SetSetting("tvWidth", n) end
    -- 色の区切り
    GUI:Spacing()
    RTL_UI_Title("バーの色（残り時間）")
    local steps = RTL_TV_ParseSteps(S.tvSteps or RTL.TV.steps)
    local changed, remove = false, nil
    local cflags = 0
    for _, k in ipairs({ "NoInputs", "NoLabel" }) do
        local f = GUI["ColorEditMode_"..k]
        if (type(f) == "number") then cflags = cflags + f end
    end
    for i, st in ipairs(steps) do
        GUI:PushItemWidth(150)
        local sec, sch = GUI:SliderFloat("##tvstepsec"..i, st.sec, 0.5, 60, "%.1f 秒以内")
        GUI:PopItemWidth()
        if (sch and type(sec) == "number") then st.sec = math.floor(sec * 10 + 0.5) / 10 changed = true end
        GUI:SameLine()
        local r, g, b, cch = GUI:ColorEdit3("##tvstepcol"..i, st.rgb[1], st.rgb[2], st.rgb[3], cflags)
        if (cch and type(r) == "number") then st.rgb = { r, g, b } changed = true end
        GUI:SameLine()
        if (RTL_UI_Button("消す##tvstepdel"..i, nil, true)) then remove = i end
    end
    RTL_UI_Muted("それより先")
    GUI:SameLine()
    local far = RTL_UI_Hex(S.tvFar or RTL.TV.far) or RTL.UI.col.success
    local r, g, b, cch = GUI:ColorEdit3("##tvfar", far[1], far[2], far[3], cflags)
    if (cch and type(r) == "number") then RTL_TV_SetSetting("tvFar", RTL_UI_ToHex({ r, g, b })) end
    GUI:SameLine()
    if (RTL_UI_Button("段階を足す##tvstepadd", nil, true)) then
        local last = steps[#steps]
        steps[#steps + 1] = { sec = last and (last.sec + 5) or 5, rgb = { 0.973, 0.443, 0.475 } }
        changed = true
    end
    GUI:SameLine()
    if (RTL_UI_Button("初期値に戻す##tvstepreset", nil, true)) then
        RTL_TV_SetSetting("tvSteps", RTL.TV.steps)
        RTL_TV_SetSetting("tvFar", RTL.TV.far)
    end
    if (remove) then
        table.remove(steps, remove)
        changed = true
    end
    if (changed) then
        table.sort(steps, function(a2, b2) return a2.sec < b2.sec end)
        RTL_TV_SetSetting("tvSteps", RTL_TV_StepsText(steps))
    end
end

-- 見た目（背景の透明度・文字の大きさ）
function RTL_UI_DrawLookSettings()
    local S = RTL.settings
    GUI:PushItemWidth(180)
    local a, ch = GUI:SliderFloat("タイムライン表示の背景##tvalpha", tonumber(S.tvAlpha) or 0.8, 0, 1, "%.2f")
    if (ch and type(a) == "number") then RTL_TV_SetSetting("tvAlpha", math.floor(a * 100 + 0.5) / 100) end
    a, ch = GUI:SliderFloat("画面の背景##uialpha", tonumber(S.uiAlpha) or 0.94, 0.3, 1, "%.2f")
    if (ch and type(a) == "number") then RTL_TV_SetSetting("uiAlpha", math.floor(a * 100 + 0.5) / 100) end
    a, ch = GUI:SliderFloat("文字の大きさ##uiscale", tonumber(S.uiScale) or 1, 0.8, 1.6, "%.2f")
    if (ch and type(a) == "number") then RTL_TV_SetSetting("uiScale", math.floor(a * 100 + 0.5) / 100) end
    GUI:PopItemWidth()
end

-- =====================================================================
-- プランの編集（v0.6.0。設計書 10.2）：プラン（plans/<mapid>/<job>_<pos>.lua）を画面で直す別ウィンドウ
--
--   目的：攻略中に「あのタイミングでは ○○ を使ってほしい」と言われたとき、その場でプランのスキルを変える
--   プランを選ぶ（v0.6.1）：plans\<mapid>\ の全部から選べる（コンテンツの外でも直せる）。選ばなければ今のプラン
--   画面：そのマップのタイムライン（全部。使っているものを先に）のフェーズ・イベントを並べ、各イベントの下に
--         自分のエントリ（アクション・タイミング・使う／使わない）を出す。エントリを押すと、その下に編集欄が開く
--   変えられるもの（ユーザーの決定）：アクション・offset（0.5 秒ずつ）・使わない（execute = false。ドライランだけになる）
--         v0.6.2：offset を数で入れる欄、対象（自分・今のターゲット・タイムラインの敵）、イベントにエントリを足す（「追加」）・消す
--         v0.6.3：音（wav フォルダの wav から選ぶ・試す・外す。分岐ごとの音 byAction は共通の音だけ変える）、音だけのエントリを足す、
--                 基準（詠唱開始／着弾）を選ぶ
--   アクションの一覧：ActionList:Get(1)（ffxivminion の SkillMgr.FillSkillBook と同じ取り方）から、今のジョブ（基本クラスも）の
--         アクション（job が一致するもの）と、ロールアクション・共通アクション（RTL.PE_ROLE の ID。v0.6.1）。
--         usable は敵のアクションにも付いていたので使わない（v0.6.0 の実機）。GCD と oGCD は別の区分・色（代表 GCD の
--         recasttime と比べる。実行と同じ見分け方）。ほかのジョブのプランは、アクションを変えられない（一覧が今のジョブのものなので）。
--         GCD は実行がまだ対応していないので、選んでも「未対応」と出すだけ（ユーザーの決定）
--   保存（ユーザーの決定）：変えたら 0.7 秒後に書く（戦闘中も）。書く前の版を plans/<mapid>/backup/ に 10 世代とっておき、
--         「元に戻す」で 1 つ前の版に戻す。書いたものは読み直して、画面の中身と同じかを確かめる（違えば前の版に戻す）
--   反映：書いたら RTL_TL_ChangePlan（ポジション変更と同じ。戦闘中なら今のフェーズの残りから並べ直す）
--   書き出し：return { format = 1, meta = ..., entries = ... }（UTF-8・CRLF）。ファイルの先頭のコメントは残し、
--         エントリの中のコメントは消える。別のエディタでファイルが変わっていたら、書かずに読み直す
-- =====================================================================

RTL.PE = {
    saveDelayMs = 700,     -- 変えてから書くまで
    keep        = 10,      -- 前の版を何世代とっておくか
    step        = 0.5,     -- offset を変える幅
    offsetMin   = -120,
    offsetMax   = 120,
    confirmMs   = 3000,    -- 「元に戻す」の確かめ（もう一度押すまで）
    -- 書き出すときのキーの順番
    topKeys     = { "format", "meta", "entries" },
    metaKeys    = { "mapid", "timeline", "timelineVersion", "job", "position" },
    entryLines  = { { "id", "event", "ref", "offset", "window" }, { "action", "target" } },
    entryKeys   = { "satisfiedBy", "recentSec", "execute", "priority", "onAction", "sound", "condition", "note" },
    decKeys     = { offset = true, window = true, recentSec = true },   -- 整数でも小数第 1 位で書く
    luaWords    = { ["and"] = 1, ["break"] = 1, ["do"] = 1, ["else"] = 1, ["elseif"] = 1, ["end"] = 1, ["false"] = 1,
                    ["for"] = 1, ["function"] = 1, ["goto"] = 1, ["if"] = 1, ["in"] = 1, ["local"] = 1, ["nil"] = 1,
                    ["not"] = 1, ["or"] = 1, ["repeat"] = 1, ["return"] = 1, ["then"] = 1, ["true"] = 1,
                    ["until"] = 1, ["while"] = 1 },
    editedMark  = "-- （プラン編集の画面で書き出し：",
}

RTL.pe = RTL.pe or { open = false }
RTL.pe.backups = RTL.pe.backups or {}    -- [プランのパス] = { 古い順のファイル名 }

-- ロールアクション・共通アクション（v0.6.1）。ActionList:Get(1) の job では見分けられないので ID で持つ（名前はゲームから取る）
--   ジョブ ID → ロール。ポーションなどのアイテムはアクションの一覧に無く、使い方も違う（GetItem）ので、ここには入れない
RTL.PE_ROLE_OF = {
    [1] = "tank", [3] = "tank", [19] = "tank", [21] = "tank", [32] = "tank", [37] = "tank",
    [6] = "healer", [24] = "healer", [28] = "healer", [33] = "healer", [40] = "healer",
    [2] = "melee", [4] = "melee", [20] = "melee", [22] = "melee", [29] = "melee", [30] = "melee", [34] = "melee", [39] = "melee", [41] = "melee",
    [5] = "ranged", [23] = "ranged", [31] = "ranged", [38] = "ranged",
    [7] = "caster", [25] = "caster", [26] = "caster", [27] = "caster", [35] = "caster", [36] = "caster", [42] = "caster",
}
RTL.PE_ROLE = {
    common = { 3 },                                                   -- スプリント
    tank   = { 7531, 7533, 7535, 7537, 7538, 7540, 7548 },            -- ランパート・挑発・リプライザル・シャーク・インタージェクト・ロウブロウ・アームズレングス
    healer = { 7559, 7561, 7562, 7568, 7571, 16560 },                 -- 堅実魔・迅速魔・ルーシッドドリーム・エスナ・救出・リポーズ
    melee  = { 7541, 7542, 7546, 7548, 7549, 7863 },                  -- 内丹・ブラッドバス・トゥルーノース・アームズレングス・牽制・足払い
    ranged = { 7541, 7548, 7551, 7553, 7554, 7557 },                  -- 内丹・アームズレングス・ヘッドグレイズ・フットグレイズ・レッググレイズ・ペロトン
    caster = { 7559, 7560, 7561, 7562, 25880 },                       -- 堅実魔・アドル・迅速魔・ルーシッドドリーム・スリープ
}

-- ---------------------------------------------------------------------
-- 書き出し（表 → 文字列）
-- ---------------------------------------------------------------------

-- 数：整数は %d（decKeys のキーは小数第 1 位）。小数は読み直して同じになる一番短い書き方
function RTL_PE_Num(v, key)
    if (v ~= v or v == math.huge or v == -math.huge) then
        return "0"
    end
    if (v == math.floor(v) and math.abs(v) < 1e15) then
        if (key and RTL.PE.decKeys[key]) then
            return string.format("%.1f", v)
        end
        return string.format("%d", v)
    end
    for n = 1, 6 do
        local s = string.format("%."..n.."f", v)
        if (tonumber(s) == v) then
            return s
        end
    end
    return string.format("%.17g", v)
end

function RTL_PE_Key(k)
    if (type(k) == "string" and k:match("^[%a_][%w_]*$") and not RTL.PE.luaWords[k]) then
        return k
    end
    if (type(k) == "number") then
        return "["..RTL_PE_Num(k).."]"
    end
    return "["..RTL_LuaString(k).."]"
end

-- 1..n が全部ある表（並べた値）か
function RTL_PE_IsList(t)
    local n = #t
    local c = 0
    for _ in pairs(t) do
        c = c + 1
    end
    return c == n, n
end

-- キーの順番：order にあるものを先に、残りは文字列・数の順に並べる
function RTL_PE_Keys(t, order)
    local keys, seen = {}, {}
    for _, k in ipairs(order or {}) do
        if (t[k] ~= nil) then
            keys[#keys + 1] = k
            seen[k] = true
        end
    end
    local rest = {}
    for k in pairs(t) do
        if (not seen[k]) then
            rest[#rest + 1] = k
        end
    end
    table.sort(rest, function(a, b)
        if (type(a) == type(b)) then
            return a < b
        end
        return type(a) == "number"
    end)
    for _, k in ipairs(rest) do
        keys[#keys + 1] = k
    end
    return keys
end

-- 値を 1 行で書く（表は { ... }）
function RTL_PE_Inline(v, key)
    local tv = type(v)
    if (tv == "number") then
        return RTL_PE_Num(v, key)
    elseif (tv == "string") then
        return RTL_LuaString(v)
    elseif (tv == "boolean") then
        return v and "true" or "false"
    elseif (tv == "table") then
        local isList, n = RTL_PE_IsList(v)
        local parts = {}
        if (isList) then
            for i = 1, n do
                parts[#parts + 1] = RTL_PE_Inline(v[i])
            end
        else
            for _, k in ipairs(RTL_PE_Keys(v)) do
                parts[#parts + 1] = RTL_PE_Key(k).." = "..RTL_PE_Inline(v[k], k)
            end
        end
        if (#parts == 0) then
            return "{}"
        end
        return "{ "..table.concat(parts, ", ").." }"
    end
    return "nil"
end

-- エントリ 1 つ（id〜window で 1 行、action・target で 1 行、残りは 1 項目 1 行）
function RTL_PE_EntryText(e, ind)
    local P = RTL.PE
    local lines, used = {}, {}
    for _, group in ipairs(P.entryLines) do
        local parts = {}
        for _, k in ipairs(group) do
            if (e[k] ~= nil) then
                parts[#parts + 1] = k.." = "..RTL_PE_Inline(e[k], k)
                used[k] = true
            end
        end
        if (#parts > 0) then
            lines[#lines + 1] = ind.."    "..table.concat(parts, ", ")..","
        end
    end
    local rest = {}
    for k in pairs(e) do
        if (not used[k]) then rest[k] = e[k] end
    end
    for _, k in ipairs(RTL_PE_Keys(rest, P.entryKeys)) do
        lines[#lines + 1] = ind.."    "..RTL_PE_Key(k).." = "..RTL_PE_Inline(rest[k], k)..","
    end
    return ind.."{\r\n"..table.concat(lines, "\r\n").."\r\n"..ind.."},"
end

-- プランの表 → ファイルの中身（head：先頭のコメント行）
function RTL_PE_Serialize(plan, head)
    local P = RTL.PE
    local out = {}
    for _, line in ipairs(head or {}) do
        out[#out + 1] = line
    end
    out[#out + 1] = P.editedMark..os.date("%Y-%m-%d %H:%M:%S").."。エントリの中のコメントは消えます）"
    out[#out + 1] = "return {"
    for _, k in ipairs(RTL_PE_Keys(plan, P.topKeys)) do
        local v = plan[k]
        if (k == "meta" and type(v) == "table") then
            out[#out + 1] = "    meta = {"
            for _, mk in ipairs(RTL_PE_Keys(v, P.metaKeys)) do
                out[#out + 1] = "        "..RTL_PE_Key(mk).." = "..RTL_PE_Inline(v[mk], mk)..","
            end
            out[#out + 1] = "    },"
        elseif (k == "entries" and type(v) == "table") then
            out[#out + 1] = ""
            out[#out + 1] = "    entries = {"
            local isList, n = RTL_PE_IsList(v)
            if (isList) then
                for i = 1, n do
                    if (type(v[i]) == "table") then
                        out[#out + 1] = RTL_PE_EntryText(v[i], "        ")
                    else
                        out[#out + 1] = "        "..RTL_PE_Inline(v[i])..","
                    end
                end
            else
                for _, ek in ipairs(RTL_PE_Keys(v)) do
                    out[#out + 1] = "        "..RTL_PE_Key(ek).." = "..RTL_PE_Inline(v[ek])..","
                end
            end
            out[#out + 1] = "    },"
        else
            out[#out + 1] = "    "..RTL_PE_Key(k).." = "..RTL_PE_Inline(v, k)..","
        end
    end
    out[#out + 1] = "}"
    return table.concat(out, "\r\n").."\r\n"
end

-- ファイルの先頭のコメント行（return より前）。前に書き出したときの印の行は除く
function RTL_PE_HeadLines(text)
    local head = {}
    if (type(text) ~= "string") then
        return head
    end
    if (text:sub(1, 3) == "\239\187\191") then
        text = text:sub(4)
    end
    for line in (text.."\n"):gmatch("([^\n]*)\n") do
        line = line:gsub("\r$", "")
        if (line:match("^%s*%-%-")) then
            if (line:sub(1, #RTL.PE.editedMark) ~= RTL.PE.editedMark) then
                head[#head + 1] = line
            end
        elseif (line:match("^%s*$")) then
            -- 空行は飛ばす
        else
            break
        end
    end
    return head
end

-- 2 つの表が同じ中身か（読み直しの確かめ用）
function RTL_PE_Same(a, b)
    if (type(a) ~= type(b)) then
        return false
    end
    if (type(a) == "number") then
        return math.abs(a - b) < 1e-9
    end
    if (type(a) ~= "table") then
        return a == b
    end
    for k, v in pairs(a) do
        if (not RTL_PE_Same(v, b[k])) then
            return false
        end
    end
    for k in pairs(b) do
        if (a[k] == nil) then
            return false
        end
    end
    return true
end

-- ---------------------------------------------------------------------
-- ファイル・前の版
-- ---------------------------------------------------------------------

-- 今のプランのパス（無ければ nil）
function RTL_PE_PlanPath()
    local T = RTL.tl
    if (not T.timeline or not T.planFile) then
        return nil
    end
    return RTL.path.."\\plans\\"..tostring(T.timeline.meta.mapid).."\\"..T.planFile, T.timeline.meta.mapid, T.planFile
end

function RTL_PE_BackupDir(mapid)
    return RTL.path.."\\plans\\"..tostring(mapid).."\\backup"
end

-- フォルダの中の「<prefix>*.lua」（RTL_TL_ListTimelines と同じ取り方：FolderList → dir /b）
function RTL_PE_ListDir(dir, prefix, ext)
    ext = ext or "lua"
    local extPat = ext:gsub("%a", function(c) return "["..c:lower()..c:upper().."]" end)
    local names, seen = {}, {}
    local function add(p)
        if (type(p) ~= "string") then return end
        local base = p:match("([^\\/]+)$") or p
        local nameOk = (ext == "lua") and base:match("^[%w_%-]+%.lua$") or base:match("^[^\\/:]+%."..extPat.."$")
        if (base:sub(1, #prefix) == prefix and nameOk and not seen[base]) then
            seen[base] = true
            names[#names + 1] = base
        end
    end
    local got = false
    if (type(FolderList) == "function") then
        local ok, list = pcall(FolderList, dir, prefix:gsub("%-", "%%-")..".*%."..extPat, false)
        if (ok and type(list) == "table") then
            for _, p in pairs(list) do add(p) end
            got = (#names > 0)
        end
    end
    if (not got and FolderExists and FolderExists(dir) and io.popen) then
        local ok, f = pcall(io.popen, 'dir /b /a-d "'..dir..'\\'..prefix..'*.'..ext..'" 2>nul')
        if (ok and f) then
            for line in f:lines() do add((line:gsub("[\r\n]", ""))) end
            f:close()
        end
    end
    table.sort(names)
    return names
end

-- 前の版の並べ方：名前の日時（YYYYMMDD_HHMMSS）、同じ秒なら _2, _3 …の番号の順（文字の順だと _10 が _2 より前になるため）
function RTL_PE_BackupKey(name)
    local d, t, n = tostring(name):match("_(%d%d%d%d%d%d%d%d)_(%d%d%d%d%d%d)_?(%d*)%.lua$")
    if (not d) then
        return "0"..tostring(name)
    end
    return d..t..string.format("%04d", tonumber(n) or 1)
end

function RTL_PE_SortBackups(list)
    table.sort(list, function(a, b) return RTL_PE_BackupKey(a) < RTL_PE_BackupKey(b) end)
end

-- そのプランの前の版の一覧（古い順）。1 回だけフォルダを見て、後は覚えておく
function RTL_PE_Backups(path, mapid, file)
    local P = RTL.pe
    local list = P.backups[path]
    if (not list) then
        local stem = file:gsub("%.lua$", "")
        list = {}
        for _, n in ipairs(RTL_PE_ListDir(RTL_PE_BackupDir(mapid), stem.."_")) do
            if (n:match("^"..stem:gsub("%-", "%%-").."_%d+_%d+[_%d]*%.lua$")) then
                list[#list + 1] = n
            end
        end
        RTL_PE_SortBackups(list)
        P.backups[path] = list
    end
    return list
end

-- 書く前の版をとっておく（古いものは keep 世代を超えたら消す）
function RTL_PE_SaveBackup(path, mapid, file, text)
    local dir = RTL_PE_BackupDir(mapid)
    RTL_EnsureFolder(dir)
    local list = RTL_PE_Backups(path, mapid, file)
    local stem = file:gsub("%.lua$", "")
    local base = stem.."_"..os.date("%Y%m%d_%H%M%S")
    local name, n = base..".lua", 1
    local used = {}
    for _, x in ipairs(list) do used[x] = true end
    while (used[name]) do
        n = n + 1
        name = base.."_"..n..".lua"
    end
    if (not RTL_WriteFile(dir.."\\"..name, text)) then
        return nil
    end
    list[#list + 1] = name
    RTL_PE_SortBackups(list)
    while (#list > RTL.PE.keep) do
        local old = table.remove(list, 1)
        pcall(os.remove, dir.."\\"..old)
    end
    return name
end

-- ---------------------------------------------------------------------
-- 読み込み（画面で直すための元の表）
-- ---------------------------------------------------------------------

-- 今のプランのファイルをそのまま読む（RTL_TL_LoadPlan は既定値を足すので、書き出しには使わない）
-- 直すプラン：選んだもの（P.manual）か、今のプラン
function RTL_PE_Target()
    local m = RTL.pe.manual
    if (m) then
        return m.path, m.mapid, m.file
    end
    return RTL_PE_PlanPath()
end

function RTL_PE_Sync()
    local P = RTL.pe
    local path, mapid, file = RTL_PE_Target()
    if (path ~= P.path) then
        -- 別のプランに変わった：保存待ちがあれば、先に元のファイルに書く
        if (P.saveAt and P.path) then
            RTL_PE_SaveNow(RTL_Now())
        end
        RTL_PE_Load(path, mapid, file)
        P.planObj = RTL.tl.plan
        return
    end
    -- プランが読み直された（保存・読み直す・ほかの画面の読み直し）：保存待ちが無ければ、ファイルから読み直す（選んだ行は残す）
    if (RTL.tl.plan ~= P.planObj) then
        P.planObj = RTL.tl.plan
        if (not P.saveAt) then
            RTL_PE_Load(path, mapid, file)
        end
    end
end

function RTL_PE_Load(path, mapid, file)
    local P = RTL.pe
    local keepSel = (path ~= nil and path == P.path)     -- 同じファイルを読み直すときは、選んだ行・一覧の開閉を残す
    P.path, P.mapid, P.file = path, mapid, file
    P.raw, P.err, P.diskText, P.head = nil, nil, nil, {}
    P.saveAt, P.changes = nil, {}
    if (not keepSel) then
        P.sel, P.pick = nil, nil
    end
    if (not path) then
        return
    end
    local text = RTL_ReadFile(path)
    if (not text) then
        P.err = "ファイルが読めません"
        return
    end
    local plan, err = RTL_LT_ParseText(text)
    if (not plan) then
        P.err = err
        return
    end
    if (type(plan.entries) ~= "table") then
        P.err = "entries がありません"
        return
    end
    P.raw, P.diskText, P.head = plan, text, RTL_PE_HeadLines(text)
    if (P.sel and type(plan.entries[P.sel]) ~= "table") then
        P.sel, P.pick = nil, nil
    end
end

-- ---------------------------------------------------------------------
-- 変える・書く
-- ---------------------------------------------------------------------

function RTL_PE_Note(msg, tone)
    RTL.pe.msg = { text = msg, tone = tone or "muted", ms = RTL_Now() }
end

-- エントリを変えた（what：ログ・画面に出す説明）
function RTL_PE_Changed(e, what)
    local P = RTL.pe
    P.saveAt = RTL_Now() + RTL.PE.saveDelayMs
    P.changes = P.changes or {}
    P.changes[#P.changes + 1] = tostring(e.id or "?")..": "..what
    RTL_PE_Note("保存待ち: "..what, "info")
end

function RTL_PE_Tick(now)
    local P = RTL.pe
    if (P.saveAt and now >= P.saveAt) then
        RTL_PE_SaveNow(now)
    end
end

-- 書く：外で変わっていないか → 前の版をとる → 書く → 読み直して確かめる → プランを読み直す（戦闘中は並べ直す）
function RTL_PE_SaveNow(now)
    local P = RTL.pe
    P.saveAt = nil
    local changes = P.changes or {}
    P.changes = {}
    if (not P.path or not P.raw) then
        return false
    end
    local path = P.path
    local cur = RTL_ReadFile(path)
    if (cur ~= P.diskText) then
        RTL_PE_Load(path, P.mapid, P.file)
        RTL_PE_Note("ファイルが外で変わっていたので、書かずに読み直しました（画面の変更は捨てました）", "warning")
        RTL_PE_Apply(path, "外で変更")
        return false
    end
    local text = RTL_PE_Serialize(P.raw, P.head)
    local check, perr = RTL_LT_ParseText(text)
    if (not check or not RTL_PE_Same(check, P.raw)) then
        RTL_PE_Load(path, P.mapid, P.file)
        RTL_PE_Note("書き出しの確かめに失敗したので書きませんでした: "..tostring(perr or "中身が違う"), "error")
        return false
    end
    local bak = cur and RTL_PE_SaveBackup(path, P.mapid, P.file, cur)
    if (cur and not bak) then
        RTL_PE_Note("前の版をとっておけなかったので書きませんでした（backup フォルダ）", "error")
        RTL_PE_Load(path, P.mapid, P.file)
        return false
    end
    if (not RTL_WriteFile(path, text)) then
        RTL_PE_Note("書けませんでした: "..path, "error")
        RTL_PE_Load(path, P.mapid, P.file)
        return false
    end
    local back = RTL_ReadFile(path)
    local reread = back and RTL_LT_ParseText(back)
    if (back ~= text or not reread or not RTL_PE_Same(reread, P.raw)) then
        -- 読み直したら違った：前の版に戻す
        if (cur) then RTL_WriteFile(path, cur) end
        RTL_PE_Load(path, P.mapid, P.file)
        RTL_PE_Note("書いたファイルを読み直したら中身が違ったので、前の版に戻しました", "error")
        return false
    end
    P.diskText = text
    P.savedMs = now
    RTL_PE_Note("保存しました "..os.date("%H:%M:%S").."（"..#changes.." 件）", "success")
    RTL_Msg("plan saved: "..path.."  backup="..tostring(bak).."  "..table.concat(changes, " / "))
    RTL_PE_Apply(path, table.concat(changes, " / "))
    return true
end

-- 書いたプランを使う（今使っているプランなら、ポジション変更と同じく読み直して並べ直す）
function RTL_PE_Apply(path, detail)
    local T = RTL.tl
    if (path ~= RTL_PE_PlanPath()) then
        return
    end
    if (T.pull) then
        RTL_TL_Row("plan_edit", { ref = tostring(T.planFile), detail = detail })
        RTL_TL_Recent(string.format("[%s] プランを変更 %s", RTL_TL_FmtT(RTL_Now()), detail))
    end
    RTL_TL_ChangePlan()
end

-- 元に戻す：保存待ちがあればそれを捨てる。無ければ 1 つ前の版をプランに書き戻す（使った版は backup から消す）
function RTL_PE_Undo()
    local P = RTL.pe
    if (not P.path) then
        return
    end
    if (P.saveAt) then
        RTL_PE_Load(P.path, P.mapid, P.file)
        RTL_PE_Note("保存前の変更を取り消しました", "info")
        return
    end
    local list = RTL_PE_Backups(P.path, P.mapid, P.file)
    local name = list[#list]
    if (not name) then
        RTL_PE_Note("前の版がありません", "warning")
        return
    end
    local bpath = RTL_PE_BackupDir(P.mapid).."\\"..name
    local text = RTL_ReadFile(bpath)
    local plan, err = RTL_LT_ParseText(text)
    if (not plan or type(plan.entries) ~= "table") then
        table.remove(list)
        RTL_PE_Note("前の版 "..name.." が読めないので使いません: "..tostring(err), "error")
        return
    end
    if (not RTL_WriteFile(P.path, text) or RTL_ReadFile(P.path) ~= text) then
        RTL_PE_Note("書き戻せませんでした: "..P.path, "error")
        RTL_PE_Load(P.path, P.mapid, P.file)
        return
    end
    table.remove(list)
    pcall(os.remove, bpath)
    RTL_PE_Load(P.path, P.mapid, P.file)
    RTL_PE_Note("1 つ前の版（"..name.."）に戻しました", "success")
    RTL_Msg("plan restored: "..P.path.." <- "..name)
    RTL_PE_Apply(P.path, "元に戻す "..name)
end

-- エントリの値を変える
function RTL_PE_SetOffset(e, v)
    v = math.max(RTL.PE.offsetMin, math.min(RTL.PE.offsetMax, v))
    v = math.floor(v * 10 + 0.5) / 10
    local old = (type(e.offset) == "number") and e.offset or 0
    if (math.abs(v - old) < 1e-9) then
        return
    end
    e.offset = v
    RTL_PE_Changed(e, string.format("offset %s -> %s", RTL_PE_Num(old, "offset"), RTL_PE_Num(v, "offset")))
end

function RTL_PE_SetUse(e, use)
    local was = (e.execute ~= false)
    if (was == use) then
        return
    end
    if (use) then
        e.execute = nil       -- 既定（true）に戻す
    else
        e.execute = false
    end
    RTL_PE_Changed(e, use and "使う" or "使わない（ドライランだけ）")
end

function RTL_PE_SetAction(e, a)
    local old = (type(e.action) == "table") and e.action.id or nil
    if (old == a.id and type(e.action) == "table" and (e.action.type or 1) == 1) then
        return
    end
    e.action = { id = a.id, type = 1 }
    RTL_PE_Changed(e, string.format("アクション %s -> %s (%d)", old and RTL_PE_ActName(old) or "なし", a.name, a.id))
end

function RTL_PE_SetTarget(e, v)
    local old = (type(e.target) == "table") and e.target or { type = "self" }
    local oldText = (old.type == "entity") and ("entity:"..tostring(old.key)) or tostring(old.type)
    local key = v:match("^entity:(.+)$")
    if (key) then
        e.target = { type = "entity", key = key }
    else
        e.target = { type = v }
    end
    RTL_PE_Changed(e, "対象 "..oldText.." -> "..v)
end

-- イベントにエントリを足す（着弾ちょうど・対象は自分。id は <イベント>_<アクション>、重なれば _2 …）
function RTL_PE_AddEntry(ev, it)
    local P = RTL.pe
    local used = {}
    for _, x in ipairs(P.raw.entries) do
        if (type(x) == "table" and x.id) then used[tostring(x.id)] = true end
    end
    local base = tostring(ev.id).."_"..tostring(it.id)
    local id, n = base, 1
    while (used[id]) do
        n = n + 1
        id = base.."_"..n
    end
    local e = { id = id, event = ev.id, ref = "hit", offset = 0, action = { id = it.id, type = 1 },
                target = { type = "self" }, note = it.name.."（画面で追加）" }
    P.raw.entries[#P.raw.entries + 1] = e
    P.adding = nil
    P.sel, P.pick = #P.raw.entries, nil
    RTL_PE_Changed(e, "追加 "..it.name.." ("..it.id..") -> "..tostring(ev.id))
end

function RTL_PE_DeleteEntry(i)
    local P = RTL.pe
    local e = P.raw.entries[i]
    if (type(e) ~= "table") then
        return
    end
    table.remove(P.raw.entries, i)
    P.sel, P.pick = nil, nil
    RTL_PE_Changed(e, "消す")
end

function RTL_PE_SetRef(e, r)
    local old = (e.ref == "start") and "start" or "hit"
    if (old == r) then
        return
    end
    e.ref = r
    RTL_PE_Changed(e, "基準 "..old.." -> "..r)
end

-- 音（v0.6.3）：sound = "x.wav" か sound = { file = "x.wav", byAction = { ... } }
function RTL_PE_SoundFile(e)
    local snd = e.sound
    if (type(snd) == "string") then
        return snd
    elseif (type(snd) == "table") then
        return snd.file
    end
    return nil
end

-- f = nil で外す（分岐ごとの音があれば、共通の音だけ外す）
function RTL_PE_SetSound(e, f)
    local old = RTL_PE_SoundFile(e)
    if (old == f) then
        return
    end
    if (type(e.sound) == "table") then
        e.sound.file = f
    else
        e.sound = f
    end
    RTL_PE_Changed(e, "音 "..tostring(old or "なし").." -> "..tostring(f or "なし"))
end

function RTL_PE_AddSoundEntry(ev, f)
    local P = RTL.pe
    local used = {}
    for _, x in ipairs(P.raw.entries) do
        if (type(x) == "table" and x.id) then used[tostring(x.id)] = true end
    end
    local base = tostring(ev.id).."_snd"
    local id, n = base, 1
    while (used[id]) do
        n = n + 1
        id = base.."_"..n
    end
    local e = { id = id, event = ev.id, ref = "hit", offset = 0, sound = f, note = f.."（画面で追加）" }
    P.raw.entries[#P.raw.entries + 1] = e
    P.adding = nil
    P.sel, P.pick, P.wavPick = #P.raw.entries, nil, nil
    RTL_PE_Changed(e, "追加 音 "..f.." -> "..tostring(ev.id))
end

-- wav フォルダの wav の一覧（作り直すまで覚えておく）
function RTL_PE_Wavs(force)
    local P = RTL.pe
    if (P.wavs and not force) then
        return P.wavs
    end
    P.wavs = RTL_PE_ListDir(RTL_SND_Dir(), "", "wav")
    return P.wavs
end

-- 試しに鳴らす（ドライランの「テスト再生」と同じ鳴らし方）
function RTL_PE_TryWav(f)
    local now = RTL_Now()
    RTL_SND_Exists(f, true)
    local ok, why, n = RTL_SND_Play(f, nil, now)
    RTL.snd.last = { file = f, ms = now, result = ok and "テスト" or ("鳴らせない（"..tostring(why).."）"), n = n }
    if (not ok) then
        RTL_PE_Note(f.." を鳴らせません: "..tostring(why), "error")
    end
end

-- 編集欄の「音」の行
function RTL_PE_DrawSoundRow(e, hasAct)
    local P = RTL.pe
    local f = RTL_PE_SoundFile(e)
    RTL_UI_Muted("音")
    GUI:SameLine()
    if (f) then
        RTL_UI_Text(f, "accent")
        if (not RTL_SND_Exists(f)) then
            GUI:SameLine()
            RTL_UI_Badge("ファイルが無い", "error")
        end
    else
        RTL_UI_Muted("なし")
    end
    GUI:SameLine()
    if (RTL_UI_Button((P.wavPick and "閉じる" or "選ぶ").."##pewav", P.wavPick and "primary" or nil, true)) then
        P.wavPick = not P.wavPick
        if (P.wavPick) then P.pick = nil end
    end
    if (f) then
        GUI:SameLine()
        if (RTL_UI_Button("試す##pewavtry", nil, true)) then
            RTL_PE_TryWav(f)
        end
        local byA = (type(e.sound) == "table" and type(e.sound.byAction) == "table")
        if (hasAct or byA) then
            GUI:SameLine()
            if (RTL_UI_Button("外す##pewavoff", nil, true)) then
                RTL_PE_SetSound(e, nil)
            end
        end
    end
    if (type(e.sound) == "table" and type(e.sound.byAction) == "table") then
        local ids = {}
        for id in pairs(e.sound.byAction) do ids[#ids + 1] = id end
        table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
        local parts = {}
        for _, id in ipairs(ids) do parts[#parts + 1] = tostring(id).." = "..tostring(e.sound.byAction[id]) end
        RTL_UI_Muted("分岐ごとの音（ファイルで直す）: "..table.concat(parts, "、"))
        RTL_UI_Muted("上の音は、分岐が分からないまま終わったときの共通の音です")
    end
    if (P.wavPick) then
        RTL_PE_DrawWavPicker(f, function(nf) RTL_PE_SetSound(e, nf) P.wavPick = nil end)
    end
end

-- wav を選ぶ一覧
function RTL_PE_DrawWavPicker(cur, onPick)
    local list = RTL_PE_Wavs()
    GUI:Spacing()
    RTL_UI_Muted(RTL_SND_Dir())
    GUI:SameLine()
    if (RTL_UI_Button("作り直す##pewavlist", nil, true)) then
        list = RTL_PE_Wavs(true)
        RTL.snd.files = {}
    end
    if (#list == 0) then
        RTL_UI_Text("wav がありません（このフォルダに .wav を置いてください）", "warning")
    end
    for i, f in ipairs(list) do
        if (RTL_SND_ValidName(f)) then
            if (RTL_UI_Button(f.."##pewv"..i, (f == cur) and "primary" or "accent", true)) then
                onPick(f)
            end
            GUI:SameLine()
            if (RTL_UI_Button("試す##pewvt"..i, nil, true)) then
                RTL_PE_TryWav(f)
            end
        else
            RTL_UI_Muted(f.."（名前は英数字・_・- だけにしてください）")
        end
    end
end

-- ---------------------------------------------------------------------
-- アクションの一覧（今のジョブ）
-- ---------------------------------------------------------------------

function RTL_PE_ActName(id)
    local c = RTL.tl.actionNames[id]
    if (c == nil) then
        c = false
        local ok, act = pcall(function() return ActionList:Get(1, id) end)
        if (ok and type(act) == "table" and type(act.name) == "string" and act.name ~= "") then
            c = act.name
        end
        RTL.tl.actionNames[id] = c
    end
    return c or ("#"..tostring(id))
end

-- GCD / oGCD / ?（実行と同じ見分け方：代表 GCD の recasttime と 0.1 秒以内なら GCD）
function RTL_PE_Kind(recast, base)
    recast = tonumber(recast)
    if (not recast or recast <= 0) then
        return "?"
    end
    return (math.abs(recast - base) <= 0.1) and "GCD" or "oGCD"
end

-- ActionList:Get(1) から今のジョブのアクションを集める（ジョブが変わったか「作り直す」で作り直す）
function RTL_PE_JobActions(force)
    local P = RTL.pe
    local job = Player and Player.job
    if (P.acts and P.actsJob == job and not force) then
        return P.acts
    end
    local res = { list = {}, byId = {}, n = { GCD = 0, oGCD = 0, ["?"] = 0 }, total = 0, byJob = 0, byRole = 0, err = nil }
    local base = nil
    if (type(FFXIVLib) == "table" and FFXIVLib.API and FFXIVLib.API.ClassJob and type(FFXIVLib.API.ClassJob.GetBaseClass) == "function") then
        local ok, v = pcall(FFXIVLib.API.ClassJob.GetBaseClass, job)
        if (ok) then base = v end
    end
    local gcdBase = RTL_EX_GcdBase()
    local ok, all = pcall(function() return ActionList:Get(1) end)
    if (not ok or type(all) ~= "table") then
        res.err = "ActionList:Get(1) が一覧を返しませんでした"
        all = {}
    end
    local function add(aid, a, role)
        if (not aid or res.byId[aid] or type(a) ~= "table" or type(a.name) ~= "string" or a.name == "") then
            return
        end
        local it = { id = aid, name = a.name, level = tonumber(a.level) or 0, recast = tonumber(a.recasttime),
                     kind = RTL_PE_Kind(a.recasttime, gcdBase), job = a.job, role = role }
        res.list[#res.list + 1] = it
        res.byId[aid] = it
        res.n[it.kind] = res.n[it.kind] + 1
        if (role) then res.byRole = res.byRole + 1 else res.byJob = res.byJob + 1 end
    end
    for id, a in pairs(all) do
        res.total = res.total + 1
        if (type(a) == "table") then
            local aj = a.job
            -- level が 0 のものは PvP のアクション（v0.6.5。ナイトでは 29058〜29073・41428〜42194 の 18 件。PvE と同じ名前がある）
            if (aj ~= nil and aj ~= 0 and (aj == job or (base ~= nil and aj == base)) and (tonumber(a.level) or 0) > 0) then
                add(tonumber(a.id) or tonumber(id), a, false)
            end
        end
    end
    -- ロールアクション・共通アクション（一覧に無ければ 1 つずつ引く）
    local ids = {}
    for _, x in ipairs(RTL.PE_ROLE.common) do ids[#ids + 1] = x end
    for _, x in ipairs(RTL.PE_ROLE[RTL.PE_ROLE_OF[job or -1] or ""] or {}) do ids[#ids + 1] = x end
    for _, aid in ipairs(ids) do
        local a = all[aid]
        if (type(a) ~= "table") then
            pcall(function() a = ActionList:Get(1, aid) end)
        end
        add(aid, a, true)
    end
    table.sort(res.list, function(a, b)
        if (a.level ~= b.level) then return a.level < b.level end
        return a.id < b.id
    end)
    res.gcdBase = gcdBase
    res.base = base
    P.acts, P.actsJob = res, job
    RTL_Msg(string.format("plan editor: actions for job %s (base %s): %d (job %d / role %d, GCD %d / oGCD %d / ? %d) of %d",
        tostring(job), tostring(base), #res.list, res.byJob, res.byRole, res.n.GCD, res.n.oGCD, res.n["?"], res.total))
    return res
end

-- 一覧に無いアクション（プランに書いてあるもの）の情報
function RTL_PE_ActInfo(id)
    local acts = RTL_PE_JobActions()
    local it = acts.byId[id]
    if (it) then
        return it
    end
    local c = RTL.pe.extra and RTL.pe.extra[id]
    if (c) then
        return c
    end
    RTL.pe.extra = RTL.pe.extra or {}
    local act = nil
    pcall(function() act = ActionList:Get(1, id) end)
    c = { id = id, name = RTL_PE_ActName(id), level = 0, kind = "?" }
    if (type(act) == "table") then
        c.recast = tonumber(act.recasttime)
        c.kind = RTL_PE_Kind(act.recasttime, acts.gcdBase or RTL_EX_GcdBase())
        c.level = tonumber(act.level) or 0
    end
    RTL.pe.extra[id] = c
    return c
end

function RTL_PE_KindTone(kind)
    if (kind == "GCD") then return "warning" end
    if (kind == "oGCD") then return "info" end
    return "neutral"
end

-- 調査用（v0.6.1）：ActionList:Get(1) の中身を logs\actions_dump_<job>.csv に書く（job・level・usable などの実際の値を見るため）
function RTL_PE_DumpActions()
    local job = Player and Player.job
    local ok, all = pcall(function() return ActionList:Get(1) end)
    if (not ok or type(all) ~= "table") then
        RTL_PE_Note("ActionList:Get(1) が一覧を返しませんでした", "error")
        return
    end
    local fields = { "id", "name", "job", "level", "usable", "recasttime", "casttime", "range", "skilltype", "cost", "isgroundtargeted" }
    local extra, seen = {}, {}
    for _, f in ipairs(fields) do seen[f] = true end
    local rows = {}
    for id, a in pairs(all) do
        if (type(a) == "table") then
            for k, v in pairs(a) do
                if (type(k) == "string" and not seen[k] and type(v) ~= "function" and type(v) ~= "table") then
                    seen[k] = true
                    extra[#extra + 1] = k
                end
            end
            rows[#rows + 1] = a
        end
    end
    table.sort(extra)
    for _, k in ipairs(extra) do fields[#fields + 1] = k end
    table.sort(rows, function(a, b) return (tonumber(a.id) or 0) < (tonumber(b.id) or 0) end)
    local out = { table.concat(fields, ",") }
    for _, a in ipairs(rows) do
        local cols = {}
        for i, f in ipairs(fields) do
            local v = a[f]
            cols[i] = (v == nil) and "" or RTL_CsvField(tostring(v))
        end
        out[#out + 1] = table.concat(cols, ",")
    end
    RTL_EnsureFolder(RTL.path.."\\logs")
    local path = RTL.path.."\\logs\\actions_dump_"..tostring(job)..".csv"
    if (RTL_WriteFile(path, "\239\187\191"..table.concat(out, "\r\n").."\r\n")) then
        RTL_PE_Note("書きました: logs\\actions_dump_"..tostring(job)..".csv（"..#rows.." 件）", "success")
        RTL_Msg("actions dump: "..path.."  rows="..#rows)
    end
end

-- ---------------------------------------------------------------------
-- プランを選ぶ（v0.6.1）：plans\<mapid>\*.lua の一覧と、そのマップのタイムライン
-- ---------------------------------------------------------------------

-- フォルダの中のフォルダ（数字の名前＝mapid）。FolderList（フォルダも返す）→ dir /b /ad
function RTL_PE_ListMapDirs(dir)
    local names, seen = {}, {}
    local function add(p)
        if (type(p) ~= "string") then return end
        local base = (p:gsub("[\\/]+$", "")):match("([^\\/]+)$") or p
        if (base:match("^%d+$") and not seen[base]) then
            seen[base] = true
            names[#names + 1] = base
        end
    end
    local got = false
    if (type(FolderList) == "function") then
        local ok, list = pcall(FolderList, dir, "^%d+$", true)
        if (ok and type(list) == "table") then
            for _, p in pairs(list) do add(p) end
            got = (#names > 0)
        end
    end
    if (not got and FolderExists and FolderExists(dir) and io.popen) then
        local ok, f = pcall(io.popen, 'dir /b /ad "'..dir..'" 2>nul')
        if (ok and f) then
            for line in f:lines() do add((line:gsub("[\r\n]", ""))) end
            f:close()
        end
    end
    table.sort(names, function(a, b) return tonumber(a) < tonumber(b) end)
    return names
end

-- プランの一覧（作り直すまで覚えておく）：{ { mapid, name, files = { "PLD_ANY.lua", ... }, ntl, hasTl }, ... }
--   プランのあるマップ（plans\<mapid>\）と、タイムラインのあるマップ（timelines\<mapid>_*.lua。v0.6.6）。
--   タイムラインだけのマップは files が空（「作る」でプランを作る）
function RTL_PE_PlanList(force)
    local P = RTL.pe
    if (P.planList and not force) then
        return P.planList
    end
    local dir = RTL.path.."\\plans"
    local files, maps = {}, {}
    for _, m in ipairs(RTL_PE_ListMapDirs(dir)) do
        local fs = {}
        for _, f in ipairs(RTL_PE_ListDir(dir.."\\"..m, "")) do
            if (f:match("^%u+_%w+%.lua$")) then fs[#fs + 1] = f end
        end
        if (#fs > 0) then
            files[tonumber(m)] = fs
            maps[#maps + 1] = tonumber(m)
        end
    end
    for _, f in ipairs(RTL_PE_ListDir(RTL.path.."\\timelines", "")) do
        local m = tonumber(f:match("^(%d+)_[%w_%-]+%.lua$") or "")
        if (m and not files[m]) then
            files[m] = {}
            maps[#maps + 1] = m
        end
    end
    table.sort(maps)
    local list = {}
    for _, mapid in ipairs(maps) do
        local cands = RTL_PE_Cands(mapid)
        local name, hasTl = nil, false
        for _, c in ipairs(cands) do
            if (c.tl) then
                hasTl = true
                if (c.tl.meta and c.tl.meta.name) then name = name or c.tl.meta.name end
            end
        end
        if (#files[mapid] > 0 or hasTl) then
            list[#list + 1] = { mapid = mapid, name = name, files = files[mapid], ntl = #cands, hasTl = hasTl }
        end
    end
    P.planList = list
    return list
end

-- 今のジョブで作れるプランのファイル名（まだ無いもの）：<ジョブ>_<ポジション>.lua（ポジションを選んでいれば）・<ジョブ>_ANY.lua
function RTL_PE_NewPlanNames(m)
    local job = RTL_TL_JobName()
    local have = {}
    for _, f in ipairs(m.files or {}) do have[f] = true end
    local out = {}
    local pos = RTL.settings.position
    if (type(pos) == "string" and pos ~= "" and pos ~= "ANY") then
        out[#out + 1] = job.."_"..pos..".lua"
    end
    out[#out + 1] = job.."_ANY.lua"
    local res = {}
    for _, f in ipairs(out) do
        if (not have[f] and f:match("^%u+_%w+%.lua$")) then res[#res + 1] = f end
    end
    return res
end

-- プランを作る（v0.6.6）：plans\<mapid>\<file> にエントリなしのプランを書き、それを直すプランにする。
--   タイムラインは、そのマップのドライランで使っているもの（今のマップなら）→ 読めた最初のもの
--   すでにあるファイルは上書きしない。書いた後に読み直して確かめる
function RTL_PE_CreatePlan(mapid, file)
    local P = RTL.pe
    local T = RTL.tl
    local dir = RTL.path.."\\plans\\"..tostring(mapid)
    local path = dir.."\\"..file
    if (RTL_ReadFile(path)) then
        RTL_PE_Note(file.." はもうあります", "warning")
        return false
    end
    local pick = nil
    for _, c in ipairs(RTL_PE_Cands(mapid)) do
        if (c.tl and (pick == nil or (mapid == T.mapid and c.file == T.file))) then pick = c end
    end
    if (not pick) then
        RTL_PE_Note("マップ "..tostring(mapid).." の読めるタイムラインがありません", "error")
        return false
    end
    local job, pos = file:match("^(%u+)_(%w+)%.lua$")
    local plan = {
        format = RTL.TL.format,
        meta = { mapid = mapid, timeline = (pick.file:gsub("%.lua$", "")),
                 timelineVersion = pick.tl.meta and pick.tl.meta.version or nil, job = job, position = pos },
        entries = {},
    }
    local head = { "-- RaidTimeline アクション設定  "..tostring(pick.tl.meta and pick.tl.meta.name or pick.file).."・"..tostring(job) }
    local text = RTL_PE_Serialize(plan, head)
    local back = RTL_LT_ParseText(text)
    if (not back or type(back.entries) ~= "table" or not back.meta or back.meta.mapid ~= mapid) then
        RTL_PE_Note("プランを作れませんでした（書く前の確かめ）", "error")
        return false
    end
    RTL_EnsureFolder(RTL.path.."\\plans")
    RTL_EnsureFolder(dir)
    if (not RTL_WriteFile(path, text) or RTL_ReadFile(path) ~= text) then
        RTL_PE_Note("プランを書けませんでした: "..path, "error")
        return false
    end
    RTL_Msg("plan created: "..path)
    P.planList = nil
    if (mapid == T.mapid and T.timeline) then
        RTL_TL_LoadPlan()               -- 今のマップ・ジョブのプランなら、ドライランでもすぐ使う
    end
    P.manual = (path ~= RTL_PE_PlanPath()) and { path = path, mapid = mapid, file = file } or nil
    P.choosing = false
    RTL_PE_Note(file.." を作りました（"..pick.file.."）。イベントの「追加」でエントリを足してください", "success")
    return true
end

-- そのマップのタイムライン（今のマップならドライランのもの。違えば自分で読む。読んだものは覚えておく）
function RTL_PE_Cands(mapid)
    local T = RTL.tl
    if (mapid == T.mapid and T.cands) then
        return T.cands
    end
    local P = RTL.pe
    P.tlCache = P.tlCache or {}
    local c = P.tlCache[mapid]
    if (c) then
        return c
    end
    c = {}
    local prefix = tostring(mapid).."_"
    for _, f in ipairs(RTL_PE_ListDir(RTL.path.."\\timelines", prefix)) do
        local one = { file = f }
        local tl, err = RTL_LT_ParseFile(RTL.path.."\\timelines\\"..f)
        if (tl) then
            local prep, perr = RTL_TL_Prepare(tl, mapid)
            if (prep) then one.tl = tl else one.err = perr end
        else
            one.err = err
        end
        c[#c + 1] = one
    end
    P.tlCache[mapid] = c
    return c
end

-- プランを選ぶ画面（見出しのカードの中）
function RTL_PE_DrawPlanPicker()
    local P = RTL.pe
    local cur = RTL_PE_PlanPath()
    local list = RTL_PE_PlanList()
    if (#list == 0) then
        RTL_UI_Muted("plans フォルダにプランがありません")
    end
    for li, m in ipairs(list) do
        RTL_UI_Text(tostring(m.name or "（タイムラインなし）"))
        GUI:SameLine()
        RTL_UI_Muted(tostring(m.mapid))
        if (#m.files == 0) then
            GUI:SameLine()
            RTL_UI_Badge("プランなし", "neutral")
        end
        for fi, f in ipairs(m.files) do
            if (fi > 1) then GUI:SameLine(0, 4) end
            if (fi == 1) then GUI:Dummy(12, 0) GUI:SameLine(0, 0) end
            local path = RTL.path.."\\plans\\"..tostring(m.mapid).."\\"..f
            local tone = (path == P.path) and "primary" or nil
            local label = f:gsub("%.lua$", "")..((path == cur) and "（今）" or "")
            if (RTL_UI_Button(label.."##pepl"..li.."_"..fi, tone, true)) then
                P.manual = (path ~= cur) and { path = path, mapid = m.mapid, file = f } or nil
                P.choosing = false
            end
        end
        -- タイムラインがあれば、今のジョブのプランを作れる（v0.6.6）
        if (m.hasTl) then
            for ni, f in ipairs(RTL_PE_NewPlanNames(m)) do
                if (ni == 1) then
                    if (#m.files > 0) then GUI:SameLine(0, 4) else GUI:Dummy(12, 0) GUI:SameLine(0, 0) end
                else
                    GUI:SameLine(0, 4)
                end
                if (RTL_UI_Button(f:gsub("%.lua$", "").." を作る##pemk"..li.."_"..ni, "success", true)) then
                    RTL_PE_CreatePlan(m.mapid, f)
                end
            end
        end
    end
    if (RTL_UI_Button("一覧を作り直す##peplrebuild", nil, true)) then
        P.tlCache = nil
        RTL_PE_PlanList(true)
    end
    if (P.manual and cur) then
        GUI:SameLine()
        if (RTL_UI_Button("今のプランに戻す##pecur", nil, true)) then
            P.manual = nil
            P.choosing = false
        end
    end
end

-- 直すプランのジョブ（ファイル名の先頭）と今のジョブが違うか
function RTL_PE_OtherJob()
    local P = RTL.pe
    local j = P.file and P.file:match("^(%u+)_")
    return (j ~= nil and j ~= RTL_TL_JobName()), j
end

-- ---------------------------------------------------------------------
-- 画面
-- ---------------------------------------------------------------------

function RTL_PE_Draw(event, ticks)
    if (not RTL.initDone or not RTL.pe.open) then
        return
    end
    GUI:SetNextWindowSize(500, 640, GUI.SetCond_FirstUseEver)
    local wasOpen = RTL.pe.open
    local _, open = RTL_UI_Window("RaidTimeline プラン編集", RTL.pe.open, nil, RTL_PE_DrawBody,
        { alpha = RTL.settings.uiAlpha, scale = RTL.settings.uiScale, where = "DrawPE" })
    RTL.pe.open = open
    if (wasOpen ~= RTL.pe.open) then
        RTL_SaveSettings()
    end
end

-- タイミングの文字（「着弾の 3.0 秒前」など）
function RTL_PE_TimingText(e)
    local off = (type(e.offset) == "number") and e.offset or 0
    local ref = (e.ref == "start") and "詠唱開始" or "着弾"
    if (math.abs(off) < 0.05) then
        return ref.."ちょうど"
    end
    return string.format("%sの %s 秒%s", ref, RTL_PE_Num(math.abs(off), "offset"), (off < 0) and "前" or "後")
end

-- フェーズの時計での実行時刻（予定）
function RTL_PE_PhaseTime(e, ev)
    local off = (type(e.offset) == "number") and e.offset or 0
    local base = ev.t + ((e.ref == "start") and 0 or (ev.cast or 0))
    return base + off
end

function RTL_PE_DrawBody()
    local P = RTL.pe
    local T = RTL.tl
    local now = RTL_Now()
    RTL_PE_Sync()
    -- 見出し：プラン・保存の状態・元に戻す
    RTL_UI_Card("pe_head", function()
        RTL_UI_Title("プラン")
        GUI:SameLine()
        local cur = RTL_PE_PlanPath()
        if (P.path and P.raw) then
            RTL_UI_Text("plans\\"..tostring(P.mapid).."\\"..tostring(P.file))
            GUI:SameLine()
            RTL_UI_Badge(#P.raw.entries.." 件", "neutral")
            GUI:SameLine()
            if (P.path == cur) then
                RTL_UI_Badge("使用中", "primary")
            else
                RTL_UI_Badge("使っていない", "neutral")
            end
        elseif (P.path and P.err) then
            RTL_UI_Text(tostring(P.file).." 読めません: "..tostring(P.err), "error")
        else
            RTL_UI_Muted("今のマップ・ジョブのプランはありません。下から選んでください")
        end
        GUI:SameLine()
        if (RTL_UI_Button((P.choosing and "閉じる" or "プランを選ぶ").."##pechoose", P.choosing and "primary" or nil, true)) then
            P.choosing = not P.choosing
        end
        if (P.choosing or not P.path) then
            RTL_PE_DrawPlanPicker()
        end
        if (not P.raw) then
            return
        end
        local list = RTL_PE_Backups(P.path, P.mapid, P.file)
        if (P.saveAt) then
            RTL_UI_Badge("保存待ち", "info")
        elseif (P.savedMs) then
            RTL_UI_Badge("保存済み", "success")
        end
        GUI:SameLine()
        RTL_UI_Muted("前の版 "..#list.." / "..RTL.PE.keep)
        GUI:SameLine()
        local armed = P.undoArm and (now - P.undoArm < RTL.PE.confirmMs)
        local canUndo = (P.saveAt ~= nil) or (#list > 0)
        if (canUndo) then
            if (RTL_UI_Button((armed and "もう一度押すと戻します" or "元に戻す").."##peundo", armed and "warning" or nil, true)) then
                if (armed or P.saveAt) then
                    P.undoArm = nil
                    RTL_PE_Undo()
                else
                    P.undoArm = now
                end
            end
        end
        GUI:SameLine()
        if (RTL_UI_Button("読み直す##pereload", nil, true)) then
            if (P.saveAt) then RTL_PE_SaveNow(now) end
            -- タイムラインの一覧も作り直す（v0.6.9）。戦闘中でなく、今のマップならドライランのタイムラインも読み直す
            P.planList, P.tlCache = nil, nil
            if (not T.pull and T.mapid and P.mapid == T.mapid) then
                RTL_TL_Reload(T.mapid, T.manualPick and T.file or nil)
            end
            RTL_PE_Load(P.path, P.mapid, P.file)
            RTL_PE_Apply(P.path, "読み直す")
        end
        if (T.pull) then
            RTL_UI_Text("戦闘中：変えたら 0.7 秒後に保存し、今のフェーズの残りから並べ直します", "info")
        end
        if (P.msg and now - P.msg.ms < 15000) then
            RTL_UI_Text(P.msg.text, P.msg.tone)
        end
        local v, pressed = RTL_UI_Toggle("エントリの無いイベントも出す##peall", P.showAll == true)
        if (pressed) then P.showAll = v end
    end)
    if (not P.raw) then
        return
    end
    -- 前のフレームで「消す」を押したエントリ（v0.6.4。同じプランの同じエントリのときだけ消す）
    local dr = P.delReq
    P.delReq = nil
    if (dr and dr.path == P.path and P.raw.entries[dr.i] == dr.e) then
        RTL_PE_DeleteEntry(dr.i)
    end
    -- イベントごとのエントリ
    local byEvent = {}
    for i, e in ipairs(P.raw.entries) do
        if (type(e) == "table") then
            local k = tostring(e.event)
            byEvent[k] = byEvent[k] or {}
            byEvent[k][#byEvent[k] + 1] = i
        end
    end
    local shown = {}
    local cands = {}
    local live = (P.mapid == T.mapid)
    for _, c in ipairs(RTL_PE_Cands(P.mapid)) do
        if (c.tl and live and c.file == T.file) then table.insert(cands, 1, c) elseif (c.tl) then cands[#cands + 1] = c end
    end
    for ci, c in ipairs(cands) do
        local any = false
        for _, ph in ipairs(c.tl.phases) do
            for _, ev in ipairs(ph.events) do
                if (byEvent[ev.id]) then any = true end
            end
        end
        if (any or P.showAll or ci == 1) then
            RTL_UI_Card("pe_tl"..ci, function()
                RTL_UI_Title(tostring(c.tl.meta.name or c.file))
                GUI:SameLine()
                RTL_UI_Muted(c.file)
                if (live and c.file == T.file) then
                    GUI:SameLine()
                    RTL_UI_Badge("使用中", "primary")
                end
                if (not any and not P.showAll) then
                    RTL_UI_Muted("このタイムラインにはまだエントリがありません。イベントの「追加」で足してください")
                end
                for _, ph in ipairs(c.tl.phases) do
                    -- エントリが 1 つも無いタイムラインは、全部のイベントを出す（v0.6.7。足せるように）
                    RTL_PE_DrawPhase(ph, byEvent, shown, live and c.file == T.file, c.tl, P.showAll or not any)
                end
            end)
        end
    end
    -- どのタイムラインにも無いイベントのエントリ
    local orphans = {}
    for i, e in ipairs(P.raw.entries) do
        if (type(e) == "table" and not shown[i]) then orphans[#orphans + 1] = i end
    end
    if (#orphans > 0) then
        RTL_UI_Card("pe_orphan", function()
            RTL_UI_Title("タイムラインに無いイベント")
            GUI:SameLine()
            RTL_UI_Badge(#orphans.." 件", "warning")
            RTL_UI_Muted("このマップのタイムラインに無いイベントを指しています（使われません）")
            for _, i in ipairs(orphans) do
                RTL_PE_DrawEntry(i, P.raw.entries[i], nil)
            end
        end, "warning")
    end
end

function RTL_PE_DrawPhase(ph, byEvent, shown, active, tl, all)
    local P = RTL.pe
    local evs = {}
    for _, ev in ipairs(ph.events) do
        if (byEvent[ev.id] or all) then evs[#evs + 1] = ev end
    end
    if (#evs == 0) then
        return
    end
    table.sort(evs, function(a, b) return a.t < b.t end)
    GUI:Spacing()
    RTL_UI_Badge(ph.id, active and "primary" or "neutral")
    GUI:SameLine()
    RTL_UI_Muted(tostring(ph.name or ""))
    local pull = active and RTL.tl.pull
    for _, ev in ipairs(evs) do
        RTL_UI_Muted(string.format("%6.1f", ev.t))
        GUI:SameLine()
        RTL_UI_Text(RTL_TL_EventLabel(ev))
        if (pull and pull.matches[ev.id]) then
            GUI:SameLine()
            RTL_UI_Badge("済み", "neutral")
        end
        local adding = (P.adding and P.adding.event == ev.id)
        GUI:SameLine()
        if (RTL_UI_Button((adding and "やめる" or "追加").."##peadd_"..ev.id, adding and "primary" or nil, true)) then
            P.adding = (not adding) and { event = ev.id, tab = "oGCD", q = "", mode = "action" } or nil
            P.sel, P.pick, P.wavPick = nil, nil, nil
        end
        for _, i in ipairs(byEvent[ev.id] or {}) do
            if (not shown[i]) then      -- 同じイベント ID が別のタイムラインにもあるときは、最初の 1 つだけに出す
                shown[i] = true
                RTL_PE_DrawEntry(i, P.raw.entries[i], ev, tl)
            end
        end
        if (adding) then
            RTL_UI_Card("pe_add", function()
                local other, pj = RTL_PE_OtherJob()
                if (other) then P.adding.mode = "sound" end
                RTL_UI_Title("「"..RTL_TL_EventLabel(ev).."」に足す")
                GUI:SameLine()
                local items = other and { { "sound", "音" } } or { { "action", "アクション" }, { "sound", "音" } }
                local m = RTL_UI_Segmented("peaddmode", items, P.adding.mode or "action")
                if (m ~= nil) then P.adding.mode = m end
                if (other) then
                    RTL_UI_Text("アクションは "..tostring(pj).." のときに足せます（今のジョブ "..RTL_TL_JobName().."）。今は音だけ足せます", "warning")
                end
                if ((P.adding.mode or "action") == "action") then
                    RTL_UI_Muted("選ぶと、着弾ちょうど・対象は自分のエントリができます（後から変えられます）")
                    RTL_PE_DrawPicker(nil, P.adding, function(it) RTL_PE_AddEntry(ev, it) end)
                else
                    RTL_UI_Muted("選ぶと、着弾ちょうどに鳴らす音だけのエントリができます（後から変えられます）")
                    RTL_PE_DrawWavPicker(nil, function(f) RTL_PE_AddSoundEntry(ev, f) end)
                end
            end, "primary")
        end
    end
end

-- エントリ 1 行（押すと編集欄）
function RTL_PE_DrawEntry(i, e, ev, tl)
    local P = RTL.pe
    if (type(e) ~= "table") then
        return
    end
    local sel = (P.sel == i)
    GUI:Dummy(12, 0)
    GUI:SameLine(0, 0)
    local hasAct = (type(e.action) == "table" and type(e.action.id) == "number")
    local info = hasAct and RTL_PE_ActInfo(e.action.id)
    local label = hasAct and info.name or ("音: "..tostring(RTL_PE_SoundFile(e) or "分岐ごと"))
    if (RTL_UI_Button(label.."##pesel"..i, sel and "primary" or (hasAct and "own" or "accent"), true)) then
        P.sel = (not sel) and i or nil
        P.pick, P.adding, P.delArm, P.wavPick = nil, nil, nil, nil
    end
    if (hasAct) then
        GUI:SameLine()
        RTL_UI_Badge(info.kind, RTL_PE_KindTone(info.kind))
    end
    GUI:SameLine()
    RTL_UI_Muted(RTL_PE_TimingText(e))
    if (e.execute == false) then
        GUI:SameLine()
        RTL_UI_Badge("使わない", "warning")
    end
    if (e.sound ~= nil and hasAct) then
        GUI:SameLine()
        RTL_UI_Badge("音", "accent")
    end
    if (hasAct and e.onAction ~= nil) then
        GUI:SameLine()
        RTL_UI_Badge("分岐 "..RTL_PE_OnActionText(e, tl), "accent")
    end
    if (sel) then
        RTL_UI_Card("pe_edit", function() RTL_PE_DrawEditor(i, e, ev, tl) end, "primary")
    end
end

-- 編集欄
function RTL_PE_DrawEditor(i, e, ev, tl)
    local P = RTL.pe
    local hasAct = (type(e.action) == "table" and type(e.action.id) == "number")
    RTL_UI_Muted("id")
    GUI:SameLine()
    RTL_UI_Text(tostring(e.id or ("entry"..i)))
    if (e.note) then
        RTL_UI_Muted(tostring(e.note))
    end
    -- アクション
    RTL_UI_Muted("アクション")
    GUI:SameLine()
    if (hasAct) then
        local info = RTL_PE_ActInfo(e.action.id)
        RTL_UI_Text(info.name, "own")
        GUI:SameLine()
        RTL_UI_Muted("#"..tostring(e.action.id))
    else
        RTL_UI_Muted("なし（音だけ）")
    end
    local other, pj = RTL_PE_OtherJob()
    if (other) then
        P.pick = nil
        RTL_UI_Text("アクションは "..tostring(pj).." のときに変えられます（一覧は今のジョブ "..RTL_TL_JobName().." のもの）", "warning")
    else
        GUI:SameLine()
        if (RTL_UI_Button((P.pick and "閉じる" or "変える").."##pepick", P.pick and "primary" or nil, true)) then
            P.pick = (not P.pick) and { tab = "oGCD", q = "" } or nil
            P.wavPick = nil
        end
    end
    if (hasAct and RTL_PE_ActInfo(e.action.id).kind == "GCD") then
        RTL_UI_Text("GCD のアクションは、実行がまだ対応していません", "warning")
    end
    -- タイミング
    RTL_UI_Muted("タイミング")
    GUI:SameLine()
    local off = (type(e.offset) == "number") and e.offset or 0
    if (RTL_UI_Button("-"..RTL_PE_Num(RTL.PE.step, "offset").."##peoffm", nil, true)) then
        RTL_PE_SetOffset(e, off - RTL.PE.step)
    end
    GUI:SameLine()
    GUI:PushItemWidth(70)
    local nv, nch = GUI:InputFloat("##peofftxt", off, 0, 0, 1)
    GUI:PopItemWidth()
    if (nch and type(nv) == "number") then
        RTL_PE_SetOffset(e, nv)
    end
    GUI:SameLine()
    if (RTL_UI_Button("+"..RTL_PE_Num(RTL.PE.step, "offset").."##peoffp", nil, true)) then
        RTL_PE_SetOffset(e, off + RTL.PE.step)
    end
    GUI:SameLine()
    RTL_UI_Text(RTL_PE_TimingText(e))
    if (ev) then
        RTL_UI_Muted(string.format("秒（マイナス＝前）。フェーズの %.1f 秒に使う", RTL_PE_PhaseTime(e, ev)))
    end
    -- 対象
    if (hasAct) then
        RTL_UI_Muted("対象")
        GUI:SameLine()
        local items = { { "self", "自分" }, { "target", "今のターゲット" } }
        local keys = {}
        for k in pairs((tl and tl.entities) or {}) do keys[#keys + 1] = k end
        table.sort(keys)
        for _, k in ipairs(keys) do
            local en = tl.entities[k]
            items[#items + 1] = { "entity:"..k, tostring((type(en) == "table" and en.name) or k) }
        end
        local tg = (type(e.target) == "table") and e.target or { type = "self" }
        local curT = (tg.type == "entity") and ("entity:"..tostring(tg.key)) or tostring(tg.type or "self")
        local found = false
        for _, it in ipairs(items) do if (it[1] == curT) then found = true end end
        if (not found) then items[#items + 1] = { curT, curT } end
        local pt = RTL_UI_Segmented("petgt", items, curT)
        if (pt ~= nil and pt ~= curT) then
            RTL_PE_SetTarget(e, pt)
        end
    end
    RTL_UI_Muted("基準")
    GUI:SameLine()
    local rp = RTL_UI_Segmented("peref", { { "start", "詠唱開始" }, { "hit", "着弾" } }, (e.ref == "start") and "start" or "hit")
    if (rp ~= nil) then
        RTL_PE_SetRef(e, rp)
    end
    -- 使う／使わない（アクションのあるエントリだけ）
    if (hasAct) then
        RTL_UI_Muted("実行")
        GUI:SameLine()
        local pick = RTL_UI_Segmented("peuse", { { true, "使う" }, { false, "使わない（ドライランだけ）" } }, e.execute ~= false)
        if (pick ~= nil) then
            RTL_PE_SetUse(e, pick)
        end
    end
    -- 分岐（v0.6.8）：照合するアクションが 2 つ以上のイベントだけ
    if (hasAct) then
        RTL_PE_DrawBranchRow(e, ev, tl)
    end
    -- 音
    RTL_PE_DrawSoundRow(e, hasAct)
    -- 消す（2 回押す）
    local now = RTL_Now()
    local armed = P.delArm and P.delArm.i == i and (now - P.delArm.ms < RTL.PE.confirmMs)
    if (RTL_UI_Button((armed and "もう一度押すと消します" or "このエントリを消す").."##pedel", armed and "error" or nil, true)) then
        if (armed) then
            P.delArm = nil
            -- 消すのは次のフレームの最初（v0.6.4）。この場で消すと、同じフレームで後に描くエントリの番号がずれる
            P.delReq = { i = i, e = e, path = P.path }
            return
        end
        P.delArm = { i = i, ms = now }
    end
    if (P.pick) then
        local cur = (type(e.action) == "table") and e.action.id or nil
        RTL_PE_DrawPicker(cur, P.pick, function(it) RTL_PE_SetAction(e, it) end)
    end
end

-- 分岐（v0.6.8）：onAction（来たアクションがこれのときだけ使う）
function RTL_PE_EventActs(ev)
    local a = type(ev) == "table" and type(ev.match) == "table" and ev.match.action
    if (type(a) == "number") then
        return { a }
    end
    local out = {}
    if (type(a) == "table") then
        for _, x in ipairs(a) do
            if (type(x) == "number") then out[#out + 1] = x end
        end
    end
    return out
end

function RTL_PE_EnemyActName(tl, a)
    return (tl and type(tl.actions) == "table" and tl.actions[a]) or (RTL.names.actions and RTL.names.actions[a])
        or RTL_TL_GameActionName(a) or tostring(a)
end

function RTL_PE_OnActionText(e, tl)
    local v = e.onAction
    local l = (type(v) == "table") and v or { v }
    local parts = {}
    for _, a in ipairs(l) do
        parts[#parts + 1] = (type(a) == "number") and RTL_PE_EnemyActName(tl, a) or tostring(a)
    end
    return table.concat(parts, "/")
end

function RTL_PE_SetOnAction(e, v, tl)
    local function key(x)
        if (x == nil) then return "" end
        if (type(x) == "table") then
            local l = {}
            for _, a in ipairs(x) do l[#l + 1] = tostring(a) end
            return table.concat(l, ",")
        end
        return tostring(x)
    end
    if (key(e.onAction) == key(v)) then
        return
    end
    local old = (e.onAction ~= nil) and RTL_PE_OnActionText(e, tl) or "どれが来ても"
    e.onAction = v
    RTL_PE_Changed(e, "分岐 "..old.." -> "..((v ~= nil) and RTL_PE_OnActionText(e, tl) or "どれが来ても"))
end

function RTL_PE_DrawBranchRow(e, ev, tl)
    local acts = RTL_PE_EventActs(ev)
    if (#acts < 2 and e.onAction == nil) then
        return
    end
    RTL_UI_Muted("分岐")
    GUI:SameLine()
    local items = { { "", "どれが来ても" } }
    for _, a in ipairs(acts) do
        items[#items + 1] = { tostring(a), RTL_PE_EnemyActName(tl, a).."のとき" }
    end
    local cur = ""
    if (type(e.onAction) == "number") then
        cur = tostring(e.onAction)
    elseif (type(e.onAction) == "table") then
        if (#e.onAction == 1) then
            cur = tostring(e.onAction[1])
        else
            cur = "multi"
            items[#items + 1] = { "multi", RTL_PE_OnActionText(e, tl).."のとき" }
        end
    end
    local found = false
    for _, it in ipairs(items) do if (it[1] == cur) then found = true end end
    if (not found) then
        items[#items + 1] = { cur, RTL_PE_OnActionText(e, tl).."のとき" }
    end
    local pick = RTL_UI_Segmented("pebr", items, cur)
    if (pick ~= nil and pick ~= cur and pick ~= "multi") then
        RTL_PE_SetOnAction(e, (pick ~= "") and tonumber(pick) or nil, tl)
    end
    RTL_UI_Muted("照合した技で使うか決めます（照合を待つので、詠唱より前のタイミングには向きません）")
end

-- アクションを選ぶ
function RTL_PE_DrawPicker(cur, pk, onPick)
    local P = RTL.pe
    local acts = RTL_PE_JobActions()
    GUI:Spacing()
    local tabs = { { "oGCD", "oGCD "..acts.n.oGCD }, { "GCD", "GCD "..acts.n.GCD } }
    if (acts.n["?"] > 0) then
        tabs[#tabs + 1] = { "?", "その他 "..acts.n["?"] }
    end
    for ti, tb in ipairs(tabs) do
        if (ti > 1) then GUI:SameLine(0, 4) end
        local tone = (pk.tab == tb[1]) and RTL_PE_KindTone(tb[1]) or nil
        if (pk.tab == tb[1] and tb[1] == "?") then tone = "primary" end
        if (RTL_UI_Button(tb[2].."##petab"..ti, tone, true)) then
            pk.tab = tb[1]
            pk.warn = nil
        end
    end
    GUI:SameLine()
    if (RTL_UI_Button("作り直す##perebuild", nil, true)) then
        RTL_PE_JobActions(true)
        RTL.pe.extra = nil
    end
    GUI:PushItemWidth(160)
    local q, ch = GUI:InputText("名前か ID で絞る##peq", pk.q or "")
    GUI:PopItemWidth()
    if (type(q) == "string" and (ch or q ~= pk.q)) then
        pk.q = q
    end
    if (acts.err) then
        RTL_UI_Text(acts.err, "error")
    end
    if (pk.tab == "GCD") then
        RTL_UI_Text("GCD は実行がまだ対応していないので、今は選べません", "warning")
    end
    if (pk.warn) then
        RTL_UI_Text(pk.warn, "warning")
    end
    -- このプランで使っているもの（同じ区分のもの）を先に
    local used, usedSet = {}, {}
    for _, x in ipairs(P.raw.entries) do
        if (type(x) == "table" and type(x.action) == "table" and type(x.action.id) == "number" and not usedSet[x.action.id]) then
            usedSet[x.action.id] = true
            used[#used + 1] = RTL_PE_ActInfo(x.action.id)
        end
    end
    local query = tostring(pk.q or ""):lower()
    local function match(it)
        if (it.kind ~= pk.tab) then return false end
        if (query == "") then return true end
        return (tostring(it.name):lower():find(query, 1, true) ~= nil) or (tostring(it.id):find(query, 1, true) ~= nil)
    end
    local function row(it, key)
        local tone = (it.id == cur) and "primary" or RTL_PE_KindTone(it.kind)
        if (RTL_UI_Button(it.name.."##pea"..key..it.id, tone, true)) then
            if (it.kind == "GCD") then
                pk.warn = it.name.." は GCD です（未対応）"
            else
                pk.warn = nil
                onPick(it)
            end
        end
        GUI:SameLine()
        RTL_UI_Muted(string.format("Lv%d  #%d", it.level or 0, it.id))
    end
    local nUsed = 0
    for _, it in ipairs(used) do
        if (match(it)) then
            if (nUsed == 0) then RTL_UI_Title("このプランで使っているもの") end
            nUsed = nUsed + 1
            row(it, "u")
        end
    end
    local n = 0
    for _, it in ipairs(acts.list) do
        if (match(it) and not usedSet[it.id]) then
            if (n == 0) then RTL_UI_Title("このジョブのアクション") end
            n = n + 1
            row(it, "j")
        end
    end
    if (n + nUsed == 0) then
        RTL_UI_Muted("ありません")
    end
    RTL_UI_Muted(string.format("一覧 %d 件（ジョブ %d・ロールと共通 %d、全アクション %d）", #acts.list, acts.byJob, acts.byRole, acts.total))
    GUI:SameLine()
    if (RTL_UI_Button("一覧をログに書く##pedump", nil, true)) then
        RTL_PE_DumpActions()
    end
end

-- =====================================================================
-- 音（v0.4.0）：プランのエントリの sound で wav を鳴らす（設計書 10.4）
--
--   書き方：sound = "x.wav"  または  sound = { file = "x.wav", byAction = { [45341] = "a.wav", [45336] = "b.wav" } }
--     時刻はアクションと同じ（event・ref・offset）。action と一緒に書いてもよい（音はアクションの判定・実行とは別に鳴る）
--     byAction：イベントを照合した詠唱のアクション ID で音を選ぶ（分岐ごとの音）。
--               照合より前に時刻が来たら、照合を待って鳴らす（ユーザーの決定）。未照合で終わったら file（共通の音）。
--   鳴らし方：MMOminion・minionlib・ffxivminion に音を鳴らす関数は無い → PowerShell の System.Media.SoundPlayer
--     resident（既定）：PowerShell を 1 つ常駐させ（io.popen の "w"）、1 行ずつ送る。ゲームは待たない。
--                      戦闘していないときに起動しておく。1 度読んだ wav は覚えておく（Load 済み）
--     oneshot        ：鳴らすたびに start /b で PowerShell を起動する（遅れ 0.3〜1 秒。常駐が動かないときの予備）
--     送ってから鳴るまでの遅れ：PowerShell が logs\sound_ack.txt に [Environment]::TickCount を書き、Now() と比べる
--   スイッチ：settings.sound（実行の ON/OFF・一時停止とは別。一時停止中も鳴らす：ユーザーの決定）
--   ログ：ドライランのログに kind = sound（予定・実際・ずれ・ファイル・結果。再生の確認が来たら「再生まで n ms」を足す）
--   wav のファイル名：英数字・_・- と .wav だけ。置き場所も英数字のパスだけ（PowerShell に渡すため）
-- =====================================================================

RTL.SND = {
    lateMaxSec      = 2.0,   -- 予定（照合を待ったときは照合した時刻）からこれ以上遅れたら鳴らさない
    pollSec         = 0.5,   -- 再生の確認（sound_ack.txt）を読む間隔
    ackWaitSec      = 10,    -- これ以上たっても確認が来なければあきらめる
    readyWaitSec    = 10,    -- 常駐を起動してから、これ以上たっても準備完了（R 行）が来なければ毎回起動に切り替える
    retryStartSec   = 10,    -- 起動に失敗したら、この秒数は起動し直さない
    oneshotCloseSec = 5,     -- 毎回起動の io.popen を閉じるまでの秒数（閉じると cmd の終了を待つので、終わってから閉じる）
    keepDelays      = 20,
    leadStep        = 0.05,
    leadMax         = 1.0,
    psCmd = "powershell -NoProfile -NoLogo -ExecutionPolicy Bypass -WindowStyle Hidden -Command -",
    -- 常駐の PowerShell に最初に送る 2 行（$global:a に確認のファイル、関数 P が再生）
    psFunc = [[function P([string]$f,[int]$n){$t=[Environment]::TickCount;try{$p=$global:c[$f];if($p -eq $null){$p=New-Object System.Media.SoundPlayer $f;$p.Load();$global:c[$f]=$p};$p.Play();[IO.File]::AppendAllText($global:a,"$n $t $([Environment]::TickCount)`r`n")}catch{[IO.File]::AppendAllText($global:a,"E $n $t $($_.Exception.Message -replace '\s+',' ')`r`n")}}]],
}

RTL.snd = RTL.snd or {}
RTL.snd.seq      = RTL.snd.seq or 0
RTL.snd.pending  = RTL.snd.pending or {}    -- [番号] = { ms, file, row }（再生の確認待ち）
RTL.snd.delays   = RTL.snd.delays or {}     -- 送ってから鳴るまで（ms）
RTL.snd.files    = RTL.snd.files or {}      -- [ファイル名] = あるか
RTL.snd.oneshots = RTL.snd.oneshots or {}   -- 毎回起動の io.popen（あとで閉じる）
RTL.snd.lastPoll = 0
RTL.snd.status   = RTL.snd.status or "未起動"

function RTL_SND_Dir()
    local d = RTL.settings.soundDir
    if (type(d) ~= "string" or d == "") then
        d = RTL.path.."\\wav"
    end
    return (d:gsub("[\\/]+$", ""))
end

function RTL_SND_Path(f)
    return RTL_SND_Dir().."\\"..tostring(f)
end

function RTL_SND_AckPath()
    return RTL.path.."\\logs\\sound_ack.txt"
end

function RTL_SND_ValidName(f)
    return type(f) == "string" and f:match("^[%w_%-]+%.[wW][aA][vV]$") ~= nil
end

-- 英数字のパスだけ（PowerShell の標準入力・コマンドラインに日本語を通さない）
function RTL_SND_AsciiPath(p)
    return not tostring(p):find("[\128-\255]")
end

-- PowerShell の文字列（'...'。中の ' は ''）
function RTL_SND_PsQuote(s)
    return "'"..(tostring(s):gsub("'", "''")).."'"
end

function RTL_SND_Exists(f, refresh)
    local c = RTL.snd.files[f]
    if (c ~= nil and not refresh) then
        return c
    end
    local fh = io.open(RTL_SND_Path(f), "rb")
    local ok = (fh ~= nil)
    if (fh) then
        fh:close()
    end
    RTL.snd.files[f] = ok
    return ok
end

-- プランのエントリの sound を読む（使えなければ nil。注意は warn に足す）
function RTL_SND_ParseEntry(e, warn)
    local s = e.sound
    if (s == nil) then
        return nil
    end
    local out = { file = nil, byAction = nil }
    local function name(v, where)
        if (v == nil) then
            return nil
        end
        if (RTL_SND_ValidName(v)) then
            return v
        end
        warn[#warn + 1] = tostring(e.id)..": "..where.." のファイル名が使えません（英数字・_・- と .wav）: "..tostring(v)
        return nil
    end
    if (type(s) == "string") then
        out.file = name(s, "sound")
    elseif (type(s) == "table") then
        out.file = name(s.file, "sound.file")
        if (type(s.byAction) == "table") then
            for k, v in pairs(s.byAction) do
                local id = tonumber(k)
                local f = name(v, "sound.byAction["..tostring(k).."]")
                if (id and f) then
                    out.byAction = out.byAction or {}
                    out.byAction[id] = f
                end
            end
        end
    else
        warn[#warn + 1] = tostring(e.id)..": sound の書き方が違います（\"x.wav\" か { file = ..., byAction = { [ID] = ... } }）"
        return nil
    end
    if (not out.file and not out.byAction) then
        return nil
    end
    return out
end

function RTL_SND_EntryFiles(snd)
    local list, seen = {}, {}
    local function add(f)
        if (f and not seen[f]) then
            seen[f] = true
            list[#list + 1] = f
        end
    end
    add(snd.file)
    if (snd.byAction) then
        local ids = {}
        for id in pairs(snd.byAction) do ids[#ids + 1] = id end
        table.sort(ids)
        for _, id in ipairs(ids) do add(snd.byAction[id]) end
    end
    return list
end

-- プランを読んだ：音のエントリがあれば、戦闘していないときに常駐の PowerShell を起動しておく
function RTL_SND_OnPlanLoaded(n)
    if (n > 0 and RTL.settings.sound == true and RTL.settings.soundMode ~= "oneshot") then
        RTL.snd.wantStart = true
    end
    if (RTL_SND_PIPE) then
        RTL_SND_Write("$global:c=@{}")   -- 覚えた wav を捨てる（差し替えた wav を読み直す）
    end
end

-- 2 つのミリ秒の差（GetTickCount は 32 ビットで一周するので、その分を直す）
function RTL_SND_TickDiff(a, b)
    if (type(a) ~= "number" or type(b) ~= "number") then
        return nil
    end
    local d = (a - b) % 4294967296
    if (d >= 2147483648) then
        d = d - 4294967296
    end
    return d
end

-- ---------------------------------------------------------------------
-- PowerShell（常駐）
-- ---------------------------------------------------------------------

function RTL_SND_Start(now)
    local S = RTL.snd
    if (RTL_SND_PIPE) then
        return true
    end
    if (S.failMs and now - S.failMs < RTL.SND.retryStartSec * 1000) then
        return false
    end
    if (type(io.popen) ~= "function") then
        S.status, S.failMs = "io.popen がありません", now
        return false
    end
    if (not RTL_SND_AsciiPath(RTL_SND_AckPath())) then
        S.status, S.failMs = "RaidTimeline の場所に英数字以外が含まれるので使えません", now
        return false
    end
    RTL_EnsureFolder(RTL.path.."\\logs")
    local t1 = RTL_Now()
    local ok, p = pcall(io.popen, RTL.SND.psCmd, "w")
    local t2 = RTL_Now()
    if (not ok or not p) then
        S.status, S.failMs = "PowerShell を起動できません: "..tostring(p), now
        RTL_Msg("sound: "..S.status)
        return false
    end
    RTL_SND_PIPE = p
    S.startMs, S.popenMs, S.readyTick, S.startupMs, S.noReadyWarned = t2, t2 - t1, nil, nil, nil
    S.status = "常駐（起動中）"
    S.starts = (S.starts or 0) + 1
    local ok1 = RTL_SND_Write("$global:c=@{};$global:a="..RTL_SND_PsQuote(RTL_SND_AckPath())..
        ";[IO.File]::WriteAllText($global:a,\"R $([Environment]::TickCount)`r`n\")")
    local ok2 = ok1 and RTL_SND_Write(RTL.SND.psFunc)
    RTL_Msg(string.format("sound: PowerShell started (io.popen %d ms)%s", S.popenMs, (ok1 and ok2) and "" or " / write failed"))
    return ok1 and ok2
end

-- 1 行送る（失敗したら、その PowerShell は捨てる。閉じると終わるのを待つので、閉じずにとっておく）
function RTL_SND_Write(line)
    local p = RTL_SND_PIPE
    if (not p) then
        return false, "未起動"
    end
    local ok, err = pcall(function()
        local r, e = p:write(line.."\n")
        if (not r) then error(e or "write failed") end
        local r2, e2 = p:flush()
        if (r2 == nil and e2) then error(e2) end
    end)
    if (not ok) then
        RTL_SND_PIPE = nil
        RTL_SND_DEAD = RTL_SND_DEAD or {}
        RTL_SND_DEAD[#RTL_SND_DEAD + 1] = p
        RTL.snd.status = "PowerShell に送れません: "..tostring(err)
        RTL.snd.failMs = RTL_Now()       -- しばらく起動し直さない（起動のたびに窓が出て、ゲームも一瞬待つため）
        RTL.snd.deadCount = (RTL.snd.deadCount or 0) + 1
        if (RTL.snd.deadCount >= 2 and RTL.settings.soundMode ~= "oneshot") then
            RTL.settings.soundMode = "oneshot"   -- 2 回送れなかったら毎回起動に切り替える（設定ファイルは変えない）
            RTL.snd.status = RTL.snd.status.." → 毎回起動に切り替えた"
        end
        RTL_Msg("sound: "..RTL.snd.status)
        return false, tostring(err)
    end
    return true
end

-- ---------------------------------------------------------------------
-- PowerShell（毎回起動）：-EncodedCommand（UTF-16LE の base64）で渡す
-- ---------------------------------------------------------------------

function RTL_SND_B64U16(s)
    local bytes = {}
    for i = 1, #s do
        bytes[#bytes + 1] = s:byte(i)
        bytes[#bytes + 1] = 0
    end
    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local out = {}
    for i = 1, #bytes, 3 do
        local a, b, c = bytes[i], bytes[i + 1], bytes[i + 2]
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1 = math.floor(n / 262144) % 64
        local c2 = math.floor(n / 4096) % 64
        local c3 = math.floor(n / 64) % 64
        local c4 = n % 64
        out[#out + 1] = chars:sub(c1 + 1, c1 + 1)..chars:sub(c2 + 1, c2 + 1)..
            (b and chars:sub(c3 + 1, c3 + 1) or "=")..(c and chars:sub(c4 + 1, c4 + 1) or "=")
    end
    return table.concat(out)
end

function RTL_SND_PlayOneshot(path, n)
    local S = RTL.snd
    local ack = RTL_SND_AckPath()
    if (not S.oneshotInit) then
        RTL_EnsureFolder(RTL.path.."\\logs")
        RTL_WriteFile(ack, "")
        S.oneshotInit = true
    end
    local script = "$t=[Environment]::TickCount;$p=New-Object System.Media.SoundPlayer "..RTL_SND_PsQuote(path)..
        ";$p.Load();[IO.File]::AppendAllText("..RTL_SND_PsQuote(ack)..",\""..n.." $t $([Environment]::TickCount)`r`n\");$p.PlaySync()"
    local cmd = "start \"\" /b powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand "..
        RTL_SND_B64U16(script)
    local ok, p = pcall(io.popen, cmd, "r")
    if (not ok or not p) then
        return false, tostring(p)
    end
    S.oneshots[#S.oneshots + 1] = { p = p, closeAt = RTL_Now() + RTL.SND.oneshotCloseSec * 1000 }
    return true
end

function RTL_SND_CloseOneshots(now)
    local S = RTL.snd
    if (#S.oneshots == 0) then
        return
    end
    local keep = {}
    for _, o in ipairs(S.oneshots) do
        if (now >= o.closeAt) then
            pcall(function() o.p:close() end)
        else
            keep[#keep + 1] = o
        end
    end
    S.oneshots = keep
end

-- ---------------------------------------------------------------------
-- 鳴らす
-- ---------------------------------------------------------------------

-- 戻り値：ok, 失敗の理由, 番号
function RTL_SND_Play(file, row, now)
    local S = RTL.snd
    if (not RTL_SND_ValidName(file)) then
        return false, "ファイル名が使えません"
    end
    local path = RTL_SND_Path(file)
    if (not RTL_SND_AsciiPath(path)) then
        return false, "置き場所に英数字以外が含まれる"
    end
    if (not RTL_SND_Exists(file)) then
        return false, "ファイルが無い"
    end
    S.seq = S.seq + 1
    local n = S.seq
    local mode = (RTL.settings.soundMode == "oneshot") and "oneshot" or "resident"
    local t1 = RTL_Now()
    local ok, err
    if (mode == "oneshot") then
        ok, err = RTL_SND_PlayOneshot(path, n)
    else
        local line = "P "..RTL_SND_PsQuote(path).." "..n
        if (not RTL_SND_PIPE) then
            RTL_SND_Start(now)
        end
        ok, err = RTL_SND_Write(line)
        if (not ok and err ~= "未起動" and RTL_SND_Start(now)) then
            ok, err = RTL_SND_Write(line)     -- 送れなかったら 1 回だけ起動し直して送り直す
        end
        if (not ok and err == "未起動") then
            err = "PowerShell が動いていない（"..tostring(S.status).."）"
        end
    end
    local cost = RTL_Now() - t1
    S.callMs = cost
    if (cost > (S.callMaxMs or 0)) then S.callMaxMs = cost end
    if (not ok) then
        return false, "再生の失敗: "..tostring(err)
    end
    S.pending[n] = { ms = now, file = file, row = row, mode = mode }
    return true, nil, n
end

-- 再生の確認（sound_ack.txt）を読む。常駐の準備完了（R 行）も見る
function RTL_SND_Poll(now)
    local S = RTL.snd
    local needReady = (RTL_SND_PIPE ~= nil and S.readyTick == nil)
    if (next(S.pending) == nil and not needReady) then
        return
    end
    local s = RTL_ReadFile(RTL_SND_AckPath())
    if (s) then
        for line in s:gmatch("[^\r\n]+") do
            local r = line:match("^R%s+(%-?%d+)")
            if (r and needReady) then
                S.readyTick = tonumber(r)
                S.startupMs = RTL_SND_TickDiff(S.readyTick, S.startMs)
                if (S.startupMs and math.abs(S.startupMs) > 60000) then
                    S.startupMs = nil
                    S.clockMismatch = true
                end
                S.status = "常駐（準備完了）"
                needReady = false
            end
            local n, t0, t1 = line:match("^(%d+)%s+(%-?%d+)%s+(%-?%d+)")
            local pd = n and S.pending[tonumber(n)]
            if (pd) then
                S.pending[tonumber(n)] = nil
                local recv = RTL_SND_TickDiff(tonumber(t0), pd.ms)
                local play = RTL_SND_TickDiff(tonumber(t1), pd.ms)
                local note
                if (not play or math.abs(play) > 60000) then
                    S.clockMismatch = true
                    note = "再生を確認（時計が違うので遅れは測れない）"
                else
                    S.delays[#S.delays + 1] = play
                    while (#S.delays > RTL.SND.keepDelays) do table.remove(S.delays, 1) end
                    S.lastDelay = play
                    note = string.format("再生まで %d ms（受け取り %d ms）", play, recv or -1)
                end
                if (pd.row) then pd.row.detail = (pd.row.detail or "").." / "..note end
                if (S.last and S.last.n == tonumber(n)) then S.last.ack = note end
            end
            local en, emsg = line:match("^E%s+(%d+)%s+%-?%d+%s*(.*)$")
            local ed = en and S.pending[tonumber(en)]
            if (ed) then
                S.pending[tonumber(en)] = nil
                S.errors = (S.errors or 0) + 1
                local note = "PowerShell のエラー: "..tostring(emsg)
                if (ed.row) then ed.row.detail = (ed.row.detail or "").." / "..note end
                if (S.last and S.last.n == tonumber(en)) then S.last.ack = note end
            end
        end
    end
    for n, pd in pairs(S.pending) do
        if (now - pd.ms > RTL.SND.ackWaitSec * 1000) then
            S.pending[n] = nil
            S.noAck = (S.noAck or 0) + 1
            if (pd.row) then pd.row.detail = (pd.row.detail or "").." / 再生の確認なし" end
            if (S.last and S.last.n == n) then S.last.ack = "再生の確認なし" end
        end
    end
    -- 常駐から応答が無い（1 行ずつ実行されていない）→ 毎回起動に切り替える（設定ファイルは変えない）
    if (RTL_SND_PIPE and S.readyTick == nil and S.startMs and now - S.startMs > RTL.SND.readyWaitSec * 1000 and not S.noReadyWarned) then
        S.noReadyWarned = true
        S.status = "常駐の PowerShell から応答がない → 毎回起動に切り替えた"
        RTL.settings.soundMode = "oneshot"
        RTL_Msg("sound: "..S.status)
    end
end

function RTL_SND_Tick(now)
    local S = RTL.snd
    -- 常駐の PowerShell は、戦闘していないときに起動しておく（起動の遅れ・窓のちらつきを戦闘中に起こさない）
    if (S.wantStart and Player and not Player.incombat) then
        S.wantStart = false
        if (RTL.settings.sound == true and RTL.settings.soundMode ~= "oneshot") then
            RTL_SND_Start(now)
        end
    end
    if (now - (S.lastPoll or 0) >= RTL.SND.pollSec * 1000) then
        S.lastPoll = now
        RTL_SND_Poll(now)
        RTL_SND_CloseOneshots(now)
    end
end

-- ---------------------------------------------------------------------
-- プルの中（ドライランの時計で鳴らす）
-- ---------------------------------------------------------------------

function RTL_SND_DelayText()
    local S = RTL.snd
    if (#S.delays == 0) then
        return S.clockMismatch and "遅れ：時計が違うので測れない" or "遅れ：まだ測っていない"
    end
    local sum, mx = 0, nil
    for _, v in ipairs(S.delays) do
        sum = sum + v
        if (not mx or v > mx) then mx = v end
    end
    return string.format("遅れ（実測）平均 %d ms 最大 %d ms（%d 回）", math.floor(sum / #S.delays + 0.5), mx, #S.delays)
end

function RTL_SND_ModeText()
    return (RTL.settings.soundMode == "oneshot") and "毎回起動" or "常駐"
end

-- プルの始めに、音の設定と状態をドライランのログに残す
function RTL_SND_PullInfo()
    local T = RTL.tl
    if ((T.planSounds or 0) == 0) then
        return
    end
    local S = RTL.snd
    RTL_TL_Row("sound_info", { result = (RTL.settings.sound == true) and "ON" or "OFF",
        detail = string.format("音のエントリ %d 件 / 方式 %s / 早め %.2f 秒 / PowerShell %s%s / %s / 置き場所 %s",
            T.planSounds, RTL_SND_ModeText(), RTL.settings.soundLead or 0, tostring(S.status),
            S.startupMs and string.format("（起動 %d ms・io.popen %d ms）", S.startupMs, S.popenMs or 0) or "",
            RTL_SND_DelayText(), RTL_SND_Dir()) })
end

function RTL_SND_Row(sr, now, due, base, result, detail, spell)
    local e = sr.entry
    local row = RTL_TL_Row("sound", { ms = now, phase = sr.phase, clock = RTL_TL_Clock(sr.phase, now), ref = e.id,
        action = spell, planned = base and RTL_TL_Clock(sr.phase, base), actual = RTL_TL_Clock(sr.phase, now),
        diff = due and (now - due) / 1000 or nil, result = result,
        detail = tostring(detail or "").." → "..RTL_TL_EventLabel(sr.ev)..string.format("（%s %+.1f）", e.ref, e.offset)..
            string.format(" / 早め %.2f 秒 / %s", RTL.settings.soundLead or 0, RTL_SND_ModeText()) })
    return row
end

function RTL_SND_Done(sr, now, due, base, result, detail, spell)
    sr.status = "done"
    sr.result = result
    local row = RTL_SND_Row(sr, now, due, base, result, detail, spell)
    RTL_TL_Recent(string.format("[%s] 音 %s：%s", RTL_TL_FmtT(now), tostring(detail or ""), result))
    return row
end

-- フェーズ移行・戦闘終了：まだ鳴らしていない音を打ち切る（phaseId が nil なら全部）
function RTL_SND_CutPull(pull, phaseId, ms, result, detail)
    if (not pull or not pull.sounds) then
        return
    end
    for _, sr in ipairs(pull.sounds) do
        if ((sr.status == "wait" or sr.status == "waitmatch") and (phaseId == nil or sr.phase == phaseId)) then
            sr.status = "done"
            sr.result = result
            RTL_TL_Row("sound", { ms = ms, phase = sr.phase, ref = sr.entry.id, result = result,
                detail = table.concat(RTL_SND_EntryFiles(sr.entry.snd), "/").." → "..RTL_TL_EventLabel(sr.ev)..
                    ((detail ~= "") and (" / "..detail) or "") })
        end
    end
end

function RTL_SND_Run(now)
    local pull = RTL.tl.pull
    if (not pull or not pull.sounds) then
        return
    end
    local lead = (RTL.settings.soundLead or 0) * 1000
    for _, sr in ipairs(pull.sounds) do
        if (sr.phase == pull.cur and (sr.status == "wait" or sr.status == "waitmatch")) then
            local base = RTL_TL_ExecMs(sr)
            if (base and now >= base - lead) then
                RTL_SND_Fire(sr, now, base, base - lead)
            end
        end
    end
end

function RTL_SND_Fire(sr, now, base, due)
    local pull = RTL.tl.pull
    local snd = sr.entry.snd
    local m = pull.matches[sr.ev.id]
    local file, note = snd.file, nil
    local refMs = due
    local spell = m and m.spell or nil
    if (snd.byAction) then
        if (m) then
            if (snd.byAction[m.spell]) then
                file = snd.byAction[m.spell]
            else
                note = "分岐 "..tostring(m.spell).." の音が無いので共通の音"
            end
            if (sr.status == "waitmatch") then
                refMs = math.max(due, m.ms)
                note = string.format("照合を待った（%.1f 秒）", (now - (sr.firstDue or due)) / 1000)
                    ..(note and (" / "..note) or "")
            end
        elseif (pull.nomatch[sr.ev.id]) then
            note = "未照合のため共通の音"
            refMs = now
        else
            -- まだ照合していない：照合（詠唱開始）を待つ
            if (sr.status ~= "waitmatch") then
                sr.status = "waitmatch"
                sr.firstDue = due
                RTL_TL_Recent(string.format("[%s] 音：照合を待つ（%s）", RTL_TL_FmtT(now), RTL_TL_EventLabel(sr.ev)))
            end
            return
        end
    end
    local function withNote(s)
        return note and (s.." / "..note) or s
    end
    if (not file) then
        return RTL_SND_Done(sr, now, due, base, "鳴らさない（対応する音なし）", withNote("-"), spell)
    end
    if (RTL.settings.sound ~= true) then
        return RTL_SND_Done(sr, now, due, base, "鳴らさない（音 OFF）", withNote(file), spell)
    end
    local late = (now - refMs) / 1000
    if (late > RTL.SND.lateMaxSec) then
        return RTL_SND_Done(sr, now, due, base, string.format("鳴らさない（%.1f 秒遅れ）", late), withNote(file), spell)
    end
    local ok, why, n = RTL_SND_Play(file, nil, now)
    local st = pull.stats
    local result
    if (ok) then
        st.sounds = (st.sounds or 0) + 1
        result = (late > 0.3) and string.format("鳴らした（%.1f 秒遅れ）", late) or "鳴らした"
    else
        st.soundFail = (st.soundFail or 0) + 1
        result = "鳴らせない（"..tostring(why).."）"
    end
    local row = RTL_SND_Done(sr, now, due, base, result, withNote(file), spell)
    if (ok and n and RTL.snd.pending[n]) then
        RTL.snd.pending[n].row = row
    end
    RTL.snd.last = { file = file, ms = now, result = result, n = n }
end

-- 画面の「テスト再生」：プランの最初の wav（無ければ test_common.wav）
function RTL_SND_Test(now)
    local T = RTL.tl
    local file = nil
    if (T.plan) then
        for _, e in ipairs(T.plan.entries) do
            if (e.snd and not file) then
                for _, f in ipairs(RTL_SND_EntryFiles(e.snd)) do
                    if (not file and RTL_SND_Exists(f, true)) then file = f end
                end
            end
        end
    end
    file = file or "test_common.wav"
    RTL_SND_Exists(file, true)
    local ok, why, n = RTL_SND_Play(file, nil, now)
    RTL.snd.last = { file = file, ms = now, result = ok and "テスト" or ("鳴らせない（"..tostring(why).."）"), n = n }
    RTL_Msg("sound test: "..file.." "..tostring(RTL.snd.last.result))
end

-- 画面（ドライランの画面の「音」のカード。v0.5.0 から部品で描く。ON / OFF は上のスイッチの行）
function RTL_SND_DrawControls(now)
    local S = RTL.snd
    RTL_UI_Title("音")
    GUI:SameLine()
    RTL_UI_Badge((RTL.settings.sound == true) and "ON" or "OFF", (RTL.settings.sound == true) and "success" or "neutral")
    GUI:SameLine()
    if (RTL_UI_Button("テスト再生##sndtest", nil, true)) then
        RTL_SND_Test(now)
    end
    GUI:SameLine()
    if (RTL_UI_Button("方式: "..RTL_SND_ModeText().."##sndmode", nil, true)) then
        RTL.settings.soundMode = (RTL.settings.soundMode == "oneshot") and "resident" or "oneshot"
        RTL_SaveSettings()
        if (RTL.settings.soundMode == "resident") then S.wantStart = true end
    end
    GUI:SameLine()
    RTL_UI_Muted(string.format("早め %.2f 秒", RTL.settings.soundLead or 0))
    GUI:SameLine()
    if (RTL_UI_Button("-##sndlead", nil, true)) then
        RTL.settings.soundLead = math.max(0, (RTL.settings.soundLead or 0) - RTL.SND.leadStep)
        RTL_SaveSettings()
    end
    GUI:SameLine(0, 4)
    if (RTL_UI_Button("+##sndlead", nil, true)) then
        RTL.settings.soundLead = math.min(RTL.SND.leadMax, (RTL.settings.soundLead or 0) + RTL.SND.leadStep)
        RTL_SaveSettings()
    end
    local st = tostring(S.status)
    if (S.startupMs) then
        st = st..string.format("（起動 %d ms）", S.startupMs)
    end
    RTL_UI_Muted("PowerShell")
    GUI:SameLine()
    RTL_UI_Text(st)
    GUI:SameLine()
    RTL_UI_Muted(RTL_SND_DelayText())
    if (not RTL_TL_Enabled()) then
        RTL_UI_Text("ドライランが OFF なのでプランの音は鳴りません", "warning")
    end
    local la = S.last
    if (la) then
        RTL_UI_Muted("最後に鳴らした音")
        GUI:SameLine()
        RTL_UI_Text(tostring(la.file), "accent")
        GUI:SameLine()
        RTL_UI_Muted(string.format("%s・%.1f 秒前%s", tostring(la.result), (now - la.ms) / 1000, la.ack and ("  "..la.ack) or ""))
    end
end

-- =====================================================================
-- 初期化
-- =====================================================================

function RTL_Init()
    RTL_EnsureFolder(RTL.path.."\\logs")
    RTL_EnsureFolder(RTL.path.."\\names")
    RTL_EnsureFolder(RTL.path.."\\wav")
    RTL_LoadSettings()
    for _, kind in ipairs({ "actions", "npcs", "buffs" }) do
        local ok, t = pcall(RTL_LoadNameFile, kind)
        if (not ok) then
            RTL_Msg("names/"..kind..".lua: "..tostring(t))
            t = nil
        end
        if (t) then
            RTL.names[kind] = t
        else
            RTL.names[kind] = nil        -- 読めなかった辞書は上書きしない
            RTL.namesDirty[kind] = false
        end
    end
    RTL_RegisterArgus()
    pcall(RTL_EX_RegisterHotkey)
    -- MMOminion のメニューに「RaidTimeline」を追加（ウィンドウを閉じても開き直せるように）
    pcall(function()
        ml_gui.ui_mgr:AddComponent({
            header = { id = "RAIDTIMELINE##MENU_HEADER", expanded = false, name = "RaidTimeline" },
            members = {
                { id = "RAIDTIMELINE##MENU_MAIN", name = "Recorder", tooltip = "RaidTimeline の記録モード",
                  onClick = function() RTL.window.open = not RTL.window.open RTL_SaveSettings() end },
                { id = "RAIDTIMELINE##MENU_DRY", name = "Dry-run", tooltip = "RaidTimeline のドライラン",
                  onClick = function() RTL.window2.open = not RTL.window2.open RTL_SaveSettings() end },
                { id = "RAIDTIMELINE##MENU_TV", name = "Timeline", tooltip = "RaidTimeline のタイムライン表示",
                  onClick = function() RTL.settings.tvShow = (RTL.settings.tvShow == false) RTL_SaveSettings() end },
                { id = "RAIDTIMELINE##MENU_PE", name = "Plan", tooltip = "RaidTimeline のプラン編集",
                  onClick = function() RTL.pe.open = not RTL.pe.open RTL_SaveSettings() end },
            },
        })
    end)
    RTL.initDone = true
    RTL_Msg("initialized v"..RTL.version.."  path="..RTL.path.."  execute="..tostring(RTL.settings.execute))
end

function RTL_OnModuleInit()
    RTL_Safe("Init", RTL_Init)
    if (not RTL.initDone) then
        RTL.initDone = true     -- 初期化の一部が失敗しても、記録は動かす
    end
end

RegisterEventHandler("Module.Initalize", RTL_OnModuleInit, "RaidTimeline.Init")
RegisterEventHandler("Gameloop.Update", RTL_Update, "RaidTimeline.Update")
RegisterEventHandler("Gameloop.Draw", RTL_Draw, "RaidTimeline.Draw")
RegisterEventHandler("Gameloop.Draw", RTL_TL_DrawWindow, "RaidTimeline.DrawDry")
RegisterEventHandler("Gameloop.Draw", RTL_TV_Draw, "RaidTimeline.DrawTV")
RegisterEventHandler("Gameloop.Draw", RTL_PE_Draw, "RaidTimeline.DrawPE")
