--[[
	Smart Scatter — Shell: the panel around the tabs. The header (area picker), the tab bar (Scatter · Brush · Map ·
	Settings), the search box, the page that scrolls under them, the bar pinned to the bottom (Generate, Live
	update, Shuffle, Undo) and toasts; and the whole-panel rebuild. Each tab is its own module in Panel/Tabs.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local FAST, MED, tween, beginRec, endRec, track = App.FAST, App.MED, App.tween, App.beginRec, App.endRec, App.track
	local G, saveG, num, P, makePalette, SANS, SANS_B = App.G, App.saveG, App.num, App.P, App.makePalette, App.SANS, App.SANS_B
	local new, corner, pad, vlist, hlist, box, col, label = App.new, App.corner, App.pad, App.vlist, App.hlist, App.box, App.col, App.label
	local para, hintOn, rebuildOverlay, saveArea, canGenerate = App.para, App.hintOn, App.rebuildOverlay, App.saveArea, App.canGenerate
	local runGenerate, commit, buildHeader = App.runGenerate, App.commit, App.buildHeader

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

	-- a new random layout with the same settings (the Shuffle button and its key)
	App.shuffle = function()
		if not App.area then
			return
		end
		local rec = beginRec("Smart Scatter: Shuffle")
		App.area.seed = math.random(1, 999999)
		saveArea()
		endRec(rec)
		runGenerate(true)
	end

	-- the bar pinned to the bottom: Generate, Live update, Shuffle and Undo. Messages show as toasts above it. A thin
	-- line along its top edge fills while a job runs.
	local BAR_H = 60
	local function buildBar(parent)
		local foot = box({
			BackgroundTransparency = 0,
			BackgroundColor3 = P.header,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, BAR_H),
			ZIndex = 3,
			Parent = parent,
		})
		App.ui.foot = foot
		App.fadeLine(foot, nil, 0.16)
		-- progress of a running job: the accent filling along the top edge, with light sweeping through it
		local line = box({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 2), ZIndex = 4, Parent = foot })
		App.ui.progress = box({
			BackgroundTransparency = 0,
			BackgroundColor3 = P.accent,
			Size = UDim2.fromScale(0, 1),
			Visible = false,
			ZIndex = 4,
			Parent = line,
		})
		App.ui.progressSweep = App.sweep(App.ui.progress, 0.6)
		App.sheen(foot, 0.025, 40)
		local inner = box({ Position = UDim2.fromOffset(12, 11), Size = UDim2.new(1, -24, 0, 38), Parent = foot })
		local right = box({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromOffset(0, 38),
			AutomaticSize = Enum.AutomaticSize.X,
			Parent = inner,
		}, { hlist(6) })

		-- Generate: runs now (with Live update on too); while a job runs it shows progress and stops it
		App.ui.genBtn = new("TextButton", {
			Text = "Generate",
			Font = SANS_B,
			TextSize = 14,
			TextColor3 = P.onAccent,
			BackgroundColor3 = P.accent,
			AutoButtonColor = false,
			Size = UDim2.new(1, -174, 1, 0),
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = inner,
		}, { corner(10), pad(8, 8, 0, 0) })
		App.shade(App.ui.genBtn, 0.12)
		App.topLight(App.ui.genBtn, 0.35, 8)
		App.ui.genSweep = App.sweep(App.ui.genBtn, 0.3)
		local press = new("UIScale", { Parent = App.ui.genBtn })
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
			local ok, why = canGenerate()
			if not ok then -- (greyed out: say what's missing)
				App.status(why or "Nothing to generate yet.")
				return
			end
			if App.worldChanged() then -- read the ground again only if something under the area changed
				App.analysisDirty = true
			end
			runGenerate(true)
		end)
		hintOn(App.ui.genBtn, function()
			if App.busy() then
				return "Click to stop. Nothing changes until it's done."
			end
			local ok, why = canGenerate()
			if not ok then
				return (why or "Nothing to generate yet.") .. " Then this places everything."
			end
			if App.failure then
				return "The last Generate failed: " .. tostring(App.failure) .. ". Click to try again."
			end
			return "Places everything now. With Live on, changes do this by themselves."
		end)

		-- Live update: a pill that lights up when on
		local live = new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			Size = UDim2.fromOffset(78, 38),
			LayoutOrder = 1,
			Parent = right,
		}, { corner(10) })
		local liveStroke = App.stroke(P.line)
		liveStroke.Parent = live
		local dot = box({
			BackgroundTransparency = 0,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 12, 0.5, 0),
			Size = UDim2.fromOffset(8, 8),
			Parent = live,
		}, { corner(4) })
		local liveText = label("Live", 13, P.dim, App.SANS_M, { Position = UDim2.fromOffset(28, 0), Size = UDim2.new(1, -30, 1, 0), Parent = live })
		App.ui.liveGlow = App.glow(live, 10, 0.6) -- breathes while a job runs
		App.pressable(live, 0.95)
		local function liveLook()
			live.BackgroundColor3 = G.live and P.accentSoft or P.raised
			liveStroke.Color = G.live and P.accentLine or P.line
			dot.BackgroundColor3 = G.live and P.accent or P.faint
			liveText.TextColor3 = G.live and P.accent or P.dim
		end
		liveLook()
		live.MouseButton1Click:Connect(function()
			G.live = not G.live
			saveG()
			liveLook()
			if G.live then
				commit()
			end
			App.status(G.live and "Live update on: every change rebuilds as you make it." or "Live update off: changes wait for Generate.")
		end)
		hintOn(live, "On: every change rebuilds the area as you make it. Off: changes wait for the Generate button.")

		local shuffle = App.iconButton("refresh", "Shuffle: a new random layout with the same settings. Ctrl+Z goes back.", App.shuffle, false, 38)
		shuffle.LayoutOrder = 2
		shuffle.Parent = right
		local undo = App.iconButton("undo", "Undo the last step (Ctrl+Z)", function()
			local chs = App.ChangeHistoryService
			local ok, can = pcall(chs.GetCanUndo, chs)
			if ok and can == false then
				App.status("Nothing to undo.")
				return
			end
			pcall(chs.Undo, chs)
		end, false, 38)
		undo.LayoutOrder = 3
		undo.Parent = right
	end

	-- phase = "Scanning" / "Placing" with progress 0-1, or nil when the job is over: the line along the bottom bar's top
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

	-- Messages: a toast, a small glassy pill that slides up above the bottom bar and fades after a while. One at a time;
	-- a new message replaces the text in place. tone: nil or "error" (red dot and glow, stays longer).
	local toastToken = 0
	-- fades a message out; once gone it's hidden, so it never takes clicks meant for the cards under it
	local function hideToast(t, speed)
		toastToken += 1
		local my = toastToken
		tween(t.group, speed or MED, { GroupTransparency = 1 })
		task.delay(0.3, function()
			if my == toastToken then
				t.group.Visible = false
			end
		end)
	end
	App.status = function(msg, tone)
		local t = App.ui.toast
		if not t then
			return
		end
		if msg == "" then
			hideToast(t, FAST)
			return
		end
		toastToken += 1
		local my = toastToken
		t.group.Visible = true
		local err = tone == "error"
		t.text.Text = msg
		t.dot.BackgroundColor3 = err and P.danger or P.accent
		t.glow:set(err)
		if t.group.GroupTransparency > 0.5 then -- appearing: rise into place
			t.group.Position = UDim2.new(0.5, 0, 1, -BAR_H - 2)
			tween(t.group, MED, { GroupTransparency = 0, Position = UDim2.new(0.5, 0, 1, -BAR_H - 10) })
		end
		-- long enough to read, no longer: a quick note goes in a couple of seconds, a problem stays a while
		task.delay(err and 6 + #msg * 0.02 or math.min(2.2 + #msg * 0.012, 5), function()
			if my == toastToken and App.ui.toast == t then
				hideToast(t)
			end
		end)
	end
	-- a tool's how-to: shown the first couple of times it's picked this session, then left to the viewport label
	local hinted = {}
	App.hint = function(key, msg)
		hinted[key] = (hinted[key] or 0) + 1
		if hinted[key] <= 2 then
			App.status(msg)
		end
	end
	local function buildToast(parent)
		local group = new("CanvasGroup", {
			BackgroundTransparency = 1,
			GroupTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -BAR_H - 10),
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
		local t = { group = group, text = text, dot = dot, glow = App.glow(pill, 12, 0.6, P.danger) }
		-- a click puts it away
		new("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 62, Parent = group }).MouseButton1Click:Connect(
			function()
				hideToast(t, FAST)
			end
		)
		group.Visible = false
		App.ui.toast = t
	end

	--------------------------------------------------------------------------------
	-- Tabs and search
	--------------------------------------------------------------------------------
	local TABS = {
		{ name = "Scatter", icon = "layers", hint = "What fills the area: objects, their rules, pattern and presets.", build = "buildScatterTab" },
		{ name = "Brush", icon = "brush", hint = "Work by hand: paint the ground, brush one object, remove copies.", build = "buildBrushTab" },
		{
			name = "Map",
			icon = "spline",
			hint = "The path and its road; scanning a finished map, swapping its models, seasons and the snapshot.",
			build = "buildMapTab",
		},
		{ name = "Settings", icon = "settings", hint = "The plugin's look, output and shortcuts.", build = "buildSettingsTab" },
	}
	local TAB = {}
	for _, t in TABS do
		TAB[t.name] = t
	end
	-- a viewport tool belongs to the tab its controls are on: leaving that tab stops it
	local OWNER =
		{ Paint = "Brush", Erase = "Brush", More = "Brush", Less = "Brush", Clear = "Brush", Place = "Brush", Remove = "Brush", Spline = "Map" }

	-- the tab an area opens on: where its next step is
	local function homeTab()
		local a = App.area
		if not a then
			return "Scatter"
		end
		local kind = App.kindOf(a)
		if kind == "Path" then
			return App.hasPath() and "Scatter" or "Map"
		end
		if kind == "Clear" or (a.count or 0) == 0 then
			return "Brush"
		end
		return "Scatter"
	end

	local searchText = "" -- the search box's text (kept while the panel is rebuilt)
	local function clearSearch()
		searchText = ""
		App.setSearch("")
	end

	-- switch tab ("" picks the area's home tab); tools that belong to the old tab stop
	App.goPage = function(name)
		if G.page == name and not App.searching() then
			return
		end
		clearSearch()
		G.page = name
		saveG()
		local owner = OWNER[App.mode]
		if owner and owner ~= (TAB[name] and name or homeTab()) then
			App.setMode("Off")
		end
		App.rebuildAll()
	end

	local function buildTabs(parent)
		local bar = box({ BackgroundTransparency = 0, BackgroundColor3 = P.raised, Size = UDim2.new(1, 0, 0, 36), Parent = parent }, {
			corner(10),
			pad(3, 3, 3, 3),
			new("UIGridLayout", {
				CellSize = UDim2.new(1 / #TABS, -3, 1, 0),
				CellPadding = UDim2.fromOffset(3, 0),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		App.ui.tabs = {}
		local fits = {} -- [icon] = the label beside it: icons hide when the panel is too narrow for both
		for i, t in TABS do
			local on = G.page == t.name and not App.searching()
			local b = new("TextButton", {
				Text = "",
				AutoButtonColor = false,
				BackgroundTransparency = on and 0 or 1,
				BackgroundColor3 = P.card,
				LayoutOrder = i,
				Parent = bar,
			}, { corner(8) })
			if on then
				App.stroke(P.accentLine).Parent = b
			end
			local row = box({ Size = UDim2.fromScale(1, 1), Parent = b }, {
				new("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 5),
				}),
			})
			local fg = on and P.accent or P.dim
			local ic = App.icon(t.icon, 13, fg)
			ic.Parent = row
			local text = label(t.name, 12, fg, SANS_B, { Size = UDim2.fromOffset(0, 16), AutomaticSize = Enum.AutomaticSize.X, Parent = row })
			fits[ic] = text
			if not on then
				b.MouseEnter:Connect(function()
					text.TextColor3 = P.text
					App.setIconColor(ic, P.text)
				end)
				b.MouseLeave:Connect(function()
					text.TextColor3 = P.dim
					App.setIconColor(ic, P.dim)
				end)
			end
			b.MouseButton1Click:Connect(function()
				App.goPage(t.name)
			end)
			hintOn(b, t.hint)
			App.ui.tabs[t.name] = b
		end
		local function fit()
			local cell = bar.AbsoluteSize.X / #TABS - 3
			for ic, text in fits do
				ic.Visible = cell >= text.TextBounds.X + 13 + 5 + 12
			end
		end
		bar:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
		task.defer(fit) -- once the labels have measured their text
	end

	local buildPage -- (below)
	local function buildSearch(parent)
		local row = box({ BackgroundTransparency = 0, BackgroundColor3 = P.field, Size = UDim2.new(1, 0, 0, 32), Parent = parent }, { corner(9) })
		local st = App.stroke(P.line)
		st.Parent = row
		local ic = App.icon("search", 13, P.faint)
		ic.AnchorPoint, ic.Position = Vector2.new(0, 0.5), UDim2.new(0, 11, 0.5, 0)
		ic.Parent = row
		local tb = new("TextBox", {
			Text = searchText,
			PlaceholderText = "Search every setting",
			Font = SANS,
			TextSize = 13,
			TextColor3 = P.text,
			PlaceholderColor3 = P.faint,
			BackgroundTransparency = 1,
			ClearTextOnFocus = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(30, 0),
			Size = UDim2.new(1, -62, 1, 0),
			Parent = row,
		})
		App.ui.search = tb
		local x = App.iconButton("close", "Clear the search", function()
			tb.Text = ""
		end, false, 24)
		x.AnchorPoint, x.Position = Vector2.new(1, 0.5), UDim2.new(1, -4, 0.5, 0)
		x.Visible = searchText ~= ""
		x.Parent = row
		tb.Focused:Connect(function()
			st.Color = P.accentLine
		end)
		tb.FocusLost:Connect(function()
			st.Color = P.line
		end)
		-- the results follow the typing, a moment after it pauses
		local token = 0
		tb:GetPropertyChangedSignal("Text"):Connect(function()
			if tb.Text == searchText then
				return
			end
			searchText = tb.Text
			x.Visible = searchText ~= ""
			token += 1
			local my = token
			task.delay(0.2, function()
				if my ~= token or App.ui.search ~= tb then
					return
				end
				App.setSearch(searchText)
				buildPage()
			end)
		end)
	end

	--------------------------------------------------------------------------------
	-- The panel
	--------------------------------------------------------------------------------
	-- what stays across a page rebuild: the header, the tabs, the search box, the bar and the toast
	local SHELL = {
		"areaPick",
		"areaName",
		"plusBtn",
		"tabs",
		"search",
		"foot",
		"progress",
		"progressSweep",
		"genBtn",
		"genSweep",
		"genBar",
		"liveGlow",
		"toast",
		"popup",
	}

	-- search results: every tab's matching cards, under the tab's name
	local function buildResults(page)
		local any = false
		for _, t in TABS do
			local holder = col({ Parent = page }, { vlist(10) })
			-- the tab's name heads its results, and opens it (the search clears)
			local head = new("TextButton", {
				Text = "",
				AutoButtonColor = false,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 20),
				Parent = holder,
			}, { hlist(4) })
			local name = label(
				string.upper(t.name),
				11,
				P.faint,
				SANS_B,
				{ Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, Parent = head }
			)
			local go = App.icon("right", 10, P.faint)
			go.Parent = head
			head.MouseEnter:Connect(function()
				name.TextColor3 = P.accent
				App.setIconColor(go, P.accent)
			end)
			head.MouseLeave:Connect(function()
				name.TextColor3 = P.faint
				App.setIconColor(go, P.faint)
			end)
			head.MouseButton1Click:Connect(function()
				App.goPage(t.name)
			end)
			hintOn(head, "Open the " .. t.name .. " tab.")
			local before = App.cardCount
			App[t.build](holder)
			if App.cardCount == before then
				holder:Destroy()
			else
				any = true
			end
		end
		if not any then
			App.emptyState(page, "Nothing found", "Try another word, like road, colour, spacing or shortcut.")
		end
	end

	-- the scrolling page under the header: the open tab, the search results, or the welcome
	function buildPage()
		local sc = App.scroll
		if not sc then
			return
		end
		local keep = {}
		for _, k in SHELL do
			keep[k] = App.ui[k]
		end
		App.ui = keep
		App.hideTip()
		App.pruneThumbs() -- (kept for the rows about to be built)
		for _, ch in sc:GetChildren() do
			if ch:IsA("GuiObject") then
				ch:Destroy()
			end
		end
		App.ui.builtShape = App.shapeKey()
		local page = col({ Parent = sc }, { vlist(10) })
		if App.searching() then
			buildResults(page)
		elseif not App.area and (G.page == "Scatter" or G.page == "Brush") then
			App.buildWelcome(page)
		else
			App[TAB[G.page].build](page)
		end
		App.refreshScan()
		App.refreshObjects()
	end

	-- scrolls the page so obj (a card on it) is in view, near the top. After the rebuild has put the page back
	-- where it was (that happens a frame later), so it isn't undone.
	App.scrollIntoView = function(obj)
		task.defer(function()
			task.defer(function()
				local sc = App.scroll
				if not (sc and obj.Parent and obj:IsDescendantOf(sc)) then
					return
				end
				local top = obj.AbsolutePosition.Y - sc.AbsolutePosition.Y + sc.CanvasPosition.Y
				tween(sc, MED, { CanvasPosition = Vector2.new(0, math.max(top - 10, 0)) })
			end)
		end)
	end

	local builtPage
	App.rebuildAll = function()
		if not TAB[G.page] then
			G.page = homeTab()
		end
		local keepScroll = builtPage == G.page and App.scroll and App.scroll.Parent and App.scroll.CanvasPosition
		local turned = builtPage ~= nil and builtPage ~= G.page -- another tab: it slides in
		builtPage = G.page
		if App.root then
			App.pruneThumbs() -- (out of the panel before it goes, to be reused)
			App.root:Destroy()
		end
		App.ui = {}
		App.root = box({ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0, BackgroundColor3 = P.bg, Parent = App.widget })
		-- fixed top: title, area picker, tabs and search; only the page below scrolls
		local head = col({ BackgroundTransparency = 0, BackgroundColor3 = P.bg, ZIndex = 2, Parent = App.root }, { pad(14, 14, 12, 8), vlist(0) })
		App.scroll = new("ScrollingFrame", {
			Size = UDim2.new(1, 0, 1, -BAR_H),
			CanvasSize = UDim2.new(),
			BackgroundTransparency = 1,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 4,
			ScrollBarImageColor3 = P.faint,
			ScrollBarImageTransparency = 0.5,
			VerticalScrollBarInset = Enum.ScrollBarInset.Always,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			Parent = App.root,
		}, { pad(14, 12, 10, 24), vlist(2) })
		local scrollPad = App.scroll:FindFirstChildOfClass("UIPadding")
		App.scroll.MouseEnter:Connect(function()
			tween(App.scroll, FAST, { ScrollBarImageTransparency = 0.15 })
		end)
		App.scroll.MouseLeave:Connect(function()
			tween(App.scroll, FAST, { ScrollBarImageTransparency = 0.5 })
		end)
		buildHeader(head)
		box({ Size = UDim2.new(1, 0, 0, 8), Parent = head })
		buildTabs(head)
		box({ Size = UDim2.new(1, 0, 0, 8), Parent = head })
		buildSearch(head)
		box({ Size = UDim2.new(1, 0, 0, 10), Parent = head })
		App.fadeLine(head, nil, 0.16)
		App.sheen(App.root, 0.04, 140, 150)
		App.halftone(App.root, 0.07, 4, 150)
		local function fit()
			local h = head.AbsoluteSize.Y
			App.scroll.Position = UDim2.fromOffset(0, h)
			App.scroll.Size = UDim2.new(1, 0, 1, -h - BAR_H)
		end
		head:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
		fit()
		buildBar(App.root)
		buildToast(App.root)
		buildPage()
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
	local function applyTheme()
		makePalette()
		App.pruneThumbs(true) -- (their frames are in the old colours)
		App.rebuildAll()
		rebuildOverlay()
		if App.removeSplineViz then
			App.removeSplineViz()
			App.drawSpline()
		end
	end
	App.applyTheme = applyTheme
	track(settings().Studio.ThemeChanged:Connect(applyTheme))
end
