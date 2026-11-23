-- ModMenu live settings: the shared variable changes -> settings reloaded once, icons rebuilt
local logs = {}
local oldPrint = print
print = function(s) logs[#logs + 1] = tostring(s); oldPrint(s) end
local function count(pat) local n = 0; for _, s in ipairs(logs) do if s:find(pat) then n = n + 1 end end; return n end
shared = {}
ModRef = { GetSharedVariable = function(self, k) return shared[k] end }
tick(2)
assert(count("settings reloaded") == 0, "reloaded without a ping")
shared["ModMenu.changed.MethCook"] = 1
tick(2)
assert(count("settings reloaded") == 1, "no reload after the ping")
tick(2)
assert(count("settings reloaded") == 1, "reloaded twice for one ping")
shared["ModMenu.changed.MethCook"] = 2
tick(2)
assert(count("settings reloaded") == 2, "second ping missed")
assert(count("frame error") == 0 and count("reload failed") == 0, "errors")
print("LIVE RELOAD OK\n")
