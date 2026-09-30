"""The source tree and the two ways it ships.

src/App and src/Engine are module trees: <folder>/init.lua is the entry, every other .lua file a child module, and
the entry's ORDER table lists its modules. The tree maps paths to sources: "App", "App/Core/State", "Engine",
"Engine/Scan"…; that is exactly the ModuleScript tree the plugin gets (a path with children but no source of its own
is a Folder).

legacy() turns both entries into the flattened release for loaders from before module trees (they run one Engine and
one Main, plus parts Main_2, Main_3… for what doesn't fit under Studio's 200k limit on a Source set from code);
flatten() makes one entry a single script of any size, for the offline tests."""
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
ENTRIES = ("App", "Engine")
LIMIT = 180_000  # bytes per flattened script, well under Studio's 200k
MODULE_LINE = re.compile(r"^local function module\((\w+)\).*?\nend\n", re.M | re.S)


def read(p):
    return p.read_text(encoding="utf-8").replace("\r\n", "\n")


def tree():
    """{path: source} for every module, entries first."""
    out = {}
    for entry in ENTRIES:
        base = SRC / entry
        out[entry] = read(base / "init.lua")
        for p in sorted(base.rglob("*.lua")):
            if p.name != "init.lua":
                out[entry + "/" + p.relative_to(base).with_suffix("").as_posix()] = read(p)
    return out


def order(entry_src):
    """the module paths an entry's ORDER table lists"""
    m = re.search(r"local ORDER = \{(.*?)\}", entry_src, re.S)
    assert m, "entry has no ORDER table"
    return re.findall(r'"([^"]+)"', m.group(1))


def check(t):
    """every module is listed exactly once, every listed module exists, and no module has a multi-line string (slim()
    takes indentation out of flattened copies, which would change one)"""
    for path, src in t.items():
        code = re.sub(r"--\[(=*)\[.*?\]\1\]", "", src, flags=re.S)
        assert not re.search(r"\[=*\[", code), path + ": a multi-line string; slim() would change its text"
    for entry in ENTRIES:
        listed = order(t[entry])
        have = sorted(p[len(entry) + 1:] for p in t if p.startswith(entry + "/"))
        assert len(set(listed)) == len(listed), entry + ": a module is listed twice"
        missing = sorted(set(listed) - set(have))
        extra = sorted(set(have) - set(listed))
        assert not missing and not extra, "%s: missing %s, not in ORDER %s" % (entry, missing, extra)


def code_part(line):
    """a line without its trailing comment: the `--` that starts one outside any string. A line whose comment opens a
    block comment (--[[) is kept whole, since the comment goes on past it; so is one that closes a block comment (]]),
    which may be inside one, where quotes mean nothing."""
    if "]]" in line:
        return line
    quote = None
    i = 0
    while i < len(line):
        ch = line[i]
        if quote:
            if ch == "\\":
                i += 2
                continue
            if ch == quote:
                quote = None
        elif ch in "\"'`":
            quote = ch
        elif line.startswith("--", i):
            if line.startswith("--[", i):
                return line
            return line[:i].rstrip()
        i += 1
    return line


def slim(src):
    """drops comments (not block comments) and indentation: a flattened copy is only run, never read, and must fit
    (the source has no multi-line strings, whose insides indentation would belong to; check() makes sure)"""
    out = []
    for l in src.split("\n"):
        l = code_part(l.lstrip("\t"))
        if l.strip():
            out.append(l)
    return "\n".join(out)


# The flattened release. Loaders from before module trees make exactly these scripts, side by side: Engine, Main and
# the parts Main_2 … Main_16 (they keep nothing else), and require Engine, then Main. So an entry's own script holds
# as many of its modules as fit, and what doesn't fit goes into the parts, which carry both entries' modules under
# their full paths ("Engine/Lines", "App/Panel/Shell"); each entry's script collects its own from them.
LEGACY_NAME = {"Engine": "Engine", "App": "Main"}
PART = "Main_%d"
FIRST_PART, LAST_PART = 2, 16  # the part numbers older loaders look for


def size(s):
    return len(s.encode())


def _blocks(t, entry, qualified):
    """the entry's modules, in ORDER, as (path, block) pairs: each module's source run once into MODULES[key]"""
    out = []
    for path in order(t[entry]):
        key = entry + "/" + path if qualified else path
        body = slim(t[entry + "/" + path].rstrip("\n"))
        out.append((path, '\n-- #module %s\nMODULES["%s"] = (function()\n%s\nend)()' % (key, key, body)))
    return out


