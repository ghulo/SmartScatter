--[[
	Smart Scatter — HandTools: one object, by hand. Its tools come in two groups, each a tile that says what it does
	without hovering: putting copies down (Stamp: one, aimed; Spray: many, where you brush) and changing how much of it
	grows where (More, Less, Erase, Reset). Under the tiles, the picked tool's own panel: how to use it, its settings
	and its keys, and nothing of the tools not in use. Then what was done by hand, and undoing it all.
	Used by the object's page and by the Brush tab's "One object by hand" card (App.buildLayerPaint).
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local G, saveG, P, SANS, SANS_B = App.G, App.saveG, App.P, App.SANS, App.SANS_B
	local box, col, label, para, vlist, corner, stroke, pad = App.box, App.col, App.label, App.para, App.vlist, App.corner, App.stroke, App.pad
	local slider, switchRow, button, buttonRow, hintOn, chip, chipGrid =
		App.slider, App.switchRow, App.button, App.buttonRow, App.hintOn, App.chip, App.chipGrid
	local key = App.keyText

	-- the tools, in their groups (mode: App.mode while it's in use)
	local GROUPS = {
		{
			title = "Put copies down",
			{ mode = "Stamp", icon = "stamp", text = "Stamp", sub = "One copy, aimed" },
			{ mode = "Place", icon = "spray", text = "Spray", sub = "Copies where you brush" },
		},
		{
			title = "Change how much grows",
			{ mode = "More", icon = "plus", text = "More", sub = "Thicker here" },
			{ mode = "Less", icon = "minus", text = "Less", sub = "Thinner here" },
			{ mode = "None", icon = "trash", text = "Erase", sub = "None of it here", danger = true },
			{ mode = "Clear", icon = "refresh", text = "Reset", sub = "Back to its rules" },
		},
	}
	local TOOL = {}
	for _, g in GROUPS do
		for _, t in ipairs(g) do
			TOOL[t.mode] = t
		end
	end
	-- how to use each one, said in the panel while it's picked (and on its tile when hovered)
	local HOW = {
		Stamp = "Click the ground to put one of its models down, exactly as it shows under the mouse, anywhere: stamps are plain models in Workspace › Stamps. Press and drag to turn it.",
		Place = "Drag over the ground: copies land where you brush, at the object's spacing, and stay put when the area rebuilds.",
		More = "Brush where you want it thicker, up to three times as much.",
		Less = "Brush where you want it thinner. Twice over clears it.",
		None = "Brush where you want none of it, copies put down by hand too. It stays gone when the area rebuilds.",
		Clear = "Brush over More, Less and Erase to take them back: it grows there by its rules alone again.",
	}
	-- what Shift does while each is in use
	local SHIFT = { Stamp = "turn freely", Place = "take away", More = "less", Less = "more", None = "reset", Clear = "erase" }

	local function brushSize(parent)
		slider("Brush size", 4, 200, function()
			return G.radius
		end, function(v)
			G.radius = v
		end, "%.0f studs", 1, nil, saveG, "Radius of the brush. While brushing, " .. key("size") .. " sizes it with the mouse.", 24).Parent =
			parent
	end

	-- the picked tool's panel: its name, how it works, its settings, its keys
	local function toolPanel(l, parent, rebuild)
		local stamping = App.mode == "Stamp" and App.stamp.from == l -- (the stamp is its own tool, started from here)
		local m = stamping and "Stamp" or (App.paintLayer == l and App.mode or nil)
		local t = m and TOOL[m]
		if not t then
			local hint = para("Pick a tool, then work in the viewport. Esc stops.", { Parent = parent })
			hint.TextColor3 = P.faint
			return
		end
		local color = t.danger and P.danger or P.accent
		local card = col(
			{ BackgroundTransparency = 0, BackgroundColor3 = color:Lerp(P.card, 0.9), Parent = parent },
			{ corner(10), stroke(color:Lerp(P.card, 0.55)), pad(12, 12, 10, 12), vlist(6) }
		)
		local head = box({ Size = UDim2.new(1, 0, 0, 18), Parent = card }, {
			App.new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 7),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		local ic = App.icon(t.icon, 15, color)
		ic.LayoutOrder = 0
		ic.Parent = head
		label(t.text .. "  ·  " .. l.inst.Name, 13, color, SANS_B, {
			Size = UDim2.fromOffset(0, 18),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = 1,
			Parent = head,
		})
		local how = para(HOW[m], { Parent = card })
		how.TextColor3 = P.text
		if m == "Stamp" then
			App.stampControls(card, rebuild)
		else
			brushSize(card)
			App.keyChips(card, { { "Shift", SHIFT[m] }, { key("size"), "size" }, { key("cancel"), "stop" } })
			if m ~= "Place" then -- (the overlay shows how much grows where, in these colours)
				App.overlayLegendRows(card, "object")
			end
		end
	end

	-- what's been done to it by hand, and taking it all back (only when there's something)
	local function handWork(l, parent)
		if not (l.paint or l.pins) then
			return
		end
		App.fadeLine(parent, nil, 0.14)
		if l.paint then
			hintOn(
				button("Reset all painting", nil, function()
					l.paint = nil
					if App.paintLayer == l then
						App.recolorOverlay()
					end
					App.commit(l)
					App.refreshObjects()
				end, { Parent = buttonRow(parent) }),
				"Forgets every More, Less and Erase for this object: it grows by its rules alone again."
			)
		end
		if l.pins then
			local rm = App.dangerButton(string.format("Remove all %d put down by hand", #l.pins), function()
				l.pins = nil
				App.commit(l)
				App.refreshObjects()
			end, { confirm = "Click again to remove", full = true })
			rm.Parent = parent
			hintOn(rm, "Takes out every copy of it you put down with Stamp or Spray. Ctrl+Z brings them back.")
		end
	end

	App.buildLayerPaint = function(l, parent, more)
		parent.add({
			id = "layerpaint",
			title = "By hand",
			sub = "Stamp or spray copies, or paint where it grows",
			keys = "brush more less erase reset place spray pins stamp single one copy add rotate turn size by hand",
			more = more,
			build = function(b)
				local groups = {}
				for _, g in GROUPS do
					label(g.title, 12, P.dim, SANS_B, { Size = UDim2.new(1, 0, 0, 18), Parent = b })
					local tiles = App.toolTiles(b, 2, 52, 120)
					for _, t in ipairs(g) do
						tiles.add({
							icon = t.icon,
							text = t.text,
							sub = t.sub,
							color = t.danger and P.danger or nil,
							tinted = t.danger,
							hint = HOW[t.mode],
							on = function()
								if t.mode == "Stamp" then
									return App.mode == "Stamp" and App.stamp.from == l
								end
								return App.paintLayer == l and App.mode == t.mode
							end,
							click = function()
								if t.mode ~= "Stamp" then
									App.setMode(t.mode, l)
								elseif App.mode == "Stamp" and App.stamp.from == l then
									App.setMode("Off")
								else
									App.startStamp(l) -- (its models, stamped anywhere: the stamp is no area's)
								end
							end,
						})
					end
					table.insert(groups, tiles)
				end
				local panel = col({ Parent = b }, { vlist(6) })
				local function buildPanel()
					for _, c in panel:GetChildren() do
						if c:IsA("GuiObject") then
							c:Destroy()
						end
					end
					toolPanel(l, panel, buildPanel)
				end
				buildPanel()
				App.stampViews.hand = function()
					if panel.Parent then
						buildPanel()
					end
				end
				App.ui.refreshLayerBrush = function()
					for _, tiles in groups do
						tiles.refresh()
					end
					buildPanel()
				end
				handWork(l, b)
			end,
		})
	end
end
