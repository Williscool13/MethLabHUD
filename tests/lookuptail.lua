-- A map without a lab: after loading, no StaticFindObject for things that aren't there.
local misses = 0
local function unload() for _, o in ipairs(sfo or {}) do if o.__path:find("BP_MethCookingStation") or o.__path:find("G_Cookie_Scripting") then o.__valid = false end end end
local realSFO = StaticFindObject
StaticFindObject = function(p)
  if p:find("BP_MethCookingStation") or p:find("G_Cookie_Scripting") then misses = misses + 1; return nil end
  return realSFO(p)
end
FindAllOf = (function(orig) return function(c) if c == "BP_MethCookingStation_C" then return {} end return orig(c) end end)(FindAllOf)
unload()
world = obj({ __addr = 777, GetFName = function() return { ToString = function() return "Brooklyn" end } end })
tick(40)                      -- level change + 30 s dead-player wait + settle
misses = 0
tick(60)
print("lab lookups in 60 s on a map without a lab: " .. misses .. "\n"); assert(misses == 0)
unload()
world = obj({ __addr = 778, GetFName = function() return { ToString = function() return "Bust" end } end })
tick(40); misses = 0; tick(10)
print("lookups in 10 s on Party Powder before the lab loads: " .. misses .. "\n"); assert(misses > 0)
print("LOOKUP OK\n")
