#!/bin/sh
# Offline checks before any push: formatting, the module tree, compile at Studio's debug level (and its 200-local
# limit), duplicate engine names, unknown globals. SS_TOOLS: the folder holding stylua, luau-compile, luau-analyze.
set -e
cd "$(dirname "$0")/.."
S=${SS_TOOLS:-$HOME/.local/bin}
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
MODULES=$(find src -name "*.lua" | sort)
for f in $MODULES Loader.lua tests/suite.lua; do stylua --check --config-path stylua.toml "$f" >/dev/null || { echo "format: $f"; exit 1; }; done
# every module listed in its entry's ORDER, and the flattened copies older loaders get
python3 - "$T" <<'PY'
import sys, pathlib
sys.path.insert(0, "tools")
import tree as T
t = T.tree()
T.check(t)
out = pathlib.Path(sys.argv[1])
(out / "Engine.lua").write_text(T.flatten(t, "Engine")[0])
for k, s in enumerate(T.flatten(t, "App", "Main_%d"), start=1):
    (out / ("Main.lua" if k == 1 else "Main_%d.lua" % k)).write_text(s)
PY
sed -e "s/__BUILD__/1/" Loader.lua > "$T/Loader.lua"
for f in $MODULES "$T"/*.lua tests/suite.lua; do "$S/luau-compile" --binary -O0 -g2 "$f" >/dev/null || { echo "compile: $f"; exit 1; }; done
python3 tools/lint_dupes.py
# anything the analyzer doesn't know that isn't a Roblox global we already use is a typo or a missing local/import
for f in $MODULES "$T/Loader.lua"; do
  "$S/luau-analyze" "$f" 2>&1 | grep -o "Unknown global '[^']*'" | sort -u | comm -23 - tools/known_globals.txt > "$T/globals.txt" || true
  if [ -s "$T/globals.txt" ]; then echo "unknown globals in $f:"; cat "$T/globals.txt"; exit 1; fi
done
# an import from I that nothing uses is dead weight
for f in src/Engine/*.lua; do
  "$S/luau-analyze" "$f" 2>&1 | grep "LocalUnused" | while read -r line; do
    n=$(echo "$line" | sed -n "s/.*Variable '\([^']*\)'.*/\1/p")
    if grep -q "^	local $n = I\.$n$" "$f"; then echo "unused import $n in $f"; exit 1; fi
  done || exit 1
done
echo "offline checks: ok ($(echo "$MODULES" | wc -l) modules)"
