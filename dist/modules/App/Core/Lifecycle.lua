--[[
	Smart Scatter — Lifecycle: undo/redo reload, wiring and cleanup.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local ChangeHistoryService, ctx, plugin, Engine, conns = App.ChangeHistoryService, App.ctx, App.plugin, App.Engine, App.conns
	local track, LAYER_MODES, toggleBtn, clearOverlay = App.track, App.LAYER_MODES, App.toggleBtn, App.clearOverlay
	local switchArea, eachThumb, closePopup, removeGizmo = App.switchArea, App.eachThumb, App.closePopup, App.removeGizmo
	local removeSplineViz = App.removeSplineViz

	local function alive(folder)
		return folder ~= nil and folder:IsDescendantOf(workspace)
	end

	--------------------------------------------------------------------------------
	-- Undo and redo: the area's saved state comes back, and only what that changed is rebuilt. The objects are never
	-- in the undo history themselves (see the engine's generate), so they're rebuilt from the area, but not all of
	-- them every time: the area before the undo (App.savedAttrs) is compared with the area after it.
	--   Placed at once when it was done (by hand, a button on one object, Shuffle, removing or erasing): rebuilt
	--   at once, Live on or off: just the patch of ground, or the object, that changed.
	--   Settings, the path, the area's look: rebuilt with Live on; with Live off they wait for Generate, as the change
	--   itself did ("changes waiting").
	-- The ground under the area is read again only when the painted ground changed.
	--------------------------------------------------------------------------------
	local HttpService = game:GetService("HttpService")
	local G = App.G
	-- saved attributes a rebuild doesn't depend on (or that are compared on their own below)
	local SKIP = { SS_TopY = true, SS_Failed = true, SS_Kind = true, SS_Area = true, SS_Mask = true, SS_Layers = true, SS_Removed = true }
	-- attributes whose change was placed at once: the whole area rebuilt (a new layout, a new grid)
	local AT_ONCE = { SS_Seed = true, SS_Cell = true }
	-- steps that changed what's placed without changing the area's saved state: undoing them rebuilds it all
	local OUTPUT_STEPS = { ["Smart Scatter: Clear"] = true }

	local function decode(json)
		local ok, t = pcall(HttpService.JSONDecode, HttpService, json or "[]")
		return (ok and type(t) == "table") and t or {}
	end
	local function same(a, b)
		if type(a) ~= type(b) then
			return false
		end
		if type(a) ~= "table" then
			return a == b
		end
		for k, v in a do
			if not same(v, b[k]) then
				return false
			end
		end
		for k in b do
			if a[k] == nil then
				return false
			end
		end
		return true
	end
	local function keyOf(d) -- a saved object's identity: its model's path, as Engine.layerKey writes it
		return type(d) == "table" and type(d.p) == "table" and table.concat(d.p, ".") or nil
	end
	-- the objects, before and after: which changed by hand (placed at once), which only in their rules, which came
	-- back and which went. first*: the earliest of them in the new order (the rebuild starts there).
	local function diffLayers(oldJSON, newJSON)
		local old, new = decode(oldJSON), decode(newJSON)
		local r = { dropped = {} }
		local oldBy, oldOrder = {}, {}
		for _, d in old do
			local k = keyOf(d)
			if k then
				oldBy[k] = d
				table.insert(oldOrder, k)
			end
		end
		local newKeys, newOrder = {}, {}
		for _, d in new do
			local k = keyOf(d)
			if k then
				newKeys[k] = true
				table.insert(newOrder, k)
				local o = oldBy[k]
				local s, os = type(d.s) == "table" and d.s or {}, o and type(o.s) == "table" and o.s or {}
				local hand = not o -- (an object that came back was taken out at once when it went)
					or not same(d.v, o.v)
					or not same(d.pm, o.pm)
					or not same(d.pn, o.pn)
					or not same(d.post, o.post)
					or s.seed ~= os.seed
				local rules = o ~= nil and not hand and not same(d.t, o.t)
				if o and not rules then
					local a, b = table.clone(s), table.clone(os)
					a.seed, b.seed = nil, nil
					rules = not same(a, b)
				end
				if hand then
					r.firstHand = r.firstHand or k
				end
				if rules then
					r.rules = true
				end
				if hand or rules then
					r.firstAny = r.firstAny or k
				end
			end
		end
		for _, k in oldOrder do
			if not newKeys[k] then
				table.insert(r.dropped, k)
			end
		end
		-- the same objects in another order: every one after the first moved is rebuilt
		local kept = {}
		for _, k in oldOrder do
			if newKeys[k] then
				table.insert(kept, k)
			end
		end
		local shared = 0
		for _, k in newOrder do
			if oldBy[k] then
				shared += 1
				if kept[shared] ~= k then
					r.reordered = true
					break
				end
			end
		end
		return r
	end
	-- the painted ground, before and after: the box round the cells that came back, the cells that went, and the rows
	-- either touched (world studs; nil when nothing changed)
	local function diffMask(oldArea, newArea)
		local c = newArea.cell
		local box, gone, rows = nil, {}, {}
		local function grow(cx, cz)
			local x0, z0, x1, z1 = cx * c, cz * c, (cx + 1) * c, (cz + 1) * c
			box = box and { math.min(box[1], x0), math.min(box[2], z0), math.max(box[3], x1), math.max(box[4], z1) } or { x0, z0, x1, z1 }
		end
		for cz, row in newArea.rows do
			for cx in row do
				if not Engine.hasCell(oldArea, cx, cz) then
					grow(cx, cz)
					rows[cz] = true
				end
			end
		end
		local anyGone = false
		for cz, row in oldArea.rows do
			for cx in row do
				if not Engine.hasCell(newArea, cx, cz) then
					gone[App.cellKey(cx, cz)] = true
					rows[cz] = true
					anyGone = true
				end
			end
		end
		return box, anyGone and gone or nil, next(rows) ~= nil and rows or nil
	end
	-- the spots of single copies taken out that differ (taken out, or brought back): a box round them
	local function diffRemoved(oldJSON, newJSON)
		local seen, box = {}, nil
		for _, e in decode(oldJSON) do
			if type(e) == "table" then
				seen[table.concat(e, ",")] = (seen[table.concat(e, ",")] or 0) + 1
			end
		end
		for _, e in decode(newJSON) do
			if type(e) == "table" then
				seen[table.concat(e, ",")] = (seen[table.concat(e, ",")] or 0) - 1
			end
		end
		for k, n in seen do
			if n ~= 0 then
				local _, x, z = string.match(k, "^([^,]+),([^,]+),([^,]+)$")
				x, z = tonumber(x), tonumber(z)
				if x and z then
					box = box and { math.min(box[1], x - 1), math.min(box[2], z - 1), math.max(box[3], x + 1), math.max(box[4], z + 1) }
						or { x - 1, z - 1, x + 1, z + 1 }
				end
			end
		end
		return box
	end
	local function joinBoxes(a, b)
		if not (a and b) then
			return a or b
		end
		return { math.min(a[1], b[1]), math.min(a[2], b[2]), math.max(a[3], b[3]), math.max(a[4], b[4]) }
	end

	-- the objects the panel and tools were showing, found again in the reloaded area
	local function remember()
		return {
			active = App.active and Engine.layerKey(App.active),
			heat = App.heatLayer and Engine.layerKey(App.heatLayer),
		}
	end
	local function layerByKey(k)
		for _, l in App.area and App.area.layers or {} do
			if Engine.layerKey(l) == k then
				return l
			end
		end
		return nil
	end
	local function restore(keys)
		App.heatLayer = keys.heat and layerByKey(keys.heat) or nil
	end

	-- steps: the name of the step undone or redone (a string), or the set of them a timeline jump passed
	local function afterHistory(steps)
		local f = App.area and App.area.folder
		local keys = remember()
		App.resetSplineDrag(true) -- a drag the undo just rolled back is dropped, not committed
		App.stopGestures()
		if LAYER_MODES[App.mode] then
			App.setMode("Off")
		end
		local snap, old = App.savedAttrs, App.area
		if not (old and alive(f) and snap and snap.folder == f) then
			-- the area itself came or went (a new or deleted area): load whichever is there now. What's placed came
			-- back or went with its folder; Live rebuilds it.
			switchArea(alive(f) and f or Engine.listAreas()[1], keys.active)
			restore(keys)
			if G.live and App.canGenerate() then
				App.runGenerate(false)
			end
			return
		end
		local outputStep = false
		for name in type(steps) == "table" and steps or { [steps or ""] = true } do
			outputStep = outputStep or OUTPUT_STEPS[name] == true
		end

		-- what the undo changed
		App.cancelJob()
		local new = Engine.loadArea(f)
		local oa, na = snap.attrs, f:GetAttributes()
		-- rebuild everything at once · the area's own settings changed (Live rebuilds them all)
		local wholeNow, areaRules = outputStep, false
		for k in oa do -- (every attribute either side has: these, then the new ones)
			if not SKIP[k] and not same(oa[k], na[k]) then
				if AT_ONCE[k] then
					wholeNow = true
				else
					areaRules = true
				end
			end
		end
		for k in na do
			if oa[k] == nil and not SKIP[k] then
				if AT_ONCE[k] then
					wholeNow = true
				else
					areaRules = true
				end
			end
		end
		local L = diffLayers(oa.SS_Layers, na.SS_Layers)
		local rules = areaRules or L.rules or L.reordered -- (settings of any kind: with Live off they wait)
		local cameBack, gone, rows = diffMask(old, new)
		local removedBox = diffRemoved(oa.SS_Removed, na.SS_Removed)

		-- the reloaded area in place of the old one; the ground is read again only if the painted ground changed
		App.area = new
		App.snapshotArea()
		App.failure = f:GetAttribute("SS_Failed")
		App.paintLayer = nil
		restore(keys)
		App.onAreaSwitched(f, keys.active) -- (the selection: the same area, its active object found again)
		if new.cell ~= old.cell then
			App.analysisDirty = true
			App.rebuildOverlay(true)
		elseif rows then
			App.analysisDirty = true
			for cz in rows do
				App.dirtyRows[cz] = true
			end
			App.recolorOverlay()
		else
			App.recolorOverlay()
		end
		App.refreshParams() -- (the objects' models are left out of ground rays; they may have changed)
		App.drawSpline()
		if new.locked and not App.NO_AREA_MODES[App.mode] then
			App.setMode("Off") -- (locked again: no painting it)
		end

		-- what was taken out goes now, Live or not: objects that went, and what stood on ground that went
		if #L.dropped > 0 then
			local dropped = {}
			for _, k in L.dropped do
				dropped[k] = true
			end
			for _, lf in f:GetChildren() do
				if dropped[lf:GetAttribute("SS_Key") or ""] then
					Engine.dropOutput(lf)
				end
			end
		end
		if gone then
			App.dropErased(gone, {})
		end
		App.countPlaced()

		-- then what has to be placed again
		local canGen = App.canGenerate()
		local runs = {} -- { recorded, from, region, real }
		if canGen and G.live then
			-- everything when the area's own settings or the objects' order changed; else from the first object that
			-- changed; else the patch of ground
			if wholeNow or areaRules or L.reordered or (L.firstAny and (cameBack or removedBox)) then
				table.insert(runs, { false })
			elseif L.firstAny then
				table.insert(runs, { false, layerByKey(L.firstAny) })
			elseif cameBack or removedBox then
				table.insert(runs, { false, nil, joinBoxes(cameBack, removedBox) })
			end
		elseif canGen then
			if wholeNow then
				table.insert(runs, { true, nil, nil, true })
			else
				local patch = joinBoxes(cameBack, removedBox)
				if patch then
					table.insert(runs, { false, nil, patch, true })
				end
				if L.firstHand then
					table.insert(runs, { true, layerByKey(L.firstHand), nil, true })
				end
				if rules then
					App.markPending()
				end
			end
		end
		if #runs > 0 then
			task.spawn(function()
				for _, r in runs do
					App.runGenerate(r[1], r[2], r[3], r[4])
				end
			end)
		end
	end
	App.afterHistory = afterHistory -- (a jump along the history timeline runs it once, at the end)
	local function onHistory(name)
		local echoes = App.historyEchoes
		if echoes and echoes.rebuild > 0 then -- one step of a jump along the timeline: it rebuilds once, at its end
			echoes.rebuild -= 1
			return
		end
		if type(name) ~= "string" or not string.find(name, "Smart Scatter", 1, true) then
			return
		end
		task.defer(afterHistory, name)
	end
	track(ChangeHistoryService.OnUndo:Connect(onHistory))
	track(ChangeHistoryService.OnRedo:Connect(onHistory))

	--------------------------------------------------------------------------------
	-- Wiring
	--------------------------------------------------------------------------------
	track(toggleBtn.Click:Connect(function()
		App.widget.Enabled = not App.widget.Enabled
	end))
	track(App.widget:GetPropertyChangedSignal("Enabled"):Connect(function()
		toggleBtn:SetActive(App.widget.Enabled)
		if App.widget.Enabled then
			local f = App.area and App.area.folder
			switchArea(alive(f) and f or Engine.listAreas()[1])
			App.maybeStartTour()
		else
			if App.mode ~= "Off" then
				App.setMode("Off")
			end
			closePopup()
			clearOverlay()
			App.drawSpline()
		end
	end))

	switchArea(Engine.listAreas()[1])
	toggleBtn:SetActive(App.widget.Enabled)
	App.maybeStartTour()
	-- the loader found a newer release while you're working: ask before swapping it in
	ctx.offerUpdate = function(version, apply)
		App.dialog(
			"Update available",
			"Smart Scatter " .. tostring(version) .. " is ready. Updating takes a second, needs no restart and changes nothing in your place.",
			{ { "Update now", "accent", apply }, { "Later", nil, function() end } },
			"info",
			"accent"
		)
	end
	if ctx.reloaded then
		App.status("Updated to v" .. tostring(ctx.version) .. ".")
	end

	-- cleanup (called by the loader before a hot-reload or when the plugin unloads)
	return function()
		App.cancelJob() -- a running Generate belongs to this copy of the plugin: it stops with it
		pcall(App.stopGestures) -- closes any open stroke or drag recording
		if App.mode ~= "Off" then
			App.mode = "Off"
			pcall(function()
				plugin:Deactivate()
			end)
		end
		for _, c in conns do
			c:Disconnect()
		end
		removeGizmo()
		removeSplineViz()
		clearOverlay()
		if App.clearFocus then
			App.clearFocus()
		end
		if App.closePalette then
			App.closePalette()
		end
		if App.clearToolbar then
			App.clearToolbar()
		end
		if App.root then
			App.root:Destroy()
			App.root = nil
		end
		eachThumb(function(vp)
			vp:Destroy()
		end)
	end
end
