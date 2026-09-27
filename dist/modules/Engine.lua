--[[
	Smart Scatter — Engine: the placement engine, with no UI. The plugin (App) drives it; the test suite too.
	Area mask → scan (surface classes + distance fields) → plan (rules → counts) → place → lines along edges and paths.
	Kinds reads a finished map: repeated models grouped by shape, and the snapshot that keeps their originals;
	Seasons turns it snowy, autumn or dry.
	Upright placement: a model's "up" is how it stands in the world, never its pivot rotation.

	Each module below is `return function(E, I) … end` and runs once, in ORDER:
	  E — the engine's API: what the plugin and the suite call.
	  I — internals the modules share with each other (helpers, tables); not for use outside the engine.
	A module may use what an earlier one put on E or I. To add a module: create it here and add its name to ORDER.
]]

local ORDER = { "Scan", "Assets", "Areas", "Paths", "Planning", "Placement", "Lines", "Pins", "Generate", "Kinds", "Seasons" }

local function module(name) -- (a flattened release swaps this line for its own table of modules)
	return require(script:FindFirstChild(name))
end

local E = {}
E.TAG = "SmartScatter" -- CollectionService tag on every placed copy
E.OUT = "SmartScatter" -- workspace folder holding the areas
E.ROADS = "SmartScatter Roads" -- road surfaces, one folder per area (kept outside E.OUT so raycasts hit them)
E.MASK_CELL = 4 -- area mask resolution in studs (older 8-stud areas are upgraded on load)

local I = {}
for _, name in ORDER do
	module(name)(E, I)
end
return E
