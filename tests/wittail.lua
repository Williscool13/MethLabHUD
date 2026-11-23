function lastLabel() for i = #texts, 1, -1 do local s = texts[i]; if s:match("^%u+$") or s:match("^%.+$") or s == "?" then return s end end return "?none" end
local cam = { X = 0, Y = 0, Z = 0 }
camRot = { Pitch = 0, Yaw = 90, Roll = 0 }
pc = obj({ __addr = 702, bShowMouseCursor = false, IsLocalController = function() return true end, GetWorld = function() return world end, WasInputKeyJustPressed = function() return false end,
  PlayerCameraManager = obj({ __addr = 703, GetCameraLocation = function() return cam end, GetCameraRotation = function() return camRot end }) })
local rendered = false
board = obj({ __addr = 970, bHidden = false, K2_GetActorLocation = function() return { X = 2000, Y = 0, Z = 0 } end, WasRecentlyRendered = function() return rendered end })
st5 = obj({ __addr = 961, CurrentState = 0, BagHandleArray = bags, K2_GetActorLocation = function() return { X = 5, Y = 5, Z = 5 } end,
  recipeActors = { ForEach = function(self, f) f(1, param(board)) end } })
world.GameState = { PlayerArray = { ForEach = function() end } }
FindAllOf = (function(orig) return function(c) if c == "BP_MethCookingStation_C" then return { st5 } end return orig(c) end end)(FindAllOf)
tick(5)
hooks.BP_OnStaticOrderGenerated(param(st5), arr({2,0,1})); hooks.ReceiveBeginPlay(param(st5)); station.__valid = false
tick(2); print("before seen: " .. lastLabel() .. "\n"); assert(lastLabel() == "?")
rendered = true; tick(1); print("rendered but far: " .. lastLabel() .. "\n"); assert(lastLabel() == "?")
cam = { X = 1500, Y = 0, Z = 0 }; tick(2); print("near, looking away: " .. lastLabel() .. "\n"); assert(lastLabel() == "?")
camRot = { Pitch = 0, Yaw = 0, Roll = 0 }; tick(0.5); print("glance 0.5 s: " .. lastLabel() .. "\n"); assert(lastLabel() == "?")
tick(1); print("looked 1.5 s: " .. lastLabel() .. "\n"); assert(lastLabel() == "HCL")
print("WIT OK\n")
