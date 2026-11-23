-- event discovery: a second lab spawns mid-level; FindAllOf would not return it
pc = obj({ __addr = 702, bShowMouseCursor = false, IsLocalController = function() return true end, GetWorld = function() return world end, WasInputKeyJustPressed = function() return false end, PlayerCameraManager = obj({ __addr = 703, GetCameraLocation = function() return { X = 0, Y = 0, Z = 0 } end }) })
tick(5)
local found0 = 0; for _, l in ipairs(logs) do if l:find("station found") then found0 = found0 + 1 end end
st2 = obj({ __addr = 900, CurrentState = 1, BagHandleArray = bags, K2_GetActorLocation = function() return { X = 1, Y = 2, Z = 3 } end })
hooks.ReceiveBeginPlay(param(st2)); tick(0.5)
local found1 = 0; for _, l in ipairs(logs) do if l:find("station found") then found1 = found1 + 1 end end
print("stations found via hook: " .. (found1 - found0) .. "\n"); assert(found1 - found0 == 1)
-- count FindAllOf station searches over 60 s
local n = 0; local orig = FindAllOf
FindAllOf = function(c) if c == "BP_MethCookingStation_C" then n = n + 1 end return orig(c) end
tick(60)
print("station searches in 60 s: " .. n .. "\n"); assert(n <= 2)
print("EV OK\n")
