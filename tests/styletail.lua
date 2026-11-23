pc = obj({ __addr = 702, bShowMouseCursor = false, IsLocalController = function() return true end, GetWorld = function() return world end, PlayerCameraManager = obj({ __addr = 703, GetCameraLocation = function() return { X = 0, Y = 0, Z = 0 } end }) })
local keyDown = nil
pc.WasInputKeyJustPressed = function(self, k) return k.KeyName == keyDown end
station.__valid = true
tick(5)
for i = 1, 4 do keyDown = "F5"; tick(0.1); keyDown = nil; tick(0.5) end
print("STYLE OK\n")
