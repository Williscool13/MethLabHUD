function lastLabel() for i = #texts, 1, -1 do local s = texts[i]; if s:match("^%u+$") or s:match("^%.+$") then return s end end return "?" end
pc = obj({ __addr = 702, bShowMouseCursor = false, IsLocalController = function() return true end, GetWorld = function() return world end, WasInputKeyJustPressed = function() return false end, PlayerCameraManager = obj({ __addr = 703, GetCameraLocation = function() return { X = 0, Y = 0, Z = 0 } end }) })
local its = { obj({ __addr = 4001, bInteractionEnabled = false }), obj({ __addr = 4002, bInteractionEnabled = false }), obj({ __addr = 4003, bInteractionEnabled = false }) }
local function setAll(v) for _, i in ipairs(its) do i.bInteractionEnabled = v end end
st3 = obj({ __addr = 950, CurrentState = 0, BagHandleArray = bags, K2_GetActorLocation = function() return { X = 5, Y = 5, Z = 5 } end,
  IngredientInteractableArray = { ForEach = function(self, f) for i, v in ipairs(its) do f(i, param(v)) end end } })
FindAllOf = (function(orig) return function(c) if c == "BP_MethCookingStation_C" then return { st3 } end return orig(c) end end)(FindAllOf)
tick(5)
hooks.BP_OnStaticOrderGenerated(param(st3), arr({2,0,1})); hooks.ReceiveBeginPlay(param(st3)); station.__valid = false; tick(1)
st3.CurrentState = 1; setAll(true); tick(1)
print("label ready: " .. lastLabel() .. "\n"); assert(lastLabel() == "HCL")
hooks.BP_OnIngredientAdded(param(st3), param(3)); setAll(false); tick(1)
print("label processing: " .. lastLabel() .. "\n"); assert(lastLabel():match("^%.+$"))
setAll(true); tick(0.5)
print("label next: " .. lastLabel() .. "\n"); assert(lastLabel() == "MU")
print("PROC OK\n")
