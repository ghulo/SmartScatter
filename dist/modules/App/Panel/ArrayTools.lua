--[[
	Smart Scatter — ArrayTools: arrays, one model repeated in a pattern (Engine/Arrays does the maths). An array is a
	Model in Workspace › Arrays: its settings in an attribute (SS_Array), its source model and the path it may follow
	as ObjectValues (Source, Path), its origin as its pivot (so moving it with Studio's Move tool moves the array),
	and its copies in a folder (Copies) rebuilt from the settings whenever they change.
	The copies stay out of the undo history, as an area's objects do: a setting changed is one undo step, and undo
	brings the setting back and the copies are rebuilt from it. Bake turns an array into a plain model.
	Here: making one, reading and saving its settings, building its copies, the outliner's Array kind and its tab.
	The strip's Array tool (click and drag to make one) is Viewport/ArrayTool.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local Engine, P, beginRec, endRec = App.Engine, App.P, App.beginRec, App.endRec
	local HttpService = game:GetService("HttpService")
	local FOLDER, ATTR = "Arrays", "SS_Array"
	local BARE = { s = {} } -- (placing asks the layer only whether it's a line: an array's copy never is)
	local LIVE_MAX = 250 -- a slider rebuilds as it moves up to this many copies; more wait for its release

	--------------------------------------------------------------------------------
	-- Arrays in the place
	--------------------------------------------------------------------------------
	local function folder(make)
		local f = workspace:FindFirstChild(FOLDER)
		if not f and make then
			f = Instance.new("Folder")
			f.Name = FOLDER
			f.Parent = workspace
		end
		return f
	end
	local function isArray(m)
		return m ~= nil and m:IsA("Model") and m:GetAttribute(ATTR) ~= nil
	end
	App.isArrayModel = isArray
	App.arrays = function()
		local out = {}
		for _, m in (folder() and folder():GetChildren() or {}) do
			if isArray(m) then
				table.insert(out, m)
			end
		end
		return out
	end
	App.arrayThing = function(m)
		return { kind = "Array", folder = m }
	end

	-- its settings, as saved (with what's missing filled in)
	local function read(m)
		local ok, t = pcall(HttpService.JSONDecode, HttpService, m:GetAttribute(ATTR) or "{}")
		return Engine.arrayDefaults(ok and type(t) == "table" and t or {})
	end
	App.readArray = read
	local function linked(m, name)
		local v = m:FindFirstChild(name)
		return v and v:IsA("ObjectValue") and v.Value or nil
	end

	-- each model measured once
	local measured = setmetatable({}, { __mode = "k" })
	local function variantOf(inst)
		local v = measured[inst]
		if v == nil then
			v = Engine.makeVariant(inst, 1, 1) or false
			measured[inst] = v
		end
		return v or nil
	end

	-- ground under a point: what copies stand on (not arrays, areas' copies or the camera's gizmos)
	local function groundParams()
		local skip = App.templates()
		local f = folder()
		if f then
			table.insert(skip, f)
		end
		return (Engine.rayParams(skip))
	end

	--------------------------------------------------------------------------------
	-- Building the copies
	--------------------------------------------------------------------------------
	local built = setmetatable({}, { __mode = "k" }) -- [array] = the settings text its copies were built from

	-- the path an array follows: its main curve, sampled, and whether it's a loop (nil when it has none)
	local function pathOf(m)
		local f = linked(m, "Path")
		if not (f and f:IsDescendantOf(workspace)) then
			return nil
		end
		local a = Engine.loadArea(f)
		local sp = a.spline
		if not (sp and #sp.pts >= 2) then
			return nil
		end
		local pts = Engine.splineCurve(sp, 1)
		return pts, sp.closed == true and #sp.pts >= 3
	end

	-- rebuild m's copies from settings s (default: its saved ones). Built out of sight and swapped in whole, so they
	-- stay out of the undo history.
	local function build(m, s)
		s = s or read(m)
		local src = linked(m, "Source")
		local v = src and src.Parent and variantOf(src)
		local holder = Instance.new("Folder")
		holder.Name = "Copies"
		holder.Archivable = false
		local placed = 0
		if v then
			local P, closed
			if s.shape == "Path" then
				P, closed = pathOf(m)
			end
			local pivot = m:GetPivot()
			local look = Vector3.new(pivot.LookVector.X, 0, pivot.LookVector.Z)
			local origin = CFrame.lookAt(pivot.Position, pivot.Position + (look.Magnitude > 1e-3 and look.Unit or Vector3.new(0, 0, -1)))
			local rp = s.ground and groundParams()
			for _, c in Engine.arrayCopies(s, P, closed) do
				local at = s.shape == "Path" and CFrame.new(c.pos) * CFrame.Angles(0, c.yaw, 0)
					or origin * CFrame.new(c.pos) * CFrame.Angles(0, c.yaw, 0)
				local pos = at.Position
				if rp then -- (settled on the ground under it; a spot with no ground keeps its height)
					local hit = Engine.cast(pos + Vector3.new(0, 60, 0), Vector3.new(0, -400, 0), rp)
					if hit then
						pos = Vector3.new(pos.X, hit.Position.Y, pos.Z)
					end
				end
				at = at.Rotation + pos + Vector3.new(0, s.lift, 0)
				local copy = (v.src or src):Clone()
				Engine.poseCopy(copy, BARE, v, c.scale, at, 0)
				for _, d in copy:GetDescendants() do
					if d:IsA("BasePart") then
						d.Anchored = true
					end
				end
				if copy:IsA("BasePart") then
					copy.Anchored = true
				end
				copy.Parent = holder
				placed += 1
			end
		end
		local old = m:FindFirstChild("Copies")
		if old then
			Engine.dropOutput(old) -- (hidden first: the undo history never holds them)
		end
		holder.Parent = m
		holder.Archivable = true
		built[m] = m:GetAttribute(ATTR)
		if App.reapplyHidden then -- (a hidden array's new copies are hidden too)
			App.reapplyHidden(m)
		end
		return placed, v ~= nil
	end
	App.buildArray = build

	-- after an undo or a redo: an array whose settings came back rebuilds its copies from them
	local function follow()
		for _, m in App.arrays() do
			if built[m] ~= m:GetAttribute(ATTR) or not m:FindFirstChild("Copies") then
				build(m)
			end
		end
	end
	App.track(App.ChangeHistoryService.OnUndo:Connect(function()
		task.defer(follow)
	end))
	App.track(App.ChangeHistoryService.OnRedo:Connect(function()
		task.defer(follow)
	end))

	--------------------------------------------------------------------------------
	-- Changing one
	--------------------------------------------------------------------------------
	-- save m's settings as one undo step (named `what`), then rebuild
	App.saveArray = function(m, s, what)
		local rec = beginRec("Smart Scatter: " .. (what or "Array"))
		m:SetAttribute(ATTR, HttpService:JSONEncode(s))
		endRec(rec)
		build(m, s)
		if App.refreshCounts then
			App.refreshCounts()
		end
	end
	-- a setting on the move (a slider dragged): the copies follow it, if that's quick enough; nothing is saved yet
	App.previewArray = function(m, s)
		local n = s.shape == "Grid" and s.rows * s.cols or s.count
		if n <= LIVE_MAX then
			build(m, s)
		end
	end
	-- a linked instance changed (its source model, the path it follows), as one undo step
	App.linkArray = function(m, name, value, what)
		local rec = beginRec("Smart Scatter: " .. what)
		local v = m:FindFirstChild(name)
		if value and not v then
			v = Instance.new("ObjectValue")
			v.Name = name
			v.Parent = m
		end
		if v then
			if value then
				v.Value = value
			else
				v.Parent = nil
			end
		end
		endRec(rec)
		build(m)
	end

	-- a model of the Explorer's selection that can be arrayed (not a copy Smart Scatter made)
	App.arraySource = function()
		local ours = { workspace:FindFirstChild(Engine.OUT), workspace:FindFirstChild(Engine.ROADS), folder() }
		for _, s in App.Selection:Get() do
			if (s:IsA("Model") or s:IsA("BasePart")) and s:GetAttribute("SS_Type") == nil and variantOf(s) then
				local mine = false
				for _, f in ours do
					mine = mine or (f ~= nil and s:IsDescendantOf(f))
				end
				if not mine then
					return s
				end
			end
		end
		return nil
	end

	-- a new array of `src`, its origin at `origin` (a CFrame: where the first copy stands, facing where the line runs),
	-- with settings s; one undo step. Selected, so its tab shows.
	App.newArray = function(src, origin, s)
		local v = variantOf(src)
		if not v then
			App.status("That model has no parts to repeat.")
			return nil
		end
		s = Engine.arrayDefaults(s or {})
		local n = 1
		local f = folder()
		while f and f:FindFirstChild("Array " .. n) do
			n += 1
		end
		local rec = beginRec("Smart Scatter: New array")
		f = folder(true)
		local m = Instance.new("Model")
		m.Name = "Array " .. n
		m:SetAttribute(ATTR, HttpService:JSONEncode(s))
		local link = Instance.new("ObjectValue")
		link.Name = "Source"
		link.Value = src
		link.Parent = m
		m.WorldPivot = origin
		m.Parent = f
		endRec(rec)
		build(m, s)
		App.select(App.arrayThing(m))
		return m
	end

	-- the spacing that puts copies of a model side by side (a little apart), along its length
	App.arraySpacing = function(src)
		local v = variantOf(src)
		if not v then
			return 8
		end
		return math.max(math.floor(math.max(v.m.size.X, v.m.size.Z) * 1.1 * 10 + 0.5) / 10, 0.5)
	end

	-- + New › Array from selected model: a line of copies on the ground in front of the camera
	App.newArrayFromSelection = function()
		local src = App.arraySource()
		if not src then
			App.status("Select a model in the Explorer first, then make an array of it.")
			return
		end
		local cam = workspace.CurrentCamera.CFrame
		local hit = Engine.cast(cam.Position, cam.LookVector * 1000, groundParams())
		local at = hit and hit.Position or (cam.Position + cam.LookVector * 40)
		local flat = Vector3.new(cam.LookVector.X, 0, cam.LookVector.Z)
		flat = flat.Magnitude > 1e-3 and flat.Unit or Vector3.new(0, 0, -1)
		App.newArray(src, CFrame.lookAt(at, at + flat), { spacing = App.arraySpacing(src) })
		App.status("Array made: tune it on its Array tab.")
	end

	-- bake: the copies stay as plain models in its Model; the array lets go of them (one undo step)
	local function bake(m)
		local rec = beginRec("Smart Scatter: Bake array")
		m:SetAttribute(ATTR, nil)
		for _, name in { "Source", "Path" } do
			local v = m:FindFirstChild(name)
			if v then
				v.Parent = nil
			end
		end
		endRec(rec)
		App.select(nil)
		App.status(m.Name .. " is plain models now.")
	end
	local function delete(m)
		local rec = beginRec("Smart Scatter: Delete array")
		m.Parent = nil
		endRec(rec)
		App.select(nil)
		App.status("Array deleted. Ctrl+Z brings it back.")
	end

	--------------------------------------------------------------------------------
	-- In the outliner and the properties
	--------------------------------------------------------------------------------
	App.registerKind({
		kind = "Array",
		icon = "grid",
		title = "Array",
		order = 35,
		list = function()
			local out = {}
			for _, m in App.arrays() do
				table.insert(out, App.arrayThing(m))
			end
			return out
		end,
		count = function(thing)
			local c = thing.folder:FindFirstChild("Copies")
			return c and #c:GetChildren() or 0
		end,
		thumb = function(thing) -- (the model it repeats)
			local src = thing.folder:FindFirstChild("Source")
			return src and src:IsA("ObjectValue") and src.Value or nil
		end,
		reorder = true,
		hide = true,
		menu = function(thing)
			return {
				{
					"Rename",
					function()
						App.startRename(thing)
					end,
				},
				{
					"Bake to plain models",
					function()
						bake(thing.folder)
					end,
					P.dim,
				},
				"-",
				{
					"Delete",
					function()
						delete(thing.folder)
					end,
					P.danger,
				},
			}
		end,
	})

	-- the Array tab: its model, its shape, how the copies vary, how they stand
	local slider, segmented, switchRow, button, buttonRow, hintOn = App.slider, App.segmented, App.switchRow, App.button, App.buttonRow, App.hintOn
	local label, box, para = App.label, App.box, App.para

	local function buildTab(page)
		local m = App.selected and App.selected.folder
		if not (m and isArray(m)) then
			return
		end
		local s = read(m)
		local cs = App.cards(page, "array")
		local function S(parent, key, text, min, max, fmt, step, hint, def)
			slider(
				text,
				min,
				max,
				function()
					return s[key]
				end,
				function(v)
					s[key] = v
				end,
				fmt,
				step,
				function()
					App.previewArray(m, s)
				end,
				function()
					App.saveArray(m, s, "Array " .. string.lower(text))
				end,
				hint,
				def
			).Parent =
				parent
		end
		local function pick(parent, key, options, rebuild)
			segmented(options, function()
				return s[key]
			end, function(v)
				s[key] = v
			end, function()
				App.saveArray(m, s, "Array " .. key)
				if rebuild then
					App.rebuildAll()
				end
			end).Parent =
				parent
		end

		cs.add({
			id = "arraymodel",
			title = "Model",
			icon = "cube",
			sub = "What's repeated",
			keys = "model source swap select",
			build = function(b)
				local src = linked(m, "Source")
				local row = box({ Size = UDim2.new(1, 0, 0, 36), Parent = b })
				if src then
					local th = App.thumbnail(src, 32)
					th.Position = UDim2.fromOffset(0, 2)
					th.Parent = row
				end
				label(src and src.Name or "Its model is gone: select another and press Swap.", 13, src and P.text or P.danger, App.SANS_M, {
					Position = UDim2.fromOffset(40, 0),
					Size = UDim2.new(1, -40, 1, 0),
					Parent = row,
				})
				local acts = buttonRow(b)
				hintOn(
					button("Swap for selected", nil, function()
						local pick2 = App.arraySource()
						if not pick2 then
							App.status("Select the model to use in the Explorer first.")
							return
						end
						App.linkArray(m, "Source", pick2, "Array model")
						App.rebuildAll()
					end, { Parent = acts }),
					"Repeats the model selected in the Explorer instead, in the same pattern."
				)
				if src then
					button("Select model", nil, function()
						App.Selection:Set({ src })
					end, { Parent = acts })
				end
			end,
		})

		cs.add({
			id = "arrayshape",
			title = "Shape",
			icon = "grid",
			sub = "Line, grid, circle, or along a path",
			keys = "line grid circle path count spacing rows columns radius face",
			build = function(b)
				pick(b, "shape", Engine.ARRAY_SHAPES, true)
				if s.shape == "Line" then
					S(b, "count", "Count", 1, 200, "%d", 1, "How many copies.", 6)
					S(b, "spacing", "Spacing", 0.5, 100, "%.1f studs", 0.5, "From one copy to the next.")
				elseif s.shape == "Grid" then
					S(b, "rows", "Rows", 1, 40, "%d", 1, "Rows, down the array's front.", 3)
					S(b, "cols", "Columns", 1, 40, "%d", 1, "Columns, to its right.", 3)
					S(b, "spacingZ", "Row spacing", 0.5, 100, "%.1f studs", 0.5, "From one row to the next.")
					S(b, "spacingX", "Column spacing", 0.5, 100, "%.1f studs", 0.5, "From one column to the next.")
				elseif s.shape == "Circle" then
					S(b, "count", "Count", 1, 200, "%d", 1, "How many copies round the circle.", 6)
					S(b, "radius", "Radius", 1, 300, "%.1f studs", 0.5, "How far from the centre.", 20)
					App.stepLabel(b, nil, "Facing")
					pick(b, "face", Engine.ARRAY_FACES)
				else -- Path
					local paths = {}
					for _, f in Engine.listAreas() do
						if f:GetAttribute("SS_Spline") then
							table.insert(paths, f)
						end
					end
					local on = linked(m, "Path")
					if #paths == 0 then
						local t = para("No paths yet. Draw one (the strip's Path tool), then pick it here.", { Parent = b })
						t.TextColor3 = P.dim
					else
						App.stepLabel(b, nil, "Along")
						local grid = App.chipGrid(b, 3, 28, 96)
						for _, f in paths do
							App.chip(grid, f.Name, function()
								return on == f
							end, function()
								App.linkArray(m, "Path", f, "Array path")
								App.rebuildAll()
							end)
						end
					end
					App.stepLabel(b, nil, "Copies")
					pick(b, "pathMode", { "Count", "Spacing" }, true)
					if s.pathMode == "Spacing" then
						S(b, "spacing", "Spacing", 0.5, 100, "%.1f studs", 0.5, "From one copy to the next along the path; as many as fit.")
					else
						S(b, "count", "Count", 1, 500, "%d", 1, "How many, spread evenly from one end to the other (round a loop).", 6)
					end
				end
			end,
		})

		cs.add({
			id = "arrayvary",
			title = "Variation",
			icon = "blend",
			sub = "Turn, size and spot, copy by copy",
			keys = "rotate turn spiral random jitter size scale seed",
			build = function(b)
				S(b, "scale", "Size", 0.1, 5, "%.2f×", 0.05, "1× is the model's own size.", 1)
				S(b, "yawStep", "Turn each copy by", -180, 180, "%d°", 1, "Each copy turns this much more than the one before: spirals, fans.", 0)
				S(b, "yawJitter", "Random turn", 0, 180, "±%d°", 1, "Each copy turns a random amount, up to this.", 0)
				S(b, "scaleJitter", "Random size", 0, 0.9, "±%.0f%%", 0.05, "Each copy a little bigger or smaller.", 0)
				S(b, "posJitter", "Random nudge", 0, 20, "±%.1f studs", 0.1, "Each copy nudged off its spot.", 0)
				hintOn(
					button("New random", nil, function()
						s.seed += 1
						App.saveArray(m, s, "Array new random")
					end, { Parent = buttonRow(b) }),
					"The same settings, other random turns, sizes and nudges."
				)
			end,
		})

		cs.add({
			id = "arraystand",
			title = "Standing",
			icon = "mountain",
			sub = "On the ground, or level",
			keys = "ground drop snap level lift height",
			build = function(b)
				switchRow("Drop onto the ground", function()
					return s.ground
				end, function(v)
					s.ground = v
				end, function()
					App.saveArray(m, s, "Array ground")
				end, "On: each copy stands on the ground under it. Off: they all stay at the array's height, level.").Parent =
					b
				S(b, "lift", "Lift", -20, 50, "%.1f studs", 0.1, "Raises every copy (or sinks it, below 0).", 0)
			end,
		})

		cs.add({
			id = "arrayfinish",
			title = "Finish",
			icon = "wand",
			sub = "Keep it as plain models, or remove it",
			keys = "bake delete remove plain",
			more = true,
			build = function(b)
				local acts = buttonRow(b)
				hintOn(
					button("Bake to plain models", nil, function()
						bake(m)
					end, { Parent = acts }),
					"The copies stay where they are as plain models; the array's settings go."
				)
				local del = App.dangerButton("Delete array", function()
					delete(m)
				end, { confirm = "Click again to delete" })
				del.Parent = acts
			end,
		})
	end

	App.registerTab({ id = "array", icon = "grid", title = "Array", order = 10, kinds = { Array = true }, build = buildTab })
end
