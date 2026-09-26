import difflib
def ck(s):
    h = 0
    for c in s.encode(): h = (h * 31 + c) % 1000000007
    return len(s.encode()), h
def ops(a, b):
    al = a.split("\n"); bl = b.split("\n"); r = []
    for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, al, bl, autojunk=False).get_opcodes():
        if tag != "equal":
            t = "\n".join("|" + x for x in bl[j1:j2])
            assert "]======]" not in t
            r.append("{%d,%d,%s,[======[%s]======]}" % (i1 + 1, i2 + 1, "true" if j2 > j1 else "false", t))
    return "{" + ",\n".join(r) + "}"
