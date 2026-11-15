--[[
    Comet Hub · House Cloner (v3) — Adopt Me
    Target : Roblox — Adopt Me! (place 920587237)
    Runtime: client-side Luau through an executor, Rayfield UI (Comet theme).
             Optional extras switch themselves off when missing: file API
             (saves), HttpGet (pastebin import), an http request function
             (pastebin upload, webhook), getconnections (anti-AFK).
    Load   : loadstring(readfile("HouseCloner.lua"))()
    Tabs   : Paste · Clone · Auto · Scanner · Saved · Settings
    Author : Nyx for Larpbase

    ── WHAT v3 FIXES (read from Adopt Me's own client code, Sept 2026) ────────
    · Buying works. BuyFurnitures wants {kind, properties = {cframe, colors,
      scale}} per piece — the exact request the game's "Clone Selected" button
      builds (FurnitureSelectorApp:get_selection_as_buy_requests). One call buys
      AND places, and the server takes from your storage before charging Bucks.
      v2 sent bare FurnitureDB entries with no `properties`; all were refused.
    · Colours survive saving. HttpService:JSONEncode turns a Color3 into null,
      so every layout v2 wrote to disk had lost its colours. v3 writes [r,g,b].
    · Store vs sell. SellFurniture(true, uniques, mode) — the mode ("store" or
      "sell") is the THIRD argument; v2 sent 0 there. v3 only ever stores.
    · No Robux prompts. The game's own pre-buy helper (pre_buy_auto -> ShopM.buy)
      can open a "buy Bucks" Robux prompt when you're short. v3 never calls it:
      it prices the layout itself and calls the remote directly.

    ── HOW A PASTE WORKS ──────────────────────────────────────────────────────
    Read the house (SubscribeToHouse gate, then GetFurnitureWithinHouse), then
    match every layout piece against what's there: already at the right pose =
    keep, same piece elsewhere = move it (PushFurnitureChanges, by unique),
    otherwise buy it (storage first). Store whatever the layout doesn't use,
    set wall/floor textures, re-read, repair once. Matching is by pose, so
    running a paste twice only fixes what's wrong — that IS the Fix button.

    INSTANT: the moves, the clear-out and the textures go out as one call
    each, and the whole purchase as ONE BuyFurnitures call (400 per call on
    huge layouts). "Pasted in X s" pops the moment it lands; the per-piece
    check runs after.

    ── THE CAPABILITY TRAP ────────────────────────────────────────────────────
    Calling any Adopt Me module function (ClientData.get, InteriorsM,
    DownloadClient …) leaves that thread unable to write Instance properties —
    silently, under pcall. So nothing writes Instances (or Rayfield) outside
    the render queue: workers read game state into plain tables, and `ui(fn)`
    closures are drained on Heartbeat, a fresh thread every frame.

    Keys: K window · LeftCtrl+Shift+ P paste · F fix · C clone the house you're
          in · V preview · B paste box · Z undo · S stop
]]

-- Stage markers: executor warn() doesn't always reach the console, so a chunk
-- that dies mid-build is found by reading _G.HCV3.stage.
_G.HCV3 = { stage = "boot" }

--==============================================================================
-- SERVICES / ENV
--==============================================================================

local Players         = game:GetService("Players")
local RS              = game:GetService("ReplicatedStorage")
local UIS             = game:GetService("UserInputService")
local HttpService     = game:GetService("HttpService")
local TweenService    = game:GetService("TweenService")
local RunService      = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local LP = Players.LocalPlayer

local fs = {
    write = writefile, read = readfile, isfile = isfile, isdir = isfolder,
    mkdir = makefolder, del = delfile, list = listfiles,
}
local hasFS = (fs.write and fs.read and fs.isfile and fs.isdir and fs.mkdir) and true or false
fs.canList = hasFS and fs.list ~= nil      -- can it SEE house files, not just save them
local setclip = setclipboard or (syn and syn.write_clipboard) or function() end
local httpRequest = (syn and syn.request) or (http and http.request) or http_request or request
local getconns = getconnections
local gethuiFn = gethui

--==============================================================================
-- CONFIG  (the PERSIST keys survive reloads in HouseCloner/settings.json)
--==============================================================================

local CONFIG = {
    folder       = "HouseCloner",
    housesFolder = "HouseCloner/houses",
    settingsFile = "HouseCloner/settings.json",
    ledgerFile   = "HouseCloner/batch.json",
    codesFile    = "HouseCloner/codes.json",

    -- paste
    instant            = true,   -- big calls, no pauses
    instantChunk       = 1000,   -- pieces per BuyFurnitures call in INSTANT (he asked for 1k)
    buyChunk           = 40,     -- pieces per BuyFurnitures call (gentle mode)
    buyDelay           = 0.35,   -- seconds between buy calls (safe mode)
    pushChunk          = 60,     -- pieces per PushFurnitureChanges call (safe mode)
    clearLeftovers     = true,   -- store furniture the layout doesn't use
    reuseExisting      = true,   -- move pieces already in the house instead of buying
    applyTextures      = true,
    spendEventCurrency = false,  -- candy / gingerbread / skull pieces: storage only unless on
    keepBucks          = 0,      -- never spend below this
    trimToBudget       = false,  -- over budget: false = refuse, true = drop priciest pieces
    verifyAfterPaste   = true,
    saveClones         = true,   -- every clone is written out as a JSON file

    -- waits
    subscribeWait = 2.5,
    enterWait     = 25,
    switchWait    = 8,

    -- auto batch
    batchKind      = "micro_2023",
    batchCount     = 5,
    batchUseOwned  = false,
    batchSkipDone  = true,
    renameOn       = true,
    renameTemplate = "{layout} #{n}",
    renameGap      = 13,         -- the name filter throttles renames closer than ~12 s
    listLastHouse  = false,
    houseColor     = "Default",  -- paint for houses the batch buys or fills ("Default" = leave it)
    houseCap       = 4000,       -- pieces a house holds when it can't be read from inside

    -- scanner
    scanMinValue = 0,
    scanDelay    = 0.2,
    scanAutoSave = false,

    -- session
    accent     = "Cyan",
    antiAfk    = true,
    webhookOn  = false,
    webhookUrl = "",
    previewCap = 500,
    maxLog     = 400,
}

local PERSIST = {
    "instant", "instantChunk", "buyChunk", "buyDelay", "pushChunk", "clearLeftovers", "reuseExisting",
    "applyTextures", "spendEventCurrency", "keepBucks", "trimToBudget", "verifyAfterPaste",
    "saveClones", "subscribeWait", "enterWait", "batchKind", "batchCount",
    "batchUseOwned", "batchSkipDone", "renameOn", "renameTemplate", "renameGap",
    "listLastHouse", "houseColor", "scanMinValue", "scanDelay", "scanAutoSave", "accent", "antiAfk",
    "webhookOn", "webhookUrl", "previewCap",
}

-- Executor file API only, no game modules — safe on the construction thread.
local function loadSettings()
    if not hasFS then return false end
    local ok, t = pcall(function()
        if not fs.isfile(CONFIG.settingsFile) then return nil end
        return HttpService:JSONDecode(fs.read(CONFIG.settingsFile))
    end)
    if not ok or type(t) ~= "table" then return false end
    for _, k in ipairs(PERSIST) do
        if t[k] ~= nil and type(t[k]) == type(CONFIG[k]) then CONFIG[k] = t[k] end
    end
    return true
end

local saveQueued = false
local function saveSettings()
    if not hasFS or saveQueued then return end
    saveQueued = true
    task.delay(1, function()
        saveQueued = false
        local t = {}
        for _, k in ipairs(PERSIST) do t[k] = CONFIG[k] end
        pcall(function()
            if not fs.isdir(CONFIG.folder) then fs.mkdir(CONFIG.folder) end
            fs.write(CONFIG.settingsFile, HttpService:JSONEncode(t))
        end)
    end)
end

local function setCfg(k, v)
    CONFIG[k] = v
    saveSettings()
end

--==============================================================================
-- STATE  (plain Lua only)
--==============================================================================

local State = {
    layout      = nil,
    layoutName  = "(none)",
    running     = false,
    stopFlag    = false,
    busy        = nil,
    progress    = { done = 0, total = 0, phase = "idle" },
    scanned     = {},
    scanStatus  = "not scanned yet",
    pickedScan  = nil,
    currentSave = "None",
    lastBuy     = nil,
    lastPlan    = nil,
    lastFetch   = nil,
    houseStats  = nil,
    batchLines  = {},
    batchDirty  = true,
    boardRows   = {},
    boardDirty  = true,
}

--==============================================================================
-- UI QUEUE + LOG
--==============================================================================

-- uiQueue drains completely every frame; uiSlow drains a few per frame, for
-- heavy work like cloning hundreds of preview models.
local uiQueue, uiSlow = {}, {}
local function ui(fn) uiQueue[#uiQueue + 1] = fn end
local function uiLater(fn) uiSlow[#uiSlow + 1] = fn end

local function stamp()
    local ok, s = pcall(os.date, "%H:%M:%S")
    return ok and s or tostring(math.floor(os.clock()))
end

local Log, logDirty = {}, true
local function log(level, fmt, ...)
    local msg = tostring(fmt)
    if select("#", ...) > 0 then
        local ok, s = pcall(string.format, fmt, ...)
        msg = ok and s or (msg .. " (bad format)")
    end
    Log[#Log + 1] = ("%s %s %s"):format(stamp(), level, msg)
    if #Log > CONFIG.maxLog then table.remove(Log, 1) end
    logDirty = true
end
local function info(...) log("·", ...) end
local function okl(...)  log("+", ...) end
local function errl(...) log("!", ...) end

-- Batch progress lines: logged, and mirrored on the Auto page.
local function bline(fmt, ...)
    local s = tostring(fmt)
    if select("#", ...) > 0 then
        local ok, f = pcall(string.format, fmt, ...)
        s = ok and f or s
    end
    info("[batch] %s", s)
    table.insert(State.batchLines, stamp() .. "  " .. s)
    while #State.batchLines > 12 do table.remove(State.batchLines, 1) end
    State.batchDirty = true
end

local function commas(n)
    n = tonumber(n) or 0
    local s = tostring(math.floor(math.abs(n)))
    s = (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
    return (n < 0 and "-" or "") .. s
end

local function r4(x) return math.floor(x * 10000 + 0.5) / 10000 end

--==============================================================================
-- GAME LAYER
--==============================================================================

local Game = {}

local API = RS:WaitForChild("API", 10)
assert(API, "[HouseCloner] ReplicatedStorage.API missing — wrong game, or Adopt Me updated.")

local function rem(n)
    local r = API:FindFirstChild(n)
    if not r then warn("[HouseCloner] missing remote: " .. n) end
    return r
end

local REMOTES = {
    GetFurniture = "HousingAPI/GetFurnitureWithinHouse",
    Buy          = "HousingAPI/BuyFurnitures",
    Push         = "HousingAPI/PushFurnitureChanges",
    Remove       = "HousingAPI/SellFurniture",
    Subscribe    = "HousingAPI/SubscribeToHouse",
    Spawn        = "HousingAPI/SpawnHouse",
    BuyTexture   = "HousingAPI/BuyTexture",
    ListHouse    = "HousingAPI/ListHouse",
    UnlistHouse  = "HousingAPI/UnlistHouse",
    BuyHouse     = "HousingAPI/BuyHouseWithAddons",
    Rename       = "HousingAPI/RenameHouse",
    ColorHouse   = "HousingAPI/ColorHouse",
}
local R = {}
for key, name in pairs(REMOTES) do R[key] = rem(name) end

-- Already loaded by the game, so require() just hands back the cached table.
local ClientData  = require(RS.ClientModules.Core.ClientData)
local FurnitureDB = require(RS.ClientDB.Housing.FurnitureDB)
local HouseDB     = require(RS.ClientDB.Housing.HouseDB)

-- Everything else is required lazily from a worker: a FIRST require runs the
-- module body, which would poison the construction thread and kill the GUI.
local lazyMods = {}
local function lazy(key, path)
    local m = lazyMods[key]
    if m == nil then
        local ok, res = pcall(function() return require(path()) end)
        m = ok and res or false
        lazyMods[key] = m
    end
    return m or nil
end
local function TexturesDB()     return lazy("tex", function() return RS.ClientDB.Housing.TexturesDB end) end
local function InteriorsM()     return lazy("int", function() return RS.ClientModules.Core.InteriorsM.InteriorsM end) end
local function DownloadClient() return lazy("dl",  function() return RS.ClientModules.Core.DownloadClient end) end

-- InvokeServer never returns if the server drops the request (or you got
-- disconnected), so every invoke runs on its own thread under a deadline.
-- Third return value: true when it gave up waiting. The call may still finish
-- on the server after that, so each call keeps a record until it answers.
-- A call with no answer 5 minutes past its deadline is treated as lost.
Game.inflight = {}   -- remote -> { [token] = { t0, limit } }
local function invoke(remote, timeout, ...)
    if not remote then return false, "remote missing", false end
    local args = table.pack(...)
    local done, ok, res = false, false, nil
    local set = Game.inflight[remote] or {}
    Game.inflight[remote] = set
    local tok = {}
    set[tok] = { t0 = os.clock(), limit = (timeout or 20) + 300 }
    task.spawn(function()
        ok, res = pcall(function() return remote:InvokeServer(table.unpack(args, 1, args.n)) end)
        done = true
        set[tok] = nil
    end)
    local t0 = os.clock()
    while not done and os.clock() - t0 < (timeout or 20) do task.wait(0.05) end
    if not done then return false, "no reply after " .. tostring(timeout or 20) .. " s", true end
    return ok, res, false
end

-- Calls to this remote that may still be running on the server.
function Game.liveCalls(remote)
    local set, n, now = Game.inflight[remote], 0, os.clock()
    if not set then return 0 end
    for tok, rec in pairs(set) do
        if now - rec.t0 > rec.limit then
            set[tok] = nil
            errl("a purchase sent %d s ago never answered — treating it as lost", math.floor(now - rec.t0))
        else
            n = n + 1
        end
    end
    return n
end

-- Wait for them to finish. Stop ends the wait.
function Game.waitInflight(remote, maxSecs)
    local t0 = os.clock()
    while Game.liveCalls(remote) > 0 and not State.stopFlag and os.clock() - t0 < (maxSecs or 120) do task.wait(0.25) end
    return Game.liveCalls(remote) == 0
end

-- Every path that buys furniture (paste, fix, undo, Auto) passes this first:
-- buying while an earlier purchase may still be landing would buy twice.
function Game.buyGate()
    if Game.liveCalls(R.Buy) == 0 then return true end
    State.progress.phase = "waiting for the last purchase to land"
    if Game.waitInflight(R.Buy, 180) then return true end
    if State.stopFlag then return false, "stopped" end
    return false, "the last purchase is still landing on the server — wait a minute, then try again"
end

--------------------------------------------------------------------------------
-- FURNITURE RULES  (pure data)
--------------------------------------------------------------------------------

local Rules = {}

-- A few catalogue ids are variants whose buyable kind is `interactable_kind`
-- (pet_water_bowl_tutorial -> pet_water_bowl) — the same redirect the game does.
function Rules.buyKind(id)
    local db = FurnitureDB[id]
    if type(db) == "table" and db.interactable_kind and type(FurnitureDB[db.interactable_kind]) == "table" then
        return FurnitureDB[db.interactable_kind].kind or db.interactable_kind
    end
    return (type(db) == "table" and db.kind) or id
end

-- How one more of `id` can be had:
--   buy       on sale for Bucks (cost may be 0)
--   event     costs an event currency (candy, gingerbread, skulls …)
--   offsale   storage only           gamepass  storage only
--   unusable  can't go in a house     unknown   not in FurnitureDB
function Rules.classify(id)
    local db = FurnitureDB[Rules.buyKind(id)]
    if type(db) ~= "table" then return "unknown", 0 end
    if not db.can_use_in_house then return "unusable", 0 end
    if db.gamepass then return "gamepass", 0 end
    if db.off_sale or type(db.cost) ~= "number" then return "offsale", 0 end
    if db.currency_id and db.currency_id ~= "money" then return "event", db.cost end
    return "buy", db.cost
end

function Rules.name(id)
    local db = FurnitureDB[Rules.buyKind(id)]
    return (type(db) == "table" and db.name) or tostring(id)
end

--------------------------------------------------------------------------------
-- STATE READS  (module calls — workers only)
--------------------------------------------------------------------------------

local function cd(key)
    local ok, v = pcall(ClientData.get, key)
    if ok then return v end
end

function Game.houses()
    local hm, out = cd("house_manager"), {}
    if type(hm) == "table" then
        for _, h in pairs(hm) do
            if type(h) == "table" and h.house_id then out[#out + 1] = h end
        end
    end
    table.sort(out, function(a, b) return (a.house_id or 0) < (b.house_id or 0) end)
    return out
end

function Game.house(id)
    for _, h in ipairs(Game.houses()) do
        if h.house_id == id then return h end
    end
end

function Game.activeHouse()
    local hs = Game.houses()
    for _, h in ipairs(hs) do if h.active then return h end end
    return hs[1]
end

function Game.interior()
    local hi = cd("house_interior")
    return type(hi) == "table" and hi or nil
end

function Game.money()
    local v = cd("money")
    return type(v) == "number" and v or 0
end

-- storage_plus_temp[kind] = how many of that piece sit in your storage.
function Game.storage()
    local s, out = cd("furniture_storage_manager"), {}
    if type(s) == "table" and type(s.storage_plus_temp) == "table" then
        for kind, n in pairs(s.storage_plus_temp) do
            if type(n) == "number" and n > 0 then out[kind] = n end
        end
    end
    return out
end

-- Every house standing in this server: {house_id, player, player_name, building_type, …}
function Game.exteriors()
    local e, out = cd("house_exteriors"), {}
    if type(e) == "table" then
        for _, v in pairs(e) do
            if type(v) == "table" and v.house_id and v.player then out[#out + 1] = v end
        end
    end
    table.sort(out, function(a, b)
        return tostring(a.player_name):lower() < tostring(b.player_name):lower()
    end)
    return out
end

function Game.houseName(kind)
    local db = HouseDB[kind]
    return (type(db) == "table" and db.name) or tostring(kind)
end

-- Houses the shop sells for Bucks, cheapest first (Robux / gamepass houses excluded).
function Game.houseTypes()
    local out = {}
    for kind, db in pairs(HouseDB) do
        if type(db) == "table" and type(db.cost) == "number" and db.is_for_sale
            and not db.off_sale and not db.gamepass then
            out[#out + 1] = { kind = kind, name = db.name or kind, cost = db.cost }
        end
    end
    table.sort(out, function(a, b) return a.cost < b.cost end)
    return out
end

function Game.location()
    local IM = InteriorsM()
    if not IM then return nil end
    local ok, loc = pcall(IM.get_current_location)
    return (ok and type(loc) == "table") and loc or nil
end

-- Whose house you're physically standing in, when the location says so: walking
-- in passes {house_owner = owner}, so look for that key (a Player, a name or a
-- UserId). nil = can't tell; callers then fall back to the subscription.
function Game.physicalOwner()
    local loc = Game.location()
    if not (loc and loc.destination_id == "housing") then return nil end
    local function find(t, depth)
        for k, v in pairs(t) do
            if k == "house_owner" then
                if typeof(v) == "Instance" and v:IsA("Player") then return v end
                if type(v) == "string" then return Players:FindFirstChild(v) end
                if type(v) == "number" then return Players:GetPlayerByUserId(v) end
            elseif type(v) == "table" and depth < 2 then
                local p = find(v, depth + 1)
                if p then return p end
            end
        end
    end
    local ok, p = pcall(find, loc, 0)
    return ok and p or nil
end

-- house_interior follows whichever house you're SUBSCRIBED to, which isn't
-- always where you stand — so the interior location has to agree too.
function Game.insideHouseOf(owner, houseId)
    local hi = Game.interior()
    if not (hi and hi.house_id and hi.player == owner) then return false end
    if houseId and hi.house_id ~= houseId then return false end
    local loc = Game.location()
    if loc and loc.destination_id and loc.destination_id ~= "housing" then return false end
    local who = Game.physicalOwner()
    if who and who ~= owner then return false end
    return true
end

-- Whose house to point the subscription back at after reading someone else's.
function Game.homeOwner()
    local loc = Game.location()
    if not (loc and loc.destination_id == "housing") then return LP end
    local who = Game.physicalOwner()
    if who then return who end
    local hi = Game.interior()
    return (hi and hi.player) or LP
end

--------------------------------------------------------------------------------
-- READ
--------------------------------------------------------------------------------

-- SubscribeToHouse(owner) is the read gate: GetFurnitureWithinHouse answers nil
-- until you're subscribed. House ids are per owner (yours can be 1 while a
-- neighbour's is 48) and the subscription is how the server knows whose
-- "house 1" you mean — so always point it back at yourself afterwards.
--
-- Only fire it when the subscription actually has to move: every SubscribeToHouse
-- makes the server rebuild the subscription, and a read that lands mid-rebuild
-- fails server-side with "HousingAPI:1535: attempt to index nil with 'house_id'".
local lastSubscribed = nil   -- owner of the last SubscribeToHouse this script fired

function Game.subscribe(owner, houseId)
    owner = owner or LP
    if not R.Subscribe then return false end
    local function there()
        local hi = Game.interior()
        return hi and hi.player == owner and hi.house_id and (houseId == nil or hi.house_id == houseId)
    end
    if there() then
        lastSubscribed = owner
        return true
    end
    -- Standing outside every house (neighbourhood, main map) the interior never
    -- shows the subscription, so "there()" can't confirm it. If the last one we
    -- fired was already this owner, firing again would only rebuild it under a
    -- read that's about to land.
    local hi = Game.interior()
    if owner == LP and lastSubscribed == LP and houseId == nil and not (hi and hi.player) then return true end
    lastSubscribed = owner
    pcall(function() R.Subscribe:FireServer(owner) end)
    local t0 = os.clock()
    local limit = math.max(CONFIG.subscribeWait, owner == LP and 2.5 or 5)
    while os.clock() - t0 < limit do
        if there() then
            task.wait(0.25)   -- let the server finish switching before anything reads through it
            return true
        end
        task.wait(0.15)
    end
    return false
end

-- Someone else's house. GetFurnitureWithinHouse only ever looks through YOUR
-- houses — asked for a neighbour's "#1" it hands back your own house #1 (seen
-- live: a 25-piece neighbour came back as the caller's 937 pieces). What the
-- game itself uses is the interior it streams to subscribers:
-- house_interior.furniture, keyed by unique, with full data.
local function readSubscribed(owner, houseId)
    -- their loaded house is the active one; don't insist on the exterior's id
    if not Game.subscribe(owner) then
        return nil, "their house didn't load in 5 s — did they leave the server?"
    end
    -- furniture can arrive over a few frames: wait until the count settles
    local hi, last, stableSince, t0 = nil, -1, os.clock(), os.clock()
    while os.clock() - t0 < 8 do
        hi = Game.interior()
        if not (hi and hi.player == owner) then return nil, "the subscription moved away mid-read" end
        local n = 0
        for _ in pairs(hi.furniture or {}) do n = n + 1 end
        if n ~= last then last, stableSince = n, os.clock() end
        local want = tonumber(hi.furniture_quantity)
        if (want and want > 0 and n >= want) or os.clock() - stableSince > (n > 0 and 0.8 or 2) then break end
        task.wait(0.2)
    end
    local items = {}
    for unique, d in pairs(hi.furniture or {}) do
        if type(d) == "table" and d.id and typeof(d.cframe) == "CFrame" then
            items[#items + 1] = {
                id = d.id, unique = d.unique or unique, cframe = d.cframe,
                colors = d.colors, scale = tonumber(d.scale) or 1,
                wasDefault = d.was_default and true or false,
            }
        end
    end
    return items
end

-- Returns {id, unique, cframe, colors, scale, wasDefault} per piece. Your own
-- houses (any of them, active or not) go through the remote; anyone else's
-- through the streamed interior.
function Game.read(houseId, owner)
    owner = owner or LP
    if owner ~= LP then return readSubscribed(owner, houseId) end
    if not R.GetFurniture then return nil, "remote missing" end
    -- the remote resolves the id among your houses itself; the subscription only
    -- has to be on you (waiting for a non-active house to show up never ends)
    Game.subscribe(LP)
    local res, why
    for attempt = 1, 4 do
        local ok, r = invoke(R.GetFurniture, 15, houseId)
        if ok and type(r) == "table" then res = r break end
        why = ok and ("server sent " .. typeof(r)) or tostring(r)
        task.wait(0.4 * attempt)
        if attempt == 2 then
            -- the subscription may have been pulled elsewhere: put it back once
            pcall(function() R.Subscribe:FireServer(LP) end)
            task.wait(0.6)
        end
    end
    if not res then return nil, why or "no reply" end
    local items = {}
    for _, w in pairs(res) do
        local d = type(w) == "table" and (w.data or w) or nil
        if type(d) == "table" and d.id and typeof(d.cframe) == "CFrame" then
            items[#items + 1] = {
                id = d.id, unique = d.unique, cframe = d.cframe,
                colors = d.colors, scale = tonumber(d.scale) or 1,
                wasDefault = d.was_default and true or false,
                wasFree = (d.was_free or d.no_value) and true or false,
            }
        end
    end
    return items
end

--------------------------------------------------------------------------------
-- WRITE
--------------------------------------------------------------------------------

-- How a paste talks to the server, per mode:
--   instant  every step is ONE call carrying all of it: the house lands at once
--   small    small batches with pauses, for weak PCs or servers that refuse big calls
--   fix      tiny batches, used by the repair pass for the last few pieces
local PASTE_MODES = {
    instant = { buy = math.huge, buyDelay = 0,   push = math.huge, pushDelay = 0,    remove = math.huge, fast = true },
    small   = { buy = 50,        buyDelay = 0.3, push = 50,        pushDelay = 0.15, remove = 100,       fast = false },
    fix     = { buy = 8,         buyDelay = 0.4, push = 25,        pushDelay = 0.15, remove = 100,       fast = false },
}

-- Moves pieces you already have, addressed by unique. It can't create anything.
function Game.push(changes, mode)
    if not R.Push then return false, "remote missing" end
    local m = PASTE_MODES[mode] or PASTE_MODES.small
    local size = math.max(1, math.min(#changes, m.push))
    local i = 1
    while i <= #changes do
        if State.stopFlag then return false, "stopped" end
        local chunk = {}
        for j = i, math.min(i + size - 1, #changes) do chunk[#chunk + 1] = changes[j] end
        if not pcall(function() R.Push:FireServer(chunk) end) then return false, "push failed" end
        State.progress.done = State.progress.done + #chunk
        i = i + size
        if m.pushDelay > 0 and i <= #changes then task.wait(m.pushDelay) end
    end
    return true
end

-- One request per piece, exactly what "Clone Selected" sends. The server buys
-- and places together; results come back in request order as {unique, status}.
local function buyRequest(it)
    return {
        kind = Rules.buyKind(it.id),
        properties = {
            cframe = it.cframe,
            colors = type(it.colors) == "table" and table.clone(it.colors) or nil,
            scale  = it.scale or 1,
        },
    }
end

-- Statuses that mean "this piece will never fit", as opposed to a call that
-- simply didn't go through and is worth sending again in smaller pieces.
local FINAL_STATUS = {
    NO_SPACE = true, PER_FURNITURE_LIMIT_REACHED = true, PER_TAG_LIMIT_REACHED = true,
}

-- Returns the number placed and a list of {item, status} failures. chunk = how
-- many pieces ride in one call; delay = pause between calls (0 = back to back).
function Game.buy(items, chunk, delay)
    local placed, fails = 0, {}
    if not R.Buy then
        for _, it in ipairs(items) do fails[#fails + 1] = { item = it, status = "remote missing" } end
        return 0, fails
    end
    chunk = math.max(1, math.floor(chunk or 40))
    local blocked, full = {}, false     -- kind -> status once the server says "no more"
    local i = 1
    while i <= #items do
        if State.stopFlag then break end
        local batch, reqs = {}, {}
        for j = i, math.min(i + chunk - 1, #items) do
            local it = items[j]
            local kind = Rules.buyKind(it.id)
            if full then
                fails[#fails + 1] = { item = it, status = "NO_SPACE" }
            elseif blocked[kind] then
                fails[#fails + 1] = { item = it, status = blocked[kind] }
            else
                batch[#batch + 1] = it
                reqs[#reqs + 1] = buyRequest(it)
            end
        end
        i = i + chunk
        if #reqs > 0 then
            -- the deadline grows with the call: a 4000-piece call gets ~145 s
            local ok, res, timedOut = invoke(R.Buy, 45 + math.floor(#reqs / 40), reqs)
            State.lastBuy = res
            if timedOut then
                errl("BuyFurnitures: no answer in time for %d piece(s) — not resending them, the server may still be placing them", #batch)
                for _, it in ipairs(batch) do fails[#fails + 1] = { item = it, status = "TIMEOUT" } end
            elseif not ok then
                errl("BuyFurnitures error: %s", tostring(res))
                for _, it in ipairs(batch) do fails[#fails + 1] = { item = it, status = "ERROR" } end
            elseif type(res) ~= "table" then
                errl("BuyFurnitures: reply was %s", typeof(res))
                for _, it in ipairs(batch) do fails[#fails + 1] = { item = it, status = "NO_REPLY" } end
            else
                local results = type(res.results) == "table" and res.results or {}
                for k, it in ipairs(batch) do
                    local r = results[k]
                    local status = type(r) == "table" and r.status or nil
                    if type(r) == "table" and r.unique and (status == nil or status == "SUCCESS") then
                        placed = placed + 1
                    else
                        status = tostring(status or (res.success and "UNKNOWN" or "REFUSED"))
                        fails[#fails + 1] = { item = it, status = status }
                        if status == "NO_SPACE" then
                            full = true
                        elseif FINAL_STATUS[status] then
                            blocked[Rules.buyKind(it.id)] = status
                        end
                    end
                end
            end
            State.progress.done = State.progress.done + #batch
            if delay and delay > 0 then task.wait(delay) end
        end
    end
    return placed, fails
end

-- INSTANT: the whole layout in ONE call — what the game's own "Clone Selected"
-- does with a selection — so the house lands at once. Anything refused for a
-- reason other than a hard limit is sent again 100 at a time, in case the
-- server capped the size of the big call.
function Game.buyInstant(items)
    local placed, fails = Game.buy(items, math.max(1, #items), 0)
    -- A call we never heard back from (or heard back without a result row) may
    -- still have bought the piece, so those are never resent here: the verify
    -- pass re-reads the house once those calls have finished.
    local uncertain = { TIMEOUT = true, NO_REPLY = true, UNKNOWN = true }
    local retry, final = {}, {}
    for _, f in ipairs(fails) do
        if FINAL_STATUS[f.status] or uncertain[f.status] then final[#final + 1] = f else retry[#retry + 1] = f.item end
    end
    if #retry > 0 and not State.stopFlag then
        info("%d piece(s) didn't take in the big call — retrying 100 at a time", #retry)
        local more, fails2 = Game.buy(retry, 100, 0.1)
        placed = placed + more
        for _, f in ipairs(fails2) do final[#final + 1] = f end
    end
    return placed, final
end

-- SellFurniture(true, uniques, mode) — the mode is the THIRD argument. "store"
-- keeps the piece in your storage. Default pieces (what a new house comes with)
-- can't be stored, so the game deletes those in either mode.
function Game.remove(uniques, mode, fast)
    if not R.Remove or #uniques == 0 then return 0 end
    mode = (mode == "sell") and "sell" or "store"
    local size = fast and math.max(1, #uniques) or 100
    local n = 0
    for i = 1, #uniques, size do
        local chunk = {}
        for j = i, math.min(i + size - 1, #uniques) do chunk[#chunk + 1] = uniques[j] end
        if pcall(function() R.Remove:FireServer(true, chunk, mode) end) then n = n + #chunk end
        State.progress.done = State.progress.done + #chunk
        if not fast then task.wait(0.25) end
    end
    return n
end

-- changes: {room, ttype = "floors" | "walls", id} — the texture picker's own call.
function Game.applyTextures(changes, fast)
    if not R.BuyTexture then return 0 end
    local n = 0
    for _, c in ipairs(changes) do
        if State.stopFlag then break end
        if pcall(function() R.BuyTexture:FireServer(c.room, c.ttype, c.id) end) then n = n + 1 end
        State.progress.done = State.progress.done + 1
        if not fast then task.wait(0.15) end
    end
    return n
end

--------------------------------------------------------------------------------
-- HOUSES
--------------------------------------------------------------------------------

-- Exterior paint for houses the batch buys or fills. "Default" = leave the
-- house type's own colour alone.
local HOUSE_COLOR_ORDER = {
    "Default", "White", "Cream", "Pastel Pink", "Hot Pink", "Lavender", "Purple", "Sky Blue",
    "Ocean Blue", "Mint", "Forest Green", "Sunshine", "Gold", "Orange", "Coral Red", "Chocolate",
    "Charcoal", "Black",
}
local HOUSE_COLORS = {
    ["White"] = Color3.fromRGB(245, 245, 245), ["Cream"] = Color3.fromRGB(250, 236, 205),
    ["Pastel Pink"] = Color3.fromRGB(255, 196, 214), ["Hot Pink"] = Color3.fromRGB(255, 80, 160),
    ["Lavender"] = Color3.fromRGB(200, 180, 255), ["Purple"] = Color3.fromRGB(140, 90, 220),
    ["Sky Blue"] = Color3.fromRGB(140, 210, 255), ["Ocean Blue"] = Color3.fromRGB(40, 110, 200),
    ["Mint"] = Color3.fromRGB(160, 235, 200), ["Forest Green"] = Color3.fromRGB(50, 130, 70),
    ["Sunshine"] = Color3.fromRGB(255, 225, 90), ["Gold"] = Color3.fromRGB(230, 180, 50),
    ["Orange"] = Color3.fromRGB(255, 150, 60), ["Coral Red"] = Color3.fromRGB(240, 90, 80),
    ["Chocolate"] = Color3.fromRGB(110, 70, 45), ["Charcoal"] = Color3.fromRGB(60, 62, 70),
    ["Black"] = Color3.fromRGB(20, 20, 24),
}

-- How many pieces a house holds: the game's HouseBuildLimit.get_limit —
-- 4000, plus 500 per Star Rewards build-limit purchase (at most 8), per house.
function Game.houseCap(houseId)
    local h = Game.house(houseId)
    local n = math.clamp(math.floor(tonumber(h and h.build_limit_purchases) or 0), 0, 8)
    return (tonumber(CONFIG.houseCap) or 4000) + n * 500
end

-- ColorHouse(house_id, colour) — the paint picker in the game's house menu.
function Game.colorHouse(houseId, color)
    if not R.ColorHouse then return false, "ColorHouse remote missing" end
    if typeof(color) ~= "Color3" then return false, "no colour" end
    return pcall(function() R.ColorHouse:FireServer(houseId, color) end)
end

-- BuyHouseWithAddons(kind, addons, colour) — the shop's own call. The new house
-- turns active by itself. Returns the new house_id.
function Game.buyHouse(kind, color)
    local db = HouseDB[kind]
    if type(db) ~= "table" then return nil, "unknown house type " .. tostring(kind) end
    local before = {}
    for _, h in ipairs(Game.houses()) do before[h.house_id] = true end
    local paintWith = (typeof(color) == "Color3" and color) or db.default_color or Color3.new(1, 1, 1)
    local ok, res = invoke(R.BuyHouse, 20, kind, {}, paintWith)
    if not ok then return nil, tostring(res) end
    local t0 = os.clock()
    while os.clock() - t0 < 8 do
        for _, h in ipairs(Game.houses()) do
            if not before[h.house_id] then return h.house_id end
        end
        task.wait(0.25)
    end
    return nil, "no new house showed up (server said " .. tostring(res) .. ")"
end

-- SpawnHouse(house_id) is what the in-game "Set Active" button fires.
function Game.setActive(houseId)
    local h = Game.house(houseId)
    if not h then return false, "you don't own house #" .. tostring(houseId) end
    if h.active then return true end
    pcall(function() R.Spawn:FireServer(houseId) end)
    local t0 = os.clock()
    while os.clock() - t0 < CONFIG.switchWait do
        local hh = Game.house(houseId)
        if hh and hh.active then return true end
        task.wait(0.2)
    end
    return false, "house #" .. tostring(houseId) .. " never became active"
end

-- The game's own door travel (InteriorsM), with the game's own rule: a locked
-- door keeps you out unless you're friends. Standing in another house of the
-- same owner can make the trip a no-op, so a second attempt steps out to the
-- neighbourhood first. Third return value: whether travel was actually fired
-- (so a caller knows you may have left where you were, even on failure).
function Game.doorLocked(owner)
    if owner == LP then return false end
    local ok, locked = pcall(ClientData.get_server, owner, "door_locked")
    if not (ok and locked == true) then return false end
    local okF, friends = pcall(function() return LP:IsFriendsWith(owner.UserId) end)
    return not (okF and friends)
end

function Game.enterHouse(owner, houseId)
    owner = owner or LP
    if Game.doorLocked(owner) then
        return false, "their door is locked — clone it from the Clone tab instead, no need to go in", false
    end
    local IM = InteriorsM()
    if not IM then return false, "InteriorsM unavailable", false end
    for attempt = 1, 2 do
        local ok = pcall(IM.enter_smooth, "housing", "MainDoor", { house_owner = owner })
        if not ok then pcall(IM.enter, "housing", "MainDoor", { house_owner = owner }) end
        local t0 = os.clock()
        while os.clock() - t0 < CONFIG.enterWait / 2 do
            if Game.insideHouseOf(owner, houseId) then
                task.wait(1)   -- let the furniture finish streaming in
                return true, nil, true
            end
            task.wait(0.25)
        end
        if attempt == 1 then
            pcall(IM.enter_smooth, "Neighborhood", "MainDoor", {})
            task.wait(3)
        end
    end
    return false, "timed out walking in", true
end

function Game.enterOwnHouse(houseId)
    if houseId then
        local ok, e = Game.setActive(houseId)
        if not ok then return false, e, false end
    end
    if Game.insideHouseOf(LP, houseId) then return true, nil, true end
    return Game.enterHouse(LP, houseId)
end

function Game.rename(houseId, name)
    return pcall(function() R.Rename:FireServer(houseId, name) end)
end

-- ListHouse lists the ACTIVE house and takes no arguments.
function Game.listForTrade(on)
    local ok, res = invoke(on and R.ListHouse or R.UnlistHouse, 15)
    return ok, ok and (on and "listed for trade" or "unlisted") or tostring(res)
end

function Game.hop()
    local ok, e = pcall(function() TeleportService:Teleport(game.PlaceId, LP) end)
    return ok, ok and "teleporting…" or tostring(e)
end

--==============================================================================
-- PLAN  (pure: decides what a paste will do and what it costs)
--==============================================================================

local Plan = {}

local function near(a, b, tol) return math.abs((a or 1) - (b or 1)) <= (tol or 0.001) end

local function samePose(a, b)
    if typeof(a) ~= "CFrame" or typeof(b) ~= "CFrame" then return false end
    if (a.Position - b.Position).Magnitude > 0.05 then return false end
    return a.LookVector:Dot(b.LookVector) > 0.9995 and a.UpVector:Dot(b.UpVector) > 0.9995
end

-- nil on the layout side means "no opinion" (v2 files lost their colours).
local function colorsMatch(want, have)
    if type(want) ~= "table" then return true end
    if type(have) ~= "table" then return false end
    for k, c in pairs(want) do
        if typeof(c) == "Color3" then
            local h = have[k]
            if typeof(h) ~= "Color3" then return false end
            if math.abs(c.R - h.R) > 0.004 or math.abs(c.G - h.G) > 0.004 or math.abs(c.B - h.B) > 0.004 then
                return false
            end
        end
    end
    return true
end

-- layout: {items, textures}; existing: pieces read from the house (nil = empty);
-- storage: kind -> count; curTex: the house's current textures.
function Plan.build(layout, existing, storage, money, curTex)
    local p = {
        total = #layout.items, keep = 0, move = 0, fromStorage = 0, buy = 0, cost = 0,
        event = 0, moves = {}, buys = {}, skipped = {}, leftovers = {},
        texChanges = {}, texCost = 0, money = money or 0,
    }

    -- what's in the house, by buyable kind
    local byKind = {}
    for _, it in ipairs(existing or {}) do
        if it.unique then
            local k = Rules.buyKind(it.id)
            byKind[k] = byKind[k] or {}
            table.insert(byKind[k], it)
        end
    end
    local used = {}

    -- 1) a piece already at the wanted pose stays; colours/scale get fixed in place
    local pending = {}
    for _, want in ipairs(layout.items) do
        local hit
        for _, have in ipairs(byKind[Rules.buyKind(want.id)] or {}) do
            if not used[have.unique] and near(want.scale, have.scale) and samePose(want.cframe, have.cframe) then
                hit = have
                break
            end
        end
        if hit then
            used[hit.unique] = true
            if colorsMatch(want.colors, hit.colors) then
                p.keep = p.keep + 1
            else
                p.move = p.move + 1
                p.moves[#p.moves + 1] = { unique = hit.unique, cframe = want.cframe, colors = want.colors, scale = want.scale or 1 }
            end
        else
            pending[#pending + 1] = want
        end
    end

    -- 2) the same piece somewhere else in the house gets moved (free)
    local need = {}
    for _, want in ipairs(pending) do
        local spare
        if CONFIG.reuseExisting then
            for _, have in ipairs(byKind[Rules.buyKind(want.id)] or {}) do
                if not used[have.unique] then spare = have break end
            end
        end
        if spare then
            used[spare.unique] = true
            p.move = p.move + 1
            p.moves[#p.moves + 1] = {
                unique = spare.unique, cframe = want.cframe,
                colors = want.colors or spare.colors, scale = want.scale or 1,
            }
        else
            need[#need + 1] = want
        end
    end

    -- 3) the rest comes out of storage, costs Bucks, or can't be had
    local store = {}
    for k, n in pairs(storage or {}) do store[k] = n end
    for _, want in ipairs(need) do
        local class, cost = Rules.classify(want.id)
        local kind = Rules.buyKind(want.id)
        if class == "unknown" or class == "unusable" then
            p.skipped[#p.skipped + 1] = { item = want, why = class }
        elseif (store[kind] or 0) > 0 then
            store[kind] = store[kind] - 1
            p.fromStorage = p.fromStorage + 1
            p.buys[#p.buys + 1] = { item = want, via = "storage", cost = 0 }
        elseif class == "buy" then
            p.buy = p.buy + 1
            p.cost = p.cost + (cost or 0)
            p.buys[#p.buys + 1] = { item = want, via = "bucks", cost = cost or 0 }
        elseif class == "event" and CONFIG.spendEventCurrency then
            p.event = p.event + 1
            p.buys[#p.buys + 1] = { item = want, via = "event", cost = 0 }
        else
            p.skipped[#p.skipped + 1] = { item = want, why = (class == "event") and "event currency" or class }
        end
    end

    -- 4) whatever the layout didn't claim
    for _, list in pairs(byKind) do
        for _, have in ipairs(list) do
            if not used[have.unique] then p.leftovers[#p.leftovers + 1] = have end
        end
    end

    -- 5) wall / floor textures that differ from what's there now
    if CONFIG.applyTextures and type(layout.textures) == "table" then
        local TDB = TexturesDB()
        for room, t in pairs(layout.textures) do
            if type(t) == "table" then
                -- inside a house without that room, the texture can never apply
                local missingRoom = type(curTex) == "table" and curTex[room] == nil
                local cur = (type(curTex) == "table" and type(curTex[room]) == "table") and curTex[room] or {}
                for _, ttype in ipairs({ "floors", "walls" }) do
                    local id = t[ttype]
                    if not missingRoom and type(id) == "string" and id ~= cur[ttype] then
                        local e = TDB and TDB[ttype] and TDB[ttype][id]
                        p.texChanges[#p.texChanges + 1] = { room = room, ttype = ttype, id = id }
                        p.texCost = p.texCost + ((type(e) == "table" and tonumber(e.cost)) or 0)
                    end
                end
            end
        end
    end

    Plan.settle(p)
    return p
end

function Plan.settle(p)
    p.spend = p.cost + p.texCost
    p.after = p.money - p.spend
    p.affordable = p.spend <= 0 or p.after >= (tonumber(CONFIG.keepBucks) or 0)
    p.work = #p.moves + #p.buys + (CONFIG.clearLeftovers and #p.leftovers or 0) + #p.texChanges
end

-- Over budget with "trim" on: drop the priciest Bucks purchases until it fits.
function Plan.trim(p)
    local budget = p.money - (tonumber(CONFIG.keepBucks) or 0) - p.texCost
    local order = {}
    for i, b in ipairs(p.buys) do if b.via == "bucks" then order[#order + 1] = i end end
    table.sort(order, function(a, b) return p.buys[a].cost > p.buys[b].cost end)
    local drop, dropped = {}, 0
    for _, i in ipairs(order) do
        if p.cost <= budget then break end
        drop[i] = true
        p.cost = p.cost - p.buys[i].cost
        p.buy = p.buy - 1
        dropped = dropped + 1
    end
    local kept = {}
    for i, b in ipairs(p.buys) do
        if drop[i] then p.skipped[#p.skipped + 1] = { item = b.item, why = "budget" }
        else kept[#kept + 1] = b end
    end
    p.buys = kept
    Plan.settle(p)
    return dropped
end

-- A house holds house_interior.max_furniture pieces (4000 on a Tiny Home) and
-- the server answers NO_SPACE past that. Cut the purchases that can't fit up
-- front — layout order, so the tail goes — instead of sending doomed calls.
function Plan.fit(p, cap)
    cap = tonumber(cap)
    if not cap or cap <= 0 then return 0 end
    local staying = p.keep + #p.moves + (CONFIG.clearLeftovers and 0 or #p.leftovers)
    local room = math.max(0, cap - staying)
    if #p.buys <= room then return 0 end
    local kept, cut = {}, 0
    for i, b in ipairs(p.buys) do
        if i <= room then
            kept[#kept + 1] = b
        else
            cut = cut + 1
            if b.via == "bucks" then p.cost = p.cost - b.cost ; p.buy = p.buy - 1
            elseif b.via == "storage" then p.fromStorage = p.fromStorage - 1
            else p.event = p.event - 1 end
            p.skipped[#p.skipped + 1] = { item = b.item, why = "house full (" .. cap .. " max)" }
        end
    end
    p.buys = kept
    Plan.settle(p)
    return cut
end

function Plan.describe(p)
    local t = {}
    if p.keep > 0 then t[#t + 1] = p.keep .. " already right" end
    if p.move > 0 then t[#t + 1] = p.move .. " to move" end
    if p.fromStorage > 0 then t[#t + 1] = p.fromStorage .. " from storage" end
    if p.buy > 0 then t[#t + 1] = ("%d to buy ($%s)"):format(p.buy, commas(p.cost)) end
    if p.event > 0 then t[#t + 1] = p.event .. " on event currency" end
    if #p.skipped > 0 then t[#t + 1] = #p.skipped .. " unobtainable" end
    if #p.leftovers > 0 then
        t[#t + 1] = #p.leftovers .. (CONFIG.clearLeftovers and " to store" or " extra (kept)")
    end
    if #p.texChanges > 0 then t[#t + 1] = ("%d texture(s) $%s"):format(#p.texChanges, commas(p.texCost)) end
    if #t == 0 then return "nothing to do — the house already matches" end
    return table.concat(t, " · ")
end

-- "3 off-sale · 2 unknown id" — why pieces were skipped.
function Plan.skipReasons(p)
    local by, order = {}, {}
    for _, s in ipairs(p.skipped) do
        if not by[s.why] then by[s.why] = 0 ; order[#order + 1] = s.why end
        by[s.why] = by[s.why] + 1
    end
    local t = {}
    for _, why in ipairs(order) do t[#t + 1] = by[why] .. " " .. why end
    return table.concat(t, " · ")
end

local function itemsOf(buys)
    local t = {}
    for _, b in ipairs(buys) do t[#t + 1] = b.item end
    return t
end

local function uniquesOf(list)
    local t = {}
    for _, it in ipairs(list) do if it.unique then t[#t + 1] = it.unique end end
    return t
end

--==============================================================================
-- UNDO  (snapshot of every piece's pose before a paste)
--==============================================================================

local Txn = { state = "IDLE", houseId = nil, snapshot = nil, takenAt = nil }

function Txn.armFrom(houseId, items)
    local snap = {}
    for _, it in ipairs(items) do
        if it.unique then
            snap[#snap + 1] = { unique = it.unique, id = it.id, cframe = it.cframe, colors = it.colors, scale = it.scale or 1 }
        end
    end
    Txn.state, Txn.houseId, Txn.snapshot, Txn.takenAt = "ARMED", houseId, snap, os.time()
    return #snap
end

function Txn.commit()
    if Txn.state == "ARMED" then Txn.state = "COMMITTED" end
end

-- Puts every snapshotted piece back where it was. Pieces the paste stored come
-- back from storage (free); ones that were deleted defaults are re-bought only
-- if that's affordable. `hard` also stores everything the paste added.
function Txn.revert(hard)
    if type(Txn.snapshot) ~= "table" or #Txn.snapshot == 0 then return false, "nothing to undo" end
    local okG, whyG = Game.buyGate()
    if not okG then return false, whyG end
    if not Game.insideHouseOf(LP, Txn.houseId) then
        local ok, e = Game.enterOwnHouse(Txn.houseId)
        if not ok then return false, "can't get back into house #" .. tostring(Txn.houseId) .. ": " .. tostring(e) end
    end
    local now = Game.read(Txn.houseId, LP)
    if not now then return false, "couldn't read the house" end

    local known, present, strays = {}, {}, {}
    for _, s in ipairs(Txn.snapshot) do known[s.unique] = true end
    for _, it in ipairs(now) do
        present[it.unique] = true
        if it.unique and not known[it.unique] then strays[#strays + 1] = it.unique end
    end

    local changes, gone = {}, {}
    for _, s in ipairs(Txn.snapshot) do
        if present[s.unique] then
            changes[#changes + 1] = { unique = s.unique, cframe = s.cframe, colors = s.colors, scale = s.scale }
        else
            gone[#gone + 1] = { id = s.id, cframe = s.cframe, colors = s.colors, scale = s.scale }
        end
    end

    State.progress = { done = 0, total = #changes + #gone + (hard and #strays or 0), phase = "undoing" }
    Game.push(changes, "small")

    local back = 0
    if #gone > 0 then
        local p = Plan.build({ items = gone }, nil, Game.storage(), Game.money(), nil)
        if p.affordable then
            back = Game.buy(itemsOf(p.buys), 10, 0.3)
        else
            errl("undo: bringing back %d removed piece(s) would cost $%s — skipped", #gone, commas(p.spend))
        end
    end
    local stored = hard and Game.remove(strays, "store") or 0
    Txn.state = "REVERTED"

    local msg = ("moved %d back"):format(#changes)
    if #gone > 0 then msg = msg .. (" · restored %d/%d removed"):format(back, #gone) end
    if hard then msg = msg .. (" · stored %d the paste added"):format(stored) end
    return true, msg
end

--==============================================================================
-- PASTE
--==============================================================================


local Paste = {}

-- Apply a plan. mode = "instant" (default), "small" or "fix" — see PASTE_MODES.
-- Instant fires the moves, the clear-out and the textures as one call each
-- (no replies to wait for), then the whole purchase as one call, the only step
-- that waits on the server.
function Paste.apply(plan, mode)
    -- no mode given (Auto batch): follow the Auto tab's INSTANT switch
    mode = PASTE_MODES[mode] and mode or (CONFIG.instant == false and "small" or "instant")
    local m = PASTE_MODES[mode]
    local res = { moved = 0, placed = 0, fails = {}, stored = 0, textures = 0 }
    State.progress.total = plan.work
    State.progress.done = 0

    if #plan.moves > 0 and not State.stopFlag then
        State.progress.phase = "moving pieces you own"
        if Game.push(plan.moves, mode) then res.moved = #plan.moves end
    end
    if CONFIG.clearLeftovers and #plan.leftovers > 0 and not State.stopFlag then
        State.progress.phase = "storing leftovers"
        res.stored = Game.remove(uniquesOf(plan.leftovers), "store", m.fast)
    end
    if #plan.texChanges > 0 and not State.stopFlag then
        State.progress.phase = "textures"
        res.textures = Game.applyTextures(plan.texChanges, m.fast)
    end
    if #plan.buys > 0 and not State.stopFlag then
        State.progress.phase = "buying + placing"
        local items = itemsOf(plan.buys)
        if mode == "instant" then
            res.placed, res.fails = Game.buyInstant(items)
        else
            res.placed, res.fails = Game.buy(items, m.buy, m.buyDelay)
        end
        if #res.fails > 0 then
            local by = {}
            for _, f in ipairs(res.fails) do by[f.status] = (by[f.status] or 0) + 1 end
            for status, n in pairs(by) do errl("%d piece(s) refused: %s", n, status) end
        end
    end
    return res
end

-- Re-read the house and fix whatever didn't land, once. Returns the final plan.
-- Waits for any buy call that timed out to really finish first, or pieces it
-- is still placing would look missing and get bought twice.
function Paste.verify(layout, houseId)
    if State.stopFlag then return nil, "stopped" end
    if not Game.waitInflight(R.Buy, 180) then
        if State.stopFlag then return nil, "stopped" end
        errl("a purchase is still landing on the server — skipped the repair pass so nothing is bought twice")
        return nil, "pending"
    end
    local now = Game.read(houseId, LP)
    if not now then return nil, "unread" end
    local hi = Game.interior() or {}
    local final = Plan.build(layout, now, Game.storage(), Game.money(), hi.textures)
    Plan.fit(final, hi.max_furniture)
    if #final.moves + #final.buys > 0 and not State.stopFlag then
        info("repair pass: %s", Plan.describe(final))
        if final.affordable then Paste.apply(final, "fix") end
        task.wait(1.5)
        local again = Game.read(houseId, LP)
        if again then
            local hi2 = Game.interior() or {}
            final = Plan.build(layout, again, Game.storage(), Game.money(), hi2.textures)
            Plan.fit(final, hi2.max_furniture)
        end
    end
    return final
end

-- Paste `layout` into one of your houses (default: the one you're in, else the
-- active one). mode = "instant" (default), "small" or "fix". onPasted(msg)
-- fires the moment the house has landed, before the verify pass.
-- Returns ok, message, final plan, untouched.
function Paste.run(layout, houseId, mode, onPasted)
    if not layout or #layout.items == 0 then return false, "no layout loaded" end
    State.progress = { done = 0, total = 0, phase = "getting inside" }
    -- before reading or snapshotting the house, so late pieces are counted
    local okG, whyG = Game.buyGate()
    if not okG then return false, whyG, nil, false, "inflight" end

    if not Game.insideHouseOf(LP, houseId) then
        local target = houseId or (Game.activeHouse() or {}).house_id
        local ok, e = Game.enterOwnHouse(target)
        if not ok then return false, "couldn't get into your house: " .. tostring(e) end
    end
    local hi = Game.interior()
    houseId = hi and hi.house_id
    if not houseId then return false, "no house loaded" end

    State.progress.phase = "reading the house"
    local existing, e = Game.read(houseId, LP)
    if not existing then return false, "read failed: " .. tostring(e) end
    Txn.armFrom(houseId, existing)

    local plan = Plan.build(layout, existing, Game.storage(), Game.money(), hi.textures)
    State.lastPlan = plan
    local cut = Plan.fit(plan, hi.max_furniture)
    if cut > 0 then
        info("this house holds %s pieces — the last %d of the layout won't fit and are skipped",
            tostring(hi.max_furniture), cut)
    end
    if not plan.affordable and CONFIG.trimToBudget then
        info("over budget — dropped the %d priciest piece(s)", Plan.trim(plan))
    end
    if not plan.affordable then
        return false, ("needs $%s, you have $%s (keeping $%s)"):format(
            commas(plan.spend), commas(plan.money), commas(tonumber(CONFIG.keepBucks) or 0)), plan
    end

    local layoutType = layout.buildingType and Game.houseName(layout.buildingType)
    local houseType = Game.houseName(hi.building_type)
    if layoutType and layoutType ~= houseType then
        info("layout is from a %s, this is a %s — pieces outside this shell may be refused", layoutType, houseType)
    end

    info("house #%s: %s", tostring(houseId), Plan.describe(plan))
    if plan.work == 0 then
        Txn.commit()
        return true, ("already matches (%d pieces)"):format(plan.keep), plan, true
    end

    local moneyBefore = Game.money()
    local t0 = os.clock()
    local res = Paste.apply(plan, mode)
    local took = os.clock() - t0
    if State.stopFlag then return false, "stopped", plan end
    Txn.commit()

    local landed = ("pasted in %.1f s — %d moved, %d placed%s"):format(took, res.moved, res.placed,
        #res.fails > 0 and (", " .. #res.fails .. " refused") or "")
    okl("%s", landed)
    if onPasted then pcall(onPasted, landed) end

    local final, vwhy = plan, nil
    if CONFIG.verifyAfterPaste then
        State.progress.phase = "checking every piece"
        task.wait(1.5)
        local v
        v, vwhy = Paste.verify(layout, houseId)
        final = v or plan
    end
    if State.stopFlag then return false, "stopped", plan end

    -- The check couldn't look (a purchase still landing, or the house didn't
    -- read): report what the paste itself knows, never the old plan.
    if CONFIG.verifyAfterPaste and vwhy then
        local unconfirmed, refused = 0, 0
        for _, f in ipairs(res.fails) do
            if f.status == "TIMEOUT" or f.status == "NO_REPLY" or f.status == "UNKNOWN" then
                unconfirmed = unconfirmed + 1
            else
                refused = refused + 1
            end
        end
        local msg = ("pasted in %.1f s — %d moved, %d placed"):format(took, res.moved, res.placed)
        if unconfirmed > 0 then
            msg = msg .. (" · %d not confirmed yet (the server is still placing them, check again before pressing Fix)"):format(unconfirmed)
        end
        if refused > 0 then msg = msg .. (" · %d refused"):format(refused) end
        if vwhy == "unread" then msg = msg .. " · couldn't re-read the house to check" end
        return false, msg, nil, false, "unverified"
    end
    State.lastPlan = final

    local spent = moneyBefore - Game.money()
    local missing = CONFIG.verifyAfterPaste and (#final.moves + #final.buys) or #res.fails
    local msg = CONFIG.verifyAfterPaste and ("%d/%d in place"):format(final.keep, #layout.items) or landed
    if missing > 0 then msg = msg .. (" · %d missing"):format(missing) end
    if #final.skipped > 0 then msg = msg .. " · skipped " .. Plan.skipReasons(final) end
    if spent > 0 then msg = msg .. (" · spent $%s"):format(commas(spent)) end
    return missing == 0, msg, final
end

--==============================================================================
-- SAVE FORMAT + FILES
--==============================================================================

local Store = {}

local function cfToT(cf) return { cf:GetComponents() } end

-- Accepts 12 components, 6, a position triple, {X,Y,Z}, or a tostring(cframe).
local function tToCF(t)
    if typeof(t) == "CFrame" then return t end
    if typeof(t) == "Vector3" then return CFrame.new(t) end
    if type(t) == "table" then
        if #t >= 12 then return CFrame.new(table.unpack(t, 1, 12)) end
        if #t == 6  then return CFrame.new(table.unpack(t, 1, 6)) end
        if #t == 3  then return CFrame.new(t[1], t[2], t[3]) end
        local x = t.x or t.X ; local y = t.y or t.Y ; local z = t.z or t.Z
        if x and y and z then return CFrame.new(x, y, z) end
    end
    if type(t) == "string" then
        local nums = {}
        for n in t:gmatch("%-?%d+%.?%d*e?%-?%d*") do nums[#nums + 1] = tonumber(n) end
        if #nums >= 12 then return CFrame.new(table.unpack(nums, 1, 12)) end
        if #nums >= 3 then return CFrame.new(nums[1], nums[2], nums[3]) end
    end
    return nil
end

-- Adopt Me keeps colours as {[1] = Color3, …}. JSONEncode would write each
-- Color3 as null, so they go out as [r, g, b] — kept dense so JSON sees an array.
local function colorsOut(c)
    if type(c) ~= "table" then return nil end
    local out, n = {}, 0
    for k, v in pairs(c) do
        if type(k) == "number" and typeof(v) == "Color3" then
            out[k] = { r4(v.R), r4(v.G), r4(v.B) }
            if k > n then n = k end
        end
    end
    if n == 0 then return nil end
    for i = 1, n do if out[i] == nil then out[i] = false end end
    return out
end

-- Color3, [r,g,b] (0-1 or 0-255) or {r,g,b} -> Color3, keeping numeric keys.
local function normalizeColors(c)
    if type(c) ~= "table" then return nil end
    local out, any = {}, false
    for k, v in pairs(c) do
        local key = tonumber(k) or k
        if typeof(v) == "Color3" then
            out[key] = v ; any = true
        elseif type(v) == "table" then
            local r = tonumber(v[1] or v.r or v.R)
            local g = tonumber(v[2] or v.g or v.G)
            local b = tonumber(v[3] or v.b or v.B)
            if r and g and b then
                if r > 1 or g > 1 or b > 1 then out[key] = Color3.fromRGB(r, g, b)
                else out[key] = Color3.new(r, g, b) end
                any = true
            end
        end
    end
    return any and out or nil
end

function Store.serialize(layout)
    local out = {
        version = 3, name = layout.name, buildingType = layout.buildingType,
        savedAt = os.time(), textures = layout.textures, items = {},
    }
    for _, it in ipairs(layout.items) do
        out.items[#out.items + 1] = {
            id = it.id, cframe = cfToT(it.cframe), colors = colorsOut(it.colors), scale = it.scale or 1,
        }
    end
    return out
end

function Store.encode(layout) return HttpService:JSONEncode(Store.serialize(layout)) end

-- FOREIGN FORMATS. Other cloners (Ragesploit and friends) publish houses as
-- JSON with renamed keys, or as a Lua table behind a banner comment. JSON goes
-- first, then Lua, then a shape-agnostic hunt for the furniture list.
--
-- The Lua path runs in a DATA-ONLY sandbox: CFrame/Vector3/Color3/math/string/
-- table and nothing else — no game, no getgenv, no loadstring, no HTTP. A
-- "house file" that's secretly a logger can't reach anything from in there.

-- Ragesploit compresses keys: i = id, cf = cframe, s = scale, c = colors.
local function fieldId(d) return d.id or d.kind or d.i or d.name or d.Name or d.item or d.furniture end
local function fieldCF(d) return d.cframe or d.CFrame or d.cf or d.position or d.pos or d.Position or d.coords end
local function fieldScale(d) return tonumber(d.scale or d.s) or 1 end
local function fieldColors(d) return d.colors or d.color or d.c end

local function looksLikeFurniture(v)
    if type(v) ~= "table" then return false end
    local d = v.data or v
    return type(d) == "table" and fieldId(d) ~= nil and fieldCF(d) ~= nil
end

-- Textures come as {Room1 = {floors, walls}} (ours, the game's) or as a list
-- of {id, room, type} (Ragesploit, ZekeHub). Always hand back the first form.
local function normalizeTextures(t)
    if type(t) ~= "table" then return nil end
    local out, any = {}, false
    for k, v in pairs(t) do
        if type(v) == "table" then
            if v.room and v.type and v.id then
                out[v.room] = out[v.room] or {}
                out[v.room][v.type] = v.id
                any = true
            elseif v.floors or v.walls then
                out[k] = out[k] or {}
                out[k].floors = out[k].floors or v.floors
                out[k].walls = out[k].walls or v.walls
                any = true
            end
        end
    end
    return any and out or nil
end

-- `bt` may be a HouseDB key ("micro_2023") or a display name ("Tiny Home").
local function resolveBuildingType(bt)
    if bt == nil then return nil end
    bt = tostring(bt)
    if HouseDB[bt] then return bt end
    for kind, db in pairs(HouseDB) do
        if type(db) == "table" and db.name == bt then return kind end
    end
    return nil
end

-- The biggest array that's mostly furniture, wherever a tool buried it.
local function findFurnitureArray(root, depth)
    depth = depth or 0
    if depth > 6 or type(root) ~= "table" then return nil end
    local n, hits = 0, 0
    for _, v in pairs(root) do
        n = n + 1
        if looksLikeFurniture(v) then hits = hits + 1 end
    end
    if n > 0 and hits >= math.max(1, math.floor(n * 0.5)) then return root end
    local best, bestN = nil, 0
    for _, v in pairs(root) do
        if type(v) == "table" then
            local found = findFurnitureArray(v, depth + 1)
            if found then
                local c = 0
                for _ in pairs(found) do c = c + 1 end
                if c > bestN then best, bestN = found, c end
            end
        end
    end
    return best
end

local function tryLua(src)
    if not loadstring then return nil, "executor has no loadstring" end
    local env = {
        CFrame  = { new = CFrame.new, Angles = CFrame.Angles, fromEulerAnglesXYZ = CFrame.fromEulerAnglesXYZ,
                    fromMatrix = CFrame.fromMatrix },
        Vector3 = { new = Vector3.new },
        Vector2 = { new = Vector2.new },
        Color3  = { new = Color3.new, fromRGB = Color3.fromRGB, fromHSV = Color3.fromHSV },
        UDim2   = { new = UDim2.new },
        math = math, string = string, table = table,
        tonumber = tonumber, tostring = tostring, type = type, typeof = typeof,
        pairs = pairs, ipairs = ipairs, select = select, unpack = table.unpack,
    }
    local braced = src:match("(%b{})")
    local attempts = { src, "return " .. src, braced and ("return " .. braced) or nil }
    local lastErr
    for i = 1, 3 do
        local chunk = attempts[i]
        if chunk then
            local fn, compileErr = loadstring(chunk)
            if fn then
                if setfenv then pcall(setfenv, fn, env) end
                local ok, res = pcall(fn)
                if ok and type(res) == "table" then return res end
                lastErr = ok and ("returned " .. typeof(res)) or ("runtime: " .. tostring(res):sub(1, 70))
            else
                lastErr = tostring(compileErr):sub(1, 70)
            end
        end
    end
    return nil, "not valid Lua either — " .. tostring(lastErr)
end

function Store.decode(str)
    if type(str) ~= "string" then return nil, "no content" end
    str = str:gsub("^%s+", ""):gsub("%s+$", "")
    if str == "" then return nil, "empty" end
    if str:sub(1, 1) == "<" then
        return nil, "got a web page, not a house — bad paste id, or the paste is private/removed"
    end
    State.lastFetch = str

    local function tryJSON(s)
        local ok, res = pcall(function() return HttpService:JSONDecode(s) end)
        return (ok and type(res) == "table") and res or nil
    end

    local stripped = str
        :gsub("^%-%-%[=*%[.-%]=*%]%s*", "")
        :gsub("^([%-][%-][^\n]*\n)+", "")
        :gsub("^%s+", "")

    local root, source = tryJSON(str), "JSON"
    if not root and stripped ~= str then
        root = tryJSON(stripped)
        if root then source = "JSON (banner stripped)" end
    end
    if not root then
        local luaRes, luaErr = tryLua(str)
        if not luaRes and stripped ~= str then luaRes, luaErr = tryLua(stripped) end
        if not luaRes then
            return nil, ("not JSON and not Lua (%s) — starts: %s"):format(tostring(luaErr), (str:sub(1, 100):gsub("%s+", " ")))
        end
        root, source = luaRes, "Lua"
    end

    local list = findFurnitureArray(root)
    if type(list) ~= "table" then
        local keys = {}
        for k in pairs(root) do keys[#keys + 1] = tostring(k) end
        table.sort(keys)
        return nil, ("parsed the %s but found no furniture list — keys: %s"):format(source, table.concat(keys, ", "):sub(1, 90))
    end

    local items, skipped = {}, 0
    for _, raw in pairs(list) do
        local d = type(raw) == "table" and (raw.data or raw) or nil
        if type(d) == "table" then
            local id, cf = fieldId(d), tToCF(fieldCF(d))
            if id and cf then
                items[#items + 1] = {
                    id = tostring(id), cframe = cf,
                    colors = normalizeColors(fieldColors(d)), scale = fieldScale(d),
                }
            else
                skipped = skipped + 1
            end
        end
    end
    if #items == 0 then
        return nil, ("read %d entr(ies) from the %s, none had a usable id + cframe"):format(skipped, source)
    end

    local kind = resolveBuildingType(root.buildingType or root.building_type or root.houseType or root.house_type or root.bt)
    info("import: %s, %d piece(s)%s%s", source, #items,
        skipped > 0 and (", skipped " .. skipped) or "", kind and (", " .. Game.houseName(kind)) or "")

    return {
        version = 3,
        name = tostring(root.name or root.Name or root.saved_by or "imported"),
        buildingType = kind,
        textures = normalizeTextures(root.textures or root.t),
        items = items,
    }
end

function Store.ensure()
    if not hasFS then return false end
    pcall(function()
        if not fs.isdir(CONFIG.folder) then fs.mkdir(CONFIG.folder) end
        if not fs.isdir(CONFIG.housesFolder) then fs.mkdir(CONFIG.housesFolder) end
    end)
    return true
end

-- Save names are cleaned for the file system; existing files are always opened
-- by their real path (a name like "greek (1)" must not become "greek _1_").
function Store.path(n)
    return CONFIG.housesFolder .. "/" .. (tostring(n):gsub("[^%w%-_ ]", "_")) .. ".json"
end

-- Other cloners' libraries in the executor workspace, listed next to ours so an
-- existing collection loads without copying anything. Read-only: only our own
-- folder can be deleted from.
local LIBRARIES = {
    { tag = nil,                    path = CONFIG.housesFolder },
    { tag = "Ragesploit",           path = "Ragesploit/House Cloner/Saved Houses" },
    { tag = "Ragesploit pastebins", path = "Ragesploit/House Cloner/Pastebins" },
    { tag = "ZekeHub",              path = "ZekeHub/HouseSaves" },
    { tag = "NyxHouse",             path = "NyxHouse/houses" },
}

-- Returns {label, name, path, own} for every .json in every library.
function Store.list()
    if not hasFS or not fs.list then return {} end
    Store.ensure()
    local out, seen = {}, {}
    for _, lib in ipairs(LIBRARIES) do
        local okDir, isDir = pcall(fs.isdir, lib.path)
        if okDir and isDir then
            local ok, files = pcall(fs.list, lib.path)
            local mine = {}
            for _, f in ipairs(ok and files or {}) do
                local n = tostring(f):match("([^/\\]+)%.[jJ][sS][oO][nN]$")
                if n then
                    local label = lib.tag and (n .. "  [" .. lib.tag .. "]") or n
                    if not seen[label] then
                        seen[label] = true
                        mine[#mine + 1] = {
                            label = label, name = n, own = lib.tag == nil,
                            path = (tostring(f):gsub("\\", "/")),   -- Volt lists with backslashes
                        }
                    end
                end
            end
            table.sort(mine, function(a, b) return a.name:lower() < b.name:lower() end)
            for _, e in ipairs(mine) do out[#out + 1] = e end
        end
    end
    return out
end

-- A save name that doesn't clobber an existing file: "Name", "Name 2", "Name 3"…
function Store.freeName(name)
    name = (tostring(name or "house"):gsub("[^%w%-_ ]", "_"))
    if not hasFS then return name end
    local candidate, n = name, 1
    while true do
        local ok, exists = pcall(fs.isfile, Store.path(candidate))
        if not (ok and exists) then return candidate end
        n = n + 1
        candidate = name .. " " .. n
    end
end

function Store.save(name, layout)
    if not hasFS then return false, "no file API" end
    Store.ensure()
    local copy = {}
    for k, v in pairs(layout) do copy[k] = v end
    copy.name = name
    local ok, e = pcall(function() fs.write(Store.path(name), Store.encode(copy)) end)
    return ok, ok and nil or tostring(e)
end

-- entry = a Store.list() row, or a plain save name.
function Store.load(entry)
    if not hasFS then return nil, "no file API" end
    local path, name
    if type(entry) == "table" then
        path, name = entry.path, entry.name
    else
        name = tostring(entry)
        path = CONFIG.housesFolder .. "/" .. name .. ".json"
        local okE, exists = pcall(fs.isfile, path)
        if not (okE and exists) then path = Store.path(name) end
    end
    local ok, body = pcall(function()
        if not fs.isfile(path) then return nil end
        return fs.read(path)
    end)
    if not ok then return nil, "couldn't read " .. tostring(path) .. ": " .. tostring(body) end
    if not body then return nil, "no file at " .. tostring(path) end
    local l, e = Store.decode(body)
    if l then l.name = name end
    return l, e
end

function Store.delete(entry)
    if not fs.del then return false, "no delfile" end
    if type(entry) == "table" then
        if not entry.own then return false, "only House Cloner's own saves can be deleted here" end
        return pcall(fs.del, entry.path)
    end
    return pcall(fs.del, Store.path(entry))
end

-- A bare paste code, a pastebin/github URL, or the JSON/Lua body itself.
function Store.fromPastebin(raw)
    raw = tostring(raw):gsub("^%s+", ""):gsub("%s+$", "")
    if raw:match("^[%w]+$") and #raw >= 5 and #raw <= 16 then
        raw = "https://pastebin.com/raw/" .. raw
    end
    if not raw:match("^https?://") then return Store.decode(raw) end
    local url = raw
    local id = url:match("pastebin%.com/raw/([%w]+)") or url:match("pastebin%.com/([%w]+)")
    if id then url = "https://pastebin.com/raw/" .. id end
    url = url:gsub("github%.com/(.-)/blob/", "raw.githubusercontent.com/%1/")
    info("fetching %s", url)
    local ok, res = pcall(function() return game:HttpGet(url, true) end)
    if not ok then return nil, "fetch failed: " .. tostring(res):sub(1, 80) end
    return Store.decode(res)
end

function Store.toPastebin(apiKey, pasteName, layout)
    if not httpRequest then return nil, "executor has no http request function" end
    if not apiKey or apiKey == "" then return nil, "pastebin API dev key required" end
    local payload = table.concat({
        "api_dev_key=" .. HttpService:UrlEncode(apiKey),
        "api_option=paste",
        "api_paste_code=" .. HttpService:UrlEncode(Store.encode(layout)),
        "api_paste_name=" .. HttpService:UrlEncode(pasteName ~= "" and pasteName or "House Cloner"),
        "api_paste_format=json",
        "api_paste_private=1",
        "api_paste_expire_date=1M",
    }, "&")
    local ok, res = pcall(function()
        return httpRequest({
            Url = "https://pastebin.com/api/api_post.php", Method = "POST",
            Headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
            Body = payload,
        })
    end)
    if not ok then return nil, "request failed" end
    local body = type(res) == "table" and (res.Body or res.body) or tostring(res)
    if type(body) == "string" and body:match("^https?://") then return body end
    return nil, tostring(body):sub(1, 120)
end

-- Code library: name -> bare paste code, one small JSON file.
function Store.loadCodes()
    if not hasFS then return {} end
    local ok, t = pcall(function()
        if not fs.isfile(CONFIG.codesFile) then return {} end
        return HttpService:JSONDecode(fs.read(CONFIG.codesFile))
    end)
    return (ok and type(t) == "table") and t or {}
end

function Store.saveCode(name, codeOrUrl)
    if not hasFS then return false, "no file API" end
    Store.ensure()
    local code = tostring(codeOrUrl):gsub("%s+", "")
    code = code:match("pastebin%.com/raw/([%w]+)") or code:match("pastebin%.com/([%w]+)") or code
    local t = Store.loadCodes()
    t[name] = code
    pcall(function() fs.write(CONFIG.codesFile, HttpService:JSONEncode(t)) end)
    return true, code
end

function Store.deleteCode(name)
    if not hasFS then return false end
    local t = Store.loadCodes()
    t[name] = nil
    pcall(function() fs.write(CONFIG.codesFile, HttpService:JSONEncode(t)) end)
    return true
end

function Store.codeLabels()
    local out = {}
    for name, code in pairs(Store.loadCodes()) do out[#out + 1] = ("%s  ·  %s"):format(name, tostring(code)) end
    table.sort(out)
    return out
end

--==============================================================================
-- LAYOUTS
--==============================================================================

local Layout = {}

function Layout.new(name, buildingType, items, textures)
    return { version = 3, name = name, buildingType = buildingType, textures = textures, items = items or {} }
end

-- A fresh read -> a layout (drops uniques, copies colours and textures).
function Layout.fromRead(name, buildingType, items, textures)
    local out = {}
    for _, it in ipairs(items) do
        out[#out + 1] = {
            id = it.id, cframe = it.cframe, scale = it.scale or 1,
            colors = type(it.colors) == "table" and table.clone(it.colors) or nil,
        }
    end
    local tex
    if type(textures) == "table" then
        tex = {}
        for room, t in pairs(textures) do
            if type(t) == "table" then tex[room] = { floors = t.floors, walls = t.walls } end
        end
    end
    return Layout.new(name, buildingType, out, tex)
end

-- Bucks if every piece were bought, plus counts of what can't be.
function Layout.value(layout)
    local total, blocked = 0, 0
    for _, it in ipairs(layout.items) do
        local class, cost = Rules.classify(it.id)
        if class == "buy" then total = total + (cost or 0) else blocked = blocked + 1 end
    end
    return total, blocked
end

-- Per-piece rollup, priciest first: {id, name, count, unit, total, class}.
function Layout.contents(layout)
    local by, out = {}, {}
    for _, it in ipairs(layout.items) do
        local e = by[it.id]
        if not e then
            local class, cost = Rules.classify(it.id)
            e = { id = it.id, name = Rules.name(it.id), count = 0, unit = cost or 0, class = class }
            by[it.id] = e
            out[#out + 1] = e
        end
        e.count = e.count + 1
    end
    for _, e in ipairs(out) do e.total = e.unit * e.count end
    table.sort(out, function(a, b)
        if a.total ~= b.total then return a.total > b.total end
        return a.name < b.name
    end)
    return out
end

function Layout.without(layout, dropIds)
    local items = {}
    for _, it in ipairs(layout.items) do
        if not dropIds[it.id] then items[#items + 1] = it end
    end
    return Layout.new(layout.name, layout.buildingType, items, layout.textures), #layout.items - #items
end

-- Keep only what can actually be placed: on sale, or sitting in your storage.
function Layout.obtainable(layout, storage)
    local store, items = {}, {}
    for k, n in pairs(storage or {}) do store[k] = n end
    for _, it in ipairs(layout.items) do
        local class = Rules.classify(it.id)
        local kind = Rules.buyKind(it.id)
        local ok = class == "buy" or (class == "event" and CONFIG.spendEventCurrency)
        if not ok and class ~= "unknown" and class ~= "unusable" and (store[kind] or 0) > 0 then
            store[kind] = store[kind] - 1
            ok = true
        end
        if ok then items[#items + 1] = it end
    end
    return Layout.new(layout.name, layout.buildingType, items, layout.textures), #layout.items - #items
end

--==============================================================================
-- GHOST PREVIEW
--==============================================================================

local Preview = { model = nil, building = false, pending = 0 }
local PREVIEW_TINT = Color3.fromRGB(96, 206, 255)

local function interiorModel()
    local hi = workspace:FindFirstChild("HouseInteriors")
    local bp = hi and hi:FindFirstChild("blueprint")
    return bp and bp:GetChildren()[1]
end

function Preview.clear()
    Preview.pending = 0
    ui(function()
        if Preview.model then Preview.model:Destroy() end
        Preview.model = nil
        local stray = workspace:FindFirstChild("HouseClonerPreview")
        if stray then stray:Destroy() end
    end)
end

-- Real furniture models: DownloadClient.download("Furniture", model_name) is
-- what the build menu's own placement ghost uses. Templates are fetched here
-- (a module call — worker thread), then cloned a few per frame on the render
-- thread. World pose = SpecialParts.FurnitureOrigin.CFrame * layout cframe,
-- pivoted on PlacementBlock, same as FurniturePlacer.place.
function Preview.build(layout)
    if Preview.building then return false, "a preview is still building" end
    local house = interiorModel()
    local sp = house and house:FindFirstChild("SpecialParts")
    local originPart = sp and sp:FindFirstChild("FurnitureOrigin")
    if not originPart then return false, "go inside a house first — no interior is loaded" end
    local origin = originPart.CFrame

    Preview.building = true
    Preview.clear()
    local DL = DownloadClient()
    local templates, jobs = {}, {}
    local cap = math.min(#layout.items, math.max(1, CONFIG.previewCap))
    for i = 1, cap do
        local it = layout.items[i]
        local db = FurnitureDB[Rules.buyKind(it.id)]
        local mn = type(db) == "table" and db.model_name or nil
        if mn and DL and templates[mn] == nil then
            local ok, tpl = pcall(DL.download, "Furniture", mn)
            templates[mn] = (ok and typeof(tpl) == "Instance") and tpl or false
        end
        jobs[#jobs + 1] = { tpl = mn and templates[mn] or nil, cf = origin * it.cframe, scale = it.scale or 1 }
    end

    ui(function()
        local holder = Instance.new("Model")
        holder.Name = "HouseClonerPreview"
        local hl = Instance.new("Highlight")
        hl.FillColor = PREVIEW_TINT
        hl.OutlineColor = PREVIEW_TINT
        hl.FillTransparency = 0.7
        hl.OutlineTransparency = 0.2
        hl.DepthMode = Enum.HighlightDepthMode.Occluded
        hl.Parent = holder
        holder.Parent = workspace
        Preview.model = holder
    end)

    Preview.pending = #jobs
    for _, j in ipairs(jobs) do
        uiLater(function()
            if not Preview.model then return end
            Preview.pending = Preview.pending - 1
            local m = j.tpl and j.tpl:Clone()
            if m then
                local pb = m:FindFirstChild("PlacementBlock")
                if pb then m.PrimaryPart = pb end
                m:PivotTo(j.cf)
                if j.scale ~= 1 then pcall(function() m:ScaleTo(j.scale) end) end
                for _, d in ipairs(m:GetDescendants()) do
                    if d:IsA("BasePart") then
                        d.Anchored, d.CanCollide, d.CanTouch, d.CanQuery, d.CastShadow = true, false, false, false, false
                        d.Transparency = (d == pb) and 1 or math.max(d.Transparency, 0.35)
                    elseif d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Sound")
                        or d:IsA("ProximityPrompt") or d:IsA("ClickDetector") then
                        d:Destroy()
                    end
                end
            else
                m = Instance.new("Part")
                m.Anchored, m.CanCollide, m.CanTouch, m.CanQuery = true, false, false, false
                m.Size = Vector3.new(2, 2, 2) * j.scale
                m.CFrame = j.cf
                m.Color = PREVIEW_TINT
                m.Material = Enum.Material.ForceField
            end
            m.Parent = Preview.model
        end)
    end

    task.spawn(function()
        local t0 = os.clock()
        while Preview.pending > 0 and os.clock() - t0 < 60 do task.wait(0.5) end
        if DL then
            for mn, tpl in pairs(templates) do
                if tpl then pcall(DL.release, "Furniture", mn) end
            end
        end
        Preview.building = false
    end)

    local missing = 0
    for _, j in ipairs(jobs) do if not j.tpl then missing = missing + 1 end end
    return true, ("%d piece(s)%s%s"):format(#jobs,
        #layout.items > cap and (" — capped at " .. cap) or "",
        missing > 0 and (" · " .. missing .. " as boxes (no model)") or "")
end

--==============================================================================
-- RENAMER
--==============================================================================
-- The name filter masks throttled renames as '#' × length, and can flip a name
-- that already read correctly to ##### seconds later. So renames go out one at
-- a time, CONFIG.renameGap apart, and get re-checked well after the last one.

local Renamer = { queue = {}, lastAt = -math.huge, running = false, wanted = {} }

function Renamer.push(houseId, name)
    Renamer.wanted[houseId] = name
    table.insert(Renamer.queue, houseId)
    Renamer.kick()
end

function Renamer.kick()
    if Renamer.running then return end
    Renamer.running = true
    task.spawn(function()
        while #Renamer.queue > 0 do
            local id = table.remove(Renamer.queue, 1)
            local name = Renamer.wanted[id]
            local wait = CONFIG.renameGap - (os.clock() - Renamer.lastAt)
            if wait > 0 then task.wait(wait) end
            if name then
                Game.rename(id, name)
                Renamer.lastAt = os.clock()
                info("renamed house #%s -> %s", tostring(id), name)
            end
        end
        Renamer.running = false
    end)
end

function Renamer.wrong()
    local bad = {}
    for _, h in ipairs(Game.houses()) do
        local want = Renamer.wanted[h.house_id]
        if want and h.name ~= want then bad[#bad + 1] = h.house_id end
    end
    return bad
end

function Renamer.verify(rounds)
    for r = 1, rounds or 3 do
        while Renamer.running or #Renamer.queue > 0 do task.wait(1) end
        task.wait(25)
        local bad = Renamer.wrong()
        if #bad == 0 then
            okl("all house names check out")
            return true
        end
        info("names round %d: %d masked or wrong — renaming again", r, #bad)
        for _, id in ipairs(bad) do table.insert(Renamer.queue, id) end
        Renamer.kick()
    end
    while Renamer.running or #Renamer.queue > 0 do task.wait(1) end
    local left = #Renamer.wrong()
    if left > 0 then errl("%d house name(s) still masked — the filter may be rejecting a word", left) end
    return left == 0
end

--==============================================================================
-- WEBHOOK + ANTI-AFK
--==============================================================================

local function webhook(text)
    if not (CONFIG.webhookOn and httpRequest and tostring(CONFIG.webhookUrl):match("^https://")) then return end
    task.spawn(function()
        pcall(httpRequest, {
            Url = CONFIG.webhookUrl, Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode({
                username = "House Cloner",
                content = ("**%s** · %s"):format(LP.Name, text):sub(1, 1900),
            }),
        })
    end)
end

-- Disables the Idled connections (the 20-minute idle kick hangs off them).
-- No VirtualUser fallback on purpose: some games flag merely acquiring it.
local function setAntiAfk(on)
    if typeof(getconns) ~= "function" then
        if on then info("anti-AFK needs getconnections — this executor has none") end
        return false
    end
    local n = 0
    for _, c in ipairs(getconns(LP.Idled)) do
        if pcall(function() if on then c:Disable() else c:Enable() end end) then n = n + 1 end
    end
    return n > 0
end

--==============================================================================
-- AUTO BATCH
--==============================================================================
-- For each house: (buy it) → check it from outside → if the layout isn't there
-- yet: make it active → walk in → paste → verify → paint → rename. A ledger on
-- disk remembers which houses this batch bought, so Start after a stop, crash
-- or rejoin carries on instead of buying again.

local Batch = {}

function Batch.load()
    local l
    if hasFS then
        local ok, t = pcall(function()
            if not fs.isfile(CONFIG.ledgerFile) then return nil end
            return HttpService:JSONDecode(fs.read(CONFIG.ledgerFile))
        end)
        if ok and type(t) == "table" then l = t end
    end
    l = l or {}
    l.done = type(l.done) == "table" and l.done or {}
    l.created = type(l.created) == "table" and l.created or {}
    return l
end

function Batch.save(l)
    if not hasFS then return end
    Store.ensure()
    pcall(function() fs.write(CONFIG.ledgerFile, HttpService:JSONEncode(l)) end)
end

function Batch.reset()
    Batch.save({ done = {}, created = {} })
end

function Batch.name(layout, n, kind)
    local tpl = (CONFIG.renameTemplate ~= "" and CONFIG.renameTemplate) or "{layout} #{n}"
    local lname = tostring(layout.name or "House")
    local s = tpl:gsub("{layout}", function() return lname end)
    s = s:gsub("{n}", function() return tostring(n) end)
    s = s:gsub("{type}", function() return Game.houseName(kind) end)
    return s:sub(1, 30)
end

-- Worst case: every piece bought, nothing reused, nothing from storage.
function Batch.estimate(layout, kind, count)
    local price = (type(HouseDB[kind]) == "table" and HouseDB[kind].cost) or 0
    local p = Plan.build(layout, nil, {}, 0, nil)
    Plan.fit(p, CONFIG.houseCap)
    local owned = 0
    if CONFIG.batchUseOwned then
        for _, h in ipairs(Game.houses()) do if h.building_type == kind then owned = owned + 1 end end
    end
    owned = math.min(owned, count)
    local per = p.cost + p.texCost
    return {
        price = price, per = per, owned = owned, toBuy = count - owned,
        total = (count - owned) * price + count * per, skipped = #p.skipped,
    }
end

--------------------------------------------------------------------------------
-- LIVE CHECK + HOUSE BOARD
--------------------------------------------------------------------------------

-- How much of the layout one of YOUR houses already holds — read from outside
-- (the remote takes any of your house ids, active or not, no walking in).
-- Wall/floor textures can't be read for a house you're not in, so they're
-- reported as unknown rather than guessed.
--   done     every piece that fits is in place
--   partial  at least half of it is
--   empty    less than that (a fresh house, or someone else's layout)
--   skipped  the layout has nothing you can get, so there is nothing to place
function Batch.inspect(layout, houseId)
    local items, e = Game.read(houseId, LP)
    if not items then return { state = "error", why = tostring(e) } end
    local p = Plan.build(layout, items, Game.storage(), Game.money(), nil)
    Plan.fit(p, Game.houseCap(houseId))
    local missing = #p.moves + #p.buys
    local wanted = p.keep + missing
    local state
    if missing == 0 then
        state = (p.keep > 0) and "done" or "skipped"
    elseif p.keep / wanted >= 0.5 then
        state = "partial"
    else
        state = "empty"
    end
    return {
        state = state, keep = p.keep, missing = missing, wanted = wanted, extra = #p.leftovers,
        unobtainable = #p.skipped, texUnknown = #p.texChanges > 0,
    }
end

local BOARD_ICON = {
    done = "🟢", partial = "🟡", empty = "⚪", pending = "⚪", working = "🔵",
    failed = "🔴", error = "🔴", skipped = "⚫",
}

-- One line per house on the Auto page, colour-coded.
function Batch.board(n, houseId, state, detail)
    local rows = State.boardRows
    local row
    for _, r in ipairs(rows) do
        if r.id == houseId then row = r break end
    end
    if not row then
        row = { n = n, id = houseId }
        rows[#rows + 1] = row
        table.sort(rows, function(a, b) return (a.n or 0) < (b.n or 0) end)
    end
    row.n, row.state, row.detail = n or row.n, state, detail
    State.boardDirty = true
end

function Batch.boardText()
    if #State.boardRows == 0 then return "Press Check or Start to fill this in" end
    local t, counts = {}, {}
    for _, r in ipairs(State.boardRows) do
        counts[r.state] = (counts[r.state] or 0) + 1
        t[#t + 1] = ("%s  %s  #%s  %s"):format(BOARD_ICON[r.state] or "⚪",
            r.n and ("%2d."):format(r.n) or "  ", tostring(r.id), tostring(r.detail or r.state))
    end
    local hdr = ("🟢 %d pasted   🟡 %d partial   ⚪ %d not yet   🔴 %d failed"):format(
        counts.done or 0, counts.partial or 0, (counts.empty or 0) + (counts.pending or 0),
        (counts.failed or 0) + (counts.error or 0))
    if (counts.skipped or 0) > 0 then hdr = hdr .. ("   ⚫ %d nothing to place"):format(counts.skipped) end
    table.insert(t, 1, hdr)
    return table.concat(t, "\n")
end

-- A job that throws leaves its 🔵 rows behind; job() calls this to close them.
function Batch.boardAbort(why)
    for _, r in ipairs(State.boardRows) do
        if r.state == "working" then r.state, r.detail = "failed", why or "stopped by an error" end
    end
    State.boardDirty = true
end

local function inspectText(r)
    if r.state == "error" then return "couldn't read it: " .. tostring(r.why) end
    if r.state == "skipped" then
        return ("nothing to place — %d piece(s) can't be had"):format(r.unobtainable or 0)
    end
    local s = ("%d/%d pieces"):format(r.keep, r.wanted)
    if r.state == "done" then s = s .. " — pasted" end
    if r.extra > 0 then s = s .. (" · %d extra"):format(r.extra) end
    if r.state == "done" and r.texUnknown then s = s .. " · walls/floors checked on Start" end
    return s
end

-- The houses a batch works through: what an earlier run of this batch bought,
-- then (with includeOwned) houses you already owned of the type.
local function batchTargets(ledger, kind, count, includeOwned)
    local targets, seen = {}, {}
    local function add(id)
        if id and not seen[id] and #targets < count then seen[id] = true ; targets[#targets + 1] = id end
    end
    for _, id in ipairs(ledger.created) do
        local hid = tonumber(id) or id
        if Game.house(hid) then add(hid) end
    end
    if includeOwned then
        for _, h in ipairs(Game.houses()) do if h.building_type == kind then add(h.house_id) end end
    end
    return targets
end

-- Repaint a house unless it already wears the colour, then read the colour
-- back from house_manager to confirm. Returns:
--   "skip"     no colour picked, or it already has it
--   "painted"  confirmed
--   "sent"     fired, but the colour didn't show within 3 s
--   "failed"   the call itself errored (second value = why)
local function paint(houseId)
    local c = HOUSE_COLORS[CONFIG.houseColor]
    if not c then return "skip" end
    local function same(cur)
        return typeof(cur) == "Color3" and math.abs(cur.R - c.R) + math.abs(cur.G - c.G) + math.abs(cur.B - c.B) < 0.01
    end
    local h = Game.house(houseId)
    if h and same(h.color) then return "skip" end
    local ok, e = Game.colorHouse(houseId, c)
    if not ok then
        errl("paint #%s: %s", tostring(houseId), tostring(e))
        return "failed", tostring(e)
    end
    local t0 = os.clock()
    while os.clock() - t0 < 3 do
        task.wait(0.25)
        if same((Game.house(houseId) or {}).color) then return "painted" end
    end
    return "sent"
end

-- Check what Start would do, without pasting anything. Your other houses of
-- the type are checked too, and marked as outside the batch.
function Batch.check()
    local layout = State.layout
    if not layout or #layout.items == 0 then return false, "load a layout first" end
    local kind = CONFIG.batchKind
    local count = math.clamp(math.floor(CONFIG.batchCount), 1, 50)
    local ledger = Batch.load()
    if ledger.layout ~= layout.name or ledger.kind ~= kind then ledger = { done = {}, created = {} } end

    local targets = batchTargets(ledger, kind, count, CONFIG.batchUseOwned)
    local inBatch, others = {}, {}
    for _, id in ipairs(targets) do inBatch[id] = true end
    for _, h in ipairs(Game.houses()) do
        if h.building_type == kind and not inBatch[h.house_id] then others[#others + 1] = h.house_id end
    end

    State.boardRows = {}
    State.boardDirty = true
    State.progress = { done = 0, total = #targets + #others, phase = "checking houses" }
    if #targets + #others == 0 then
        return true, ("you own no %s yet — Start will buy %d"):format(Game.houseName(kind), count)
    end

    local home = Game.homeOwner()
    local pasted = 0
    local function look(n, id, outside, wouldJoin)
        Batch.board(n, id, "working", "checking…")
        local okI, r = pcall(Batch.inspect, layout, id)
        if not okI then r = { state = "error", why = tostring(r) } end
        local text = inspectText(r)
        if outside then
            text = text .. (wouldJoin and "  (not in the batch — turn on \"Also fill houses I already own\")"
                or "  (past the batch size)")
        end
        Batch.board(n, id, r.state, text)
        State.progress.done = State.progress.done + 1
        return r
    end
    for i, id in ipairs(targets) do
        if State.stopFlag then break end
        if look(i, id, false).state == "done" then pasted = pasted + 1 end
    end
    local free = count - #targets
    for j, id in ipairs(others) do
        if State.stopFlag then break end
        look(#targets + j, id, true, j <= free)
    end
    if home ~= LP then Game.subscribe(home) end

    local msg = ("%d of %d batch house(s) already have '%s'"):format(pasted, #targets, tostring(layout.name))
    if #targets < count then msg = msg .. (" · Start will buy %d more"):format(count - #targets) end
    if #others > 0 then msg = msg .. (" · %d other %s listed below"):format(#others, Game.houseName(kind)) end
    bline("check: %s", msg)
    return true, msg
end

function Batch.run()
    local layout = State.layout
    if not layout or #layout.items == 0 then return false, "load a layout first" end
    local kind = CONFIG.batchKind
    if type(HouseDB[kind]) ~= "table" or type(HouseDB[kind].cost) ~= "number" then
        return false, "pick a house type on the Auto page"
    end
    local count = math.clamp(math.floor(CONFIG.batchCount), 1, 50)
    local keep = tonumber(CONFIG.keepBucks) or 0

    local ledger = Batch.load()
    if ledger.layout ~= layout.name or ledger.kind ~= kind then
        ledger = { layout = layout.name, kind = kind, done = {}, created = {} }
    end
    Batch.save(ledger)

    local targets = batchTargets(ledger, kind, count, CONFIG.batchUseOwned)
    State.boardRows = {}
    State.boardDirty = true
    for i, id in ipairs(targets) do Batch.board(i, id, "pending", "waiting") end

    local est = Batch.estimate(layout, kind, count)
    bline("start: %d × %s · layout '%s' (%d pieces) · worst case $%s, you have $%s",
        count, Game.houseName(kind), tostring(layout.name), #layout.items, commas(est.total), commas(Game.money()))
    webhook(("batch started — %d × %s, layout '%s'"):format(count, Game.houseName(kind), tostring(layout.name)))
    State.progress = { done = 0, total = count, phase = "batch" }

    local home, leftHome = Game.homeOwner(), false
    local filled, pastedNow, failures, lastId = 0, 0, 0, nil
    for i = 1, count do
        if State.stopFlag then bline("stopped by you") break end
        local id = targets[i]
        local fresh = false

        if not id then
            local need = est.price + est.per + keep
            if Game.money() < need then
                bline("stopping: house %d needs up to $%s, you have $%s", i, commas(need), commas(Game.money()))
                break
            end
            bline("house %d/%d: buying a %s ($%s)", i, count, Game.houseName(kind), commas(est.price))
            local newId, e = Game.buyHouse(kind, HOUSE_COLORS[CONFIG.houseColor])
            if not newId then
                bline("house purchase failed: %s", tostring(e))
                break
            end
            table.insert(ledger.created, newId)
            Batch.save(ledger)
            targets[i], id, fresh = newId, newId, true
            Batch.board(i, id, "pending", "just bought")
        end

        -- Houses that may already hold the layout are checked from outside
        -- first, so a re-run walks into nothing and buys nothing for them.
        -- Textures can't be read from outside: a house is only skipped on that
        -- check alone once this batch has verified it from inside.
        local skip = false
        if not fresh and CONFIG.batchSkipDone then
            Batch.board(i, id, "working", "checking…")
            local okI, r = pcall(Batch.inspect, layout, id)
            if not okI then r = { state = "error", why = tostring(r) } end
            Batch.board(i, id, r.state, inspectText(r))
            local trusted = (not r.texUnknown) or ledger.done[tostring(id)]
            if r.state == "done" and trusted then
                skip = true
                filled = filled + 1
                bline("house %d/%d (#%s): already pasted (%d/%d) — skipped", i, count, tostring(id), r.keep, r.wanted)
            elseif r.state == "skipped" then
                skip = true
                bline("house %d/%d (#%s): nothing in the layout can be had — skipped", i, count, tostring(id))
            elseif r.state == "done" then
                bline("house %d/%d (#%s): furniture is in place — going in once to check walls/floors", i, count, tostring(id))
            elseif r.state ~= "error" then
                bline("house %d/%d (#%s): %d/%d pieces there — finishing it", i, count, tostring(id), r.keep, r.wanted)
            end
        end
        if State.stopFlag then bline("stopped by you") break end

        if not skip then
            Batch.board(i, id, "working", "going in…")
            bline("house %d/%d (#%s): going in", i, count, tostring(id))
            -- The outside checks moved the subscription to you. If you are standing
            -- in someone else's house, point it back first, or enterOwnHouse would
            -- read the interior as yours and think you're already inside.
            if not leftHome and home ~= LP then Game.subscribe(home) end
            local inOk, inErr, moved = Game.enterOwnHouse(id)
            if inOk or moved then leftHome = true end
            if not inOk then
                failures = failures + 1
                Batch.board(i, id, "failed", "couldn't get in: " .. tostring(inErr))
                bline("couldn't get into #%s: %s", tostring(id), tostring(inErr))
                if failures >= 3 then bline("3 houses in a row failed — stopping") break end
            else
                failures = 0
                Batch.board(i, id, "working", "pasting…")
                local good, msg, final, untouched, status = Paste.run(layout, id)
                State.progress = { done = i - 1, total = count, phase = ("batch %d/%d"):format(i, count) }
                bline("house %d/%d: %s", i, count, tostring(msg))
                if status == "inflight" then
                    Batch.board(i, id, "partial", tostring(msg))
                    bline("stopping: the last purchase is still landing on the server — press Start again in a minute")
                    break
                end
                if good then
                    -- verified from inside; only worth trusting later if textures were part of it
                    if CONFIG.applyTextures and final and #(final.texChanges or {}) == 0 then
                        ledger.done[tostring(id)] = true
                        Batch.save(ledger)
                    end
                    filled = filled + 1
                    if not untouched then
                        pastedNow = pastedNow + 1
                        lastId = id
                    end
                    Batch.board(i, id, "done", untouched and ("already matched — " .. tostring(msg)) or tostring(msg))
                elseif status == "unverified" then
                    Batch.board(i, id, "partial", tostring(msg))
                else
                    local partial = final and final.keep and final.keep > 0
                    Batch.board(i, id, partial and "partial" or "failed", tostring(msg))
                end
                webhook(("house %d/%d (#%s): %s"):format(i, count, tostring(id), tostring(msg)))
            end
        end

        if not State.stopFlag then
            local st, why = paint(id)
            if st == "painted" then
                bline("house %d/%d (#%s): painted %s", i, count, tostring(id), tostring(CONFIG.houseColor))
            elseif st == "sent" then
                bline("house %d/%d (#%s): paint sent, colour not confirmed yet", i, count, tostring(id))
            elseif st == "failed" then
                bline("house %d/%d (#%s): paint failed — %s", i, count, tostring(id), tostring(why))
            end
        end
        if CONFIG.renameOn and not State.stopFlag then
            local name = Batch.name(layout, i, kind)
            local h = Game.house(id)
            if not h or h.name ~= name then Renamer.push(id, name) end
        end
        State.progress.done = i
    end

    -- lastId is only set by a paste this run, so a re-run over finished houses
    -- doesn't switch the active house or list it again.
    if CONFIG.listLastHouse and lastId and not State.stopFlag then
        Game.setActive(lastId)
        local ok, msg = Game.listForTrade(true)
        bline("last house #%s: %s", tostring(lastId), tostring(msg))
    end
    -- Put the subscription where you actually are: your own (if travel fired)
    -- or wherever you stood before (if only outside checks ran).
    if home ~= LP then Game.subscribe(leftHome and LP or home) end
    if CONFIG.renameOn then
        task.spawn(function() Renamer.verify(3) end)
        bline("names are being set %d s apart and re-checked after", CONFIG.renameGap)
    end
    bline("finished: %d/%d house(s) have the layout (%d pasted this run)", filled, count, pastedNow)
    webhook(("batch finished — %d/%d house(s) filled, $%s left"):format(filled, count, commas(Game.money())))
    return filled > 0, ("%d/%d house(s) have the layout · %d pasted this run"):format(filled, count, pastedNow)
end

-- Just buy houses up to the count, no pasting.
function Batch.buyOnly()
    local kind, count = CONFIG.batchKind, math.clamp(math.floor(CONFIG.batchCount), 1, 50)
    local price = (type(HouseDB[kind]) == "table" and HouseDB[kind].cost) or 0
    local bought = 0
    State.progress = { done = 0, total = count, phase = "buying houses" }
    for i = 1, count do
        if State.stopFlag then break end
        if Game.money() - price < (tonumber(CONFIG.keepBucks) or 0) then
            bline("out of Bucks after %d house(s)", bought)
            break
        end
        local id, e = Game.buyHouse(kind, HOUSE_COLORS[CONFIG.houseColor])
        if not id then bline("purchase %d failed: %s", i, tostring(e)) break end
        bought = bought + 1
        bline("bought %s #%s (%d/%d)", Game.houseName(kind), tostring(id), i, count)
        State.progress.done = i
        task.wait(1.2)
    end
    return bought > 0, ("bought %d house(s)"):format(bought)
end

-- Repaint every house of the batch type in the chosen colour. A second away
-- between houses; stops if the game ignores the paint or if Bucks ever drop.
function Batch.paintAll()
    if not HOUSE_COLORS[CONFIG.houseColor] then return false, "pick a house colour first (not Default)" end
    local painted, unconfirmed, failed = 0, 0, 0
    local money0 = Game.money()
    for _, h in ipairs(Game.houses()) do
        if State.stopFlag then break end
        if h.building_type == CONFIG.batchKind then
            local st = paint(h.house_id)
            if st == "painted" then painted = painted + 1
            elseif st == "sent" then unconfirmed = unconfirmed + 1
            elseif st == "failed" then failed = failed + 1 end
            if st ~= "skip" then
                if Game.money() < money0 then
                    return false, "Bucks went down while painting — stopped to be safe"
                end
                if painted == 0 and unconfirmed + failed >= 2 then
                    return false, "the game isn't taking the paint — stopped after 2 houses"
                end
                task.wait(1)
            end
        end
    end
    local msg = ("painted %d %s %s"):format(painted, Game.houseName(CONFIG.batchKind), tostring(CONFIG.houseColor))
    if unconfirmed > 0 then msg = msg .. (" · %d not confirmed yet"):format(unconfirmed) end
    if failed > 0 then msg = msg .. (" · %d failed"):format(failed) end
    return failed == 0, msg
end

--==============================================================================
-- SCANNER
--==============================================================================
-- Reads every house standing in the server, prices it, and keeps the pieces in
-- memory so loading one is instant. Subscribing hops between owners, so the
-- subscription is pointed back at you (or whoever's house you're in) after.

local Scanner = { types = {} }

function Scanner.run()
    local exts = Game.exteriors()
    local home = Game.homeOwner()
    local wantAll = next(Scanner.types) == nil or Scanner.types.All
    State.scanned = {}
    local found = 0
    for i, e in ipairs(exts) do
        if State.stopFlag then break end
        State.scanStatus = ("reading %d/%d · %s"):format(i, #exts, tostring(e.player_name))
        State.progress = { done = i - 1, total = #exts, phase = "scanning" }
        if e.player ~= LP and (wantAll or Scanner.types[e.building_type]) then
            local items = Game.read(e.house_id, e.player)
            if items then
                local value = 0
                for _, it in ipairs(items) do
                    local class, cost = Rules.classify(it.id)
                    if class == "buy" then value = value + (cost or 0) end
                end
                if value >= (tonumber(CONFIG.scanMinValue) or 0) then
                    local hi = Game.interior()
                    local tex = (hi and hi.player == e.player) and hi.textures or nil
                    local name = ("%s's %s"):format(tostring(e.player_name), Game.houseName(e.building_type))
                    local entry = {
                        label = ("%s · %s · $%s · %d pcs"):format(tostring(e.player_name),
                            Game.houseName(e.building_type), commas(value), #items),
                        owner = e.player, ownerName = e.player_name, houseId = e.house_id,
                        kind = e.building_type, value = value,
                        layout = Layout.fromRead(name, e.building_type, items, tex),
                    }
                    State.scanned[#State.scanned + 1] = entry
                    found = found + 1
                    if CONFIG.scanAutoSave then
                        Store.save(("%s_%s_%d"):format(tostring(e.player_name), tostring(e.building_type), value), entry.layout)
                    end
                end
            end
        end
        task.wait(CONFIG.scanDelay)
    end
    table.sort(State.scanned, function(a, b) return a.value > b.value end)
    Game.subscribe(home)
    State.scanStatus = ("done — %d house(s)%s"):format(found, CONFIG.scanAutoSave and ", all saved" or "")
    return found
end

--==============================================================================
-- COMET HUB · RAYFIELD
--==============================================================================
-- Rayfield element handles live in the UI table rather than in locals — this
-- chunk sits close to Luau's 200-locals-per-function limit. Every callback that
-- touches the game hops to its own thread (go / job): calling a game module on
-- Rayfield's thread would leave Rayfield unable to update itself.

_G.HCV3.stage = "rayfield"
loadSettings()

-- One copy at a time: stop a previous run and clear older cloners' windows.
if type(_G.HouseClonerKill) == "function" then pcall(_G.HouseClonerKill) end
for _, host in ipairs({ gethuiFn and gethuiFn() or nil, game:GetService("CoreGui") }) do
    if host then
        for _, legacy in ipairs({ "HouseCloner", "NyxHouseV2", "NyxHouse", "CometPasteBox", "CometHowTo" }) do
            local old = host:FindFirstChild(legacy)
            while old do old:Destroy() ; old = host:FindFirstChild(legacy) end
        end
    end
end
do
    local stray = workspace:FindFirstChild("HouseClonerPreview")
    if stray then stray:Destroy() end
end

local UI = { conns = {}, maps = {}, sel = {} }
local function track(c) UI.conns[#UI.conns + 1] = c ; return c end

-- The menu library is downloaded every launch, and a failed download used to
-- end the script silently ("it doesn't even show up"). Now: two sources, two
-- rounds, then the last copy that worked (kept on disk). If everything fails
-- the player gets a message on screen instead of nothing.
pcall(function() getgenv().DISABLE_RAYFIELD_REQUESTS = true end)
local Rayfield
do
    local SOURCES = {
        "https://sirius.menu/rayfield",
        "https://raw.githubusercontent.com/SiriusSoftwareLtd/Rayfield/main/source.lua",
    }
    local CACHE = CONFIG.folder .. "/rayfield_cache.lua"
    local compile = loadstring or load
    local why = "no response"

    -- Each source gets one budget for both download methods, so a stuck
    -- request can't hold the script forever.
    local function fetch(url)
        local function timed(secs, f)
            local done, ok, res = false, false, nil
            task.spawn(function() ok, res = pcall(f) ; done = true end)
            local t0 = os.clock()
            while not done and os.clock() - t0 < secs do task.wait(0.05) end
            if not done then return false, "timed out" end
            return ok, res
        end
        _G.HCV3.stage = "rayfield: " .. url
        local okH, body = timed(8, function() return game:HttpGet(url) end)
        if okH and type(body) == "string" and #body > 1000 then return body end
        if httpRequest then
            local okQ, res = timed(8, function() return httpRequest({ Url = url, Method = "GET" }) end)
            body = okQ and type(res) == "table" and (res.Body or res.body) or nil
            if type(body) == "string" and #body > 1000 then return body end
        end
        why = "couldn't download " .. url
        return nil
    end
    local function build(body)
        local okC, fn, err = pcall(compile, body)
        if not (okC and fn) then why = "bad download: " .. tostring(okC and err or fn) return nil end
        local ok, lib = pcall(fn)
        if ok and type(lib) == "table" then return lib end
        why = "menu library crashed: " .. tostring(lib)
        return nil
    end
    local function fromCache()
        if not hasFS then return nil end
        local ok, body = pcall(function() return fs.isfile(CACHE) and fs.read(CACHE) or nil end)
        if not (ok and type(body) == "string") then return nil end
        local lib = build(body)
        if lib then warn("[Comet Hub] menu download failed — using the copy saved last time") end
        return lib
    end
    -- on-screen message for when the window can't appear at all
    function UI.banner(msg)
        pcall(function()
            local sg = Instance.new("ScreenGui")
            sg.Name = "CometHowTo"
            sg.ResetOnSpawn = false
            sg.DisplayOrder = 100002
            local l = Instance.new("TextLabel")
            l.Size = UDim2.new(0, 520, 0, 74)
            l.Position = UDim2.new(0.5, -260, 0, 40)
            l.BackgroundColor3 = Color3.fromRGB(14, 17, 30)
            l.TextColor3 = Color3.fromRGB(236, 240, 255)
            l.Font = Enum.Font.GothamBold
            l.TextSize = 14
            l.TextWrapped = true
            l.Text = msg
            l.Parent = sg
            Instance.new("UICorner", l).CornerRadius = UDim.new(0, 10)
            sg.Parent = (gethuiFn and gethuiFn()) or game:GetService("CoreGui")
            task.delay(15, function() pcall(function() sg:Destroy() end) end)
        end)
    end

    for round = 1, 2 do
        for _, url in ipairs(SOURCES) do
            local body = fetch(url)
            if body then
                Rayfield = build(body)
                -- cached only once the window has really opened (see below)
                if Rayfield then UI.rfBody = body break end
            end
        end
        if Rayfield then break end
        if round == 1 then
            Rayfield = fromCache()          -- don't make people wait for round 2
            if Rayfield then break end
            task.wait(2)
        end
    end

    if not Rayfield then
        warn("[Comet Hub] menu failed to load: " .. tostring(why))
        _G.HCV3.stage = "rayfield failed: " .. tostring(why)
        UI.banner("Comet Hub · House Cloner couldn't download its menu.\nCheck your internet, then run the script again. ("
            .. tostring(why):sub(1, 80) .. ")")
        return
    end
end

local ACCENTS = {
    Cyan = Color3.fromRGB(96, 206, 255), Pink = Color3.fromRGB(255, 110, 190),
    Purple = Color3.fromRGB(160, 120, 255), Green = Color3.fromRGB(90, 220, 140),
    Gold = Color3.fromRGB(255, 196, 70), Red = Color3.fromRGB(255, 96, 96),
}
local function cometTheme(accentName)
    local a = ACCENTS[accentName] or ACCENTS.Cyan
    local rgb, BLACK, WHITE = Color3.fromRGB, Color3.new(0, 0, 0), Color3.new(1, 1, 1)
    return {
        TextColor = rgb(236, 240, 255),
        Background = rgb(14, 17, 30), Topbar = rgb(20, 24, 42), Shadow = rgb(8, 10, 18),
        NotificationBackground = rgb(16, 19, 34), NotificationActionsBackground = rgb(230, 234, 250),
        TabBackground = rgb(30, 36, 60), TabStroke = rgb(44, 52, 84), TabBackgroundSelected = a,
        TabTextColor = rgb(200, 208, 235), SelectedTabTextColor = rgb(12, 14, 24),
        ElementBackground = rgb(24, 29, 50), ElementBackgroundHover = rgb(30, 36, 62),
        SecondaryElementBackground = rgb(18, 22, 38),
        ElementStroke = rgb(40, 48, 78), SecondaryElementStroke = rgb(34, 40, 66),
        SliderBackground = a:Lerp(BLACK, 0.55), SliderProgress = a, SliderStroke = a:Lerp(WHITE, 0.2),
        ToggleBackground = rgb(20, 24, 42), ToggleEnabled = a, ToggleDisabled = rgb(70, 78, 104),
        ToggleEnabledStroke = a:Lerp(WHITE, 0.25), ToggleDisabledStroke = rgb(90, 98, 124),
        ToggleEnabledOuterStroke = a:Lerp(BLACK, 0.4), ToggleDisabledOuterStroke = rgb(44, 50, 74),
        DropdownSelected = rgb(34, 42, 72), DropdownUnselected = rgb(24, 29, 50),
        InputBackground = rgb(20, 24, 42), InputStroke = rgb(48, 56, 90), PlaceholderColor = rgb(130, 140, 170),
    }
end

local function notify(title, text, dur)
    ui(function()
        Rayfield:Notify({ Title = title, Content = tostring(text), Duration = dur or 4, Image = 4483362458 })
    end)
end
local function toast(text, kind)
    local title = (kind == "bad" and "Comet Hub · problem") or (kind == "warn" and "Comet Hub · check") or "Comet Hub"
    notify(title, text, kind == "bad" and 6 or 4)
end

local Window
do
    local opts = {
        Name = "Comet Hub · House Cloner",
        Icon = "paw-print",   -- "house" isn't in Rayfield's icon pack
        LoadingTitle = "Comet Hub",
        LoadingSubtitle = "house cloner · instant paste",
        Theme = cometTheme(CONFIG.accent),
        ToggleUIKeybind = "K",
        DisableRayfieldPrompts = true,
        DisableBuildWarnings = true,
        ConfigurationSaving = { Enabled = false },
        Discord = { Enabled = false, Invite = "", RememberJoins = true },
        KeySystem = false,
    }
    local ok, w = pcall(function() return Rayfield:CreateWindow(opts) end)
    if not ok or not w then
        local first = w
        opts.Icon = 0
        ok, w = pcall(function() return Rayfield:CreateWindow(opts) end)
        if not ok or not w then
            _G.HCV3.stage = "window failed: " .. tostring(w or first)
            pcall(function() Rayfield:Destroy() end)
            UI.banner("Comet Hub · House Cloner couldn't open its window.\nRun the script again. ("
                .. tostring(w or first):sub(1, 80) .. ")")
            return
        end
    end
    Window = w
    -- the download worked AND the window opened: keep this copy for bad-network days
    if UI.rfBody and hasFS then
        pcall(function()
            if not fs.isdir(CONFIG.folder) then fs.mkdir(CONFIG.folder) end
            fs.write(CONFIG.folder .. "/rayfield_cache.lua", UI.rfBody)
        end)
        UI.rfBody = nil
    end
end

-- Unknown Lucide names make CreateTab throw; fall back to a plain tab.
local function newTab(name, icon)
    local ok, tab = pcall(function() return Window:CreateTab(name, icon) end)
    if ok and tab then return tab end
    return Window:CreateTab(name, 4483362458)
end

local function rayfieldRoot()
    local root
    pcall(function() root = gethuiFn and gethuiFn():FindFirstChild("Rayfield") end)
    return root or game:GetService("CoreGui"):FindFirstChild("Rayfield")
end

-- ModifyTheme recolours backgrounds and text but not tab buttons, toggle knobs
-- or slider bars, so those get repainted by hand (same fix as the farm hub).
local function repaintRayfield(theme)
    local root = rayfieldRoot()
    local main = root and root:FindFirstChild("Main")
    if not (main and type(theme) == "table") then return end
    for _, t in ipairs(main.TabList:GetChildren()) do
        if t:IsA("Frame") and t:FindFirstChild("Title") and t.Name ~= "Template" then
            local sel = t.BackgroundTransparency < 0.5
            t.BackgroundColor3 = sel and theme.TabBackgroundSelected or theme.TabBackground
            t.Title.TextColor3 = sel and theme.SelectedTabTextColor or theme.TabTextColor
            if t:FindFirstChild("Image") then t.Image.ImageColor3 = t.Title.TextColor3 end
            if t:FindFirstChild("UIStroke") then t.UIStroke.Color = theme.TabStroke end
        end
    end
    for _, page in ipairs(main.Elements:GetChildren()) do
        for _, el in ipairs(page:GetChildren()) do
            local sw = el:FindFirstChild("Switch")
            local knob = sw and sw:FindFirstChild("Indicator")
            if knob then
                local on = knob.Position.X.Offset > -30
                sw.BackgroundColor3 = theme.ToggleBackground
                knob.BackgroundColor3 = on and theme.ToggleEnabled or theme.ToggleDisabled
                if knob:FindFirstChild("UIStroke") then
                    knob.UIStroke.Color = on and theme.ToggleEnabledStroke or theme.ToggleDisabledStroke
                end
                if sw:FindFirstChild("UIStroke") then
                    sw.UIStroke.Color = on and theme.ToggleEnabledOuterStroke or theme.ToggleDisabledOuterStroke
                end
            end
            local bar = el:FindFirstChild("Main")
            if bar and bar:FindFirstChild("Progress") then
                bar.BackgroundColor3 = theme.SliderBackground
                bar.Progress.BackgroundColor3 = theme.SliderProgress
                if bar:FindFirstChild("UIStroke") then bar.UIStroke.Color = theme.SliderStroke end
                if bar.Progress:FindFirstChild("UIStroke") then bar.Progress.UIStroke.Color = theme.SliderStroke end
            end
        end
    end
end

-- Callback wrapper: run on a fresh thread, log anything that throws.
local function go(fn)
    return function(...)
        local args = table.pack(...)
        task.spawn(function()
            local ok, e = pcall(fn, table.unpack(args, 1, args.n))
            if not ok then errl("%s", tostring(e)) end
        end)
    end
end

-- Rayfield hands dropdown callbacks a table (new builds) or a string (old ones).
local function firstOpt(o) if type(o) == "table" then return o[1] end return o end
local function allOpts(o) if type(o) == "table" then return o end return o and { o } or {} end

local function setOptions(dd, labels, placeholder)
    if #labels == 0 then labels = { placeholder or "(none)" } end
    ui(function() dd:Refresh(labels) end)
end

-- Paragraph setter that only writes when the text actually changed.
local function para(el, title)
    local last
    return function(content)
        content = tostring(content)
        if content == last then return end
        last = content
        ui(function() el:Set({ Title = title, Content = content }) end)
    end
end

--==============================================================================
-- JOBS + SHARED ACTIONS
--==============================================================================

-- One long job at a time (paste, batch, scan …), crash-proof, with a traceback
-- in the log when something throws.
local function job(name, fn)
    if State.running then
        toast("Busy with " .. tostring(State.busy) .. " — press Stop first", "bad")
        return false
    end
    State.running, State.stopFlag, State.busy = true, false, name
    State.progress = { done = 0, total = 0, phase = name }
    -- anything else in between (paste, fix, undo …) changes the house: the
    -- next sell press has to warn again
    if name ~= "sell" then State.sellArm = nil end
    task.spawn(function()
        local ok, e = xpcall(fn, debug.traceback)
        if not ok then
            errl("%s crashed: %s", name, tostring(e):sub(1, 500))
            toast(name .. " failed — see the log in Settings", "bad")
            Batch.boardAbort("stopped by an error — see the log")
        end
        State.running, State.busy = false, nil
        State.progress.phase = "idle"
    end)
    return true
end

-- Big spends and deletes ask twice.
local armedAt = {}
local function confirm(key, msg)
    local t = armedAt[key]
    if t and os.clock() - t < 6 then
        armedAt[key] = nil
        return true
    end
    armedAt[key] = os.clock()
    toast(msg .. " — press again within 6 s to confirm", "warn")
    return false
end

local Actions = {}
local Refresh = {}

function Actions.setLayout(layout, source)
    State.layout = layout
    State.layoutName = layout.name or "(unnamed)"
    State.dashPlan = nil
    local value, blocked = Layout.value(layout)
    okl("%s '%s' — %d pieces, $%s%s", source or "loaded", State.layoutName, #layout.items, commas(value),
        blocked > 0 and (" · " .. blocked .. " not buyable") or "")
    if source == "cloned" and CONFIG.saveClones and hasFS then
        Actions.download(true)
    end
    task.spawn(function() pcall(Refresh.contents) end)
end

-- Write the loaded layout out as a JSON file (never overwriting an older one)
-- and put the same JSON on the clipboard.
function Actions.download(quiet)
    local l = State.layout
    if not l then return toast("Clone or load a house first", "bad") end
    local json = Store.encode(l)
    if hasFS then
        local file = Store.freeName(l.name)
        local ok, e = Store.save(file, l)
        if not ok then return toast("Couldn't write the file: " .. tostring(e), "bad") end
        State.currentSave = file
        okl("saved %s.json (%s KB)", file, commas(#json / 1024))
        task.spawn(function() pcall(Refresh.saved) end)
        if not quiet then setclip(json) end
        toast(("Saved as JSON: workspace/%s/%s.json%s"):format(CONFIG.housesFolder, file,
            quiet and "" or " — also copied to your clipboard"), "good")
    else
        setclip(json)
        toast("No file API here — the JSON is on your clipboard instead", "warn")
    end
end

-- Anything a person might paste: JSON, a Lua table, a pastebin link or bare
-- code, a raw GitHub link. Auto-detected by Store.fromPastebin/decode.
local lastLoaded
function Actions.loadText(text, thenPaste)
    text = tostring(text or "")
    if text:gsub("%s", "") == "" then return false end
    if text == lastLoaded and not thenPaste then return true end
    local l, e = Store.fromPastebin(text)
    if not l then
        errl("load: %s", tostring(e))
        toast("Couldn't read that: " .. tostring(e), "bad")
        return false, e
    end
    lastLoaded = text
    Actions.setLayout(l, "loaded")
    toast(("Loaded %s · %d pieces"):format(l.name, #l.items), "good")
    if thenPaste then Actions.paste(nil, "instant") end
    return true
end

-- Read a house into a layout, then point the subscription back where you are.
function Actions.clone(owner, houseId, kind)
    local home = Game.homeOwner()
    local items, e = Game.read(houseId, owner)
    local hi = Game.interior()
    local sameHouse = hi and hi.player == owner and hi.house_id == houseId
    local tex = sameHouse and hi.textures or nil
    kind = kind or (sameHouse and hi.building_type) or nil
    if owner ~= home then Game.subscribe(home) end
    if not items then return nil, e end
    local name
    if owner == LP then
        local h = Game.house(houseId)
        name = (h and h.name and not tostring(h.name):find("^#+$")) and tostring(h.name)
            or ("My %s #%s"):format(Game.houseName(kind), tostring(houseId))
    else
        name = ("%s's %s"):format(owner.Name, Game.houseName(kind))
    end
    return Layout.fromRead(name, kind, items, tex)
end

function Actions.cloneHere()
    job("clone", function()
        local loc = Game.location()
        local hi = Game.interior()
        if not (loc and loc.destination_id == "housing" and hi and hi.player and hi.house_id) then
            return toast("Walk into a house first", "bad")
        end
        local l, e = Actions.clone(hi.player, hi.house_id, hi.building_type)
        if not l then
            errl("clone: %s", tostring(e))
            return toast("Clone failed: " .. tostring(e), "bad")
        end
        Actions.setLayout(l, "cloned")
        toast(("Cloned %s · %d pieces"):format(l.name, #l.items), "good")
    end)
end

-- mode = "instant" | "small" | "fix" (see PASTE_MODES).
function Actions.paste(houseId, mode)
    if not State.layout then return toast("Load or clone a layout first", "bad") end
    mode = PASTE_MODES[mode] and mode or nil
    job(mode == "fix" and "fix" or (mode == "small" and "small paste" or "paste"), function()
        local ok, msg, _, _, status = Paste.run(State.layout, houseId, mode, function(landed)
            toast("⚡ " .. landed, "good")
        end)
        if ok then okl("paste: %s", msg) else errl("paste: %s", tostring(msg)) end
        local waiting = status == "unverified" or status == "inflight"
        toast(tostring(msg), ok and "good" or (waiting and "warn" or "bad"))
        State.houseStats = nil
    end)
end

function Actions.previewToggle()
    if Preview.model or Preview.building then
        Preview.clear()
        return toast("Preview removed", "good")
    end
    if not State.layout then return toast("Load or clone a layout first", "bad") end
    local ok, msg = Preview.build(State.layout)
    toast(ok and ("Ghost preview: " .. msg) or tostring(msg), ok and "good" or "bad")
end

function Actions.undo(hard)
    job(hard and "hard undo" or "undo", function()
        local ok, msg = Txn.revert(hard)
        if ok then okl("undo: %s", msg) else errl("undo: %s", tostring(msg)) end
        toast(tostring(msg), ok and "good" or "bad")
        State.houseStats = nil
    end)
end

-- Sell every piece of furniture in one of your houses for Bucks, for a house
-- you're done with. Two presses: the first reads the house and says what will
-- go; the second (1-15 s later) goes ahead only if the house still holds
-- exactly the pieces that warning described. Pieces the house came with are
-- worth nothing and are simply removed; pieces that can never be bought back
-- (off-sale, gamepass, event, unknown) go to storage instead of being sold.
-- houseId nil = the house you're standing in (must be yours).
function Actions.sellAll(houseId)
    job("sell", function()
        State.progress = { done = 0, total = 0, phase = "finding the house" }
        -- a purchase still landing would add pieces after the read
        local okG, whyG = Game.buyGate()
        if not okG then return toast("Can't sell yet: " .. tostring(whyG), "bad") end
        local id
        if houseId then
            local ok, e = Game.enterOwnHouse(houseId)
            if not ok then return toast("Couldn't get into house #" .. tostring(houseId) .. ": " .. tostring(e), "bad") end
            id = houseId
        else
            -- house_interior follows the subscription, not your feet: ask the
            -- location whose house this is before trusting it
            if not Game.location() then
                return toast("Can't tell which house you're standing in — pick it in \"Your house\" and use the other sell button", "bad")
            end
            local who = Game.physicalOwner()
            if who and who ~= LP then
                return toast("You're in " .. who.Name .. "'s house — this only sells YOUR furniture", "bad")
            end
            if not Game.insideHouseOf(LP) then
                return toast("Walk into one of YOUR houses first — this only sells your own furniture", "bad")
            end
            local hi = Game.interior()
            id = hi and hi.house_id
        end
        if not id then return toast("No house loaded", "bad") end

        State.progress.phase = "reading the house"
        local items, e = Game.read(id, LP)
        if not items then return toast("Couldn't read the house: " .. tostring(e), "bad") end
        local pieces, sell, keep, paid, defaults = {}, {}, {}, 0, 0
        for _, it in ipairs(items) do
            if it.unique and not pieces[it.unique] then
                pieces[it.unique] = it
                if it.wasDefault then
                    defaults = defaults + 1
                    sell[#sell + 1] = it.unique   -- deleted in either mode
                else
                    local class, cost = Rules.classify(it.id)
                    if class == "buy" then
                        sell[#sell + 1] = it.unique
                        if not it.wasFree then paid = paid + (cost or 0) end
                    else
                        keep[#keep + 1] = it.unique
                    end
                end
            end
        end
        local n = #sell + #keep
        if n == 0 then
            State.sellArm = nil
            return toast("House #" .. tostring(id) .. " is already empty", "good")
        end

        local arm, now = State.sellArm, os.clock()
        local confirmed = arm and arm.houseId == id and arm.n == n and now - arm.at >= 1 and now - arm.at < 15
        if confirmed then
            for u in pairs(pieces) do
                if not arm.set[u] then confirmed = false break end
            end
        end
        if not confirmed then
            local set = {}
            for u in pairs(pieces) do set[u] = true end
            State.sellArm = { houseId = id, n = n, set = set, at = now }
            local h = Game.house(id)
            local what = h and ("\"%s\" (%s, #%s)"):format(tostring(h.name), Game.houseName(h.building_type), tostring(id))
                or ("house #" .. tostring(id))
            local parts = { ("%d sold for Bucks (you paid about $%s)"):format(#sell - defaults, commas(paid)) }
            if #keep > 0 then parts[#parts + 1] = ("%d rare one(s) go to your storage instead"):format(#keep) end
            if defaults > 0 then parts[#parts + 1] = ("%d came with the house and are just removed"):format(defaults) end
            return toast(("Sell everything in %s? %d piece(s): %s. Press the sell button again (wait 1 s, within 15 s) to do it. This can't be undone.")
                :format(what, n, table.concat(parts, ", ")), "warn")
        end
        State.sellArm = nil

        local money0 = Game.money()
        State.progress = { done = 0, total = n, phase = "selling furniture" }
        local sent = Game.remove(sell, "sell") + Game.remove(keep, "store")
        -- the server takes a moment: re-read until the house stops changing
        State.progress.phase = "checking what sold"
        local left, last, stableSince, t0 = nil, -1, os.clock(), os.clock()
        while os.clock() - t0 < 10 do
            task.wait(0.75)
            local r = Game.read(id, LP)
            if r then
                left = r
                if #r ~= last then last, stableSince = #r, os.clock() end
                if #r == 0 or os.clock() - stableSince >= 1 then break end
            end
        end
        local money1 = Game.money()
        local bucks = ""
        if money1 > money0 then
            bucks = (" · +$%s Bucks"):format(commas(money1 - money0))
        elseif money1 < money0 and money1 > 0 then
            bucks = (" · Bucks went DOWN by $%s meanwhile (something else was spending)"):format(commas(money0 - money1))
        end
        State.houseStats = nil
        if not left then
            local msg = ("Sent %d piece(s) from house #%s but couldn't re-read the house to check%s"):format(sent, tostring(id), bucks)
            errl("%s", msg)
            return toast(msg, "warn")
        end

        local still, kept = {}, {}
        for _, it in ipairs(left) do if it.unique then still[it.unique] = true end end
        for _, u in ipairs(keep) do kept[u] = true end
        local sold, stored, removed = 0, 0, 0
        for u, it in pairs(pieces) do
            if not still[u] then
                if it.wasDefault then removed = removed + 1
                elseif kept[u] then stored = stored + 1
                else sold = sold + 1 end
            end
        end
        -- the undo snapshot would try to buy what's gone back: drop it
        if Txn.houseId == id and sold + stored + removed > 0 then Txn.snapshot, Txn.state = nil, "IDLE" end
        local parts = { ("Sold %d piece(s)"):format(sold) }
        if stored > 0 then parts[#parts + 1] = ("%d rare one(s) put in storage"):format(stored) end
        if removed > 0 then parts[#parts + 1] = ("%d default piece(s) removed"):format(removed) end
        local msg = ("%s from house #%s%s"):format(table.concat(parts, ", "), tostring(id), bucks)
        if #left > 0 then msg = msg .. (" · %d still there (press sell again to retry)"):format(#left) end
        okl("%s", msg)
        toast(msg, #left > 0 and "warn" or "good")
    end)
end

function Actions.stop()
    if not State.running then return toast("Nothing is running", "good") end
    State.stopFlag = true
    info("stop requested")
    toast("Stopping after the current step…", "warn")
end

--==============================================================================
-- PASTE BOX  (a real multi-line box — Rayfield inputs are one line, which
-- mangles pasted JSON and Lua)
--==============================================================================

local PasteBox = {}
do
    local accent = ACCENTS[CONFIG.accent] or ACCENTS.Cyan
    local function new(class, props, parent)
        local o = Instance.new(class)
        for k, v in pairs(props) do o[k] = v end
        o.Parent = parent
        return o
    end
    local function round(o, r) new("UICorner", { CornerRadius = UDim.new(0, r) }, o) end

    local gui = new("ScreenGui", {
        Name = "CometPasteBox", ResetOnSpawn = false, Enabled = false, DisplayOrder = 100000,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    }, nil)
    if gethuiFn then gui.Parent = gethuiFn()
    elseif syn and syn.protect_gui then syn.protect_gui(gui) ; gui.Parent = game:GetService("CoreGui")
    else gui.Parent = game:GetService("CoreGui") end

    local frame = new("Frame", {
        Size = UDim2.new(0, 560, 0, 400), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        BackgroundColor3 = Color3.fromRGB(14, 17, 30), BorderSizePixel = 0, Active = true, Draggable = true,
    }, gui)
    local boxScale = new("UIScale", {}, frame)
    local function fitBox()
        local a = gui.AbsoluteSize
        if a.X > 0 then boxScale.Scale = math.clamp(math.min((a.Y - 16) / 400, (a.X - 16) / 560), 0.5, 1) end
    end
    round(frame, 12)
    local stroke = new("UIStroke", { Color = accent, Thickness = 1.5, Transparency = 0.2 }, frame)

    new("TextLabel", {
        Size = UDim2.new(1, -40, 0, 26), Position = UDim2.new(0, 18, 0, 12), BackgroundTransparency = 1,
        Text = "Paste a house", TextColor3 = Color3.fromRGB(236, 240, 255), Font = Enum.Font.GothamBold,
        TextSize = 17, TextXAlignment = Enum.TextXAlignment.Left,
    }, frame)
    new("TextLabel", {
        Size = UDim2.new(1, -40, 0, 18), Position = UDim2.new(0, 18, 0, 36), BackgroundTransparency = 1,
        Text = "JSON · Lua table · pastebin link or code · raw GitHub link — any cloner's format",
        TextColor3 = Color3.fromRGB(130, 140, 170), Font = Enum.Font.Gotham, TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, frame)

    local holder = new("ScrollingFrame", {
        Size = UDim2.new(1, -36, 1, -140), Position = UDim2.new(0, 18, 0, 64),
        BackgroundColor3 = Color3.fromRGB(20, 24, 42), BorderSizePixel = 0,
        ScrollBarThickness = 5, ScrollBarImageColor3 = accent,
        CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
    }, frame)
    round(holder, 8)
    new("UIStroke", { Color = Color3.fromRGB(48, 56, 90), Thickness = 1 }, holder)
    local box = new("TextBox", {
        Size = UDim2.new(1, -16, 0, 0), Position = UDim2.new(0, 8, 0, 6), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1, Text = "", PlaceholderText = "Click here and paste (Ctrl+V)…",
        TextColor3 = Color3.fromRGB(220, 226, 245), PlaceholderColor3 = Color3.fromRGB(110, 120, 150),
        Font = Enum.Font.Code, TextSize = 12, MultiLine = true, ClearTextOnFocus = false, TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
    }, holder)

    local status = new("TextLabel", {
        Size = UDim2.new(1, -36, 0, 18), Position = UDim2.new(0, 18, 1, -70), BackgroundTransparency = 1,
        Text = "", TextColor3 = Color3.fromRGB(130, 140, 170), Font = Enum.Font.Gotham, TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
    }, frame)

    local buttons = {}
    local function button(x, w, text, primary, cb)
        local b = new("TextButton", {
            Size = UDim2.new(0, w, 0, 34), Position = UDim2.new(0, x, 1, -46),
            BackgroundColor3 = primary and accent or Color3.fromRGB(30, 36, 60), BorderSizePixel = 0,
            Text = text, TextColor3 = primary and Color3.fromRGB(12, 14, 24) or Color3.fromRGB(220, 226, 245),
            Font = Enum.Font.GothamBold, TextSize = 13, AutoButtonColor = true,
        }, frame)
        round(b, 8)
        b.MouseButton1Click:Connect(cb)
        if primary then buttons[#buttons + 1] = b end
        return b
    end

    -- Text is read here, on the click's own (clean) thread; the load runs on a worker.
    local function load(thenPaste)
        local text = box.Text
        if text:gsub("%s", "") == "" then
            status.Text = "Nothing pasted yet."
            return
        end
        status.Text = "Reading " .. commas(#text) .. " characters…"
        task.spawn(function()
            local ok, e = Actions.loadText(text, thenPaste)
            ui(function()
                status.Text = ok and ("Loaded: " .. tostring(State.layoutName) .. " · " ..
                    #State.layout.items .. " pieces" .. (thenPaste and " — pasting…" or ""))
                    or ("Couldn't read it: " .. tostring(e))
                if ok then gui.Enabled = false end
            end)
        end)
    end

    button(18, 110, "Load", true, function() load(false) end)
    button(136, 170, "⚡ Load + PASTE", true, function() load(true) end)
    button(314, 90, "Clear", false, function() box.Text = "" ; status.Text = "" end)
    button(560 - 18 - 90, 90, "Close", false, function() gui.Enabled = false end)

    -- Opens with the cursor already in the box, so Ctrl+V is all it takes.
    function PasteBox.open()
        ui(function()
            fitBox()
            gui.Enabled = true
            pcall(function() box:CaptureFocus() end)
        end)
    end
    function PasteBox.recolor(c)
        ui(function()
            stroke.Color = c
            holder.ScrollBarImageColor3 = c
            for _, b in ipairs(buttons) do b.BackgroundColor3 = c end
        end)
    end
    UI.box = gui
end

--==============================================================================
-- HOW-TO WINDOW  (Saved tab: "how do I add a house file?")
--==============================================================================

-- Where house files go on this PC. Volt's folder is known for sure; any other
-- executor keeps the same path under its own workspace folder.
local HowTo = {}
do
    -- Full paths only for executors checked on a real install; everyone else
    -- gets the folder names to look for.
    local KNOWN = { volt = "%LOCALAPPDATA%\\Volt\\workspace\\" }
    local exe = ""
    pcall(function() exe = tostring((identifyexecutor and identifyexecutor()) or ""):lower() end)
    local rel = (CONFIG.housesFolder:gsub("/", "\\"))
    local root
    for key, path in pairs(KNOWN) do if exe:find(key, 1, true) then root = path end end
    local phone = UIS.TouchEnabled and not UIS.KeyboardEnabled
    HowTo.exact = root ~= nil
    HowTo.path = root and (root .. rel) or ("workspace\\" .. rel)
    HowTo.canCopy = (setclipboard or (syn and syn.write_clipboard)) ~= nil
    HowTo.where = HowTo.exact and "paste the path in the Windows Explorer address bar to open it"
        or (phone and "open your file manager → your executor's folder → workspace → HouseCloner → houses"
            or "open your executor's own folder (where its .exe is) → workspace → HouseCloner → houses")
    -- what to say after a copy button
    function HowTo.copied()
        if not HowTo.canCopy then return "This executor can't copy — type the path shown instead." end
        return HowTo.exact and "Path copied — paste it in the Windows Explorer address bar."
            or "Copied workspace\\HouseCloner\\houses — it's inside your executor's folder."
    end

    local accent = ACCENTS[CONFIG.accent] or ACCENTS.Cyan
    local INK, MUTED, PANEL = Color3.fromRGB(236, 240, 255), Color3.fromRGB(150, 160, 190), Color3.fromRGB(20, 24, 42)
    local function new(class, props, parent)
        local o = Instance.new(class)
        for k, v in pairs(props) do o[k] = v end
        o.Parent = parent
        return o
    end
    local function round(o, r) new("UICorner", { CornerRadius = UDim.new(0, r) }, o) end

    local gui = new("ScreenGui", {
        Name = "CometHowTo", ResetOnSpawn = false, Enabled = false, DisplayOrder = 100001,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    }, nil)
    if gethuiFn then gui.Parent = gethuiFn()
    elseif syn and syn.protect_gui then syn.protect_gui(gui) ; gui.Parent = game:GetService("CoreGui")
    else gui.Parent = game:GetService("CoreGui") end

    local frame = new("Frame", {
        Size = UDim2.new(0, 540, 0, 430), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        BackgroundColor3 = Color3.fromRGB(14, 17, 30), BorderSizePixel = 0, Active = true, Draggable = true,
    }, gui)
    local scale = new("UIScale", {}, frame)
    local function fit()
        local a = gui.AbsoluteSize
        if a.X > 0 then scale.Scale = math.clamp(math.min((a.Y - 16) / 430, (a.X - 16) / 540), 0.5, 1) end
    end
    round(frame, 12)
    local stroke = new("UIStroke", { Color = accent, Thickness = 1.5, Transparency = 0.2 }, frame)

    new("TextLabel", {
        Size = UDim2.new(1, -36, 0, 26), Position = UDim2.new(0, 18, 0, 12), BackgroundTransparency = 1,
        Text = "Add a house file", TextColor3 = INK, Font = Enum.Font.GothamBold,
        TextSize = 17, TextXAlignment = Enum.TextXAlignment.Left,
    }, frame)
    new("TextLabel", {
        Size = UDim2.new(1, -36, 0, 18), Position = UDim2.new(0, 18, 0, 38), BackgroundTransparency = 1,
        Text = "Ragesploit, ZekeHub and NyxHouse saves already show up — no copying needed for those.",
        TextColor3 = MUTED, Font = Enum.Font.Gotham, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, frame)

    local function step(n, y, text)
        local dot = new("TextLabel", {
            Size = UDim2.new(0, 26, 0, 26), Position = UDim2.new(0, 18, 0, y), BackgroundColor3 = accent,
            Text = tostring(n), TextColor3 = Color3.fromRGB(12, 14, 24), Font = Enum.Font.GothamBold, TextSize = 14,
        }, frame)
        round(dot, 13)
        new("TextLabel", {
            Size = UDim2.new(1, -72, 0, 40), Position = UDim2.new(0, 54, 0, y - 2), BackgroundTransparency = 1,
            Text = text, TextColor3 = INK, Font = Enum.Font.Gotham, TextSize = 14, TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
        }, frame)
        return dot
    end
    local dots = {
        step(1, 72, "Get a house file: a .json from a friend, a Discord server or another cloner."),
        step(2, 122, "Put it in this folder (" .. HowTo.where .. "):"),
    }
    local pathBox = new("TextBox", {
        Size = UDim2.new(1, -72, 0, 32), Position = UDim2.new(0, 54, 0, 166), BackgroundColor3 = PANEL,
        Text = HowTo.path, TextColor3 = INK, Font = Enum.Font.Code, TextSize = 13, ClearTextOnFocus = false,
        TextEditable = false, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
    }, frame)
    round(pathBox, 6)
    new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, pathBox)
    dots[#dots + 1] = step(3, 216, "Press \"I added it — refresh\" below (the list also refreshes by itself every few seconds).")
    dots[#dots + 1] = step(4, 266, "On the Saved tab, tick the house in \"Saved houses\" and press \"Load the ticked file(s)\". Then paste it from the Paste tab.")
    new("TextLabel", {
        Size = UDim2.new(1, -36, 0, 34), Position = UDim2.new(0, 18, 0, 318), BackgroundTransparency = 1,
        Text = "Got a pastebin link instead? Paste tab → put the link in \"…or put a pastebin link or code here\".",
        TextColor3 = MUTED, Font = Enum.Font.Gotham, TextSize = 12, TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
    }, frame)

    local status = new("TextLabel", {
        Size = UDim2.new(1, -36, 0, 16), Position = UDim2.new(0, 18, 1, -66), BackgroundTransparency = 1,
        Text = "", TextColor3 = MUTED, Font = Enum.Font.Gotham, TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
    }, frame)

    local primary = {}
    local function button(x, w, text, isPrimary, cb)
        local b = new("TextButton", {
            Size = UDim2.new(0, w, 0, 34), Position = UDim2.new(0, x, 1, -46),
            BackgroundColor3 = isPrimary and accent or Color3.fromRGB(30, 36, 60), BorderSizePixel = 0,
            Text = text, TextColor3 = isPrimary and Color3.fromRGB(12, 14, 24) or INK,
            Font = Enum.Font.GothamBold, TextSize = 13, AutoButtonColor = true,
        }, frame)
        round(b, 8)
        b.MouseButton1Click:Connect(cb)
        if isPrimary then primary[#primary + 1] = b end
        return b
    end
    button(18, 150, "Copy folder path", true, function()
        setclip(HowTo.path)
        status.Text = HowTo.copied()
    end)
    button(176, 200, "I added it — refresh", true, function()
        status.Text = "Looking for house files…"
        task.spawn(function()
            local ok, n = pcall(Refresh.saved)
            ui(function()
                status.Text = ok and ("Found " .. tostring(n) .. " house file(s). Pick yours on the Saved tab.")
                    or "Couldn't read the folder."
            end)
        end)
    end)
    button(540 - 18 - 90, 90, "Close", false, function() gui.Enabled = false end)

    function HowTo.open()
        if not fs.canList then
            return toast("This executor can't read house files — use a pastebin link on the Paste tab", "bad")
        end
        ui(function() fit() ; gui.Enabled = true end)
    end
    function HowTo.recolor(c)
        ui(function()
            stroke.Color = c
            for _, b in ipairs(primary) do b.BackgroundColor3 = c end
            for _, d in ipairs(dots) do d.BackgroundColor3 = c end
        end)
    end
    UI.howto = gui
end

--==============================================================================
-- TABS
--==============================================================================

_G.HCV3.stage = "tabs"
local Set = {}

-------------------------------------------------------------------------------- PASTE
do
    local T = newTab("Paste", "clipboard-paste")
    Set.now = para(T:CreateParagraph({ Title = "Now", Content = "Loading…" }), "Now")
    Set.layout = para(T:CreateParagraph({ Title = "Layout", Content = "None — paste one below or clone a house" }), "Layout")
    Set.plan = para(T:CreateParagraph({ Title = "What a paste will do", Content = "—" }), "What a paste will do")

    T:CreateSection("Step 1 · Load a house")
    T:CreateButton({ Name = "Open the paste box  (JSON · Lua · pastebin)", Callback = function() PasteBox.open() end })
    T:CreateInput({
        Name = "…or put a pastebin link or code here", CurrentValue = "",
        PlaceholderText = "pastebin.com/… or 4KF2Q9Z1", RemoveTextAfterFocusLost = false,
        Callback = go(function(t) Actions.loadText(t) end),
    })

    T:CreateSection("Step 2 · Paste it into the house you're in")
    T:CreateButton({ Name = "⚡  INSTANT PASTE  (everything at once)", Callback = go(function() Actions.paste(nil, "instant") end) })
    T:CreateButton({ Name = "🐢  SMALL PASTE  (small batches — use it if instant fails or lags)",
        Callback = go(function() Actions.paste(nil, "small") end) })
    T:CreateButton({ Name = "Fix — place only what's missing", Callback = go(function() Actions.paste(nil, "fix") end) })
    T:CreateButton({ Name = "Ghost preview on / off", Callback = go(Actions.previewToggle) })
    T:CreateButton({ Name = "Undo the last paste", Callback = go(function() Actions.undo(false) end) })
    T:CreateButton({ Name = "Hard undo (also store what the paste added)", Callback = go(function()
        if confirm("hardundo", "Hard undo stores every piece the paste added") then Actions.undo(true) end
    end) })
    T:CreateButton({ Name = "Stop", Callback = go(Actions.stop) })

    T:CreateSection("Paste into another of your houses")
    UI.dTarget = T:CreateDropdown({
        Name = "Your house", Options = { "(loading…)" }, CurrentOption = {}, MultipleOptions = false,
        Callback = function(o) UI.sel.target = UI.maps.target and UI.maps.target[firstOpt(o) or ""] end,
    })
    T:CreateButton({ Name = "⚡  Switch to it, walk in, INSTANT paste", Callback = go(function()
        if not UI.sel.target then return toast("Pick a house first", "bad") end
        Actions.paste(UI.sel.target, "instant")
    end) })
    T:CreateButton({ Name = "🐢  Switch to it, walk in, SMALL paste", Callback = go(function()
        if not UI.sel.target then return toast("Pick a house first", "bad") end
        Actions.paste(UI.sel.target, "small")
    end) })

    T:CreateSection("Extra · edit the loaded layout")
    T:CreateInput({
        Name = "Layout name", CurrentValue = "", PlaceholderText = "used for saves and {layout} in names",
        RemoveTextAfterFocusLost = false,
        Callback = function(t)
            t = tostring(t):gsub("^%s+", ""):gsub("%s+$", "")
            if State.layout and t ~= "" then State.layout.name, State.layoutName = t, t end
        end,
    })
    Set.contents = para(T:CreateParagraph({ Title = "Pieces", Content = "—" }), "Pieces")
    UI.dContents = T:CreateDropdown({
        Name = "Pieces in the layout (priciest first)", Options = { "(no layout)" }, CurrentOption = {},
        MultipleOptions = true, Callback = function(o) UI.sel.contents = allOpts(o) end,
    })
    T:CreateButton({ Name = "Remove the ticked pieces", Callback = go(function()
        if not State.layout then return toast("No layout loaded", "bad") end
        local drop, n = {}, 0
        for _, label in ipairs(UI.sel.contents or {}) do
            local id = UI.maps.contents and UI.maps.contents[label]
            if id then drop[id] = true ; n = n + 1 end
        end
        if n == 0 then return toast("Tick some pieces first", "bad") end
        local l, removed = Layout.without(State.layout, drop)
        UI.sel.contents = {}
        Actions.setLayout(l, "edited")
        toast(("Removed %d piece(s) — save it in Saved to keep the edit"):format(removed), "good")
    end) })
    T:CreateButton({ Name = "Remove everything I can't get", Callback = go(function()
        if not State.layout then return toast("No layout loaded", "bad") end
        local l, removed = Layout.obtainable(State.layout, Game.storage())
        Actions.setLayout(l, "edited")
        toast(removed > 0 and ("Removed " .. removed .. " unobtainable piece(s)") or "Everything in it can be had", "good")
    end) })
end

-------------------------------------------------------------------------------- CLONE
do
    local T = newTab("Clone", "copy")
    Set.where = para(T:CreateParagraph({ Title = "Where you are", Content = "—" }), "Where you are")
    T:CreateButton({ Name = "Clone the house I'm standing in", Callback = go(Actions.cloneHere) })

    T:CreateSection("Anyone in this server — no need to walk there")
    UI.dPlayer = T:CreateDropdown({
        Name = "Player", Options = { "(loading…)" }, CurrentOption = {}, MultipleOptions = false,
        Callback = function(o) UI.sel.player = UI.maps.player and UI.maps.player[firstOpt(o) or ""] end,
    })
    T:CreateButton({ Name = "Refresh players", Callback = go(function()
        toast(Refresh.players() .. " house(s) in this server", "good")
    end) })
    T:CreateButton({ Name = "Clone their house", Callback = go(function()
        local e = UI.sel.player
        if not e then return toast("Pick a player first", "bad") end
        job("clone", function()
            local l, err = Actions.clone(e.player, e.house_id, e.building_type)
            if not l then errl("clone: %s", tostring(err)) return toast("Clone failed: " .. tostring(err), "bad") end
            Actions.setLayout(l, "cloned")
            toast(("Cloned %s · %d pieces"):format(l.name, #l.items), "good")
        end)
    end) })
    T:CreateButton({ Name = "Visit their house  (unlocked doors, or friends)", Callback = go(function()
        local e = UI.sel.player
        if not e then return toast("Pick a player first", "bad") end
        job("visit", function()
            local ok, err = Game.enterHouse(e.player)
            toast(ok and ("You're in " .. tostring(e.player_name) .. "'s house")
                or ("Couldn't get in (door locked?): " .. tostring(err)), ok and "good" or "bad")
        end)
    end) })

    T:CreateSection("Your houses")
    UI.dMine = T:CreateDropdown({
        Name = "Your house", Options = { "(loading…)" }, CurrentOption = {}, MultipleOptions = false,
        Callback = function(o) UI.sel.mine = UI.maps.mine and UI.maps.mine[firstOpt(o) or ""] end,
    })
    T:CreateButton({ Name = "Refresh my houses", Callback = go(function()
        local n = Refresh.mine()
        toast(n .. " house(s)", "good")
    end) })
    T:CreateButton({ Name = "Clone it", Callback = go(function()
        local id = UI.sel.mine
        if not id then return toast("Pick one of your houses first", "bad") end
        job("clone", function()
            local h = Game.house(id)
            local l, err = Actions.clone(LP, id, h and h.building_type)
            if not l then errl("clone: %s", tostring(err)) return toast("Clone failed: " .. tostring(err), "bad") end
            Actions.setLayout(l, "cloned")
            toast(("Cloned %s · %d pieces"):format(l.name, #l.items), "good")
        end)
    end) })
    T:CreateButton({ Name = "Make it active and walk in", Callback = go(function()
        local id = UI.sel.mine
        if not id then return toast("Pick one of your houses first", "bad") end
        job("enter", function()
            local ok, err = Game.enterOwnHouse(id)
            toast(ok and ("In house #" .. tostring(id)) or ("Couldn't: " .. tostring(err)), ok and "good" or "bad")
        end)
    end) })

    T:CreateSection("Sell furniture for Bucks (a house you don't want)")
    T:CreateButton({ Name = "💰  Sell ALL furniture in the house I'm in", Callback = go(function()
        Actions.sellAll(nil)
    end) })
    T:CreateButton({ Name = "💰  Sell ALL furniture in the picked house above", Callback = go(function()
        if not UI.sel.mine then return toast("Pick one of your houses in \"Your house\" first", "bad") end
        Actions.sellAll(UI.sel.mine)
    end) })

    T:CreateSection("Download as JSON")
    T:CreateButton({ Name = "⬇  Download the loaded house as JSON", Callback = go(function() Actions.download(false) end) })
    T:CreateToggle({ Name = "Save every clone as a JSON file automatically", CurrentValue = CONFIG.saveClones,
        Callback = function(v) setCfg("saveClones", v) end })
end

-------------------------------------------------------------------------------- AUTO
do
    local T = newTab("Auto", "repeat")
    Set.estimate = para(T:CreateParagraph({ Title = "Estimate", Content = "Load a layout first" }), "Estimate")
    Set.board = para(T:CreateParagraph({ Title = "Houses", Content = "Press Check or Start to fill this in" }), "Houses")
    Set.batch = para(T:CreateParagraph({ Title = "Progress", Content = "Nothing yet" }), "Progress")

    T:CreateSection("Batch — buy → check → walk in → paste → paint → rename, house after house")
    UI.dKind = T:CreateDropdown({
        Name = "House type", Options = { "(loading…)" }, CurrentOption = {}, MultipleOptions = false,
        Callback = function(o)
            local kind = UI.maps.kind and UI.maps.kind[firstOpt(o) or ""]
            if kind then setCfg("batchKind", kind) end
        end,
    })
    T:CreateSlider({ Name = "How many houses", Range = { 1, 50 }, Increment = 1, Suffix = "",
        CurrentValue = CONFIG.batchCount, Callback = function(v) setCfg("batchCount", math.floor(v)) end })
    T:CreateToggle({ Name = "Also fill houses I already own of this type", CurrentValue = CONFIG.batchUseOwned,
        Callback = function(v) setCfg("batchUseOwned", v) end })
    T:CreateToggle({ Name = "Check each house first — skip it if the layout is already there", CurrentValue = CONFIG.batchSkipDone,
        Callback = function(v) setCfg("batchSkipDone", v) end })
    T:CreateToggle({ Name = "Paste each house INSTANTLY (off = small batches, for laggy servers)", CurrentValue = CONFIG.instant ~= false,
        Callback = function(v) setCfg("instant", v) end })
    T:CreateToggle({ Name = "List the last house for trade when done", CurrentValue = CONFIG.listLastHouse,
        Callback = function(v) setCfg("listLastHouse", v) end })

    T:CreateSection("House colour")
    T:CreateDropdown({
        Name = "Paint the houses", Options = HOUSE_COLOR_ORDER,
        CurrentOption = { HOUSE_COLORS[CONFIG.houseColor] and CONFIG.houseColor or "Default" }, MultipleOptions = false,
        Callback = function(o)
            local c = firstOpt(o)
            if c and (c == "Default" or HOUSE_COLORS[c]) then setCfg("houseColor", c) end
        end,
    })
    T:CreateButton({ Name = "Paint all my houses of this type now", Callback = go(function()
        if not HOUSE_COLORS[CONFIG.houseColor] then return toast("Pick a colour first (not Default)", "bad") end
        if not confirm("paintall", ("Repaint every %s %s"):format(Game.houseName(CONFIG.batchKind), CONFIG.houseColor)) then
            return
        end
        job("paint", function()
            local ok, m = Batch.paintAll()
            toast(m, ok and "good" or "bad")
        end)
    end) })

    T:CreateSection("Names")
    T:CreateToggle({ Name = "Rename each house", CurrentValue = CONFIG.renameOn,
        Callback = function(v) setCfg("renameOn", v) end })
    T:CreateInput({ Name = "Name template  ({layout} {n} {type})", CurrentValue = CONFIG.renameTemplate,
        PlaceholderText = "{layout} #{n}", RemoveTextAfterFocusLost = false,
        Callback = function(t) setCfg("renameTemplate", tostring(t)) end })
    T:CreateSlider({ Name = "Seconds between renames", Range = { 12, 40 }, Increment = 1, Suffix = " s",
        CurrentValue = CONFIG.renameGap, Callback = function(v) setCfg("renameGap", v) end })
    T:CreateButton({ Name = "Re-check names now", Callback = go(function()
        local bad = Renamer.wrong()
        if #bad == 0 then return toast("Every renamed house reads correctly", "good") end
        for _, id in ipairs(bad) do table.insert(Renamer.queue, id) end
        Renamer.kick()
        toast(#bad .. " masked name(s) queued again", "warn")
    end) })

    T:CreateSection("Run")
    T:CreateButton({ Name = "🔍  Check my houses (reads them, pastes nothing)", Callback = go(function()
        if not State.layout then return toast("Load or clone a layout first", "bad") end
        job("check", function()
            local ok, m = Batch.check()
            toast(m, ok and "good" or "bad")
        end)
    end) })
    T:CreateButton({ Name = "▶  START / RESUME batch", Callback = go(function()
        if not State.layout then return toast("Load or clone a layout first", "bad") end
        local est = State.dashEstimate
        if not confirm("batch", est and ("The batch may spend up to $%s"):format(commas(est.total)) or "Start the batch") then
            return
        end
        job("batch", function()
            local ok, m = Batch.run()
            toast("Batch: " .. tostring(m), ok and "good" or "bad")
        end)
    end) })
    T:CreateButton({ Name = "Stop after the current step", Callback = go(Actions.stop) })
    T:CreateButton({ Name = "Buy the houses only (no paste)", Callback = go(function()
        local price = (type(HouseDB[CONFIG.batchKind]) == "table" and HouseDB[CONFIG.batchKind].cost) or 0
        if not confirm("buyhouses", ("Buy %d %s for $%s"):format(CONFIG.batchCount, Game.houseName(CONFIG.batchKind),
            commas(price * CONFIG.batchCount))) then return end
        job("buy houses", function()
            local ok, m = Batch.buyOnly()
            toast(m, ok and "good" or "bad")
        end)
    end) })
    T:CreateButton({ Name = "Forget batch progress", Callback = go(function()
        if not confirm("resetbatch", "The next Start will treat every house as new") then return end
        Batch.reset()
        bline("progress cleared")
        toast("Batch progress cleared", "good")
    end) })
end

-------------------------------------------------------------------------------- SCANNER
do
    local T = newTab("Scanner", "search")
    Set.scan = para(T:CreateParagraph({ Title = "Scanner", Content = "Not scanned yet" }), "Scanner")
    T:CreateSection("Find the best houses in this server")
    UI.dScanTypes = T:CreateDropdown({
        Name = "House types", Options = { "All" }, CurrentOption = {}, MultipleOptions = true,
        Callback = function(o)
            Scanner.types = {}
            for _, v in ipairs(allOpts(o)) do Scanner.types[v] = true end
        end,
    })
    T:CreateInput({ Name = "Only houses worth at least ($)", CurrentValue = CONFIG.scanMinValue > 0 and tostring(CONFIG.scanMinValue) or "",
        PlaceholderText = "0", RemoveTextAfterFocusLost = false,
        Callback = function(t)
            local n = tonumber((tostring(t):gsub("[,%s%$]", "")))
            if n then setCfg("scanMinValue", math.max(0, math.floor(n))) end
        end })
    T:CreateToggle({ Name = "Save every house found to a file", CurrentValue = CONFIG.scanAutoSave,
        Callback = function(v) setCfg("scanAutoSave", v) end })
    T:CreateSlider({ Name = "Pause between houses", Range = { 0, 2 }, Increment = 0.1, Suffix = " s",
        CurrentValue = CONFIG.scanDelay, Callback = function(v) setCfg("scanDelay", v) end })
    T:CreateButton({ Name = "Scan", Callback = go(function()
        job("scan", function()
            Refresh.scanTypes()
            local n = Scanner.run()
            UI.maps.scan = {}
            local labels = {}
            for _, s in ipairs(State.scanned) do
                labels[#labels + 1] = s.label
                UI.maps.scan[s.label] = s
            end
            setOptions(UI.dScan, labels, "(nothing matched)")
            okl("scan: %d house(s)", n)
            toast(("Scan done · %d house(s)"):format(n), "good")
        end)
    end) })
    T:CreateButton({ Name = "Stop", Callback = go(Actions.stop) })

    T:CreateSection("Found")
    UI.dScan = T:CreateDropdown({
        Name = "Found houses (best first)", Options = { "(scan first)" }, CurrentOption = {}, MultipleOptions = false,
        Callback = function(o) State.pickedScan = UI.maps.scan and UI.maps.scan[firstOpt(o) or ""] end,
    })
    T:CreateButton({ Name = "Load the picked house", Callback = go(function()
        local s = State.pickedScan
        if not s then return toast("Pick a found house first", "bad") end
        Actions.setLayout(s.layout, "cloned")
        toast(("Loaded %s · %d pieces"):format(s.layout.name, #s.layout.items), "good")
    end) })
    T:CreateButton({ Name = "Save the picked house to a file", Callback = go(function()
        local s = State.pickedScan
        if not s then return toast("Pick a found house first", "bad") end
        local ok, e = Store.save(s.layout.name, s.layout)
        toast(ok and ("Saved " .. s.layout.name) or ("Save failed: " .. tostring(e)), ok and "good" or "bad")
    end) })
    T:CreateButton({ Name = "Visit the picked house  (unlocked doors, or friends)", Callback = go(function()
        local s = State.pickedScan
        if not s then return toast("Pick a found house first", "bad") end
        job("visit", function()
            local ok, e = Game.enterHouse(s.owner)
            toast(ok and "You're in" or ("Couldn't get in: " .. tostring(e)), ok and "good" or "bad")
        end)
    end) })
    T:CreateButton({ Name = "Hop to another server", Callback = go(function()
        if not confirm("hop", "Leave this server") then return end
        local ok, msg = Game.hop()
        toast(msg, ok and "good" or "bad")
    end) })
end

-------------------------------------------------------------------------------- SAVED
do
    local T = newTab("Saved", "folder")
    T:CreateSection("How do I add a house file?")
    Set.saved = para(T:CreateParagraph({ Title = "3 steps", Content = fs.canList and
        ("1. Put the .json file in:\n" .. HowTo.path .. "\n   (" .. HowTo.where .. ")" ..
         "\n2. Press \"Refresh my list\" (it also refreshes by itself)." ..
         "\n3. Tick it in \"Saved houses\" below and press \"Load the ticked file(s)\"." ..
         "\nRagesploit, ZekeHub and NyxHouse saves show up on their own.")
        or (hasFS and "This executor can save houses but can't list files, so saved files won't show here. Use a pastebin link on the Paste tab to load one."
            or "This executor has no file API, so it can't read house files. Use a pastebin link on the Paste tab instead.") }), "3 steps")
    if fs.canList then
        T:CreateButton({ Name = "📖  Show me how (step by step)", Callback = function() HowTo.open() end })
        T:CreateButton({ Name = "Copy the folder path", Callback = function()
            setclip(HowTo.path)
            toast(HowTo.copied(), HowTo.canCopy and "good" or "warn")
        end })
    end

    T:CreateSection("Save")
    UI.saveName = ""
    T:CreateInput({ Name = "File name", CurrentValue = "", PlaceholderText = "empty = the layout's name",
        RemoveTextAfterFocusLost = false, Callback = function(t) UI.saveName = tostring(t) end })
    T:CreateButton({ Name = "Save the loaded layout", Callback = go(function()
        if not State.layout then return toast("Nothing loaded to save", "bad") end
        local name = (UI.saveName or "") ~= "" and UI.saveName or State.layoutName
        local ok, e = Store.save(name, State.layout)
        if not ok then return toast("Save failed: " .. tostring(e), "bad") end
        State.currentSave = name
        okl("saved '%s'", name)
        toast("Saved " .. name .. ".json", "good")
        Refresh.saved()
    end) })

    T:CreateSection("Load")
    UI.dSaved = T:CreateDropdown({
        Name = "Saved houses (tick several to merge)", Options = { "(loading…)" }, CurrentOption = {},
        MultipleOptions = true, Callback = function(o) UI.sel.saved = allOpts(o) end,
    })
    T:CreateButton({ Name = "Refresh my list", Callback = go(function() toast(Refresh.saved() .. " house file(s) found", "good") end) })
    T:CreateButton({ Name = "Load the ticked file(s)", Callback = go(function()
        local labels = UI.sel.saved or {}
        if #labels == 0 then return toast("Tick at least one", "bad") end
        local merged, kind, tex, loaded, names, lastErr = {}, nil, nil, 0, {}, nil
        for _, label in ipairs(labels) do
            local entry = UI.maps.saved and UI.maps.saved[label]
            local l, e = Store.load(entry or label)
            if l then
                loaded = loaded + 1
                names[#names + 1] = l.name
                kind = kind or l.buildingType
                tex = tex or l.textures
                for _, it in ipairs(l.items) do merged[#merged + 1] = it end
            else
                lastErr = e
                errl("load %s: %s", label, tostring(e))
            end
        end
        if loaded == 0 then return toast("Couldn't load it: " .. tostring(lastErr), "bad") end
        Actions.setLayout(Layout.new(table.concat(names, " + "), kind, merged, tex), "loaded")
        State.currentSave = State.layoutName
        toast(("Loaded %s · %d pieces"):format(State.layoutName, #merged), "good")
    end) })
    T:CreateButton({ Name = "Delete the ticked file(s)  (House Cloner saves only)", Callback = go(function()
        local labels = UI.sel.saved or {}
        local own = {}
        for _, label in ipairs(labels) do
            local entry = UI.maps.saved and UI.maps.saved[label]
            if entry and entry.own then own[#own + 1] = entry end
        end
        if #own == 0 then return toast("Tick one of House Cloner's own saves (other cloners' files are read-only)", "bad") end
        if not confirm("delsaves", ("Delete %d file(s)"):format(#own)) then return end
        for _, entry in ipairs(own) do Store.delete(entry) end
        Refresh.saved()
        toast("Deleted " .. #own .. " file(s)", "good")
    end) })
    T:CreateButton({ Name = "Copy the loaded layout as JSON", Callback = function()
        if not State.layout then return toast("Nothing loaded", "bad") end
        setclip(Store.encode(State.layout))
        toast("JSON copied", "good")
    end })

    T:CreateSection("Pastebin")
    UI.pbKey, UI.pbTitle = "", ""
    T:CreateInput({ Name = "Your pastebin API dev key", CurrentValue = "", PlaceholderText = "api_dev_key",
        RemoveTextAfterFocusLost = false, Callback = function(t) UI.pbKey = tostring(t) end })
    T:CreateInput({ Name = "Paste title", CurrentValue = "", PlaceholderText = "My house",
        RemoveTextAfterFocusLost = false, Callback = function(t) UI.pbTitle = tostring(t) end })
    T:CreateButton({ Name = "Upload the loaded layout", Callback = go(function()
        if not State.layout then return toast("Nothing loaded", "bad") end
        local url, e = Store.toPastebin(UI.pbKey, UI.pbTitle, State.layout)
        if not url then errl("upload: %s", tostring(e)) return toast("Upload failed: " .. tostring(e), "bad") end
        setclip(url)
        okl("uploaded: %s", url)
        toast("Uploaded — link copied", "good")
    end) })

    T:CreateSection("Code library")
    UI.codeText, UI.codeName = "", ""
    T:CreateInput({ Name = "Pastebin code or link", CurrentValue = "", PlaceholderText = "4KF2Q9Z1",
        RemoveTextAfterFocusLost = false, Callback = function(t) UI.codeText = tostring(t) end })
    T:CreateInput({ Name = "Save it as", CurrentValue = "", PlaceholderText = "my favourite build",
        RemoveTextAfterFocusLost = false, Callback = function(t) UI.codeName = tostring(t) end })
    T:CreateButton({ Name = "Save code to library", Callback = go(function()
        if UI.codeName == "" or UI.codeText == "" then return toast("Need a name and a code", "bad") end
        local ok, code = Store.saveCode(UI.codeName, UI.codeText)
        if not ok then return toast("Save failed: " .. tostring(code), "bad") end
        Refresh.codes()
        toast("Saved code '" .. UI.codeName .. "'", "good")
    end) })
    UI.dCodes = T:CreateDropdown({
        Name = "Saved codes", Options = { "(none saved)" }, CurrentOption = {}, MultipleOptions = false,
        Callback = function(o) UI.sel.code = firstOpt(o) end,
    })
    T:CreateButton({ Name = "Load the picked code", Callback = go(function()
        local c = UI.sel.code and UI.sel.code:match("·%s*([%w]+)%s*$")
        if not c then return toast("Pick a saved code first", "bad") end
        Actions.loadText(c)
    end) })
    T:CreateButton({ Name = "Delete the picked code", Callback = go(function()
        local n = UI.sel.code and UI.sel.code:match("^(.-)%s+·")
        if not n then return toast("Pick a saved code first", "bad") end
        Store.deleteCode(n)
        UI.sel.code = nil
        Refresh.codes()
        toast("Deleted '" .. n .. "'", "good")
    end) })
end

-------------------------------------------------------------------------------- SETTINGS
do
    local T = newTab("Settings", "settings-2")

    T:CreateSection("Look")
    local accents = { "Cyan", "Pink", "Purple", "Green", "Gold", "Red" }
    T:CreateDropdown({
        Name = "Accent colour", Options = accents, CurrentOption = { CONFIG.accent }, MultipleOptions = false,
        Callback = function(o)
            local a = firstOpt(o)
            if not ACCENTS[a] or a == CONFIG.accent then return end
            setCfg("accent", a)
            local theme = cometTheme(a)
            task.delay(0.2, function()
                ui(function()
                    pcall(function() Window.ModifyTheme(theme) end)
                    pcall(repaintRayfield, theme)
                end)
                PasteBox.recolor(ACCENTS[a])
                HowTo.recolor(ACCENTS[a])
            end)
        end,
    })

    T:CreateSection("Paste options")
    T:CreateToggle({ Name = "Store furniture the layout doesn't use", CurrentValue = CONFIG.clearLeftovers,
        Callback = function(v) setCfg("clearLeftovers", v) end })
    T:CreateToggle({ Name = "Reuse pieces already in the house (free)", CurrentValue = CONFIG.reuseExisting,
        Callback = function(v) setCfg("reuseExisting", v) end })
    T:CreateToggle({ Name = "Copy wall and floor textures", CurrentValue = CONFIG.applyTextures,
        Callback = function(v) setCfg("applyTextures", v) end })
    T:CreateToggle({ Name = "Spend event currency (candy, gingerbread, skulls)", CurrentValue = CONFIG.spendEventCurrency,
        Callback = function(v) setCfg("spendEventCurrency", v) end })
    T:CreateToggle({ Name = "Over budget: buy what fits instead of refusing", CurrentValue = CONFIG.trimToBudget,
        Callback = function(v) setCfg("trimToBudget", v) end })
    T:CreateToggle({ Name = "Check every piece after pasting (and fix)", CurrentValue = CONFIG.verifyAfterPaste,
        Callback = function(v) setCfg("verifyAfterPaste", v) end })
    T:CreateInput({
        Name = "Always keep at least ($)", CurrentValue = CONFIG.keepBucks > 0 and tostring(CONFIG.keepBucks) or "",
        PlaceholderText = "0", RemoveTextAfterFocusLost = false,
        Callback = function(t)
            local n = tonumber((tostring(t):gsub("[,%s%$]", "")))
            if n and n >= 0 then setCfg("keepBucks", math.floor(n)) end
        end,
    })


    T:CreateSection("Waits")
    T:CreateSlider({ Name = "Wait for a house subscription", Range = { 1, 8 }, Increment = 0.5, Suffix = " s",
        CurrentValue = CONFIG.subscribeWait, Callback = function(v) setCfg("subscribeWait", v) end })
    T:CreateSlider({ Name = "Give up walking into a house after", Range = { 10, 60 }, Increment = 1, Suffix = " s",
        CurrentValue = CONFIG.enterWait, Callback = function(v) setCfg("enterWait", v) end })
    T:CreateSlider({ Name = "Most pieces in a ghost preview", Range = { 50, 1500 }, Increment = 50, Suffix = "",
        CurrentValue = CONFIG.previewCap, Callback = function(v) setCfg("previewCap", math.floor(v)) end })

    T:CreateSection("Session")
    T:CreateToggle({ Name = "Anti-AFK (needs getconnections)", CurrentValue = CONFIG.antiAfk,
        Callback = function(v) setCfg("antiAfk", v) ; setAntiAfk(v) end })

    T:CreateSection("Discord webhook")
    T:CreateToggle({ Name = "Post batch progress", CurrentValue = CONFIG.webhookOn,
        Callback = function(v) setCfg("webhookOn", v) end })
    T:CreateInput({ Name = "Webhook URL", CurrentValue = CONFIG.webhookUrl,
        PlaceholderText = "https://discord.com/api/webhooks/…", RemoveTextAfterFocusLost = false,
        Callback = function(t) setCfg("webhookUrl", (tostring(t):gsub("%s+", ""))) end })
    T:CreateButton({ Name = "Send a test message", Callback = go(function()
        if not httpRequest then return toast("This executor has no http request function", "bad") end
        if not tostring(CONFIG.webhookUrl):match("^https://") then return toast("Set a webhook URL first", "bad") end
        local was = CONFIG.webhookOn
        CONFIG.webhookOn = true
        webhook("Comet Hub house cloner — test message")
        CONFIG.webhookOn = was
        toast("Sent", "good")
    end) })

    T:CreateSection("Diagnostics")
    Set.caps = para(T:CreateParagraph({ Title = "Executor", Content = "checking…" }), "Executor")
    T:CreateButton({ Name = "Check the Adopt Me remotes", Callback = go(function()
        local missing, total = {}, 0
        for key, name in pairs(REMOTES) do
            total = total + 1
            if not R[key] then missing[#missing + 1] = name end
        end
        if #missing == 0 then
            okl("all %d housing remotes present", total)
            toast("All " .. total .. " housing remotes found", "good")
        else
            errl("missing remotes: %s", table.concat(missing, ", "))
            toast("Missing: " .. table.concat(missing, ", "), "bad")
        end
    end) })
    T:CreateButton({ Name = "Dump the last BuyFurnitures reply to the log", Callback = go(function()
        if State.lastBuy == nil then return toast("Nothing bought yet this session", "bad") end
        local ok, s = pcall(function() return HttpService:JSONEncode(State.lastBuy) end)
        info("last buy reply: %s", ok and s:sub(1, 900) or typeof(State.lastBuy))
        toast("Written to the log below", "good")
    end) })
    Set.log = para(T:CreateParagraph({ Title = "Log", Content = "—" }), "Log")
    T:CreateButton({ Name = "Copy the whole log", Callback = function()
        setclip(table.concat(Log, "\n"))
        toast("Log copied", "good")
    end })
    T:CreateButton({ Name = "Copy the last fetched paste (for broken imports)", Callback = function()
        if not State.lastFetch then return toast("Nothing fetched yet", "bad") end
        setclip(State.lastFetch)
        toast(("Copied %s characters"):format(commas(#State.lastFetch)), "good")
    end })
end

--==============================================================================
-- LIST REFRESHERS  (workers: they read game state, then queue the UI write)
--==============================================================================

function Refresh.players()
    local labels, map = {}, {}
    for _, e in ipairs(Game.exteriors()) do
        if e.player ~= LP then
            -- 🔒 = locked: Visit won't open it, but Clone still copies it from outside
            local okL, locked = pcall(ClientData.get_server, e.player, "door_locked")
            local label = ("%s · %s%s"):format(tostring(e.player_name), Game.houseName(e.building_type),
                (okL and locked == true) and "  🔒" or "")
            labels[#labels + 1] = label
            map[label] = e
        end
    end
    UI.maps.player, UI.sel.player = map, nil
    setOptions(UI.dPlayer, labels, "(nobody else has a house out)")
    return #labels
end

function Refresh.mine()
    local labels, map, tLabels, tMap = {}, {}, {}, {}
    for _, h in ipairs(Game.houses()) do
        local base = ("#%s · %s · %s"):format(tostring(h.house_id), tostring(h.name), Game.houseName(h.building_type))
        local label = base .. (h.active and "  (active)" or "")
        labels[#labels + 1] = label
        map[label] = h.house_id
        tLabels[#tLabels + 1] = base
        tMap[base] = h.house_id
    end
    UI.maps.mine, UI.sel.mine = map, nil
    UI.maps.target, UI.sel.target = tMap, nil
    setOptions(UI.dMine, labels, "(you don't own a house)")
    setOptions(UI.dTarget, tLabels, "(you don't own a house)")
    return #labels
end

function Refresh.kinds()
    local labels, map, pick = {}, {}, nil
    for _, t in ipairs(Game.houseTypes()) do
        local label = ("%s — $%s"):format(t.name, commas(t.cost))
        labels[#labels + 1] = label
        map[label] = t.kind
        if t.kind == CONFIG.batchKind then pick = label end
    end
    UI.maps.kind = map
    setOptions(UI.dKind, labels, "(no houses for sale)")
    if pick then ui(function() pcall(function() UI.dKind:Set({ pick }) end) end) end
    return #labels
end

function Refresh.scanTypes()
    local seen, list = {}, { "All" }
    for _, e in ipairs(Game.exteriors()) do
        if e.building_type and not seen[e.building_type] then
            seen[e.building_type] = true
            list[#list + 1] = e.building_type
        end
    end
    setOptions(UI.dScanTypes, list)
end

function Refresh.saved()
    local labels, map = {}, {}
    for _, entry in ipairs(Store.list()) do
        labels[#labels + 1] = entry.label
        map[entry.label] = entry
    end
    -- keep whatever is still ticked; tell Rayfield only if something was dropped
    local old, keep = UI.sel.saved or {}, {}
    for _, l in ipairs(old) do if map[l] then keep[#keep + 1] = l end end
    UI.maps.saved, UI.sel.saved = map, keep
    UI.savedSig = table.concat(labels, "\n")
    setOptions(UI.dSaved, labels, fs.canList and "(no saves yet)" or "(can't list files)")
    if #keep ~= #old then ui(function() pcall(function() UI.dSaved:Set(keep) end) end) end
    return #labels
end

function Refresh.codes()
    local labels = Store.codeLabels()
    setOptions(UI.dCodes, labels, "(none saved)")
    return #labels
end

function Refresh.contents()
    local l = State.layout
    UI.maps.contents, UI.sel.contents = {}, {}
    if not l then
        setOptions(UI.dContents, {}, "(no layout)")
        Set.contents("—")
        return
    end
    local labels = {}
    local rows = Layout.contents(l)
    for _, e in ipairs(rows) do
        local tag = (e.class ~= "buy") and ("  [" .. e.class .. "]") or ""
        local label = ("%s ×%d · $%s%s"):format(e.name, e.count, commas(e.total), tag)
        labels[#labels + 1] = label
        UI.maps.contents[label] = e.id
    end
    setOptions(UI.dContents, labels, "(empty layout)")
    local value, blocked = Layout.value(l)
    Set.contents(("%d pieces in %d kinds · $%s to buy everything%s"):format(#l.items, #rows, commas(value),
        blocked > 0 and (" · " .. blocked .. " not buyable") or ""))
end

--==============================================================================
-- COLLECTOR  (reads game state into strings; never touches Instances)
--==============================================================================

_G.HCV3.stage = "collector"

local dash = {}
local collecting, lastCollectErr = false, nil

-- Server read of the house you're standing in, so the plan knows what can be
-- reused. Slow cadence, idle only, and only in your own house.
local function refreshHouseStats()
    local hi = Game.interior()
    if not (hi and hi.house_id and Game.insideHouseOf(LP, hi.house_id)) then
        State.houseStats = nil
        return
    end
    local items = Game.read(hi.house_id, LP)
    if not items then return end
    local defaults, value = 0, 0
    for _, it in ipairs(items) do
        if it.wasDefault then defaults = defaults + 1 end
        local class, cost = Rules.classify(it.id)
        if class == "buy" then value = value + (cost or 0) end
    end
    State.houseStats = { houseId = hi.house_id, items = items, count = #items, defaults = defaults, value = value }
end

local function collect()
    local d = {}
    local money = Game.money()
    local keep = tonumber(CONFIG.keepBucks) or 0
    local storage = Game.storage()
    local stored = 0
    for _, n in pairs(storage) do stored = stored + n end
    local houses = Game.houses()
    d.acct = ("%s · $%s · %d house(s) · %d piece(s) in storage"):format(LP.Name, commas(money), #houses, stored)

    local hi = Game.interior()
    local loc = Game.location()
    local inHouse = loc and loc.destination_id == "housing" and hi and hi.player and hi.house_id
    if inHouse and hi.player ~= LP then lastSubscribed = hi.player end
    local mine = inHouse and hi.player == LP
    local st = State.houseStats
    local fresh = mine and st and st.houseId == hi.house_id

    local where, pieces
    if inHouse then
        local h = mine and Game.house(hi.house_id)
        where = ("In %s · %s%s · #%s"):format(
            mine and "your house" or (tostring(hi.player.Name) .. "'s house"),
            Game.houseName(hi.building_type),
            (h and h.name) and ("  \"" .. tostring(h.name) .. "\"") or "",
            tostring(hi.house_id))
        if fresh then
            pieces = ("%d pieces (%d came with the house) · worth $%s · limit %s"):format(
                st.count, st.defaults, commas(st.value), tostring(hi.max_furniture or "?"))
        elseif mine then
            pieces = "Counting the pieces…"
        else
            pieces = "Clone this house to copy it"
        end
    else
        local a = Game.activeHouse()
        where = a and ("Outside · active house #%s  \"%s\" · %s"):format(
            tostring(a.house_id), tostring(a.name), Game.houseName(a.building_type)) or "You don't own a house yet"
        pieces = "Walk into your house to paste"
    end
    d.where = d.acct .. "\n" .. where .. "\n" .. pieces

    local L = State.layout
    if L then
        local value, blocked = Layout.value(L)
        d.layout = ("%s\n%d pieces · $%s to buy it all%s%s"):format(State.layoutName, #L.items, commas(value),
            blocked > 0 and (" · " .. blocked .. " not buyable") or "",
            L.buildingType and (" · from a " .. Game.houseName(L.buildingType)) or "")
        local p = Plan.build(L, fresh and st.items or nil, storage, money, fresh and hi.textures or nil)
        if fresh then Plan.fit(p, hi.max_furniture) end
        State.dashPlan = p
        d.plan = (fresh and "In this house: " or "Into an empty house: ") .. Plan.describe(p) .. "\n" ..
            (p.affordable and ("You'll have $" .. commas(p.after) .. " left")
                or ("SHORT by $" .. commas(keep - p.after))) ..
            (#p.skipped > 0 and ("\nSkipped: " .. Plan.skipReasons(p)) or "")
        local count = math.floor(CONFIG.batchCount)
        local est = Batch.estimate(L, CONFIG.batchKind, count)
        State.dashEstimate = est
        d.estimate = ("%d × %s — %d to buy at $%s each\nup to $%s of furniture per house\nup to $%s in total · you have $%s"):format(
            count, Game.houseName(CONFIG.batchKind), est.toBuy, commas(est.price), commas(est.per),
            commas(est.total), commas(money))
    else
        d.layout = "None — open the paste box, clone a house, or load a save"
        d.plan = "—"
        d.estimate = "Load a layout first"
        State.dashPlan, State.dashEstimate = nil, nil
    end
    return d
end

--==============================================================================
-- RENDER LOOP  —  the only place the UI gets written
--==============================================================================

local function bar(frac)
    local n = math.clamp(math.floor(frac * 12 + 0.5), 0, 12)
    return string.rep("▰", n) .. string.rep("▱", 12 - n)
end

local accum, ticks = 0, 0
track(RunService.Heartbeat:Connect(function(dt)
    if #uiQueue > 0 then
        local q = uiQueue
        uiQueue = {}
        for _, fn in ipairs(q) do pcall(fn) end
    end
    for _ = 1, math.min(#uiSlow, 20) do
        pcall(table.remove(uiSlow, 1))
    end

    accum = accum + dt
    if accum < 0.5 then return end
    accum = 0
    ticks = ticks + 1

    local pr = State.progress
    if State.running then
        local line = tostring(State.busy) .. " · " .. tostring(pr.phase)
        if (pr.total or 0) > 0 then
            local done = math.min(pr.done, pr.total)
            line = line .. "\n" .. bar(done / pr.total) .. ("  %d / %d"):format(done, pr.total)
        end
        Set.now(line)
    else
        Set.now("Idle — " .. tostring(dash.acct or LP.Name))
    end
    if dash.layout then Set.layout(dash.layout) end
    if dash.plan then Set.plan(dash.plan) end
    if dash.where then Set.where(dash.where) end
    if dash.estimate then Set.estimate(dash.estimate) end
    Set.scan(tostring(State.scanStatus))

    if State.batchDirty then
        State.batchDirty = false
        Set.batch(#State.batchLines > 0 and table.concat(State.batchLines, "\n") or "Nothing yet")
    end
    if State.boardDirty then
        State.boardDirty = false
        Set.board(Batch.boardText())
    end
    if logDirty then
        logDirty = false
        local slice = {}
        for i = math.max(1, #Log - 14), #Log do slice[#slice + 1] = Log[i] end
        Set.log(#slice > 0 and table.concat(slice, "\n") or "—")
    end

    if ticks % 4 == 0 and not collecting then
        collecting = true
        task.spawn(function()
            local ok, res = pcall(collect)
            if ok and type(res) == "table" then
                dash = res
            elseif not ok and tostring(res) ~= lastCollectErr then
                lastCollectErr = tostring(res)
                errl("dashboard: %s", lastCollectErr)
            end
            collecting = false
        end)
    end
    if ticks % 30 == 0 and not State.running then
        task.spawn(function() pcall(refreshHouseStats) end)
    end
    -- New .json files show up without anyone pressing Refresh.
    if ticks % 10 == 5 and fs.canList and not UI.savedChecking then
        UI.savedChecking = true
        task.spawn(function()
            local ok, list = pcall(Store.list)
            if ok then
                local t = {}
                for _, e in ipairs(list) do t[#t + 1] = e.label end
                if table.concat(t, "\n") ~= UI.savedSig then pcall(Refresh.saved) end
            end
            UI.savedChecking = false
        end)
    end
end))

--==============================================================================
-- HOTKEYS  (K toggles the window — Rayfield's own key)
--==============================================================================

track(UIS.InputBegan:Connect(function(i, gpe)
    if gpe then return end
    if not (UIS:IsKeyDown(Enum.KeyCode.LeftControl) and
            (UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift))) then
        return
    end
    local k, act = i.KeyCode, nil
    if k == Enum.KeyCode.P then act = function() Actions.paste(nil, "instant") end
    elseif k == Enum.KeyCode.F then act = function() Actions.paste(nil, "fix") end
    elseif k == Enum.KeyCode.C then act = Actions.cloneHere
    elseif k == Enum.KeyCode.V then act = Actions.previewToggle
    elseif k == Enum.KeyCode.B then act = PasteBox.open
    elseif k == Enum.KeyCode.Z then act = function() Actions.undo(false) end
    elseif k == Enum.KeyCode.S then act = Actions.stop end
    if act then
        task.spawn(function()
            local ok, e = pcall(act)
            if not ok then errl("hotkey: %s", tostring(e)) end
        end)
    end
end))

--==============================================================================
-- INIT
--==============================================================================

_G.HCV3.stage = "init"

-- Re-running the script calls this first: stops jobs, loops and both windows.
_G.HouseClonerKill = function()
    State.stopFlag = true
    for _, c in ipairs(UI.conns) do pcall(function() c:Disconnect() end) end
    pcall(function() Rayfield:Destroy() end)
    pcall(function() UI.box:Destroy() end)
    pcall(function() UI.howto:Destroy() end)
    local stray = workspace:FindFirstChild("HouseClonerPreview")
    if stray then pcall(function() stray:Destroy() end) end
end

-- Handle for poking at a live session from an executor console / MCP probe.
_G.HCV3.api = {
    Game = Game, Rules = Rules, Plan = Plan, Paste = Paste, Txn = Txn, Store = Store, Layout = Layout,
    Preview = Preview, Renamer = Renamer, Batch = Batch, Scanner = Scanner, Actions = Actions,
    State = State, CONFIG = CONFIG, Log = Log, UI = UI, PasteBox = PasteBox,
}

Store.ensure()

-- Everything below reads game state, so it runs off the construction thread.
task.spawn(function()
    Set.caps(("file API %s · http %s · getconnections %s · loadstring %s"):format(
        hasFS and "yes" or "NO", httpRequest and "yes" or "NO",
        typeof(getconns) == "function" and "yes" or "NO", loadstring and "yes" or "NO"))
    for _, name in ipairs({ "kinds", "players", "mine", "scanTypes", "saved", "codes", "contents" }) do
        local ok, e = pcall(Refresh[name])
        if not ok then errl("init %s: %s", name, tostring(e)) end
    end
    if CONFIG.antiAfk then setAntiAfk(true) end
    pcall(refreshHouseStats)
    local ok, res = pcall(collect)
    if ok then dash = res end
    local n = 0
    for _ in pairs(FurnitureDB) do n = n + 1 end
    okl("Comet Hub house cloner ready — %d house(s), %d furniture kinds", #Game.houses(), n)
    info("K hides the window · LeftCtrl+Shift: P paste, F fix, C clone, V preview, B paste box, Z undo, S stop")
    toast("House cloner ready — K hides the window", "good")
end)

_G.HCV3.stage = "ready"
