COOKOFF = true
pc = obj({ __addr = 702, bShowMouseCursor = false, IsLocalController = function() return true end, GetWorld = function() return world end, WasInputKeyJustPressed = function() return false end, PlayerCameraManager = obj({ __addr = 703, GetCameraLocation = function() return { X = 0, Y = 0, Z = 0 } end }) })
local active = {}
local function asset(n) return obj({ GetFName = function() return { ToString = function() return n end } end }) end
local mgr = obj({ __addr = 8801, ActiveDialogs = { ForEach = function(self, f) for _, n in ipairs(active) do f(param(asset(n)), param({})) end end } })
local sub = obj({ __addr = 8802, Text_SubtitleText = obj({ __addr = 8803, GetText = function() return { ToString = function() return CURTEXT or "" end } end }) })
FindAllOf = (function(orig) return function(c) if c == "SBZDialogManager" then return { mgr } elseif c == "WBP_UI_Widget_Subtitles_C" then return { sub } elseif c == "BP_MethCookingStation_C" then return { station } end return orig(c) end end)(FindAllOf)
station.__valid = true
tick(5)
active = { "sha_rmk02_17_04" }; CURTEXT = "You can add the caustic soda now."; tick(1)
active = { "sha_rmk02_25_02" }; CURTEXT = "Hold up!"; tick(1)
active = {}; CURTEXT = ""; tick(1)
print("DLG OK\n")
