"""Build the Meth Lab HUD release zip from the dev source.

Dev-only code (debug logging, PerfLog, the DEBUG tab actions) is marked in main.lua and stripped here:
  a line ending in   -- @dev          is removed
  lines between      -- @dev-begin / -- @dev-end   are removed (markers too)

usage: python build_release.py          (run from the repo root)
"""
import json, os, time, zipfile

VERSION = "1.0.0"
MOD = "MethCook"          # folder name in ue4ss\Mods (kept from the dev builds)

def strip_dev(src):
    out, skipping = [], False
    for line in src.split("\n"):
        tag = line.strip()
        if tag == "-- @dev-begin":
            assert not skipping, "nested @dev-begin"
            skipping = True
            continue
        if tag == "-- @dev-end":
            assert skipping, "@dev-end without begin"
            skipping = False
            continue
        if skipping or line.rstrip().endswith("-- @dev"):
            continue
        out.append(line)
    assert not skipping, "unclosed @dev-begin"
    return "\n".join(out)

lua_dev = open(f"{MOD}/Scripts/main.lua", encoding="utf-8").read()
lua = strip_dev(lua_dev)
for bad in ("DEBUG_KEYS", "PERF_LOG", "debugkeys", "perflog", "MM.action", "watchPours", "runBench",
            "COOKIE_REQ_EVENTS", "MethCookLastPour", "@dev"):
    assert bad not in lua, "dev code left in release: " + bad
os.makedirs("build", exist_ok=True)
os.makedirs("release", exist_ok=True)
open("build/main.release.lua", "w", encoding="utf-8", newline="\n").write(lua)

ini = open(f"{MOD}/settings.ini", encoding="utf-8").read().replace("\r\n", "\n")
assert "debugkeys" not in ini.lower() and "perflog" not in ini.lower()
sch = json.loads(open(f"{MOD}/settings.schema.json", encoding="utf-8").read())
for k in ("DebugKeys", "PerfLog"):
    sch["settings"].pop(k, None)
schema = (json.dumps(sch, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
crlf = lambda t: t.replace("\n", "\r\n").encode("utf-8")

p = f"release/MethLabHUD-{VERSION}.zip"
dt = time.localtime()[:6]
with zipfile.ZipFile(p, "w", zipfile.ZIP_DEFLATED) as z:
    for name, data in ((f"{MOD}/Scripts/main.lua", lua.encode("utf-8")),
                       (f"{MOD}/settings.ini", crlf(ini)),
                       (f"{MOD}/settings.schema.json", schema),
                       (f"{MOD}/enabled.txt", b"")):
        zi = zipfile.ZipInfo(name, dt)
        zi.compress_type = zipfile.ZIP_DEFLATED
        z.writestr(zi, data)
with zipfile.ZipFile(p) as z:
    assert z.testzip() is None
    print(p, z.namelist())
print("release main.lua: %d lines (dev %d); also written to build/main.release.lua for testing"
      % (lua.count("\n") + 1, lua_dev.count("\n") + 1))
