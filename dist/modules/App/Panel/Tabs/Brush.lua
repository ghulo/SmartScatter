--[[
	Smart Scatter — Brush tab: working by hand in the viewport. Paint the area's ground, brush one object more or
	less (or place copies exactly), take single copies out; then which surfaces painting sticks to and cleaning up
	the painted edge under More options.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local Engine, P, SANS = App.Engine, App.P, App.SANS
	local label, chip, chipGrid, hintOn = App.label, App.chip, App.chipGrid, App.hintOn

	-- the object the "Paint one object" card works on (this session only; the first one that can be painted)
	local picked
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
		if not table.find(list, picked) then
			picked = App.paintLayer and table.find(list, App.paintLayer) and App.paintLayer or list[1]
		end
		label("Object", 13, P.text, SANS, { Parent = b })
		local grid = chipGrid(b, 3, 30)
		for i, l in list do
			local c = chip(grid, l.inst.Name, function()
				return picked == l
			end, function()
				if picked ~= l then
					if App.LAYER_MODES[App.mode] then -- the brush moves over to the new pick
						App.setMode(App.mode, l)
					end
					picked = l
					App.rebuildAll()
				end
			end)
			c.LayoutOrder = i
			hintOn(c, "Brush " .. l.inst.Name .. ".")
		end
		App.buildLayerPaint(picked, { -- its controls straight into this card
			add = function(spec)
				spec.build(b)
			end,
		})
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
				keys = "paint ground brush lasso box polygon fill erase size shape reach selected parts",
				build = App.buildPaintTools,
			})
			App.ui.step1Card = card
		end
		if a and kind ~= "Clear" then
			if kind ~= "Path" then
				cs.add({
					id = "objectbrush",
					title = "Paint one object",
					sub = "More, less or none of it where you brush; or place copies exactly",
					keys = "more less clear place pins object brush by hand",
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
					keys = "fill holes smooth grow shrink erase all paint cleanup",
					more = true,
					build = App.buildTidy,
				})
			end
		end
	end
end
