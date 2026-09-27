--[[
	Smart Scatter — MapTools: reading a finished map, as the controls the Map tab puts in its cards. The map scan
	(every repeated model, grouped into kinds by shape) and the snapshot (the originals kept before anything changes
	them, and putting them back).
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

	-- one kind: its thumbnail, name and count, and a button that selects every copy
	local function kindRow(parent, k)
		local list = alive(k)
		local row = box({ Size = UDim2.new(1, 0, 0, 36), Parent = parent })
		local th = App.thumbnail(k.copies[1].inst, 30)
		th.Position = UDim2.fromOffset(0, 3)
		th.Parent = row
		label(k.name, 13, P.text, SANS_M, { Position = UDim2.fromOffset(40, 1), Size = UDim2.new(1, -120, 0, 18), Parent = row })
		label(
			string.format("%s cop%s · %d part%s", num(#list), #list == 1 and "y" or "ies", k.parts, k.parts == 1 and "" or "s"),
			11,
			P.dim,
			SANS,
			{ Position = UDim2.fromOffset(40, 18), Size = UDim2.new(1, -120, 0, 16), Parent = row }
		)
		hintOn(
			button("Select", nil, function()
				local now = alive(k)
				Selection:Set(now)
				App.status(string.format("Selected %s %s.", num(#now), #now == 1 and "copy" or "copies"))
			end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Parent = row }),
			"Selects every copy of this kind in the Explorer and the viewport."
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
