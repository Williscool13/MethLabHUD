-- Cook Off call tracking, replaying the real dialogue sequence from the 01:40 log
COOKOFF = true
world = obj({ __addr = 601, GetFName = function() return { ToString = function() return "Cookie" end } end })
function lastLabel() for i = #texts, 1, -1 do local s = texts[i]; if s:match("^%u+%??$") or s:match("^%.+$") or s == "?" or s == "" then return s end end return "?none" end
pc = obj({ __addr = 702, bShowMouseCursor = false, IsLocalController = function() return true end, GetWorld = function() return world end, WasInputKeyJustPressed = function() return false end, PlayerCameraManager = obj({ __addr = 703, GetCameraLocation = function() return { X = 0, Y = 0, Z = 0 } end }) })
local active = {}
local function asset(n) return obj({ GetFName = function() return { ToString = function() return n end } end }) end
local mgr = obj({ __addr = 8801, ActiveDialogs = { ForEach = function(self, f) for _, n in ipairs(active) do f(param(asset(n)), param({})) end end } })
cst = obj({ __addr = 990, CurrentState = 1, NumberOfBags = 19, BagHandleArray = { GetArrayNum = function() return 1 end }, K2_GetActorLocation = function() return { X = 5, Y = 5, Z = 5 } end })
FindAllOf = (function(orig) return function(c) if c == "SBZDialogManager" then return { mgr } elseif c == "BP_MethCookingStation_C" then return { cst } end return orig(c) end end)(FindAllOf)
tick(5); hooks.ReceiveBeginPlay(param(cst)); station.__valid = false; tick(1)
local function say(n) active = { n }; tick(1.3); active = {}; tick(0.3) end
local function blip(n) active = { n }; tick(0.5); active = {}; tick(0.3) end
local function check(what, want) local got = lastLabel(); print(what .. ": " .. got .. "\n"); assert(got == want, what) end
say("sha_rmk02_22"); say("sha_rmk02_17"); check("instruction line CS = sure", "CS")
say("sha_rmk02_29"); check("confirmed", "CS")
hooks.BP_OnIngredientAdded(param(cst), param(2)); tick(0.5); check("after pour 1", "")
say("sha_rmk02_22"); say("sha_rmk02_16"); say("sha_lvl00_17"); check("MU call, other chatter", "MU")
say("sha_rmk02_29"); check("MU confirmed", "MU")
hooks.BP_OnIngredientAdded(param(cst), param(1)); tick(0.5); check("two in -> third known", "HCL")
-- new batch with a fake-out
cst.CurrentState = 2; tick(1); cst.CurrentState = 1; tick(1)
say("sha_rmk02_17"); check("new batch first call", "CS")
say("sha_rmk02_25"); check("hold up", "?")
say("sha_rmk02_26"); check("correction", "MU")
-- cut off: call then interrupted by a sniper line, no confirmation
hooks.BP_OnIngredientAdded(param(cst), param(1)); tick(0.5)
say("sha_rmk02_18"); say("sha_rmk02_44"); check("cut off instruction line", "HCL")
print("COOK OK\n")
-- a confirmation cut after 0.5 s must not confirm
hooks.BP_OnIngredientAdded(param(cst), param(3)); tick(0.5)
cst.CurrentState = 2; tick(1); cst.CurrentState = 1; tick(1)
say("sha_rmk02_16"); blip("sha_rmk02_29"); check("short confirmation still counts", "MU")
say("sha_rmk02_24"); check("encouragement confirms", "MU")
print("COOK2 OK\n")
hooks.BP_OnIngredientAdded(param(cst), param(1)); tick(0.5)
cst.CurrentState = 2; tick(1); cst.CurrentState = 1; tick(1)
say("sha_rmk02_21"); check("one-off call", "HCL?")
tick(4); check("5 s, no warning -> stands", "HCL")
hooks.BP_OnIngredientAdded(param(cst), param(3)); tick(0.5)
say("sha_rmk02_19"); say("sha_rmk02_25"); check("fake-out within 2 s", "?")
say("sha_rmk02_28"); check("correction", "HCL")
print("COOK3 OK\n")
hooks.BP_OnIngredientAdded(param(cst), param(3)); tick(0.5)
say("sha_rmk02_20"); say("sha_rmk02_25"); say("sha_rmk02_18"); check("correction via a normal call", "HCL")
print("COOK4 OK\n")
hooks.BP_OnIngredientAdded(param(cst), param(1)); tick(0.5)
cst.CurrentState = 2; tick(1); cst.CurrentState = 1; tick(1)
say("sha_rmk02_17"); say("sha_rmk02_25"); check("warning after an instruction line still wins", "?")
say("sha_rmk02_27"); check("correction", "CS")
print("COOK5 OK\n")
-- power cut after a call: keep it as it was
hooks.BP_OnIngredientAdded(param(cst), param(2)); tick(0.5)
say("sha_rmk02_18"); check("call before the cut", "HCL")
cst.CurrentState = 6; tick(2); cst.CurrentState = 1; tick(1)
check("power back: kept", "HCL")
tick(10); check("still kept", "HCL")
say("sha_rmk02_18"); check("she repeats it", "HCL")
print("COOK6 OK\n")
-- one-off call, then a power cut inside the 5 s window: stays "?" until she speaks again
hooks.BP_OnIngredientAdded(param(cst), param(3)); tick(0.5)
cst.CurrentState = 2; tick(1); cst.CurrentState = 1; tick(1)
say("sha_rmk02_20"); check("one-off call", "CS?")
cst.CurrentState = 6; tick(8); cst.CurrentState = 1; tick(8)
check("cut inside the window: still unsure", "CS?")
say("sha_rmk02_17"); check("she calls it again", "CS")
print("COOK7 OK\n")
-- 2026-11-21 log: sure HCL, then a one-off "CS?" and "hold up", then HCL again: the label stays HCL
hooks.BP_OnIngredientAdded(param(cst), param(2)); tick(0.5)
cst.CurrentState = 2; tick(1); cst.CurrentState = 1; tick(1)
say("sha_rmk02_18"); say("sha_rmk02_29"); check("sure HCL", "HCL")
say("sha_rmk02_20"); check("one-off CS after a sure HCL: ignored", "HCL")
say("sha_rmk02_25"); check("its hold up: ignored", "HCL")
say("sha_rmk02_18"); check("she repeats HCL", "HCL")
print("COOK8 OK\n")
-- first call said in the same moment the batch starts: kept
hooks.BP_OnIngredientAdded(param(cst), param(3)); tick(0.5)
cst.CurrentState = 2; tick(1)
active = { "sha_rmk02_18" }; cst.CurrentState = 1; tick(1.3); active = {}; tick(0.3)
check("call at the batch start kept", "HCL")
print("COOK9 OK\n")

