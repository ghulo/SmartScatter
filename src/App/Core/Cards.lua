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
		layerpaint = "Brush more or less of it by hand",
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

	-- one feature's card: a title, a line under it, and its controls. spec: { id, title, sub?, icon?, tag?, keys?, build }
	local function card(parent, spec, order)
		App.cardCount += 1
		local c = col({ BackgroundTransparency = 0, BackgroundColor3 = P.card, LayoutOrder = order, Parent = parent }, {
			corner(12),
			stroke(P.line),
			pad(14, 14, 12, 14),
			vlist(8),
		})
		App.shade(c, 0.05)
		App.topLight(c, 0.06, 12)
		local head = col({ Parent = c })
		local x = 0
		if spec.icon then
			local badge = box({
				BackgroundTransparency = 0,
				BackgroundColor3 = P.accent:Lerp(P.card, 0.86),
				Size = UDim2.fromOffset(28, 28),
				Parent = head,
			}, { corner(7) })
			local ic = icon(spec.icon, 14, P.accent)
			ic.AnchorPoint, ic.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
			ic.Parent = badge
			x = 38
		end
		local txt = col({ Position = UDim2.fromOffset(x, 0), Size = UDim2.new(1, -x, 0, 0), Parent = head }, { vlist(1) })
		local titleRow = box({ Size = UDim2.new(1, 0, 0, 18), Parent = txt }, { hlist(8) })
		label(spec.title, 14, P.text, SANS_B, { Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, Parent = titleRow })
		if spec.tag then -- a small pill after the title ("Optional")
			local tag = label(spec.tag, 10, P.dim, SANS_B, {
				Size = UDim2.fromOffset(0, 18),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundTransparency = 0,
				BackgroundColor3 = P.raised,
				Parent = titleRow,
			})
			corner(9).Parent = tag
			pad(7, 7, 0, 0).Parent = tag
		end
		local sub = spec.sub or SUB[spec.id]
		if sub and sub ~= "" then
			local s = App.para(sub, { Parent = txt })
			s.TextColor3 = P.dim
		end
		local body = col({ Parent = c }, { vlist(6) })
		spec.build(body, c)
		return c
	end

	-- a tab's column of cards. id names its "More options" fold (its open state is remembered).
	-- cards.add(spec): spec.more puts the card under the fold. Returns the card, or nil when the search skips it.
	App.cards = function(parent, id)
		local cs = {}
		local order = 0
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
			fold = col({ LayoutOrder = 100000, Parent = parent }, { vlist(10) })
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
				order += 1
				return card(into, spec, order)
			end
			order += 1
			return card(parent, spec, order)
		end
		return cs
	end

	-- a note, with a button that goes to another tab when given ("Paint an area first" → Brush)
	App.goNote = function(parent, text, buttonText, tab)
		local wrap = col({ Parent = parent }, { vlist(8) })
		App.hintBox(wrap, text)
		if buttonText then
			App.button(buttonText, "accent", function()
				App.goPage(tab)
			end, { Parent = App.buttonRow(wrap) })
		end
		return wrap
	end
end
