--[[
	Smart Scatter — Select: the strip's Select tool. Point at something Smart Scatter made and it's named by the mouse;
	a click selects it (Core/Selection), so the panel shows it:
	  a placed copy     its zone, with its object active
	  a path            the path (its curve, or a point of it, within a few pixels on screen)
	  painted ground    the zone painted there (a keep-clear zone if no zone is)
	Shift + click picks more copies of the same zone (or takes one back out), and a drag over the ground boxes them;
	what's done then is done to each. The viewport's header shows what's picked, with the same changes as buttons.
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
			if area and not (App.isHidden and App.isHidden(area)) then -- (a hidden zone's copies can't be clicked)
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
	-- Placed copies, picked: one (a click), or several of one zone (Shift + click adds or takes one; a drag over the
	-- ground boxes them). What's done to them is done to each.
	--------------------------------------------------------------------------------
	-- picks: { { folder = its area's, key = its object's, x, z = where it stands, copy = the instance (another one
	-- after its spot is rebuilt), l, pin = its object and pin once it was changed } … }, the last one the main one
	-- (the label is by it; one alone can be moved). moving: the next click on the ground puts it there.
	-- press: a press that may become a box: { px = where on screen, add = Shift was held }
	local picks, moving, press = {}, false, nil
	local MAX_PICKS = 300
	local DRAG_PX = 6

	-- the outline round the copy under the mouse
	local function lightHover(copy)
		App.gizmoFolder()
		local h = App.gz.copyHover
		if not (h and h.Parent) then
			if not copy then
				return
			end
			h = Instance.new("Highlight")
			h.DepthMode = Enum.HighlightDepthMode.Occluded
			h.OutlineTransparency = 0
			h.FillTransparency = 1
			h.Parent = App.gz.folder
			App.gz.copyHover = h
		end
		h.OutlineColor = P.accent
		h.Adornee = copy
	end
	-- a pick's instance now: the one picked, or (its spot rebuilt since) the one standing there
	local function copyOf(e)
		if e.copy and e.copy.Parent then
			return e.copy
		end
		e.copy = nil
		local a = App.area
		if not (a and a.folder == e.folder) then
			return nil
		end
		for _, f in a.folder:GetChildren() do
			if f:GetAttribute("SS_Key") == e.key then
				for _, d in f:GetDescendants() do
					local x, z = d:GetAttribute("SS_X"), d:GetAttribute("SS_Z")
					if x and z and d:GetAttribute("SS_Type") and math.abs(x - e.x) < 0.05 and math.abs(z - e.z) < 0.05 then
						e.copy = d
						return d
					end
				end
			end
		end
		return nil
	end
	local function pickedCopy() -- the main one's
		local e = picks[#picks]
		return e and copyOf(e) or nil
	end
	-- a box round every picked copy (boxes, not Highlights: Studio draws only a few dozen of those)
	local function outline()
		App.gizmoFolder()
		local pool = App.gz.copyBoxes or {}
		App.gz.copyBoxes = pool
		local n = 0
		for _, e in picks do
			local c = copyOf(e)
			if c then
				n += 1
				local sb = pool[n]
				if not sb then
					sb = Instance.new("SelectionBox")
					sb.LineThickness = 0.04
					sb.SurfaceTransparency = 0.88
					sb.Parent = App.gz.folder
					pool[n] = sb
				end
				sb.Color3, sb.SurfaceColor3 = P.accent, P.accent
				sb.Adornee = c
			end
		end
		for i = n + 1, #pool do
			pool[i].Adornee = nil
		end
		return n
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
		outline()
		local copy = pickedCopy()
		if copy then
			App.gz.anchor.CFrame = CFrame.new(copy:GetPivot().Position)
			App.setLabel(
				moving and "Click where it should stand"
					or #picks > 1 and string.format("%d copies  ·  Shift + right-click for more", #picks)
					or (describe(copy) .. "  ·  Shift + right-click for more")
			)
		end
	end
	local function unpick()
		picks, moving, press = {}, false, nil
		outline()
		lightHover(nil)
		if App.closeViewMenu then
			App.closeViewMenu()
		end
		if App.viewRect then
			App.viewRect(nil)
		end
	end
	-- after a change their spots are rebuilt a moment later: the boxes go to the copies that come back
	local function follow()
		local mine = picks
		task.spawn(function()
			for _ = 1, 60 do
				task.wait(0.05)
				if picks ~= mine or App.mode ~= "Select" then
					return
				end
				local all = true
				for _, e in picks do
					all = all and copyOf(e) ~= nil
				end
				if all then
					break
				end
			end
			if picks == mine and App.mode == "Select" then
				showPicked()
			end
		end)
	end
	local function ready()
		local a = App.area
		if #picks == 0 or not a or a.folder ~= picks[1].folder then
			return nil
		end
		if a.locked then
			App.status("This area is locked. Unlock it to change its copies.")
			return nil
		end
		if not App.canGenerate() then
			App.status("The area can't be rebuilt right now: the Generate button says why.")
			return nil
		end
		return a
	end

	-- One change to every picked copy: change(pose) -> { x, z, yaw, k, vi } (what it leaves out stays). Each becomes
	-- (or already is) a stamp's pin of its object, and their spots are rebuilt at once, Live on or off: the pins
	-- alone, every other copy there stays as it is. One undo step.
	local function edit(what, change)
		local a = ready()
		if not a then
			return false
		end
		local box, done
		for _, e in picks do
			local copy = copyOf(e)
			local pose = copy and Engine.copyPose(a, copy)
			if not pose and not copy and e.pin and e.l.pins and table.find(e.l.pins, e.pin) then
				-- (changed again before its spot was rebuilt: the pin is changed, there's no copy to read)
				local q = e.pin
				pose = { l = e.l, vi = q[6], x = q[1], z = q[2], yaw = q[4], k = q[5], pin = q }
			end
			if pose then
				local l = pose.l
				local fromX, fromZ = pose.x, pose.z
				local c = change(pose)
				local pin
				if copy then
					pin = Engine.pinCopy(a, copy, c)
				else
					pin = Engine.changePin(l, pose.pin, c)
				end
				if pin then
					local v = l.variants[pin[6]] or l.variants[1]
					local r = v.m.radius * pin[5] * v.size * 2 + 6 -- (the patch rebuilt: where it stood and where it stands)
					local x0, z0 = math.min(fromX, pin[1]) - r, math.min(fromZ, pin[2]) - r
					local x1, z1 = math.max(fromX, pin[1]) + r, math.max(fromZ, pin[2]) + r
					box = box and { math.min(box[1], x0), math.min(box[2], z0), math.max(box[3], x1), math.max(box[4], z1) } or { x0, z0, x1, z1 }
					e.copy, e.x, e.z, e.l, e.pin = nil, pin[1], pin[2], l, pin
					done = true
				end
			end
		end
		if not done then
			App.status(
				#picks == 1 and "This copy can't be changed by itself (a piece of a line, or a preview box)."
					or "These copies can't be changed by themselves."
			)
			return false
		end
		outline()
		App.applyNow(nil, what, box, true) -- (their pins alone: every other copy there stays as it is)
		follow()
		return true
	end
	local function several(one, many)
		return #picks > 1 and many or one
	end
	local function turn(dir)
		return edit(several("Turn a copy", "Turn copies"), function(pose)
			return { yaw = (math.floor(pose.yaw / STEP + 0.5) + dir) * STEP }
		end)
	end
	local function size(dir)
		return edit(several("Size a copy", "Size copies"), function(pose)
			return { k = math.clamp(pose.k * 1.1 ^ dir, 0.05, 20) }
		end)
	end
	local function nextModel(dir)
		return edit(several("Change a copy's model", "Change copies' models"), function(pose)
			return { vi = (pose.vi - 1 + (dir or 1)) % #pose.l.variants + 1 }
		end)
	end
	local function moveTo(pos)
		local a = App.area
		if #picks ~= 1 then
			return false
		end
		if not (a and Engine.hasCell(a, math.floor(pos.X / a.cell), math.floor(pos.Z / a.cell))) then
			App.status("Click on this zone's painted ground to move it there.")
			return false
		end
		return edit("Move a copy", function()
			return { x = pos.X, z = pos.Z }
		end)
	end
	-- takes them out for good (as the Remove copies tool does)
	local function remove()
		local a = App.area
		if #picks == 0 or not a or a.folder ~= picks[1].folder or a.locked then
			return false
		end
		local rec = App.beginRec("Smart Scatter: " .. several("Remove copy", "Remove copies"))
		local n = 0
		for _, e in picks do
			local copy = copyOf(e)
			local h = copy and Engine.removeCopy(a, copy)
			if h then
				n += 1
				for _, l in a.layers do
					if l._h == h and App.lastCounts[l] then
						App.lastCounts[l] = math.max(App.lastCounts[l] - 1, 0)
					end
				end
			end
		end
		App.saveArea()
		App.endRec(rec)
		unpick()
		App.setLabel("")
		App.refreshCounts()
		App.status(n == 1 and "Removed. Ctrl+Z brings it back." or string.format("Removed %d. Ctrl+Z brings them back.", n))
		return n > 0
	end
	-- the picked copies that were the rules' and still stand where those put them
	local function canGoBack()
		local a, n = App.area, 0
		for _, e in picks do
			local copy = copyOf(e)
			if a and copy and Engine.canUnpinCopy(a, copy) then
				n += 1
			end
		end
		return n
	end
	-- gives changed copies back to the rules: the ones they place there come back
	local function backToRules()
		local a = ready()
		if not a then
			return false
		end
		local first
		for _, e in picks do
			local copy = copyOf(e)
			local pose = copy and Engine.copyPose(a, copy)
			if pose and Engine.unpinCopy(a, copy) then
				local i = table.find(a.layers, pose.l) or 1
				first = math.min(first or i, i)
				e.copy, e.pin = nil, nil
			end
		end
		if not first then
			return false
		end
		outline()
		-- (their objects are placed again in full: the rules put every copy back exactly where it was, these too)
		App.applyNow(a.layers[first], "Give copies back to their rules")
		follow()
		return true
	end

	local function entry(thing, key, copy)
		return { folder = thing.folder, key = key, copy = copy, x = copy:GetAttribute("SS_X") or 0, z = copy:GetAttribute("SS_Z") or 0 }
	end
	local function indexOf(copy)
		for i, e in picks do
			if copyOf(e) == copy then
				return i
			end
		end
		return nil
	end
	-- picks a copy: alone (its zone selected, its object active), or (add) one more of the same zone, or one fewer
	local function pick(thing, key, copy, add)
		if add and #picks > 0 and picks[1].folder == thing.folder and App.mode == "Select" then
			local i = indexOf(copy)
			if i then
				table.remove(picks, i)
			elseif #picks < MAX_PICKS then
				table.insert(picks, entry(thing, key, copy))
			end
			picks = table.clone(picks) -- (a new list: what was following the old one stops)
			moving = false
			showPicked()
			if #picks == 0 then
				App.setLabel("")
			end
			return nil
		end
		local object
		App.select(thing)
		for _, l in App.area and App.area.layers or {} do
			if Engine.layerKey(l) == key then
				object = l
			end
		end
		App.select(thing, object)
		if App.mode ~= "Select" then -- (selecting a thing may put the tool away: picked copies are the Select tool's)
			return object
		end
		picks = { entry(thing, key, copy) }
		moving = false
		lightHover(nil)
		showPicked()
		return object
	end
	-- Picks the copies inside a rectangle of the screen (a, b: two corners): of the zone already picked from (add),
	-- else of the zone being worked on if any of its copies are inside, else of the zone with the most inside.
	-- Returns how many.
	local function boxPick(a, b, add)
		local out = workspace:FindFirstChild(Engine.OUT)
		local cam = workspace.CurrentCamera
		if not (out and cam) then
			return 0
		end
		local x0, x1, y0, y1 = math.min(a.X, b.X), math.max(a.X, b.X), math.min(a.Y, b.Y), math.max(a.Y, b.Y)
		local keep = add and #picks > 0 and picks[1].folder or nil
		local found = {} -- [area folder] = { { key, copy } }
		for _, area in out:GetChildren() do
			if area:GetAttribute("SS_Area") and (not keep or area == keep) and not (App.isHidden and App.isHidden(area)) then
				for _, f in area:GetChildren() do
					local key = f:GetAttribute("SS_Key")
					if key and not f:GetAttribute("SS_Ghost") then
						for _, d in f:GetDescendants() do
							if d:GetAttribute("SS_Type") and d:GetAttribute("SS_X") then
								local v = cam:WorldToViewportPoint(d:GetPivot().Position)
								if v.Z > 0 and v.X >= x0 and v.X <= x1 and v.Y >= y0 and v.Y <= y1 then
									found[area] = found[area] or {}
									table.insert(found[area], { key, d })
								end
							end
						end
					end
				end
			end
		end
		local chosen = keep or (App.area and found[App.area.folder] and App.area.folder) or nil
		if not chosen then
			for area, list in found do
				if not chosen or #list > #found[chosen] then
					chosen = area
				end
			end
		end
		local list = chosen and found[chosen]
		if not list then
			return 0
		end
		local thing = App.thingOf(chosen)
		if not keep then
			if not App.sameThing(App.selected, thing) then
				App.select(thing)
			end
			if App.mode ~= "Select" then
				return 0
			end
			picks = {}
		end
		local next = table.clone(picks)
		for _, pair in list do
			if #next >= MAX_PICKS then
				break
			end
			if not indexOf(pair[2]) then
				table.insert(next, entry(thing, pair[1], pair[2]))
			end
		end
		picks = next
		moving = false
		showPicked()
		return #picks
	end

	-- what can be done to the picked copies (Shift + right-click, a second click on one, or the quick menu)
	local function menu()
		local a, copy = App.area, pickedCopy()
		local pose = a and copy and Engine.copyPose(a, copy)
		local items = {}
		if pose or #picks > 1 then
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
			if #picks == 1 and pose and #pose.l.variants > 1 then
				table.insert(items, {
					"Another of its models",
					function()
						nextModel(1)
					end,
				})
			end
			if #picks == 1 then
				table.insert(items, {
					"Move it…",
					function()
						moving = true
						showPicked()
						App.status("Click this zone's painted ground where it should stand. Esc leaves it where it is.")
					end,
				})
			end
			table.insert(items, "-")
			if canGoBack() > 0 then
				table.insert(items, { several("Back to its rules", "Back to their rules"), backToRules, P.dim })
			end
		end
		if #picks == 1 then
			table.insert(items, {
				"Its object's settings",
				function()
					App.openTab("object")
				end,
				P.dim,
			})
		end
		table.insert(items, "-")
		table.insert(items, { several("Remove", string.format("Remove %d", #picks)), remove, P.danger })
		return items
	end
	-- the viewport's header while Select is on: what's picked, and the same changes as buttons
	local function header()
		local a, copy = App.area, pickedCopy()
		if #picks == 0 or not copy then
			return "Select", { { text = "Click a zone, a path or a copy · Shift + click or drag a box for more copies" } }, "none"
		end
		local one = #picks == 1
		local pose = one and a and Engine.copyPose(a, copy) or nil
		local items = {
			{
				step = "Turn",
				value = pose and string.format("%d°", math.floor(math.deg(pose.yaw) + 0.5) % 360) or "15°",
				dec = function()
					turn(-1)
				end,
				inc = function()
					turn(1)
				end,
			},
			{
				step = "Size",
				value = pose and string.format("%.2f×", pose.k) or "10%",
				dec = function()
					size(-1)
				end,
				inc = function()
					size(1)
				end,
			},
		}
		if pose and #pose.l.variants > 1 then
			table.insert(items, {
				step = "Model",
				value = pose.l.variants[pose.vi].inst.Name,
				dec = function()
					nextModel(-1)
				end,
				inc = function()
					nextModel(1)
				end,
			})
		end
		if one then
			table.insert(items, {
				button = "Move",
				on = moving,
				click = function()
					moving = not moving
					showPicked()
				end,
			})
		end
		local back = canGoBack()
		if back > 0 then
			table.insert(items, { button = several("Back to its rules", "Back to their rules"), click = backToRules })
		end
		table.insert(items, { button = several("Remove", string.format("Remove %d", #picks)), click = remove, danger = true })
		local title = one and copy.Name or string.format("%d copies", #picks)
		local key = string.format(
			"%d|%s|%s|%d|%s",
			#picks,
			tostring(moving),
			pose and string.format("%.3f|%.3f|%d", pose.yaw, pose.k, pose.vi) or "",
			back,
			title
		)
		return title, items, key
	end

	-- the mouse moved with Select on: name what a click would select; the picked copies keep their boxes
	App.selectMove = function()
		if press and (Vector2.new(rawMouse.X, rawMouse.Y) - press.px).Magnitude > DRAG_PX then
			press.dragging = true
		end
		if press and press.dragging then -- a box being dragged out
			App.viewRect(press.px, Vector2.new(rawMouse.X, rawMouse.Y))
			App.setLabel("")
			return
		end
		local thing, key, copy = App.pickAt()
		local g = App.mouseHit()
		App.gizmoFolder()
		for _, k in { "ring", "disc", "halo", "sq", "dot" } do
			if App.gz[k] then
				App.gz[k].Visible = false
			end
		end
		outline()
		local mine = copy ~= nil and indexOf(copy) ~= nil
		lightHover(not moving and not mine and copy or nil)
		if moving or (#picks > 0 and (mine or not thing)) then
			showPicked()
		elseif thing and g then
			App.gz.anchor.CFrame = CFrame.new(g.Position)
			local what = thing.folder and thing.folder.Name or "?"
			if key then
				what ..= " · " .. (string.match(key, "([^%.]+)$") or key)
			end
			App.setLabel((copy and #picks > 0 and App.shiftHeld()) and "Click to add it" or ("Click to select " .. what))
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
		local add = App.shiftHeld()
		local thing, key, copy = App.pickAt()
		if not copy then -- on the ground or on nothing: a click selects what's there, a drag boxes copies
			press = { px = Vector2.new(rawMouse.X, rawMouse.Y), add = add, thing = thing }
			return
		end
		if not add and indexOf(copy) then
			-- a picked copy clicked again: the menu, by the mouse (as Shift + right-click opens it)
			App.viewMenu(menu(), #picks == 1 and string.upper(copy.Name) or string.format("%d COPIES", #picks))
			return
		end
		local object = pick(thing, key, copy, add)
		if #picks > 1 then
			App.status(string.format("%d copies picked. Shift + wheel turns them, Alt + wheel sizes them; the bar at the top has the rest.", #picks))
		elseif #picks == 1 then
			App.status(
				"Selected "
					.. (thing.folder and thing.folder.Name or thing.kind)
					.. (object and (" · " .. object.inst.Name) or "")
					.. ". Shift + wheel turns this copy, Alt + wheel sizes it; Shift + click adds more."
			)
		end
	end
	-- the button let go: a drag's box picks the copies in it; a plain click selects what was under it
	App.selectUp = function()
		local pr = press
		press = nil
		if not pr then
			return
		end
		App.viewRect(nil)
		if pr.dragging then
			local n = boxPick(pr.px, Vector2.new(rawMouse.X, rawMouse.Y), pr.add)
			App.status(
				n > 0 and string.format("%d cop%s picked. The bar at the top turns, sizes and removes them.", n, n == 1 and "y" or "ies")
					or "No copies in that box."
			)
			return
		end
		if pr.add and #picks > 0 then
			return -- (Shift + a click beside the copies: nothing is let go)
		end
		unpick()
		App.setLabel("")
		if pr.thing then
			App.select(pr.thing)
			App.status("Selected " .. (pr.thing.folder and pr.thing.folder.Name or pr.thing.kind) .. ".")
		end
	end
	-- Shift + right-click on a copy: it's picked (if it wasn't), and the menu opens by the mouse. (With Shift: Studio
	-- opens its own menu on a plain right-click, and a plugin can't stop it.)
	App.onRightClick(function()
		if App.mode ~= "Select" or moving or not App.shiftHeld() then
			return
		end
		local thing, key, copy = App.pickAt()
		if not copy then
			return
		end
		if not indexOf(copy) then
			pick(thing, key, copy)
		end
		if #picks > 0 then
			App.viewMenu(menu(), #picks == 1 and string.upper(copy.Name) or string.format("%d COPIES", #picks))
		end
	end)
	-- the wheel on the picked copies: Shift turns them, Alt sizes them (a plain notch zooms, as ever)
	local function wheel(dir)
		if App.mode ~= "Select" or #picks == 0 then
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
	-- the picked copies' keys (the stamp's, and Delete); true when the key was one of them
	App.selectKey = function(name)
		if name == "cancel" and (moving or press or #picks > 0) then -- first what's half done is dropped, then the copies let go
			if moving or press then
				moving, press = false, nil
				App.viewRect(nil)
				showPicked()
			else
				unpick()
				App.setLabel("")
			end
			return true
		end
		if #picks == 0 then
			return false
		end
		if name == "turn" then
			turn(App.shiftHeld() and -1 or 1)
		elseif name == "grow" or name == "shrink" then
			size(name == "grow" and 1 or -1)
		elseif name == "model" then
			nextModel(1)
		elseif name == "delete" then
			remove()
		else
			return false
		end
		return true
	end
	-- The quick menu (its key, Z): the picked copies' actions round the mouse, or with none picked the tools, one of
	-- each group. Where the viewport can't show it, the search menu opens.
	App.openQuick = function()
		local items, title = {}, nil
		if App.mode == "Select" and #picks > 0 then
			for _, it in menu() do
				if type(it) == "table" then
					table.insert(items, it)
				end
			end
			title = #picks == 1 and "COPY" or string.format("%d COPIES", #picks)
		else
			for _, g in App.toolGroups() do
				local t = g.tools[1]
				if t and t.id ~= "search" then
					table.insert(items, { (string.match(t.name, "^([^:(]+)") or t.name):gsub("%s+$", ""), t.click, t.on() and P.accent or nil })
				end
			end
			title = "TOOLS"
		end
		if not App.viewPie(items, title) and App.openPalette then
			App.openPalette()
		end
	end
	-- (for the search menu, the suite and other tools)
	App.pickedCopy = pickedCopy
	App.pickedCopies = function()
		local t = {}
		for _, e in picks do
			local c = copyOf(e)
			if c then
				table.insert(t, c)
			end
		end
		return t
	end
	App.pickCopy = pick
	App.boxPick = boxPick
	App.copyMenu = menu
	App.copyHeader = header
	App.copyEdit = { turn = turn, size = size, model = nextModel, move = moveTo, remove = remove, back = backToRules }
	-- another thing selected: the picked copies were the last one's
	App.onSelect(function(thing)
		if #picks > 0 and not (thing and thing.folder == picks[1].folder) then
			unpick()
		end
	end)

	App.registerMode("Select", { move = App.selectMove, down = App.selectDown, up = App.selectUp, stop = unpick, header = header, noArea = true })

	App.registerTool({
		id = "select",
		group = "Select",
		icon = "cursor",
		name = "Select: click a zone, a path or a placed copy; Shift + click or drag a box for more copies",
		on = function()
			return App.mode == "Select"
		end,
		click = function()
			App.setMode(App.mode == "Select" and "Off" or "Select")
		end,
	})
end
