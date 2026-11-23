-- Meth Lab HUD 1.0.0 - meth lab status icon for Payday 3.
--
--   A meth bag silhouette that fills as ingredients go in (1/3, 2/3), with the
--   next ingredient's initials (CS / MU / HCL) on it. Then:
--     cooking / raw  = light blue, slow pulse
--     perfect        = deep blue "pure" bag (+ a non-spatial copy of the ready sound)
--     overcooked     = red "burnt" bag
--     generator off  = dimmed bag with a warning sign
--     wrong mix      = greyed bag with a red X
--   Style = hud (fixed spot on screen), world (over the lab), or both.
--   Only shows on maps that have a cooking station.
--
--   Keys (settings.ini, none by default): on/off, switch style.
--   Settings: settings.ini in this mod's folder. Restart the game after editing
--   it by hand; changes made in ModMenu (the in-game settings menu) apply live.
--
-- Rules carried over from SentryHeat (this UE4SS build): all Lua on the game
-- thread, Blueprint-function hooks only, no delegate parameters/properties,
-- FindAllOf kept rare.

---------------------------------------------------------------------------
-- Config (defaults; settings.ini overrides)
---------------------------------------------------------------------------
local STYLE         = "hud"    -- hud | world | both
local PANEL_X       = 0.985    -- hud: right edge, fraction of screen width
local PANEL_Y       = 0.70     -- hud: vertical centre (below SentryHeat's panel, above the carried-bag icon)
local ICON_SIZE     = 56       -- px
local WORLD_HEIGHT  = 150      -- cm above the station origin (world style)
local READY_SOUND   = true     -- play the "meth ready" sound non-spatially too
local SHOW_BATCHES  = true     -- small number: bags the station can still make
local INGREDIENT_MARKERS = false  -- markers over ingredient pickups (grouped by spot), seen through walls
local GROUP_RADIUS  = 6        -- metres: pickups this close share one marker
local PICKUP_HEIGHT = 40       -- cm above the group's centre
local HIDE_WHEN_PAUSED = true
local TOGGLE_KEY    = "NONE"   -- no keys unless the player sets them
local STYLE_KEY     = "NONE"   -- cycles hud -> world -> both
local PERF_LOG      = false    -- (undocumented) log the mod's time per frame every 10 s   -- @dev
local DEBUG_KEYS    = false    -- (undocumented) extra dialogue logging for Cook Off (debug actions: ModMenu's DEBUG tab)   -- @dev

local COL_IDLE    = { R = 0.85, G = 0.85, B = 0.85, A = 1 }
local COL_COOK    = { R = 0.15, G = 0.70, B = 1.00, A = 1 }
local COL_PERFECT = { R = 0.05, G = 0.25, B = 1.00, A = 1 }
local COL_BURNT   = { R = 1.00, G = 0.20, B = 0.15, A = 1 }
local COL_BOOM    = { R = 1.00, G = 0.15, B = 0.12, A = 1 }   -- the red X on a destroyed lab
local COL_WRECK   = { R = 0.30, G = 0.30, B = 0.30, A = 1 }   -- the bag under the X
local COL_FIX     = { R = 1.00, G = 0.85, B = 0.20, A = 1 }
local COL_SABOTAGED = { R = 0.45, G = 0.45, B = 0.45, A = 1 }   -- filled part while the power is off
local COL_DIM     = { R = 0.15, G = 0.15, B = 0.15, A = 0.6 }
local COL_TEXT    = { R = 1.00, G = 1.00, B = 1.00, A = 1 }
local COL_COUNT   = { R = 0.80, G = 0.80, B = 0.80, A = 1 }
local LABEL_GAP   = 6      -- px between the ingredient text and the bag
local LABEL_Y     = 0.3    -- ingredient text height on the bag (0 = top, 1 = bottom); the batch number sits at the bottom

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local TAG = "[MethCook] "
local function log(fmt, ...) print(TAG .. string.format(fmt, ...) .. "\n") end
local loggedOnce = {}
local function logOnce(key, fmt, ...)
    if loggedOnce[key] then return end
    loggedOnce[key] = true
    log(fmt, ...)
end
local function safe(fn, default)
    local ok, v = pcall(fn)
    if ok then return v end
    return default
end
-- Hot-path helpers: pcall on fixed functions instead of a new closure per
-- call, so the per-frame path makes (almost) no Lua garbage.
local function _isValid(o) return o:IsValid() end
local function _addr(o) return o:GetAddress() end
local function _get(o, k) return o[k] end
local function _call(o, m, ...) return o[m](o, ...) end
local function valid(o)
    if o == nil then return false end
    local ok, v = pcall(_isValid, o)
    return ok and v == true
end
local function addr(o)
    local ok, v = pcall(_addr, o)
    if ok then return v end
    return 0
end
local function getp(o, k, default)          -- o[k], or default on error / nil
    local ok, v = pcall(_get, o, k)
    if ok and v ~= nil then return v end
    return default
end
local function callm(o, m, ...)             -- o:m(...), or nil on error
    local ok, v = pcall(_call, o, m, ...)
    if ok then return v end
    return nil
end
local function clearTable(t) for k in pairs(t) do t[k] = nil end end

-- StaticFindObject costs ~5 ms when the object is NOT loaded (measured in game,
-- 2026-11-19; ~0.02 ms when it is). So "is the lab / Cook Off loaded yet?" is
-- only asked while a level loads (no player yet) or on the maps that have a
-- lab, and a found object is kept (checking it is still valid costs ~0).
local lvl = { noPC = true, name = "",            -- name = current map, lower case
    meth = { bust = true, cookie = true },          -- maps with a lab: Party Powder, Cook Off
    cookie = { cookie = true },
    found = {} }
function lvl.on(maps)                            -- map name contains one of these
    for k in pairs(maps) do if lvl.name:find(k, 1, true) then return true end end
    return false
end
local function findLoaded(path, maps)
    local o = lvl.found[path]
    if o ~= nil and valid(o) then return o end
    lvl.found[path] = nil
    if not (lvl.noPC or (maps and lvl.on(maps))) then return nil end
    local ok, r = pcall(StaticFindObject, path)
    if ok and valid(r) then lvl.found[path] = r; return r end
    return nil
end
local function clampNum(x, a, b, default)
    if type(x) ~= "number" then return default end
    if x < a then return a elseif x > b then return b end
    return x
end

---------------------------------------------------------------------------
-- settings.ini
---------------------------------------------------------------------------
local SETTINGS_LOG = {}
local function hexColor(v)
    local h = tostring(v):gsub("^#", "")
    if not h:match("^%x%x%x%x%x%x$") then return nil end
    return { R = tonumber(h:sub(1, 2), 16) / 255, G = tonumber(h:sub(3, 4), 16) / 255,
             B = tonumber(h:sub(5, 6), 16) / 255, A = 1 }
end
local function toBool(v) v = tostring(v):lower(); return v == "true" or v == "1" or v == "yes" or v == "on" end
local function loadSettings()
    local src = (debug and debug.getinfo and debug.getinfo(1, "S").source) or ""
    local dir = src:gsub("^@", ""):gsub("[/\\]Scripts[/\\][^/\\]*$", "")
    local f = io and io.open(dir .. "\\settings.ini", "r")
    if not f then SETTINGS_LOG[#SETTINGS_LOG + 1] = "no settings.ini found, using defaults" return end
    for rawLine in f:lines() do
        local line = rawLine:gsub(";.*$", "")
        local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
        if k and v ~= "" then
            local key, ok = k:lower(), true
            if key == "style" then
                local st = v:lower()
                if st == "hud" or st == "world" or st == "both" then STYLE = st else ok = false end
            elseif key == "panelx" then PANEL_X = clampNum(tonumber(v), 0, 1, PANEL_X)
            elseif key == "panely" then PANEL_Y = clampNum(tonumber(v), 0, 1, PANEL_Y)
            elseif key == "iconsize" then ICON_SIZE = clampNum(tonumber(v), 24, 200, ICON_SIZE)
            elseif key == "worldheight" then WORLD_HEIGHT = clampNum(tonumber(v), -500, 1000, WORLD_HEIGHT)
            elseif key == "readysound" then READY_SOUND = toBool(v)
            elseif key == "showbatches" then SHOW_BATCHES = toBool(v)
            elseif key == "ingredientmarkers" then INGREDIENT_MARKERS = toBool(v)
            elseif key == "groupradius" then GROUP_RADIUS = clampNum(tonumber(v), 1, 50, GROUP_RADIUS)
            elseif key == "hideinmenus" then HIDE_WHEN_PAUSED = toBool(v)
            elseif key == "togglekey" then TOGGLE_KEY = v:upper()
            elseif key == "stylekey" then STYLE_KEY = v:upper()
            elseif key == "debugkeys" then DEBUG_KEYS = toBool(v)   -- @dev
            elseif key == "perflog" then PERF_LOG = toBool(v)   -- @dev
            elseif key == "idlecolor" then COL_IDLE = hexColor(v) or COL_IDLE
            elseif key == "cookingcolor" then COL_COOK = hexColor(v) or COL_COOK
            elseif key == "perfectcolor" then COL_PERFECT = hexColor(v) or COL_PERFECT
            elseif key == "burntcolor" then COL_BURNT = hexColor(v) or COL_BURNT
            elseif key == "boomcolor" then COL_BOOM = hexColor(v) or COL_BOOM
            else ok = false end
            if not ok then SETTINGS_LOG[#SETTINGS_LOG + 1] = "settings.ini: unknown setting or value: " .. k end
        end
    end
    f:close()
end
do
    local ok, err = pcall(loadSettings)
    if not ok then SETTINGS_LOG[#SETTINGS_LOG + 1] = "settings.ini error: " .. tostring(err) end
end

---------------------------------------------------------------------------
-- Game data
---------------------------------------------------------------------------
local STATION_CLASS = "BP_MethCookingStation_C"
local STATION_BP = "/Game/DLCs/00004-DLCREMA/Prototype/Maps/Villa/Blueprints/BP_MethCookingStation.BP_MethCookingStation_C"
local PICKUP_CLASSES = { "BP_Meth_CausticSoda_C", "BP_Meth_HydrogenChloride_C", "BP_Meth_MuriaticAcid_C" }
-- ESBZCookingState
local INACTIVE, WAITING, COOKING, UNDER, COOKED, OVER, SABOTAGED, DESTROYED = 0, 1, 2, 3, 4, 5, 6, 7
local STATE_NAMES = { [0] = "Inactive", "Waiting", "Cooking", "Raw", "Perfect", "Overcooked", "Sabotaged", "Destroyed" }
local SOUND = "/Game/WwiseAudio/Events/Player/Interactions/Chemicals/PLR_Int_Meth_ReadySimple.PLR_Int_Meth_ReadySimple"
local HUD = "/Game/DLCs/00004-DLCREMA/UI/Textures/HUDIcons/"
local ICONS = {
    normal = HUD .. "SS_UI_pickups_REM_MethBag_Normal.SS_UI_pickups_REM_MethBag_Normal",
    pure   = HUD .. "SS_UI_pickups_REM_MethBag_Pure.SS_UI_pickups_REM_MethBag_Pure",
    burnt  = HUD .. "SS_UI_pickups_REM_MethBag_Burnt.SS_UI_pickups_REM_MethBag_Burnt",
    fix    = "/Game/UI/Textures/HUDIcons/SS_UI_HUD_WpFix.SS_UI_HUD_WpFix",
    warn   = "/Game/UI/Textures/HUDIcons/SS_UI_Security_WarningSign.SS_UI_Security_WarningSign",
}
-- Pour slot (1..3) -> ingredient, if the station's meshes don't tell us.
-- Seen in Party Powder: slot 1 = MU, slot 2 = CS, slot 3 = HCL.
local FALLBACK_SLOTS = { "MU", "CS", "HCL" }

---------------------------------------------------------------------------
-- Local player controller (own lookup; UEHelpers caches across levels)
---------------------------------------------------------------------------
local pcCache, lastPCScan, deadPC = nil, -1, {}
local function localPC()
    if pcCache and valid(pcCache) then return pcCache end
    pcCache = nil
    local now = os.clock()
    if now - lastPCScan < 0.5 then return nil end
    lastPCScan = now
    for _, c in ipairs(FindAllOf("PlayerController") or {}) do
        if valid(c) and not deadPC[addr(c)] and safe(function() return c:IsLocalController() end, false) then
            pcCache = c
            break
        end
    end
    return pcCache
end
local function cameraLoc(pc)
    local cam = safe(function() return pc.PlayerCameraManager end)
    local l = valid(cam) and safe(function() return cam:GetCameraLocation() end)
    if not l then
        local pawn = safe(function() return pc.Pawn end)
        if valid(pawn) then l = safe(function() return pawn:K2_GetActorLocation() end) end
    end
    return l
end

---------------------------------------------------------------------------
-- Stations
---------------------------------------------------------------------------
-- addr -> { obj, loc, state, slots = {ing, ing, ing}, widget }
local stations = {}
local dirty = false       -- set by hooks: run the lab update on the next frame
local cookCall = { ing = nil, sure = false, fakeout = false }   -- Cook Off: Shade's current call (see onDialog)
local CALL_TRUST_S = 5     -- seconds after her call with no "hold up" before the ? clears
local DIALOG_MIN_S = 0     -- lines count as soon as they start (time in the dialog list does not match playback: a full subtitle showed for an entry that left after 0.8 s)
local orders = {}          -- station addr -> recipe as 0-based pour slots (hook may fire before we track it)
local addedBy = {}         -- station addr -> { [slot] = true } (from the pour hook)

-- Uses the mapping seen in Party Powder; the station's ingredient mesh names
-- are logged so other labs (Cook Off) can be checked against it.
local function readSlots(st)
    local names, fromMesh = {}, {}
    for i = 1, 3 do
        local comp = safe(function() return st["Ingredient" .. i] end)
        local mesh = valid(comp) and safe(function() return comp.StaticMesh end)
        local n = valid(mesh) and safe(function() return mesh:GetFName():ToString() end, "?") or "?"
        names[i] = n
        if n:find("Muriatic") then fromMesh[i] = "MU"
        elseif n:find("Hydrogen") then fromMesh[i] = "HCL"
        elseif n:find("Caustic") then fromMesh[i] = "CS" end
    end
    -- @dev-begin
    log("ingredient meshes: %s / %s / %s (mesh says %s/%s/%s)", names[1], names[2], names[3],
        fromMesh[1] or "-", fromMesh[2] or "-", fromMesh[3] or "-")
    -- @dev-end
    return FALLBACK_SLOTS, false
end

local function isGhost(loc)
    -- Copies left over from loading sit at the origin.
    return loc == nil or (loc.X == 0 and loc.Y == 0 and loc.Z == 0)
end

-- Discovery is event-based: the lab's BeginPlay and recipe events hand us the
-- station (see hooks below). FindAllOf (which walks every object in the game)
-- only runs once when the lab class first appears, then every 30 s as a
-- safety net, and never on maps without a lab.
local pending = {}        -- addr -> station object, queued by hooks
local function addStation(o)
    if not valid(o) then return end
    local a = addr(o)
    if stations[a] then return end
    local loc = safe(function() return o:K2_GetActorLocation() end)
    if isGhost(loc) then return end
    local slots, fromMesh = readSlots(o)
    stations[a] = { obj = o, loc = loc, state = nil, slots = slots, boards = {} }
    pcall(function()
        o.recipeActors:ForEach(function(i, e)
            local b = e:get()
            if valid(b) then
                local bl = safe(function() return b:K2_GetActorLocation() end)
                stations[a].boards[#stations[a].boards + 1] = b
                -- @dev-begin
                log("recipe display %d at (%.0f %.0f %.0f), hidden=%s", i, bl and bl.X or 0, bl and bl.Y or 0, bl and bl.Z or 0,
                    tostring(safe(function() return b.bHidden end)))
                -- @dev-end
            end
        end)
    end)
    addedBy[a] = addedBy[a] or {}
    log("station found at (%.0f %.0f %.0f), slots %s/%s/%s (%s), recipe %s",
        loc.X, loc.Y, loc.Z, slots[1], slots[2], slots[3], fromMesh and "from meshes" or "as seen in Party Powder",
        orders[a] and "known" or "not seen")
end

local SAFETY_EVERY = 30.0
local lastScan = nil      -- nil = not searched on this level yet
local classCheckAt, classLoaded = nil, false
local function scanStations()
    -- Hooked stations: add them now (cheap, no search).
    for a, o in pairs(pending) do
        pending[a] = nil
        addStation(o)
    end
    -- No station class loaded = no meth on this map: nothing to do.
    -- (Checked once a second, not every frame.)
    local now = os.clock()
    if not classCheckAt or now - classCheckAt >= 1.0 then
        classCheckAt = now
        classLoaded = findLoaded(STATION_BP, lvl.meth) ~= nil
    end
    if not classLoaded then
        for a in pairs(stations) do stations[a] = nil end
        lastScan = nil
        return
    end
    -- The full search (walks every object: a hitch) is only a fallback for
    -- when no lab is known yet (e.g. hooks registered after BeginPlay). Once a
    -- lab is known, new ones arrive through the BeginPlay hook.
    if next(stations) ~= nil then return end
    if lastScan and now - lastScan < SAFETY_EVERY then return end
    lastScan = now
    for _, o in ipairs(FindAllOf(STATION_CLASS) or {}) do addStation(o) end
end

---------------------------------------------------------------------------
-- Hooks (Blueprint events on the station). Registered as soon as the
-- station class is loaded, so the recipe event at map start isn't missed.
---------------------------------------------------------------------------
local hooked = false
local lastHookTry = 0
local function _pget(x) return x:get() end
local function p(x)
    local ok, v = pcall(_pget, x)
    if ok then return v end
    return x
end
local function queue(st)
    if valid(st) then pending[addr(st)] = st end
end
-- Each hook is registered on its own and retried until it succeeds.
-- (StaticFindObject on a Blueprint function path returns nothing in this
-- build, so the class is checked instead and RegisterHook is just tried.)
local HOOKS = {
    { fn = "BP_OnStaticOrderGenerated", cb = function(ctx, order)
        local st = p(ctx)
        local list = {}
        pcall(function() p(order):ForEach(function(i, e) list[#list + 1] = tonumber(p(e)) end) end)
        orders[addr(st)] = { list = list, t = os.clock() }
        queue(st)
        log("recipe received (%d steps)", #list)   -- @dev
    end },
    { fn = "BP_OnIngredientAdded", cb = function(ctx, idx)
        local st = p(ctx)
        local a = addr(st)
        addedBy[a] = addedBy[a] or {}
        local i = tonumber(p(idx))
        if i then addedBy[a][i] = true end
        -- Joined (or reloaded) mid-batch: this pour's place in the recipe tells
        -- us exactly which ingredients are already in.
        local stn = stations[a]
        local order = orders[a] and orders[a].list
        if stn and stn.progressUnknown and i and order then
            for pos, slot0 in ipairs(order) do
                if slot0 + 1 == i then
                    for k = 1, pos do addedBy[a][order[k] + 1] = true end
                    stn.progressUnknown = false
                    log("progress rebuilt from pour: %d of %d in", pos, #order)   -- @dev
                    break
                end
            end
        end
        if stn and i then
            if not stn.witnessed then log("recipe known: someone poured an ingredient") end   -- @dev
            stn.witnessed = true
        end
        _G.MethCookLastPour = os.clock()   -- @dev
        dirty = true
        cookCall.ing, cookCall.sure, cookCall.fakeout = nil, false, false
        log("pour into slot %s", tostring(i))   -- @dev
        queue(st)
    end },
    { fn = "ReceiveBeginPlay", cb = function(ctx) queue(p(ctx)) end },
    -- Optional: instant refresh on a state change (the state is also read 10x/s).
    { fn = "BP_OnStateChanged", optional = true, cb = function() dirty = true end },
}
-- Cook Off announces ingredients live. Its level script binds the stations'
-- OnRequiredIngredientChanged (host-only) to these Blueprint functions.
local COOKIE_SCRIPT = "/Game/DLCs/00242-COOKIE/Maps/Sublevels/Gameplay_Cookie/G_Cookie_Scripting.G_Cookie_Scripting_C"
-- @dev-begin
local COOKIE_REQ_EVENTS = {
    "BndEvt__G_Villa_Scripting_BP_MethCookingStation_2_K2Node_ActorBoundEvent_55_SBZCookingStationIngredientDelegate__DelegateSignature",
    "BndEvt__G_Villa_Scripting_BP_MethCookingStation2_K2Node_ActorBoundEvent_56_SBZCookingStationIngredientDelegate__DelegateSignature",
    "BndEvt__G_Villa_Scripting_BP_MethCookingStation3_6_K2Node_ActorBoundEvent_57_SBZCookingStationIngredientDelegate__DelegateSignature",
}
local liveRequired = { idx = nil, t = 0 }      -- last announced ingredient index (Cook Off, host)
local cookieHooked, lastCookieTry = false, 0
local function tryCookieHooks()
    if cookieHooked then return end
    local now = os.clock()
    if now - lastCookieTry < 1.0 then return end
    lastCookieTry = now
    if not findLoaded(COOKIE_SCRIPT, lvl.cookie) then return end
    local n = 0
    for i, fn in ipairs(COOKIE_REQ_EVENTS) do
        local ok, err = pcall(RegisterHook, COOKIE_SCRIPT .. ":" .. fn, function(ctx, idx)
            local v = tonumber(safe(function() return idx:get() end))
            liveRequired.idx, liveRequired.t, liveRequired.lab = v, os.clock(), i
            log("Cook Off: required ingredient changed -> %s (lab handler %d)", tostring(v), i)
        end)
        if ok then n = n + 1 else log("Cook Off hook %d: %s", i, tostring(err)) end
    end
    cookieHooked = true
    log("Cook Off: %d required-ingredient hooks registered", n)
end
-- @dev-end

local function tryHooks()
    tryCookieHooks()   -- @dev
    if hooked then return end
    local now = os.clock()
    if now - lastHookTry < 0.25 then return end
    lastHookTry = now
    if not findLoaded(STATION_BP, lvl.meth) then return end
    local all = true
    for _, h in ipairs(HOOKS) do
        if not h.done and not (h.optional and (h.fails or 0) >= 20) then
            local ok, err = pcall(RegisterHook, STATION_BP .. ":" .. h.fn, h.cb)
            if ok then h.done = true; log("hooked %s", h.fn)
            else
                h.fails = (h.fails or 0) + 1
                if not (h.optional and h.fails >= 20) then all = false end
                if h.fails == 1 or h.fails % 40 == 0 then log("hook %s not ready: %s", h.fn, tostring(err)) end
            end
        end
    end
    if all then hooked = true; log("lab hooks registered") end
end

---------------------------------------------------------------------------
-- Sound: the game's ready sound, played at the camera (= non-spatial).
-- PostEventAtLocation has no delegate parameter (delegates crash UE4SS here).
---------------------------------------------------------------------------
local soundEv, AK = nil, nil
local function playReady(pc)
    if not valid(soundEv) then
        soundEv = safe(function() return StaticFindObject(SOUND) end)
        if not valid(soundEv) then soundEv = safe(function() return LoadAsset(SOUND) end) end
    end
    if not valid(AK) then AK = StaticFindObject("/Script/AkAudio.Default__AkGameplayStatics") end
    local l = cameraLoc(pc)
    if not (valid(soundEv) and valid(AK) and l) then logOnce("snd", "ready sound unavailable"); return end
    local ok, err = pcall(function()
        AK:PostEventAtLocation(soundEv, { X = l.X, Y = l.Y, Z = l.Z }, { Pitch = 0, Yaw = 0, Roll = 0 }, pc)
    end)
    if not ok then logOnce("snd2", "ready sound failed: %s", tostring(err)) end
end

---------------------------------------------------------------------------
-- Widgets (runtime UMG)
---------------------------------------------------------------------------
local ui = {}
local nameN = 0
local function newObj(classPath, outer, base)
    nameN = nameN + 1
    return StaticConstructObject(StaticFindObject(classPath), outer, FName(base .. "_" .. nameN))
end
local texCache, texTry = {}, {}
local function tex(key)
    local o = texCache[key]
    if valid(o) then return o end
    local now = os.clock()
    if texTry[key] and now - texTry[key] < 2 then return nil end
    texTry[key] = now
    o = safe(function() return StaticFindObject(ICONS[key]) end)
    if not valid(o) then o = safe(function() return LoadAsset(ICONS[key]) end) end
    if valid(o) then texCache[key] = o else logOnce("icon" .. key, "icon not found: %s", ICONS[key]) end
    return o
end

local VIS_COLLAPSED, VIS_HITTEST_INVIS = 1, 3

local function ensureRoot(pc)
    if valid(ui.root) and valid(ui.canvas) then
        if callm(ui.root, "IsInViewport") == false then
            pcall(function() ui.root:AddToViewport(49) end)
        end
        return true
    end
    for _, old in ipairs(FindAllOf("UserWidget") or {}) do
        if valid(old) and old ~= ui.root and safe(function() return old:GetFName():ToString() end, ""):find("^MethCookRoot") then
            pcall(function() old:RemoveFromParent() end)
        end
    end
    local ok, err = pcall(function()
        local w = newObj("/Script/UMG.UserWidget", pc:GetWorld(), "MethCookRoot")
        local tree = newObj("/Script/UMG.WidgetTree", w, "MethCookTree")
        w.WidgetTree = tree
        local canvas = newObj("/Script/UMG.CanvasPanel", tree, "MethCookCanvas")
        tree.RootWidget = canvas
        ui.root, ui.tree, ui.canvas = w, tree, canvas
        ui.rootVis = VIS_HITTEST_INVIS
        -- Icons belonged to the old root: rebuild them.
        ui.hud = nil
        ui.ingMarkers = nil
        groupSig = nil
        for _, st in pairs(stations) do st.widget = nil end
        w:SetVisibility(VIS_HITTEST_INVIS)
        w:AddToViewport(49)
    end)
    if not ok then
        logOnce("root:" .. tostring(err), "UI creation failed: %s", tostring(err))
        ui.root, ui.tree, ui.canvas = nil, nil, nil
        return false
    end
    return true
end

local function setIcon(img, key, size)
    local t = tex(key)
    if t then pcall(function() img:SetBrushResourceObject(t) end) end
    pcall(function() img:SetDesiredSizeOverride({ X = size, Y = size }) end)
end

local function makeText(size, color)
    local t = newObj("/Script/UMG.TextBlock", ui.tree, "MethCookText")
    pcall(function() t.Font.Size = size end)
    pcall(function() t.Font.OutlineSettings.OutlineSize = 1 end)
    pcall(function() t:SetColorAndOpacity({ SpecifiedColor = color, ColorUseRule = 0 }) end)
    return t
end

-- One icon: dim silhouette + bottom-anchored clipped bright copy + label,
-- a "fix" badge (top right) and a batch count (bottom left).
local function makeIcon(isHud)
    local S = ICON_SIZE
    local w = { size = S, cache = {} }
    local holder = newObj("/Script/UMG.CanvasPanel", ui.tree, "MethCookHolder")
    local hs = ui.canvas:AddChildToCanvas(holder)
    hs:SetSize({ X = S, Y = S })
    if isHud then
        hs:SetAnchors({ Minimum = { X = PANEL_X, Y = PANEL_Y }, Maximum = { X = PANEL_X, Y = PANEL_Y } })
        hs:SetAlignment({ X = 1, Y = 0.5 })
    else
        hs:SetAlignment({ X = 0.5, Y = 1 })
    end
    local dim = newObj("/Script/UMG.Image", ui.tree, "MethCookDim")
    setIcon(dim, "normal", S)
    pcall(function() dim:SetColorAndOpacity(COL_DIM) end)
    local ds = holder:AddChildToCanvas(dim)
    ds:SetPosition({ X = 0, Y = 0 }); ds:SetSize({ X = S, Y = S })
    local clip = newObj("/Script/UMG.CanvasPanel", ui.tree, "MethCookClip")
    pcall(function() clip:SetClipping(1) end)
    local cs = holder:AddChildToCanvas(clip)
    local bright = newObj("/Script/UMG.Image", ui.tree, "MethCookBright")
    setIcon(bright, "normal", S)
    local bs = clip:AddChildToCanvas(bright)
    bs:SetSize({ X = S, Y = S })
    local label = makeText(math.max(8, math.floor(S * 0.2 + 0.5)), COL_TEXT)
    pcall(function() label:SetJustification(2) end)
    local ls = holder:AddChildToCanvas(label)
    ls:SetAutoSize(true)
    ls:SetAnchors({ Minimum = { X = 0, Y = LABEL_Y }, Maximum = { X = 0, Y = LABEL_Y } })
    ls:SetAlignment({ X = 1, Y = 0.5 })
    ls:SetPosition({ X = -LABEL_GAP, Y = 0 })
    local badge = newObj("/Script/UMG.Image", ui.tree, "MethCookBadge")
    local B = math.floor(S * 0.45)
    setIcon(badge, "warn", B)
    pcall(function() badge:SetColorAndOpacity(COL_FIX) end)
    local bgs = holder:AddChildToCanvas(badge)
    bgs:SetSize({ X = B, Y = B })
    bgs:SetAnchors({ Minimum = { X = 1, Y = 0 }, Maximum = { X = 1, Y = 0 } })
    bgs:SetAlignment({ X = 0.75, Y = 0.25 })
    pcall(function() badge:SetVisibility(VIS_COLLAPSED) end)
    local count = makeText(math.max(9, math.floor(S * 0.27 + 0.5)), COL_COUNT)
    local cts = holder:AddChildToCanvas(count)
    cts:SetAutoSize(true)
    -- Right-aligned to the same edge as the ingredient text (just left of the
    -- bag), sitting at the bag's bottom.
    pcall(function() count:SetJustification(2) end)
    cts:SetAnchors({ Minimum = { X = 0, Y = 1 }, Maximum = { X = 0, Y = 1 } })
    cts:SetAlignment({ X = 1, Y = 1 })
    cts:SetPosition({ X = -LABEL_GAP, Y = 0 })
    w.holder, w.slot, w.dim, w.bright, w.clipSlot, w.brightSlot = holder, hs, dim, bright, cs, bs
    local cross = makeText(math.floor(S * 0.8 + 0.5), COL_BOOM)
    pcall(function() cross.Font.OutlineSettings.OutlineSize = 2 end)
    pcall(function() cross:SetText(FText("X")) end)
    local xs = holder:AddChildToCanvas(cross)
    xs:SetAutoSize(true)
    xs:SetAnchors({ Minimum = { X = 0.5, Y = 0.5 }, Maximum = { X = 0.5, Y = 0.5 } })
    xs:SetAlignment({ X = 0.5, Y = 0.5 })
    pcall(function() cross:SetVisibility(VIS_COLLAPSED) end)
    w.cross = cross
    w.cache.cross = false
    w.label, w.badge, w.count = label, badge, count
    w.cache.badge = false
    return w
end

local function setVis(w, key, widget, on)
    if w.cache[key] == on then return end
    w.cache[key] = on
    pcall(function() widget:SetVisibility(on and VIS_HITTEST_INVIS or VIS_COLLAPSED) end)
end

local function applyLook(w, look)
    local c = w.cache
    local S = w.size
    if c.fill ~= look.fill then
        c.fill = look.fill
        local h = S * look.fill
        pcall(function() w.clipSlot:SetPosition({ X = 0, Y = S - h }) end)
        pcall(function() w.clipSlot:SetSize({ X = S, Y = h }) end)
        pcall(function() w.brightSlot:SetPosition({ X = 0, Y = -(S - h) }) end)
    end
    if c.icon ~= look.icon then
        c.icon = look.icon
        setIcon(w.bright, look.icon, S)
        setIcon(w.dim, look.icon, S)
    end
    if c.color ~= look.color then
        c.color = look.color
        pcall(function() w.bright:SetColorAndOpacity(look.color) end)
    end
    if c.label ~= look.label then
        c.label = look.label
        pcall(function() w.label:SetText(FText(look.label)) end)
    end
    if c.countText ~= look.count then
        c.countText = look.count
        pcall(function() w.count:SetText(FText(look.count)) end)
    end
    -- Badge = the game's warning sign. (The "fix" waypoint icon never loads
    -- standalone and drew an empty square.) Retried until the icon is in.
    if look.badge and not c.badgeTex and tex("warn") then
        setIcon(w.badge, "warn", math.floor(S * 0.45)); c.badgeTex = true
    end
    setVis(w, "badge", w.badge, look.badge)
    setVis(w, "cross", w.cross, look.cross or false)
    if look.pulse then
        c.pulsing = true                 -- animated in fastUpdate
    elseif c.pulsing then
        c.pulsing = false
        pcall(function() w.bright:SetRenderOpacity(1) end)
    end
end

---------------------------------------------------------------------------
-- State -> look
---------------------------------------------------------------------------
local function addedCount(a)
    local n = 0
    for _ in pairs(addedBy[a] or {}) do n = n + 1 end
    return n
end

local function nextIngredient(s, a)
    local order = orders[a] and orders[a].list
    if not order or #order == 0 then return "" end
    local step = order[addedCount(a) + 1]
    if step == nil then return "" end
    return s.slots[step + 1] or ""
end

-- Bags the lab can still make. A client may not get the bag list synced (it
-- would read 0), so a client only trusts a non-zero count.
local INFINITY = "\u{221E}"   -- shown instead of a count on labs that never run out
-- Cook Off (its level script is loaded): cooking is unlimited, ingredients are
-- flown in, and the bag fields don't mean "bags left" (NumberOfBags 19, 1 handle).
local cookOffAt, cookOff = -10, false
local function isCookOff()
    local now = os.clock()
    if now - cookOffAt >= 1.0 then
        cookOffAt = now
        cookOff = findLoaded(COOKIE_SCRIPT, lvl.cookie) ~= nil
    end
    return cookOff
end
local function bagsLeft(s)
    if not valid(s.obj) then return nil end
    if isCookOff() then return INFINITY end
    local total = tonumber(getp(s.obj, "NumberOfBags"))
    if total and total <= 1 then return INFINITY end   -- one bag per batch, refilled: unlimited
    local arr = getp(s.obj, "BagHandleArray")
    local n = arr and callm(arr, "GetArrayNum")
    if n == nil then return nil end
    if n == 0 and not s.isHost then return nil end
    return n
end

-- The recipe is only shown once someone has seen the lab's recipe display.
local function recipeKnown(s) return s.witnessed or #(s.boards or {}) == 0 end
-- Cook Off: what Shade has said for the current ingredient. Only what the
-- player has heard. A full instruction line ("Get the muriatic acid") is taken
-- as final: in ~60 logged calls those were right 51/51, and every fake-out was a
-- short one-off line ("Muriatic acid."). A one-off is "maybe" until 5 s pass
-- without a warning, or she follows up. A warning ("Hold up!") always wins.
--   ing = "CS"/"MU"/"HCL" or nil, sure = true/false
local CALL_GROUPS = {
    [16] = { "MU", true },  [17] = { "CS", true },  [18] = { "HCL", true },    -- instruction line (never seen faked)
    [19] = { "MU", false }, [20] = { "CS", false }, [21] = { "HCL", false },   -- one-off call
    [26] = { "MU", true },  [27] = { "CS", true },  [28] = { "HCL", true },    -- correction
}
local function resetCall(why)
    if cookCall.ing ~= nil then log("Cook Off call cleared (%s)", why) end   -- @dev
    cookCall.ing, cookCall.sure, cookCall.ignoredAt = nil, false, nil
end
local function onDialog(name)
    local g = tonumber(name:match("^sha_rmk02_(%d+)$"))
    if not g then return end
    local c = CALL_GROUPS[g]
    -- A sure call stays: the answer never changes within one request, and her
    -- fake-outs come as a one-off call for another ingredient followed by
    -- "hold up" (2026-11-21: twice after a sure HCL). That one-off is ignored,
    -- and so is a "hold up" within 6 s of it. (A "hold up" on its own still
    -- turns the label to "?", as agreed on 2026-11-20.)
    if cookCall.ing and cookCall.sure then
        if c and not c[2] and c[1] ~= cookCall.ing then
            log("Cook Off call: %s? ignored (%s is already sure; one-off line group %d)", c[1], cookCall.ing, g)   -- @dev
            cookCall.ignoredAt = os.clock()
            return
        elseif g == 25 and cookCall.ignoredAt and os.clock() - cookCall.ignoredAt < 6 then
            log("Cook Off call: \"hold up\" ignored (%s is already sure)", cookCall.ing)   -- @dev
            return
        end
    end
    if c then
        -- After a warning, the next call is the correction even if it uses a normal
        -- instruction line (seen: "Connect the tank of hydrogen chloride.").
        local sure = c[2] or cookCall.fakeout
        cookCall.ing, cookCall.sure, cookCall.t, cookCall.fakeout = c[1], sure, os.clock(), false
        cookCall.at = os.clock()            -- when it was said (cookCall.t is the 5 s timer)
        log("Cook Off call: %s%s (line group %d)", c[1], sure and "" or "?", g)   -- @dev
    elseif (g == 29 or g == 24) and cookCall.ing then   -- 29 "...I am N% sure", 24 "Go for it."
        cookCall.sure = true
        log("Cook Off call: %s confirmed", cookCall.ing)   -- @dev
    elseif g == 25 then
        cookCall.ing, cookCall.sure = nil, false
        log("Cook Off call: fake-out (\"hold up\"), waiting for the correction")   -- @dev
        cookCall.fakeout = true
    end
end
local function cookOffLabel(s, a)
    -- Two in: the third is the one left (each batch uses all three once).
    local poured = addedBy[a] or {}
    local n = 0
    for _ in pairs(poured) do n = n + 1 end
    if n == 2 then
        for slot = 1, 3 do if not poured[slot] then return s.slots[slot] or "" end end
    end
    if cookCall.ing then
        -- A fake-out warning comes ~2 s after the call (seen: 2.0 s). No warning
        -- within CALL_TRUST_S = the call stands.
        if not cookCall.sure and cookCall.t and os.clock() - cookCall.t >= CALL_TRUST_S then
            cookCall.sure = true
            log("Cook Off call: %s stands (no warning within %d s)", cookCall.ing, CALL_TRUST_S)   -- @dev
        end
        return cookCall.ing .. (cookCall.sure and "" or "?")
    end
    if cookCall.fakeout then return "?" end
    return ""
end

local function recipeLabel(s, a)
    if isCookOff() then return cookOffLabel(s, a) end
    if s.progressUnknown then return "?" end
    local n = nextIngredient(s, a)
    if n ~= "" and not recipeKnown(s) then return "?" end
    return n
end

local function lookFor(s, a)
    local st = s.state
    local bags = SHOW_BATCHES and bagsLeft(s) or nil
    local look = { fill = 0, icon = "normal", color = COL_IDLE, label = "", badge = false, pulse = false,
                   count = bags and tostring(bags) or "" }
    if st == WAITING or st == SABOTAGED then
        look.fill = math.min(addedCount(a), 3) / 3
        if s.processing then
            look.label = string.rep(".", 1 + math.floor(os.clock() * 2.5) % 3)
        else
            look.label = recipeLabel(s, a)
        end
        if st == SABOTAGED then look.badge, look.color = true, COL_SABOTAGED end
    elseif st == INACTIVE then
        -- Lab not started yet: show the first ingredient, if the recipe is
        -- already known (Party Powder sends it at map load).
        look.label = recipeLabel(s, a)
    elseif st == COOKING or st == UNDER then
        look.fill, look.color, look.pulse = 1, COL_COOK, true
    elseif st == COOKED then
        look.fill, look.icon, look.color = 1, "pure", COL_PERFECT
    elseif st == OVER then
        look.fill, look.icon, look.color = 1, "burnt", COL_BURNT
    elseif st == DESTROYED then
        look.fill, look.color, look.cross, look.count = 1, COL_WRECK, true, ""   -- no batch number on a wrecked lab
    end
    return look
end

-- Debug preview (ModMenu's DEBUG tab, "Next preview look"): steps the HUD icon through every look.
local PREVIEW = {
    { "idle" }, { "recipe not found yet", 0, "?" }, { "0/3, next CS", 0, "CS" }, { "1/3, processing", 1/3, "..." }, { "1/3, next MU", 1/3, "MU" },
    { "2/3, next HCL", 2/3, "HCL" },
    { "sabotaged at 2/3", 2/3, "HCL", "sab" }, { "cooking/raw", "cook" }, { "perfect", "pure" }, { "overcooked", "burnt" },
    { "destroyed (red X)", "boom" },
}
local previewIdx = 0     -- 0 = live
local function previewLook()
    local e = PREVIEW[previewIdx]
    local look = { fill = 0, icon = "normal", color = COL_IDLE, label = "", badge = false, pulse = false, count = "3" }
    if type(e[2]) == "number" then
        look.fill, look.label = e[2], e[3]
        if e[4] == "sab" then look.badge, look.color = true, COL_SABOTAGED end
    elseif e[2] == "cook" then look.fill, look.color, look.pulse = 1, COL_COOK, true
    elseif e[2] == "pure" then look.fill, look.icon, look.color = 1, "pure", COL_PERFECT
    elseif e[2] == "burnt" then look.fill, look.icon, look.color = 1, "burnt", COL_BURNT
    elseif e[2] == "boom" then look.fill, look.color, look.cross, look.count = 1, COL_WRECK, true, "" end
    return look
end

---------------------------------------------------------------------------
-- Per-frame update
---------------------------------------------------------------------------
local enabled = true
local WLL, GPS = nil, nil
local function project(pc, loc)
    if not valid(WLL) then WLL = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary") end
    local out = {}
    local ok, res = pcall(_call, WLL, "ProjectWorldLocationToWidgetPosition", pc, loc, out, false)
    if not ok or not res then return nil end
    local x, y = out.X, out.Y
    if x == nil and out.ScreenPosition then x, y = out.ScreenPosition.X, out.ScreenPosition.Y end
    return x, y
end
local function shouldHide(pc)
    if not HIDE_WHEN_PAUSED then return false end
    if getp(pc, "bShowMouseCursor", false) == true then return true end
    if not valid(GPS) then GPS = StaticFindObject("/Script/Engine.Default__GameplayStatics") end
    return valid(GPS) and callm(GPS, "IsGamePaused", pc) == true
end

---------------------------------------------------------------------------
-- Ingredient markers (IngredientMarkers = true): pickups within GroupRadius of
-- each other share one marker, e.g. "CS 1  MU 2". Counts drop as pickups are
-- taken; a group holding the ingredient you need next is yellow.
---------------------------------------------------------------------------
local PICKUP_ING = { BP_Meth_CausticSoda_C = "CS", BP_Meth_MuriaticAcid_C = "MU", BP_Meth_HydrogenChloride_C = "HCL" }
local ING_ORDER = { "CS", "MU", "HCL" }
local COL_NEEDED = { R = 1.00, G = 0.85, B = 0.20, A = 1 }
local pickups = {}          -- addr -> { obj, ing, loc }
local pickupScan, pickupSince = nil, nil
local groupSig = nil
local function scanPickups()
    -- Pickups are placed at map start (more may arrive later, e.g. Cook Off's
    -- helicopter), so search every 10 s for the first 2 min, then every 30 s.
    local now = os.clock()
    pickupSince = pickupSince or now
    local every = (now - pickupSince < 120) and 10 or 30
    if pickupScan and now - pickupScan < every then return end
    pickupScan = now
    for cn, ing in pairs(PICKUP_ING) do
        for _, o in ipairs(FindAllOf(cn) or {}) do
            if valid(o) and not pickups[addr(o)] then
                local loc = safe(function() return o:K2_GetActorLocation() end)
                if not isGhost(loc) then pickups[addr(o)] = { obj = o, ing = ing, loc = loc } end
            end
        end
    end
end

local function clearIngredientMarkers()
    for _, m in ipairs(ui.ingMarkers or {}) do pcall(function() m.text:RemoveFromParent() end) end
    ui.ingMarkers = {}
    groupSig = nil
end

local function regroup(list)
    clearIngredientMarkers()
    local R2 = (GROUP_RADIUS * 100) ^ 2
    local groups = {}
    for _, pk in ipairs(list) do
        local g = nil
        for _, cand in ipairs(groups) do
            local dx, dy, dz = pk.loc.X - cand.x, pk.loc.Y - cand.y, pk.loc.Z - cand.z
            if dx * dx + dy * dy + dz * dz <= R2 then g = cand; break end
        end
        if not g then
            g = { x = 0, y = 0, z = 0, n = 0, counts = {} }
            groups[#groups + 1] = g
        end
        g.n = g.n + 1
        g.x = g.x + (pk.loc.X - g.x) / g.n
        g.y = g.y + (pk.loc.Y - g.y) / g.n
        g.z = g.z + (pk.loc.Z - g.z) / g.n
        g.counts[pk.ing] = (g.counts[pk.ing] or 0) + 1
    end
    for _, g in ipairs(groups) do
        local parts = {}
        for _, ing in ipairs(ING_ORDER) do
            if g.counts[ing] then parts[#parts + 1] = ing .. " " .. g.counts[ing] end
        end
        local t = makeText(12, COL_TEXT)
        pcall(function() t:SetText(FText(table.concat(parts, "  "))) end)
        local slot = ui.canvas:AddChildToCanvas(t)
        pcall(function() slot:SetAutoSize(true) end)
        pcall(function() slot:SetAlignment({ X = 0.5, Y = 1 }) end)
        ui.ingMarkers[#ui.ingMarkers + 1] = { text = t, slot = slot, g = g, cache = {} }
    end
end

local function updateIngredientMarkers(pc, needed)
    if not INGREDIENT_MARKERS then
        if ui.ingMarkers and #ui.ingMarkers > 0 then clearIngredientMarkers() end
        return
    end
    scanPickups()
    -- Visible pickups (taken ones are hidden by the game, or destroyed).
    local list, sig = {}, {}
    for a, pk in pairs(pickups) do
        if not valid(pk.obj) then pickups[a] = nil
        elseif not safe(function() return pk.obj.bHidden end, false) then
            list[#list + 1] = pk
        end
    end
    table.sort(list, function(x, y) return addr(x.obj) < addr(y.obj) end)
    for i, pk in ipairs(list) do sig[i] = tostring(addr(pk.obj)) end
    local key = table.concat(sig, ",")
    if key ~= groupSig or ui.ingMarkers == nil then
        regroup(list)
        groupSig = key
    end
    for _, m in ipairs(ui.ingMarkers) do
        local hot = needed ~= nil and needed ~= "" and m.g.counts[needed] ~= nil
        if m.cache.hot ~= hot then
            m.cache.hot = hot
            pcall(function() m.text:SetColorAndOpacity({ SpecifiedColor = hot and COL_NEEDED or COL_TEXT, ColorUseRule = 0 }) end)
        end
    end
end
-- Per frame: move the markers with the camera.
local function moveIngredientMarkers(pc)
    if not INGREDIENT_MARKERS or not ui.ingMarkers then return end
    for _, m in ipairs(ui.ingMarkers) do
        local x, y = project(pc, { X = m.g.x, Y = m.g.y, Z = m.g.z + PICKUP_HEIGHT })
        local on = x ~= nil
        if m.cache.on ~= on then
            m.cache.on = on
            pcall(_call, m.text, "SetVisibility", on and VIS_HITTEST_INVIS or VIS_COLLAPSED)
        end
        if on then pcall(_call, m.slot, "SetPosition", { X = x, Y = y }) end
    end
end

-- @dev-begin
---------------------------------------------------------------------------
-- (DebugKeys only) watch the lab's three pour interactions for changes, to
-- find what marks "processing" between pours. Plain values only.
---------------------------------------------------------------------------
local SAFE_KINDS = { FloatProperty = true, DoubleProperty = true, IntProperty = true, ByteProperty = true,
    EnumProperty = true, BoolProperty = true, NameProperty = true, ObjectProperty = true }
local propCache = {}
local function plainProps(obj)
    local c = safe(function() return obj:GetClass() end)
    local ca = addr(c)
    if propCache[ca] then return propCache[ca] end
    local names, seen, st, guard = {}, {}, c, 0
    while valid(st) and guard < 20 do
        guard = guard + 1
        local sn = safe(function() return st:GetFName():ToString() end, "?")
        if sn == "ActorComponent" or sn == "Object" then break end
        pcall(function()
            st:ForEachProperty(function(pr)
                local n = safe(function() return pr:GetFName():ToString() end)
                local k = safe(function() return pr:GetClass():GetFName():ToString() end, "?")
                if n and not seen[n] and SAFE_KINDS[k] then seen[n] = true; names[#names + 1] = n end
            end)
        end)
        st = safe(function() return st:GetSuperStruct() end)
    end
    propCache[ca] = names
    log("watch: %s has %d plain properties", safe(function() return c:GetFName():ToString() end, "?"), #names)
    return names
end
local function snap(obj)
    local out = {}
    for _, n in ipairs(plainProps(obj)) do
        local ok, v = pcall(function() return obj[n] end)
        if ok then
            if type(v) == "number" or type(v) == "boolean" then out[n] = tostring(v)
            elseif valid(v) then out[n] = safe(function() return v:GetFName():ToString() end, "obj") end
        end
    end
    return out
end
local watchAt = 0
local function watchPours()
    if not DEBUG_KEYS then return end
    local now = os.clock()
    if now - watchAt < 0.25 then return end
    watchAt = now
    for a, s in pairs(stations) do
        if valid(s.obj) then
            if not s.inter then
                s.inter = {}
                pcall(function()
                    s.obj.IngredientInteractableArray:ForEach(function(i, e) s.inter[i] = { obj = p(e), snap = nil } end)
                end)
                log("watch: %d pour interactions", #s.inter)
            end
            if not s.outl then
                s.outl = {}
                for k = 1, 3 do
                    local o = safe(function() return s.obj["SBZIngredientOutline" .. k] end)
                    if valid(o) then
                        s.outl[#s.outl + 1] = { obj = o, snap = nil, n = k }
                        local first = snap(o)
                        local parts = {}
                        for kk, vv in pairs(first) do parts[#parts + 1] = kk .. "=" .. vv end
                        table.sort(parts)
                        log("watch: outline%d now: %s", k, table.concat(parts, " "))
                    end
                end
            end
            for _, ot in ipairs(s.outl) do
                if valid(ot.obj) then
                    local cur = snap(ot.obj)
                    if ot.snap then
                        for k, v in pairs(cur) do
                            if ot.snap[k] ~= v then log("watch: outline%d %s: %s -> %s", ot.n, k, tostring(ot.snap[k]), v) end
                        end
                    end
                    ot.snap = cur
                end
            end
            for i, it in ipairs(s.inter) do
                if valid(it.obj) then
                    local cur = snap(it.obj)
                    if it.snap then
                        for k, v in pairs(cur) do
                            if it.snap[k] ~= v then
                                log("watch: pour%d %s: %s -> %s (%.1f s after last pour)", i, k, tostring(it.snap[k]), v,
                                    _G.MethCookLastPour and (now - _G.MethCookLastPour) or -1)
                            end
                        end
                    end
                    it.snap = cur
                end
            end
        end
    end
end
-- @dev-end

---------------------------------------------------------------------------
-- Recipe witness: you saw a recipe display (rendered on your screen within
-- WITNESS_SEE_M), or a teammate stood within WITNESS_NEAR_M of one.
---------------------------------------------------------------------------
local WITNESS_SEE_M, WITNESS_NEAR_M = 10, 4
local WITNESS_CONE = math.cos(math.rad(20))   -- within ~20 degrees of the screen centre
local WITNESS_DWELL = 1.0                     -- seconds of looking at it
local WITNESS_FRONT = -0.5                    -- must be within ~60 degrees of straight in front
-- Line of sight: true if nothing blocks the Visibility channel between the two
-- points. KismetSystemLibrary.LineTraceSingle has no delegate parameters.
-- If the call itself fails, fall back to "visible" (the older behaviour) so
-- the recipe can still be unlocked, and log it once.
local KSL = nil
local function clearSight(pc, from, to, alsoIgnore)
    if not valid(KSL) then KSL = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary") end
    if not valid(KSL) then logOnce("ksl", "line trace unavailable; using render check only"); return true end
    local myPawn = safe(function() return pc.Pawn end)
    local ignore = {}
    if valid(myPawn) then ignore[#ignore + 1] = myPawn end
    if valid(alsoIgnore) then ignore[#ignore + 1] = alsoIgnore end
    local hit = {}
    local ok, blocked = pcall(function()
        return KSL:LineTraceSingle(pc, { X = from.X, Y = from.Y, Z = from.Z }, { X = to.X, Y = to.Y, Z = to.Z },
            0, false, ignore, 0, hit, true,
            { R = 1, G = 0, B = 0, A = 1 }, { R = 0, G = 1, B = 0, A = 1 }, 0)
    end)
    if not ok then logOnce("trace", "line trace failed (%s); using render check only", tostring(blocked)); return true end
    return not blocked
end

-- Visual centre of a display (its pivot may be at floor level). Cached.
local centreCache = {}
local function boundsCentre(b, fallback)
    local a = addr(b)
    if centreCache[a] then return centreCache[a] end
    local o, e = {}, {}
    local ok = pcall(function() b:GetActorBounds(false, o, e, false) end)
    local c = (ok and o.X and (o.X ~= 0 or o.Y ~= 0)) and { X = o.X, Y = o.Y, Z = o.Z } or fallback
    centreCache[a] = c
    return c
end

local function camForward(pc)
    local cm = safe(function() return pc.PlayerCameraManager end)
    local r = valid(cm) and safe(function() return cm:GetCameraRotation() end)
    if not r then return nil end
    local pr, yr = math.rad(r.Pitch), math.rad(r.Yaw)
    return { X = math.cos(pr) * math.cos(yr), Y = math.cos(pr) * math.sin(yr), Z = math.sin(pr) }
end
local witnessAt = 0
local function checkWitness(pc)
    local now = os.clock()
    if now - witnessAt < 0.25 then return end
    witnessAt = now
    local cam = nil
    local pawns = nil
    for a, s in pairs(stations) do
        if not s.witnessed and #s.boards > 0 then
            cam = cam or cameraLoc(pc)
            if pawns == nil then
                pawns = {}
                pcall(function()
                    pc:GetWorld().GameState.PlayerArray:ForEach(function(i, e)
                        local ps = e:get()
                        local pw = valid(ps) and safe(function() return ps:GetPawn() end)
                        if valid(pw) then pawns[#pawns + 1] = pw end
                    end)
                end)
            end
            for bi, b in ipairs(s.boards) do
                if valid(b) and not safe(function() return b.bHidden end, false) then
                    local bl = safe(function() return b:K2_GetActorLocation() end)
                    if bl and not isGhost(bl) then
                        local function dm(l) return math.sqrt((l.X - bl.X) ^ 2 + (l.Y - bl.Y) ^ 2 + (l.Z - bl.Z) ^ 2) / 100 end
                        local looking = false
                        if cam and dm(cam) <= WITNESS_SEE_M and safe(function() return b:WasRecentlyRendered(0.3) end, false) then
                            local fw = camForward(pc)
                            local vx, vy, vz = bl.X - cam.X, bl.Y - cam.Y, bl.Z - cam.Z
                            local len = math.sqrt(vx * vx + vy * vy + vz * vz)
                            if fw and len > 1 and (fw.X * vx + fw.Y * vy + fw.Z * vz) / len >= WITNESS_CONE then
                                -- ...and from the front: the display's readable side faces
                                -- along -forward (a straight-on read logged forward.dot = -1.00;
                                -- the side-window glimpse logged 0.24).
                                local f = safe(function() return b:GetActorForwardVector() end)
                                local hx, hy = cam.X - bl.X, cam.Y - bl.Y
                                local hl = math.sqrt(hx * hx + hy * hy)
                                if not f or hl < 1 or (f.X * hx + f.Y * hy) / hl <= WITNESS_FRONT then
                                    -- ...and nothing in between: "was rendered" alone also passed
                                    -- through walls. Trace to a point 25 cm in front of the display
                                    -- (tracing to the display itself would hit the display).
                                    local bc = boundsCentre(b, bl)
                                    local tgt = f and { X = bc.X - f.X * 25, Y = bc.Y - f.Y * 25, Z = bc.Z - f.Z * 25 } or bc
                                    if clearSight(pc, cam, tgt, b) then looking = true end
                                end
                            end
                        end
                        if looking then
                            s.look = s.look or {}; s.look[addr(b)] = s.look[addr(b)] or now
                            if now - s.look[addr(b)] >= WITNESS_DWELL then
                                s.witnessed = true
                                -- @dev-begin
                                -- log which way the display faces relative to us (to add a "from the front" check later)
                                local f = safe(function() return b:GetActorForwardVector() end)
                                local rt = safe(function() return b:GetActorRightVector() end)
                                local vx, vy = cam.X - bl.X, cam.Y - bl.Y
                                local l2 = math.sqrt(vx * vx + vy * vy)
                                log("recipe seen by you at display %d (%.1f m); display forward.dot=%.2f right.dot=%.2f", bi, dm(cam),
                                    f and l2 > 0 and (f.X * vx + f.Y * vy) / l2 or 9, rt and l2 > 0 and (rt.X * vx + rt.Y * vy) / l2 or 9)
                                -- @dev-end
                            end
                        else
                            if s.look then s.look[addr(b)] = nil end
                            -- Teammates (not you: you're covered by the look rule) standing
                            -- close to the display AND in front of it (not behind a wall).
                            local myPawn = safe(function() return pc.Pawn end)
                            local f = safe(function() return b:GetActorForwardVector() end)
                            for _, pw in ipairs(pawns) do
                                local pl = (addr(pw) ~= addr(myPawn)) and safe(function() return pw:K2_GetActorLocation() end)
                                if pl and dm(pl) <= WITNESS_NEAR_M then
                                    local hx, hy = pl.X - bl.X, pl.Y - bl.Y
                                    local hl = math.sqrt(hx * hx + hy * hy)
                                    local side = (f and hl >= 1) and (f.X * hx + f.Y * hy) / hl or -1
                                    if side <= WITNESS_FRONT then
                                        s.witnessed = true
                                        log("recipe seen by a teammate at display %d (%.1f m, forward.dot=%.2f)", bi, dm(pl), side)   -- @dev
                                        break
                                    end
                                end
                            end
                        end
                    end
                end
                if s.witnessed then break end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Cook Off dialogue: which Shade line is playing. Read from the dialog
-- manager's ActiveDialogs map (dialog asset names, e.g. sha_rmk02_17), ten
-- times a second, Cook Off only. No hooks; the manager is searched for once
-- (then every 10 s until found).
---------------------------------------------------------------------------
local dlg = { mgr = nil, lastFind = -100, prev = {}, at = 0, broken = false }
local function watchDialog()
    if dlg.broken or not isCookOff() then return end
    local now = os.clock()
    if now - dlg.at < 0.1 then return end
    dlg.at = now
    if not valid(dlg.mgr) then
        if now - dlg.lastFind < 10 then return end
        dlg.lastFind = now
        for _, m in ipairs(FindAllOf("SBZDialogManager") or {}) do if valid(m) then dlg.mgr = m; break end end
        if not valid(dlg.mgr) then logOnce("dlgmgr", "Cook Off: dialog manager not found yet"); return end   -- @dev
    end
    local cur = {}
    local ok, err = pcall(function()
        dlg.mgr.ActiveDialogs:ForEach(function(k, v)
            local key = safe(function() return k:get() end, k)
            local n = valid(key) and safe(function() return key:GetFName():ToString() end) or nil
            if n then cur[n] = true end
        end)
    end)
    if not ok then
        dlg.broken = true
        log("Cook Off: dialog list not readable (%s); calls won't show", tostring(err))
        return
    end
    -- A line only counts once it has played for DIALOG_MIN_S: lines that get
    -- cut off (or dropped) almost immediately were never really heard.
    dlg.since = dlg.since or {}
    for n in pairs(cur) do
        if not dlg.prev[n] then
            dlg.since[n] = now
            if DEBUG_KEYS then log("dialog start: %s", n) end   -- @dev
        end
        if dlg.since[n] and now - dlg.since[n] >= DIALOG_MIN_S then
            dlg.since[n] = nil          -- counted once
            onDialog(n)
        end
    end
    for n in pairs(dlg.prev) do
        if not cur[n] and dlg.since[n] then
            if DEBUG_KEYS then log("dialog cut after %.1f s, ignored: %s", now - dlg.since[n], n) end   -- @dev
            dlg.since[n] = nil
        end
    end
    dlg.prev = cur
    -- @dev-begin
    -- (DebugKeys) what's actually on screen, to compare with the list above
    if DEBUG_KEYS then
        if not valid(dlg.sub) and now - (dlg.subFind or -100) >= 10 then
            dlg.subFind = now
            for _, cn in ipairs({ "WBP_UI_Widget_Subtitles_C", "SBZSubtitleWidget" }) do
                for _, w in ipairs(FindAllOf(cn) or {}) do
                    if valid(w) and valid(safe(function() return w.Text_SubtitleText end)) then dlg.sub = w; break end
                end
                if valid(dlg.sub) then break end
            end
            logOnce("subw", "subtitle text block %s", valid(dlg.sub) and "found" or "not found (subtitles off?)")
        end
        if valid(dlg.sub) then
            local txt = safe(function() return dlg.sub.Text_SubtitleText:GetText():ToString() end)
            local vis = safe(function() return dlg.sub:IsVisible() end)
            local key = tostring(txt) .. "|" .. tostring(vis)
            if key ~= dlg.lastSub then
                dlg.lastSub = key
                log("subtitle on screen (visible=%s): \"%s\"", tostring(vis), tostring(txt))
            end
        end
    end
    -- @dev-end
end

local function update(pc)
    ui.live = false
    scanStations()
    checkWitness(pc)
    watchPours()   -- @dev
    watchDialog()
    if next(stations) == nil and previewIdx == 0 then
        if valid(ui.root) and ui.rootVis ~= VIS_COLLAPSED then
            ui.rootVis = VIS_COLLAPSED
            pcall(function() ui.root:SetVisibility(VIS_COLLAPSED) end)
        end
        return
    end

    -- State tracking (replicated CurrentState, so this also works as a client).
    for a, s in pairs(stations) do
        if not valid(s.obj) then   -- lab gone between searches: drop it now
            if s.widget then pcall(function() s.widget.holder:RemoveFromParent() end) end
            stations[a] = nil
        end
    end
    if next(stations) == nil and previewIdx == 0 then return end
    for a, s in pairs(stations) do
        local stv = tonumber(getp(s.obj, "CurrentState"))
        if stv ~= nil and stv ~= s.state then
            local old = s.state
            s.state = stv
            if old == nil then
                s.isHost = safe(function() return s.obj:HasAuthority() end, false)
                -- First seen already waiting = we joined (or reloaded) mid-batch:
                -- pours before now were missed. Rebuilt on the next pour.
                -- Only if the heist has been running a while (late join / reload); at a
                -- normal start a lab can already be waiting with nothing poured.
                if stv == WAITING or stv == SABOTAGED then
                    local t = tonumber(safe(function() return pc:GetWorld().GameState:GetServerWorldTimeSeconds() end))
                    if t == nil or t > 120 then s.progressUnknown = true end
                    if s.progressUnknown then log("lab first seen mid-batch (heist time %s s): progress unknown until the next pour", t and string.format("%.0f", t) or "?") end   -- @dev
                end
            end
            -- Power back: keep her last call as it was. The ingredient doesn't
            -- change (a host log showed the same one before and after), and she
            -- re-announces ~25 s later; any new call replaces it.
            -- Power cut while a call is still "maybe": the blackout's lines may
            -- have cut off her warning, so stop the 5 s timer. It stays "?"
            -- until she speaks again.
            if stv == SABOTAGED and cookCall.ing and not cookCall.sure and cookCall.t then
                cookCall.t = nil
                log("Cook Off call: %s? stays unsure (power cut inside the warning window)", cookCall.ing)   -- @dev
            end
            if stv == WAITING and old == SABOTAGED and cookCall.ing then
                log("Cook Off call: %s kept after the power cut", cookCall.ing)   -- @dev
            end
            if stv == WAITING and old ~= nil and old ~= SABOTAGED and old ~= WAITING then
                -- her first call can arrive in the same moment the batch starts
                -- (the state is polled ~10x/s): keep a call from the last 2 s
                if cookCall.ing and cookCall.at and os.clock() - cookCall.at < 2 then
                    log("Cook Off call: %s kept (said as the new batch started)", cookCall.ing)   -- @dev
                else
                    resetCall("new batch")
                end
                clearTable(addedBy[a] or {})          -- new batch
                s.progressUnknown = false
            end
            if stv == COOKING or stv == UNDER or stv == COOKED or stv == OVER then
                s.progressUnknown = false
                if not s.witnessed then log("recipe known: the lab is cooking") end   -- @dev
                s.witnessed = true                    -- nobody cooks without the recipe
            end
            if stv == COOKED and old ~= nil and READY_SOUND then playReady(pc) end
            log("lab: %s -> %s", STATE_NAMES[old] or "start", STATE_NAMES[stv] or tostring(stv))   -- @dev
        end
        if not s.witnessed then
            local total = tonumber(safe(function() return s.obj.NumberOfBags end))
            local left = bagsLeft(s)
            if total and total > 1 and type(left) == "number" and left < total then
                s.witnessed = true
                log("recipe known: %d of %d bags already made", total - left, total)   -- @dev
            end
        end
        -- "Processing": after a pour the game disables all three pour points
        -- until the lab is ready for the next ingredient (seen: 15-26 s).
        -- Only trusted once we've seen a pour point enabled on this lab, in case
        -- the flag doesn't reach clients.
        if not s.pours then
            s.pours = {}
            pcall(function()
                s.obj.IngredientInteractableArray:ForEach(function(i, e) s.pours[#s.pours + 1] = p(e) end)
            end)
        end
        local anyOn = false
        for _, it in ipairs(s.pours) do
            if valid(it) and getp(it, "bInteractionEnabled", false) then anyOn = true; break end
        end
        if anyOn then s.sawPourEnabled = true end
        local busy = (s.sawPourEnabled and s.state == WAITING and addedCount(a) > 0 and addedCount(a) < 3 and not anyOn) and true or false
        if busy ~= (s.processing or false) then
            s.processing = busy
            log("lab: %s", busy and "processing pour" or "ready for next ingredient")   -- @dev
        end
    end

    if not ensureRoot(pc) then return end
    local hide = (not enabled) or shouldHide(pc)
    local want = hide and VIS_COLLAPSED or VIS_HITTEST_INVIS
    if ui.rootVis ~= want then
        ui.rootVis = want
        pcall(function() ui.root:SetVisibility(want) end)
    end
    if hide then return end
    ui.live = true

    -- HUD: nearest station.
    local cam = cameraLoc(pc)
    local nearA, nearD = nil, 1e30
    for a, s in pairs(stations) do
        local d = cam and ((s.loc.X - cam.X) ^ 2 + (s.loc.Y - cam.Y) ^ 2 + (s.loc.Z - cam.Z) ^ 2) or 0
        if d < nearD then nearA, nearD = a, d end
    end
    if STYLE == "hud" or STYLE == "both" or previewIdx > 0 then
        if not ui.hud then ui.hud = makeIcon(true) end
        if previewIdx > 0 then applyLook(ui.hud, previewLook())
        elseif nearA then applyLook(ui.hud, lookFor(stations[nearA], nearA)) end
    end
    if STYLE == "world" or STYLE == "both" then
        for a, s in pairs(stations) do
            if not s.widget then s.widget = makeIcon(false) end
            applyLook(s.widget, lookFor(s, a))      -- position: fastUpdate
        end
    end
    local needed = nil
    local ns = nearA and stations[nearA].state
    if ns == WAITING or ns == SABOTAGED or ns == INACTIVE then
        needed = recipeKnown(stations[nearA]) and nextIngredient(stations[nearA], nearA) or nil
    end
    updateIngredientMarkers(pc, needed)
end

-- Per frame, only what moves: the cooking pulse (30x/s) and, in world style,
-- icon positions. Nothing at all when the icon is hidden or there's no lab.
local pulseAt = 0
local function pulse(w, o)
    if w and w.cache.pulsing then pcall(_call, w.bright, "SetRenderOpacity", o) end
end
local function fastUpdate(pc)
    if not ui.live then return end
    local now = os.clock()
    if now - pulseAt >= 1 / 30 then
        pulseAt = now
        local o = 0.65 + 0.35 * (0.5 + 0.5 * math.sin(now * 2.5))
        pulse(ui.hud, o)
        for _, s in pairs(stations) do pulse(s.widget, o) end
    end
    if STYLE == "world" or STYLE == "both" then
        for _, s in pairs(stations) do
            local w = s.widget
            if w then
                local x, y = project(pc, { X = s.loc.X, Y = s.loc.Y, Z = s.loc.Z + WORLD_HEIGHT })
                setVis(w, "holder", w.holder, x ~= nil)
                if x then pcall(_call, w.slot, "SetPosition", { X = x, Y = y }) end
            end
        end
    end
    moveIngredientMarkers(pc)
end

---------------------------------------------------------------------------
-- Keys, level change, main loop
---------------------------------------------------------------------------
local KEYS = {}
-- the two keys from settings.ini (rebuilt when the settings are reloaded)
local MM = { seen = nil, at = 0,   -- ModMenu live settings (one table: Lua's 200-locals limit)
    NEXT_STYLE = { hud = "world", world = "both", both = "hud" } }
function MM.buildKeys()
    for i = #KEYS, 1, -1 do if KEYS[i].setting then table.remove(KEYS, i) end end
    if TOGGLE_KEY ~= "" and TOGGLE_KEY ~= "NONE" then
        KEYS[#KEYS + 1] = { name = TOGGLE_KEY, setting = true, fn = function() enabled = not enabled end }
    end
    if STYLE_KEY ~= "" and STYLE_KEY ~= "NONE" and STYLE_KEY ~= TOGGLE_KEY then
        KEYS[#KEYS + 1] = { name = STYLE_KEY, setting = true, fn = function()
            STYLE = MM.NEXT_STYLE[STYLE] or "hud"
            -- Drop the icons the new style doesn't use; update() creates the ones it needs.
            if STYLE == "world" and ui.hud then
                pcall(function() ui.hud.holder:RemoveFromParent() end); ui.hud = nil
            end
            if STYLE == "hud" then
                for _, st in pairs(stations) do
                    if st.widget then pcall(function() st.widget.holder:RemoveFromParent() end); st.widget = nil end
                end
            end
            log("style: %s", STYLE)
        end }
    end
end
MM.buildKeys()

-- settings.ini changed (from ModMenu): read it again; the icons and ingredient
-- markers are rebuilt with the new size / position / colours on the next update
function MM.reloadSettings()
    local before = #SETTINGS_LOG
    loadSettings()
    MM.buildKeys()
    if ui.hud then pcall(function() ui.hud.holder:RemoveFromParent() end); ui.hud = nil end
    for _, st in pairs(stations) do
        if st.widget then pcall(function() st.widget.holder:RemoveFromParent() end); st.widget = nil end
    end
    if ui.ingMarkers then clearIngredientMarkers() end
    log("settings reloaded (style=%s, %s = on/off, %s = switch style, ingredient markers=%s)",
        STYLE, TOGGLE_KEY, STYLE_KEY, tostring(INGREDIENT_MARKERS))
    for i = before + 1, #SETTINGS_LOG do log("%s", SETTINGS_LOG[i]) end
end
---------------------------------------------------------------------------
-- Live settings: ModMenu (the in-game settings menu) sets the shared
-- variable "ModMenu.changed.<this folder>" after it saves our settings.ini.
-- Checked twice a second; without ModMenu it never changes.
---------------------------------------------------------------------------
MM.var = "ModMenu.changed." .. (((debug and debug.getinfo and debug.getinfo(1, "S").source) or "")
    :match("([^/\\]+)[/\\]Scripts[/\\][^/\\]*$") or "MethCook")
function MM.check()
    local now = os.clock()
    if now < MM.at then return end
    MM.at = now + 0.5
    if ModRef == nil then return end
    if MM.debugCheck then MM.debugCheck() end
    local ok, v = pcall(ModRef.GetSharedVariable, ModRef, MM.var)
    if not ok or v == nil or v == MM.seen then return end
    MM.seen = v
    local ok2, err = pcall(MM.reloadSettings)
    if not ok2 then log("settings reload failed: %s", tostring(err)) end
end
-- @dev-begin
-- Debug actions for ModMenu's DEBUG tab (dev builds; shown when its Debug setting is on). The
-- list goes out in "ModMenu.debug.<folder>" (one "id<TAB>label<TAB>description"
-- per line). ModMenu asks for one with "ModMenu.run.<folder>" = "id#stamp" and
-- gets "id#stamp<TAB>result" back in "ModMenu.reply.<folder>".
MM.folder = MM.var:match("^ModMenu%.changed%.(.+)$")
MM.actions = {}
function MM.action(id, label, desc, fn) MM.actions[#MM.actions + 1] = { id = id, label = label, desc = desc, fn = fn } end
function MM.debugCheck()
    if #MM.actions == 0 then return end           -- (dev builds; ModMenu shows them when its Debug setting is on)
    if not MM.published then
        local lines = {}
        for _, a in ipairs(MM.actions) do lines[#lines + 1] = a.id .. "\t" .. a.label .. "\t" .. (a.desc or "") end
        MM.published = pcall(ModRef.SetSharedVariable, ModRef, "ModMenu.debug." .. MM.folder, table.concat(lines, "\n"))
    end
    local ok, r = pcall(ModRef.GetSharedVariable, ModRef, "ModMenu.run." .. MM.folder)
    r = (ok and type(r) == "string") and r or ""
    if MM.lastRun == nil then MM.lastRun = r; return end   -- first look: a request from before a reload is old
    if r == MM.lastRun then return end
    MM.lastRun = r
    local id = r:match("^(.-)#")
    for _, a in ipairs(MM.actions) do
        if a.id == id then
            local ok2, res = pcall(a.fn)
            res = ok2 and tostring(res or "done") or ("error: " .. tostring(res))
            log("debug action %s: %s", id, res)
            pcall(ModRef.SetSharedVariable, ModRef, "ModMenu.reply." .. MM.folder, r .. "\t" .. res)
        end
    end
end
-- @dev-end
-- @dev-begin
function MM.nextPreview()
    previewIdx = (previewIdx + 1) % (#PREVIEW + 1)
    local what = previewIdx == 0 and "off (live)" or PREVIEW[previewIdx][1]
    log("preview: %s", what)
    if previewIdx == 0 and STYLE == "world" and ui.hud then
        pcall(function() ui.hud.holder:RemoveFromParent() end); ui.hud = nil
    end
    return "preview: " .. what
end
function MM.toggleMarkers()
    INGREDIENT_MARKERS = not INGREDIENT_MARKERS
    log("ingredient markers: %s", INGREDIENT_MARKERS and "on" or "off")
    return "ingredient markers " .. (INGREDIENT_MARKERS and "on" or "off")
end
-- @dev-end
-- @dev-begin
MM.action("preview", "Next preview look", "Cycles the icon through every look, anywhere (no lab needed). The last step goes back to live.", MM.nextPreview)
MM.action("markers", "Ingredient markers on/off", "Shows or hides the markers over ingredient pickups.", MM.toggleMarkers)
-- @dev-end

local function pollKeys(pc)
    for _, k in ipairs(KEYS) do
        if not k.fkey then k.fkey = { KeyName = FName(k.name) } end
        local ok, down = pcall(_call, pc, "WasInputKeyJustPressed", k.fkey)
        if ok and down then
            local ok2, err = pcall(k.fn, pc)
            if not ok2 then logOnce("key:" .. tostring(err), "key %s error: %s", k.name, tostring(err)) end
        end
    end
end

local curWorld, pauseUntil = nil, 0
local function resetAll()
    if valid(ui.root) then pcall(function() ui.root:RemoveFromParent() end) end
    ui = {}
    clearTable(stations); clearTable(addedBy); clearTable(pickups); clearTable(centreCache)
    liveRequired.idx = nil   -- @dev
    dlg.mgr, dlg.prev, dlg.broken = nil, {}, false
    cookCall.ing, cookCall.sure, cookCall.fakeout = nil, false, false
    pickupScan, pickupSince, groupSig = nil, nil, nil
    lastScan, classCheckAt = nil, nil
    -- Keep only recipes that just arrived (during this level's load).
    for k, v in pairs(orders) do if os.clock() - v.t > 20 then orders[k] = nil end end
    if pcCache then deadPC[addr(pcCache)] = true end
    pcCache = nil
    curWorld = nil
    lvl.noPC, lvl.name = true, ""          -- treat the pause after a level change as loading
    pauseUntil = os.clock() + 3
end

-- @dev-begin
-- PerfLog: time per section of frame() (seconds, summed over the 10 s window)
local sec = { hooks = 0, pc = 0, keys = 0, slow = 0, fast = 0 }
local function bench(n, f)
    local c0 = os.clock()
    for _ = 1, n do f() end
    return (os.clock() - c0) / n * 1e6      -- microseconds per call
end
local function runBench(pc)
    sec.benchDone = true
    local fk = { KeyName = FName("F7") }
    local r = {
        string.format("os.clock %.1f", bench(500, function() return os.clock() end)),
        string.format("IsValid %.1f", bench(300, function() return valid(pc) end)),
        string.format("WasInputKeyJustPressed %.1f", bench(300, function() return pcall(_call, pc, "WasInputKeyJustPressed", fk) end)),
        string.format("read bShowMouseCursor %.1f", bench(300, function() return getp(pc, "bShowMouseCursor") end)),
        string.format("GetWorld %.1f", bench(300, function() return callm(pc, "GetWorld") end)),
        string.format("StaticFindObject(found) %.1f", bench(100, function() return StaticFindObject("/Script/Engine.Default__GameplayStatics") end)),
        string.format("StaticFindObject(lab, not loaded here) %.1f", bench(5, function() return StaticFindObject(STATION_BP) end)),
    }
    log("bench, microseconds per call: %s", table.concat(r, ", "))
end
-- @dev-end
local SLOW_EVERY = 0.095      -- lab update ~10x/s (a hook can request one sooner)
local slowAt, slowRuns = -1, 0
local function frame()
    local P = PERF_LOG   -- @dev
    local t = P and os.clock()   -- @dev
    -- Hooks first: the recipe event fires while the map is still loading.
    tryHooks()
    local now = os.clock()
    if P then sec.hooks = sec.hooks + (now - t); t = now end   -- @dev
    if now < pauseUntil then return end
    if next(deadPC) and now - pauseUntil > 30 then clearTable(deadPC) end
    local pc = localPC()
    lvl.noPC = (pc == nil)
    if P then local c = os.clock(); sec.pc = sec.pc + (c - t); t = c end   -- @dev
    if not pc then return end
    if P and not sec.benchDone and now - pauseUntil > 15 then runBench(pc); return end   -- @dev
    pollKeys(pc)                            -- "just pressed" is only true for one frame
    if P then local c = os.clock(); sec.keys = sec.keys + (c - t); t = c end   -- @dev
    if dirty or now - slowAt >= SLOW_EVERY then
        dirty, slowAt, slowRuns = false, now, slowRuns + 1
        local wa = addr(callm(pc, "GetWorld"))
        if curWorld ~= nil and wa ~= curWorld then
            -- Recipes (keyed by station address) are kept: the new level's recipe
            -- usually arrives during the load, before this reset runs.
            resetAll()
            return
        end
        if curWorld == nil and wa ~= 0 then
            local w = callm(pc, "GetWorld")
            local fn = w and callm(w, "GetFName")
            lvl.name = tostring(fn and callm(fn, "ToString") or ""):lower()
            log("map: %s (lab lookups %s)", lvl.name, lvl.on(lvl.meth) and "on" or "off after loading")
        end
        curWorld = wa ~= 0 and wa or nil
        if wa == 0 then ui.live = false; return end
        local ok, err = pcall(update, pc)
        if not ok then logOnce("upd:" .. tostring(err), "update error: %s", tostring(err)) end
    end
    if P then local c = os.clock(); sec.slow = sec.slow + (c - t); t = c end   -- @dev
    local ok, err = pcall(fastUpdate, pc)
    if not ok then logOnce("fast:" .. tostring(err), "fast update error: %s", tostring(err)) end
    if P then sec.fast = sec.fast + (os.clock() - t) end   -- @dev
end

-- @dev-begin
-- PerfLog = true: every 10 s, the mod's own time per frame and the Lua garbage
-- it makes (os.clock has ~1 ms steps, so the average is over many frames).
local pf = { t0 = os.clock(), n = 0, sum = 0, worst = 0, kb = 0, slow0 = 0 }
local function perfFrame()
    local m0 = collectgarbage("count")
    local c0 = os.clock()
    local ok, err = pcall(frame)
    local dt = os.clock() - c0
    local m1 = collectgarbage("count")
    if not ok then logOnce("frame:" .. tostring(err), "frame error: %s", tostring(err)) end
    pf.n, pf.sum = pf.n + 1, pf.sum + dt
    if dt > pf.worst then pf.worst = dt end
    if m1 > m0 then pf.kb = pf.kb + (m1 - m0) end
    local span = c0 - pf.t0
    if span >= 10 then
        log("perf: %d frames in %.0f s, avg %.3f ms, worst %.1f ms, %d lab updates, garbage %.1f KB/s, Lua memory %.0f KB, %d lab(s)",
            pf.n, span, pf.sum / pf.n * 1000, pf.worst * 1000, slowRuns - pf.slow0, pf.kb / span, m1, (function()
                local k = 0; for _ in pairs(stations) do k = k + 1 end; return k end)())
        local f = 1000 / pf.n
        log("perf sections, ms per frame: hooks %.3f, find player %.3f, keys %.3f, lab update %.3f, fast %.3f",
            sec.hooks * f, sec.pc * f, sec.keys * f, sec.slow * f, sec.fast * f)
        for _, k in ipairs({ "hooks", "pc", "keys", "slow", "fast" }) do sec[k] = 0 end
        pf.t0, pf.n, pf.sum, pf.worst, pf.kb, pf.slow0 = c0, 0, 0, 0, 0, slowRuns
    end
end
-- @dev-end

LoopInGameThreadAfterFrames(1, function()
    MM.check()
    if PERF_LOG then perfFrame(); return false end   -- @dev
    local ok, err = pcall(frame)
    if not ok then logOnce("frame:" .. tostring(err), "frame error: %s", tostring(err)) end
    return false
end)

log("1.0.0 loaded (style=%s, %s = on/off, %s = switch style, ingredient markers=%s)", STYLE, TOGGLE_KEY, STYLE_KEY, tostring(INGREDIENT_MARKERS))
for _, l in ipairs(SETTINGS_LOG) do log("%s", l) end
if DEBUG_KEYS then log("extra Cook Off logging ON") end   -- @dev
if PERF_LOG then log("perf log ON (every 10 s)") end   -- @dev
