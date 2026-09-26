"""Development push of small changes into the open place's live copy (ServerStorage.SmartScatterSource): only the
lines that changed travel, so a one-line fix is one short snippet. For whole modules use tools/push.py.

python3 tools/push_patch.py OUT_PREFIX VERSION BUILD MAXBYTES name=old.lua,new.lua [name=old.lua,new.lua ...]

name is a module of the live copy (Engine, Main, Main_2… for a flattened copy; Tests for the suite). old is what the
live copy holds now ("-" for a new module). Writes OUT_PREFIX_1.lua … (each adds line edits to _G.SS_ops[name]) and
OUT_PREFIX_final.lua (checks every base, applies, checks every result, then sets the modules and the Build attribute
last so the plugin reloads once)."""
import difflib
import sys


def ck(s):
    h = 0
    for c in s.encode():
        h = (h * 31 + c) % 1000000007
    return len(s.encode()), h


def ops(a, b):
    """line edits turning a into b: {first line, line after the replaced run, has new lines, "|"-prefixed new lines}"""
    al, bl, r = a.split("\n"), b.split("\n"), []
    for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, al, bl, autojunk=False).get_opcodes():
        if tag != "equal":
            t = "\n".join("|" + x for x in bl[j1:j2])
            assert "]======]" not in t
            r.append("{%d,%d,%s,[======[%s]======]}" % (i1 + 1, i2 + 1, "true" if j2 > j1 else "false", t))
    return "{" + ",\n".join(r) + "}"


out, ver, build, maxb = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
targets = []
for arg in sys.argv[5:]:
    name, files = arg.split("=", 1)
    old, new = files.split(",")
    a = "" if old == "-" else open(old).read()
    b = open(new).read()
    targets.append((name, a, b))

# every hunk, tagged with its module
hunks = []
for name, a, b in targets:
    body = ops(a, b)[1:-1]  # "{...},\n{...}"
    if not body:
        continue
    depth, start, i = 0, 0, 0
    # split the top-level {…} entries (long brackets never contain "]======]" so a scan for it is safe)
    items, cur = [], 0
    while cur < len(body):
        j = body.index("]======]}", cur) + len("]======]}")
        items.append(body[cur:j].lstrip(",\n"))
        cur = j
    for it in items:
        hunks.append((name, it))

parts, cur, size = [], [], 0
for h in hunks:
    if cur and size + len(h[1]) > maxb:
        parts.append(cur)
        cur, size = [], 0
    cur.append(h)
    size += len(h[1]) + 40
if cur:
    parts.append(cur)

for k, p in enumerate(parts, start=1):
    lines = ["_G.SS_ops = _G.SS_ops or {}" if k > 1 else "_G.SS_ops = {}"]
    for name, it in p:
        lines.append('_G.SS_ops["%s"] = _G.SS_ops["%s"] or {} table.insert(_G.SS_ops["%s"], %s)' % (name, name, name, it))
    n = sum(1 for _ in p)
    lines.append('return "part %d: %d ops"' % (k, n))
    open("%s_%d.lua" % (out, k), "w").write("\n".join(lines))
    print("part", k, len(p), "ops", len("\n".join(lines)), "bytes")

counts = {}
for name, _ in hunks:
    counts[name] = counts.get(name, 0) + 1
final = [
    'local src=game:GetService("ServerStorage").SmartScatterSource',
    "local function ck(s) local h=0 for i=1,#s do h=(h*31+string.byte(s,i))%1000000007 end return h end",
    'local function ap(old,ops) local L=string.split(old,"\\n"); local out,pos={},1',
    " for _,o in ops do for k=pos,o[1]-1 do table.insert(out,L[k]) end",
    '  if o[3] then for _,x in string.split(o[4],"\\n") do table.insert(out,string.sub(x,2)) end end pos=o[2] end',
    ' for k=pos,#L do table.insert(out,L[k]) end return table.concat(out,"\\n") end',
    "local ops = _G.SS_ops or {}",
    "local results = {}",
]
for name, a, b in targets:
    la, ha = ck(a)
    lb, hb = ck(b)
    final += [
        'do local m=src:FindFirstChild("%s") local s0=m and m.Source or ""' % name,
        ' if #s0~=%d or ck(s0)~=%d then return "%s base mismatch "..#s0 end' % (la, ha, name),
        ' if #(ops["%s"] or {})~=%d then return "%s ops count "..#(ops["%s"] or {}) end' % (name, counts.get(name, 0), name, name),
        ' local s1=ap(s0,ops["%s"] or {})' % name,
        ' if #s1~=%d or ck(s1)~=%d then return "%s result mismatch "..#s1.." "..ck(s1) end' % (lb, hb, name),
        ' results["%s"]=s1 end' % name,
    ]
final += [
    "for name,s1 in results do",
    " local m=src:FindFirstChild(name)",
    ' if not m then m=Instance.new("ModuleScript") m.Name=name m.Archivable=false m.Parent=src end',
    " m.Source=s1",
    "end",
    'src:SetAttribute("Version","%s") src:SetAttribute("Build",%s)' % (ver, build),
    "_G.SS_ops=nil",
    'return "pushed %s b%s"' % (ver, build),
]
open("%s_final.lua" % out, "w").write("\n".join(final))
print("final", len("\n".join(final)), "bytes")
