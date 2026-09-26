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

The plugin updates itself: when Studio starts (and every five minutes) it checks this repository's `dist` folder and,
if there's a newer build, downloads it. Studio asks once for permission to reach `raw.githubusercontent.com`;
allow it to receive updates. Nothing else is sent anywhere.

## Development

### Layout

```
Loader.lua                the installed Script: picks the newest code (bundled, saved update, online release,
                          or the live copy in the open place) and runs it
src/
  Engine/                 placement, no UI            each module: return function(E, I) … end
    init.lua                entry: constants + ORDER
    Scan · Assets · Areas · Paths · Planning · Placement · Lines · Generate
  App/                    the plugin's panel and tools  each module: return function(App) … end
    init.lua                entry: ORDER + runner
    Core/                   State · Kit (UI kit) · Generation (jobs, areas) · Lifecycle (undo, cleanup; runs last)
    Viewport/               Overlay · Paint · Spline
    Panel/                  Header · AreaPage · ObjectsPage · Settings · Tour
tests/suite.lua           regression suite: builds its own world far away, checks every placement path, cleans up
tools/                    tree.py (the module tree + flattening), check.sh, push.py / push_patch.py (dev pushes),
                          loader_test.py, lint_dupes.py
```

In Studio the plugin is the same tree: the Loader Script with the `App` and `Engine` ModuleScripts (folders inside).

### How the pieces talk

- **Engine**: modules run once, in `ORDER`. `E` is the API the plugin and the suite call; `I` holds what engine
  modules share with each other (helpers, tables), exported at the end of the module that defines them
  (`I.name = name`) and imported at the top of the ones that use them (`local name = I.name`). Nothing outside the
  engine touches `I`.
- **App**: modules run once, in `ORDER`, against one shared `App` table: a module reads what earlier ones put there
  and adds its own. The module that returns a function hands back the cleanup.

### Adding things

- A new engine feature: put it in the module it belongs to; if a later module needs a helper, export it on `I`.
- A new module: create the file in its folder and add its path to that entry's `ORDER`, after what it uses.
  `tools/check.sh` fails if a file isn't listed, a listed file is missing, an import is unused or a global is unknown.

Requirements: Python 3; for `tools/check.sh` also `stylua`, `luau-compile` and `luau-analyze` (set `SS_TOOLS` to the
folder holding them).

```sh
./tools/check.sh                 # format, module tree, compile and lint checks
python3 build.py 9.45 107        # version, build number -> SmartScatter.rbxmx and dist/
```

### Releasing an update

1. Bump the version and **build number** (the build must be higher than the last release) and run `build.py`.
2. Commit and push `dist/` — every installed copy picks it up on its next check. `dist/release.json` + `dist/modules/`
   is the module tree (loaders from 9.45 on); `dist/manifest.json` + `Engine.lua` / `Main.lua` / `Main_2.lua` is the
   same code flattened, for loaders installed before that.
3. Attach `SmartScatter.rbxmx` to a GitHub release, and update the Creator Store copy now and then so new installs
   start recent.

Only people who can push to this repository can publish updates, so keep write access tight.

## License

MIT — see `LICENSE`.
