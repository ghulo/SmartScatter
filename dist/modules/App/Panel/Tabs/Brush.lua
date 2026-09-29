--[[
	Smart Scatter — Brush tab: working by hand in the viewport. Paint the area's ground, work one object by hand
	(stamp or spray copies, paint where it grows more or less: Panel/HandTools), take single copies out; then which surfaces painting sticks to and cleaning up
	the painted edge under More options.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local Engine, P, SANS = App.Engine, App.P, App.SANS
	local label, hintOn = App.label, App.hintOn

	-- the "One object by hand" card: which object (App.handLayer: the one picked here, or sent here by an object's
	-- "Brush by hand"; the viewport's tool strip sprays it too), then its tools (Panel/HandTools)
	local function paintable(l)
		return not (Engine.isLine(l) and l.s.follow == "Spline")
	end
	local function buildObjectBrush(b)
		local list = {}
		for _, l in App.area.layers do
			if paintable(l) then
				table.insert(list, l)
			end
		end
		if #list == 0 then
			App.goNote(
				b,
				#App.area.layers == 0 and "Add objects on the Scatter tab first." or "Objects along a path can't be brushed.",
				#App.area.layers == 0 and "Add objects" or nil,
				"Scatter"
			)
			return
		end
		if not table.find(list, App.handLayer) then
			App.handLayer = App.paintLayer and table.find(list, App.paintLayer) and App.paintLayer or list[1]
		end
		local picked = App.handLayer
		-- the objects as chips, like the Stamp card's; the picked one lit
		if #list > 1 then
			local grid = App.chipGrid(b, 3, 28, 96)
			for _, l in list do
				hintOn(
					App.chip(grid, l.inst.Name, function()
						return App.handLayer == l
					end, function()
						if App.handLayer ~= l then
							if App.LAYER_MODES[App.mode] then -- the brush moves over to the new pick
								App.setMode(App.mode, l)
							end
							App.handLayer = l
							App.rebuildAll()
						end
					end),
					"Brush " .. l.inst.Name .. "."
				)
			end
		end
		-- what's been done to it by hand so far, in one quiet line
		local n = App.lastCounts[picked]
		local bits = { picked.inst.Name, n and (App.num(n) .. " placed") or picked.type }
		if picked.pins then
			table.insert(bits, #picked.pins .. " by hand")
		end
		if picked.paint then
			table.insert(bits, "painted")
		end
		label(table.concat(bits, "  ·  "), 12, P.dim, SANS, { Size = UDim2.new(1, 0, 0, 18), Parent = b })
		App.buildHandTools(picked, b)
	end

	App.buildBrushTab = function(page)
		local a = App.area
		local cs = App.cards(page, "brush")
		local kind = a and App.kindOf(a)
		if kind == "Path" then
			cs.add({
				id = "pathbrush",
				title = "Draw the path",
				icon = "spline",
				sub = "Paths are drawn, not painted",
				keys = "draw path spline points",
				build = function(b)
					App.goNote(b, "Draw and shape the path on the Map tab.", "Go to Map", "Map")
				end,
			})
		else
			local painted = a and (a.count or 0) > 0
			local card = cs.add({
				id = "paint",
				title = kind == "Clear" and "Paint the zone" or "Paint the area",
				icon = kind == "Clear" and "clear" or "brush",
				sub = kind == "Clear" and "Where nothing from any area may go"
					or painted and string.format("%s studs² painted. Keep painting, or tune what fills it.", App.num(a.count * a.cell * a.cell))
					or "Pick a tool, then paint the ground in the viewport",
				keys = "paint ground brush lasso box polygon fill erase all delete size shape reach selected parts",
				build = App.buildPaintTools,
			})
			App.ui.step1Card = card
		end
		cs.add({
			id = "stamp",
			title = "Stamp",
			icon = "stamp",
			sub = "One model, exactly where you click: no area needed",
			keys = "stamp single one copy model place put rotate turn size anywhere",
			build = App.buildStampCard,
		})
		if a and kind ~= "Clear" then
			if kind ~= "Path" then
				cs.add({
					id = "objectbrush",
					title = "One object by hand",
					sub = "Spray copies of it, or brush where it grows more or less",
					keys = "more less erase reset place spray stamp pins object brush by hand single copy",
					build = buildObjectBrush,
				})
			end
			cs.add({
				id = "removecopies",
				title = "Remove single copies",
				sub = "Click a copy that looks wrong to take it out; it stays out",
				keys = "remove delete copy copies bring back",
				build = App.removeCopiesBox,
			})
		end
		if kind ~= "Path" then
			cs.add({
				id = "paintfilter",
				title = "Paint only on",
				sub = "Painting and erasing stick to these surfaces",
				keys = "filter surfaces grass road rock sand snow",
				more = true,
				build = App.buildPaintFilter,
			})
			if a then
				cs.add({
					id = "tidy",
					title = "Tidy the edge",
					sub = "Fill holes, smooth, grow or shrink what's painted",
					keys = "fill holes smooth grow shrink cleanup",
					more = true,
					build = App.buildTidy,
				})
			end
		end
	end
end
