--[[
	Smart Scatter — Shell: the panel's frame. At the top the name with + New and Settings, the search box, the
	outliner (Panel/Outliner) and the selection's tabs (Panel/Properties); under them the page that scrolls; the bar
	pinned to the bottom (Generate, Live update, Shuffle, Undo, the history) and toasts; and the whole-panel rebuild,
	which follows the selection.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local FAST, MED, tween, beginRec, endRec, track = App.FAST, App.MED, App.tween, App.beginRec, App.endRec, App.track
	local G, saveG, num, P, makePalette, SANS, SANS_B = App.G, App.saveG, App.num, App.P, App.makePalette, App.SANS, App.SANS_B
	local new, corner, pad, vlist, hlist, box, col, label = App.new, App.corner, App.pad, App.vlist, App.hlist, App.box, App.col, App.label
	local para, hintOn, rebuildOverlay, saveArea, canGenerate = App.para, App.hintOn, App.rebuildOverlay, App.saveArea, App.canGenerate
	local runGenerate, commit = App.runGenerate, App.commit
	local PAGE_PAD = 14 -- the page's side margin
	local CRUMB_H = 30 -- the strip across the top of the workbench
	local SHADOW = settings().Studio.Theme.Name == "Light" and 0.9 or 0.72 -- how see-through a shadow is at its darkest

	-- how heavy the area's output is for players: a note ("" when fine) and whether it's too much
	App.perfNote = function()
		if App.area and App.area.folder.Parent and App.Engine.isPreview(App.area) then
			return "Some are still a preview (boxes): press Generate to place the real models.", false
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

	-- Generate: places the real models now (a live preview's boxes too); while a job runs, stops it
	App.generateNow = function()
		if App.busy() then
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
		runGenerate(true, nil, nil, true)
	end
	-- Live on or off (the pill in the bottom bar)
	App.toggleLive = function()
		G.live = not G.live
		saveG()
		if App.ui.liveLook then
			App.ui.liveLook()
		end
		if G.live then
			commit()
		end
		App.status(
			G.live
					and (G.liveBoxes and "Live on: changes show as you make them (a big area as see-through boxes until Generate)." or "Live update on: every change rebuilds as you make it.")
				or "Live off: changes wait for Generate."
		)
	end
	-- undo or redo one step (the bottom bar's button, and the search menu)
	App.undoStep = function(redo)
		local chs = App.ChangeHistoryService
		local ok, can = pcall(redo and chs.GetCanRedo or chs.GetCanUndo, chs)
		if ok and can == false then
			App.status(redo and "Nothing to redo." or "Nothing to undo.")
			return
		end
		pcall(redo and chs.Redo or chs.Undo, chs)
	end

	-- the bar pinned to the bottom: Generate, Live update, Shuffle and Undo. Messages show as toasts above it. A thin
	-- line along its top edge fills while a job runs.
	local buildTimeline -- (below)
	-- its height: the buttons, and the history timeline above them when it's shown (Settings)
	local STRIP_H = 22
	local function barH()
		return 60 + (G.history and STRIP_H or 0)
	end
	--------------------------------------------------------------------------------
	-- The history timeline: a tick per step Smart Scatter took (Core/History), like ZBrush's undo history
	--------------------------------------------------------------------------------
	local SHOWN_STEPS = 60 -- the newest ones; older steps are still undone on the way back
	local function ago(t)
		local d = os.time() - t
		return d < 60 and "just now" or d < 3600 and (math.floor(d / 60) .. " min ago") or (math.floor(d / 3600) .. " h ago")
	end
	function buildTimeline(foot)
		local strip = box({ Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, STRIP_H - 6), Parent = foot })
		App.ui.history = strip
		local function draw()
			strip:ClearAllChildren()
			local H = App.history
			local n = #H.list
			if n == 0 then
				label("History · your steps show up here", 11, P.faint, SANS, { Size = UDim2.fromScale(1, 1), Parent = strip })
				return
			end
			local first = math.max(0, n - SHOWN_STEPS) -- (0: the start, before any step)
			local count = n - first + 1
			-- a faint baseline the ticks stand on
			box({
				BackgroundTransparency = 0,
				BackgroundColor3 = P.line,
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.new(1, 0, 0, 1),
				Parent = strip,
			})
			for i = first, n do
				local x = count > 1 and (i - first) / (count - 1) or 0
				local here, done = i == H.pos, i < H.pos
				local hit = new("TextButton", {
					Text = "",
					AutoButtonColor = false,
					BackgroundTransparency = 1,
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(x, 0, 0, 0),
					Size = UDim2.new(0, 10, 1, 0),
					Parent = strip,
				})
				local line = box({
					BackgroundTransparency = 0,
					BackgroundColor3 = here and P.accent or done and P.dim or P.line,
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.new(0.5, 0, 1, 0),
					Size = UDim2.fromOffset(here and 3 or 2, here and 16 or (i == 0 and 6 or 10)),
					Parent = hit,
				}, { corner(1) })
				hit.MouseEnter:Connect(function()
					if not here then
						line.BackgroundColor3 = P.text
					end
				end)
				hit.MouseLeave:Connect(function()
					line.BackgroundColor3 = here and P.accent or done and P.dim or P.line
				end)
				hintOn(hit, function()
					local what = i == 0 and "Before your first step" or string.gsub(H.list[i].name, "^Smart Scatter: ", "")
					local when = i > 0 and ("  ·  " .. ago(H.list[i].time)) or ""
					return what .. when .. (here and "  ·  you're here" or "  ·  click to go here (Studio edits in between go with it)")
				end)
				hit.MouseButton1Click:Connect(function()
					if i ~= App.history.pos then
						local from = App.history.pos
						App.historyJump(i)
						App.status(
							i < from and string.format("Went back %d step%s.", from - i, from - i == 1 and "" or "s")
								or string.format("Went forward %d step%s.", i - from, i - from == 1 and "" or "s")
						)
					end
				end)
			end
		end
		draw()
		App.onHistoryChanged = function()
			if App.ui.history == strip and strip.Parent then
				draw()
			end
		end
	end

	local function buildBar(parent)
		local foot = box({
			BackgroundTransparency = 0,
			BackgroundColor3 = P.header,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, barH()),
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
		if G.history then
			buildTimeline(foot)
		end
		local inner = box({ Position = UDim2.fromOffset(12, 11 + (G.history and STRIP_H or 0)), Size = UDim2.new(1, -24, 0, 38), Parent = foot })
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
			Size = UDim2.new(1, -162, 1, 0),
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = inner,
		}, { corner(6), pad(8, 8, 0, 0) })
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
		}, { corner(6) })
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
		App.ui.genBtn.MouseButton1Click:Connect(App.generateNow)
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
			if App.hasPending() then
				return "You've changed settings, ground or the path since the last Generate. Click to place them."
			end
			return "Places the real models now. With Live on, a big area's changes show as see-through boxes first; this turns them into the models."
		end)

		-- Live update: a pill that lights up when on
		local live = new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			Size = UDim2.fromOffset(66, 38),
			LayoutOrder = 1,
			Parent = right,
		}, { corner(6) })
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
		App.ui.liveGlow = App.glow(live, 10, 0.6) -- a steady ring while a job runs
		App.pressable(live, 0.95)
		local function liveLook()
			live.BackgroundColor3 = G.live and P.accentSoft or P.raised
			liveStroke.Color = G.live and P.accentLine or P.line
			dot.BackgroundColor3 = G.live and P.accent or P.faint
			liveText.TextColor3 = G.live and P.accent or P.dim
		end
		liveLook()
		App.ui.liveLook = liveLook
		-- in a narrow panel Live is its dot alone, so Generate keeps room for its word
		local genPad = App.ui.genBtn:FindFirstChildOfClass("UIPadding")
		local function fitFoot()
			local tight = inner.AbsoluteSize.X < 250
			live.Size = UDim2.fromOffset(tight and 32 or 66, 38)
			liveText.Visible = not tight
			dot.Position = tight and UDim2.new(0.5, -4, 0.5, 0) or UDim2.new(0, 12, 0.5, 0)
			local side = tight and 4 or 8
			genPad.PaddingLeft, genPad.PaddingRight = UDim.new(0, side), UDim.new(0, side)
			App.ui.genBtn.Size = UDim2.new(1, -(right.AbsoluteSize.X + 6), 1, 0) -- (what the buttons beside it leave)
		end
		inner:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitFoot)
		right:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitFoot)
		fitFoot()
		live.MouseButton1Click:Connect(App.toggleLive)
		hintOn(
			live,
			"On: every change shows right away (a big area as see-through boxes until Generate). Off: changes wait for Generate; brushing one object and its buttons always show at once."
		)

		local shuffle = App.iconButton("refresh", "Shuffle: a new random layout with the same settings. Ctrl+Z goes back.", App.shuffle, false, 38)
		shuffle.LayoutOrder = 2
		shuffle.Parent = right
		local undo = App.iconButton("undo", "Undo the last step (Ctrl+Z)", function()
			App.undoStep()
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
			t.group.Position = UDim2.new(0.5, 0, 1, -barH() - 2)
			tween(t.group, MED, { GroupTransparency = 0, Position = UDim2.new(0.5, 0, 1, -barH() - 10) })
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
			Position = UDim2.new(0.5, 0, 1, -barH() - 10),
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
	-- The head: the name, + New, Settings; the search box; the outliner; the selection's tabs
	--------------------------------------------------------------------------------
	local searchText = "" -- the search box's text (kept while the panel is rebuilt)
	local function clearSearch()
		searchText = ""
		App.setSearch("")
	end
	App.clearSearch = clearSearch

	-- the settings page in place of the outliner and the properties (the ⚙; its back arrow returns)
	App.settingsOpen = false
	App.openSettings = function(on)
		App.settingsOpen = on
		clearSearch()
		App.rebuildAll()
	end

	-- the top line: the plugin's mark and name (or, on the settings page, the way back), + New and ⚙
	local function buildTitle(parent)
		local row = box({ Size = UDim2.new(1, 0, 0, 30), Parent = parent })
		if App.settingsOpen then
			App.pageHead(row, "Settings", nil, function()
				App.openSettings(false)
			end)
		else
			new("ImageLabel", {
				Image = App.LOGO.mark,
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 0, 0.5, 0),
				Size = UDim2.fromOffset(20, 20),
				Parent = row,
			})
			label("Smart Scatter", 14, P.text, SANS_B, { Position = UDim2.fromOffset(28, 0), Size = UDim2.new(1, -110, 1, 0), Parent = row })
		end
		local right = box({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromOffset(0, 30),
			AutomaticSize = Enum.AutomaticSize.X,
			Parent = row,
		}, { hlist(6) })
		if not App.settingsOpen then
			local plus = App.iconButton("plus", "New: a zone, a path or a keep-clear zone", function(b)
				App.openNewMenu(b)
			end, false, 30)
			plus.LayoutOrder = 1
			plus.Parent = right
			App.ui.plusBtn = plus
		end
		local gear = App.iconButton("settings", App.settingsOpen and "Back to your things" or "Settings", function()
			App.openSettings(not App.settingsOpen)
		end, App.settingsOpen, 30)
		gear.LayoutOrder = 2
		gear.Parent = right
		App.ui.gearBtn = gear
	end

	local buildPage, enterCards -- (below)
	local function buildSearch(parent)
		local row = box({ BackgroundTransparency = 0, BackgroundColor3 = P.field, Size = UDim2.new(1, 0, 0, 32), Parent = parent }, { corner(6) })
		local st = App.stroke(P.line)
		st.Parent = row
		local ic = App.icon("search", 13, P.faint)
		ic.AnchorPoint, ic.Position = Vector2.new(0, 0.5), UDim2.new(0, 11, 0.5, 0)
		ic.Parent = row
		local tb = new("TextBox", {
			Text = searchText,
			PlaceholderText = "Search settings  ·  " .. App.keyText("palette") .. " for any action",
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
	-- what stays across a page rebuild: the head (title, search, outliner, tabs), the bar and the toast
	local SHELL = {
		"plusBtn",
		"gearBtn",
		"outliner",
		"outlinerCount",
		"outlinerFilter",
		"tabs",
		"tabRow",
		"crumb",
		"search",
		"foot",
		"progress",
		"progressSweep",
		"genBtn",
		"genSweep",
		"genBar",
		"liveGlow",
		"history",
		"toast",
		"popup",
	}

	-- the scrolling page under the head: the selection's open tab, the search results, the settings or the welcome
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
		App.pruneThumbs(false, sc) -- (the page's, kept for the rows about to be built; the outliner keeps its own)
		for _, ch in sc:GetChildren() do
			if ch:IsA("GuiObject") then
				ch:Destroy()
			end
		end
		App.ui.builtShape = App.shapeKey()
		local page = col({ Parent = sc }, { vlist(10) })
		if App.settingsOpen and not App.searching() then
			App.buildSettingsPage(page)
		else
			App.buildProperties(page) -- (the open tab, the search results, or the welcome: Panel/Properties)
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

	-- the page's cards arriving one after another: each fades in and settles from a touch smaller, a beat after the
	-- one above it (the first several; the rest are below the fold anyway)
	local ENTER = TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	function enterCards()
		local k = 0
		for _, c in App.scroll:GetDescendants() do
			if k >= 8 then
				break
			end
			if c:IsA("GuiObject") and c:GetAttribute("SS_Card") then
				local sc = new("UIScale", { Scale = 0.97, Parent = c })
				local rest = c.BackgroundTransparency
				c.BackgroundTransparency = 1
				task.delay(k * 0.045, function()
					if c.Parent then
						tween(sc, ENTER, { Scale = 1 })
						tween(c, MED, { BackgroundTransparency = rest })
					end
				end)
				k += 1
			end
		end
	end

	local builtPage
	local firstBuild = true
	-- what the page shows: the settings, or a tab of a thing (another one slides in; the same one keeps its scroll)
	local function pageKey()
		if App.settingsOpen then
			return "settings"
		end
		local t = App.currentTab()
		local sel = App.selected
		local what = "none"
		if sel then
			what = sel.kind .. ":" .. (sel.folder and sel.folder:GetFullName() or "")
		end
		return what .. "|" .. (t and t.id or "")
	end
	App.rebuildAll = function()
		local key = pageKey()
		local keepScroll = builtPage == key and App.scroll and App.scroll.Parent and App.scroll.CanvasPosition
		local turned = builtPage ~= nil and builtPage ~= key -- another tab or thing: it slides in
		builtPage = key
		if App.root then
			App.pruneThumbs() -- (out of the panel before it goes, to be reused)
			App.root:Destroy()
		end
		App.ui = {}
		for _, old in App.widget:GetChildren() do -- (the colour blobs of versions before 9.97, left in the widget)
			if old.Name == "SS_Backdrop" then
				old:Destroy()
			end
		end
		App.root = box({
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 0,
			BackgroundColor3 = P.bg,
			ZIndex = 1,
			Parent = App.widget,
		})
		App.root.InputBegan:Connect(function(input) -- shortcuts work with the mouse over the panel too
			if App.panelKey then
				App.panelKey(input)
			end
		end)
		App.root.InputEnded:Connect(function(input) -- a stroke or drag let go over the panel ends there
			if input.UserInputType == Enum.UserInputType.MouseButton1 and App.releaseMouse then
				App.releaseMouse()
			end
		end)
		-- Fixed top: title, search and the outliner; only the page below scrolls. Its ground is the panel's colour
		-- with a wash of the accent at the very top, fading out by the outliner: the one place the theme's colour
		-- shows as colour and not as a mark on something.
		local head = col({
			BackgroundTransparency = 0,
			BackgroundColor3 = Color3.new(1, 1, 1),
			ZIndex = 2,
			Parent = App.root,
		}, {
			pad(14, 14, 12, 8),
			vlist(0),
			new("UIGradient", {
				Rotation = 90,
				Color = ColorSequence.new(P.bg:Lerp(P.accent, 0.18), P.bg),
			}),
		})
		App.scroll = new("ScrollingFrame", {
			Size = UDim2.new(1, 0, 1, -barH()),
			CanvasSize = UDim2.new(),
			BackgroundTransparency = 1,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 4,
			ScrollBarImageColor3 = P.faint,
			ScrollBarImageTransparency = 0.5,
			VerticalScrollBarInset = Enum.ScrollBarInset.Always,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			Parent = App.root,
		}, { pad(PAGE_PAD, 12, 10, 24), vlist(2) })
		local scrollPad = App.scroll:FindFirstChildOfClass("UIPadding")
		App.scroll.MouseEnter:Connect(function()
			tween(App.scroll, FAST, { ScrollBarImageTransparency = 0.15 })
		end)
		App.scroll.MouseLeave:Connect(function()
			tween(App.scroll, FAST, { ScrollBarImageTransparency = 0.5 })
		end)
		buildTitle(head)
		if App.settingsOpen or not G.compact then -- (compact: no search box over the outliner; Space still searches)
			box({ Size = UDim2.new(1, 0, 0, 8), Parent = head })
			buildSearch(head)
		end
		if not App.settingsOpen then
			box({ Size = UDim2.new(1, 0, 0, 8), Parent = head })
			App.buildOutliner(head)
			if App.toolbarAvailable and not App.toolbarAvailable() then -- (no tool strip here: the same tools here)
				box({ Size = UDim2.new(1, 0, 0, 6), Parent = head })
				App.buildToolRow(head)
			end
		end
		box({ Size = UDim2.new(1, 0, 0, 2), Parent = head })
		-- The workbench, under the head: one solid sheet, with a strip across its top naming what's open, the tabs as a rail down its left on a darker
		-- ground, and the page. The settings page has the sheet alone.
		local bench = box({ BackgroundTransparency = 0, BackgroundColor3 = P.bg, ZIndex = 0, Parent = App.root })
		box({ BackgroundTransparency = 0, BackgroundColor3 = P.line, Size = UDim2.new(1, 0, 0, 1), Parent = bench })
		local strip, column, rail
		if not App.settingsOpen then
			strip = box({ BackgroundTransparency = 0, BackgroundColor3 = P.strip, Size = UDim2.new(1, 0, 0, CRUMB_H), Parent = bench }, {
				pad(PAGE_PAD, PAGE_PAD, 4, 4),
			})
			App.shade(strip, 0.14) -- (lit from the top, as a header bar is)
			App.buildCrumb(strip)
			box({
				BackgroundTransparency = 0,
				BackgroundColor3 = P.line,
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, -PAGE_PAD, 1, 4),
				Size = UDim2.new(1, PAGE_PAD * 2, 0, 1),
				Parent = strip,
			})
			rail = box({
				BackgroundTransparency = 0,
				BackgroundColor3 = P.well,
				Position = UDim2.fromOffset(0, CRUMB_H),
				Size = UDim2.new(0, App.TAB_COL, 1, -CRUMB_H),
				Parent = bench,
			})
			box({ -- the rail's edge, on the page's side
				BackgroundTransparency = 0,
				BackgroundColor3 = P.line,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromScale(1, 0),
				Size = UDim2.new(0, 1, 1, 0),
				Parent = rail,
			})
			column = App.buildTabColumn(rail)
			column.Size = UDim2.fromScale(1, 1)
			scrollPad.PaddingLeft = UDim.new(0, PAGE_PAD - 8) -- (beside the rail the page needs less of a margin)
		end
		local left = column and App.TAB_COL or 0
		local top = strip and CRUMB_H or 0
		-- soft shadows over the page's two edges (it scrolls under the strip and down to the footer): a few pixels of
		-- dark fading out, so the surfaces read as lying one over the other
		local function shadow(up)
			local f = box({ BackgroundTransparency = 0, BackgroundColor3 = Color3.new(0, 0, 0), Active = false, ZIndex = 3, Parent = App.root })
			new("UIGradient", {
				Rotation = 90,
				Transparency = up and NumberSequence.new(1, SHADOW) or NumberSequence.new(SHADOW, 1),
				Parent = f,
			})
			return f
		end
		local under, over = shadow(false), shadow(true)
		local function fit()
			local h = head.AbsoluteSize.Y
			bench.Position = UDim2.fromOffset(0, h)
			bench.Size = UDim2.new(1, 0, 1, -h - barH())
			App.scroll.Position = UDim2.fromOffset(left, h + top)
			App.scroll.Size = UDim2.new(1, -left, 1, -h - top - barH())
			under.Position = UDim2.fromOffset(left, h + top)
			under.Size = UDim2.new(1, -left, 0, 8)
			over.Position = UDim2.new(0, left, 1, -barH() - 10)
			over.Size = UDim2.new(1, -left, 0, 10)
		end
		head:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
		fit()
		buildBar(App.root)
		buildToast(App.root)
		buildPage()
		if turned then -- the new page slides in from the right
			local rest = scrollPad.PaddingLeft.Offset
			scrollPad.PaddingLeft, scrollPad.PaddingRight = UDim.new(0, rest + 24), UDim.new(0, -12)
			tween(scrollPad, MED, { PaddingLeft = UDim.new(0, rest), PaddingRight = UDim.new(0, 12) })
		end
		if turned or firstBuild then
			enterCards()
		end
		firstBuild = false
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

	-- the selection changed (Core/Selection): the outliner, the tabs and the page follow, rebuilt once however many
	-- changes came together
	local rebuildQueued = false
	App.onSelect(function()
		if rebuildQueued then
			return
		end
		rebuildQueued = true
		task.defer(function()
			rebuildQueued = false
			App.rebuildAll()
		end)
	end)
	track(settings().Studio.ThemeChanged:Connect(applyTheme))
end
