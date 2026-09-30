--[[
	Panel preview (a dev tool): runs the plugin's panel from src/ in the open place, drawn on a board far from the map,
	so its layout can be dumped (dump.lua) and drawn (render.py) without the plugin, a dock widget or a screenshot
	(Studio's screenshots show the 3D view only). The code comes from tools/preview/server.py (/tree.json): what's on
	disk, not the installed plugin, which is left alone.
	Run from the command bar or the MCP with HttpService on for the call. Leaves _G.SS_Preview = { app = the App
	table, cleanup = fn }; a second run replaces the first. Nothing it makes is saved with the place.
	The stand-ins: a plugin (settings in a table, no mouse), a SurfaceGui for the dock widget (360 × 860), the Engine
	built from the same tree. The tour is marked seen.
]]
local HS = game:GetService("HttpService")
local URL = "http://127.0.0.1:8766/"
if _G.SS_Preview and _G.SS_Preview.cleanup then
	pcall(_G.SS_Preview.cleanup)
end

-- the module tree, built as the loader builds it: a path's module; a path with children but no source is a Folder
local modules = HS:JSONDecode(HS:GetAsync(URL .. "tree.json", true))
local holder = Instance.new("Folder")
holder.Name = "SS_PreviewCode"
local function node(path)
	local cur, sofar = holder, ""
	for part in string.gmatch(path, "[^/]+") do
		sofar = sofar == "" and part or (sofar .. "/" .. part)
		local nxt = cur:FindFirstChild(part)
		if not nxt then
			nxt = Instance.new(modules[sofar] and "ModuleScript" or "Folder")
			nxt.Name = part
			nxt.Parent = cur
		end
		cur = nxt
	end
	return cur
end
local paths = {}
for path in modules do
	table.insert(paths, path)
end
table.sort(paths) -- (parents before their children)
for _, path in paths do
	node(path).Source = modules[path]
end
-- hand the App table out (the preview drives it)
holder.App.Source = string.gsub(holder.App.Source, "local App = { ctx = ctx }", "local App = { ctx = ctx }\n\t_G.SS_PreviewApp = App", 1)
local E = require(holder.Engine)

local function signal()
	local fns = {}
	return {
		Connect = function(_, fn)
			table.insert(fns, fn)
			return { Disconnect = function() end, Connected = true }
		end,
	}
end
-- (the tour seen; no overlay: the real plugin draws the viewport)
local store = { SmartScatter_tour = 99, SmartScatter_v3 = { overlay = false } }
local mouse = {
	Move = signal(),
	Button1Down = signal(),
	Button1Up = signal(),
	Button2Down = signal(),
	Button2Up = signal(),
	KeyDown = signal(),
	WheelForward = signal(),
	WheelBackward = signal(),
	X = 0,
	Y = 0,
	UnitRay = Ray.new(Vector3.new(0, 1e5, 0), Vector3.new(0, -1, 0)),
}
local plugin = {
	GetMouse = function()
		return mouse
	end,
	GetSetting = function(_, k)
		return store[k]
	end,
	SetSetting = function(_, k, v)
		store[k] = v
	end,
	Activate = function() end,
	Deactivate = function() end,
	Deactivation = signal(),
}

-- the dock widget: a SurfaceGui on a board far away (it has the widget's Enabled)
local W, H, PPS = 360, 860, 100
local board = Instance.new("Part")
board.Name = "SS_PanelPreviewBoard"
board.Archivable = false
board.Anchored, board.CanCollide, board.CanQuery, board.CanTouch, board.CastShadow = true, false, false, false, false
board.Size = Vector3.new(W / PPS, H / PPS, 0.05)
board.CFrame = CFrame.new(0, 1e5, 0)
board.Transparency = 1
board.Parent = workspace.CurrentCamera
local gui = Instance.new("SurfaceGui")
gui.Name = "SS_PanelPreview"
gui.Archivable = false
gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
gui.PixelsPerStud = PPS
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Adornee = board
gui.Parent = board

local cleanup = require(holder.App)({
	plugin = plugin,
	button = { Click = signal(), SetActive = function() end },
	widget = gui,
	Engine = E,
	version = "preview",
	preview = true, -- (the plugin leaves the viewport alone: no tool strip, the panel's tool row instead)
	updates = _G.SS_PreviewUpdates, -- (a stand-in for the loader's update state, when a run sets one)
})
local App = _G.SS_PreviewApp
_G.SS_PreviewApp = nil
_G.SS_Preview = {
	app = App,
	cleanup = function()
		pcall(cleanup)
		board:Destroy()
		holder:Destroy()
		_G.SS_Preview = nil
	end,
}
return "preview up: " .. tostring(#paths) .. " modules, area " .. tostring(App.area and App.area.folder.Name)
