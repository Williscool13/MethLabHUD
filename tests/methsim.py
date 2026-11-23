import lupa.lua54 as lupa, sys
L = lupa.LuaRuntime()
L.execute(r'''
clock = 0
os.clock = function() return clock end
local function obj(fields)
  local o = fields or {}
  o.__valid = true
  local mt = {}
  mt.__index = function(t, k)
    if k == "IsValid" then return function(self) return self.__valid end end
    if k == "GetAddress" then return function(self) return self.__addr end end
    return function(self, ...) return rawget(t, "__ret_" .. k) end
  end
  return setmetatable(o, mt)
end
_G.obj = obj
local n = 0
texts = {}; calls = {}
local function W() n = n + 1; local o = obj({ __addr = 1000 + n }); o.Font = { OutlineSettings = {} }
  o.SetText = function(self, s) texts[#texts+1] = s end
  o.SetBrushResourceObject = function(self, t) calls[#calls+1] = "icon:" .. tostring(t.__path) end
  return o end
function FName(s) return s end
function FText(s) return s end
logs = {}
function print(...) local s = table.concat({...}, " "); logs[#logs+1] = s; io.write(s) end
function StaticFindObject(p)
  if p:find("G_Cookie_Scripting") and not COOKOFF then return nil end
  if p:find("WidgetLayoutLibrary") then
    return obj({ __addr = 7, ProjectWorldLocationToWidgetPosition = function(self, pc, loc, out) out.X = 100; out.Y = 200; return true end })
  end
  if p:find("GameplayStatics") and not p:find("Ak") then return obj({ __addr = 8, IsGamePaused = function() return false end }) end
  if p:find("AkGameplayStatics") then return obj({ __addr = 11, PostEventAtLocation = function(self, ev, l, r, pc) sounds = (sounds or 0) + 1; return 1 end }) end
  local o = obj({ __addr = 9, __path = p }); sfo = sfo or {}; sfo[#sfo + 1] = o; return o
end
function LoadAsset(p) return obj({ __addr = 10, __path = p }) end
function StaticConstructObject(c, outer, name)
  local o = W(); o.__name = name
  o.AddChildToCanvas = function() return W() end
  o.IsInViewport = function() return true end
  o.GetFName = function() return { ToString = function() return name end } end
  return o
end
hooks = {}
function RegisterHook(path, fn) hooks[path:match(":(.*)$")] = fn; return 1, 1 end
loops = {}
function LoopInGameThreadAfterFrames(n, fn) loops[#loops + 1] = fn end
world = obj({ __addr = 500, GetFName = function() return { ToString = function() return "Bust" end } end })
pc = obj({ __addr = 700, bShowMouseCursor = false,
  IsLocalController = function() return true end,
  GetWorld = function() return world end,
  WasInputKeyJustPressed = function() return false end,
  PlayerCameraManager = obj({ __addr = 701, GetCameraLocation = function() return { X = 0, Y = 0, Z = 0 } end }) })
local function meshComp(name) return obj({ __addr = math.random(5000,9000), StaticMesh = obj({ __addr = 1, GetFName = function() return { ToString = function() return name end } end }) }) end
bags = obj({ GetArrayNum = function() return 4 end })
station = obj({ __addr = 800, CurrentState = 0, BagHandleArray = bags,
  K2_GetActorLocation = function() return { X = 7008, Y = 476, Z = 160 } end,
  Ingredient1 = meshComp("SM_Something"), Ingredient2 = meshComp("x"), Ingredient3 = meshComp("y") })
ghost = obj({ __addr = 801, CurrentState = 0, K2_GetActorLocation = function() return { X = 0, Y = 0, Z = 0 } end })
function FindAllOf(c)
  if c == "PlayerController" then return { pc } end
  if c == "BP_MethCookingStation_C" then return { ghost, station } end
  return {}
end
function tick(sec) for i = 1, math.floor(sec * 10) do clock = clock + 0.1; for _, f in ipairs(loops) do f() end end end
function param(v) return { get = function() return v end } end
function arr(t) return { get = function() return { ForEach = function(self, f) for i, v in ipairs(t) do f(i, param(v)) end end } end } end
''')
L.execute(open(sys.argv[1], encoding='utf-8').read())
L.execute(r'''
tick(1)
assert(hooks.BP_OnStaticOrderGenerated, "hooks not registered")
hooks.BP_OnStaticOrderGenerated(param(station), arr({2,0,1}))
tick(4)
station.CurrentState = 1; tick(1)
local function lastText() for i = #texts, 1, -1 do local s = texts[i]; if s:match("^%u+$") then return s end end return "?" end
print("next after start: " .. tostring(lastText()) .. "\n"); assert(lastText() == "HCL")
hooks.BP_OnIngredientAdded(param(station), param(3)); tick(0.5)
print("next after 1: " .. lastText() .. "\n"); assert(lastText() == "MU")
station.CurrentState = 6; tick(1)
station.CurrentState = 1; tick(1)
hooks.BP_OnIngredientAdded(param(station), param(1)); tick(0.5)
print("next after 2: " .. lastText() .. "\n"); assert(lastText() == "CS")
station.CurrentState = 2; hooks.BP_OnIngredientAdded(param(station), param(2)); tick(1)
station.CurrentState = 3; tick(1)
station.CurrentState = 4; tick(1)
assert(sounds == 1, "sound not played once")
station.CurrentState = 1; tick(1)
print("next after new batch: " .. lastText() .. "\n"); assert(lastText() == "HCL")
station.CurrentState = 5; tick(1); station.CurrentState = 7; tick(1)
-- level change
world = obj({ __addr = 501 }); tick(5)
print("OK\n")
''')
if len(sys.argv) > 2: L.execute(open(sys.argv[2], encoding="utf-8").read())
