-- late join: lab already waiting 10 minutes in, 2 already poured (slots 3 then 1); next pour is slot 2 (CS)
function lastLabel() for i = #texts, 1, -1 do local s = texts[i]; if s:match("^%u+$") or s:match("^%.+$") or s == "?" then return s end end return "?none" end
pc = obj({ __addr = 702, bShowMouseCursor = false, IsLocalController = function() return true end, GetWorld = function() return world end, WasInputKeyJustPressed = function() return false end, PlayerCameraManager = obj({ __addr = 703, GetCameraLocation = function() return { X = 0, Y = 0, Z = 0 } end }) })
local board = obj({ __addr = 971, bHidden = false, K2_GetActorLocation = function() return { X = 9000, Y = 0, Z = 0 } end })
world.GameState = { PlayerArray = { ForEach = function() end }, GetServerWorldTimeSeconds = function() return 600 end }
local left = 3
st6 = obj({ __addr = 962, CurrentState = 1, NumberOfBags = 4, HasAuthority = function() return false end,
  BagHandleArray = { GetArrayNum = function() return left end },
  K2_GetActorLocation = function() return { X = 5, Y = 5, Z = 5 } end, recipeActors = { ForEach = function(self, f) f(1, param(board)) end } })
FindAllOf = (function(orig) return function(c) if c == "BP_MethCookingStation_C" then return { st6 } end return orig(c) end end)(FindAllOf)
tick(5)
hooks.BP_OnStaticOrderGenerated(param(st6), arr({2,0,1})); hooks.ReceiveBeginPlay(param(st6)); station.__valid = false
tick(2); print("late join label: " .. lastLabel() .. "\n"); assert(lastLabel() == "?")
hooks.BP_OnIngredientAdded(param(st6), param(2)); tick(1)
print("after seeing the 3rd pour: next label " .. lastLabel() .. "\n")
-- recipe (2,0,1) = slots 3,1,2; a pour into slot 2 is step 3 -> all in
print("LATE OK\n")
