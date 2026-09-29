--[[
	Smart Scatter — Properties: the tabs for what's selected (Core/Selection), from the tabs the features registered
	(Core/Registry), and the page of the open one. Like Blender's properties editor: pick a thing and its settings are
	here; pick one of its objects and its Object tab opens.
	Which tab is open: the one picked, while the selection keeps it; else the last one used for that kind of thing;
	else the one for its next step (an unpainted zone: Zone; an undrawn path: Curve; else Objects).
	Also the search results (every matching card of the selection's tabs and of Settings) and, with no areas at all,
	the welcome.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local G, saveG, P, SANS_B, SANS_M = App.G, App.saveG, App.P, App.SANS_B, App.SANS_M
	local new, box, col, label, vlist, hlist = App.new, App.box, App.col, App.label, App.vlist, App.hlist
	local Engine = App.Engine

	App.propTab = nil -- the tab picked for the current selection (nil: choose one)
	local shownFor, lastActive -- what the tabs were last chosen for

	-- the tab a selection opens on when none was picked: where its next step is
	local function homeTab(thing)
		if not thing then
			return "world"
		end
		if thing.kind == "Stamps" then
			return "stamp"
		end
		local a = App.area
		if thing.kind == "Clear" then
			return "zone"
		end
		if thing.kind == "Path" then
			return App.hasPath() and "objects" or "curve"
		end
		return (a and (a.count or 0) == 0 and not App.hasPath()) and "zone" or "objects"
	end

	-- the open tab's spec for the current selection
	App.currentTab = function()
		local tabs = App.tabsFor(App.selected, App.active)
		local want = App.propTab or (App.selected and G.tabs[App.selected.kind]) or homeTab(App.selected)
		for _, t in tabs do
			if t.id == want then
				return t, tabs
			end
		end
		local home = homeTab(App.selected)
		for _, t in tabs do
			if t.id == home then
				return t, tabs
			end
		end
		return tabs[1], tabs
	end

	-- open a tab (and remember it for this kind of thing)
	App.openTab = function(id)
		App.settingsOpen = false
		if App.searching() and App.clearSearch then
			App.clearSearch()
		end
		App.propTab = id
		if App.selected then
			G.tabs[App.selected.kind] = id
			saveG()
		end
		App.rebuildAll()
	end

	-- the selection changed: a new thing chooses its tab again; a newly active object opens its Object tab, and when
	-- none is active any more, the Object tab gives way
	App.onSelect(function(thing, active)
		if not App.sameThing(thing, shownFor) then
			shownFor = thing
			App.propTab = nil
		end
		if active and active ~= lastActive then
			App.propTab = "object"
		elseif not active and App.propTab == "object" then
			App.propTab = "objects"
		end
		lastActive = active
	end)

	--------------------------------------------------------------------------------
	-- The tab row
	--------------------------------------------------------------------------------
	App.buildTabRow = function(parent)
		local open, tabs = App.currentTab()
		local strip = box({ Size = UDim2.new(1, 0, 0, 34), Parent = parent })
		App.ui.tabRow = strip
		local bar = box({ Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = strip }, {
			new("UIGridLayout", {
				CellSize = UDim2.new(1 / math.max(#tabs, 1), 0, 1, 0),
				CellPadding = UDim2.fromOffset(0, 0),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		box({ -- the hairline the tabs stand on
			BackgroundTransparency = 0,
			BackgroundColor3 = P.line,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, 0),
			Size = UDim2.new(1, 0, 0, 1),
			Parent = strip,
		})
		App.ui.tabs = {}
		local fits = {} -- [label] = its icon: under a certain width only the icons show (the name on hover)
		for i, t in tabs do
			local on = t == open and not App.searching()
			local b = new("TextButton", { Text = "", AutoButtonColor = false, BackgroundTransparency = 1, LayoutOrder = i, Parent = bar })
			if on then
				box({
					BackgroundTransparency = 0,
					BackgroundColor3 = P.accent,
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.fromScale(0.5, 1),
					Size = UDim2.new(1, -12, 0, 2),
					ZIndex = 3,
					Parent = b,
				}, { App.corner(1) })
			end
			local row = box({ Size = UDim2.fromScale(1, 1), Parent = b }, {
				new("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 5),
				}),
			})
			local fg = on and P.text or P.dim
			local ic = App.icon(t.icon, 13, on and P.accent or fg)
			ic.Parent = row
			local text = label(t.title, 12, fg, on and SANS_B or SANS_M, {
				Size = UDim2.fromOffset(0, 16),
				AutomaticSize = Enum.AutomaticSize.X,
				Parent = row,
			})
			fits[text] = ic
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
				App.openTab(t.id)
			end)
			App.hintOn(b, t.title)
			App.ui.tabs[t.id] = b
		end
		local function fit()
			local cell = bar.AbsoluteSize.X / math.max(#tabs, 1)
			for text, ic in fits do
				text.Visible = cell >= text.TextBounds.X + ic.AbsoluteSize.X + 5 + 10
			end
		end
		bar:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
		task.defer(fit) -- (once the names have measured their text)
		return strip
	end

	--------------------------------------------------------------------------------
	-- The page
	--------------------------------------------------------------------------------
	-- the open tab's page, the search results, or (no areas at all, nothing picked) the welcome
	App.buildProperties = function(page)
		if App.searching() then
			App.buildSearchResults(page)
			return
		end
		if not App.selected and #Engine.listAreas() == 0 then
			App.buildWelcome(page)
			return
		end
		local open = App.currentTab()
		if open then
			open.build(page)
		end
	end

	-- every tab of the selection with cards matching the search, under its name (a click opens it), then Settings
	App.buildSearchResults = function(page)
		local any = false
		local function section(title, onOpen, build)
			local holder = col({ Parent = page }, { vlist(10) })
			local head = new("TextButton", {
				Text = "",
				AutoButtonColor = false,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 20),
				Parent = holder,
			}, { hlist(4) })
			local name = label(
				string.upper(title),
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
			head.MouseButton1Click:Connect(onOpen)
			local before = App.cardCount
			build(holder)
			if App.cardCount == before then
				holder:Destroy()
			else
				any = true
			end
		end
		for _, t in App.tabsFor(App.selected, App.active) do
			section(t.title, function()
				App.openTab(t.id)
			end, t.build)
		end
		section("Settings", function()
			App.openSettings(true)
		end, App.buildSettingsPage)
		if not any then
			App.emptyState(page, "Nothing found", "Try another word, like road, colour, spacing or shortcut.")
		end
	end
end
