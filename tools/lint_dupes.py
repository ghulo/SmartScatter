"""Fails when Engine.lua defines the same E.<name> twice (function E.x / E.x = ...), which silently replaces the first."""
import re, sys, collections
src = open(sys.argv[1] if len(sys.argv) > 1 else "Engine.lua").read().split("\n")
seen = collections.defaultdict(list)
for i, line in enumerate(src, 1):
    m = re.match(r"^function E\.(\w+)\s*\(", line) or re.match(r"^E\.(\w+)\s*=", line)
    if m:
        seen[m.group(1)].append(i)
bad = {k: v for k, v in seen.items() if len(v) > 1}
for k, v in bad.items():
    print(f"duplicate E.{k} at lines {v}")
sys.exit(1 if bad else 0)
