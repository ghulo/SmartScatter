#!/bin/sh
# Offline checks before any push: formatting, compile at Studio's debug level, duplicate engine names, unknown globals.
set -e
cd "$(dirname "$0")/.."
S=${SS_TOOLS:-$HOME/.local/bin}
for f in src/*.lua; do stylua --check --config-path stylua.toml "$f" >/dev/null || { echo "format: $f"; exit 1; }; done
python3 tools/bundle.py >/dev/null
python3 tools/bundle_engine.py >/dev/null
for f in Main.lua $(ls | grep -E "^Main_[0-9]+\.lua$") Engine.lua tests/suite.lua; do "$S/luau-compile" --binary -O0 -g2 "$f" >/dev/null || { echo "compile: $f"; exit 1; }; done
python3 tools/lint_dupes.py Engine.lua
# anything the analyzer doesn't know that isn't a Roblox global we already use is a typo or a missing local
for f in Main.lua $(ls | grep -E "^Main_[0-9]+\.lua$") Engine.lua; do
  "$S/luau-analyze" "$f" 2>&1 | grep -o "Unknown global '[^']*'" | sort -u | comm -23 - tools/known_globals.txt > /tmp/ss_globals.txt || true
  if [ -s /tmp/ss_globals.txt ]; then echo "unknown globals in $f:"; cat /tmp/ss_globals.txt; exit 1; fi
done
echo "offline checks: ok"