def _entry(t, entry, blocks, parts):
    """the entry's own script: its modules, then (if some are in the parts) the loop that collects those, then the
    entry's code with module() reading MODULES instead of the tree"""
    src = t[entry]
    assert MODULE_LINE.search(src), entry + ": the entry's module() function is what a flattened copy replaces"
    head = "-- GENERATED from src/%s by tools/tree.py (a flattened copy for older loaders): edit the modules, not this.\nlocal MODULES = {}\n" % entry
    collect = ""
    if parts:
        collect = (
            "\n-- the modules that didn't fit here are in the sibling parts (keys \"%s/<path>\"); an older loader that\n"
            "-- only copies Engine and Main finds them in the live mirror instead\n"
            "for k = %d, %d do\n"
            '\tlocal name = "%s" .. k\n'
            "\tlocal p = script.Parent and script.Parent:FindFirstChild(name)\n"
            "\tif not p then\n"
            '\t\tlocal m = game:GetService("ServerStorage"):FindFirstChild("SmartScatterSource")\n'
            "\t\tp = m and m:FindFirstChild(name)\n"
            "\tend\n"
            "\tif not p then\n"
            "\t\tbreak\n"
            "\tend\n"
            "\tfor key, f in require(p) do\n"
            '\t\tlocal path = string.match(key, "^%s/(.+)$")\n'
            "\t\tif path then\n"
            "\t\t\tMODULES[path] = f\n"
            "\t\tend\n"
            "\tend\n"
            "end\n"
        ) % (entry, FIRST_PART, LAST_PART, PART.replace("%d", ""), entry)
    tail = MODULE_LINE.sub(lambda m: "local function module(%s)\n\treturn MODULES[%s]\nend\n" % (m.group(1), m.group(1)), src, count=1)
    return head + "".join(b for _, b in blocks) + "\n" + collect + "\n" + tail


def flatten(t, entry):
    """one entry and all its modules as a single script, whatever its size (what the offline tests run)"""
    return _entry(t, entry, _blocks(t, entry, False), False)


def legacy(t, limit=LIMIT):
    """the flattened release: {script name: source}, in the order older loaders make them: Engine, Main, Main_2…
    Every script stays under limit (Studio refuses a Source over 200k set from code; the offline tests pass a small
    one so the split is always exercised)."""
    out, spill = {}, []
    for entry in ENTRIES_LEGACY:
        own = _blocks(t, entry, False)
        if size(_entry(t, entry, own, False)) <= limit:
            out[LEGACY_NAME[entry]] = _entry(t, entry, own, False)
            continue
        # as many modules as fit in the entry's own script (with the loop that collects the rest), in ORDER
        room = limit - size(_entry(t, entry, [], True))
        keep = []
        for path, b in own:
            if room - size(b) < 0:
                break
            keep.append((path, b))
            room -= size(b)
        out[LEGACY_NAME[entry]] = _entry(t, entry, keep, True)
        kept = {path for path, _ in keep}
        spill += [b for path, b in _blocks(t, entry, True) if path not in kept]
    # the rest, packed into as few parts as they fit in (a part is a plain table of modules)
    parts, cur = [], []
    frame = size("-- GENERATED part 00 of the flattened release by tools/tree.py: edit the modules, not this.\nlocal MODULES = {}\n\nreturn MODULES\n")
    for b in spill:
        assert frame + size(b) <= limit, "one module is bigger than a whole script: split it"
        if cur and frame + size("".join(cur) + b) > limit:
            parts.append(cur)
            cur = []
        cur.append(b)
    if cur:
        parts.append(cur)
    assert FIRST_PART + len(parts) - 1 <= LAST_PART, "more parts than older loaders look for"
    for k, blocks in enumerate(parts, start=FIRST_PART):
        out[PART % k] = (
            "-- GENERATED part %d of the flattened release by tools/tree.py: edit the modules, not this.\nlocal MODULES = {}\n%s\n\nreturn MODULES\n"
            % (k, "".join(blocks))
        )
    for name, src in out.items():
        assert size(src) <= limit, (name, size(src))
    # every module is somewhere, once
    for entry in ENTRIES_LEGACY:
        for path in order(t[entry]):
            own = '\nMODULES["%s"] = ' % path in out[LEGACY_NAME[entry]]
            elsewhere = sum('\nMODULES["%s/%s"] = ' % (entry, path) in out[PART % k] for k in range(FIRST_PART, FIRST_PART + len(parts)))
            assert own + elsewhere == 1, (entry, path, own, elsewhere)
    return out


ENTRIES_LEGACY = ("Engine", "App")  # (the order they're made and required in)


def checksum(text):
    h = 0
    for c in text.encode():
        h = (h * 31 + c) % 1000000007
    return h


# The loader's functions that need nothing from Studio: the offline tests and tools/loader_test.py run them as they
# are in Loader.lua.
LOADER_PURE = ("checksum", "normalize", "gatherRelease")


def loader_function(loader_src, name):
    m = re.search(r"^local function %s\(.*?\n^end\n" % name, loader_src, re.S | re.M)
    assert m, "Loader.lua has no top-level function " + name
    return m.group(0)
