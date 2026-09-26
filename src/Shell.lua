--[[
	Smart Scatter — Shell: the Settings page, the footer, toasts and the whole-panel rebuild.
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

	local applyTheme -- (below)
	local function buildGlobal(parent)
		App.pageHead(parent, App.area and App.area.folder.Name or "Back", "Settings", function()
			App.goPage("Main")
		end)
		heading(parent, "Look", 14)
		local swatches = App.chipGrid(parent, 5, 32)
		for _, a in App.ACCENTS do
			App.chip(swatches, a.name, function()
				return G.accent == a.name
			end, function()
				if G.accent ~= a.name then
					G.accent = a.name
					saveG()
					task.defer(applyTheme) -- after this click finishes (the page it's on is rebuilt)
				end
			end, Color3.fromHex(a.dark))
		end
		App.explain(parent, "The accent the whole plugin wears: buttons, glow, the brush, painted ground and paths.")
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
		local about = box({ Size = UDim2.new(1, 0, 0, 40), Parent = parent }, { hlist(10) })
		App.new("ImageLabel", { Image = App.LOGO.mark, BackgroundTransparency = 1, Size = UDim2.fromOffset(32, 32), Parent = about })
		label("Smart Scatter  v" .. tostring(App.ctx.version or "dev") .. "  ·  made by Ghulo", 12, P.faint, SANS, {
			Size = UDim2.new(1, -42, 1, 0),
			Parent = about,
		})
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

	-- the footer: Live update, Shuffle and Clear; with Live update off, a Generate button on top. Messages show as
	-- toasts above it. A thin bar along its top edge shows a running job.
	local function footHeight()
		return G.live and 58 or 108
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
		-- progress of a running job: the accent filling along the top edge, with light sweeping through it
		local track = box({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 2), ZIndex = 3, Parent = foot })
		App.ui.progress = box({
			BackgroundTransparency = 0,
			BackgroundColor3 = P.accent,
			Size = UDim2.fromScale(0, 1),
			Visible = false,
			ZIndex = 3,
			Parent = track,
		})
		App.ui.progressSweep = App.sweep(App.ui.progress, 0.6)
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
			App.shade(App.ui.genBtn, 0.12)
			App.topLight(App.ui.genBtn, 0.35, 8)
			App.glow(App.ui.genBtn, 10, 0.7):set(true, true)
			App.ui.genSweep = App.sweep(App.ui.genBtn, 0.3)
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
		local sw, swGlow = switch(function()
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
		App.ui.liveGlow = swGlow -- breathes while a job runs
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
	end

	-- phase = "Scanning" / "Placing" with progress 0-1, or nil when the job is over: the bar along the footer's top
	-- edge, the Live update switch breathing, and (with Live update off) the Generate button counting
	local running = false
	App.showProgress = function(phase, progress)
		local bar, btn = App.ui.progress, App.ui.genBtn
		local on = phase ~= nil
		if on ~= running then -- start or end: light effects switch once, not every tick
			running = on
			if bar then
				bar.Visible = on
				App.ui.progressSweep:play(on)
			end
			if App.ui.liveGlow then
				App.ui.liveGlow:pulse(on)
			end
			if App.ui.genSweep then
				App.ui.genSweep:play(on)
			end
			if btn and App.ui.genBar then
				App.ui.genBar.Visible = on
			end
		end
		if not on then
			App.refreshCounts()
			return
		end
		local p = math.clamp(progress or 0, 0.02, 1)
		if bar then
			bar.Size = UDim2.fromScale(p, 1)
		end
		if btn and App.ui.genBar then
			App.ui.genBar.Size = UDim2.fromScale(p, 1)
			btn.Text = string.format("%s…  %d%%   ·   click to stop", phase, math.floor(p * 100 + 0.5))
			btn.Font = SANS_B
			btn.BackgroundColor3 = P.accent
			btn.TextColor3 = P.onAccent
		end
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

	-- Messages: a toast, a small glassy pill that slides up above the footer and fades after a while. One at a time;
	-- a new message replaces the text in place. tone: nil or "error" (red dot and glow, stays longer).
	local toastToken = 0
	App.status = function(msg, tone)
		local t = App.ui.toast
		if not t then
			return
		end
		toastToken += 1
		local my = toastToken
		if msg == "" then
			tween(t.group, FAST, { GroupTransparency = 1 })
			return
		end
		local err = tone == "error"
		t.text.Text = msg
		t.dot.BackgroundColor3 = err and P.danger or P.accent
		t.glow:set(err)
		if t.group.GroupTransparency > 0.5 then -- appearing: rise into place
			t.group.Position = UDim2.new(0.5, 0, 1, -footHeight() - 2)
			tween(t.group, MED, { GroupTransparency = 0, Position = UDim2.new(0.5, 0, 1, -footHeight() - 10) })
		end
		task.delay((err and 7 or 3.5) + #msg * 0.02, function()
			if my == toastToken and App.ui.toast == t then
				tween(t.group, MED, { GroupTransparency = 1 })
			end
		end)
	end
	local function buildToast(parent)
		local group = new("CanvasGroup", {
			BackgroundTransparency = 1,
			GroupTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -footHeight() - 10),
			Size = UDim2.new(1, -24, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			ZIndex = 60,
			Parent = parent,
		})
		local pill = col({
			BackgroundTransparency = 0.04,
			BackgroundColor3 = P.card,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.new(1, -8, 0, 0),
			ZIndex = 60,
			Parent = group,
		}, { corner(12), App.stroke(P.line), pad(34, 14, 9, 9) })
		App.shade(pill, 0.06)
		App.topLight(pill, 0.1, 12)
		local dot = box({
			BackgroundTransparency = 0,
			BackgroundColor3 = P.accent,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, -20, 0.5, 0),
			Size = UDim2.fromOffset(8, 8),
			ZIndex = 61,
			Parent = pill,
		}, { corner(4) })
		local text = para("", { ZIndex = 61, Parent = pill })
		text.TextColor3 = P.text
		App.ui.toast = { group = group, text = text, dot = dot, glow = App.glow(pill, 12, 0.6, P.danger) }
	end

	local builtPage
	App.rebuildAll = function()
		local keepScroll = builtPage == G.page and App.scroll and App.scroll.Parent and App.scroll.CanvasPosition
		local turned = builtPage ~= nil and builtPage ~= G.page -- another page: it slides in
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
		local scrollPad = App.scroll:FindFirstChildOfClass("UIPadding")
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
		buildToast(App.root)
		App.refreshScan()
		App.refreshObjects()
		if turned then
			scrollPad.PaddingLeft, scrollPad.PaddingRight = UDim.new(0, 38), UDim.new(0, -12)
			tween(scrollPad, MED, { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 12) })
		end
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

	-- a new accent, or Studio switched light / dark: the panel and everything drawn in the viewport take it on
	function applyTheme()
		makePalette()
		App.rebuildAll()
		rebuildOverlay()
		if App.removeSplineViz then
			App.removeSplineViz()
			App.drawSpline()
		end
	end
	track(settings().Studio.ThemeChanged:Connect(applyTheme))
end
