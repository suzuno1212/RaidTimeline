-- MMOminion の API を模した最小限の環境（ドライランの検証用）
-- setfenv / loadstring / load / loadfile / dofile は消す（実機に合わせる・読み込みが実行に頼っていないことの確認）
setfenv = nil
loadstring = nil
load = nil
loadfile = nil
dofile = nil

SIM = { now = 1000000, ents = {}, handlers = {}, argus = {}, log = {}, lastUse = {}, clicks = {},
        recast = { [7531] = 90, [7535] = 60, [25746] = 5, [36920] = 120, [3540] = 90, [7548] = 120, [30] = 420, [9] = 2.5 },
        casts = {}, queue = {}, lockUntil = 0, acr = false, acrNext = 0, castMode = "normal", acrUses = {} }

function Now() return SIM.now end
function d(x) SIM.log[#SIM.log + 1] = tostring(x) end
function GetLuaModsPath() return "SIMROOT" end

-- パス変換（SIMROOT\a\b → <root>/a/b）
local real_open = io.open
function SIM_Path(p) return (p:gsub("^SIMROOT", SIM_ROOT):gsub("\\", "/")) end
io.open = function(p, m) return real_open(SIM_Path(p), m) end
function FolderExists(p) return PY_ISDIR(SIM_Path(p)) end
function FolderCreate(p) PY_MKDIR(SIM_Path(p)) return true end
function FileSave(p, t) SIM.saved = t return true end
function FileLoad(p) return SIM.saved end
if SIM_USE_FOLDERLIST then
    function FolderList(dir, pattern, folders)
        local t = {}
        local list = PY_LISTDIR(SIM_Path(dir))
        for i = 1, #list do
            if list[i]:match(pattern) then t[#t + 1] = dir.."\\"..list[i] end
        end
        return t
    end
else
    FolderList = nil
end
-- 音（v0.4.0）：PowerShell の模擬。常駐（-Command -）は送られた行を SIM.psLines に控え、
--   初めの行で sound_ack.txt に R 行、P 行で「番号 受け取り 再生」を書く（時計は SIM.now ＋ SIM.psDelay）
--   毎回起動（start /b ... -EncodedCommand）は SIM.oneshots に控え、中身を Python で読んで確認の行を書く
SIM.psLines, SIM.oneshots, SIM.psStarts, SIM.psDelay, SIM.psDead = {}, {}, 0, 30, false
local function sim_append(path, text)
    local f = real_open(SIM_Path(path), "ab")
    if f then f:write(text) f:close() end
end
local function sim_ps_resident(cmd)
    SIM.psStarts = SIM.psStarts + 1
    local ack = nil
    local P = {}
    function P:write(s)
        if SIM.psDead then return nil, "Broken pipe" end
        SIM.psLines[#SIM.psLines + 1] = { ms = SIM.now, line = s }
        if SIM.psNoExec then return self end   -- 1 行ずつ実行されない PowerShell の模擬（何も書かない）
        local a = s:match("%$global:a='(.-)';")
        if a then
            ack = a
            local f = real_open(SIM_Path(a), "wb")
            if f then f:write("R "..(SIM.now + 800).."\r\n") f:close() end
        end
        local path, n = s:match("^P '(.-)' (%d+)")
        if path and ack then
            if SIM.psFail then
                sim_append(ack, "E "..n.." "..(SIM.now + SIM.psDelay).." file not found\r\n")
            else
                sim_append(ack, n.." "..(SIM.now + SIM.psDelay - 5).." "..(SIM.now + SIM.psDelay).."\r\n")
            end
            SIM.played = SIM.played or {}
            SIM.played[#SIM.played + 1] = { ms = SIM.now, path = path, n = tonumber(n) }
        end
        return self
    end
    function P:flush() return true end
    function P:close() SIM.psClosed = (SIM.psClosed or 0) + 1 return true end
    return P
end
io.popen = function(cmd, mode)
    SIM.popen = cmd
    if cmd:find("powershell", 1, true) and cmd:find("-Command -", 1, true) then
        return sim_ps_resident(cmd)
    end
    if cmd:find("-EncodedCommand", 1, true) then
        local b64 = cmd:match("-EncodedCommand (%S+)")
        local script = PY_B64U16DEC(b64)
        SIM.oneshots[#SIM.oneshots + 1] = { ms = SIM.now, cmd = cmd, script = script }
        local path = script:match("SoundPlayer '(.-)'")
        local ack, n = script:match("AppendAllText%('(.-)',\"(%d+) ")
        if ack and n then
            sim_append(ack, n.." "..(SIM.now + 400).." "..(SIM.now + 450).."\r\n")
            SIM.played = SIM.played or {}
            SIM.played[#SIM.played + 1] = { ms = SIM.now, path = path, n = tonumber(n), oneshot = true }
        end
        return { close = function() SIM.oneshotClosed = (SIM.oneshotClosed or 0) + 1 return true end,
                 lines = function() return function() return nil end end }
    end
    local dir, pat = cmd:match('dir /b /a%-d "(.-)\\([^\\"]*)"')
    local out = {}
    if dir then
        local prefix = pat:gsub("%*%.lua$", "")
        local list = PY_LISTDIR(SIM_Path(dir))
        for i = 1, #list do
            if list[i]:sub(1, #prefix) == prefix and list[i]:match("%.lua$") then out[#out + 1] = list[i].."\r" end
        end
    end
    local i = 0
    return { lines = function(self) return function() i = i + 1 return out[i] end end, close = function() end }
end

function RegisterEventHandler(ev, fn, name) SIM.handlers[ev] = SIM.handlers[ev] or {} SIM.handlers[ev][name] = fn end
function SIM_Fire(ev)
    if ev == "Gameloop.Update" then SIM_Process() end
    for name, fn in pairs(SIM.handlers[ev] or {}) do
        fn(ev, SIM.now)
        if ev == "Gameloop.Draw" and SIM_CheckUi then SIM_CheckUi(name) end
    end
end

-- 実行の模擬（v0.3.0）：Cast はキューに入り、アニメーションロック（0.6 秒）が明けたら使われる。
--   SIM.acr = true なら、ACR の代わりに 2.5 秒ごとに GCD（ファストブレード 9）を使う（ロック中なら遅れる）
function SIM_Use(id)
    SIM.lastUse[id] = SIM.now
    SIM.lockUntil = SIM.now + 600
    if SIM.argus.registerOnEntityCast then SIM.argus.registerOnEntityCast(Player.id, id, 0) end
end
function SIM_Process()
    local keep = {}
    for _, q in ipairs(SIM.queue) do
        if SIM.now >= q.at and SIM.now >= SIM.lockUntil then SIM_Use(q.id) else keep[#keep + 1] = q end
    end
    SIM.queue = keep
    if SIM.acr and Player.incombat and SIM.now >= SIM.acrNext and SIM.now >= SIM.lockUntil and #SIM.queue == 0 then
        SIM.acrUses[#SIM.acrUses + 1] = SIM.now
        SIM.acrNext = SIM.now + 2500
        SIM_Use(9)
    end
end

ml_gui = { ui_mgr = { AddComponent = function() end } }

-- GUI：何もしない。ボタンは SIM.clicks[ラベル] のときだけ true
--   v0.5.0：部品（RTL_UI_*）のために、位置・文字の大きさを数で返す。描いた文字をウィンドウごとに SIM.ui.texts に控える。
--           Push / Pop・Begin / End・BeginGroup / EndGroup・PushTextWrapPos / Pop が 1 フレームの中で釣り合っているかを数える
--           （釣り合わなければ SIM.ui.errors に書く）。定数（StyleVar_・Col_・WindowFlags_・ColorEditMode_）は数を返す
SIM.ui = { var = 0, col = 0, begin = 0, group = 0, wrap = 0, errors = {}, texts = {}, cur = "?", headers = false,
           calls = 0, consts = {}, pushes = 0 }
local function uitext(s)
    local t = SIM.ui.texts[SIM.ui.cur]
    if not t then t = {} SIM.ui.texts[SIM.ui.cur] = t end
    t[#t + 1] = tostring(s)
end
local function u8len(s) local _, n = tostring(s):gsub("[^\128-\191]", "") return n end
GUI = setmetatable({ SetCond_FirstUseEver = 4, SetCond_Always = 1, SetCond_Once = 2 }, { __index = function(t, k)
    if type(k) == "string" and (k:match("^StyleVar_") or k:match("^Col_") or k:match("^WindowFlags_") or k:match("^ColorEditMode_")) then
        local c = SIM.ui.consts
        if not c[k] then c.n = (c.n or 0) + 1 c[k] = 2 ^ (c.n % 30) end
        return c[k]
    end
    return function(self, ...) SIM.ui.calls = SIM.ui.calls + 1 return false end end })
function GUI:Begin(name, open) SIM.ui.begin = SIM.ui.begin + 1 SIM.ui.cur = name SIM.ui.texts[name] = {} SIM.ui.cx, SIM.ui.cy = 110, 120 return true, open end
function GUI:End() SIM.ui.begin = SIM.ui.begin - 1 end
function GUI:PushStyleVar(id, x, y) assert(type(id) == "number") SIM.ui.var = SIM.ui.var + 1 SIM.ui.pushes = SIM.ui.pushes + 1 end
function GUI:PopStyleVar(n) SIM.ui.var = SIM.ui.var - (n or 1) end
function GUI:PushStyleColor(id, r, g, b, a) assert(type(id) == "number" and type(a) == "number") SIM.ui.col = SIM.ui.col + 1 SIM.ui.pushes = SIM.ui.pushes + 1 end
function GUI:PopStyleColor(n) SIM.ui.col = SIM.ui.col - (n or 1) end
function GUI:BeginGroup() SIM.ui.group = SIM.ui.group + 1 end
function GUI:EndGroup() SIM.ui.group = SIM.ui.group - 1 end
function GUI:PushTextWrapPos(x) SIM.ui.wrap = SIM.ui.wrap + 1 end
function GUI:PopTextWrapPos() SIM.ui.wrap = SIM.ui.wrap - 1 end
function GUI:GetCursorScreenPos() return SIM.ui.cx or 110, SIM.ui.cy or 120 end
function GUI:SetCursorScreenPos(x, y) SIM.ui.cx, SIM.ui.cy = x, y end
function GUI:GetWindowPos() return SIM.ui.winX or 100, SIM.ui.winY or 100 end
function GUI:GetContentRegionAvailWidth() return 420 end
function GUI:GetItemRectMax() return 500, 180 end
function GUI:GetTextLineHeight() return 14 end
function GUI:CalcTextSize(s) return u8len(s) * 7, 14 end
function GUI:ColorConvertFloat4ToU32(r, g, b, a) assert(type(r) == "number" and type(a) == "number") return 0 end
function GUI:AddText(x, y, c, s) assert(type(x) == "number" and type(y) == "number" and type(s) == "string") uitext(s) end
function GUI:AddRectFilled(x1, y1, x2, y2, c, r) assert(type(x1) == "number" and type(y2) == "number") end
function GUI:AddRect(x1, y1, x2, y2, c, r) assert(type(x1) == "number" and type(y2) == "number") end
function GUI:Dummy(w, h) assert(type(w) == "number" and type(h) == "number") SIM.ui.cy = (SIM.ui.cy or 120) + h + 6 end   -- 次の行へ（ItemSpacing 6）
function GUI:IsMouseDown(b) return false end
function GUI:CollapsingHeader(label) return SIM.ui.headers == true end
function GUI:SliderInt(label, v, lo, hi) local c = SIM.clicks[label] if c ~= nil then SIM.clicks[label] = nil return c, true end return v, false end
function GUI:SliderFloat(label, v, lo, hi) local c = SIM.clicks[label] if c ~= nil then SIM.clicks[label] = nil return c, true end return v, false end
function GUI:InputFloat(label, v) local c = SIM.clicks[label] if c ~= nil then SIM.clicks[label] = nil return c, true end return v, false end   -- v0.6.2
function GUI:InputText(label, v) local c = SIM.clicks[label] if c ~= nil then SIM.clicks[label] = nil return c, true end return v, false end    -- v0.6.2
function GUI:ColorEdit3(label, r, g, b) local c = SIM.clicks[label] if c ~= nil then SIM.clicks[label] = nil return c[1], c[2], c[3], true end return r, g, b, false end
function GUI:Checkbox(label, v) if SIM.clicks[label] then SIM.clicks[label] = nil return not v, true end return v, false end
function GUI:SmallButton(label) if SIM.clicks[label] then SIM.clicks[label] = nil return true end return false end
function GUI:Button(label) return GUI.SmallButton(self, label) end
function GUI:Text(s) SIM.lastText = s uitext(s) end
function GUI:TextColored(r, g, b, a, s) assert(type(r) == "number") SIM.lastText = s uitext(s) end
function SIM_CheckUi(where)
    local u = SIM.ui
    if u.var ~= 0 or u.col ~= 0 or u.begin ~= 0 or u.group ~= 0 or u.wrap ~= 0 then
        u.errors[#u.errors + 1] = string.format("%s @%d var=%d col=%d begin=%d group=%d wrap=%d", where, SIM.now, u.var, u.col, u.begin, u.group, u.wrap)
        u.var, u.col, u.begin, u.group, u.wrap = 0, 0, 0, 0, 0
    end
end

-- Player
Player = { id = 268435457, localmapid = 0, job = 19, incombat = false, alive = true, buffs = {}, name = "me", level = 100,
           castinginfo = { channelingid = 0, castingid = 0, channeltargetid = 0, castingtargets = {} },
           hp = { current = 100000, max = 100000, percent = 100 }, chartype = 4, targetable = true }
function Player:GetTarget() return SIM.ents[SIM.targetId or -1] end

-- EntityList
EntityList = setmetatable({ myparty = {} }, { __call = function(self, filter)
    local out, n = {}, 0
    local cid = tonumber(filter:match("contentid=(%d+)") or "")
    local ty = tonumber(filter:match("type=(%d+)") or "")
    for id, e in pairs(SIM.ents) do
        if (not cid or e.contentid == cid) and (not ty or ty == 2) then out[id] = e n = n + 1 end
    end
    SIM.elCalls = (SIM.elCalls or 0) + 1
    if n == 0 then return nil end
    return out
end })
function EntityList:Get(id)
    if id == Player.id then return Player end
    return SIM.ents[id]
end

-- ActionList
ActionList = {}
-- v0.6.0：ActionList:Get(1)（ID なし）はアクションの一覧（SkillMgr.FillSkillBook と同じ取り方）。job・usable・level・recasttime
--   ナイト（19）と剣術士（1）のアクション、ロールアクション（job 0・usable）、ほかのジョブ（使えない）
SIM.actionBook = SIM.actionBook or {
    { 9, 1, 1, 2.5 }, { 15, 1, 4, 2.5 }, { 16, 1, 10, 2.5 }, { 24, 1, 15, 2.5 }, { 20, 1, 2, 60 }, { 30, 1, 50, 420 },
    { 3540, 19, 56, 90 }, { 25746, 19, 82, 5 }, { 36920, 19, 92, 120 }, { 16461, 19, 70, 10 }, { 7384, 19, 62, 2.5 },
    { 7531, 0, 8, 90, true }, { 7535, 0, 22, 60, true }, { 7548, 0, 32, 120, true }, { 7533, 0, 15, 30, true },
    { 7, 0, 1, 0, true }, { 1128, 0, 0, 0, true }, { 2238, 0, 0, 2.5, true },   -- オートアタック・敵のアクション（実機では usable が付いていた）
    { 7382, 21, 52, 25 }, { 7389, 21, 30, 2.5 },
    { 29067, 19, 0, 16 }, { 29058, 19, 0, 2.4 },   -- PvP のアクション（v0.6.5。実機では job がナイトで level 0）
}
function ActionList:Get(ty, id)   -- 実機と同じ（種類, ID）の順
    if ty == 1 and id == nil then
        SIM.bookCalls = (SIM.bookCalls or 0) + 1
        local out = {}
        for _, r in ipairs(SIM.actionBook) do
            out[r[1]] = { id = r[1], name = "Action"..r[1], job = r[2], level = r[3], recasttime = r[4],
                          usable = (r[5] == true) or r[2] == Player.job or r[2] == 1 }
        end
        return out
    end
    local last = SIM.lastUse[id]
    local rc = SIM.recast[id] or 0
    local el = last and (SIM.now - last) / 1000 or 1e9
    local oncd = el < rc
    if ty ~= 1 then return nil end
    return { id = id, name = "Action"..id, isoncd = oncd, cd = oncd and el or 0, cdmax = oncd and rc or 0, isready = not oncd,
             recasttime = rc, range = (id == 7535) and 0 or 3,
             IsReady = function(self, tid)
                 if id == 7535 and tid ~= Player.id then return false end   -- リプライザルは自分中心
                 return not oncd
             end,
             Cast = function(self, tid)
                 SIM.casts[#SIM.casts + 1] = { id = id, tid = tid, ms = SIM.now }
                 if oncd then return false end
                 if SIM.castMode == "ignore" then return true end
                 SIM.queue[#SIM.queue + 1] = { id = id, at = SIM.now + 60 }
                 return true
             end }
end
function ActionList:IsCasting() return false end

-- Argus
Argus = { getCurrentTethers = function() return {} end }
for _, f in ipairs({ "registerOnEntityChannel", "registerOnEntityCast", "registerOnMarkerAdd", "registerOnMapEffect", "registerOnTetherChange" }) do
    Argus[f] = function(fn) SIM.argus[f] = fn end
end

-- 状態を変える（Python から呼ぶ）
function SIM_Appear(id, cid, name, maxhp, tg)
    SIM.ents[id] = { id = id, contentid = cid, name = name, chartype = 0, targetable = tg, attackable = tg,
                     hp = { current = maxhp, max = maxhp, percent = 100 }, buffs = {}, alive = true }
end
function SIM_Remove(id) SIM.ents[id] = nil end
function SIM_Tg(id, tg) local e = SIM.ents[id] if e then e.targetable = tg if tg then e.attackable = true end end end
function SIM_Hp(id, cur, pct)
    local e = SIM.ents[id]
    if e then e.hp.current = cur e.hp.percent = pct end
end
function SIM_HpDrop(id) local e = SIM.ents[id] if e then e.hp.current = e.hp.current - 1 e.hp.percent = e.hp.current * 100 / e.hp.max end end
function SIM_Channel(id, a, tgt, cast) if SIM.argus.registerOnEntityChannel then SIM.argus.registerOnEntityChannel(id, a, tgt, cast) end end
function SIM_Cast(id, a, tid)
    if id == Player.id then SIM.lastUse[a] = SIM.now end
    -- v0.4.0：発動時の castinginfo（対象を渡されたら castingtargets に入れる。戦闘開始 first_hostile の確認用）
    local e = (id == Player.id) and Player or SIM.ents[id]
    if e then
        e.castinginfo = e.castinginfo or { channelingid = 0, castingid = 0, channeltargetid = 0, castingtargets = {} }
        e.castinginfo.castingid = a
        e.castinginfo.castingtargets = tid and { tid } or { (id == Player.id) and Player.id or id }
    end
    if SIM.argus.registerOnEntityCast then SIM.argus.registerOnEntityCast(id, a, 0) end
end
function SIM_Buff(id, bid, owner, dur, on)
    local e = (id == Player.id) and Player or SIM.ents[id]
    if not e then return end
    local key = bid..":"..owner
    if on then e.buffs[key] = { id = bid, ownerid = owner, duration = dur, name = "buff"..bid } else e.buffs[key] = nil end
end
function SIM_Party(mapid) EntityList.myparty = { { id = Player.id, mapid = mapid } } end

FFXIVMinionAction = { GetRepresentativeGCD = function(job) if job == 19 or job == 1 then return 9 end return nil end }
ml_input_mgr = { registerFunction = function(t) SIM.hotkey = t return true end }
