-- 60 fps for 10 s with a lab: Lua garbage and function calls per frame
local function frames(sec) for i = 1, math.floor(sec * 60) do clock = clock + 1/60; for _, f in ipairs(loops) do f() end end end
tick(35); hooks.ReceiveBeginPlay(param(station)); station.CurrentState = 1; tick(1)
local nst = 0; for _ in pairs({}) do end
for _, mode in ipairs({ "waiting", "cooking" }) do
  station.CurrentState = (mode == "cooking") and 2 or 1; frames(1)
  collectgarbage("collect"); collectgarbage("stop")
  local calls = 0
  debug.sethook(function() calls = calls + 1 end, "c")
  local m0 = collectgarbage("count")
  frames(10)
  local kb = collectgarbage("count") - m0
  debug.sethook()
  collectgarbage("restart")
  print(string.format("PERF %s: %.2f KB garbage/frame, %.0f Lua calls/frame\n", mode, kb / 600, calls / 600))
end
STYLE_TEST = true
