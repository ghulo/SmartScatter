"""The source tree and the two ways it ships.

src/App and src/Engine are module trees: <folder>/init.lua is the entry, every other .lua file a child module, and
the entry's ORDER table lists its modules. The tree maps paths to sources: "App", "App/Core/State", "Engine",
"Engine/Scan"…; that is exactly the ModuleScript tree the plugin gets (a path with children but no source of its own
is a Folder).

flatten() turns one entry and its modules into single scripts for loaders from before module trees (they run one
Engine and one Main, split into Main_2, Main_3… when Studio's 200k limit on a Source set from code would be hit)."""
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


def flatten(t, entry, part_name=None):
    """one entry + its modules as [main, part2, part3…] scripts (part_name: sibling name for part k, e.g. Main_%d)"""
    src = t[entry]
    assert MODULE_LINE.search(src), entry + ": the entry's module() function is what a flattened copy replaces"
    blocks = []
    for path in order(src):
        body = slim(t[entry + "/" + path].rstrip("\n"))
        blocks.append('\n-- #module %s\nMODULES["%s"] = (function()\n%s\nend)()' % (path, path, body))
    head = "-- GENERATED from src/%s by tools/tree.py (a flattened copy for older loaders): edit the modules, not this.\nlocal MODULES = {}\n" % entry
    loader = ""
    if part_name:
        loader = (
            "\n-- the rest of the modules are in sibling parts; an older loader that only copies Main finds them in the\n"
            "-- live mirror instead\n"
            "for k = 2, 16 do\n"
            '\tlocal p = script.Parent and script.Parent:FindFirstChild("%s" .. k)\n'
            "\tif not p then\n"
            '\t\tlocal m = game:GetService("ServerStorage"):FindFirstChild("SmartScatterSource")\n'
            '\t\tp = m and m:FindFirstChild("%s" .. k)\n'
            "\tend\n"
            "\tif not p then\n"
            "\t\tbreak\n"
            "\tend\n"
            "\tfor k2, f in require(p) do\n"
            "\t\tMODULES[k2] = f\n"
            "\tend\n"
            "end\n"
        ) % (part_name.replace("%d", ""), part_name.replace("%d", ""))
    tail = MODULE_LINE.sub(lambda m: "local function module(%s)\n\treturn MODULES[%s]\nend\n" % (m.group(1), m.group(1)), src, count=1)
    size = lambda s: len(s.encode())
    chunks, cur = [], []
    budget = LIMIT - size(head + loader + tail)
    for b in blocks:
        if cur and size("".join(cur) + b) > budget:
            assert part_name, entry + " is too big for one script"
            chunks.append(cur)
            cur, budget = [], LIMIT - 400
        cur.append(b)
    chunks.append(cur)
    out = [head + "".join(chunks[0]) + "\n" + loader + "\n" + tail]
    for k, ch in enumerate(chunks[1:], start=2):
        out.append("-- GENERATED part %d of src/%s by tools/tree.py: edit the modules, not this.\nlocal MODULES = {}\n%s\n\nreturn MODULES\n" % (k, entry, "".join(ch)))
    assert all(size(s) < 195_000 for s in out), [size(s) for s in out]
    return out


def checksum(text):
    h = 0
    for c in text.encode():
        h = (h * 31 + c) % 1000000007
    return h
