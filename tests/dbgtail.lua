pc = obj({ __addr = 702, bShowMouseCursor = false, IsLocalController = function() return true end, GetWorld = function() return world end, PlayerCameraManager = obj({ __addr = 703, GetCameraLocation = function() return { X = 0, Y = 0, Z = 0 } end }) })
tick(2)
-- press PageDown through all previews, then Insert
local keyDown = nil
pc.WasInputKeyJustPressed = function(self, k) return k.KeyName == keyDown end
for i = 1, 13 do keyDown = "PageDown"; tick(0.1); keyDown = nil; tick(0.2) end
keyDown = "Insert"; tick(0.1); keyDown = nil; tick(11)
print("DBG OK\n")
