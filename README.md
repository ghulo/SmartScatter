# Smart Scatter

A Roblox Studio plugin that fills your map by rules instead of by hand. Paint an area (or draw a path), pick your
models, and it places them: trees keep off roads and roofs, rocks cluster, lamps line a road, fences meet end to end
round bends, and everything updates live as you tweak it.

## Features

- **Scatter areas** — paint with brush, lasso, box, polygon or smart fill, or fill the tops of selected parts
- **Paths** — draw a curve for roads, fences, walls, tiled paths or rows of lamps; branches and junctions join cleanly
- **Rules per object** — size, spacing, clumping, piles, slopes, surfaces, height bands, distance from roads/water/buildings
- **Keep-clear zones** — ground no area may place anything on (spawns, doorways)
- **Biomes and presets** — start from a Forest/Meadow/Desert/Town mix made from your own models, or save your own sets
- **Game-ready output** — optional streaming chunks, no-collision plants, shadow and click settings; a heaviness warning
- **Undo everything** — every edit is one Ctrl+Z step

## Install

Get it from the Creator Store, or download `SmartScatter.rbxmx` from the latest release and put it in your
Studio plugins folder (Plugins → Plugins Folder).

The plugin updates itself: when Studio starts (and every half hour) it checks this repository's `dist` folder and,
if there's a newer build, downloads it. Studio asks once for permission to reach `raw.githubusercontent.com`;
allow it to receive updates. Nothing else is sent anywhere.

## Development

The plugin is generated from the sources in `src/`:

| Path | What it is |
|---|---|
| `Loader.lua` | the installed script: picks the newest code (bundled, saved update, or online release) and runs it |
| `src/engine/NN_*.lua` | the placement engine, concatenated in order into `Engine.lua` |
| `src/*.lua` | the panel, one module each (`return function(App) … end`), bundled into `Main.lua` (+ `Main_2.lua`) |
| `tests/suite.lua` | the regression suite: paste into Studio's command bar with the plugin running |
| `tools/` | bundlers, checks and the live-push tool used during development |

Requirements: Python 3; for `tools/check.sh` also `stylua`, `luau-compile` and `luau-analyze` (set `SS_TOOLS` to the
folder holding them).

```sh
./tools/check.sh                 # format, compile and lint checks
python3 build.py 9.29 89         # version, build number -> SmartScatter.rbxmx and dist/
```

### Releasing an update

1. Bump the version and **build number** (the build must be higher than the last release) and run `build.py`.
2. Commit and push `dist/` — every installed copy picks it up on its next check.
3. Attach `SmartScatter.rbxmx` to a GitHub release, and update the Creator Store copy now and then so new installs
   start recent.

Only people who can push to this repository can publish updates, so keep write access tight.

## License

MIT — see `LICENSE`.
