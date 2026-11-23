COOKOFF = true
world = obj({ __addr = 601, GetFName = function() return { ToString = function() return "Cookie" end } end })
pc = obj({ __addr = 702, bShowMouseCursor = false, IsLocalController = function() return true end, GetWorld = function() return world end, WasInputKeyJustPressed = function() return false end, PlayerCameraManager = obj({ __addr = 703, GetCameraLocation = function() return { X = 0, Y = 0, Z = 0 } end }) })
st8 = obj({ __addr = 964, CurrentState = 1, NumberOfBags = 19, BagHandleArray = { GetArrayNum = function() return 1 end }, K2_GetActorLocation = function() return { X = 5, Y = 5, Z = 5 } end })
FindAllOf = (function(orig) return function(c) if c == "BP_MethCookingStation_C" then return { st8 } end return orig(c) end end)(FindAllOf)
tick(5); hooks.ReceiveBeginPlay(param(st8)); station.__valid = false; tick(2)
local found = false; for _, t in ipairs(texts) do if t == "\u{221E}" then found = true end end
print("infinity shown: " .. tostring(found) .. "\n"); assert(found)
print("INF OK\n")
