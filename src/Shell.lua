--[[
	Smart Scatter — Shell: the Settings page, the footer, status line and the whole-panel rebuild.
	Part of Main; loaded in order by the bundle. Shared state and cross-module functions live on App.
]]

return function(App)
	local FAST, MED, tween, beginRec, endRec, Engine, track = App.FAST, App.MED, App.tween, App.beginRec, App.endRec, App.Engine, App.track
	local G, saveG, num, P, makePalette, SANS, SANS_B = App.G, App.saveG, App.num, App.P, App.makePalette, App.SANS, App.SANS_B
	local new, corner, pad, vlist, hlist, box, col, label = App.new, App.corner, App.pad, App.vlist, App.hlist, App.box, App.col, App.label
	local para, hintOn, slider, switch, switchRow = App.para, App.hintOn, App.slider, App.switch, App.switchRow
	local button, buttonRow = App.button, App.buttonRow
	local section, rebuildOverlay, saveArea, canGenerate = App.section, App.rebuildOverlay, App.saveArea, App.canGenerate
	local runGenerate, requestLive, commit, thumbCache = App.runGenerate, App.requestLive, App.commit, App.thumbCache
	local eachThumb, heading, buildHeader, buildArea = App.eachThumb, App.heading, App.buildHeader, App.buildArea

	local function buildGlobal(parent)
		App.pageHead(parent, App.area and App.area.folder.Name or "Back", "Settings", function()
			App.goPage("Main")
		end)
		heading(parent, "Scatter", 14)
		slider(
			"Overall density",
			0.1,
			3,
			function()
				return G.density
			end,
			function(v)
				G.density = v
			end,
			"%.2f×",
			0.05,
			function()
				requestLive()
			end,
			function()
				saveG()
				commit()
			end,
			"Scales every layer at once.",
			1
		).Parent =
			parent
		heading(parent, "Viewport", 12)
		switchRow("Show overlay", function()
			return G.overlay
		end, function(v)
			G.overlay = v
		end, function()
			saveG()
			rebuildOverlay()
			App.drawSpline()
		end, "Shows the painted area coloured by the surface under it, and the path.").Parent =
			parent
		box({ Size = UDim2.new(1, 0, 0, 10), Parent = parent })
		section(parent, "output", "Game-ready output", true, function(b)
			local function outSwitch(text, key, hint)
				switchRow(text, function()
					return G[key]
				end, function(v)
					G[key] = v
				end, function()
					saveG()
					commit()
				end, hint).Parent =
					b
			end
			outSwitch("Walk through plants", "walk", "Flowers and bushes get no collision, so players never snag on them.")
			outSwitch("No shadows on small stuff", "shadows", "Flowers and tiny parts skip shadows. Big win on lower-end devices.")
			outSwitch("Flowers ignore clicks", "query", "Flowers won't block raycasts, clicks, tools or weapons.")
			outSwitch(
				"Streaming chunks",
				"chunks",
				"Groups output into 128-stud models that stream in and out together, with low-detail stand-ins far away."
			)
			outSwitch(
				"Preview as boxes",
				"ghost",
				"Places a see-through box per copy instead of the model. Much faster on big areas while you tune; turn it off for the real thing."
			)
			box({ Size = UDim2.new(1, 0, 0, 4), Parent = b })
			App.ui.perf = para("", { Parent = b })
		end)
		section(parent, "shortcuts", "Shortcuts", false, function(b)
			for _, group in
				{
					{ "Painting", { { "Shift", "erase" }, { "F", "brush size" }, { "[ ]", "step size" }, { "Esc", "stop" } } },
					{ "Polygon", { { "Enter", "close" }, { "RMB", "close" }, { "Backspace", "last point" } } },
					{ "Path", { { "C", "sharp corner" }, { "Shift+drag", "height" }, { "X / RMB", "delete point" } } },
					{ "Anywhere", { { "Ctrl+Z", "undo any step" } } },
				}
			do
				label(group[1], 12, P.dim, SANS_B, { Size = UDim2.new(1, 0, 0, 18), Parent = b })
				App.keyChips(b, group[2])
			end
		end)
		box({ Size = UDim2.new(1, 0, 0, 12), Parent = parent })
		hintOn(
			button("Replay the tour", nil, function()
				App.startTour()
			end, { Parent = buttonRow(parent) }),
			"A three-minute walk through everything: what it's for, areas, paths, objects and their rules, placing and finishing."
		)
		box({ Size = UDim2.new(1, 0, 0, 8), Parent = parent })
		label("Smart Scatter  v" .. tostring(App.ctx.version or "dev") .. "  ·  made by Ghulo", 12, P.faint, SANS, { Parent = parent })
	end

	-- how heavy the area's output is for players: a note ("" when fine) and whether it's too much
	App.perfNote = function()
		if G.ghost then
			return "Boxes only: turn off Preview as boxes to place the real models.", false
		end
		local heavy = App.lastParts > 20000
		return heavy and "That's heavy. Lower the amount or use simpler models." or App.lastParts > 8000 and "Getting heavy for phones." or "", heavy
	end
	App.refreshPerf = function()
		if not App.ui.perf then
			return
		end
		local note, heavy = App.perfNote()
		App.ui.perf.Text = string.format("This area: %s objects, %s parts.  %s", num(App.lastTotal), num(App.lastParts), note)
		App.ui.perf.TextColor3 = heavy and P.danger or P.dim
	end

	-- the footer: Live update, Shuffle and Clear, and a status line. With Live update off, a Generate button on top.
	local function footHeight()
		return G.live and 84 or 134
	end
	local function buildFooter(parent)
		local h = footHeight()
		local foot = box({
			BackgroundTransparency = 0,
			BackgroundColor3 = P.header,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, h),
			Parent = parent,
		})
		App.ui.foot = foot
		App.fadeLine(foot, nil, 0.16)
		App.sheen(foot, 0.025, 40)
		local inner = box({ Position = UDim2.fromOffset(14, 13), Size = UDim2.new(1, -28, 1, -23), Parent = foot })
		local y = 0
		if not G.live then
			App.ui.genBtn = new("TextButton", {
				Text = "Generate",
				Font = SANS_B,
				TextSize = 14,
				TextColor3 = P.onAccent,
				BackgroundColor3 = P.accent,
				AutoButtonColor = false,
				Size = UDim2.new(1, 0, 0, 40),
				TextTruncate = Enum.TextTruncate.AtEnd,
				Parent = inner,
			}, { corner(10) })
			local press = new("UIScale", { Parent = App.ui.genBtn })
			-- progress while a job runs: a light sweep across the button
			App.ui.genBar = box({
				BackgroundTransparency = 0.82,
				BackgroundColor3 = Color3.new(1, 1, 1),
				Size = UDim2.fromScale(0, 1),
				Visible = false,
				Parent = App.ui.genBtn,
			}, { corner(10) })
			App.ui.genBtn.MouseEnter:Connect(function()
				if canGenerate() then
					tween(App.ui.genBtn, FAST, { BackgroundColor3 = (App.failure and P.danger or P.accent):Lerp(Color3.new(1, 1, 1), 0.1) })
				end
			end)
			App.ui.genBtn.MouseLeave:Connect(function()
				tween(press, FAST, { Scale = 1 })
				App.refreshCounts()
			end)
			App.ui.genBtn.MouseButton1Down:Connect(function()
				if canGenerate() then
					tween(press, FAST, { Scale = 0.98 })
				end
			end)
			App.ui.genBtn.MouseButton1Up:Connect(function()
				tween(press, MED, { Scale = 1 })
			end)
			App.ui.genBtn.MouseButton1Click:Connect(function()
				if App.busy() then -- while generating the button stops it
					App.cancelJob()
					App.status("Stopped. Nothing was changed.")
					return
				end
				if App.worldChanged() then -- read the ground again only if something under the area changed
					App.analysisDirty = true
				end
				runGenerate(true)
			end)
			y = 50
		end

		-- live updates on the left, shuffle and clear on the right
		local r = box({ Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, y), Parent = inner })
		local sw = switch(function()
			return G.live
		end, function(v)
			G.live = v
		end, function()
			saveG()
			if G.live then
				commit()
			end
			task.defer(App.rebuildAll) -- the Generate button comes and goes with it
		end)
		sw.Position = UDim2.fromOffset(0, 4)
		sw.Parent = r
		label("Live update", 13, P.dim, App.SANS_M, { Position = UDim2.fromOffset(46, 0), Size = UDim2.fromOffset(90, 30), Parent = r })
		hintOn(sw, "On: every change rebuilds the area as you make it. Off: changes wait for the Generate button.")
		local links = box({
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Parent = r,
		}, { hlist(8) })
		hintOn(
			button("Shuffle", nil, function()
				if not App.area then
					return
				end
				local rec = beginRec("Smart Scatter: Shuffle")
				App.area.seed = math.random(1, 999999)
				saveArea()
				endRec(rec)
				runGenerate(true)
			end, { Parent = links }),
			"A new random layout with the same settings. Ctrl+Z goes back to the last one."
		)
		hintOn(
			button("Clear", "ghost", function()
				if not App.area then
					return
				end
				local rec = beginRec("Smart Scatter: Clear")
				Engine.clearOutputs(App.area)
				endRec(rec)
				App.lastCounts, App.lastTotal = {}, 0
				App.refreshCounts()
				App.status("Cleared. The area and objects are kept.")
			end, { Parent = links }),
			"Removes everything placed in this area. The painted ground, path and objects stay; Generate brings it all back."
		)
		App.ui.status = label("", 11, P.faint, SANS, {
			Position = UDim2.fromOffset(0, y + 40),
			Size = UDim2.new(1, 0, 0, 16),
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = inner,
		})
		-- a long message is cut to one line; hovering shows all of it
		App.ui.status.MouseEnter:Connect(function()
			local full = App.ui.status:GetAttribute("full")
			if full and App.ui.status.TextFits == false and App.showTipFor then
				App.showTipFor(App.ui.status, full)
			end
		end)
		App.ui.status.MouseLeave:Connect(function()
			if App.hideTip then
				App.hideTip()
			end
		end)
	end

	-- phase = "Scanning" / "Placing" with progress 0-1, or nil when the job is over
	App.showProgress = function(phase, progress)
		local btn, bar = App.ui.genBtn, App.ui.genBar
		if not btn or not bar then
			if App.ui.status then
				App.ui.status.Text = phase and string.format("%s…  %d%%", phase, math.floor((progress or 0) * 100 + 0.5)) or ""
				App.ui.status.TextColor3 = P.dim
				if not phase then
					App.refreshCounts()
				end
			end
			return
		end
		if not phase then
			bar.Visible = false
			App.refreshCounts()
			return
		end
		bar.Visible = true
		bar.Size = UDim2.fromScale(math.clamp(progress or 0, 0.02, 1), 1)
		btn.Text = string.format("%s…  %d%%   ·   click to stop", phase, math.floor((progress or 0) * 100 + 0.5))
		btn.Font = SANS_B
		btn.BackgroundColor3 = P.accent
		btn.TextColor3 = P.onAccent
	end

	-- a short confirmation on the button after a finished run
	local flashToken = 0
	App.flashDone = function(text)
		local btn = App.ui.genBtn
		if not btn then
			return
		end
		flashToken += 1
		local my = flashToken
		btn.Text = text
		task.delay(1.5, function()
			if my == flashToken and not App.busy() then
				App.refreshCounts()
			end
		end)
	end

	local lastStatus = ""
	-- tone: nil (normal) or "error" (red, and it stays readable in full on hover)
	App.status = function(msg, tone)
		if App.ui.status and msg ~= lastStatus then
			App.ui.status.TextTransparency = 0.7
			tween(App.ui.status, MED, { TextTransparency = 0 })
		end
		lastStatus = msg
		if App.ui.status then
			App.ui.status.Text = msg ~= "" and msg or ("Smart Scatter · v" .. tostring(App.ctx.version or "dev"))
			App.ui.status.TextColor3 = tone == "error" and P.danger or msg ~= "" and P.dim or P.faint
			App.ui.status:SetAttribute("full", msg)
		end
	end

	local builtPage
	App.rebuildAll = function()
		local keepScroll = builtPage == G.page and App.scroll and App.scroll.Parent and App.scroll.CanvasPosition
		builtPage = G.page
		if App.root then
			App.root:Destroy()
		end
		eachThumb(function(vp)
			vp:Destroy()
		end)
		table.clear(thumbCache)
		App.ui = {}
		App.root = box({ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0, BackgroundColor3 = P.bg, Parent = App.widget })
		-- fixed top: title, area picker and page tabs; only the page below scrolls
		local head = col({ BackgroundTransparency = 0, BackgroundColor3 = P.bg, ZIndex = 2, Parent = App.root }, { pad(14, 14, 12, 8), vlist(0) })
		App.scroll = new("ScrollingFrame", {
			Size = UDim2.new(1, 0, 1, -footHeight()),
			CanvasSize = UDim2.new(),
			BackgroundTransparency = 1,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 4,
			ScrollBarImageColor3 = P.faint,
			ScrollBarImageTransparency = 0.5,
			VerticalScrollBarInset = Enum.ScrollBarInset.Always,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			Parent = App.root,
		}, { pad(14, 12, 8, 24), vlist(2) })
		App.scroll.MouseEnter:Connect(function()
			tween(App.scroll, FAST, { ScrollBarImageTransparency = 0.15 })
		end)
		App.scroll.MouseLeave:Connect(function()
			tween(App.scroll, FAST, { ScrollBarImageTransparency = 0.5 })
		end)
		buildHeader(head)
		box({ Size = UDim2.new(1, 0, 0, 10), Parent = head })
		App.fadeLine(head, nil, 0.16)
		App.sheen(App.root, 0.04, 140, 150)
		App.halftone(App.root, 0.07, 4, 150)
		local function fit()
			local h = head.AbsoluteSize.Y
			App.scroll.Position = UDim2.fromOffset(0, h)
			App.scroll.Size = UDim2.new(1, 0, 1, -h - footHeight())
		end
		head:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
		fit()
		if G.page == "Settings" then
			buildGlobal(App.scroll)
		elseif G.page == "Objects" and App.area then
			App.buildObjectsPage(App.scroll)
		else
			buildArea(App.scroll)
		end
		buildFooter(App.root)
		App.refreshScan()
		App.refreshObjects()
		App.status("") -- when it can't run, the Generate button already says why
		if App.tour and App.renderTour then
			App.renderTour()
		end
		if keepScroll then
			task.defer(function()
				if App.scroll then
					App.scroll.CanvasPosition = keepScroll
				end
			end)
		end
	end

	track(settings().Studio.ThemeChanged:Connect(function()
		makePalette()
		App.rebuildAll()
	end))
end
