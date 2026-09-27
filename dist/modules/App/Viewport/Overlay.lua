--[[
	Smart Scatter — Overlay: the widget and the painted-area overlay in the viewport.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local RunService, ctx, Engine, track, G, LAYER_MODES = App.RunService, App.ctx, App.Engine, App.track, App.G, App.LAYER_MODES
	local new = App.new

	--------------------------------------------------------------------------------
	-- Widget
	--------------------------------------------------------------------------------
	local toggleBtn = ctx.button
	App.widget = ctx.widget

	--------------------------------------------------------------------------------
	-- Overlay (painted area, coloured by what's under it). Cells are drawn as merged strips:
	-- one part per run of neighbouring cells in a row with the same colour and height, rebuilt row by row.
	--------------------------------------------------------------------------------
	local overlayFolder
	local rowParts = {} -- [cz] = { parts }
	local edgeStrips, edgeCount = {}, 0 -- the contour's pieces (they breathe while you paint, when there aren't too many)
	App.dirtyRows = {} -- [cz] = true
	local cellInfo = {} -- [cz][cx] = { y =, cls = } quick ground probe cache
	local MAX_OVERLAY = 80000
	local VIEW = App.VIEW -- the viewport's colours (Base; they follow the accent theme)

	local function templates()
		local t = {}
		if App.area then
			for _, l in App.area.layers do
				for _, v in l.variants do
					table.insert(t, v.inst)
				end
			end
		end
		return t
	end
	local function refreshParams()
		App.probeParams = Engine.rayParams(templates())
	end

	-- ground height + surface under a cell centre (cached)
	local function probe(cx, cz, yHint)
		local r = cellInfo[cz]
		local info = r and r[cx]
		if info then
			return info
		end
		if not App.probeParams then
			refreshParams()
		end
		local c = App.area.cell
		local top = math.max(App.area.topY or 0, yHint or -math.huge) + 250
		local hit = Engine.cast(Vector3.new((cx + 0.5) * c, top, (cz + 0.5) * c), Vector3.new(0, -1500, 0), App.probeParams)
		info = { y = hit and hit.Position.Y or (yHint or App.area.topY or 0), cls = hit and (Engine.surfaceOf(hit.Instance, hit.Material)) or "None" }
		if not r then
			r = {}
			cellInfo[cz] = r
		end
		r[cx] = info
		return info
	end

	local function overlayVisible()
		return App.area ~= nil
			and App.widget.Enabled
			and not App.overlayHidden -- the hide key (for this session)
			and (G.overlay or App.mode ~= "Off" or App.heatLayer ~= nil)
			and App.area.count <= MAX_OVERLAY
	end
	local function clearOverlay()
		if overlayFolder then
			overlayFolder:Destroy()
			overlayFolder = nil
		end
		rowParts, App.dirtyRows = {}, {}
		table.clear(edgeStrips)
		edgeCount = 0
	end
	local classColor -- (below)
	local QUIET = { Road = true, Dirt = true } -- only some objects go there
	local BLOCKED = { Building = true, Water = true }
	-- nothing under the cell at all (off the edge of an island or a platform): a pale grey
	local function noneColor()
		return VIEW.muted:Lerp(Color3.new(1, 1, 1), 0.55)
	end
	-- the colour a cell of ground takes in the overlay, by what the scan found there
	classColor = function(cls)
		return cls == "None" and noneColor() or BLOCKED[cls] and VIEW.blocked or QUIET[cls] and VIEW.muted or VIEW.accent
	end
	-- what a class of ground means for what grows on it (the label by the brush says it; nil: things grow there)
	local CLASS_NOTE = {
		Building = "a building or roof: nothing grows here",
		Water = "water: nothing grows here",
		Road = "a road: only objects set to go on roads",
		Dirt = "a path: only objects set to go on paths",
		None = "nothing under it: nothing grows here",
	}
	-- The overlay's colours and what they mean, for what's on show now: { { colour, short, long } }. The panel and the
	-- viewport's corner show it, so no colour is a mystery.
	-- which: "object" for the one-object brush's key, whatever is on
	App.overlayLegend = function(which)
		if which == "object" or (App.paintLayer and LAYER_MODES[App.mode]) then
			return {
				{ VIEW.muted:Lerp(VIEW.accent, 0.7), "more", "More of this object" },
				{ VIEW.muted, "normal", "As many as its rules place" },
				{ VIEW.muted:Lerp(VIEW.less, 0.8), "less / none", "Less of it, or none" },
			}
		end
		if App.area and App.kindOf and App.kindOf(App.area) == "Clear" then
			return { { VIEW.blocked, "kept clear", "Kept clear: nothing from any area goes here" } }
		end
		return {
			{ VIEW.accent, "grows", "Things grow here" },
			{ VIEW.muted, "roads, paths", "Road or path: only objects set to go there" },
			{ VIEW.blocked, "building, water", "Building, roof or water: nothing grows" },
			{ noneColor(), "nothing under", "Nothing under it (off an edge): nothing grows" },
		}
	end
	-- what the ground at a world point is, as the overlay knows it, and what that means ("" when things grow there)
	App.groundNote = function(x, z)
		if not App.area then
			return ""
		end
		local cls
		local an = App.lastAnalysis
		if an and not App.analysisDirty then
			local j = Engine.indexAt(an, x, z)
			cls = j and an.cls[j]
		end
		cls = cls or probe(math.floor(x / App.area.cell), math.floor(z / App.area.cell)).cls
		return CLASS_NOTE[cls] or ""
	end
	local function cellColor(cx, cz, zone)
		-- the heatmap of one object: dark where it never goes, the accent where it grows thickest
		local an = App.lastAnalysis
		if App.heatLayer and an and not App.analysisDirty then
			App.heatFn = App.heatFn or Engine.heat(App.heatLayer, an, App.area)
			local j = Engine.indexAt(an, (cx + 0.5) * App.area.cell, (cz + 0.5) * App.area.cell)
			local v = j and App.heatFn(j) or 0
			return v <= 0 and VIEW.less or VIEW.muted:Lerp(VIEW.accent, math.clamp(0.25 + v * 0.75, 0, 1))
		end
		if App.paintLayer and LAYER_MODES[App.mode] then
			local v = Engine.paintValue(App.paintLayer, cx, cz)
			if v > 1.001 then
				return VIEW.muted:Lerp(VIEW.accent, math.clamp(0.35 + (v - 1) * 0.35, 0, 1))
			end
			if v < 0.999 then
				return VIEW.muted:Lerp(VIEW.less, math.clamp(0.4 + (1 - v) * 0.6, 0, 1))
			end
			return VIEW.muted
		end
		if zone then -- a keep-clear zone: one colour
			return VIEW.blocked
		end
		local cls
		if App.lastAnalysis and not App.analysisDirty then
			local j = Engine.indexAt(App.lastAnalysis, (cx + 0.5) * App.area.cell, (cz + 0.5) * App.area.cell)
			cls = j and App.lastAnalysis.cls[j]
		end
		cls = cls or probe(cx, cz).cls
		return classColor(cls)
	end
	-- The look: a soft, continuous fill (no seams between cells, one flat strip per run of cells of the same colour and
	-- height) and, round the painted shape, a thin glowing contour exactly on its border, so the area reads as one
	-- clean shape rather than a grid of tiles.
	local FILL = 0.66 -- how see-through the fill is
	local RIM, RIM_W = 0.3, 0.26 -- the contour: how see-through, and how wide (studs)
	local BREATHE_MAX = 300 -- more contour pieces than this: it stays still (animating thousands costs frames)
	local EDGE_REST = RIM
	-- Parts are reused, not made and destroyed: a stroke rebuilds the rows it touches, and making parts is the
	-- slow part of that. A rebuilt row's parts go back to this pool (out of the world) for the next row to take.
	local pool, POOL_MAX = {}, 4000
	local function strip(props)
		local p = table.remove(pool)
		if not p then
			p = Instance.new("Part")
			p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
			p.CastShadow, p.Locked, p.Archivable = false, true, false
		end
		p.Material, p.Transparency, p.Color, p.Size, p.CFrame = props.Material, props.Transparency, props.Color, props.Size, props.CFrame
		p.Parent = overlayFolder
		return p
	end
	local function release(p)
		if edgeStrips[p] then
			edgeStrips[p] = nil
			edgeCount -= 1
		end
		if #pool < POOL_MAX and p.Parent then
			p.Parent = nil
			table.insert(pool, p)
		else
			p:Destroy()
		end
	end
	local function buildRow(cz)
		local old = rowParts[cz]
		if old then
			for _, p in old do
				release(p)
			end
			rowParts[cz] = nil
		end
		local a = App.area
		local row = a and a.rows[cz]
		if not row then
			return
		end
		if not overlayFolder or not overlayFolder.Parent then
			overlayFolder = new("Folder", { Name = "SmartScatterOverlay", Archivable = false, Parent = workspace.CurrentCamera })
		end
		local xs = {}
		for cx in row do
			table.insert(xs, cx)
		end
		table.sort(xs)
		local c, parts = a.cell, {}
		local zone = App.kindOf(a) == "Clear"
		local painting = App.paintLayer and LAYER_MODES[App.mode] ~= nil -- one object: no contour, just its amounts
		-- the fill: runs of neighbouring cells with the same colour and height, edge to edge
		local i = 1
		while i <= #xs do
			local sx = xs[i]
			local y0 = probe(sx, cz).y
			local col = cellColor(sx, cz, zone)
			local ymax, j = y0, i
			while j < #xs and xs[j + 1] == xs[j] + 1 and j - i < 31 do
				local ny = probe(xs[j + 1], cz).y
				if math.abs(ny - y0) > 0.6 or cellColor(xs[j + 1], cz, zone) ~= col then
					break
				end
				ymax = math.max(ymax, ny)
				j += 1
			end
			local n = j - i + 1
			table.insert(
				parts,
				strip({
					Material = Enum.Material.SmoothPlastic,
					Transparency = FILL,
					Color = col,
					Size = Vector3.new(n * c, 0.06, c),
					CFrame = CFrame.new(sx * c + n * c / 2, ymax + 0.18, (cz + 0.5) * c),
				})
			)
			i = j + 1
		end
		if painting then
			rowParts[cz] = parts
			return
		end
		-- the contour: every side of a cell that borders unpainted ground, as a thin glowing line (the sides along the
		-- row joined into one line where they run on at the same height)
		local function rimColor(cx)
			local col = cellColor(cx, cz, zone)
			return col == VIEW.accent and VIEW.edge or col
		end
		local function line(cf, size, col)
			local p = strip({ Material = Enum.Material.Neon, Transparency = RIM, Color = col, Size = size, CFrame = cf })
			edgeStrips[p] = true
			edgeCount += 1
			table.insert(parts, p)
		end
		for _, side in { -1, 1 } do -- the row's far and near sides (z)
			local k = 1
			while k <= #xs do
				local cx = xs[k]
				if not Engine.hasCell(a, cx, cz + side) then
					local y0, col, m = probe(cx, cz).y, rimColor(cx), k
					while m < #xs and xs[m + 1] == xs[m] + 1 and not Engine.hasCell(a, xs[m + 1], cz + side) do
						if math.abs(probe(xs[m + 1], cz).y - y0) > 0.6 or rimColor(xs[m + 1]) ~= col then
							break
						end
						m += 1
					end
					local n = xs[m] - cx + 1
					local z = (side < 0 and cz or cz + 1) * c
					line(CFrame.new(cx * c + n * c / 2, y0 + 0.22, z), Vector3.new(n * c + RIM_W, 0.08, RIM_W), col)
					k = m + 1
				else
					k += 1
				end
			end
		end
		for _, cx in xs do -- the ends of each run (x)
			for _, side in { -1, 1 } do
				if not Engine.hasCell(a, cx + side, cz) then
					local x = (side < 0 and cx or cx + 1) * c
					line(CFrame.new(x, probe(cx, cz).y + 0.22, (cz + 0.5) * c), Vector3.new(RIM_W, 0.08, c + RIM_W), rimColor(cx))
				end
			end
		end
		rowParts[cz] = parts
	end
	-- budget (seconds, optional): stop after this long; the rest is drawn over the next frames
	local function flushRows(budget)
		if not overlayVisible() then
			App.dirtyRows = {}
			return
		end
		-- a changed row changes which cells of the rows beside it are on the outline: redraw those too (once)
		local fresh = {}
		for cz, v in App.dirtyRows do
			if v == true then
				table.insert(fresh, cz)
			end
		end
		for _, cz in fresh do -- (keys are added after the loop: a table can't grow while it's being walked)
			App.dirtyRows[cz] = "near"
			App.dirtyRows[cz - 1] = App.dirtyRows[cz - 1] or "near"
			App.dirtyRows[cz + 1] = App.dirtyRows[cz + 1] or "near"
		end
		local t0 = os.clock()
		for cz in App.dirtyRows do
			App.dirtyRows[cz] = nil
			buildRow(cz)
			if budget and os.clock() - t0 > budget then
				break
			end
		end
	end
	-- while you paint the area, its outline breathes (a dozen updates a second, only the outline's strips)
	local breath, breathing = 0, false
	track(RunService.Heartbeat:Connect(function(dt)
		if next(App.dirtyRows) then
			flushRows(0.004) -- a few ms a frame, so a big redraw never stalls Studio
		end
		local paint = (App.mode == "Paint" or App.mode == "Erase") and overlayFolder ~= nil and edgeCount <= BREATHE_MAX
		if paint or breathing then
			breath += dt
			if breath >= 0.08 or not paint then
				local t = paint and EDGE_REST - 0.06 + 0.06 * math.sin(os.clock() * 2.4) or EDGE_REST
				breath, breathing = 0, paint
				for strip in edgeStrips do
					strip.Transparency = t
				end
			end
		end
	end))

	-- fresh = forget cached ground probes (area switched, rescan, geometry changed)
	local function rebuildOverlay(fresh)
		clearOverlay()
		if fresh then
			cellInfo = {}
		end
		refreshParams()
		if not overlayVisible() then
			return
		end
		for cz in App.area.rows do
			App.dirtyRows[cz] = true
		end
		flushRows(0.03) -- the first part now, the rest over the next frames
	end
	local function recolorOverlay()
		App.heatFn = nil -- rules may have changed: the heatmap is worked out again
		for cz in rowParts do
			App.dirtyRows[cz] = true
		end
	end

	-- used by later modules
	App.toggleBtn = toggleBtn
	App.templates = templates
	App.refreshParams = refreshParams
	App.probe = probe
	App.clearOverlay = clearOverlay
	App.flushRows = flushRows
	App.rebuildOverlay = rebuildOverlay
	App.recolorOverlay = recolorOverlay
end
