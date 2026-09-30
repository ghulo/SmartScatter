--[[
	Smart Scatter — Properties: the tabs for what's selected (Core/Selection), from the tabs the features registered
	(Core/Registry), and the page of the open one. Like Blender's properties editor: pick a thing and its settings are
	here; pick one of its objects and its Object tab opens. The tabs are a column of icons beside the page; the line
	over the page names what's open.
	Which tab is open: the one picked, while the selection keeps it; else the last one used for that kind of thing;
	else the one for its next step (an unpainted zone: Zone; an undrawn path: Curve; else Objects).
	Also the search results (every matching card of the selection's tabs and of Settings).
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
		if not thing then -- (nothing made yet: where to start; else the map's own tools)
			return #Engine.listAreas() == 0 and "start" or "world"
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
	-- The tabs: a column of icons down the left of the page (as in Blender's properties editor), so every tab fits
	-- however narrow the panel is. A tab's name is its tip, and the strip over the page says which one is open. The
	-- shell stands it on its rail (Panel/Shell).
	--------------------------------------------------------------------------------
	App.TAB_COL = 38 -- the column's width
	local TAB = 30 -- a tab's button
	App.buildTabColumn = function(parent)
		local open, tabs = App.currentTab()
		local column = new("ScrollingFrame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(0, App.TAB_COL, 1, 0),
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 0, -- (more tabs than fit: the wheel scrolls them)
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ZIndex = 2,
			Parent = parent,
		}, {
			new("UIListLayout", {
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				Padding = UDim.new(0, 4),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			App.pad(0, 0, 10, 10),
		})
		App.ui.tabRow = column
		App.ui.tabs = {}
		for i, t in tabs do
			local on = t == open and not App.searching()
			local b = new("TextButton", {
				Text = "",
				AutoButtonColor = false,
				BackgroundColor3 = on and P.accentSoft or P.hover,
				BackgroundTransparency = on and 0 or 1,
				Size = UDim2.fromOffset(TAB, TAB),
				LayoutOrder = i,
				ZIndex = 2,
				Parent = column,
			}, { App.corner(5) })
			local ic = App.icon(t.icon, 15, on and P.accent or P.dim)
			ic.AnchorPoint, ic.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
			ic.ZIndex = 3
			ic.Parent = b
			if on then
				box({ -- the open tab's mark, on the edge the page is on
					BackgroundTransparency = 0,
					BackgroundColor3 = P.accent,
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, 3, 0.5, 0),
					Size = UDim2.fromOffset(2, TAB - 12),
					ZIndex = 3,
					Parent = b,
				}, { App.corner(1) })
			else
				b.MouseEnter:Connect(function()
					b.BackgroundTransparency = 0
					App.setIconColor(ic, P.text)
				end)
				b.MouseLeave:Connect(function()
					b.BackgroundTransparency = 1
					App.setIconColor(ic, P.dim)
				end)
			end
			b.MouseButton1Click:Connect(function()
				App.openTab(t.id)
			end)
			App.hintOn(b, t.title)
			App.ui.tabs[t.id] = b
		end
		return column
	end

	-- The line over the page: what the settings below belong to (the thing, then its open object; a click on the thing
	-- goes back up to it) and, on the right, the open tab's name.
	App.buildCrumb = function(parent)
		local open = App.currentTab()
		local row = box({ Size = UDim2.new(1, 0, 0, 22), Parent = parent })
		local left = box({ Size = UDim2.new(1, -96, 1, 0), ClipsDescendants = true, Parent = row }, { hlist(6) })
		local function word(text, color, font, click)
			local w = new(click and "TextButton" or "TextLabel", {
				Text = text,
				Font = font,
				TextSize = 12,
				TextColor3 = color,
				TextTruncate = Enum.TextTruncate.AtEnd,
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(0, 22),
				AutomaticSize = Enum.AutomaticSize.X,
				Parent = left,
			}, { new("UISizeConstraint", { MaxSize = Vector2.new(130, 22) }) })
			if click then
				w.AutoButtonColor = false
				w.MouseEnter:Connect(function()
					w.TextColor3 = P.accent
				end)
				w.MouseLeave:Connect(function()
					w.TextColor3 = color
				end)
				w.MouseButton1Click:Connect(click)
			end
			return w
		end
		local sel, active = App.selected, App.active
		if App.searching() then
			word("Search results", P.dim, SANS_M)
		elseif not sel then
			word("Nothing selected", P.faint, SANS_M)
		else
			local spec = App.kindSpec(sel.kind)
			local name = sel.folder and sel.folder.Name or (spec and spec.title or sel.kind)
			if active then
				App.hintOn(
					word(name, P.dim, SANS_M, function()
						App.selectObject(nil)
					end),
					"Back to " .. name .. " itself."
				)
				local sep = App.icon("right", 9, P.faint)
				sep.AnchorPoint, sep.Position = Vector2.new(0, 0.5), UDim2.fromScale(0, 0.5)
				sep.Parent = box({ Size = UDim2.fromOffset(9, 22), Parent = left })
				word(active.inst.Name, P.text, SANS_B)
			else
				word(name, P.text, SANS_B)
			end
		end
		if open and not App.searching() then
			label(open.title, 12, P.dim, SANS_M, {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, 0, 0, 0),
				Size = UDim2.fromOffset(92, 22),
				TextXAlignment = Enum.TextXAlignment.Right,
				Parent = row,
			})
		end
		App.ui.crumb = row
		return row
	end

	--------------------------------------------------------------------------------
	-- The page
	--------------------------------------------------------------------------------
	-- the open tab's page, or the search results
	App.buildProperties = function(page)
		if App.searching() then
			App.buildSearchResults(page)
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
