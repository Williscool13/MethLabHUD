function lastLabel() for i = #texts, 1, -1 do local s = texts[i]; if s:match("^%u+$") or s:match("^%.+$") then return s end end return "?" end
pc = obj({ __addr = 702, bShowMouseCursor = false, IsLocalController = function() return true end, GetWorld = function() return world end, WasInputKeyJustPressed = function() return false end, PlayerCameraManager = obj({ __addr = 703, GetCameraLocation = function() return { X = 0, Y = 0, Z = 0 } end }) })
st4 = obj({ __addr = 960, CurrentState = 0, BagHandleArray = bags, K2_GetActorLocation = function() return { X = 5, Y = 5, Z = 5 } end })
FindAllOf = (function(orig) return function(c) if c == "BP_MethCookingStation_C" then return { st4 } end return orig(c) end end)(FindAllOf)
tick(5)
hooks.BP_OnStaticOrderGenerated(param(st4), arr({2,0,1})); hooks.ReceiveBeginPlay(param(st4)); station.__valid = false
texts = {}
tick(2)
local t = {} for i = 1, #texts do t[#t+1] = "[" .. texts[i] .. "]" end
print("texts: " .. table.concat(t, " ") .. "\n")
print("inactive label: " .. lastLabel() .. "\n"); assert(lastLabel() == "HCL")
st4.CurrentState = 1; tick(1)
print("waiting label: " .. lastLabel() .. "\n"); assert(lastLabel() == "HCL")
print("INACT OK\n")
