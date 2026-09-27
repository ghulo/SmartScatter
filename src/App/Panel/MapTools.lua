--[[
	Smart Scatter — MapTools: working on a finished map, as the controls the Map tab puts in its cards. The map scan
	(every repeated model, grouped into kinds by shape), swapping a kind for other models (tried on a few copies
	first), seasons (snowy, autumn or dry, fully or in patches), and the snapshot (the originals kept before anything
	changes them, and putting them back).
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local Selection, Engine, G, saveG, P, num = App.Selection, App.Engine, App.G, App.saveG, App.P, App.num
	local SANS, SANS_M, SANS_B, box, col, label, vlist = App.SANS, App.SANS_M, App.SANS_B, App.box, App.col, App.label, App.vlist
	local button, buttonRow, hintOn, explain, beginRec, endRec = App.button, App.buttonRow, App.hintOn, App.explain, App.beginRec, App.endRec

	local SHOWN = 12 -- kinds listed before "Show all"

	-- the last scan (this session): App.kinds = { kind, ... } from Engine.scanKinds, and where it looked
	App.kinds = nil
	local scanning, showAll, scope = false, false, "the whole map"

	-- the copies of a kind still in the map (some may have been deleted since the scan)
	local function alive(k)
		local out = {}
		for _, c in k.copies do
			if c.inst.Parent then
				table.insert(out, c.inst)
			end
		end
		return out
	end

	local function runScan()
		if scanning then
			return
		end
		local roots
		if G.scanSelection then
			roots = {}
			for _, s in Selection:Get() do
				table.insert(roots, s)
			end
			if #roots == 0 then
				App.status("Select the models or folders to scan in the Explorer first, or turn off Only the selection.")
				return
			end
		end
		scanning = true
		App.rebuildAll()
		App.status("Scanning the map…")
		task.spawn(function()
			local ok, kinds = pcall(Engine.scanKinds, { roots = roots, pause = task.wait })
			scanning = false
			if not ok then
				App.status("The scan stopped: " .. tostring(kinds), "error")
				App.rebuildAll()
				return
			end
			App.kinds, showAll = kinds, false
			scope = roots and (#roots == 1 and roots[1].Name or (#roots .. " selected")) or "the whole map"
			local copies = 0
			for _, k in kinds do
				copies += k.count
			end
			App.status(#kinds == 0 and "No repeated models found." or string.format("Found %d kinds, %s copies in all.", #kinds, num(copies)))
			App.rebuildAll()
		end)
	end

	-- swapping: the kind being swapped (its key), the models it's swapped for, how, and the copies tried so far
	local swap = { key = nil, with = {}, size = 1, match = false, turn = 0, scripts = false, tags = true, attributes = true }
	local function swapKind()
		for _, k in App.kinds or {} do
			if k.key == swap.key then
				return k
			end
		end
		return nil
	end

	-- one kind: its thumbnail, name and count, and buttons that select every copy or pick it to swap
	local function kindRow(parent, k)
		local list = alive(k)
		local row = box({ Size = UDim2.new(1, 0, 0, 36), Parent = parent })
		local th = App.thumbnail(k.copies[1].inst, 30)
		th.Position = UDim2.fromOffset(0, 3)
		th.Parent = row
		label(k.name, 13, P.text, SANS_M, { Position = UDim2.fromOffset(40, 1), Size = UDim2.new(1, -170, 0, 18), Parent = row })
		label(
			string.format("%s cop%s · %d part%s", num(#list), #list == 1 and "y" or "ies", k.parts, k.parts == 1 and "" or "s"),
			11,
			P.dim,
			SANS,
			{ Position = UDim2.fromOffset(40, 18), Size = UDim2.new(1, -170, 0, 16), Parent = row }
		)
		local acts = box({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 0, 0.5, 0),
			Size = UDim2.fromOffset(0, 30),
			AutomaticSize = Enum.AutomaticSize.X,
			Parent = row,
		}, { App.hlist(6) })
		hintOn(
			button("Select", nil, function()
				local now = alive(k)
				Selection:Set(now)
				App.status(string.format("Selected %s %s.", num(#now), #now == 1 and "copy" or "copies"))
			end, { LayoutOrder = 1, Parent = acts }),
			"Selects every copy of this kind in the Explorer and the viewport."
		)
		local picked = swap.key == k.key
		hintOn(
			button("Swap", picked and "accent" or nil, function()
				if swap.key ~= k.key then
					swap.key, swap.preview, swap.ref = k.key, nil, nil
				end
				App.rebuildAll()
			end, { LayoutOrder = 2, Parent = acts }),
			"Swap every copy of this kind for another model, or a mix (the Swap models card below)."
		)
	end

	App.buildMapScan = function(b)
		App.switchRow("Only the selection", function()
			return G.scanSelection == true
		end, function(v)
			G.scanSelection = v
		end, function()
			saveG()
		end, "On: scans only inside the models and folders selected in the Explorer. Off: the whole Workspace.").Parent =
			b
		local go = App.primaryButton(scanning and "Scanning…" or (App.kinds and "Scan again" or "Scan the map"), runScan)
		go.Parent = b
		hintOn(
			go,
			"Finds every model that appears more than once, by its shape: renamed, turned and resized copies still match. What Smart Scatter placed, and characters, are left out."
		)
		local kinds = App.kinds
		if not kinds then
			explain(b, "Groups the copies in a finished map into kinds, so you can pick every copy of one at once.")
			return
		end
		if #kinds == 0 then
			App.emptyState(b, "No repeated models", "Nothing in " .. scope .. " appears more than once.")
			return
		end
		local copies = 0
		for _, k in kinds do
			copies += k.count
		end
		label(
			string.format("%d kinds · %s copies · in %s", #kinds, num(copies), scope),
			12,
			P.faint,
			SANS_B,
			{ Size = UDim2.new(1, 0, 0, 20), Parent = b }
		)
		local list = col({ Parent = b }, { vlist(4) })
		for i, k in kinds do
			if i > SHOWN and not showAll then
				break
			end
			kindRow(list, k)
		end
		if #kinds > SHOWN then
			button(showAll and "Show fewer" or string.format("Show all %d", #kinds), "ghost", function()
				showAll = not showAll
				App.rebuildAll()
			end, { Parent = buttonRow(b) })
		end
	end

	-- the models in the current selection that can stand in for a kind
	local function selectedModels(k)
		local out, own = {}, {}
		for _, c in k and k.copies or {} do
			own[c.inst] = true
		end
		for _, sel in Selection:Get() do
			for _, inst in sel:IsA("Folder") and sel:GetChildren() or { sel } do
				if (inst:IsA("Model") or inst:IsA("BasePart")) and not own[inst] and Engine.keyOf(inst) then
					table.insert(out, inst)
				end
			end
		end
		return out
	end

	local function doSwap(k, copies, preview)
		local rec = beginRec(preview and "Smart Scatter: Try swap" or "Smart Scatter: Swap models")
		-- what the kind is like, measured once before any of it is swapped (tried copies would skew it)
		swap.ref = swap.ref or Engine.kindRef(k.copies)
		local ok, pairsOrErr = pcall(Engine.swapCopies, copies, swap.with, {
			ref = swap.ref,
			size = swap.size,
			match = swap.match,
			turn = swap.turn,
			scripts = swap.scripts,
			tags = swap.tags,
			attributes = swap.attributes,
			seed = #k.copies,
		})
		endRec(rec, not ok)
		if not ok then
			App.status("The swap stopped: " .. tostring(pairsOrErr), "error")
			return nil
		end
		-- the kind's list follows its copies: a swapped one is now the new model
		local newOf = {}
		for _, pr in pairsOrErr do
			newOf[pr.old] = pr.new
		end
		for _, c in k.copies do
			c.inst = newOf[c.inst] or c.inst
		end
		return pairsOrErr
	end

	App.buildSwap = function(b)
		local k = swapKind()
		if not k then
			swap.key, swap.preview, swap.ref = nil, nil, nil
			explain(
				b,
				App.kinds and "Press Swap on a kind in the Map scan to replace its copies with another model or a mix."
					or "Scan the map first, then press Swap on a kind."
			)
			return
		end
		-- the kind
		local head = box({ Size = UDim2.new(1, 0, 0, 36), Parent = b })
		local th = App.thumbnail(k.copies[1].inst, 30)
		th.Position = UDim2.fromOffset(0, 3)
		th.Parent = head
		label("Swap " .. k.name, 13, P.text, SANS_B, { Position = UDim2.fromOffset(40, 1), Size = UDim2.new(1, -40, 0, 18), Parent = head })
		label(string.format("%s copies in the map", num(#alive(k))), 11, P.dim, SANS, {
			Position = UDim2.fromOffset(40, 18),
			Size = UDim2.new(1, -40, 0, 16),
			Parent = head,
		})
		-- what it's swapped for
		label("For", 13, P.text, SANS, { Parent = b })
		for i, w in swap.with do
			local row = box({ Size = UDim2.new(1, 0, 0, 32), Parent = b })
			local t = App.thumbnail(w.inst, 28)
			t.Position = UDim2.fromOffset(0, 2)
			t.Parent = row
			label(w.inst.Name, 13, P.text, SANS_M, { Position = UDim2.fromOffset(36, 0), Size = UDim2.new(1, -120, 1, 0), Parent = row })
			button("Remove", "danger", function()
				table.remove(swap.with, i)
				App.rebuildAll()
			end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Parent = row })
			if #swap.with > 1 then
				App.slider("Share", 0, 10, function()
					return w.w
				end, function(v)
					w.w = v
				end, "%.1f", 0.5, nil, nil, "How often this model is picked compared to the others.", 1).Parent =
					b
			end
		end
		local pickRow = buttonRow(b)
		hintOn(
			button(#swap.with == 0 and "Use selected models" or "Add selected models", #swap.with == 0 and "accent" or nil, function()
				local found = selectedModels(k)
				if #found == 0 then
					App.status("Select the new model, or several to mix, in the Explorer first (not a copy of this kind).")
					return
				end
				for _, inst in found do
					local dup = false
					for _, w in swap.with do
						dup = dup or w.inst == inst
					end
					if not dup then
						table.insert(swap.with, { inst = inst, w = 1 })
					end
				end
				App.rebuildAll()
			end, { Parent = pickRow }),
			"Select the model to swap in, or several to mix (a folder works too), in the Explorer, then click."
		)
		if #swap.with == 0 then
			return
		end
		-- how
		App.slider("Size", 0.2, 4, function()
			return swap.size
		end, function(v)
			swap.size = v
		end, "%.2f×", 0.05, nil, nil, "On top of each copy's own scale.", 1).Parent =
			b
		App.switchRow(
			"Same size as the old ones",
			function()
				return swap.match
			end,
			function(v)
				swap.match = v
			end,
			nil,
			"On: each new copy is made as big as the one it replaces. Off: the new model keeps its own size, bigger or smaller where the old copies were."
		).Parent =
			b
		label("Turn", 13, P.text, SANS, { Parent = b })
		App.segmented({ "0°", "90°", "180°", "270°" }, function()
			return swap.turn .. "°"
		end, function(v)
			swap.turn = tonumber(string.match(v, "%d+")) or 0
		end).Parent =
			b
		explain(b, "If the new model faces another way than the old one, turn every copy about its up.")
		for _, o in
			{
				{ "scripts", "Carry over scripts", "Copies the old copy's scripts into the new one." },
				{ "tags", "Carry over tags", "The old copy's CollectionService tags go on the new one." },
				{ "attributes", "Carry over attributes", "The old copy's attributes go on the new one." },
			}
		do
			App.switchRow(o[2], function()
				return swap[o[1]]
			end, function(v)
				swap[o[1]] = v
			end, nil, o[3]).Parent = b
		end
		-- go: try it on a few first, then all
		local acts = buttonRow(b)
		local n = #alive(k)
		if swap.preview then
			hintOn(
				button("Undo the try", nil, function()
					local only = {}
					for _, pr in swap.preview do
						only[pr.new] = true
					end
					local rec = beginRec("Smart Scatter: Undo try")
					local back, map = Engine.restoreSnapshot(only)
					endRec(rec, back == 0)
					for _, c in k.copies do
						c.inst = map[c.inst] or c.inst
					end
					swap.preview = nil
					App.status(string.format("Put %d back as they were.", back))
					App.rebuildAll()
				end, { Parent = acts }),
				"Puts the tried copies back as they were."
			)
		else
			hintOn(
				button("Try on 5", nil, function()
					local copies, list = {}, {}
					for _, c in k.copies do
						if c.inst.Parent then
							table.insert(list, c)
						end
					end
					for i = 1, math.min(5, #list) do -- spread over the kind, not the first five in a row
						table.insert(copies, list[math.floor((i - 0.5) * #list / math.min(5, #list)) + 1])
					end
					local done = doSwap(k, copies, true)
					if done then
						swap.preview = done
						local sel = {}
						for _, pr in done do
							table.insert(sel, pr.new)
						end
						Selection:Set(sel)
						App.status(string.format("Swapped %d copies to try (selected). Swap all, or undo the try.", #done))
					end
					App.rebuildAll()
				end, { Parent = acts }),
				"Swaps 5 copies spread over the map, and selects them, so you can check the look first."
			)
		end
		hintOn(
			button(string.format("Swap all %s", num(n)), "accent", function()
				local tried, copies = {}, {}
				for _, pr in swap.preview or {} do
					tried[pr.new] = true
				end
				for _, c in k.copies do
					if not tried[c.inst] then -- (the tried ones are swapped already)
						table.insert(copies, c)
					end
				end
				local done = doSwap(k, copies, false)
				if done then
					App.status(
						string.format(
							"Swapped %s copies. The originals are kept: Restore original in the Snapshot card puts them back.",
							num(#done + #(swap.preview or {}))
						)
					)
					App.kinds = nil -- the map changed: scan again to see its kinds now
					swap.key, swap.preview, swap.ref = nil, nil, nil
				end
				App.rebuildAll()
			end, { Parent = acts }),
			"Swaps every copy of this kind. Their originals are kept in the snapshot first."
		)
	end

	-- seasons: what the Seasons card is set to (this session)
	local season = {
		name = "Snow",
		strength = 1,
		patchy = 0,
		patchSize = 90,
		selection = false,
		terrainColors = true,
		terrainMaterials = false,
	}
	local seasonBusy = false

	local function runSeason(off)
		if seasonBusy then
			return
		end
		local roots
		if season.selection then
			roots = Selection:Get()
			if #roots == 0 then
				App.status("Select the models or folders to change in the Explorer first, or turn off Only the selection.")
				return
			end
		end
		seasonBusy = true
		App.status(off and "Taking the season off…" or ("Turning the map " .. string.lower(season.name) .. "…"))
		App.rebuildAll()
		task.spawn(function()
			local rec = beginRec(off and "Smart Scatter: Season off" or ("Smart Scatter: " .. season.name))
			local ok, n, terrainOk = pcall(function()
				if off then
					return Engine.clearSeason({ roots = roots, pause = task.wait })
				end
				return Engine.applySeason({
					season = season.name,
					strength = season.strength,
					patchy = season.patchy,
					patchSize = season.patchSize,
					seed = 7,
					roots = roots,
					terrainColors = season.terrainColors,
					terrainMaterials = season.terrainMaterials,
					pause = task.wait,
				})
			end)
			endRec(rec, not ok)
			seasonBusy = false
			if not ok then
				App.status("Stopped: " .. tostring(n), "error")
			elseif off then
				App.status(string.format("Season off: %s parts back to their own colours.", num(n)))
			else
				App.status(
					string.format("%s: %s parts changed.", season.name, num(n))
						.. (terrainOk == false and " The terrain was too big to keep a copy of, so its grass stayed; try Only the selection." or "")
				)
			end
			App.rebuildAll()
		end)
	end

	App.buildSeasons = function(b)
		local grid = App.chipGrid(b, 3, 30)
		for i, name in Engine.SEASONS do
			local c = App.chip(grid, name, function()
				return season.name == name
			end, function()
				season.name = name
				App.rebuildAll() -- (the terrain options differ)
			end)
			c.LayoutOrder = i
			hintOn(c, Engine.SEASON_HINT[name])
		end
		App.slider("Strength", 0, 1, function()
			return season.strength
		end, function(v)
			season.strength = v
		end, "%.0f%%", 0.05, nil, nil, "How far into the season: 100% is fully snowy, autumn or dry.", 1).Parent =
			b
		App.slider("Patchy", 0, 1, function()
			return season.patchy
		end, function(v)
			season.patchy = v
		end, "%.0f%%", 0.05, nil, nil, "0%: the same everywhere. Higher: stronger in some places and lighter in others, like the first snow.", 0).Parent =
			b
		if season.patchy > 0 then
			App.slider("Patch size", 20, 300, function()
				return season.patchSize
			end, function(v)
				season.patchSize = v
			end, "%.0f studs", 5, nil, nil, "How big the stronger and lighter patches are.", 90).Parent =
				b
		end
		for _, o in
			{
				{ "selection", "Only the selection", "On: changes only the models and folders selected in the Explorer. Off: the whole Workspace." },
				{ "terrainColors", "Terrain grass colour", "Tints the terrain's grass for the season." },
				{
					"terrainMaterials",
					season.name == "Dry" and "Terrain grass to dry ground" or "Terrain grass to snow",
					"Turns the terrain's grass itself around the map. The terrain there is kept first, so it comes back exactly.",
				},
			}
		do
			if not (o[1] == "terrainMaterials" and season.name == "Autumn") then -- (autumn keeps its grass)
				App.switchRow(o[2], function()
					return season[o[1]]
				end, function(v)
					season[o[1]] = v
				end, nil, o[3]).Parent = b
			end
		end
		local info = Engine.seasonInfo()
		explain(
			b,
			info
					and string.format(
						"The map is %s now (%d%%). Applying again starts from the original colours.",
						string.lower(info.season),
						info.strength * 100
					)
				or "Colours keep their originals, so a season can be switched or taken off again exactly. What Smart Scatter places has its own Colour zones."
		)
		local row = buttonRow(b)
		button(seasonBusy and "Working…" or ("Make it " .. string.lower(season.name == "Snow" and "snowy" or season.name)), "accent", function()
			runSeason(false)
		end, { Parent = row })
		if info then
			hintOn(
				button("Take it off", nil, function()
					runSeason(true)
				end, { Parent = row }),
				"Every colour back to its own, and the terrain as it was."
			)
		end
	end

	App.buildSnapshot = function(b)
		local info = Engine.snapshotInfo()
		local text
		if not info then
			text = "Nothing kept yet. Keep the originals before swapping models or changing seasons, and put them back with one click."
		else
			text = string.format(
				"%s cop%s kept%s. %s",
				num(info.saved),
				info.saved == 1 and "y" or "ies",
				info.time and os.date(" on %d %b, %H:%M", info.time) or "",
				info.changed > 0 and string.format("%s changed since.", num(info.changed)) or "Nothing changed since."
			)
		end
		explain(b, text)
		local row = buttonRow(b)
		local kinds = App.kinds
		hintOn(
			button("Keep originals", "accent", function()
				if not (App.kinds and #App.kinds > 0) then
					App.status("Scan the map first: the snapshot keeps the copies it finds.")
					return
				end
				local list = {}
				for _, k in App.kinds do
					for _, inst in alive(k) do
						table.insert(list, inst)
					end
				end
				local rec = beginRec("Smart Scatter: Keep originals")
				local added = Engine.snapshot(list)
				endRec(rec, added == 0)
				App.status(
					added == 0 and "Every copy found is already kept."
						or string.format("Kept the originals of %s copies (ServerStorage › SmartScatter Snapshot).", num(added))
				)
				App.rebuildAll()
			end, { Parent = row }),
			kinds and "Keeps a copy of every model the scan found, as it is now. Copies kept before stay as they were."
				or "Scan the map first; this keeps a copy of every model it finds."
		)
		if info and info.changed > 0 then
			local armed = 0
			local restore
			restore = button("Restore original", "danger", function()
				if os.clock() - armed > 3 then -- asks twice
					armed = os.clock()
					restore.Text = "Click again to restore"
					task.delay(3, function()
						if os.clock() - armed >= 2.9 then
							restore.Text = "Restore original"
						end
					end)
					return
				end
				armed = 0
				local rec = beginRec("Smart Scatter: Restore original")
				local back = Engine.restoreSnapshot()
				endRec(rec, back == 0)
				App.kinds = nil -- the copies in the map are new instances now
				App.status(string.format("Put %s copies back as they were. Ctrl+Z undoes it.", num(back)))
				App.rebuildAll()
			end, { Parent = row })
			hintOn(restore, "Puts every changed copy back exactly as it was kept, where it was. Ctrl+Z undoes it.")
		end
		if info then
			hintOn(
				button("Forget", "ghost", function()
					App.dialog(
						"Forget the snapshot?",
						"The map stays as it is now, but the kept originals are deleted, so changed copies can't be put back any more.",
						{
							{
								"Forget it",
								"danger",
								function()
									local rec = beginRec("Smart Scatter: Forget snapshot")
									Engine.clearSnapshot()
									endRec(rec)
									App.status("Snapshot forgotten.")
									App.rebuildAll()
								end,
							},
							{ "Keep it", nil, function() end },
						}
					)
				end, { Parent = row }),
				"Deletes the kept originals (the map stays as it is)."
			)
		end
	end
end
