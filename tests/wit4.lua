-- wall between camera and display must block; clear line must pass
function lastLabel() for i = #texts, 1, -1 do local s = texts[i]; if s:match("^%u+$") or s:match("^%.+$") or s == "?" then return s end end return "?none" end
camRot = { Pitch = 0, Yaw = 0, Roll = 0 }
local cam = { X = 1500, Y = 0, Z = 0 }
local wall = true
pc = obj({ __addr = 702, bShowMouseCursor = false, IsLocalController = function() return true end, GetWorld = function() return world end, WasInputKeyJustPressed = function() return false end,
  PlayerCameraManager = obj({ __addr = 703, GetCameraLocation = function() return cam end, GetCameraRotation = function() return camRot end }) })
board = obj({ __addr = 970, bHidden = false, K2_GetActorLocation = function() return { X = 2000, Y = 0, Z = 0 } end, WasRecentlyRendered = function() return true end, GetActorForwardVector = function() return { X = 1, Y = 0, Z = 0 } end,
  GetActorBounds = function(self, oc, o, e, ch) o.X, o.Y, o.Z = 2000, 0, 120 end })
local traces = 0
local origSFO = StaticFindObject
StaticFindObject = function(p) if p:find("KismetSystemLibrary") then return obj({ __addr = 12, LineTraceSingle = function(self, wc, a, b, ch, cx, ign, dbg, hit) traces = traces + 1; lastTarget = b; return wall end }) end return origSFO(p) end
st5 = obj({ __addr = 961, CurrentState = 0, BagHandleArray = bags, K2_GetActorLocation = function() return { X = 5, Y = 5, Z = 5 } end, recipeActors = { ForEach = function(self, f) f(1, param(board)) end } })
world.GameState = { PlayerArray = { ForEach = function() end } }
FindAllOf = (function(orig) return function(c) if c == "BP_MethCookingStation_C" then return { st5 } end return orig(c) end end)(FindAllOf)
tick(5)
hooks.BP_OnStaticOrderGenerated(param(st5), arr({2,0,1})); hooks.ReceiveBeginPlay(param(st5)); station.__valid = false
tick(3); print("through a wall: " .. lastLabel() .. " (traces " .. traces .. ")\n"); assert(lastLabel() == "?" and traces > 0)
print(string.format("trace target %.0f %.0f %.0f\n", lastTarget.X, lastTarget.Y, lastTarget.Z)); assert(lastTarget.X == 1975 and lastTarget.Z == 120)
wall = false; tick(2); print("clear line: " .. lastLabel() .. "\n"); assert(lastLabel() == "HCL")
print("WIT4 OK\n")
