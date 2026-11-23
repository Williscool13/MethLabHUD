-- late join seeing the 2nd pour: slot 1 = step 2 -> next is slot 2 = CS
function lastLabel() for i = #texts, 1, -1 do local s = texts[i]; if s:match("^%u+$") or s:match("^%.+$") or s == "?" then return s end end return "?none" end
pc = obj({ __addr = 702, bShowMouseCursor = false, IsLocalController = function() return true end, GetWorld = function() return world end, WasInputKeyJustPressed = function() return false end, PlayerCameraManager = obj({ __addr = 703, GetCameraLocation = function() return { X = 0, Y = 0, Z = 0 } end }) })
world.GameState = { PlayerArray = { ForEach = function() end }, GetServerWorldTimeSeconds = function() return 600 end }
st7 = obj({ __addr = 963, CurrentState = 1, NumberOfBags = 4, HasAuthority = function() return false end, BagHandleArray = { GetArrayNum = function() return 0 end },
  K2_GetActorLocation = function() return { X = 5, Y = 5, Z = 5 } end })
FindAllOf = (function(orig) return function(c) if c == "BP_MethCookingStation_C" then return { st7 } end return orig(c) end end)(FindAllOf)
tick(5)
hooks.BP_OnStaticOrderGenerated(param(st7), arr({2,0,1})); hooks.ReceiveBeginPlay(param(st7)); station.__valid = false
tick(2); print("late join: " .. lastLabel() .. "\n"); assert(lastLabel() == "?")
hooks.BP_OnIngredientAdded(param(st7), param(1)); tick(1)
print("after 2nd pour seen: " .. lastLabel() .. "\n"); assert(lastLabel() == "CS")
local hasCount = false; for _, t in ipairs(texts) do if t == "0" then hasCount = true end end
print("client batch number shown as 0: " .. tostring(hasCount) .. "\n"); assert(not hasCount)
print("LATE2 OK\n")
