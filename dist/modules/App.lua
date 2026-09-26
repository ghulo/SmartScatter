--[[
	Smart Scatter — App: the plugin's panel and viewport tools, built on the Engine.

	Each module below is `return function(App) … end` and runs once, in ORDER, against one shared App table: a module
	puts its state and functions on App, and later modules read them from there. A module that returns a function
	hands back its cleanup (the last one returned runs when the plugin unloads or updates).
	  Core/      state, UI kit, generation jobs, and the undo/cleanup wiring that runs last
	  Viewport/  what happens in the 3D view: the painted overlay, painting, the spline editor
	  Panel/     the pages of the panel
	To add a module: create it in the folder it belongs to and add its path to ORDER after what it uses.
]]

local ORDER = {
	"Core/State",
	"Core/Kit",
	"Viewport/Overlay",
	"Core/Generation",
	"Panel/Header",
	"Panel/AreaPage",
	"Panel/ObjectsPage",
	"Panel/Settings",
	"Viewport/Paint",
	"Viewport/Spline",
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
