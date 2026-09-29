--[[
	Smart Scatter — HandTools: one object, by hand, as its Object tab shows it. The tools themselves (Spray, More,
	Less, Erase, Reset) are in the viewport's strip and act on the active object; here: what they do, what was done
	to this object by hand, and taking it back.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local P = App.P
	local para, button, buttonRow, hintOn = App.para, App.button, App.buttonRow, App.hintOn

	-- the one-object tools, as the strip shows them (mode: App.mode while one's in use; how: its tip and hint line)
	App.HAND_TOOLS = {
		{
			mode = "Place",
			icon = "spray",
			text = "Spray",
			how = "Drag over the ground: copies land where you brush, at the object's spacing, and stay put when the area rebuilds.",
		},
		{ mode = "More", icon = "plus", text = "More", how = "Brush where you want it thicker, up to three times as much." },
		{ mode = "Less", icon = "minus", text = "Less", how = "Brush where you want it thinner. Twice over clears it." },
		{
			mode = "None",
			icon = "trash",
			text = "Erase",
			danger = true,
			how = "Brush where you want none of it, copies put down by hand too. It stays gone when the area rebuilds.",
		},
		{
			mode = "Clear",
			icon = "refresh",
			text = "Reset",
			how = "Brush over More, Less and Erase to take them back: it grows there by its rules alone again.",
		},
	}

	-- the tools in the viewport's strip, acting on the active object (or the selected zone's first one)
	for i, t in App.HAND_TOOLS do
		App.registerTool({
			id = "object:" .. t.mode,
			group = "Object",
			order = i,
			icon = t.icon,
			name = t.text .. ": " .. t.how,
			danger = t.danger,
			when = function()
				return App.brushTarget() ~= nil
			end,
			on = function()
				return App.mode == t.mode and App.paintLayer == App.brushTarget()
			end,
			click = function()
				App.setMode(t.mode, App.brushTarget())
			end,
		})
	end

	-- the By hand card of object l
	App.buildHandWork = function(l, parent)
		local what = {}
		if l.pins then
			table.insert(what, #l.pins .. " put down by hand")
		end
		if l.paint then
			table.insert(what, "painted more or less in places")
		end
		local line = para(
			#what > 0 and (table.concat(what, " · ") .. ".")
				or "Nothing done by hand yet. Pick Spray, More, Less, Erase or Reset in the viewport's strip: they act on this object.",
			{ Parent = parent }
		)
		line.TextColor3 = #what > 0 and P.text or P.faint
		if not (l.paint or l.pins) then
			return
		end
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
end
