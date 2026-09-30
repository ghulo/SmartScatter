--[[
	Smart Scatter — Cards: how every tab lays out its features, and the search box that finds them.
	A tab is a column of cards, one per feature: the basics first, then the extras folded under "More options".
	While searching, only the cards whose words match are built, and the extras show without the fold.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local G, saveG, P, SANS_B = App.G, App.saveG, App.P, App.SANS_B
	local new, corner, stroke, pad, vlist, hlist = App.new, App.corner, App.stroke, App.pad, App.vlist, App.hlist
	local box, col, label, icon = App.box, App.col, App.label, App.icon

	-- one line under a card's title, so what's inside can be seen at a glance (a card may pass its own `sub`)
	local SUB = {
		scanfix = "Tell it what's a road, building or water",
		line = "What it follows and which way it faces",
		variants = "Mix several models in one object",
		size = "Random sizes, smallest to largest",
		spread = "Spacing, clumping and a limit",
		groups = "Small piles, like rocks or crates",
		surfaces = "Grass, sand, rock… and a height band",
		avoid = "Distance from buildings, roads, water",
		attract = "Grow close to walls, water or roads",
		terrain = "Steepest ground and leaning",
		look = "Rotation, tilt, colour, variation and sinking",
		presets = "Save this set of objects, reuse it anywhere",
		output = "Collision, shadows, streaming",
	}

	-- every card's badge, by its id (a card may pass its own `icon`)
	local ICON = {
		objects = "layers",
		biomes = "leaf",
		pattern = "grid",
		zones = "blend",
		edges = "wind",
		presets = "bookmark",
		performance = "chart",
		clearzone = "clear",
		paint = "brush",
		stamp = "stamp",
		objectbrush = "spray",
		removecopies = "close",
		paintfilter = "filter",
		tidy = "wand",
		pathbrush = "spline",
		path = "spline",
		curve = "spline",
		line = "spline",
		road = "road",
		mapscan = "search",
		swap = "swap",
		layout = "spread",
		seasons = "snow",
		snapshot = "camera",
		scanfix = "pin",
		look = "palette",
		viewport = "eye",
		output = "cube",
		about = "info",
		shortcuts = "keyboard",
		placement = "tag",
		variants = "layers",
		size = "scale",
		spread = "spread",
		groups = "stack",
		surfaces = "leaf",
		avoid = "shield",
		attract = "magnet",
		terrain = "mountain",
	}

	-- the search box's words, lowercased ({} when not searching)
	App.searchWords = {}
	App.searching = function()
		return #App.searchWords > 0
	end
	App.setSearch = function(text)
		local words = {}
		for w in string.gmatch(string.lower(text or ""), "%S+") do
			table.insert(words, w)
		end
		App.searchWords = words
	end
	-- a card matches when every word is found in its title, subtitle or keywords
	local function matches(spec)
		local hay = string.lower(spec.title .. " " .. (spec.sub or SUB[spec.id] or "") .. " " .. (spec.keys or ""))
		for _, w in App.searchWords do
			if not string.find(hay, w, 1, true) then
				return false
			end
		end
		return true
	end

	App.cardCount = 0 -- cards built since the panel was last built (the search tells empty tabs from ones with hits)

	-- One feature's card: a title, a line under it, and its controls. spec: { id, title, sub?, icon?, tag?, keys?, build }
	-- A card is a section of the page, flat on it, under a bar with its name, as a panel in Blender's properties: a
	-- click on the bar folds the section away, and it stays folded (G.groups, by the tab's cards id and its own) until
	-- it's clicked again. A search shows every match unfolded. Its edge is only drawn for a moment, when a search
	-- jumps to it.
	local function card(parent, spec, group)
		App.cardCount += 1
		local key = "fold:" .. group .. ":" .. spec.id
		local open = App.searching() or G.groups[key] ~= true
		local c = col({ Parent = parent }, { corner(6), vlist(6) })
		local edge = stroke(P.accent)
		edge.Transparency = 1
		edge.Parent = c
		local head = new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = P.strip,
			Size = UDim2.new(1, 0, 0, 28),
			Parent = c,
		}, { corner(5), pad(9, 9, 0, 0), hlist(7) })
		App.shade(head, 0.12)
		-- (two arrows, one shown: an icon turned inside a list layout isn't drawn turned)
		local shut, unfolded = icon("right", 9, P.dim), icon("down", 9, P.dim)
		shut.Visible, unfolded.Visible = not open, open
		shut.Parent, unfolded.Parent = head, head
		local badgeIcon = spec.icon or ICON[spec.id]
		if badgeIcon then
			local ic = icon(badgeIcon, 13, P.accent)
			ic.Parent = head
		end
		label(spec.title, 13, P.text, SANS_B, { Size = UDim2.fromOffset(0, 28), AutomaticSize = Enum.AutomaticSize.X, Parent = head })
		if spec.tag then -- a small tag after the title ("Optional")
			local tag = label(spec.tag, 11, P.faint, App.SANS_M, {
				Size = UDim2.fromOffset(0, 28),
				AutomaticSize = Enum.AutomaticSize.X,
				Parent = head,
			})
			tag.TextYAlignment = Enum.TextYAlignment.Center
		end
		local inner = col({ Visible = open, Parent = c }, { pad(9, 9, 2, 8), vlist(8) })
		local sub = spec.sub or SUB[spec.id]
		if sub and sub ~= "" then
			local t = App.para(sub, { Parent = inner })
			t.TextColor3 = P.dim
		end
		local body = col({ Parent = inner }, { vlist(6) })
		spec.build(body, c)
		head.MouseEnter:Connect(function()
			head.BackgroundColor3 = P.hover
		end)
		head.MouseLeave:Connect(function()
			head.BackgroundColor3 = P.strip
		end)
		head.MouseButton1Click:Connect(function()
			open = not open
			G.groups[key] = not open or nil
			saveG()
			inner.Visible = open
			shut.Visible, unfolded.Visible = not open, open
		end)
		c:SetAttribute("SS_Card", spec.id) -- (App.openCard finds it by this)
		return c
	end

	-- a tab's column of cards. id names its "More options" fold (its open state is remembered).
	-- cards.add(spec): spec.more puts the card under the fold. Returns the card, or nil when the search skips it.
	App.cards = function(parent, id)
		local cs = {}
		local fold, foldBody, foldCount
		local function moreBody()
			if App.searching() then -- search results show flat
				return parent
			end
			if foldBody then
				return foldBody
			end
			local key = "more:" .. id
			local open = G.groups[key] == true
			-- (last in the column, whatever comes after it: everything else keeps the order it was made in, Kit's new)
			fold = col({ LayoutOrder = 2 ^ 30, Parent = parent }, { vlist(10) })
			local head = new("TextButton", {
				Text = "",
				AutoButtonColor = false,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 30),
				Parent = fold,
			})
			local line = box({
				BackgroundTransparency = 0,
				BackgroundColor3 = P.line,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromScale(0, 0.5),
				Size = UDim2.new(1, 0, 0, 1),
				Parent = head,
			})
			local chip = box({
				BackgroundTransparency = 0,
				BackgroundColor3 = P.bg,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(0, 26),
				AutomaticSize = Enum.AutomaticSize.X,
				Parent = head,
			}, { pad(10, 10, 0, 0), hlist(6) })
			local chev = icon("right", 11, P.dim)
			chev.Parent = chip
			foldCount = label("", 12, P.dim, SANS_B, { Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, Parent = chip })
			foldBody = col({ Parent = fold }, { vlist(10) })
			local function look()
				foldBody.Visible = open
				chev.Rotation = open and 90 or 0
			end
			look()
			head.MouseEnter:Connect(function()
				foldCount.TextColor3 = P.text
				line.BackgroundColor3 = P.accentLine
			end)
			head.MouseLeave:Connect(function()
				foldCount.TextColor3 = P.dim
				line.BackgroundColor3 = P.line
			end)
			head.MouseButton1Click:Connect(function()
				open = not open
				G.groups[key] = open or nil
				saveG()
				look()
				chev.Rotation = open and 0 or 90 -- (from where it was: the arrow turns over)
				App.tween(chev, App.MED, { Rotation = open and 90 or 0 })
				if open then -- the folded cards arrive one after another
					local k = 0
					for _, c in foldBody:GetChildren() do
						if c:IsA("GuiObject") and c:GetAttribute("SS_Card") and k < 8 then
							local sc = App.new("UIScale", { Scale = 0.97, Parent = c })
							task.delay(k * 0.04, function()
								App.tween(sc, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
							end)
							k += 1
						end
					end
				end
			end)
			return foldBody
		end
		local nMore = 0
		function cs.add(spec)
			if App.searching() and not matches(spec) then
				return nil
			end
			if spec.more then
				local into = moreBody()
				nMore += 1
				if foldCount then
					foldCount.Text = string.format("More options  ·  %d", nMore)
				end
				return card(into, spec, id)
			end
			return card(parent, spec, id)
		end
		return cs
	end

	-- opens a property tab (by id: Panel/Properties) at one of its cards (by id), unfolding "More options" if it's in
	-- there (fold: the tab's cards id), scrolls to it and lights its edge for a moment. Returns false when the card
	-- isn't there (not for what's selected).
	App.openCard = function(tab, id, fold)
		if fold then
			G.groups["more:" .. fold] = true
			saveG()
		end
		for k in G.groups do -- (a section folded away is unfolded: it's being asked for)
			if string.sub(k, 1, 5) == "fold:" and string.sub(k, -#id - 1) == ":" .. id then
				G.groups[k] = nil
			end
		end
		if tab == "settings" then
			App.openSettings(true)
		else
			App.openTab(tab)
		end
		for _, d in App.root:GetDescendants() do
			if d:GetAttribute("SS_Card") == id then
				App.scrollIntoView(d)
				local edge = d:FindFirstChildOfClass("UIStroke")
				if edge then
					edge.Transparency = 0
					task.delay(0.9, function()
						App.tween(edge, App.MED, { Transparency = 1 })
					end)
				end
				return true
			end
		end
		return false
	end

	-- a note, with a button that opens another property tab when given (by its id)
	App.goNote = function(parent, text, buttonText, tab)
		local wrap = col({ Parent = parent }, { vlist(8) })
		App.hintBox(wrap, text)
		if buttonText then
			App.button(buttonText, "accent", function()
				App.openTab(tab)
			end, { Parent = App.buttonRow(wrap) })
		end
		return wrap
	end
end
