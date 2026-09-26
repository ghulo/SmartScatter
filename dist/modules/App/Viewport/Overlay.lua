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
		local hit = workspace:Raycast(Vector3.new((cx + 0.5) * c, top, (cz + 0.5) * c), Vector3.new(0, -1500, 0), App.probeParams)
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
	end
	local QUIET = { Road = true, Dirt = true } -- only some objects go there
	local BLOCKED = { Building = true, Water = true }
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
		return BLOCKED[cls] and VIEW.blocked or QUIET[cls] and VIEW.muted or VIEW.accent
	end
	-- a cell on the area's border (a neighbour isn't painted): drawn as a brighter outline
	local function onEdge(cx, cz)
		local a = App.area
		return not (
			Engine.hasCell(a, cx + 1, cz)
			and Engine.hasCell(a, cx - 1, cz)
			and Engine.hasCell(a, cx, cz + 1)
			and Engine.hasCell(a, cx, cz - 1)
		)
	end
	local edgeStrips = setmetatable({}, { __mode = "k" }) -- the outline's strips (they breathe while you paint)
	local EDGE_REST = 0.25
	local function buildRow(cz)
		local old = rowParts[cz]
		if old then
			for _, p in old do
				p:Destroy()
			end
			rowParts[cz] = nil
		end
		local row = App.area and App.area.rows[cz]
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
		local c, parts, i = App.area.cell, {}, 1
		local zone = App.kindOf(App.area) == "Clear"
		local painting = App.paintLayer and LAYER_MODES[App.mode] -- per-object paint: no outline, just the amounts
		-- a cell's look: its colour, and whether it's on the outline (brighter, more solid)
		local function style(cx)
			local col = cellColor(cx, cz, zone)
			if not painting and onEdge(cx, cz) then
				return col == VIEW.accent and VIEW.edge or col, true
			end
			return col, false
		end
		while i <= #xs do
			local sx = xs[i]
			local y0 = probe(sx, cz).y
			local col, edge = style(sx)
			local ymax, j = y0, i
			while j < #xs and xs[j + 1] == xs[j] + 1 and j - i < 31 do
				local ny = probe(xs[j + 1], cz).y
				local col2, edge2 = style(xs[j + 1])
				if math.abs(ny - y0) > 0.6 or col2 ~= col or edge2 ~= edge then
					break
				end
				ymax = math.max(ymax, ny)
				j += 1
			end
			local n = j - i + 1
			local strip = new("Part", {
				Anchored = true,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
				CastShadow = false,
				Locked = true,
				Archivable = false,
				Material = Enum.Material.SmoothPlastic,
				Transparency = edge and EDGE_REST or 0.62,
				Color = col,
				Size = Vector3.new(n * c - 0.3, edge and 0.16 or 0.1, c - 0.3),
				CFrame = CFrame.new(sx * c + n * c / 2, ymax + 0.2, (cz + 0.5) * c),
				Parent = overlayFolder,
			})
			table.insert(parts, strip)
			if edge then
				edgeStrips[strip] = true
			end
			i = j + 1
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
		local paint = (App.mode == "Paint" or App.mode == "Erase") and overlayFolder ~= nil
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
