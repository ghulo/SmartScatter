--[[
	Smart Scatter — ObjectsPage: the Objects page. The area's objects (each one model or a mix of models, with its
	rules) with adding, presets and objects whose model went missing; or one object's settings on a page of its own.
	Part of Main; loaded in order by the bundle. Shared state and cross-module functions live on App.
]]

return function(App)
	local Selection, FAST, tween, Engine, G, saveG, num = App.Selection, App.FAST, App.tween, App.Engine, App.G, App.saveG, App.num
	local P, SANS, SANS_M, SANS_B, new, corner, stroke = App.P, App.SANS, App.SANS_M, App.SANS_B, App.new, App.corner, App.stroke
	local pad, vlist, hlist, box, col, label, para = App.pad, App.vlist, App.hlist, App.box, App.col, App.label, App.para
	local hintOn, slider, switch, switchRow, segmented, section = App.hintOn, App.slider, App.switch, App.switchRow, App.segmented, App.section
	local recolorOverlay, rebuildOverlay, canGenerate, requestLive, commit =
		App.recolorOverlay, App.rebuildOverlay, App.canGenerate, App.requestLive, App.commit
	local newArea, eachThumb, thumbnail = App.newArea, App.eachThumb, App.thumbnail
	local beginRec, endRec, button, buttonRow, explain = App.beginRec, App.endRec, App.button, App.buttonRow, App.explain
	local chip, chipGrid, stepLabel, NICE = App.chip, App.chipGrid, App.stepLabel, App.NICE

	local rowRefs = {} -- [layer] = { name, kind (list row), sub (settings page) }: labels refreshCounts keeps current

	local function gap(parent, h)
		box({ Size = UDim2.new(1, 0, 0, h), Parent = parent })
	end
	-- the page shows something else now (an object opened or closed): rebuild it, and stop a brush that belonged there
	local function showObject(l)
		if App.LAYER_MODES[App.mode] then
			App.setMode("Off")
		end
		App.expanded = l
		if App.heatLayer and App.heatLayer ~= l then -- the heatmap belongs to the object whose page it was
			App.heatLayer = nil
			rebuildOverlay()
		end
		App.rebuildAll()
	end
	-- a model with its thumbnail and, on the right, its buttons: actions = { { text, style, onClick }, ... }
	local function modelRow(parent, inst, text, actions)
		local row = box({ Size = UDim2.new(1, 0, 0, 32), Parent = parent })
		local th = thumbnail(inst, 28)
		th.Position = UDim2.fromOffset(0, 2)
		th.Parent = row
		label(text, 13, P.text, SANS_M, { Position = UDim2.fromOffset(36, 0), Size = UDim2.new(1, -170, 1, 0), Parent = row })
		local right = box({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 1),
			Size = UDim2.fromOffset(0, 30),
			AutomaticSize = Enum.AutomaticSize.X,
			Parent = row,
		}, {
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 6),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		for i, a in actions or {} do
			button(a[1], a[2], a[3], { LayoutOrder = i, Parent = right })
		end
		return row
	end

	--------------------------------------------------------------------------------
	-- One object's rules, a section each
	--------------------------------------------------------------------------------
	-- the controls a section needs, bound to one object
	local function controls(l)
		local s, D = l.s, Engine.defaults(l.type)
		local c = {}
		local function reheat() -- the heatmap follows the rules as they change
			if App.heatLayer == l then
				recolorOverlay()
			end
		end
		function c.live()
			requestLive(l)
			reheat()
		end
		function c.done()
			commit(l)
			reheat()
		end
		function c.changed(rebuild) -- a change the page must be redrawn for (other controls appear or go)
			c.live()
			c.done()
			if rebuild then
				App.refreshObjects()
			end
		end
		function c.S(parent, key, text, min, max, fmt, step, hint) -- a slider for s[key], right-click resets it
			slider(text, min, max, function()
				return s[key]
			end, function(v)
				s[key] = v
			end, fmt, step, c.live, c.done, hint, D[key]).Parent =
				parent
		end
		function c.SW(parent, key, text, hint, rebuild) -- an on/off switch for s[key]
			switchRow(text, function()
				return s[key]
			end, function(v)
				s[key] = v
			end, function()
				c.changed(rebuild)
			end, hint).Parent =
				parent
		end
		function c.PICK(parent, title, key, options, hint, rebuild) -- a labelled choice for s[key]
			stepLabel(parent, nil, title)
			segmented(options, function()
				return s[key]
			end, function(v)
				s[key] = v
			end, function()
				c.changed(rebuild)
			end).Parent =
				parent
			if hint then
				explain(parent, hint)
			end
		end
		return c
	end

	local function buildBasics(l, parent, c)
		local s = l.s
		local line = Engine.isLine(l)
		stepLabel(parent, nil, "Placement")
		segmented(Engine.PLACES, function()
			return s.place
		end, function(v)
			if v == "Along" and s.place ~= "Along" then
				-- becoming a line: tiles, panels and walls resize to meet, lamps keep a gap; a drawn path is followed
				local sp = App.area and App.area.spline
				Engine.smartLine(l, sp ~= nil and #sp.pts >= 2)
			else
				s.place = v
			end
		end, function()
			commit()
			App.refreshObjects()
		end).Parent =
			parent
		explain(
			parent,
			line and "Along: copies follow a line (a road edge, the area's border or a path), like lamps or a fence."
				or "Scatter: copies spread over the painted area, following the rules below."
		)
		gap(parent, 6)
		if not line then
			c.S(parent, "density", "Amount", 0, 4, "%.2f×", 0.05, "How much of this object to place. 1× is the smart default for its type.")
			gap(parent, 4)
		end
		stepLabel(parent, nil, "Type")
		segmented(Engine.TYPES, function()
			return l.type
		end, function(t)
			Engine.setType(l, t)
		end, function()
			commit()
			App.refreshObjects()
		end).Parent =
			parent
		explain(parent, "What it is. Sets sensible defaults for spacing, slopes and what it keeps away from.")
		gap(parent, 6)
		c.SW(
			parent,
			"locked",
			"Lock placement",
			"Keeps every copy of this object exactly where it is when the area regenerates. Changes still save; unlock to see them."
		)
	end

	local function buildLine(l, parent, c)
		local s = l.s
		section(parent, "line", "Line", true, function(b)
			local follows = table.clone(Engine.FOLLOWS)
			if (App.area and App.area.spline and #App.area.spline.pts > 0) or s.follow == "Spline" then
				table.insert(follows, "Spline")
			end
			c.PICK(
				b,
				"Follow",
				"follow",
				follows,
				s.follow == "Spline" and "Follows this area's path."
					or s.follow == "Border" and "Runs around the edge of the painted area, e.g. a fence around a field."
					or ("Runs along " .. string.lower(s.follow) .. " inside the painted area (found by the scan)."),
				true
			)
			local onSpline = s.follow == "Spline"
			if onSpline then
				gap(b, 4)
				c.PICK(
					b,
					"Side",
					"side",
					Engine.SIDES,
					"Center puts copies on the curve itself, turned toward the nearest road; the others set them beside it, e.g. lamps along both sides of a road.",
					true
				)
				gap(b, 4)
				c.PICK(
					b,
					"Orientation",
					"orient",
					Engine.ORIENTS,
					"Upright stands straight (lamps, posts). Surface sticks to what's under it (moss on walls, lights on a ceiling). Follow bends with the curve up and down (bridge planks, rails, pipes)."
				)
				c.S(b, "roll", "Roll", 0, 360, "%.0f°", 5, "Turns each copy around the direction of the curve.")
			end
			gap(b, 4)
			if not onSpline then
				c.S(b, "offset", "Distance from it", 0, 40, "%.0f studs", 0.5, "Gap between the edge you follow and the side of each copy.")
			elseif s.side ~= "Center" then
				c.S(b, "offset", "Distance from the curve", 0, 60, "%.0f studs", 0.5, "How far to the side of the path each copy sits.")
			end
			c.SW(
				b,
				"fit",
				"Line up end to end",
				"Resizes each piece so they meet with no gaps or overlaps, even on bends: fences, walls, path tiles, rails.",
				true
			)
			if not s.fit and Engine.looksLikeSegment(l) then
				-- a tile or panel spaced out by a fixed gap leaves gaps on straights and overlaps on bends
				local row = col({ Parent = b }, { vlist(4) })
				label("Pieces don't meet. Resize them to fit?", 12, P.dim, SANS, { Parent = row })
				button("Resize pieces to fit", "accent", function()
					s.fit = true
					c.changed(true)
				end, { Parent = buttonRow(row) })
			end
			if s.fit then -- an optional post model at every joint and both ends
				if l.post then
					modelRow(b, l.post.inst, "Post: " .. l.post.inst.Name, {
						{
							"Remove",
							"danger",
							function()
								Engine.setPost(l, nil)
								c.changed(true)
							end,
						},
					})
				else
					hintOn(
						button("Add selected as post", nil, function()
							local sel = Selection:Get()[1]
							if not sel or sel == l.inst or not Engine.setPost(l, sel) then
								App.status("Select a post or pillar model in the Explorer first.")
								return
							end
							App.status("Posts go at every joint and both ends.")
							c.changed(true)
						end, { Parent = buttonRow(b) }),
						"Optional: a separate post model placed at every joint and at both ends. Without one, a fence whose model has a post on one end only gets matching end posts automatically."
					)
				end
			else
				c.S(b, "interval", "Gap between", 2, 150, "%.0f studs", 1, "Distance from one copy to the next along the line.")
				c.S(b, "jitter", "Unevenness", 0, 1, "%.0f%%", 0.05, "0% is perfectly even. Higher shifts copies back and forth along the line.")
				if not onSpline or s.side == "Both" then
					c.SW(b, "stagger", "Stagger the two sides", "Copies on opposite sides sit between each other instead of facing pairs.")
				end
			end
			c.S(
				b,
				"skip",
				"Leave gaps",
				0,
				0.9,
				"%.0f%%",
				0.05,
				"How much is left out, in real openings: stretches of fence with gaps between them, never a lone piece. Posts only stand where there's fence."
			)
			if not s.fit then -- end-to-end pieces always run along the line
				gap(b, 4)
				c.PICK(
					b,
					"Facing",
					"facing",
					Engine.FACINGS,
					"Face it turns the front (−Z side) toward the edge, like a lamp over a road. Along lines the long side up with it.",
					true -- the axis picker below reads differently for "Along"
				)
			end
			gap(b, 4)
			local alongAxis = s.fit or s.facing == "Along"
			c.PICK(
				b,
				alongAxis and "Axis along the line" or "Model's front",
				"front",
				Engine.FRONTS,
				alongAxis and "Which of the model's axes runs down the line, and so sets the piece length. Auto uses the longer side."
					or "Which side of the model is its front, the side that faces the edge (a lantern's glass, a sign's face). Auto uses the side the model reaches out to (a lamp's arm), otherwise -Z, Roblox's front."
			)
			c.S(b, "maxCount", "Limit", 0, 2000, "%.0f", 10, "Maximum number of copies. 0 means no limit.")
		end)
	end

	local function buildModels(l, parent, c)
		section(parent, "variants", "Models", true, function(b)
			for _, v in l.variants do
				local actions = {
					{
						"Swap",
						nil,
						function()
							local pick = Selection:Get()[1]
							local old = v.inst.Name
							if not (pick and Engine.swapVariant(l, table.find(l.variants, v), pick)) then
								App.status("Select the model to swap in, in the Explorer, then click Swap.")
								return
							end
							App.status(string.format("Swapped %s for %s. Copies stay on the same spots where they fit.", old, pick.Name))
							commit(l)
							App.refreshObjects()
						end,
					},
				}
				if #l.variants > 1 then
					table.insert(actions, {
						"Remove",
						"danger",
						function()
							Engine.removeVariant(l, table.find(l.variants, v))
							commit()
							App.refreshObjects()
						end,
					})
				end
				modelRow(b, v.inst, v.inst.Name, actions)
				if #l.variants > 1 then
					slider("Share", 0, 10, function()
						return v.w
					end, function(x)
						v.w = x
					end, "%.1f", 0.5, c.live, c.done, "How often this model is picked compared to the others in this object.", 1).Parent =
						b
				end
				slider("Size", 0.3, 3, function()
					return v.size
				end, function(x)
					v.size = x
				end, "%.2f×", 0.05, c.live, c.done, "Size of this model on top of the object's size range.", 1).Parent =
					b
			end
			if l.missing then
				para(
					string.format(
						"%d more model%s not found in this place. %s kept, and come%s back when found again.",
						#l.missing,
						#l.missing == 1 and "" or "s",
						#l.missing == 1 and "It's" or "They're",
						#l.missing == 1 and "s" or ""
					),
					{ Parent = b }
				)
			end
			gap(b, 4)
			hintOn(
				button("Add selected as models", nil, function()
					local added = 0
					for _, sel in Selection:Get() do
						for _, inst in sel:IsA("Folder") and sel:GetChildren() or { sel } do
							if Engine.addVariant(l, inst) then
								added += 1
							end
						end
					end
					if added == 0 then
						App.status("Select more models in the Explorer to mix them into this object.")
						return
					end
					App.status(string.format("Added %d model%s to %s.", added, added == 1 and "" or "s", l.inst.Name))
					commit(l)
					App.refreshObjects()
				end, { Parent = buttonRow(b) }),
				"Select models (or a folder of them) in the Explorer, then click: they mix into this object, e.g. pine, oak and birch in one forest."
			)
		end)
	end

	local function buildLayerPaint(l, parent)
		section(parent, "layerpaint", "Paint this object", false, function(b)
			local seg, refresh = segmented({ "More", "Less", "Clear" }, function()
				return App.paintLayer == l and App.mode or nil
			end, function(m)
				App.setMode(m, l)
			end, nil, nil, true)
			seg.Parent = b
			explain(b, "Brush over the area: More adds, Less thins out (twice removes), Clear undoes your painting.")
			App.ui.refreshLayerBrush = refresh
			if l.paint then
				gap(b, 4)
				button("Reset painting", nil, function()
					l.paint = nil
					if App.paintLayer == l then
						recolorOverlay()
					end
					commit(l)
					App.refreshObjects()
				end, { Parent = buttonRow(b) })
			end
		end)
	end

	local function buildSize(l, parent, c)
		local s = l.s
		section(parent, "size", "Size", true, function(b)
			if Engine.isLine(l) and s.fit then -- pieces that join up all share one size
				slider("Size", 0.2, 4, function()
					return (s.scaleMin + s.scaleMax) / 2
				end, function(v)
					s.scaleMin, s.scaleMax = v, v
				end, "%.2f×", 0.05, c.live, c.done, "Size of every piece. Pieces that join end to end all share one size.", 1).Parent =
					b
			else
				c.S(b, "scaleMin", "Smallest", 0.2, 4, "%.2f×", 0.05, "Smallest random size a copy can be.")
				c.S(b, "scaleMax", "Largest", 0.2, 4, "%.2f×", 0.05, "Largest random size. Bigger copies land in the middle of clumps.")
				c.S(
					b,
					"edgeYoung",
					"Young at the edges",
					0,
					1,
					"%.0f%%",
					0.05,
					"Smaller copies toward the area's edge and its clearings, like the young fringe of a real forest."
				)
			end
		end)
	end

	local function buildSpread(parent, c)
		section(parent, "spread", "Spread", true, function(b)
			c.S(b, "spacing", "Spacing", 0.3, 3, "%.2f×", 0.05, "Gap between copies of this object, relative to their size.")
			c.S(b, "clearance", "Room for others", 0, 2, "%.2f×", 0.05, "Lower lets other objects tuck in close, e.g. bushes under trees.")
			c.S(b, "cluster", "Clumping", 0, 1, "%.0f%%", 0.05, "0% spreads evenly. 100% groups copies into patches.")
			c.S(b, "clumpSize", "Clump size", 0.3, 4, "%.2f×", 0.05, "How big the patches are when clumping.")
			c.S(b, "maxCount", "Limit", 0, 2000, "%.0f", 10, "Maximum number of copies. 0 means no limit.")
		end)
	end

	local function buildGroups(l, parent, c)
		local s = l.s
		section(parent, "groups", "Groups", s.groups, function(b)
			c.SW(
				b,
				"groups",
				"Place in small groups",
				"Copies gather in little piles (barrels, crates, rocks, bushes) with space between piles, instead of spreading one by one.",
				true
			)
			if not s.groups then
				return
			end
			c.S(b, "groupMin", "Smallest group", 1, 12, "%.0f", 1, "Fewest pieces in one pile.")
			c.S(b, "groupMax", "Largest group", 1, 12, "%.0f", 1, "Most pieces in one pile.")
			c.S(b, "tight", "Tightness", 0.9, 2.5, "%.2f×", 0.05, "1× means pieces touch. Higher leaves a small gap between them.")
			-- stacking needs something flat to sit on: only offered for models with a flat top (crates, barrels, boxes)
			local flat = false
			for _, v in l.variants do
				flat = flat or v.m.flatTop >= 0.45
			end
			if flat then
				c.S(
					b,
					"stack",
					"Stack on top",
					0,
					0.6,
					"%.0f%%",
					0.05,
					"Chance a piece sits on top of another, like crates on crates. Only on flat tops."
				)
			end
			c.SW(b, "sameModel", "Same model per group", "On: a pile is all barrels or all crates. Off: models mix inside a pile.")
		end)
	end

	local function buildGrowsOn(l, parent, c)
		local s = l.s
		section(parent, "surfaces", "Grows on", false, function(b)
			local grid = chipGrid(b, 4, 30)
			for _, cls in Engine.SURFACES do
				chip(grid, NICE[cls] or cls, function()
					return s.surfaces[cls]
				end, function()
					s.surfaces[cls] = not s.surfaces[cls]
					c.changed()
				end)
			end
			if not Engine.isLine(l) then -- the height band is a scatter rule: lines follow their edge wherever it goes
				gap(b, 6)
				c.SW(b, "useAlt", "Only within a height band", "Keeps this object to part of the area's height, e.g. rocks only up high.", true)
				if s.useAlt then
					c.S(b, "altMin", "From", 0, 1, "%.0f%%", 0.05, "Bottom of the band. 0% is the lowest ground in the area.")
					c.S(b, "altMax", "To", 0, 1, "%.0f%%", 0.05, "Top of the band. 100% is the highest ground in the area.")
				end
			end
		end)
	end

	local function buildNeighbours(l, parent, c)
		local s = l.s
		section(parent, "avoid", "Keep away from", false, function(b)
			c.S(b, "keepBuilding", "Buildings", 0, 60, "%.0f studs", 1, "Minimum distance from buildings and other structures.")
			c.S(b, "keepRoad", "Roads", 0, 60, "%.0f studs", 1, "Minimum distance from roads and pavement.")
			c.S(b, "keepWater", "Water", 0, 60, "%.0f studs", 1, "Minimum distance from water.")
		end)
		section(parent, "attract", "Prefer near", false, function(b)
			segmented(Engine.HUGS, function()
				return s.hug
			end, function(v)
				s.hug = v
			end, function()
				c.changed(true)
			end).Parent =
				b
			explain(b, "Pull this object toward something: bushes near trees, crates near houses.")
			if s.hug ~= "None" then
				gap(b, 4)
				c.S(b, "hugRange", "Within", 2, 80, "%.0f studs", 1, "How far the pull reaches.")
				c.S(b, "hugStrength", "Strength", 0, 1, "%.0f%%", 0.05, "100% means only near it. 0% ignores it.")
			end
			if l.type == "Building" then
				c.SW(b, "faceRoad", "Face the nearest road", "Turns the front (−Z side) of each building toward the closest road.")
			end
			-- near another of this area's objects: mushrooms round trees, flowers round rocks
			local others = {}
			for _, o in App.area.layers do
				if o ~= l then
					table.insert(others, o)
				end
			end
			if #others > 0 then
				gap(b, 6)
				stepLabel(b, nil, "Near another object")
				local grid = chipGrid(b, 3, 30)
				chip(grid, "None", function()
					return s.near == ""
				end, function()
					s.near = ""
					c.changed(true)
				end)
				for _, o in others do
					local key = Engine.layerKey(o)
					chip(grid, o.inst.Name, function()
						return s.near == key
					end, function()
						s.near = key
						c.changed(true)
					end)
				end
				if s.near ~= "" then
					c.S(b, "nearRange", "Within", 2, 60, "%.0f studs", 1, "How far from that object's copies this one grows.")
					c.S(b, "nearStrength", "Strength", 0, 1, "%.0f%%", 0.05, "100% means only near it. 0% ignores it.")
				end
			end
		end)
	end

	local function buildSlope(parent, c)
		section(parent, "terrain", "Slope", false, function(b)
			c.S(b, "maxSlope", "Steepest", 0, 89, "%.0f°", 1, "Steepest ground this object can stand on.")
			c.S(b, "align", "Lean with the ground", 0, 1, "%.0f%%", 0.05, "0% stands straight up. 100% tilts with the slope.")
		end)
	end

	local function buildLook(l, parent, c)
		local s = l.s
		local line = Engine.isLine(l)
		section(parent, "look", "Look", false, function(b)
			if not line then
				c.PICK(b, "Rotation", "yawMode", Engine.YAW_MODES, nil, true)
				if s.yawMode == "Fixed" then
					gap(b, 4)
					c.S(b, "yaw", "Fixed angle", 0, 359, "%.0f°", 5, "The direction every copy faces.")
				end
			end
			if not (line and s.fit) then -- joined pieces stay true so their joints meet
				c.S(b, "tilt", "Random tilt", 0, 45, "%.0f°", 1, "Random lean for a less uniform look.")
				c.S(
					b,
					"lean",
					"Lean with the wind",
					0,
					30,
					"%.0f°",
					1,
					"Every copy leans the same way, like windswept trees. The direction is the area's Wind setting."
				)
			end
			gap(b, 4)
			c.SW(
				b,
				"vary",
				"Variation",
				"Every copy a little different: its own hue, saturation and brightness, on part colours, SurfaceAppearance meshes and decals alike; optionally with some details left out.",
				true
			)
			if s.vary then
				c.S(b, "hueVar", "Hue", 0, 0.15, "±%.0f%%", 0.005, "How far colours may drift round the colour wheel.")
				c.S(b, "satVar", "Saturation", 0, 0.5, "±%.0f%%", 0.01, "Richer or more washed-out colours.")
				c.S(b, "valVar", "Brightness", 0, 0.5, "±%.0f%%", 0.01, "Lighter or darker copies.")
				c.SW(
					b,
					"perPart",
					"Each part separately",
					"Off: one shift for the whole copy. On: every part gets its own, e.g. leaves in slightly different greens."
				)
				c.S(
					b,
					"dropDetails",
					"Leave out details",
					0,
					1,
					"%.0f%%",
					0.05,
					"Chance each detail part is left out, so copies differ in shape too. Details: parts named like Apple, Fruit, Berry, Mushroom, Moss, Detail, Extra or Optional, or marked with the attribute SS_Optional."
				)
			else
				c.S(b, "tint", "Colour shift", 0, 0.4, "%.0f%%", 0.01, "Random brightness and hue change per copy.")
			end
			c.S(
				b,
				"sink",
				"Sink or lift",
				-0.3,
				0.6,
				"%.0f%%",
				0.01,
				"Pushes copies into the ground (+) or lifts them (−), as a share of their height."
			)
		end)
	end

	local function buildActions(l, parent, c)
		local actions = buttonRow(parent)
		hintOn(
			button("New look", "accent", function()
				l.s.seed = (tonumber(l.s.seed) or 0) + 1
				c.done()
			end, { Parent = actions }),
			"Rerolls just this object: new positions, same settings. The other objects stay where they are."
		)
		hintOn(
			button("Reset settings", nil, function()
				Engine.resetLayer(l)
				commit(l)
				App.refreshObjects()
			end, { Parent = actions }),
			"Puts this object's rules back to the smart defaults for its type. A line stays a line."
		)
		hintOn(
			button("Select model", nil, function()
				Selection:Set({ l.inst })
			end, { Parent = actions }),
			"Selects the source model in the Explorer."
		)
		button("Remove object", "danger", function()
			table.remove(App.area.layers, table.find(App.area.layers, l))
			commit()
			showObject(nil)
		end, { Parent = actions })
	end

	local function layerRules(l, parent)
		local s = l.s
		-- a path with no painted area has nothing to scan: its lines always follow the path (the engine does the
		-- same), so the settings show that instead of a "Roads" choice that isn't what happens
		local spl = App.area and App.area.spline
		if Engine.isLine(l) and spl and #spl.pts >= 2 and (App.area.count or 0) == 0 and s.follow ~= "Spline" then
			s.follow = "Spline"
			App.saveArea()
		end
		local line = Engine.isLine(l)
		local onSpline = line and s.follow == "Spline" -- stands on the curve: ground filters and slope don't apply
		local c = controls(l)
		local panel = col({ Parent = parent }, { vlist(2) })
		buildBasics(l, panel, c)
		gap(panel, 8)
		if line then
			buildLine(l, panel, c)
		end
		buildModels(l, panel, c)
		if not onSpline then
			buildLayerPaint(l, panel)
		end
		buildSize(l, panel, c)
		if not line then
			buildSpread(panel, c)
			buildGroups(l, panel, c)
		end
		if not onSpline then
			buildGrowsOn(l, panel, c)
		end
		if not line then
			buildNeighbours(l, panel, c)
		end
		if not onSpline then -- on a path, Orientation decides how copies stand
			buildSlope(panel, c)
		end
		buildLook(l, panel, c)
		gap(panel, 8)
		buildActions(l, panel, c)
	end

	--------------------------------------------------------------------------------
	-- The list
	--------------------------------------------------------------------------------
	-- one object: thumbnail, name, what it is and how many were placed, on/off. Click to open its settings.
	local function layerRow(l, parent) -- an object in the list: thumbnail, name, what it is, its share, on/off
		local r = new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = P.card,
			Size = UDim2.new(1, 0, 0, 60),
			Parent = parent,
		}, { corner(12), stroke(P.line) })
		App.shade(r, 0.05)
		App.topLight(r, 0.06, 12)
		App.shadow(r, 12)
		App.pressable(r, 0.985)
		r.MouseEnter:Connect(function()
			r.BackgroundColor3 = P.card:Lerp(P.hover, 0.45)
		end)
		r.MouseLeave:Connect(function()
			r.BackgroundColor3 = P.card
		end)
		local th = thumbnail(l.inst, 44)
		th.Position = UDim2.fromOffset(8, 8)
		th.Parent = r
		local name = label(l.inst.Name .. (#l.variants > 1 and ("  +" .. (#l.variants - 1)) or ""), 13, l.s.enabled and P.text or P.faint, SANS_B, {
			Position = UDim2.fromOffset(62, 9),
			Size = UDim2.new(1, -112, 0, 18),
			Parent = r,
		})
		local kind = label("", 12, P.dim, SANS, { Position = UDim2.fromOffset(62, 27), Size = UDim2.new(1, -112, 0, 16), Parent = r })
		-- its share of what's placed in the area: a thin accent bar under the text (widths set by refreshCounts)
		local barTrack = box({
			BackgroundTransparency = 0,
			BackgroundColor3 = P.raised,
			Position = UDim2.fromOffset(62, 47),
			Size = UDim2.new(1, -112, 0, 3),
			Parent = r,
		}, { corner(2) })
		local bar = box({ BackgroundTransparency = 0, BackgroundColor3 = P.accent, Size = UDim2.fromScale(0, 1), Parent = barTrack }, { corner(2) })
		rowRefs[l] = { kind = kind, name = name, bar = bar }
		local sw = switch(function()
			return l.s.enabled
		end, function(v)
			l.s.enabled = v
		end, function()
			commit(l)
			App.refreshObjects()
		end)
		sw.Position = UDim2.new(1, -48, 0.5, -11)
		sw.ZIndex = 3
		sw.Parent = r
		hintOn(sw, "On or off, keeping its settings.")
		r.MouseButton1Click:Connect(function()
			showObject(l)
		end)
	end

	-- one object's settings: its name, then its rules
	local function objectPage(l, parent)
		local head = box({ Size = UDim2.new(1, 0, 0, 44), Parent = parent })
		local th = thumbnail(l.inst, 40)
		th.Position = UDim2.fromOffset(0, 2)
		th.Parent = head
		label(l.inst.Name, 16, P.text, SANS_B, { Position = UDim2.fromOffset(52, 2), Size = UDim2.new(1, -52, 0, 22), Parent = head })
		local sub = label("", 12, P.dim, SANS, { Position = UDim2.fromOffset(52, 24), Size = UDim2.new(1, -52, 0, 16), Parent = head })
		rowRefs[l] = { sub = sub }
		gap(parent, 8)
		if not Engine.isLine(l) then
			switchRow(
				"Show where it grows",
				function()
					return App.heatLayer == l
				end,
				function(v)
					App.heatLayer = v and l or nil
				end,
				function()
					rebuildOverlay()
				end,
				"Colours the painted area by how likely this object is to grow there with its current rules: dark is never, the accent is thickest. It follows your changes as you make them."
			).Parent =
				parent
		end
		layerRules(l, parent)
	end

	local function addSelected()
		if not App.area then
			newArea()
		end
		local added, skipped, last = 0, nil, nil
		local function tryAdd(inst)
			for _, l in App.area.layers do
				if l.inst == inst then
					return
				end
			end
			if Engine.isGround(inst) then
				skipped = inst.Name
				return
			end
			local l = Engine.makeLayer(inst)
			if l then
				local sp = App.area.spline
				if sp and #sp.pts >= 2 then
					if App.area.count == 0 then -- a path-only area: everything follows the curve
						Engine.smartLine(l, true)
					elseif l.s.place == "Along" then -- lamps, fences in a strip: along both edges of the curve
						l.s.follow, l.s.side, l.s.offset = "Spline", "Both", math.max(l.s.offset, (sp.width or 0) / 2)
					end
				end
				table.insert(App.area.layers, l)
				added += 1
				last = l
			end
		end
		for _, sel in Selection:Get() do
			for _, inst in sel:IsA("Folder") and sel:GetChildren() or { sel } do
				tryAdd(inst)
			end
		end
		if added == 0 then
			App.status(
				skipped and ('"' .. skipped .. '" looks like ground. To make it a road, use Mark selected as.')
					or "Select models, or a folder of them, in the Explorer first."
			)
			return
		end
		App.status(added == 1 and "Added 1 object." or string.format("Added %d objects.", added))
		G.page = "Objects"
		saveG()
		commit()
		showObject(added == 1 and last or nil) -- one new object: open it; several: show the list
	end

	-- adds ready-made objects (a preset, a biome) to the area, skipping models it already has. from: where they came
	-- from, for the status line; note: anything more to say
	local function addLayers(layers, from, note)
		if not App.area then
			newArea()
		end
		local added = 0
		for _, l in layers do
			local dup = false
			for _, o in App.area.layers do
				dup = dup or o.inst == l.inst
			end
			if not dup then
				table.insert(App.area.layers, l)
				added += 1
			end
		end
		-- objects made for a path need one: say so instead of silently placing nothing
		local sp, needPath = App.area.spline, false
		for _, l in layers do
			needPath = needPath or (l.s.follow == "Spline" and Engine.isLine(l) and not (sp and #sp.pts >= 2))
		end
		App.status(
			(
				added == 0 and string.format("%s: this area already has all its objects.", from)
				or string.format("Added %d object%s from %s.", added, added == 1 and "" or "s", from)
			)
				.. (note and (" " .. note) or "")
				.. (needPath and " Some follow a path: draw one first." or "")
		)
		App.refreshObjects()
		commit()
	end

	-- biomes: a ready set of objects made from the models already in the place (picked by their names)
	local function buildBiomes(parent, open)
		section(parent, "biomes", "Start from a biome", open, function(b)
			local grid = chipGrid(b, 4, 30)
			for _, biome in Engine.BIOMES do
				hintOn(
					chip(grid, biome.name, nil, function()
						local layers, missing = Engine.biomeLayers(biome)
						if #layers == 0 then
							App.status('No models with fitting names found (like "Oak Tree" or "Rock"). Try Get sample models.')
							return
						end
						local none = #missing > 0 and ("No " .. string.lower(table.concat(missing, ", ")) .. " models found.") or nil
						addLayers(layers, biome.name, none)
					end),
					"Adds a "
						.. string.lower(biome.name)
						.. " mix made from your models, found by name in ServerStorage, ReplicatedStorage and asset folders."
				)
			end
			gap(b, 4)
			hintOn(
				button("Get sample models", nil, function()
					local rec = beginRec("Smart Scatter: Sample models")
					local folder, made = Engine.makeSamples()
					endRec(rec, not made)
					Selection:Set({ folder })
					App.status(
						made and "Sample models are in ServerStorage > SmartScatter Samples, and selected. Pick a biome, or Add selected."
							or "Sample models are already in ServerStorage; selected them."
					)
				end, { Parent = buttonRow(b) }),
				"Puts a few simple trees, a bush, a flower, a rock and a crate in ServerStorage to try things with."
			)
		end)
	end

	-- presets: named sets of objects saved with the place, reusable in any area
	local function buildPresets(parent)
		section(parent, "presets", "Presets", false, function(b)
			local list = Engine.listPresets()
			if #list == 0 then
				App.emptyState(b, "No presets yet", "Save this area's objects below to reuse them in any area.")
			end
			for _, v in list do
				local row = box({ Size = UDim2.new(1, 0, 0, 36), Parent = b })
				label(v.Name, 13, P.text, SANS_M, { Size = UDim2.new(1, -150, 1, 0), Parent = row })
				local acts = box({
					Size = UDim2.new(0, 0, 1, 0),
					AutomaticSize = Enum.AutomaticSize.X,
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.fromScale(1, 0),
					Parent = row,
				}, { hlist(6) })
				hintOn(
					button("Use", "accent", function()
						local layers, lost = Engine.layersFromJSON(v.Value)
						addLayers(layers, v.Name, #lost > 0 and string.format("%d model%s not found in this place.", #lost, #lost == 1 and "" or "s"))
					end, { Parent = acts }),
					"Adds this preset's objects to the area (ones it already has are skipped)."
				)
				button("Delete", "danger", function()
					local rec = beginRec("Smart Scatter: Delete preset")
					v.Parent = nil
					endRec(rec)
					App.refreshObjects()
				end, { Parent = acts })
			end
			gap(b, 6)
			local saveRow = box({ Size = UDim2.new(1, 0, 0, 30), Parent = b })
			local nameBox = new("TextBox", {
				Text = "",
				PlaceholderText = "Preset name",
				Font = SANS,
				TextSize = 13,
				TextColor3 = P.text,
				PlaceholderColor3 = P.faint,
				BackgroundColor3 = P.field,
				ClearTextOnFocus = false,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, -76, 1, 0),
				Parent = saveRow,
			}, { corner(8), stroke(P.line), pad(8, 8, 0, 0) })
			hintOn(
				button("Save", "accent", function()
					local name = string.gsub(nameBox.Text, "^%s*(.-)%s*$", "%1")
					if name == "" then
						name = App.area.folder.Name
					end
					if #App.area.layers == 0 then
						App.status("Add some objects first, then save them as a preset.")
						return
					end
					local rec = beginRec("Smart Scatter: Save preset")
					Engine.savePreset(name, App.area.layers)
					endRec(rec)
					App.status(string.format("Saved %d objects as %s.", #App.area.layers, name))
					App.refreshObjects()
				end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Parent = saveRow }),
				"Saves this area's objects and all their settings under that name. Saving an existing name replaces it."
			)
		end)
	end

	-- objects whose model moved or was deleted: kept with their settings until they're pointed at a model again
	local function buildLost(list)
		local lost = App.area and App.area.lost
		if not (lost and #lost > 0) then
			return
		end
		local card = col(
			{ BackgroundTransparency = 0, BackgroundColor3 = P.card, Parent = list },
			{ corner(10), stroke(P.danger:Lerp(P.line, 0.5)), pad(12, 12, 10, 12), vlist(4) }
		)
		label(#lost == 1 and "1 object lost its model" or (#lost .. " objects lost their model"), 13, P.danger, SANS_B, { Parent = card })
		explain(
			card,
			"The model was moved, renamed or deleted, so nothing is placed. The settings are kept: select the model in the Explorer and press Use selected."
		)
		for i, d in lost do
			local row = col({ Parent = card }, { vlist(4) })
			label(tostring(d.p[#d.p]), 13, P.text, SANS_M, { Parent = row })
			label("was at " .. table.concat(d.p, " › "), 11, P.faint, SANS, { Parent = row })
			local acts = buttonRow(row)
			button("Use selected", "accent", function()
				local sel = Selection:Get()[1]
				if not sel or not (sel:IsA("Model") or sel:IsA("BasePart")) then
					App.status("Select the model this object should use in the Explorer first.")
					return
				end
				if Engine.relinkLost(App.area, i, sel) then
					App.status(tostring(d.p[#d.p]) .. " now uses " .. sel.Name .. ", with all its old settings.")
					commit()
				else
					App.status("That model can't be used for an object (it needs parts).")
				end
				App.refreshObjects()
			end, { Parent = acts })
			button("Remove", "danger", function()
				table.remove(App.area.lost, i)
				commit()
				App.refreshObjects()
			end, { Parent = acts })
		end
		gap(list, 8)
	end

	local function fillList(list)
		buildLost(list)
		if #App.area.layers > 0 then
			slider(
				"Size of everything",
				0.3,
				3,
				function()
					return App.area.size or 1
				end,
				function(v)
					App.area.size = v
				end,
				"%.2f×",
				0.05,
				function()
					requestLive()
				end,
				function()
					commit()
				end,
				"Scales every object in this area at once, on top of each one's own size. Spacing grows with it.",
				1
			).Parent =
				list
			for _, l in App.area.layers do
				layerRow(l, list)
			end
			gap(list, 2)
			hintOn(
				button("+  Add selected models", nil, addSelected, { Parent = buttonRow(list) }),
				"Select models, or a folder of them, in the Explorer. Each becomes an object you can tune."
			)
			-- single copies: take out the one that looks wrong, or bring them all back
			local fix = buttonRow(list)
			local pick = button("", nil, function()
				App.setMode("Remove")
			end, { Parent = fix })
			hintOn(pick, "Click placed copies in the viewport to take them out. Generating again keeps them out.")
			local function refresh()
				pick.Text = App.mode == "Remove" and "Done removing" or "Remove single copies"
			end
			refresh()
			App.ui.refreshRemoveBtn = refresh
			local n = Engine.removedCount(App.area)
			if n > 0 then
				button(string.format("Bring back %d removed", n), "ghost", function()
					App.area.removed = {}
					commit()
					App.refreshObjects()
					if not G.live then
						App.status("Press Generate to bring them back.")
					end
				end, { Parent = fix })
			end
		else
			App.emptyState(
				list,
				"No objects yet",
				"Select models (or a folder of them) in the Explorer, then add them. Keep the originals outside the area, e.g. in ServerStorage.",
				"Add selected models",
				addSelected
			)
		end
		gap(list, 4)
		buildBiomes(list, #App.area.layers == 0)
		buildPresets(list)
	end

	-- the page: the list, or one object's settings when one is open
	local function buildObjectsPage(parent)
		if App.expanded and not table.find(App.area.layers, App.expanded) then
			App.expanded = nil
		end
		if App.expanded then
			App.pageHead(parent, "Objects", nil, function()
				showObject(nil)
			end)
			gap(parent, 6)
			App.ui.inspector = col({ Parent = parent }, { vlist(6) })
		else
			App.pageHead(parent, App.area.folder.Name, "Objects", function()
				App.goPage("Main")
			end)
			gap(parent, 10)
			App.ui.objectList = col({ Parent = parent }, { vlist(8) })
		end
	end

	-- redraws what the page shows of the objects (after any change to them)
	App.refreshObjects = function()
		local list, inspector = App.ui.objectList, App.ui.inspector
		if App.expanded and not (App.area and table.find(App.area.layers, App.expanded)) then
			App.expanded = nil
			if inspector then -- the open object is gone (removed, undone): back to the list
				App.rebuildAll()
				return
			end
		end
		if App.area and (App.area.relinked or 0) > 0 then
			App.status(
				string.format(
					"Found %d model%s in a new place and reconnected %s.",
					App.area.relinked,
					App.area.relinked == 1 and "" or "s",
					App.area.relinked == 1 and "it" or "them"
				)
			)
			App.area.relinked = 0
			App.saveArea()
		end
		if list or inspector then
			eachThumb(function(vp) -- thumbnails are reused: take them out before the rows they sit in go
				vp.Parent = nil
			end)
			table.clear(rowRefs)
			for _, holder in { list, inspector } do
				for _, ch in holder:GetChildren() do
					if ch:IsA("GuiObject") then
						ch:Destroy()
					end
				end
			end
			if list and App.area then
				fillList(list)
			end
			if inspector and App.expanded then
				objectPage(App.expanded, inspector)
			end
		end
		App.refreshCounts()
	end

	App.refreshCounts = function()
		App.refreshPerf()
		App.checkShape()
		local most = 1 -- the bars are relative to the object placed most
		for l in rowRefs do
			most = math.max(most, (l.s.enabled and App.lastCounts[l]) or 0)
		end
		for l, r in rowRefs do
			if r.bar then
				local share = l.s.enabled and (App.lastCounts[l] or 0) / most or 0
				tween(r.bar, App.MED, { Size = UDim2.fromScale(share, 1) })
			end
			local n = App.lastCounts[l]
			local what = Engine.isLine(l) and ("Along " .. (l.s.follow == "Spline" and "path" or string.lower(l.s.follow))) or l.type
			local placed = (n and l.s.enabled) and ("  ·  " .. num(n) .. " placed") or ""
			if r.sub then
				r.sub.Text = (l.s.enabled and what or (what .. "  ·  off")) .. placed
			end
			if r.kind then
				r.kind.Text = l.s.enabled and (what .. placed .. (l.s.locked and " · locked" or "")) or "Off"
			end
		end
		if App.ui.objectsSub and App.area and #App.area.layers > 0 then
			local on, n = 0, #App.area.layers
			for _, l in App.area.layers do
				on += l.s.enabled and 1 or 0
			end
			App.ui.objectsSub.Text = string.format("%d object%s", n, n == 1 and "" or "s")
				.. (on < n and string.format(" · %d on", on) or "")
				.. (App.lastTotal > 0 and ("  ·  " .. num(App.lastTotal) .. " placed") or "")
		end
		if App.ui.genBtn and not App.busy() then -- while busy the button shows progress
			local ok, why = canGenerate()
			local failed = ok and App.failure ~= nil
			App.ui.genBtn.Text = failed and "Generate failed  ·  click to try again" or ok and "Generate" or (why or "Generate")
			tween(App.ui.genBtn, FAST, {
				BackgroundColor3 = failed and P.danger or ok and P.accent or P.raised,
				TextColor3 = ok and P.onAccent or P.faint,
			})
		end
	end

	-- used by later modules
	App.buildObjectsPage = buildObjectsPage
end
