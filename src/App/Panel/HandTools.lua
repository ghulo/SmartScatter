--[[
	Smart Scatter — HandTools: one object, by hand. One row of tool tiles, like the ground's paint tools: Spray (copies
	where you brush) and the four that change how much of it grows where (More, Less, Erase, Reset). Under them, only
	the picked tool's own lines: how to use it, the brush size, its keys and (for the painting ones) the overlay's
	colours. Then what was done by hand, and taking it back. (Stamping one copy is the Stamp card's.)
	Used by the Brush tab's "One object by hand" card (App.buildHandTools).
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local G, saveG, P = App.G, App.saveG, App.P
	local col, para, vlist = App.col, App.para, App.vlist
	local slider, button, buttonRow, hintOn = App.slider, App.button, App.buttonRow, App.hintOn
	local key = App.keyText

	-- the tools, in the order the tiles show them (mode: App.mode while it's in use)
	local TOOLS = {
		{ mode = "Place", icon = "spray", text = "Spray" },
		{ mode = "More", icon = "plus", text = "More" },
		{ mode = "Less", icon = "minus", text = "Less" },
		{ mode = "None", icon = "trash", text = "Erase", danger = true },
		{ mode = "Clear", icon = "refresh", text = "Reset" },
	}
	-- how to use each one, said under the tiles while it's picked (and on its tile when hovered)
	local HOW = {
		Place = "Drag over the ground: copies land where you brush, at the object's spacing, and stay put when the area rebuilds.",
		More = "Brush where you want it thicker, up to three times as much.",
		Less = "Brush where you want it thinner. Twice over clears it.",
		None = "Brush where you want none of it, copies put down by hand too. It stays gone when the area rebuilds.",
		Clear = "Brush over More, Less and Erase to take them back: it grows there by its rules alone again.",
	}
	-- what Shift does while each is in use
	local SHIFT = { Place = "take away", More = "less", Less = "more", None = "reset", Clear = "erase" }

	-- the picked tool's lines: how it works, the brush size, its keys, the overlay's colours
	local function toolPanel(l, parent)
		local m = App.paintLayer == l and HOW[App.mode] and App.mode or nil
		if not m then
			local hint = para("Pick a tool, then brush in the viewport. Esc stops.", { Parent = parent })
			hint.TextColor3 = P.faint
			return
		end
		local how = para(HOW[m], { Parent = parent })
		how.TextColor3 = P.dim
		slider("Brush size", 4, 200, function()
			return G.radius
		end, function(v)
			G.radius = v
		end, "%.0f studs", 1, nil, saveG, "Radius of the brush. While brushing, " .. key("size") .. " sizes it with the mouse.", 24).Parent =
			parent
		App.keyChips(parent, { { "Shift", SHIFT[m] }, { key("size"), "size" }, { key("cancel"), "stop" } })
		if m ~= "Place" then -- (the overlay shows how much grows where, in these colours)
			App.overlayLegendRows(parent, "object")
		end
	end

	-- what's been done to it by hand, and taking it all back (only when there's something)
	local function handWork(l, parent)
		if not (l.paint or l.pins) then
			return
		end
		App.fadeLine(parent, nil, 0.14)
		local row = buttonRow(parent)
		if l.paint then
			hintOn(
				button("Reset all painting", nil, function()
					l.paint = nil
					if App.paintLayer == l then
						App.recolorOverlay()
					end
					App.applyNow(l, "Reset painting")
					App.refreshObjects()
				end, { Parent = row }),
				"Forgets every More, Less and Erase for this object: it grows by its rules alone again."
			)
		end
		if l.pins then
			local rm = App.dangerButton(string.format("Remove %d put down by hand", #l.pins), function()
				l.pins = nil
				App.applyNow(l, "Remove hand-placed")
				App.refreshObjects()
			end, { confirm = "Click again to remove" })
			rm.Parent = row
			hintOn(rm, "Takes out every copy of it you put down with Spray. Ctrl+Z brings them back.")
		end
	end

	-- the tools for object l, built into parent
	App.buildHandTools = function(l, parent)
		local tiles = App.toolTiles(parent, 3, 36, 88)
		for _, t in TOOLS do
			tiles.add({
				icon = t.icon,
				text = t.text,
				color = t.danger and P.danger or nil,
				tinted = t.danger,
				hint = t.text .. ": " .. HOW[t.mode],
				on = function()
					return App.paintLayer == l and App.mode == t.mode
				end,
				click = function()
					App.setMode(t.mode, l)
				end,
			})
		end
		local panel = col({ Parent = parent }, { vlist(6) })
		local function buildPanel()
			for _, c in panel:GetChildren() do
				if c:IsA("GuiObject") then
					c:Destroy()
				end
			end
			toolPanel(l, panel)
		end
		buildPanel()
		App.ui.refreshLayerBrush = function()
			tiles.refresh()
			if panel.Parent then
				buildPanel()
			end
		end
		handWork(l, parent)
	end
end
