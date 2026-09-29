--[[
	Smart Scatter — Select: the strip's Select tool. Point at something Smart Scatter made and it's named by the mouse;
	a click selects it (Core/Selection), so the panel shows it:
	  a placed copy     its zone, with its object active
	  a path            the path (its curve, or a point of it, within a few pixels on screen)
	  painted ground    the zone painted there (a keep-clear zone if no zone is)
	Studio's own selection is left as it was. Paint hands the viewport's mouse to it while the mode is "Select".
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local Engine, HttpService = App.Engine, game:GetService("HttpService")
	local rawMouse = App.rawMouse
	local NEAR_PX = 10 -- how close on screen a path has to be to the mouse

	-- each area's painted cells and path points, read from its saved attributes and kept until they change
	local cache = setmetatable({}, { __mode = "k" }) -- [folder] = { mask = attr, cells = { [key] = true }, spline = attr, pts = { Vector3 } }
	local function shapeOf(f)
		local c = cache[f]
		if not c then
			c = {}
			cache[f] = c
		end
		local mask = f:GetAttribute("SS_Mask") or ""
		if c.mask ~= mask then
			c.mask, c.cells = mask, {}
			for cz, rest in string.gmatch(mask, "(-?%d+):([^|]*)") do
				for s, e in string.gmatch(rest, "(-?%d+)~(-?%d+)") do
					for cx = tonumber(s), tonumber(e) do
						c.cells[cx * 1000003 + tonumber(cz)] = true
					end
				end
			end
			c.cell = f:GetAttribute("SS_Cell") or Engine.MASK_CELL
		end
		local spline = f:GetAttribute("SS_Spline") or ""
		if c.spline ~= spline then
			c.spline, c.curves = spline, {}
			local ok, sd = pcall(HttpService.JSONDecode, HttpService, spline ~= "" and spline or "null")
			if ok and type(sd) == "table" then
				for _, list in { { sd.pts }, sd.branches or {}, sd.loops or {} } do
					for _, pts in list do
						local curve = {}
						for _, q in type(pts) == "table" and pts or {} do
							if type(q) == "table" and #q >= 3 then
								table.insert(curve, Vector3.new(q[1], q[2], q[3]))
							end
						end
						if #curve > 0 then
							table.insert(c.curves, curve)
						end
					end
				end
			end
		end
		return c
	end

	-- how far a world line segment is from the mouse on screen (a point: a = b)
	local cam = function()
		return workspace.CurrentCamera
	end
	local function screen(p)
		local v, on = cam():WorldToViewportPoint(p)
		return Vector2.new(v.X, v.Y), on and v.Z > 0
	end
	local function segDist(m, a, b)
		local pa, oka = screen(a)
		local pb, okb = screen(b)
		if not (oka or okb) then
			return math.huge
		end
		local ab = pb - pa
		local t = ab.Magnitude > 1e-3 and math.clamp((m - pa):Dot(ab) / ab:Dot(ab), 0, 1) or 0
		return (m - (pa + ab * t)).Magnitude
	end

	-- what's under the mouse: thing, object (a layer key), and a word for it; nil when nothing of ours
	App.pickAt = function()
		local out = workspace:FindFirstChild(Engine.OUT)
		if not out then
			return nil
		end
		-- 1. a placed copy
		local ray = rawMouse.UnitRay
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Include
		rp.FilterDescendantsInstances = { out }
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 5000, rp)
		if hit then
			local key, area
			local cur = hit.Instance
			while cur and cur ~= out do
				key = key or cur:GetAttribute("SS_Key")
				if cur.Parent == out then
					area = cur
				end
				cur = cur.Parent
			end
			if area then
				return App.thingOf(area), key
			end
		end
		-- 2. a path near the mouse
		local m = Vector2.new(rawMouse.X, rawMouse.Y)
		local best, bestD = nil, NEAR_PX
		for _, f in Engine.listAreas() do
			for _, curve in shapeOf(f).curves do
				for i = 1, #curve do
					local d = segDist(m, curve[i], curve[math.min(i + 1, #curve)])
					if d < bestD then
						best, bestD = f, d
					end
				end
			end
		end
		if best then
			return App.thingOf(best)
		end
		-- 3. painted ground: a zone's, else a keep-clear zone's
		local g = App.mouseHit()
		if g then
			local clear
			for _, f in Engine.listAreas() do
				local c = shapeOf(f)
				local k = math.floor(g.Position.X / c.cell) * 1000003 + math.floor(g.Position.Z / c.cell)
				if c.cells[k] then
					local t = App.thingOf(f)
					if t.kind ~= "Clear" then
						return t
					end
					clear = clear or t
				end
			end
			return clear
		end
		return nil
	end

	-- the mouse moved with Select on: name what a click would select
	App.selectMove = function()
		local thing, key = App.pickAt()
		local g = App.mouseHit()
		App.gizmoFolder()
		for _, k in { "ring", "disc", "halo", "sq", "dot" } do
			if App.gz[k] then
				App.gz[k].Visible = false
			end
		end
		if thing and g then
			App.gz.anchor.CFrame = CFrame.new(g.Position)
			local what = thing.folder and thing.folder.Name or "?"
			if key then
				what ..= " · " .. (string.match(key, "([^%.]+)$") or key)
			end
			App.setLabel("Click to select " .. what)
		else
			App.setLabel("")
		end
	end
	-- a click with Select on
	App.selectDown = function()
		local thing, key = App.pickAt()
		if not thing then
			return
		end
		local object
		if key then
			App.select(thing)
			for _, l in App.area and App.area.layers or {} do
				if Engine.layerKey(l) == key then
					object = l
				end
			end
		end
		App.select(thing, object)
		App.status("Selected " .. (thing.folder and thing.folder.Name or thing.kind) .. (object and (" · " .. object.inst.Name) or "") .. ".")
	end

	App.registerTool({
		id = "select",
		group = "Select",
		icon = "cursor",
		name = "Select: click a zone, a path or a placed copy",
		on = function()
			return App.mode == "Select"
		end,
		click = function()
			App.setMode(App.mode == "Select" and "Off" or "Select")
		end,
	})
end
