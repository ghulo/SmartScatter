--[[
	Smart Scatter — App: the plugin's panel and viewport tools, built on the Engine.

	Each module below is `return function(App) … end` and runs once, in ORDER, against one shared App table: a module
	puts its state and functions on App, and later modules read them from there. A module that returns a function
	hands back its cleanup (the last one returned runs when the plugin unloads or updates).
	  Core/        state, UI kit, cards and search, generation jobs, and the undo/cleanup wiring that runs last
	  Viewport/    what happens in the 3D view: the painted overlay, painting, the spline editor
	  Panel/       the header, the controls for areas, objects and the map, the shell (tabs, search, bottom bar), the tour
	  Panel/Tabs/  one module per tab: Scatter, Brush, Map, Settings
	To add a module: create it in the folder it belongs to and add its path to ORDER after what it uses.
]]

local ORDER = {
	"Core/State",
	"Core/Kit",
	"Core/Cards",
	"Viewport/Overlay",
	"Core/Generation",
	"Core/History",
	"Panel/Header",
	"Panel/AreaTools",
	"Panel/ObjectTools",
	"Panel/HandTools",
	"Panel/MapTools",
	"Panel/Tabs/Scatter",
	"Panel/Tabs/Brush",
	"Panel/Tabs/Map",
	"Panel/Tabs/Settings",
	"Panel/Shell",
	"Viewport/Paint",
	"Viewport/Grid",
	"Viewport/Spline",
	"Viewport/Shapes",
	"Viewport/Stamp",
	"Viewport/Focus",
	"Panel/Palette",
	"Panel/Tour",
	"Core/Lifecycle",
}

local function module(path) -- (a flattened release swaps this line for its own table of modules)
	local node = script
	for part in string.gmatch(path, "[^/]+") do
		node = node:FindFirstChild(part)
	end
	return require(node)
end

-- ctx: what the loader passes in (plugin, button, widget, Engine, version…)
return function(ctx)
	local App = { ctx = ctx }
	local cleanup
	for _, path in ORDER do
		local r = module(path)(App)
		if r ~= nil then
			cleanup = r
		end
	end
	return cleanup
end
