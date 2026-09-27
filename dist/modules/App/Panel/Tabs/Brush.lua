--[[
	Smart Scatter — Brush tab: working by hand in the viewport. Paint the area's ground, work one object by hand
	(stamp or spray copies, paint where it grows more or less: Panel/HandTools), take single copies out; then which surfaces painting sticks to and cleaning up
	the painted edge under More options.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local Engine, P, SANS = App.Engine, App.P, App.SANS
	local label, hintOn = App.label, App.hintOn

	-- the object the "One object by hand" card works on (this session only; the first one that can be painted)
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
		-- the objects as rows: a small view of the model, its name, how many are placed; the picked one lit
		for _, l in list do
			local on = picked == l
			local row = App.new("TextButton", {
				Text = "",
				AutoButtonColor = false,
				BackgroundColor3 = on and P.accentSoft or P.raised,
				Size = UDim2.new(1, 0, 0, 48),
				Parent = b,
			}, { App.corner(10) })
			local st = App.stroke(on and P.accentLine or P.line)
			st.Parent = row
			local th = App.thumbnail(l.inst, 38)
			th.Position = UDim2.fromOffset(5, 5)
			th.Parent = row
			label(l.inst.Name .. (#l.variants > 1 and ("  +" .. (#l.variants - 1)) or ""), 13, on and P.accent or P.text, App.SANS_B, {
				Position = UDim2.fromOffset(52, 7),
				Size = UDim2.new(1, -60, 0, 18),
				Parent = row,
			})
			local n = App.lastCounts[l]
			local bits = { n and (App.num(n) .. " placed") or l.type }
			if l.pins then
				table.insert(bits, #l.pins .. " by hand")
			end
			if l.paint then
				table.insert(bits, "painted")
			end
			label(table.concat(bits, " · "), 11, P.dim, SANS, { Position = UDim2.fromOffset(52, 25), Size = UDim2.new(1, -60, 0, 16), Parent = row })
			if not on then
				row.MouseEnter:Connect(function()
					row.BackgroundColor3 = P.hover
				end)
				row.MouseLeave:Connect(function()
					row.BackgroundColor3 = P.raised
				end)
			end
			App.pressable(row, 0.985)
			row.MouseButton1Click:Connect(function()
				if picked ~= l then
					if App.LAYER_MODES[App.mode] then -- the brush moves over to the new pick
						App.setMode(App.mode, l)
					end
					picked = l
					App.rebuildAll()
				end
			end)
			hintOn(row, "Brush " .. l.inst.Name .. ".")
		end
		App.buildLayerPaint(picked, { -- its tools straight into this card, under the pick
			add = function(spec)
				App.fadeLine(b, nil, 0.14)
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
				keys = "paint ground brush lasso box polygon fill erase all delete size shape reach selected parts",
				build = App.buildPaintTools,
			})
			App.ui.step1Card = card
		end
		if a and kind ~= "Clear" then
			if kind ~= "Path" then
				cs.add({
					id = "objectbrush",
					title = "One object by hand",
					sub = "Stamp or spray copies of it, or paint where it grows more or less",
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
