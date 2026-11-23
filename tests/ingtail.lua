pc = obj({ __addr = 702, bShowMouseCursor = false, IsLocalController = function() return true end, GetWorld = function() return world end, WasInputKeyJustPressed = function() return false end, PlayerCameraManager = obj({ __addr = 703, GetCameraLocation = function() return { X = 0, Y = 0, Z = 0 } end }) })
local P = {
  BP_Meth_CausticSoda_C = { {842,1540,477},{0,0,0},{839,-3640,103},{3254,439,82},{22,1177,119} },
  BP_Meth_HydrogenChloride_C = { {852,1461,416},{804,-3740,-1},{6650,-115,48},{2881,1303,2} },
  BP_Meth_MuriaticAcid_C = { {826,1511,519},{2024,-4842,208},{828,-3593,114},{6691,1486,129} },
}
local objs = {}; local id = 3000
for cn, list in pairs(P) do objs[cn] = {}
  for _, v in ipairs(list) do id = id + 1
    local o = obj({ __addr = id, bHidden = false, K2_GetActorLocation = function() return { X = v[1], Y = v[2], Z = v[3] } end })
    table.insert(objs[cn], o) end end
local orig = FindAllOf
FindAllOf = function(c) if objs[c] then return objs[c] end return orig(c) end
station.CurrentState = 1
texts = {}
tick(12)
local function dump(tag) local t = {} for _, s in ipairs(texts) do if s:find("%d") and (s:find("CS") or s:find("MU") or s:find("HCL")) and s:find(" %d") then t[#t+1] = s end end print(tag .. ": " .. table.concat(t, " | ") .. "\n") end
dump("groups")
texts = {}
objs.BP_Meth_CausticSoda_C[1].bHidden = true; tick(1)
dump("after taking one CS")
print("ING OK\n")
