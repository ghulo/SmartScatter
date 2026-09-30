--[[
	Smart Scatter — Select: the strip's Select tool. Point at something Smart Scatter made and it's named by the mouse;
	a click selects it (Core/Selection), so the panel shows it:
	  a placed copy     its zone, with its object active
	  a path            the path (its curve, or a point of it, within a few pixels on screen)
	  painted ground    the zone painted there (a keep-clear zone if no zone is)
	A click on a placed copy also picks that one copy: it's outlined, Shift + the wheel turns it and Alt + the wheel
	sizes it (as the stamp's), the stamp's keys work on it, and Shift + right-click on a copy, or a second click on the
	picked one, has the rest (another model,
	moving it, giving it back to the rules, removing it). A copy changed this way becomes a stamp's pin of its object
	(Engine/Pins), so generating puts it back just as it was left.
	Studio's own selection is left as it was. Paint hands the viewport's mouse to it while the mode is "Select".
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local Engine, HttpService = App.Engine, game:GetService("HttpService")
	local rawMouse, P = App.rawMouse, App.P
	local STEP = math.rad(15) -- a turn's step (the stamp's)
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

	-- what's under the mouse: thing, object (a layer key), and the placed copy itself; nil when nothing of ours
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
			local key, area, copy
			local cur = hit.Instance
			while cur and cur ~= out do
				copy = copy or (cur:GetAttribute("SS_Type") and cur or nil)
				key = key or cur:GetAttribute("SS_Key")
				if cur.Parent == out then
					area = cur
				end
				cur = cur.Parent
			end
			if area then
				return App.thingOf(area), key, key and copy or nil
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

	--------------------------------------------------------------------------------
	-- One placed copy, picked
	--------------------------------------------------------------------------------
	-- picked: { folder = its area's, key = its object's, x, z = where it stands, copy = the instance (another one
	-- after its spot is rebuilt), l, pin = its object and pin once it was changed }; moving: the next click on the
	-- ground puts it there
	local picked, moving = nil, false

	-- an outline round a copy (name: which of the two, the picked one's or the one under the mouse)
	local function light(name, copy, fill)
		App.gizmoFolder()
		local h = App.gz[name]
		if not (h and h.Parent) then
			if not copy then
				return
			end
			h = Instance.new("Highlight")
			h.DepthMode = Enum.HighlightDepthMode.Occluded
			h.OutlineTransparency = 0
			h.Parent = App.gz.folder
			App.gz[name] = h
		end
		h.FillColor, h.OutlineColor = P.accent, P.accent
		h.FillTransparency = fill
		h.Adornee = copy
	end
	-- the picked copy's instance now: the one picked, or (its spot rebuilt since) the one standing there
	local function pickedCopy()
		if not picked then
			return nil
		end
		if picked.copy and picked.copy.Parent then
			return picked.copy
		end
		picked.copy = nil
		local a = App.area
		if not (a and a.folder == picked.folder) then
			return nil
		end
		for _, f in a.folder:GetChildren() do
			if f:GetAttribute("SS_Key") == picked.key then
				for _, d in f:GetDescendants() do
					local x, z = d:GetAttribute("SS_X"), d:GetAttribute("SS_Z")
					if x and z and d:GetAttribute("SS_Type") and math.abs(x - picked.x) < 0.05 and math.abs(z - picked.z) < 0.05 then
						picked.copy = d
						return d
					end
				end
			end
		end
		return nil
	end
	-- "Rock · 45° · 1.20×"
	local function describe(copy)
		local pose = App.area and Engine.copyPose(App.area, copy)
		if not pose then
			return copy.Name
		end
		return string.format("%s · %d° · %.2f×", copy.Name, math.floor(math.deg(pose.yaw) + 0.5) % 360, pose.k)
	end
	local function showPicked()
		local copy = pickedCopy()
		light("copySel", copy, 0.8)
		if copy then
			App.gz.anchor.CFrame = CFrame.new(copy:GetPivot().Position)
			App.setLabel(moving and "Click where it should stand" or (describe(copy) .. "  ·  Shift + right-click for more"))
		end
	end
	local function unpick()
		picked, moving = nil, false
		light("copySel", nil, 0.8)
		light("copyHover", nil, 1)
		if App.closeViewMenu then
			App.closeViewMenu()
		end
	end
	-- after a change its spot is rebuilt a moment later: the outline goes to the copy that comes back
	local function follow()
		local mine = picked
		task.spawn(function()
			for _ = 1, 60 do
				task.wait(0.05)
				if picked ~= mine or App.mode ~= "Select" then
					return
				end
				if pickedCopy() then
					showPicked()
					return
				end
			end
		end)
	end

	-- One change to the picked copy: change(pose) -> { x, z, yaw, k, vi } (what it leaves out stays). The copy becomes
	-- (or already is) a stamp's pin of its object, and its spot is rebuilt at once, Live on or off. One undo step.
	local function edit(what, change)
		local a = App.area
		if not (picked and a and a.folder == picked.folder) then
			return false
		end
		if a.locked then
			App.status("This area is locked. Unlock it to change its copies.")
			return false
		end
		if not App.canGenerate() then
			App.status("The area can't be rebuilt right now: the Generate button says why.")
			return false
		end
		local copy = pickedCopy()
		local pose = copy and Engine.copyPose(a, copy)
		if not pose and not copy and picked.pin and picked.l.pins and table.find(picked.l.pins, picked.pin) then
			-- (changed again before its spot was rebuilt: the pin is changed, there's no copy to read)
			local q = picked.pin
			pose = { l = picked.l, vi = q[6], x = q[1], z = q[2], yaw = q[4], k = q[5], pin = q }
		end
		if not pose then
			App.status(copy and "This copy can't be changed by itself (a piece of a line, or a preview box)." or "That copy is gone.")
			return false
		end
		local l = pose.l
		local fromX, fromZ = pose.x, pose.z
		local c = change(pose)
		local pin
		if copy then
			pin = Engine.pinCopy(a, copy, c)
		else
			pin = Engine.changePin(l, pose.pin, c)
		end
		if not pin then
			return false
		end
		local v = l.variants[pin[6]] or l.variants[1]
		local r = v.m.radius * pin[5] * v.size * 2 + 6 -- (the patch rebuilt: where it stood and where it stands)
		local box = { math.min(fromX, pin[1]) - r, math.min(fromZ, pin[2]) - r, math.max(fromX, pin[1]) + r, math.max(fromZ, pin[2]) + r }
		picked.copy, picked.x, picked.z, picked.l, picked.pin = nil, pin[1], pin[2], l, pin
		light("copySel", nil, 0.8)
		App.applyNow(l, what, box, true) -- (its pin alone: every other copy there stays as it is)
		follow()
		return true
	end
	local function turn(dir)
		return edit("Turn a copy", function(pose)
			return { yaw = (math.floor(pose.yaw / STEP + 0.5) + dir) * STEP }
		end)
	end
	local function size(dir)
		return edit("Size a copy", function(pose)
			return { k = math.clamp(pose.k * 1.1 ^ dir, 0.05, 20) }
		end)
	end
	local function nextModel()
		return edit("Change a copy's model", function(pose)
			return { vi = pose.vi % #pose.l.variants + 1 }
		end)
	end
	local function moveTo(pos)
		local a = App.area
		if not (a and Engine.hasCell(a, math.floor(pos.X / a.cell), math.floor(pos.Z / a.cell))) then
			App.status("Click on this zone's painted ground to move it there.")
			return false
		end
		return edit("Move a copy", function()
			return { x = pos.X, z = pos.Z }
		end)
	end
	-- takes it out for good (as the Remove copies tool does)
	local function remove()
		local a, copy = App.area, pickedCopy()
		if not (a and copy) or a.locked then
			return false
		end
		local rec = App.beginRec("Smart Scatter: Remove copy")
		local h = Engine.removeCopy(a, copy)
		for _, l in a.layers do
			if l._h == h and App.lastCounts[l] then
				App.lastCounts[l] = math.max(App.lastCounts[l] - 1, 0)
			end
		end
		App.saveArea()
		App.endRec(rec)
		unpick()
		App.setLabel("")
		App.refreshCounts()
		App.status("Removed. Ctrl+Z brings it back.")
		return true
	end
	-- gives a changed copy back to the rules: the one they place there comes back
	local function backToRules()
		local a, copy = App.area, pickedCopy()
		if not (a and copy) or a.locked or not App.canGenerate() then
			return false
		end
		local pose = Engine.copyPose(a, copy)
		if not (pose and Engine.unpinCopy(a, copy)) then
			return false
		end
		picked.copy, picked.pin = nil, nil
		light("copySel", nil, 0.8)
		-- (its object is placed again in full: the rules put every copy back exactly where it was, this one too)
		App.applyNow(pose.l, "Give a copy back to its rules")
		follow()
		return true
	end

	-- picks one copy (its zone selected, its object active)
	local function pick(thing, key, copy)
		local object
		App.select(thing)
		for _, l in App.area and App.area.layers or {} do
			if Engine.layerKey(l) == key then
				object = l
			end
		end
		App.select(thing, object)
		if App.mode ~= "Select" then -- (selecting a thing may put the tool away: a picked copy is the Select tool's)
			return object
		end
		picked = { folder = thing.folder, key = key, copy = copy, x = copy:GetAttribute("SS_X") or 0, z = copy:GetAttribute("SS_Z") or 0 }
		moving = false
		light("copyHover", nil, 1)
		showPicked()
		return object
	end
	-- what can be done to the picked copy (Shift + right-click, or a second click on it)
	local function menu()
		local a, copy = App.area, pickedCopy()
		local pose = a and copy and Engine.copyPose(a, copy)
		local items = {}
		if pose then
			table.insert(items, {
				"Turn 15°",
				function()
					turn(1)
				end,
			})
			table.insert(items, {
				"Turn 15° back",
				function()
					turn(-1)
				end,
			})
			table.insert(items, {
				"Bigger",
				function()
					size(1)
				end,
			})
			table.insert(items, {
				"Smaller",
				function()
					size(-1)
				end,
			})
			if #pose.l.variants > 1 then
				table.insert(items, { "Another of its models", nextModel })
			end
			table.insert(items, {
				"Move it…",
				function()
					moving = true
					showPicked()
					App.status("Click this zone's painted ground where it should stand. Esc leaves it where it is.")
				end,
			})
			table.insert(items, "-")
			if Engine.canUnpinCopy(a, copy) then
				table.insert(items, { "Back to its rules", backToRules, P.dim })
			end
		end
		table.insert(items, {
			"Its object's settings",
			function()
				App.openTab("object")
			end,
			P.dim,
		})
		table.insert(items, "-")
		table.insert(items, { "Remove", remove, P.danger })
		return items
	end

	-- the mouse moved with Select on: name what a click would select; the picked copy keeps its outline
	App.selectMove = function()
		local thing, key, copy = App.pickAt()
		local g = App.mouseHit()
		App.gizmoFolder()
		for _, k in { "ring", "disc", "halo", "sq", "dot" } do
			if App.gz[k] then
				App.gz[k].Visible = false
			end
		end
		local mine = pickedCopy()
		light("copySel", mine, 0.8)
		light("copyHover", not moving and copy ~= mine and copy or nil, 1)
		if moving or (mine and (copy == mine or not thing)) then
			showPicked()
		elseif thing and g then
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
		if moving then -- the picked copy goes where the click lands
			local g = App.mouseHit()
			if g and moveTo(g.Position) then
				moving = false
			end
			return
		end
		local thing, key, copy = App.pickAt()
		if not thing then
			unpick()
			return
		end
		if copy and copy == pickedCopy() then
			-- the picked copy clicked again: its menu, by the mouse (as Shift + right-click opens it)
			App.viewMenu(menu(), string.upper(copy.Name))
			return
		end
		local object
		if copy then
			object = pick(thing, key, copy)
		else
			unpick()
			App.select(thing)
		end
		App.status(
			"Selected "
				.. (thing.folder and thing.folder.Name or thing.kind)
				.. (object and (" · " .. object.inst.Name) or "")
				.. (copy and ". Shift + wheel turns this copy, Alt + wheel sizes it, Shift + right-click (or a second click) has more." or ".")
		)
	end
	-- Shift + right-click on a copy: it's picked, and its menu opens by the mouse. (With Shift: Studio opens its own
	-- menu on a plain right-click, and a plugin can't stop it.)
	App.onRightClick(function()
		if App.mode ~= "Select" or moving or not App.shiftHeld() then
			return
		end
		local thing, key, copy = App.pickAt()
		if not copy then
			return
		end
		if copy ~= pickedCopy() then
			pick(thing, key, copy)
		end
		if picked then
			App.viewMenu(menu(), string.upper(copy.Name))
		end
	end)
	-- the wheel on the picked copy: Shift turns it, Alt sizes it (a plain notch zooms, as ever)
	local function wheel(dir)
		if App.mode ~= "Select" or not picked then
			return
		end
		local does = App.wheelDoes()
		if not does then
			return
		end
		App.holdCamera()
		if does == "turn" then
			turn(dir)
		else
			size(dir)
		end
	end
	App.track(rawMouse.WheelForward:Connect(function()
		wheel(1)
	end))
	App.track(rawMouse.WheelBackward:Connect(function()
		wheel(-1)
	end))
	-- the picked copy's keys (the stamp's, and Delete); true when the key was one of them
	App.selectKey = function(name)
		if name == "cancel" and (moving or picked) then -- first the move is dropped, then the copy let go
			if moving then
				moving = false
				showPicked()
			else
				unpick()
				App.setLabel("")
			end
			return true
		end
		if not picked then
			return false
		end
		if name == "turn" then
			turn(App.shiftHeld() and -1 or 1)
		elseif name == "grow" or name == "shrink" then
			size(name == "grow" and 1 or -1)
		elseif name == "model" then
			nextModel()
		elseif name == "delete" then
			remove()
		else
			return false
		end
		return true
	end
	-- (for the search menu, the suite and other tools)
	App.pickedCopy = pickedCopy
	App.pickCopy = pick
	App.copyMenu = menu
	App.copyEdit = { turn = turn, size = size, model = nextModel, move = moveTo, remove = remove, back = backToRules }
	-- another thing selected: the picked copy was the last one's
	App.onSelect(function(thing)
		if picked and not (thing and thing.folder == picked.folder) then
			unpick()
		end
	end)

	App.registerMode("Select", { move = App.selectMove, down = App.selectDown, stop = unpick, noArea = true })

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
