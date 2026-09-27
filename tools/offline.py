"""Runs the engine's offline tests (tests/offline/*.luau) with the Luau command-line runtime: no Studio needed.

python3 tools/offline.py LUAU_BINARY

The engine is flattened (tools/tree.py) so it loads as one chunk, handing back its internals (I) as well as its API
(E), after tests/offline/roblox.luau has set up the few Roblox types the pure logic needs."""
import pathlib
import subprocess
import sys
import tempfile

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import tree as T  # noqa: E402

luau = sys.argv[1]
engine = T.flatten(T.tree(), "Engine")[0]
tail = "\nreturn E\n"
assert engine.endswith(tail), "the engine entry should end by returning E"
engine = engine[: -len(tail)] + "\nreturn E, I\n"  # the tests reach the internals too

stubs = T.read(T.ROOT / "tests" / "offline" / "roblox.luau")
status = 0
for test in sorted((T.ROOT / "tests" / "offline").glob("*.luau")):
    if test.name == "roblox.luau":
        continue
    src = stubs + "\nlocal E, I = (function()\n" + engine + "\nend)()\n" + T.read(test)
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
        f.write(src)
    r = subprocess.run([luau, f.name], capture_output=True, text=True)
    pathlib.Path(f.name).unlink()
    print((r.stdout + r.stderr).strip())
    status |= r.returncode
sys.exit(status)
