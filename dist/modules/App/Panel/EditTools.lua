--[[
	Smart Scatter — EditTools: helpers for the models selected in Studio (the Explorer or the viewport), whatever made
	them: drop them onto the ground, line them up, space them evenly, give them random turns and sizes, or replace
	them with another model. Each is one undo step. The Edit tab has them (it's there whatever is selected in the
	outliner), and the search menu. The maths is Engine/Edit's; Replace is the map tools' swap (Engine/Kinds), so
	Restore original on the World tab puts replaced models back too.
	Copies an area or an array placed are left alone: its next rebuild would put them back where its rules say.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local Engine, G, saveG, P, beginRec, endRec = App.Engine, App.G, App.saveG, App.P, App.beginRec, App.endRec
	local Selection = App.Selection

	--------------------------------------------------------------------------------
	-- What's selected
	--------------------------------------------------------------------------------
	-- the selected models and parts to work on: top ones only (a part inside a selected model moves with it), none
	-- an area or an array placed
	local function items()
		local sel = Selection:Get()
		local set = {}
		for _, s in sel do
			set[s] = true
		end
		local skip = { workspace:FindFirstChild(Engine.OUT), workspace:FindFirstChild(Engine.ROADS) }
		local arrays = workspace:FindFirstChild("Arrays")
		local out = {}
		for _, s in sel do
			if (s:IsA("Model") or s:IsA("BasePart")) and s:IsDescendantOf(workspace) and s ~= workspace.Terrain then
				local ok = true
				for _, f in skip do
					ok = ok and not (f and s:IsDescendantOf(f))
				end
				if arrays and s:IsDescendantOf(arrays) then -- (an array's copies, not the array itself)
					local copies = s:FindFirstAncestor("Copies")
					ok = ok and not (copies and copies:IsDescendantOf(arrays))
				end
				local up = s.Parent
				while ok and up and up ~= workspace do
					ok = not set[up]
					up = up.Parent
				end
				if ok then
					table.insert(out, s)
				end
			end
		end
		return out
	end
	App.editItems = items

	-- a thing's extent in the world: { min, max }
	local function boxOf(inst)
		local cf, size
		if inst:IsA("BasePart") then
			cf, size = inst.CFrame, inst.Size
		else
			cf, size = inst:GetBoundingBox()
		end
		local h = size / 2
		local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local p = cf:PointToWorldSpace(Vector3.new(h.X * sx, h.Y * sy, h.Z * sz))
					lo, hi = lo:Min(p), hi:Max(p)
				end
			end
		end
		return { min = lo, max = hi }
	end
	local function moveBy(inst, d)
		if d.Magnitude > 1e-6 then
			inst:PivotTo(inst:GetPivot() + d)
		end
	end
	-- turned about the vertical line through a point
	local function turnAbout(inst, at, yaw)
		local r = CFrame.new(at) * CFrame.Angles(0, yaw, 0) * CFrame.new(-at)
		inst:PivotTo(r * inst:GetPivot())
	end
	local function scaleBy(inst, f)
		if math.abs(f - 1) < 1e-4 then
			return
		end
		if inst:IsA("Model") then
			inst:ScaleTo(inst:GetScale() * f)
		else
			inst.Size *= f
		end
	end

	-- one step: `what` done to the selection, as one undo step; fn(list) does it and returns what to say
	local function step(what, fn, min)
		local list = items()
		if #list < (min or 1) then
			App.status(
				min and min > 1 and string.format("Select at least %d models (in the Explorer or the viewport) first.", min)
					or "Select the models to work on (in the Explorer or the viewport) first."
			)
			return
		end
		local rec = beginRec("Smart Scatter: " .. what)
		local ok, said = pcall(fn, list)
		endRec(rec, not ok)
		if not ok then
			warn("[Smart Scatter] " .. tostring(said))
			App.status(what .. " didn't work: " .. tostring(said), "error")
			return
		end
		App.status(said or string.format("%s: %d done. Ctrl+Z undoes it.", what, #list))
	end

	--------------------------------------------------------------------------------
	-- The helpers
	--------------------------------------------------------------------------------
	-- the ground under a thing: the lowest of a few rays over its footprint (so no side floats), never deeper than
	-- its own size below the middle one; what's selected and what areas placed are passed through
	local function groundUnder(inst, b, rp)
		local c = (b.min + b.max) / 2
		local rx, rz = (b.max.X - b.min.X) * 0.35, (b.max.Z - b.min.Z) * 0.35
		local top = b.max.Y + 4
		local best, normal
		local mid = Engine.cast(Vector3.new(c.X, top, c.Z), Vector3.new(0, -2000, 0), rp)
		if not mid then
			return nil
		end
		best, normal = mid.Position.Y, mid.Normal
		for _, o in { Vector3.new(rx, 0, 0), Vector3.new(-rx, 0, 0), Vector3.new(0, 0, rz), Vector3.new(0, 0, -rz) } do
			local h = Engine.cast(Vector3.new(c.X + o.X, top, c.Z + o.Z), Vector3.new(0, -2000, 0), rp)
			if h and h.Position.Y < best and mid.Position.Y - h.Position.Y < math.max(rx, rz) * 1.5 then
				best = h.Position.Y
			end
		end
		return best, normal, Vector3.new(c.X, best, c.Z)
	end
	App.dropToGround = function()
		step("Drop to ground", function(list)
			local skip = App.templates()
			for _, inst in list do
				table.insert(skip, inst)
			end
			local rp = Engine.rayParams(skip)
			local missed = 0
			for _, inst in list do
				local b = boxOf(inst)
				local y, normal, base = groundUnder(inst, b, rp)
				if y then
					moveBy(inst, Vector3.new(0, y - b.min.Y, 0))
					if G.editLean and normal.Y > 0.2 then -- tilted so its up is the ground's
						local r = CFrame.new(base) * Engine.rotateUp(normal) * CFrame.new(-base)
						inst:PivotTo(r * inst:GetPivot())
					end
				else
					missed += 1
				end
			end
			return string.format(
				"Dropped %d onto the ground%s.",
				#list - missed,
				missed > 0 and string.format(" (%d had no ground under them)", missed) or ""
			)
		end)
	end

	App.alignSelection = function(axis, where)
		step("Align " .. axis .. " " .. string.lower(where), function(list)
			local boxes = {}
			for i, inst in list do
				boxes[i] = boxOf(inst)
			end
			for i, d in Engine.alignMoves(boxes, axis, where) do
				moveBy(list[i], d)
			end
			return string.format("Lined up %d on %s (%s).", #list, axis, string.lower(where == "Center" and "centre" or where))
		end, 2)
	end

	App.distributeSelection = function(axis, by)
		step("Distribute " .. axis, function(list)
			local boxes = {}
			for i, inst in list do
				boxes[i] = boxOf(inst)
			end
			for i, d in Engine.distributeMoves(boxes, axis, by) do
				moveBy(list[i], d)
			end
			return string.format("Spaced %d evenly on %s, the outer two staying put.", #list, axis)
		end, 3)
	end

	local seed = 1
	App.randomizeSelection = function()
		seed += 1
		step("Randomize", function(list)
			local r = Engine.randomTurns(#list, G.editTurn, G.editSize, seed + os.clock() * 1000)
			for i, inst in list do
				local b = boxOf(inst)
				local base = Vector3.new((b.min.X + b.max.X) / 2, b.min.Y, (b.min.Z + b.max.Z) / 2)
				turnAbout(inst, base, r[i].yaw)
				scaleBy(inst, r[i].scale)
				if G.editKeep then -- its underside back where it was
					moveBy(inst, Vector3.new(0, b.min.Y - boxOf(inst).min.Y, 0))
				end
			end
			return string.format("Gave %d a random turn and size. Press again for another.", #list)
		end)
	end

	local replacement -- the model Replace puts in (picked from the selection)
	App.pickReplacement = function()
		local s = Selection:Get()[1]
		if not (s and (s:IsA("Model") or s:IsA("BasePart"))) then
			App.status("Select the model to replace with (in the Explorer), then press this.")
			return
		end
		replacement = s
		App.status(s.Name .. " is what Replace puts in. Now select the models to replace.")
		if App.refreshEditTab then
			App.refreshEditTab()
		end
	end
	App.replaceSelection = function()
		if not (replacement and replacement.Parent) then
			App.status("Pick the model to replace with first: select it and press Use the selected.")
			return
		end
		local made = {}
		step("Replace", function(list)
			for i, inst in list do
				if inst ~= replacement then
					for _, pair in
						Engine.swapCopies({ { inst = inst, scale = 1 } }, { { inst = replacement, w = 1 } }, { match = G.editMatch, seed = i })
					do
						table.insert(made, pair.new)
					end
				end
			end
			return string.format("Replaced %d with %s. Restore original (World tab) or Ctrl+Z puts them back.", #made, replacement.Name)
		end)
		if #made > 0 then
			Selection:Set(made)
		end
	end

	--------------------------------------------------------------------------------
	-- The Edit tab and the search menu
	--------------------------------------------------------------------------------
	local slider, segmented, switchRow, button, buttonRow, hintOn = App.slider, App.segmented, App.switchRow, App.button, App.buttonRow, App.hintOn
	local para = App.para
	local AXES = { "X", "Y", "Z" }

	App.registerTab({
		id = "edit",
		icon = "align",
		title = "Edit",
		order = 85,
		kinds = "all",
		build = function(page)
			local cs = App.cards(page, "edit")
			cs.add({
				id = "editsel",
				title = "The selection",
				icon = "cursor",
				sub = "What these helpers work on",
				keys = "selected models explorer viewport",
				build = function(b)
					local t = para("", { Parent = b })
					local function count()
						local n = #items()
						t.Text = n > 0 and string.format("%d selected in Studio.", n)
							or "Select models or parts in the Explorer or the viewport. (Copies an area or an array placed are left alone.)"
						t.TextColor3 = n > 0 and P.text or P.dim
					end
					count()
					local conn
					conn = Selection.SelectionChanged:Connect(function()
						if not t.Parent then
							conn:Disconnect()
							return
						end
						count()
					end)
				end,
			})
			cs.add({
				id = "editground",
				title = "Drop to the ground",
				icon = "mountain",
				sub = "Each one onto whatever is under it",
				keys = "ground drop snap floor land settle",
				build = function(b)
					switchRow("Lean with the slope", function()
						return G.editLean
					end, function(v)
						G.editLean = v
					end, saveG, "On: each one tilts to stand square on the ground under it. Off: they stay upright.").Parent =
						b
					hintOn(
						button("Drop to the ground", "accent", App.dropToGround, { Parent = buttonRow(b) }),
						"Each selected model lands on what's under it; selected models don't land on each other."
					)
				end,
			})
			cs.add({
				id = "editalign",
				title = "Align and space",
				icon = "align",
				sub = "Line them up, or space them evenly",
				keys = "align line up distribute space evenly gap center centre min max",
				build = function(b)
					segmented(AXES, function()
						return G.editAxis
					end, function(v)
						G.editAxis = v
					end, saveG).Parent = b
					App.stepLabel(b, nil, "Align to the selection's")
					local row = buttonRow(b)
					for _, w in { { "Min", "Lowest" }, { "Center", "Middle" }, { "Max", "Highest" } } do
						hintOn(
							button(w[2], nil, function()
								App.alignSelection(G.editAxis, w[1])
							end, { Parent = row }),
							"Every selected one moves on the chosen axis to the selection's " .. string.lower(w[2]) .. " edge (or middle)."
						)
					end
					App.stepLabel(b, nil, "Space evenly by")
					segmented({ "Centers", "Gaps" }, function()
						return G.editBy
					end, function(v)
						G.editBy = v
					end, saveG).Parent =
						b
					hintOn(
						button("Distribute", nil, function()
							App.distributeSelection(G.editAxis, G.editBy)
						end, { Parent = buttonRow(b) }),
						"The two outermost stay put; the rest spread evenly between them: the same distance centre to centre, or the same gap between neighbours."
					)
				end,
			})
			cs.add({
				id = "editrandom",
				title = "Randomize",
				icon = "refresh",
				sub = "A random turn and size for each",
				keys = "random turn rotate size scale vary jitter",
				build = function(b)
					slider("Turn", 0, 180, function()
						return G.editTurn
					end, function(v)
						G.editTurn = v
					end, "±%d°", 5, nil, saveG, "How far each one may turn, either way.", 180).Parent =
						b
					slider("Size", 0, 0.9, function()
						return G.editSize
					end, function(v)
						G.editSize = v
					end, "±%.0f%%", 0.05, nil, saveG, "How much bigger or smaller each one may get.", 0.15).Parent =
						b
					switchRow("Keep on the ground", function()
						return G.editKeep
					end, function(v)
						G.editKeep = v
					end, saveG, "Their undersides stay where they were as they grow or shrink.").Parent =
						b
					hintOn(button("Randomize", nil, App.randomizeSelection, { Parent = buttonRow(b) }), "Each press, another random turn and size.")
				end,
			})
			cs.add({
				id = "editreplace",
				title = "Replace",
				icon = "swap",
				sub = "Put another model in each one's place",
				keys = "replace swap exchange model",
				build = function(b)
					local t = para("", { Parent = b })
					local function show()
						local ok = replacement and replacement.Parent
						t.Text = ok and ("Replacing with " .. replacement.Name .. ".")
							or "Pick the model to put in: select it, then Use the selected."
						t.TextColor3 = ok and P.text or P.dim
					end
					show()
					App.refreshEditTab = function()
						if t.Parent then
							show()
						end
					end
					local row = buttonRow(b)
					hintOn(button("Use the selected", nil, App.pickReplacement, { Parent = row }), "The model selected now is what Replace puts in.")
					hintOn(
						button("Replace the selected", "accent", App.replaceSelection, { Parent = row }),
						"Each selected model makes way for the replacement: same spot, same turn, its base where the old one's was."
					)
					switchRow("Match each one's size", function()
						return G.editMatch
					end, function(v)
						G.editMatch = v
					end, saveG, "On: each new one is as big as the one it replaces. Off: the replacement keeps its own size.").Parent =
						b
				end,
			})
		end,
	})

	-- the search menu finds them too
	local function any()
		return #Selection:Get() > 0
	end
	App.registerAction({
		id = "edit:drop",
		name = "Drop the selection to the ground",
		group = "Edit",
		icon = "mountain",
		words = "ground snap land floor",
		when = any,
		run = App.dropToGround,
	})
	for _, axis in AXES do
		for _, w in { { "Min", "lowest" }, { "Center", "middle" }, { "Max", "highest" } } do
			App.registerAction({
				id = "edit:align" .. axis .. w[1],
				name = string.format("Align the selection on %s, to its %s", axis, w[2]),
				group = "Edit",
				icon = "align",
				words = "align line up",
				when = any,
				run = function()
					App.alignSelection(axis, w[1])
				end,
			})
		end
		App.registerAction({
			id = "edit:distribute" .. axis,
			name = "Space the selection evenly on " .. axis,
			group = "Edit",
			icon = "align",
			words = "distribute spread even",
			when = any,
			run = function()
				App.distributeSelection(axis, G.editBy)
			end,
		})
	end
	App.registerAction({
		id = "edit:random",
		name = "Randomize the selection's turn and size",
		group = "Edit",
		icon = "refresh",
		words = "random rotate scale",
		when = any,
		run = App.randomizeSelection,
	})
	App.registerAction({
		id = "edit:replace",
		name = "Replace the selection",
		group = "Edit",
		icon = "swap",
		words = "swap exchange model",
		when = any,
		run = App.replaceSelection,
	})
end
