# Smart Scatter

A Roblox Studio plugin that fills your map by rules instead of by hand. Paint an area (or draw a path), pick your
models, and it places them: trees keep off roads and roofs, rocks cluster, lamps line a road, fences meet end to end
round bends, and everything updates live as you tweak it.

## Features

- **Scatter areas** — paint with brush, lasso, box, polygon or smart fill, or fill the tops of selected parts
- **Paths** — draw a curve for roads, fences, walls, tiled paths or rows of lamps; branches and junctions join cleanly
- **Rules per object** — size, spacing, clumping, piles, slopes, surfaces, height bands, distance from roads/water/buildings
- **Stamp** — put one copy down exactly: the real model shows under the mouse; drag to turn it, keys to size it or
  pick the model; it stays exactly so every time the area is generated
- **Keep-clear zones** — ground no area may place anything on (spawns, doorways)
- **Map scan** — finds every repeated model in a finished map and groups the copies into kinds by shape (renamed,
  turned and resized copies still match); a snapshot keeps the originals so they can be put back in one click
- **Swap models** — replace every copy of a kind with another model or a mix, keeping each copy's spot, turn,
  relative size and base; try it on a few copies first
- **Seasons** — turn a finished map snowy, autumn or dry, fully or in patches: part colours, SurfaceAppearance
  tints, and optionally the terrain's grass; switch seasons or take one off exactly
- **Improve layout** — re-space a kind's crowded and empty spots with the placement rules (learned from the map's
  own copies), previewed in the viewport first; hand-placed copies never move
- **Biomes and presets** — start from a Forest/Meadow/Desert/Town mix made from your own models, or save your own sets
- **Game-ready output** — optional streaming chunks, no-collision plants, shadow and click settings; a heaviness warning
- **Search menu** — press Space in the viewport (like Blender's F3): type a few letters of any action and run it
- **Undo everything** — every edit is one Ctrl+Z step, and a history timeline (a tick per step) jumps back or
  forward to any of them

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
    Scan · Assets · Areas · Paths · Planning · Placement · Lines · Pins · Generate · Kinds · Seasons · Layout
  App/                    the plugin's panel and tools  each module: return function(App) … end
    init.lua                entry: ORDER + runner
    Core/                   State · Kit (UI kit) · Cards (feature cards + search) · Generation (jobs, areas) ·
                            Lifecycle (undo, cleanup; runs last)
    Viewport/               Overlay · Paint · Grid · Spline · Shapes · Stamp · Focus
    Panel/                  Header (area menu) · AreaTools · ObjectTools · HandTools · MapTools (the controls) · Palette (the search menu) · Shell (tabs, search,
                            bottom bar) · Tour
      Tabs/                 Scatter · Brush · Map · Settings: one module per tab, a card per feature
tests/suite.lua           regression suite for Studio: builds its own world far away, checks every placement path,
                          cleans up
tests/offline/            engine tests that need no Studio (patterns, spacing and footprints, the mask, curves), run
                          by check.sh with the Luau runtime; roblox.luau stands in for the few Roblox types they use
tools/                    tree.py (the module tree + flattening), check.sh, offline.py, push.py / push_patch.py
                          (dev pushes), loader_test.py, lint_dupes.py
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

Requirements: Python 3; for `tools/check.sh` also `stylua`, `luau`, `luau-compile` and `luau-analyze` (set `SS_TOOLS`
to the folder holding them).

```sh
./tools/check.sh                 # format, module tree, compile, lint and offline engine tests
python3 build.py 9.45 107        # version, build number -> SmartScatter.rbxmx and dist/
```

### Releasing an update

1. Bump the version and **build number** (the build must be higher than the last release) and run `build.py`.
2. Commit and push `dist/` — every installed copy picks it up on its next check. `dist/release.json` + `dist/modules/`
   is the module tree (loaders from 9.45 on); `dist/manifest.json` + `Engine.lua` / `Main.lua` / `Main_2.lua`… is the
   same code flattened, for loaders installed before that. Those make only Engine, Main and parts Main_2…Main_16, and
   Studio caps a script at 200k, so `tools/tree.py` keeps each under 180k: what doesn't fit in Engine or Main goes into
   the parts (keyed "Engine/…" or "App/…"), and each collects its own. The offline tests run the engine split this way.
3. Attach `SmartScatter.rbxmx` to a GitHub release, and update the Creator Store copy now and then so new installs
   start recent.

Only people who can push to this repository can publish updates, so keep write access tight.

## License

MIT — see `LICENSE`.
