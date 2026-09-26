"""Development push into the open place, in snippets small enough for one command-bar run each.

python3 tools/push.py OUT_DIR MAXBYTES MODE [VERSION BUILD]
  MODE tree:   the App and Engine trees -> ServerStorage.SS_TreeTest (not archivable), built with the loader's own
               buildTree/readTree, then read back and compared (checks the loader's tree code and every module)
  MODE tests:  tests/suite.lua -> SmartScatterSource.Tests, then runs it and returns its report
  MODE mirror: the flattened release (dist/Engine.lua, Main.lua, Main_2…) -> ServerStorage.SmartScatterSource with
               the new Build, so a running loader of any age hot-swaps to it
Writes OUT_DIR/push_001.lua … (each checks its own piece and stores it in _G.SS_up; any order) and
OUT_DIR/push_final.lua (joins them, checks every module's length and checksum, then acts)."""
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import tree as T  # noqa: E402

out, maxb, mode = pathlib.Path(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
out.mkdir(parents=True, exist_ok=True)
root = T.ROOT
if mode == "tree":
    files = T.tree()
elif mode == "tests":
    files = {"Tests": T.read(root / "tests" / "suite.lua")}
else:
    version, build = sys.argv[4], sys.argv[5]
    files = {p.stem: T.read(p) for p in (root / "dist").glob("*.lua")}

# small self-checking pieces: each one verifies its own checksum on arrival, so they can be sent in any order (or
# in parallel) and a bad copy is caught at the piece, not only at the end
CK = "local function ck(s) local h = 0 for i = 1, #s do h = (h * 31 + string.byte(s, i)) % 1000000007 end return h end"
PIECE = """%s
local s = [======[%s]======]
local lines = {} for l in string.gmatch(s .. "\\n", "([^\\n]*)\\n") do table.insert(lines, string.sub(l, 2)) end
s = table.concat(lines, "\\n")
if #s ~= %d or ck(s) ~= %d then return "BAD piece %d (%s)" end
_G.SS_up = _G.SS_up or {} _G.SS_up["%s#%d"] = s
return "ok %d"
"""


def split(src):
    """a source as runs of whole lines, each under maxb bytes"""
    runs, cur, size = [], [], 0
    for line in src.split("\n"):
        if cur and size + len(line) > maxb:
            runs.append(cur)
            cur, size = [], 0
        cur.append(line)
        size += len(line) + 2
    runs.append(cur)
    return runs


n, counts = 0, {}
for path, src in files.items():
    runs = split(src)
    counts[path] = len(runs)
    for k, run in enumerate(runs, start=1):
        n += 1
        body, text = "\n".join("|" + l for l in run), "\n".join(run)
        assert "]======]" not in body
        piece = PIECE % (CK, body, len(text.encode()), T.checksum(text), n, path, path, k, n)
        (out / ("push_%03d.lua" % n)).write_text(piece, encoding="utf-8")

loader = T.read(root / "Loader.lua")
fns = "\n".join(re.search(r"(local function %s\(.*?\n^end\n)" % n, loader, re.S | re.M).group(1) for n in ("buildTree", "readTree"))
expect = ",\n".join('\t["%s"] = { %d, %d, %d }' % (p, len(s.encode()), T.checksum(s), counts[p]) for p, s in files.items())
final = [
    "local EXPECT = {\n%s\n}" % expect,
    "local function ck(s) local h = 0 for i = 1, #s do h = (h * 31 + string.byte(s, i)) % 1000000007 end return h end",
    "local got = {}",
    "for path, want in EXPECT do",
    "\tlocal parts = {}",
    "\tfor k = 1, want[3] do",
    "\t\tlocal p = _G.SS_up and _G.SS_up[path .. \"#\" .. k]",
    "\t\tif not p then return \"missing piece \" .. k .. \" of \" .. path end",
    "\t\tparts[k] = p",
    "\tend",
    "\tlocal s = table.concat(parts, \"\\n\")",
    "\tif #s ~= want[1] or ck(s) ~= want[2] then return \"bad copy of \" .. path .. \" (\" .. #s .. \" bytes)\" end",
    "\tgot[path] = s",
    "end",
    "_G.SS_up = nil",
]
if mode == "tree":
    final += [
        fns,
        'local SS = game:GetService("ServerStorage")',
        'if SS:FindFirstChild("SS_TreeTest") then SS.SS_TreeTest:Destroy() end',
        'local f = Instance.new("Folder") f.Name = "SS_TreeTest" f.Archivable = false',
        "buildTree(got, f, false)",
        "f.Parent = SS",
        "local back, n = readTree(f), 0",
        "for path, s in got do n += 1 if back[path] ~= s then return \"tree read back differently at \" .. path end end",
        "for path in back do if not got[path] then return \"extra module read back: \" .. path end end",
        'return "tree ok: " .. n .. " modules"',
    ]
elif mode == "tests":
    final += [
        'local f = game:GetService("ServerStorage"):FindFirstChild("SmartScatterSource")',
        'if not f then return "no live copy: is the plugin running?" end',
        'local t = f:FindFirstChild("Tests") or Instance.new("ModuleScript")',
        't.Name, t.Archivable, t.Source = "Tests", false, got.Tests',
        "t.Parent = f",
        "local run, err = loadstring(got.Tests)",
        'if not run then return "suite does not compile: " .. tostring(err) end',
        "return run()",
    ]
else:
    final += [
        'local f = game:GetService("ServerStorage"):FindFirstChild("SmartScatterSource")',
        'if not f then return "no live copy: is the plugin running?" end',
        "for name, s in got do",
        "\tlocal m = f:FindFirstChild(name)",
        '\tif not m then m = Instance.new("ModuleScript") m.Name = name m.Archivable = false m.Parent = f end',
        "\tm.Source = s",
        "end",
        "for _, c in f:GetChildren() do if string.match(c.Name, \"^Main_%d+$\") and not got[c.Name] then c:Destroy() end end",
        'f:SetAttribute("Version", "%s")' % version,
        'f:SetAttribute("Build", %s) -- last: the loader reloads once' % build,
        'return "mirror now %s (build %s)"' % (version, build),
    ]
(out / "push_final.lua").write_text("\n".join(final) + "\n", encoding="utf-8")
print(n, "pieces + push_final ->", out)
