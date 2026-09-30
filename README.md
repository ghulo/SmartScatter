# Smart Scatter

A Roblox Studio plugin that fills your map by rules instead of by hand. Paint an area (or draw a path), pick your
models, and it places them: trees keep off roads and roofs, rocks cluster, lamps line a road, fences meet end to end
round bends, and everything updates live as you tweak it.

## Features

- **One screen, like Blender** — an outliner of everything you made (zones, paths, keep-clear zones, stamps), tabs
  for what's selected (Objects, Object, Zone, Curve, Road, World), and every tool in the viewport's tool strip.
  Right-click a row for what can be done to it; drag rows to reorder them (a zone's objects are placed in that order)
- **Zones** — paint with brush, lasso, box, polygon or smart fill, or fill the tops of selected parts; or make one
  from the models selected in the Explorer and start painting at once
- **Paths** — draw a curve for roads, fences, walls, tiled paths or rows of lamps; branches and junctions join cleanly
- **Rules per object** — size, spacing, clumping, piles, slopes, surfaces, height bands, distance from roads/water/buildings
- **Stamp** — put any model down exactly, anywhere, no area needed: the real model shows under the mouse; drag to
  turn it, keys to size it or pick the model; stamps are plain models in Workspace › Stamps
- **One copy at a time** — with Select, click any placed copy: Shift + wheel turns it, Alt + wheel sizes it, and a
  second click on it moves it, swaps its model, removes it or gives it back to the rules. Nothing round it moves, and
  generating again keeps it as you left it
- **Arrays** — any model repeated in a line, a grid, a circle or along a path, like Blender's Array modifier: turn per
  copy, random turn, size and nudge, dropped onto the ground; stays editable (and follows Studio's Move tool), or bake it
- **Edit helpers** — for any models selected in Studio: drop them onto the ground (not onto each other), align them on
  X/Y/Z, space them evenly by centres or gaps, randomize their turn and size, or replace them with another model
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
if there's a newer build, downloads the modules that changed. With the panel closed it goes straight in; with it open
the plugin asks first. Studio asks once for permission to reach `raw.githubusercontent.com`; allow it to receive
updates. Nothing else is sent anywhere. ⚙ › Tour and about shows how the last check went, with a button to check now
(plugins installed before 9.89 update the same way, without that line).

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
                            Selection (the selected thing and active object) · Registry (thing kinds, property tabs,
                            tools) · History · Lifecycle (undo, cleanup; runs last)
    Viewport/               Overlay · Paint · Grid · Spline · Shapes · Stamp · Select · Focus · Toolbar (the tool strip)
    Panel/                  Header (area actions, + New) · AreaTools · ObjectTools · StampTools · HandTools · MapTools
                            (the controls) · Outliner · Properties (the selection's tabs) · Shell (the frame, search,
                            bottom bar) · Palette (the search menu) · Tour
      Tabs/                 Objects · Object · Zone · Path (Curve, Road) · Stamp · World: one module per property tab,
                            a card per feature; Settings: the ⚙ page
tests/suite.lua           regression suite for Studio: builds its own world far away, checks every placement path,
                          cleans up
tests/offline/            tests that need no Studio, run by check.sh with the Luau runtime: engine.luau (patterns, spacing
                          and footprints, the mask, curves) and loader.luau (what an update downloads, with the loader's
                          own functions); roblox.luau stands in for the few Roblox types they use
tools/                    tree.py (the module tree + flattening), check.sh, offline.py, push.py / push_patch.py
                          (dev pushes), loader_test.py, lint_dupes.py
  preview/                the panel without the plugin: server.py serves src/ to Studio, panel.lua runs the panel on
                          a board far away, dump.lua + render.py draw its layout as a PNG (and flag cut-off text),
                          shots.lua dumps several states, run_suite.lua runs tests/suite.lua against src/,
                          loader_run.lua runs Loader.lua against a stand-in update site (server.py) and checks its
                          online updates end to end
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

### Adding a tool

A feature is one module that registers its pieces with `Core/Registry`; the outliner, the properties, the viewport's
tool strip (and the panel's tool row where the strip can't show) and the search menu read them from there.

- **A tool**: `App.registerTool({ id, group, order, icon, name, key?, when?, on, click })`. `group` places it in the
  strip (`App.TOOL_GROUPS`: Select · Ground · Object · Stamp · Path · Remove · Search; a new group goes last); `on()`
  lights it; `when()` hides it when it doesn't apply; `name` is its tip (text after a `:` is the longer hint). The
  search menu lists it by itself. Its mode: add the mode to `App.setMode` callers as Paint does, and to
  `App.NO_AREA_MODES` if it needs no area.
- **A thing it makes** (an outliner row): `App.registerKind({ kind, icon, title, order, list, count?, menu?, thumb?,
  reorder? })`. `menu` is also its right-click menu; `thumb(thing)` gives the model its row pictures; `reorder = true`
  lets its rows be dragged into any order (kept on each thing's folder). A list of your own that reorders:
  `App.reorderList(onMove)`, then `add(row, index)` per row.
- **Its settings** (a property tab): `App.registerTab({ id, icon, title, order, kinds, when?, build })`; `build(page)`
  adds cards with `App.cards(page, id).add({ id, title, sub, keys, more?, build })`.
- **What it acts on**: `App.selected` (the thing) and `App.active` (its object), `App.onSelect(fn)` to follow them,
  `App.select(thing, object?)` / `App.selectObject(l)` to change them.

To look at a layout without Studio's dock widget: run `python tools/preview/server.py`, then in Studio (HttpService on
for the call) `tools/preview/panel.lua` (or `shots.lua` for several states) and `dump.lua`, then
`python tools/preview/render.py <name>`.

### Releasing an update

1. Bump the version and **build number** (the build must be higher than the last release) and run `build.py`.
2. Commit and push `dist/` — every installed copy picks it up on its next check. `dist/release.json` + `dist/modules/`
   is the module tree (loaders from 9.45 on); `dist/manifest.json` + `Engine.lua` / `Main.lua` / `Main_2.lua`… is the
   same code flattened, for loaders installed before that. Those make only Engine, Main and parts Main_2…Main_16, and
   Studio caps a script at 200k, so `tools/tree.py` keeps each under 180k: what doesn't fit in Engine or Main goes into
   the parts (keyed "Engine/…" or "App/…"), and each collects its own. The offline tests run the engine split this way.
3. Attach `SmartScatter.rbxmx` to a GitHub release, and update the Creator Store copy now and then so new installs
   start recent.

`Loader.lua` is the one file an online update can't replace: a change to it reaches people only through a new
`SmartScatter.rbxmx` (the Creator Store copy). The running code must therefore work with any loader: what a newer
loader adds to `ctx` (like `ctx.updates`) is optional to it.

Only people who can push to this repository can publish updates, so keep write access tight.

## License

MIT — see `LICENSE`.
