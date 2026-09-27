--[[
	Smart Scatter — AreaTools: what an area is made of, as the controls the tabs put in their cards: the ground's
	paint tools and clean-up, its pattern, colour zones and wind, the path with its curve and road, fixing the scan,
	and the welcome shown before there are any areas. Each builder fills the body it's given.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local beginRec, endRec, Engine, G, saveG, refreshFilter = App.beginRec, App.endRec, App.Engine, App.G, App.saveG, App.refreshFilter
	local P, SANS, SANS_M, new, corner, stroke, vlist = App.P, App.SANS, App.SANS_M, App.new, App.corner, App.stroke, App.vlist
	local box, col, label, para = App.box, App.col, App.label, App.para
	local pad, SANS_B, icon = App.pad, App.SANS_B, App.icon
	local button, buttonRow = App.button, App.buttonRow
	local hintOn, slider, switchRow, segmented = App.hintOn, App.slider, App.switchRow, App.segmented
	local rebuildOverlay, saveArea, runGenerate, requestLive = App.rebuildOverlay, App.saveArea, App.runGenerate, App.requestLive
	local commit, heading, NICE, TOOLS, TOOL_HINT = App.commit, App.heading, App.NICE, App.TOOLS, App.TOOL_HINT
	local FILTER_SURFACES, maskOp, primaryButton = App.FILTER_SURFACES, App.maskOp, App.primaryButton
	local setIconColor, keyChips = App.setIconColor, App.keyChips
	local chip, chipGrid = App.chip, App.chipGrid

	local function gap(parent, h)
		box({ Size = UDim2.new(1, 0, 0, h), Parent = parent })
	end

	--------------------------------------------------------------------------------
	-- Scatter area, step 1: the tools that mark ground (inside the step card)
	--------------------------------------------------------------------------------
	local function buildPaintTools(parent)
		local grid = chipGrid(parent, 3, 36)
		local ICON = { Brush = "brush", Lasso = "lasso", Box = "box", Polygon = "polygon", Fill = "fill" }
		local cells = {}
		-- a tool; tinted: in its colour even when not picked (Erase: red, so it's never taken for another tool)
		local function cell(iconName, text, color, hint, onClick, tinted)
			local b = new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = P.raised, Parent = grid }, { corner(8) })
			local st = stroke(P.line)
			st.Parent = b
			local row = box({ Size = UDim2.fromScale(1, 1), Parent = b }, {
				new("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 6),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
			})
			local ic = icon(iconName, 14, P.dim)
			ic.Parent = row
			local t = label(text, 12, P.dim, SANS_B, { Size = UDim2.fromOffset(0, 16), AutomaticSize = Enum.AutomaticSize.X, Parent = row })
			hintOn(b, hint)
			b.MouseButton1Click:Connect(onClick)
			App.pressable(b, 0.96)
			local lit = App.glow(b, 8, 0.6, color)
			local c = { hot = false }
			c.paint = function(on)
				lit:set(on)
				local idle = tinted and color:Lerp(P.raised, c.hot and 0.8 or 0.9) or (c.hot and P.hover or P.raised)
				b.BackgroundColor3 = on and color:Lerp(P.card, 0.8) or idle
				st.Color = on and color:Lerp(P.card, 0.4) or (tinted and color:Lerp(P.card, 0.6) or P.line)
				local fg = on and color or (tinted and color:Lerp(P.dim, 0.2) or (c.hot and P.text or P.dim))
				setIconColor(ic, fg)
				t.TextColor3 = fg
			end
			b.MouseEnter:Connect(function()
				c.hot = true
				c.look()
			end)
			b.MouseLeave:Connect(function()
				c.hot = false
				c.look()
			end)
			table.insert(cells, c)
			return c
		end
		for _, t in TOOLS do
			local c = cell(ICON[t], t, P.accent, t .. ": " .. (TOOL_HINT[t] or ""), function()
				if (App.mode == "Paint" or App.mode == "Erase") and G.tool == t then
					App.setMode("Off")
				else
					App.setTool(t)
				end
			end)
			c.look = function()
				c.paint(G.tool == t and App.mode == "Paint")
			end
		end
		local er = cell("trash", "Erase", P.danger, "Erase: take ground out of the area (Shift does it while painting).", function()
			App.setMode(App.mode == "Erase" and "Paint" or "Erase")
		end, true)
		er.look = function()
			er.paint(App.mode == "Erase")
		end
		local function refresh()
			for _, c in cells do
				c.look()
			end
		end
		refresh()
		App.ui.refreshMode = refresh
		keyChips(parent, {
			{ "Shift", "erase" },
			{ App.keyText("size"), "size" },
			{ App.keyText("shrink") .. " " .. App.keyText("grow"), "step" },
			{ App.keyText("cancel"), "stop" },
		})
		hintOn(
			button("Fill selected parts", nil, function()
				App.fillSelection()
			end, { Parent = buttonRow(parent) }),
			"Select parts or models in the Explorer (an island, a roof, a platform), then click: their tops join the area and count as ground."
		)
		-- tool-specific options (shown for the tool in use)
		local brushOpts = col({ Parent = parent }, { vlist(6) })
		slider(
			"Brush size",
			4,
			200,
			function()
				return G.radius
			end,
			function(v)
				G.radius = v
			end,
			"%.0f studs",
			1,
			nil,
			saveG,
			"Radius of the brush. While painting, press "
				.. App.keyText("size")
				.. " and move the mouse to set it (click to keep), or step it with "
				.. App.keyText("shrink")
				.. " and "
				.. App.keyText("grow")
				.. ".",
			24
		).Parent =
			brushOpts
		segmented({ "Circle", "Square" }, function()
			return G.shape
		end, function(v)
			G.shape = v
		end, function()
			saveG()
		end).Parent =
			brushOpts
		local fillOpts = col({ Parent = parent }, { vlist(6) })
		slider("Reach", 16, 400, function()
			return G.fillReach
		end, function(v)
			G.fillReach = v
		end, "%.0f studs", 4, nil, saveG, "How far a fill can spread from where you click.", 120).Parent =
			fillOpts
		local function showTool()
			brushOpts.Visible = G.tool == "Brush"
			fillOpts.Visible = G.tool == "Fill"
		end
		showTool()
		App.ui.refreshTool = function()
			refresh()
			showTool()
		end

		-- erase everything painted: only once there is some, at the bottom, apart, and it asks twice
		if App.area and App.area.count > 0 then
			gap(parent, 2)
			App.fadeLine(parent, nil, 0.14)
			local clr = App.dangerButton("Erase all paint", function()
				if not App.area or App.area.count == 0 then
					return
				end
				local rec = beginRec("Smart Scatter: Erase area")
				App.area.rows, App.area.count = {}, 0
				Engine.clearOutputs(App.area)
				saveArea()
				endRec(rec)
				App.analysisDirty = true
				App.lastCounts, App.lastTotal = {}, 0
				rebuildOverlay()
				App.rebuildAll()
				App.status("Area erased. Objects and settings are kept, paint a new one.")
			end, { confirm = "Click again to erase everything", full = true })
			clr.Parent = parent
			hintOn(clr, "Removes all painted ground in this area and what was placed on it. Your objects stay. Ctrl+Z brings it back.")
		end
	end

	-- a setting of the whole area, saved with it; every change rebuilds live
	local function areaSlider(parent, key, text, min, max, fmt, step, hint, def)
		slider(
			text,
			min,
			max,
			function()
				return App.area and App.area[key] or def
			end,
			function(v)
				if App.area then
					App.area[key] = v
				end
			end,
			fmt,
			step,
			function()
				requestLive()
			end,
			function()
				commit()
			end,
			hint,
			def
		).Parent =
			parent
	end
	-- a choice of the whole area, as chips: key's value is one of options (hints: a tooltip for each)
	local function areaChoice(parent, key, title, options, hints, def, onPick)
		label(title, 13, P.text, SANS, { Parent = parent })
		local grid = chipGrid(parent, #options > 4 and 3 or 4, 30)
		for i, name in options do
			local c = chip(grid, name, function()
				return (App.area and App.area[key] or def) == name
			end, function()
				if App.area and App.area[key] ~= name then
					App.area[key] = name
					if onPick then
						onPick(App.area)
					end
					commit()
					App.rebuildAll()
				end
			end)
			c.LayoutOrder = i
			hintOn(c, hints[name])
		end
	end
	-- picking a pattern or a mood means wanting to see it: a strength left at 0 comes on
	local function showing(strengthKey, amount)
		return function(a)
			if (a[strengthKey] or 0) <= 0 then
				a[strengthKey] = amount
			end
		end
	end

	local function buildEdges(parent)
		areaSlider(
			parent,
			"edge",
			"Soft edges",
			0,
			48,
			"%.0f studs",
			1,
			"Thins things out toward the border so the area fades into its surroundings.",
			12
		)
	end

	-- patterns: the noise every object in the area thickens and thins with (Engine.PATTERNS)
	local function buildPattern(parent)
		areaChoice(parent, "pattern", "Pattern", Engine.PATTERNS, Engine.PATTERN_HINT, "Groves", showing("patches", 0.6))
		areaSlider(
			parent,
			"patches",
			"Pattern strength",
			0,
			1,
			"%.0f%%",
			0.05,
			"How much the pattern shapes the area: every object thickens and thins in the same places. 0% is off.",
			0
		)
		areaSlider(parent, "patchSize", "Pattern size", 16, 240, "%.0f studs", 4, "How big the pattern's patches, spots or rows are.", 60)
	end

	local function buildZones(parent)
		areaChoice(parent, "zoneMood", "Mood", Engine.ZONE_MOODS, Engine.ZONE_HINT, "Autumn", showing("zones", 0.5))
		areaSlider(
			parent,
			"zones",
			"Strength",
			0,
			1,
			"%.0f%%",
			0.05,
			"Tints every object by the pattern: the open, thin parts take on this mood, the thick parts keep their colours. 0% is off.",
			0
		)
	end

	local function buildWind(parent)
		areaSlider(
			parent,
			"windDir",
			"Wind direction",
			0,
			359,
			"%.0f°",
			5,
			'The way objects with "Lean with the wind" lean (0° leans toward +Z).',
			0
		)
	end

	-- which surfaces painting and erasing work on
	local function buildPaintFilter(parent)
		local fHead = box({ Size = UDim2.new(1, 0, 0, 30), Parent = parent })
		local fLabel = label("", 13, P.text, SANS, { Size = UDim2.new(1, -110, 1, 0), Parent = fHead })
		hintOn(fHead, "Only paint or erase over these surfaces, e.g. just the grass between roads. None picked means any surface.")
		local chips = chipGrid(parent, 4, 30)
		local refreshers = {}
		local function refreshHead()
			fLabel.Text = App.paintFilterOn and "Paint only on" or "Paint only on · any"
		end
		for _, cls in FILTER_SURFACES do
			local _, look = chip(chips, NICE[cls] or cls, function()
				return G.paintOn[cls] == true
			end, function()
				G.paintOn[cls] = not G.paintOn[cls] or nil
				refreshFilter()
				saveG()
				refreshHead()
			end)
			table.insert(refreshers, look)
		end
		button("Any surface", "ghost", function()
			table.clear(G.paintOn)
			refreshFilter()
			saveG()
			for _, f in refreshers do
				f()
			end
			refreshHead()
		end, { Size = UDim2.fromOffset(0, 26), Position = UDim2.new(1, 0, 0, 2), AnchorPoint = Vector2.new(1, 0), Parent = fHead })
		refreshHead()
	end

	-- clean up the painted ground: fill holes, smooth, grow, shrink, or erase it all
	local function buildTidy(parent)
		local tools = buttonRow(parent, 6)
		for _, t in
			{
				{ "Fill holes", "holes", "Fills gaps enclosed by the area." },
				{ "Smooth", "smooth", "Rounds jagged edges and removes specks." },
				{ "Grow", "grow", "Expands the area by one cell all around." },
				{ "Shrink", "shrink", "Pulls the edge in by one cell." },
			}
		do
			local b = button(t[1], nil, function()
				maskOp(t[2], t[1])
			end, { Parent = tools })
			hintOn(b, t[3])
		end
	end

	--------------------------------------------------------------------------------
	-- Path: drawing (inside the step card), then the curve and road
	--------------------------------------------------------------------------------
	local function hasPath()
		return App.area ~= nil and App.area.spline ~= nil and #App.area.spline.pts > 0
	end

	local function buildDrawTools(parent)
		local drawBtn = primaryButton("Draw path", function()
			if App.mode == "Spline" then
				App.setMode("Off")
			else
				App.ensureSplineFn()
				App.setMode("Spline")
			end
		end)
		drawBtn.Parent = parent
		hintOn(
			drawBtn,
			"Click to add points or hold and drag to draw. Drag a point to move it. Select a point and click the ground to branch off. Drop an end on a point or curve to join them; on the first point to close a loop."
		)
		App.ui.refreshSplineBtn = function()
			local editing = App.mode == "Spline"
			drawBtn.Text = editing and "Done" or (hasPath() and "+  Keep drawing" or "+  Draw path")
			drawBtn:SetAttribute("secondary", editing)
			drawBtn.BackgroundColor3 = editing and P.raised or P.accent
			drawBtn.TextColor3 = editing and P.text or P.onAccent
		end
		App.ui.refreshSplineBtn()
		keyChips(parent, { { "Shift", "height" }, { App.keyText("corner"), "corner" }, { App.keyText("delete"), "delete" } })
		App.ui.splineInfo = para("", { Parent = parent })
		App.refreshSplineInfo()
		if hasPath() then
			local clearBtn = button("Clear path", "danger", function()
				if not hasPath() then
					return
				end
				App.clearSplineFn(beginRec("Smart Scatter: Clear spline"))
				App.rebuildAll()
			end, { Parent = buttonRow(parent) })
			hintOn(clearBtn, "Removes every point and branch. Ctrl+Z brings them back.")
		end

		-- the selected point while drawing: its width, scale, corner and handles
		local pointBox = col({ Parent = parent }, { vlist(4) })
		App.ui.refreshPoint = function()
			for _, c in pointBox:GetChildren() do
				if c:IsA("GuiObject") then
					c:Destroy()
				end
			end
			local q = App.selectedPoint and App.selectedPoint()
			if not q then
				return
			end
			local card = col(
				{ BackgroundTransparency = 0, BackgroundColor3 = P.raised, Parent = pointBox },
				{ corner(10), stroke(P.line), pad(12, 12, 10, 10), vlist(2) }
			)
			label("SELECTED POINT", 11, P.faint, SANS_B, { Parent = card })
			local function pointSlider(key, text, hint)
				return slider(
					text,
					0.2,
					3,
					function()
						return q[key] or 1
					end,
					function(v)
						q[key] = math.abs(v - 1) > 1e-3 and v or nil
					end,
					"%.2f×",
					0.05,
					function()
						App.drawSpline()
					end,
					function()
						App.commitSplineFn(beginRec("Smart Scatter: Spline point"))
					end,
					hint,
					1
				)
			end
			local sp = App.area and App.area.spline
			if sp and (sp.width or 0) > 0 then
				pointSlider("w", "Width here", "Widens or narrows the strip at this point; it eases into the next point.").Parent = card
			end
			pointSlider(
				"s",
				"Scale here",
				"Makes things near this point bigger or smaller (spaced copies and posts; end-to-end pieces keep their length)."
			).Parent =
				card
			switchRow("Sharp corner  (C)", function()
				return q.sharp == true
			end, function() end, function()
				App.pointAction("sharp")
			end, "Straight lines into and out of this point, like a fence corner. Smooth points get handles to bend the curve.").Parent =
				card
			local acts = buttonRow(card)
			if q.h then
				hintOn(
					button("Reset handles", nil, function()
						App.pointAction("resetHandle")
					end, { Parent = acts }),
					"Forgets how you bent the curve here; it goes back to the automatic smooth shape."
				)
			end
			button("Delete point", "danger", function()
				App.pointAction("delete")
			end, { Parent = acts })
		end
		App.ui.refreshPoint()
	end

	local function spGet(k, d)
		return function()
			local sp = App.area and App.area.spline
			if sp then
				return sp[k]
			end
			return d
		end
	end
	local function spSet(k)
		return function(v)
			App.ensureSplineFn()[k] = v
		end
	end

	local function buildCurve(parent)
		slider(
			"Strip width",
			0,
			200,
			spGet("width", 0),
			spSet("width"),
			"%.0f studs",
			2,
			function()
				App.drawSpline()
			end,
			function()
				if App.area and App.area.spline then
					App.commitSplineFn(beginRec("Smart Scatter: Spline width"))
				end
			end,
			"0 keeps it a line for fences and rows. Wider makes a strip: your scatter objects fill it, or it becomes the road when Build a road is on.",
			0
		).Parent =
			parent
		gap(parent, 4)
		local function toggle(text, key, def, rec, hint)
			switchRow(text, spGet(key, def), spSet(key), function()
				if App.area and App.area.spline then
					App.commitSplineFn(beginRec("Smart Scatter: " .. rec))
				end
			end, hint).Parent =
				parent
		end
		toggle(
			"Snap to surfaces",
			"snap",
			true,
			"Spline snap",
			"On: things hug the ground, walls or ceilings under the curve. Off: they sit exactly on the curve, e.g. lanterns on a cable in the air."
		)
		toggle(
			"Points on walls",
			"walls",
			false,
			"Spline walls",
			"Off: a click on a wall drops the point onto the ground below. On: points can sit on walls and ceilings (vines, cables)."
		)
		toggle("Closed loop", "closed", false, "Spline loop", "Joins the last point back to the first, e.g. a fence around a field.")
	end

	-- when the scan misreads a part (a road it thinks is grass): mark it by hand
	local function buildScanFix(parent)
		local markHead = box({ Size = UDim2.new(1, 0, 0, 30), Parent = parent })
		hintOn(
			markHead,
			"The scan guesses what each part is from its material and name, to keep things off roads, out of water and off roofs. If it guesses wrong, select the part and mark it."
		)
		label("MARK SELECTED AS", 11, P.faint, SANS_B, { Size = UDim2.new(1, -120, 1, 0), Parent = markHead })
		hintOn(
			button("Remove mark", "ghost", function()
				App.markSelected(nil)
			end, { Size = UDim2.fromOffset(0, 26), Position = UDim2.new(1, 0, 0, 2), AnchorPoint = Vector2.new(1, 0), Parent = markHead }),
			"Lets the scan guess again for the selected parts."
		)
		local marks = chipGrid(parent, 4, 30)
		for _, cls in { "Road", "Path", "Building", "Water" } do
			local c = chip(marks, cls, nil, function()
				App.markSelected(cls)
			end)
			hintOn(c, "Select parts, models or meshes in the Explorer or viewport, then click to mark them as " .. string.lower(cls) .. ".")
		end
		gap(parent, 4)
		App.ui.scanText = para("", { Parent = parent })
		hintOn(
			button("Rescan", nil, function()
				App.analysisDirty = true
				rebuildOverlay(true)
				runGenerate(true)
			end, { Parent = buttonRow(parent) }),
			"Reads the ground again, e.g. after you moved a house or added a road, then regenerates."
		)
	end

	local function buildRoad(parent)
		local function surf()
			local sp = App.ensureSplineFn()
			sp.surface = sp.surface or { on = false, style = "Asphalt", thick = 1 }
			return sp.surface
		end
		local function roadOn()
			local sp = App.area and App.area.spline
			return sp ~= nil and sp.surface ~= nil and sp.surface.on == true
		end
		local function roadCommit(name)
			if App.area and App.area.spline then
				App.commitSplineFn(beginRec("Smart Scatter: " .. name))
			end
		end
		switchRow(
			"Build a road",
			roadOn,
			function(v)
				local sf = surf()
				sf.on = v
				sf.width = sf.width or 12 -- its own width: the strip around it stays as it is
				if not v then -- the road goes now, even when nothing else is left to generate
					local road = Engine.roadOf(App.area)
					if road then
						Engine.dropOutput(road)
					end
				end
			end,
			function()
				roadCommit("Road")
				App.rebuildAll()
			end,
			"Lays a solid road or path down the middle of the curve; the strip beside it still gets filled. Bends, slopes, junctions and per-point widths stay seamless, and scattered objects keep off it."
		).Parent =
			parent
		if roadOn() then
			local grid = chipGrid(parent, 4, 32)
			for i, st in Engine.ROAD_STYLES do
				chip(grid, st.name, function()
					return (App.area.spline.surface.style or "Asphalt") == st.name
				end, function()
					surf().style = st.name
					roadCommit("Road style")
					App.rebuildAll()
				end, st.color).LayoutOrder =
					i
			end
			slider(
				"Road width",
				2,
				80,
				function()
					return Engine.roadWidth(App.area.spline)
				end,
				function(v)
					surf().width = v
				end,
				"%d studs",
				1,
				function() end,
				function()
					roadCommit("Road width")
				end,
				"How wide the road is. Widen the strip past it to fill the ground on either side.",
				12
			).Parent =
				parent
			slider(
				"Thickness",
				0.2,
				4,
				function()
					return surf().thick or 1
				end,
				function(v)
					surf().thick = v
				end,
				"%.1f studs",
				0.1,
				function() end,
				function()
					roadCommit("Road thickness")
				end,
				"How deep the road is. Thicker hides uneven ground at the edges.",
				1
			).Parent =
				parent
		end
	end

	--------------------------------------------------------------------------------
	-- First run (no areas yet): what the plugin does, and the two ways to start
	--------------------------------------------------------------------------------
	local function buildWelcome(parent)
		new("ImageLabel", { Image = App.LOGO.mark, BackgroundTransparency = 1, Size = UDim2.fromOffset(48, 48), Parent = parent })
		gap(parent, 6)
		local title = label("Fill your map by rules, not by hand.", 18, P.text, SANS_B, { Parent = parent })
		title.TextWrapped = true
		title.TextTruncate = Enum.TextTruncate.None
		title.AutomaticSize = Enum.AutomaticSize.Y
		title.Size = UDim2.new(1, 0, 0, 0)
		gap(parent, 2)
		para("Pick what you want to make. You can have as many of each as you like.", { Parent = parent }).TextColor3 = P.dim
		gap(parent, 12)
		local function choice(iconName, title, text, examples, onClick)
			local b = new("TextButton", {
				Text = "",
				AutoButtonColor = false,
				BackgroundColor3 = P.card,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Parent = parent,
			}, { corner(14), pad(14, 14, 14, 14) })
			local st = stroke(P.line)
			st.Parent = b
			local badge = box({
				BackgroundTransparency = 0,
				BackgroundColor3 = P.accent:Lerp(P.card, 0.86),
				Size = UDim2.fromOffset(36, 36),
				Parent = b,
			}, { corner(9), stroke(P.accent:Lerp(P.card, 0.8)) })
			local ic = icon(iconName, 18, P.accent)
			ic.AnchorPoint = Vector2.new(0.5, 0.5)
			ic.Position = UDim2.fromScale(0.5, 0.5)
			ic.Parent = badge
			local txt = col({ Position = UDim2.fromOffset(48, 0), Size = UDim2.new(1, -48, 0, 0), Parent = b }, { vlist(4) })
			label(title, 14, P.text, SANS_B, { Size = UDim2.new(1, 0, 0, 18), Parent = txt })
			para(text, { Parent = txt }).TextColor3 = P.dim
			local tags = buttonRow(txt, 5)
			for _, e in examples do
				local tag = label(e, 11, P.dim, SANS_M, {
					Size = UDim2.fromOffset(0, 22),
					AutomaticSize = Enum.AutomaticSize.X,
					BackgroundTransparency = 0,
					BackgroundColor3 = P.raised,
					Parent = tags,
				})
				corner(6).Parent = tag
				pad(8, 8, 0, 0).Parent = tag
			end
			App.shadow(b, 14)
			App.pressable(b, 0.985)
			local lit = App.glow(b, 14, 0.5) -- lights up under the mouse
			b.MouseEnter:Connect(function()
				st.Color = P.accentLine
				b.BackgroundColor3 = P.card:Lerp(P.hover, 0.4)
				lit:set(true)
			end)
			b.MouseLeave:Connect(function()
				st.Color = P.line
				b.BackgroundColor3 = P.card
				lit:set(false)
			end)
			b.MouseButton1Click:Connect(onClick)
			return b
		end
		App.ui.welcomeChoice = choice(
			"area",
			"Scatter area",
			"Paint a patch of ground and fill it. Things keep off roads, water and roofs by themselves.",
			{ "Forests", "Flower fields", "Rocks", "Rubble" },
			App.newArea
		)
		gap(parent, 10)
		choice("spline", "Path", "Draw a curve and line it. It follows hills and bends round corners without gaps.", {
			"Fences",
			"Street lamps",
			"Tiled paths",
			"Roads",
		}, function()
			App.newSplineFn()
		end)
		gap(parent, 20)
		heading(parent, "How it works", 0)
		for i, s in
			{
				{ "Shape", "Paint the ground, or draw a path." },
				{ "Objects", "Pick models from the Explorer." },
				{ "Generate", "Everything is placed, and updates as you tweak." },
			}
		do
			local row = box({ Size = UDim2.new(1, 0, 0, 30), Parent = parent })
			local n = label(tostring(i), 10, P.faint, SANS_B, {
				Size = UDim2.fromOffset(16, 16),
				Position = UDim2.fromOffset(0, 7),
				TextXAlignment = Enum.TextXAlignment.Center,
				Parent = row,
			})
			corner(8).Parent = n
			local st = stroke(P.faint)
			st.Thickness = 1.5
			st.Parent = n
			label(s[1], 13, P.text, SANS_B, { Position = UDim2.fromOffset(26, 0), Size = UDim2.new(0, 70, 1, 0), Parent = row })
			label(s[2], 12, P.dim, SANS, { Position = UDim2.fromOffset(96, 0), Size = UDim2.new(1, -96, 1, 0), Parent = row })
		end
	end

	-- what the panel was built for: whether the ground is marked / the path drawn, and whether there are objects
	local function shapeKey()
		local a = App.area
		if not a then
			return "none"
		end
		return tostring((a.count or 0) > 0) .. tostring(a.spline ~= nil and #a.spline.pts >= 2) .. tostring(#a.layers > 0)
	end
	-- the tabs show what comes next once a step gets done (the path's road once it's drawn, objects once there's
	-- ground): rebuild when that changes
	local pending = false
	local function stale()
		return G.page ~= "Settings" and App.ui.builtShape ~= nil and App.ui.builtShape ~= shapeKey()
	end
	App.checkShape = function()
		if pending or not stale() then
			return
		end
		pending = true
		task.defer(function()
			pending = false
			if stale() then
				App.rebuildAll()
			end
		end)
	end
	App.shapeKey = shapeKey

	App.refreshScan = function()
		if not App.ui.scanText then
			return
		end
		local an = App.lastAnalysis
		if not an or App.analysisDirty or an.maskCells == 0 then
			App.ui.scanText.Text = (App.area and App.area.count > 0) and "Not scanned yet." or "Paint over the ground to mark an area."
			return
		end
		local list = {}
		for cls, n in an.stats do
			if cls ~= "None" then
				table.insert(list, { cls, n / an.maskCells })
			end
		end
		table.sort(list, function(a, b)
			return a[2] > b[2]
		end)
		local parts = {}
		for i = 1, math.min(4, #list) do
			if list[i][2] >= 0.01 then
				table.insert(parts, string.format("%s %d%%", NICE[list[i][1]] or list[i][1], math.floor(list[i][2] * 100 + 0.5)))
			end
		end
		App.ui.scanText.Text = table.concat(parts, "  ·  ")
	end

	-- used by later modules
	App.hasPath = hasPath
	App.buildPaintTools = buildPaintTools
	App.buildTidy = buildTidy
	App.buildPaintFilter = buildPaintFilter
	App.buildEdges = buildEdges
	App.buildPattern = buildPattern
	App.buildZones = buildZones
	App.buildWind = buildWind
	App.buildDrawTools = buildDrawTools
	App.buildCurve = buildCurve
	App.buildRoad = buildRoad
	App.buildScanFix = buildScanFix
	App.buildWelcome = buildWelcome
end
