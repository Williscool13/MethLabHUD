-- you standing right behind the display must NOT count; a teammate in front must
function lastLabel() for i = #texts, 1, -1 do local s = texts[i]; if s:match("^%u+$") or s:match("^%.+$") or s == "?" then return s end end return "?none" end
camRot = { Pitch = 0, Yaw = 180, Roll = 0 }
local cam = { X = 2200, Y = 0, Z = 0 }
local me = obj({ __addr = 7701, K2_GetActorLocation = function() return { X = 2200, Y = 0, Z = 0 } end })
local mate = obj({ __addr = 7702, K2_GetActorLocation = function() return { X = 5000, Y = 0, Z = 0 } end })
pc = obj({ __addr = 702, Pawn = me, bShowMouseCursor = false, IsLocalController = function() return true end, GetWorld = function() return world end, WasInputKeyJustPressed = function() return false end,
  PlayerCameraManager = obj({ __addr = 703, GetCameraLocation = function() return cam end, GetCameraRotation = function() return camRot end }) })
board = obj({ __addr = 970, bHidden = false, K2_GetActorLocation = function() return { X = 2000, Y = 0, Z = 0 } end, WasRecentlyRendered = function() return false end, GetActorForwardVector = function() return { X = 1, Y = 0, Z = 0 } end })
st5 = obj({ __addr = 961, CurrentState = 0, BagHandleArray = bags, K2_GetActorLocation = function() return { X = 5, Y = 5, Z = 5 } end, recipeActors = { ForEach = function(self, f) f(1, param(board)) end } })
local function ps(pw) return obj({ GetPawn = function() return pw end }) end
world.GameState = { PlayerArray = { ForEach = function(self, f) f(1, param(ps(me))); f(2, param(ps(mate))) end } }
FindAllOf = (function(orig) return function(c) if c == "BP_MethCookingStation_C" then return { st5 } end return orig(c) end end)(FindAllOf)
tick(5)
hooks.BP_OnStaticOrderGenerated(param(st5), arr({2,0,1})); hooks.ReceiveBeginPlay(param(st5)); station.__valid = false
tick(3); print("me 2 m behind it: " .. lastLabel() .. "\n"); assert(lastLabel() == "?")
mate.K2_GetActorLocation = function() return { X = 2300, Y = 0, Z = 0 } end; tick(1); print("teammate 3 m behind it: " .. lastLabel() .. "\n"); assert(lastLabel() == "?")
mate.K2_GetActorLocation = function() return { X = 1700, Y = 0, Z = 0 } end; tick(1); print("teammate 3 m in front: " .. lastLabel() .. "\n"); assert(lastLabel() == "HCL")
print("WIT3 OK\n")
