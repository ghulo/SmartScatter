"""Runs the engine's offline tests (tests/offline/*.luau) with the Luau command-line runtime: no Studio needed.

python3 tools/offline.py LUAU_BINARY

The engine runs as the flattened release ships it (tools/tree.py: its own script and the parts it collects modules
from), handing back its internals (I) as well as its API (E), after tests/offline/roblox.luau has set up the few Roblox
types the pure logic needs."""
import pathlib
import subprocess
import sys
import tempfile

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import tree as T  # noqa: E402

luau = sys.argv[1]
# The engine as the flattened release runs it (Engine plus the parts Main_2…, which older loaders make side by side),
# split here at a small size so the parts are always exercised: the release itself only splits when it has to.
SPLIT = 120_000
scripts = T.legacy(T.tree(), SPLIT)
assert any('MODULES["Engine/' in src for name, src in scripts.items() if name != "Engine"), "the engine didn't split"
tail = "\nreturn E\n"
assert scripts["Engine"].endswith(tail), "the engine entry should end by returning E"
scripts["Engine"] = scripts["Engine"][: -len(tail)] + "\nreturn E, I\n"  # the tests reach the internals too
# each script as a function of its `script`, side by side in one folder; require runs one once, like Roblox's
engine = "local SCRIPTS, folder, loaded = {}, {}, {}\n"
for name, src in scripts.items():
    if name != "Main":  # (the App's own script needs Studio; its modules in the parts are only defined, never run)
        engine += "SCRIPTS[%r] = function(script)\n%s\nend\n" % (name, src)
engine += """function folder:FindFirstChild(name)
	return SCRIPTS[name] and { Name = name, Parent = folder } or nil
end
function require(s)
	loaded[s.Name] = loaded[s.Name] or table.pack(SCRIPTS[s.Name](s))
	return table.unpack(loaded[s.Name], 1, loaded[s.Name].n)
end
return require(folder:FindFirstChild("Engine"))
"""

# The loader's pure update logic (its own functions, cut out of Loader.lua), with one checksum worked out by the
# release's side (tree.py), so the two are known to agree.
SAMPLE = "return function(App)\n\t-- é ✓\nend\n"
loader_src = T.read(T.ROOT / "Loader.lua")
loader = "local LOADER = (function()\n"
for name in T.LOADER_PURE:
    loader += T.loader_function(loader_src, name)
loader += "return { %s, sample = %s, sampleSum = %d }\nend)()\n" % (
    ", ".join("%s = %s" % (n, n) for n in T.LOADER_PURE),
    '"' + "".join("\\%d" % b for b in SAMPLE.encode("utf-8")) + '"',
    T.checksum(SAMPLE),
)

stubs = T.read(T.ROOT / "tests" / "offline" / "roblox.luau")
status = 0
for test in sorted((T.ROOT / "tests" / "offline").glob("*.luau")):
    if test.name == "roblox.luau":
        continue
    src = stubs + "\nlocal E, I = (function()\n" + engine + "\nend)()\n" + loader + T.read(test)
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
        f.write(src)
    r = subprocess.run([luau, f.name], capture_output=True, text=True)
    pathlib.Path(f.name).unlink()
    print((r.stdout + r.stderr).strip())
    status |= r.returncode
sys.exit(status)
