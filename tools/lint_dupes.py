"""Fails when the engine defines the same E.<name> twice (function E.x / E.x = ...): the later one silently wins."""
import collections
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parent.parent / "src" / "Engine"
seen = collections.defaultdict(list)
for p in sorted(root.rglob("*.lua")):
    for i, line in enumerate(p.read_text(encoding="utf-8").split("\n"), 1):
        m = re.match(r"^\t?function E\.(\w+)\s*\(", line) or re.match(r"^\t?E\.(\w+)\s*=", line)
        if m:
            seen[m.group(1)].append("%s:%d" % (p.stem, i))
bad = {k: v for k, v in seen.items() if len(v) > 1}
for k, v in bad.items():
    print("duplicate E.%s at %s" % (k, ", ".join(v)))
sys.exit(1 if bad else 0)
