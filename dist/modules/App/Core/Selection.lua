--[[
	Smart Scatter — Selection: what's being worked on. One selected thing (App.selected) and, of its stack, one
	active object (App.active). The outliner, the properties, the viewport's tools and the search menu all follow it,
	so nothing else keeps its own idea of "the current one".
	A thing is { kind, folder }: a Zone, Path or Clear (a keep-clear zone) is an area folder in Workspace › SmartScatter
	(App.area is its loaded area), and Stamps is the one entry for Workspace › Stamps (no area). Further kinds come
	with the tools that make them (Core/Registry).
	Loading an area stays Generation's switchArea; whatever switches area (a new one, a delete, an undo) lands here too.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local Engine = App.Engine

	-- what an area is for: "Scatter" (painted ground to fill), "Path" (a curve things follow) or "Clear" (a keep-clear
	-- zone). Chosen when it's made; older areas are read from what they have.
	local AREA_KINDS = { Scatter = true, Path = true, Clear = true }
	App.kindOf = function(a)
		if not a then
			return nil
		end
		local k = a.folder and a.folder:GetAttribute("SS_Kind")
		if AREA_KINDS[k] then
			return k
		end
		if a.spline and #a.spline.pts > 0 and (a.count or 0) == 0 then
			return "Path"
		end
		return "Scatter"
	end
	-- the same for a folder that isn't loaded (the outliner lists every area without loading each)
	local function folderKind(f)
		local k = f:GetAttribute("SS_Kind")
		if AREA_KINDS[k] then
			return k
		end
		return (f:GetAttribute("SS_Spline") ~= nil and (f:GetAttribute("SS_Mask") or "") == "") and "Path" or "Scatter"
	end
	-- an area's kind as a thing's: a scatter area is a Zone
	local THING_KIND = { Scatter = "Zone", Path = "Path", Clear = "Clear" }

	-- an area folder as a thing
	App.thingOf = function(folder)
		return folder and { kind = THING_KIND[folderKind(folder)], folder = folder } or nil
	end
	-- the one Stamps thing (its folder, Workspace › Stamps, may not be there yet)
	App.stampsThing = function()
		return { kind = "Stamps", folder = workspace:FindFirstChild("Stamps") }
	end
	App.isArea = function(thing) -- a thing that's an area (a Zone, Path or keep-clear zone)
		return thing ~= nil and (thing.kind == "Zone" or thing.kind == "Path" or thing.kind == "Clear")
	end
	App.sameThing = function(a, b)
		if a == nil or b == nil then
			return a == b
		end
		return a.kind == b.kind and (a.kind == "Stamps" or a.folder == b.folder)
	end

	App.selected, App.active = nil, nil

	-- listeners: fn(App.selected, App.active) after every change. The panel coalesces its rebuild (Panel/Shell).
	local listeners = {}
	App.onSelect = function(fn)
		table.insert(listeners, fn)
	end
	local function notify()
		for _, fn in listeners do
			local ok, err = pcall(fn, App.selected, App.active)
			if not ok then
				warn("[Smart Scatter] " .. tostring(err))
			end
		end
	end

	-- an object of the loaded area, or nil (one that went, with an undo or a delete, isn't kept)
	local function inArea(l)
		return l ~= nil and App.area ~= nil and table.find(App.area.layers, l) ~= nil
	end

	-- switchArea (Core/Generation) calls this after it loads an area, whoever asked for it: the selection follows.
	-- The active object goes (it belonged to the area before); keep: a layer key to find again (an undo reloads the
	-- same area's objects as new tables).
	App.onAreaSwitched = function(folder, keep)
		App.selected = App.thingOf(folder)
		App.active = nil
		if keep and App.area then
			for _, l in App.area.layers do
				if Engine.layerKey(l) == keep then
					App.active = l
				end
			end
		end
		notify()
	end

	-- select a thing (nil: nothing), and optionally one object of its stack. A thing that's gone falls back to the
	-- first area there is (or nothing).
	App.select = function(thing, object)
		if thing and thing.kind ~= "Stamps" and not (thing.folder and thing.folder:IsDescendantOf(workspace)) then
			thing = App.thingOf(Engine.listAreas()[1])
		end
		if App.isArea(thing) then
			if not (App.area and App.area.folder == thing.folder) then
				App.switchArea(thing.folder) -- (notifies)
			end
			App.selected = App.thingOf(thing.folder)
		else
			if App.area then
				App.switchArea(nil)
			end
			App.selected = thing
		end
		App.active = inArea(object) and object or nil
		notify()
	end

	-- make one object of the selected thing active (nil: none). A one-object brush in use moves over to it.
	App.selectObject = function(l)
		l = inArea(l) and l or nil
		if l == App.active then
			return
		end
		App.active = l
		if App.LAYER_MODES[App.mode] and l then
			App.setMode(App.mode, l)
		elseif App.LAYER_MODES[App.mode] then
			App.setMode("Off")
		end
		if App.heatLayer and App.heatLayer ~= l then -- the heatmap belongs to the object whose page it was
			App.heatLayer = nil
			App.rebuildOverlay()
		end
		notify()
	end

	-- the object the one-object tools act on: the active one, else the selected thing's first that can be brushed
	App.brushTarget = function()
		local a = App.area
		if not a then
			return nil
		end
		local function ok(l)
			return l ~= nil and table.find(a.layers, l) ~= nil and not (Engine.isLine(l) and l.s.follow == "Spline")
		end
		if ok(App.active) then
			return App.active
		end
		for _, l in a.layers do
			if ok(l) then
				return l
			end
		end
		return nil
	end
end
