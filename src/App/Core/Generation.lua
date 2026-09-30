--[[
	Smart Scatter — Generation: generation (cached scan, live throttle), areas and model thumbnails.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local beginRec, endRec, Engine, G, num, P, new = App.beginRec, App.endRec, App.Engine, App.G, App.num, App.P, App.new
	local corner, stroke, templates, rebuildOverlay = App.corner, App.stroke, App.templates, App.rebuildOverlay
	local recolorOverlay = App.recolorOverlay

	--------------------------------------------------------------------------------
	-- Generation (cached scan, cooperative jobs)
	--------------------------------------------------------------------------------

	-- Has the world under the area changed since the last scan? A fingerprint of the parts in the scanned region
	-- (where they are, how big, what they're made of) and a grid of terrain heights, plus Studio's own history: any
	-- edit that isn't ours. Generate re-scans only when something changed; Rescan always does.
	local CHS = App.ChangeHistoryService
	local lastPrint, worldEdited = nil, true
	local function edited()
		worldEdited = true
	end
	App.track(CHS.OnUndo:Connect(edited))
	App.track(CHS.OnRedo:Connect(edited))
	pcall(function()
		App.track(CHS.OnRecordingFinished:Connect(function(name)
			if not (type(name) == "string" and string.find(name, "Smart Scatter", 1, true)) then
				worldEdited = true
			end
		end))
	end)
	local function worldPrint()
		local an = App.lastAnalysis
		if not an then
			return nil
		end
		local w, d = an.nx * an.G, an.nz * an.G
		local centre = Vector3.new(an.x0 + w / 2, an.top - an.len / 2, an.z0 + d / 2)
		local op = OverlapParams.new()
		op.FilterType = Enum.RaycastFilterType.Exclude
		local skip = { workspace.CurrentCamera, workspace.Terrain }
		for _, f in { Engine.outFolder(), workspace:FindFirstChild(Engine.ROADS) } do
			table.insert(skip, f)
		end
		for _, t in templates() do
			table.insert(skip, t)
		end
		op.FilterDescendantsInstances = skip
		local sum, count = 0, 0
		for _, p in workspace:GetPartBoundsInBox(CFrame.new(centre), Vector3.new(w, an.len, d), op) do
			local pos, sz = p.Position, p.Size
			sum += pos.X * 1.31 + pos.Y * 2.17 + pos.Z * 3.73 + sz.X * 5.39 + sz.Y * 7.13 + sz.Z * 11.97 + p.Material.Value * 0.013 + (p.CanCollide and 0.7 or 0) + p.Orientation.Y * 0.0071
			count += 1
		end
		-- terrain: heights on a 16 x 16 grid over the region
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Include
		rp.FilterDescendantsInstances = { workspace.Terrain }
		local down = Vector3.new(0, -an.len, 0)
		for i = 0, 15 do
			for j = 0, 15 do
				local hit = workspace:Raycast(Vector3.new(an.x0 + (i + 0.5) * w / 16, an.top, an.z0 + (j + 0.5) * d / 16), down, rp)
				if hit then
					sum += hit.Position.Y * (i * 16 + j + 1) * 0.001 + hit.Material.Value * 0.0003
				end
			end
		end
		return string.format("%d:%.3f", count, sum)
	end
	-- true when the next Generate has to read the ground again
	App.worldChanged = function()
		if worldEdited or not App.lastAnalysis or not lastPrint then
			return true
		end
		return worldPrint() ~= lastPrint
	end

	-- the area as last saved or loaded (its folder's attributes): what an undo is compared against, so it rebuilds
	-- only what the undo changed (Core/Lifecycle)
	local function snapshot()
		App.savedAttrs = App.area and { folder = App.area.folder, attrs = App.area.folder:GetAttributes() } or nil
	end
	App.snapshotArea = snapshot
	local function saveArea()
		if App.area then
			Engine.saveArea(App.area)
			snapshot()
		end
	end

	local function canGenerate()
		if not App.area then
			return false, "Paint an area to get started."
		end
		if App.area.locked then
			return false, "Area locked · unlock it in the area menu"
		end
		if App.area.count == 0 and not (App.area.spline and #App.area.spline.pts >= 2) then
			return false, "Paint an area or draw a spline first."
		end
		local sp = App.area.spline
		local road = sp and Engine.roadWidth(sp) > 0 and #sp.pts >= 2
		if #App.area.layers == 0 and not road then
			return false, "Add a layer to fill the area."
		end
		return true
	end

	-- a short, readable reason from an error ("Engine:890: attempt to index nil" -> "attempt to index nil (engine line 890)")
	local function explainError(err)
		local msg = tostring(err)
		local where, line, rest = string.match(msg, "([%w_]+):(%d+): (.*)$")
		if rest then
			local part = string.find(where, "Engine", 1, true) and "engine" or "plugin"
			msg = rest .. " (" .. part .. " line " .. line .. ")"
		end
		msg = string.gsub(msg, "%s+", " ")
		if #msg > 90 then
			msg = string.sub(msg, 1, 87) .. "..."
		end
		return msg .. "."
	end

	-- Generation runs as a job, time-sliced so Studio stays responsive, with its
	-- progress on the Generate button. One job at a time: a newer request cancels a running live preview, and a
	-- cancelled job changes nothing (the engine builds off-screen and swaps the result in at the end).
	local ALL = {} -- `from` meaning "rebuild every layer"
	local function mergeFrom(a, b)
		b = b or ALL
		if a == nil or a == b then
			return b
		end
		return ALL
	end
	-- a job under ~80 ms finishes in the frame it started (feels instant); a longer one works 30 ms per frame,
	-- so Studio still redraws and the Generate button can stop it
	local FIRST_SLICE, SLICE = 0.08, 0.03
	-- a live preview (dragging a slider starts one every frame, each retiring the last) works in short slices from the
	-- start, so the panel keeps up with the mouse instead of stalling 80 ms a frame
	local LIVE_SLICE = 0.015
	local HEAVY_PARTS = 25000 -- more than this is a slowdown on most machines: Live update stops and asks
	local LIGHT_PARTS = 3000 -- up to this, Live places the real models (quick enough); above it, see-through boxes
	local heavyAsked = setmetatable({}, { __mode = "k" }) -- [area folder] = true once the pop-up was shown
	local job -- the running job: { live = bool, from = layer?, cancel = bool }
	local liveFrom, liveLoop = nil, false

	-- Changes waiting for Generate (Live off): an area whose saved settings, ground or path changed since its last full
	-- real run. The Generate button says so, so a change that doesn't show yet never looks like it did nothing.
	local pendingFor = setmetatable({}, { __mode = "k" }) -- [area folder] = true
	local function markPending()
		if G.live or not App.area then
			return
		end
		local first = not pendingFor[App.area.folder]
		pendingFor[App.area.folder] = true
		if first and App.hint then -- (the button keeps saying it; the toast only the first couple of times)
			App.hint("pending", "Saved. Changes show when you press Generate (or turn Live on).")
		end
		if App.refreshCounts then
			App.refreshCounts()
		end
	end
	App.markPending = markPending
	App.hasPending = function()
		return App.area ~= nil and pendingFor[App.area.folder] == true
	end

	-- region: the patch a stroke changed (live only). A run that gets cancelled leaves its patch (or, for a full run,
	-- everything: lostPatch = true) out of date, so the next run covers it too; a completed run clears it.
	-- lostPins: that patch was only ever a copy changed by hand's (pins), so the run covering it places pins alone.
	local lostPatch, lostPins = nil, false
	local function joinBoxes(a, b)
		if not (a and b) then
			return a or b
		end
		return { math.min(a[1], b[1]), math.min(a[2], b[2]), math.max(a[3], b[3]), math.max(a[4], b[4]) }
	end
	-- reads the ground under the area again if it's out of date (tick: the job's time slicing, or nil to do it at once).
	-- Returns true when it was read now, false when it was up to date, nil when cancelled.
	local function readGround(area, tick)
		if not (App.analysisDirty or not App.lastAnalysis) then
			return false
		end
		local an, aborted = Engine.analyze(area, templates(), tick)
		if aborted then
			return nil
		end
		App.lastAnalysis = an
		App.analysisDirty = false
		lastPrint, worldEdited = worldPrint(), false
		App.refreshScan()
		recolorOverlay()
		return true
	end
	App.readGround = readGround

	-- real: this run places the real models (the Generate button, a change applied at once). Any other run while Live
	-- is on places the real models too when that's quick (a patch, a light area); a heavier one is a preview: a
	-- see-through box per copy (Settings › Live previews as boxes), quick to redo, until Generate places the models.
	-- pins (with a region): only the stamps' pins in the patch are placed again, every other copy there stays.
	local function runGenerate(recorded, from, region, real, pins)
		if not canGenerate() then -- the Generate button shows why
			return
		end
		local preview = G.live and G.liveBoxes and not real
		local me = { live = not recorded, from = from }
		while job do -- wait for the running job; a newer request of any kind retires a live preview
			if job.live and job ~= me then
				job.cancel = true
			end
			task.wait()
		end
		if not canGenerate() then -- the area was deleted, emptied or locked while this waited
			return
		end
		job = me
		-- (after the wait: the run just retired may have left something out of date) every layer there, or all
		if lostPatch then
			from = nil
			region = lostPatch ~= true and region and joinBoxes(region, lostPatch) or nil
			pins = pins and lostPins
		end
		me.from, me.region = from, not recorded and region or nil
		me.pins = me.region ~= nil and pins == true
		App.heavyWarning = nil
		local area = App.area
		local t0, slice = os.clock(), os.clock()
		local budget = (me.live and not region) and LIVE_SLICE or FIRST_SLICE
		local phase = "Scanning"
		local function tick(progress)
			if me.cancel or App.area ~= area then
				return false
			end
			if os.clock() - slice > budget then
				budget = (me.live and not me.region) and LIVE_SLICE or SLICE
				if App.showProgress then
					App.showProgress(phase, progress)
				end
				task.wait()
				slice = os.clock()
				if me.cancel or App.area ~= area then
					return false
				end
			end
			return true
		end
		local trace
		local success, err = xpcall(function()
			local read = readGround(area, tick)
			if read == nil then
				return
			elseif read then -- everything depends on the ground: every layer is rebuilt
				from = nil
			end
			if from and not table.find(area.layers, from) then
				from = nil
			end
			-- Live's preview is the real models when they're quick to place (a patch, or a light area): boxes only
			-- stand in when the real thing would be slow, so a change shows as it will look whenever it can
			local copies, parts
			if preview then
				if me.region then
					preview = false
				else
					copies, parts = Engine.estimate(area, App.lastAnalysis, G.density)
					preview = parts > LIGHT_PARTS
				end
			end
			-- a live preview that would place enough to stall Studio waits for a real Generate instead (a box is
			-- one part, however many the model has). A patch run places only its patch: never too heavy.
			if (me.live or preview) and not me.region then
				if not copies then
					copies, parts = Engine.estimate(area, App.lastAnalysis, G.density)
				end
				if (preview and copies or parts) > HEAVY_PARTS then
					App.heavyWarning = { copies = copies, parts = parts, area = area }
					return
				end
			end
			App.heavyWarning = nil
			phase = "Placing"
			local counts, total, parts = Engine.generate(area, App.lastAnalysis, G.density, templates(), {
				from = from,
				region = me.region,
				pins = me.pins,
				output = { walk = G.walk, shadows = G.shadows, query = G.query, chunks = G.chunks, ghost = preview },
				tick = tick,
			})
			if counts then
				App.lastCounts, App.lastTotal, App.lastParts = counts, total, parts
				me.done = true
				lostPatch, lostPins = nil, false
				App.reapplyHidden(area.folder)
				if not preview and from == nil and me.region == nil then -- everything is as saved now
					pendingFor[area.folder] = nil
				end
			end
		end, function(e)
			trace = debug.traceback(tostring(e), 2)
			return e
		end)
		job = nil
		if not me.done and App.area == area then
			lostPins = me.pins and (lostPatch == nil or lostPins)
			lostPatch = (me.region and lostPatch ~= true) and joinBoxes(lostPatch, me.region) or true
		end
		if App.showProgress then
			App.showProgress(nil)
		end
		if success and not me.done then -- cancelled, or paused as too heavy: nothing changed
			local w = App.heavyWarning
			if w then
				App.status(string.format("Live update paused: about %s objects (%s parts) is too heavy.", num(w.copies), num(w.parts)), "error")
				if not heavyAsked[w.area.folder] then -- asked once per area; after that the status line says it
					heavyAsked[w.area.folder] = true
					App.dialog(
						"This would slow Studio down",
						string.format(
							"The area would get about %s objects (%s parts). Live update paused so Studio stays smooth.\n\n"
								.. "Place it anyway, or lower the amount or Size of everything first.",
							num(w.copies),
							num(w.parts)
						),
						{
							{
								"Place anyway",
								"accent",
								function()
									runGenerate(true, nil, nil, true)
								end,
							},
							{ "Keep it off", nil, function() end },
						}
					)
				end
			end
			return
		end
		local seconds = os.clock() - t0
		App.failure = not success and explainError(err) or nil
		if area and area.folder and area.folder.Parent then
			-- the objects on screen are from the last run that worked; remember that across sessions too
			if area.folder:GetAttribute("SS_Failed") ~= App.failure then
				area.folder:SetAttribute("SS_Failed", App.failure)
			end
		end
		if success and preview then
			App.status(string.format("Preview: %s objects as boxes. Press Generate to place the real models.", num(App.lastTotal)))
		elseif success then
			local ms = seconds * 1000
			local note, heavy = App.perfNote()
			App.status(
				string.format(
					"%s objects · %s parts · %s%s",
					num(App.lastTotal),
					num(App.lastParts),
					ms < 1000 and string.format("%d ms", math.floor(ms + 0.5)) or string.format("%.1f s", ms / 1000),
					note ~= "" and ("  " .. note) or ""
				),
				heavy and "error" or nil
			)
		else
			warn("[Smart Scatter] Generate failed. Please send this to the plugin author:\n" .. tostring(trace or err))
			App.status("Generate failed: " .. App.failure .. " What you see is the last result that worked.", "error")
		end
		App.refreshCounts()
		if success and recorded and not preview and App.flashDone then
			App.flashDone(string.format("Done  ·  %s placed", num(App.lastTotal)))
		end
	end

	-- stop whatever is generating (the Generate button while busy, switching areas)
	local function cancelJob()
		if job then
			job.cancel = true
		end
	end
	local function busy()
		return job ~= nil
	end

	-- live preview: the newest settings win; a stale preview is dropped, not finished
	local function requestLive(from)
		if not G.live or not canGenerate() then
			return
		end
		liveFrom = mergeFrom(liveFrom, from)
		if job and job.live then
			liveFrom = mergeFrom(liveFrom, job.from)
			job.cancel = true
		end
		if liveLoop then
			return
		end
		liveLoop = true
		task.spawn(function()
			while liveFrom ~= nil do
				local f = liveFrom
				liveFrom = nil
				runGenerate(false, f ~= ALL and f or nil)
			end
			liveLoop = false
		end)
	end

	-- a finished edit: saved as one undo step (the objects aren't part of it: undo rebuilds them from the saved
	-- settings), then one run that also covers any preview still pending
	-- saves the area as one undo step (named `what`, or "Change settings") and, when live, rebuilds from `from` on
	local function commit(from, what)
		local rec = beginRec("Smart Scatter: " .. (what or "Change settings"))
		saveArea()
		endRec(rec)
		if not G.live then
			markPending()
			return
		end
		local f = mergeFrom(liveFrom, from)
		if job and job.live then
			f = mergeFrom(f, job.from)
		end
		liveFrom = nil
		task.spawn(function()
			runGenerate(true, f ~= ALL and f or nil)
		end)
	end

	-- A change to one object that you do by hand or by a button on it (New look, Swap, taking back what was done by
	-- hand): saved as one undo step, then its real copies rebuilt at once, Live on or off, as a stamp is. from: the
	-- object (it and the objects after it are rebuilt; nil: all of them). region: only that patch (a brush stroke).
	-- pins (with a region): only the stamps' pins in the patch (a copy changed by hand); the rest of it stays.
	local function applyNow(from, what, region, pins)
		if what then
			local rec = beginRec("Smart Scatter: " .. what)
			saveArea()
			endRec(rec)
		end
		if not canGenerate() then
			return
		end
		liveFrom = nil -- (this run covers a preview still waiting)
		task.spawn(function()
			if region then -- (a patch is a quick run of its own: a newer stroke may take over from it)
				runGenerate(false, from, region, true, pins)
			else
				runGenerate(true, from, nil, true)
			end
		end)
	end

	--------------------------------------------------------------------------------
	-- Areas
	--------------------------------------------------------------------------------
	-- what's placed in the area now, counted per object from its output folder
	function App.countPlaced()
		App.lastCounts, App.lastTotal, App.lastParts = {}, 0, 0
		if not App.area then
			return
		end
		for _, f in App.area.folder:GetChildren() do
			local key = f:GetAttribute("SS_Key")
			for _, l in App.area.layers do
				if key == Engine.layerKey(l) or (not key and f.Name == l.inst.Name) then
					local n = 0
					for _, d in f:GetDescendants() do
						if d:GetAttribute("SS_Type") then
							n += 1
						end
						if d:IsA("BasePart") then
							App.lastParts += 1
						end
					end
					App.lastCounts[l] = n
					App.lastTotal += n
					break
				end
			end
		end
	end

	-- loads an area (nil: none) as the one being worked on; the selection follows (Core/Selection), and with it the
	-- panel. keep (optional): the key of an object to keep active (an undo reloads the same area).
	local function switchArea(folder, keep)
		cancelJob()
		App.area = folder and Engine.loadArea(folder) or nil
		snapshot()
		App.failure = App.area and App.area.folder:GetAttribute("SS_Failed") or nil -- its last Generate failed
		App.lastAnalysis, App.analysisDirty, App.lastCounts, App.lastTotal, App.lastParts = nil, true, {}, 0, 0
		App.paintLayer = nil
		App.countPlaced()
		if App.setMode and not App.NO_AREA_MODES[App.mode] and (not App.area or App.area.locked) then
			App.setMode("Off") -- nothing to paint on, or not allowed to
		end
		rebuildOverlay(true)
		if App.drawSpline then
			App.drawSpline()
		end
		if App.onAreaSwitched then -- (the selection, then everything that shows it)
			App.onAreaSwitched(App.area and App.area.folder, keep)
		end
		if App.refreshCounts then
			App.refreshCounts()
		end
	end

	-- opts.keepMode: the caller is already switching modes (painting started with no area yet)
	-- opts.kind: "Scatter" (default) or "Clear" (a keep-clear zone)
	local function newArea(opts)
		local clear = opts and opts.kind == "Clear"
		local n = #Engine.listAreas() + 1
		while Engine.getOut():FindFirstChild("Area " .. n) do
			n += 1
		end
		local rec = beginRec(clear and "Smart Scatter: New Keep-clear Zone" or "Smart Scatter: New Area")
		local a = Engine.createArea((clear and "Keep clear " or "Area ") .. n, nil)
		a.folder:SetAttribute("SS_Kind", clear and "Clear" or "Scatter")
		endRec(rec)
		switchArea(a.folder)
		if not (opts and opts.keepMode) then
			App.setMode("Paint")
		end
		App.status(clear and "Paint where nothing should go." or "Paint the ground where things should go.")
	end

	local function deleteArea()
		if not App.area then
			return
		end
		local rec = beginRec("Smart Scatter: Delete Area")
		local surface = Engine.roadOf(App.area)
		if surface then
			surface.Parent = nil -- its road goes with it
		end
		App.area.folder.Parent = nil
		endRec(rec)
		switchArea(Engine.listAreas()[1])
		App.status("Area deleted. Ctrl+Z brings it back.")
	end

	--------------------------------------------------------------------------------
	-- Hidden things (the outliner's eye): what a zone, a path or an array placed, not drawn. For this session and for
	-- you only: nothing in the place changes (a part's LocalTransparencyModifier is neither saved nor sent to anyone
	-- else), so nothing needs undoing. Copies placed while it's hidden are hidden as they arrive.
	--------------------------------------------------------------------------------
	local hidden = setmetatable({}, { __mode = "k" }) -- [a thing's folder] = true
	local function applyHidden(folder)
		local t = hidden[folder] and 1 or 0
		for _, d in folder:GetDescendants() do
			if d:IsA("BasePart") or d:IsA("Decal") then
				d.LocalTransparencyModifier = t
			end
		end
	end
	App.isHidden = function(folder)
		return hidden[folder] == true
	end
	App.setHidden = function(folder, on)
		hidden[folder] = on and true or nil
		applyHidden(folder)
	end
	-- after something placed copies again (a generate, an undo, an array rebuilt): the hidden ones' new copies too
	App.reapplyHidden = function(only)
		for folder in hidden do
			if folder.Parent and (only == nil or only == folder) then
				applyHidden(folder)
			end
		end
	end

	--------------------------------------------------------------------------------
	-- Thumbnails
	--------------------------------------------------------------------------------
	local thumbCache = {} -- [inst] = { [px] = ViewportFrame }
	local function eachThumb(fn)
		for _, bySize in thumbCache do
			for _, vp in bySize do
				fn(vp)
			end
		end
	end
	-- Thumbnails outlive a panel rebuild (a model's view is cloned once, not on every click): before the panel's
	-- rows go, they're taken out of them; the ones whose model is gone are dropped, and all of them if there are
	-- many. all: drop every one (a new theme: their colours come from it). under: only the ones inside it are taken
	-- out (the page rebuilt by itself: the outliner above it keeps its own).
	local function pruneThumbs(all, under)
		local n = 0
		for _ in thumbCache do
			n += 1
		end
		for inst, bySize in thumbCache do
			local drop = all or (n > 150 and not under) or not inst.Parent
			for _, vp in bySize do
				if drop then
					vp:Destroy()
				elseif not under or vp:IsDescendantOf(under) then
					vp.Parent = nil
				end
			end
			if drop then
				thumbCache[inst] = nil
			end
		end
	end
	local function thumbnail(inst, px)
		px = px or 36
		thumbCache[inst] = thumbCache[inst] or {}
		local vp = thumbCache[inst][px]
		if vp then
			return vp
		end
		vp = new("ViewportFrame", {
			Size = UDim2.fromOffset(px, px),
			BackgroundColor3 = P.raised,
			Ambient = Color3.fromRGB(170, 168, 160),
			LightColor = Color3.new(1, 1, 1),
			LightDirection = Vector3.new(-1, -2, -0.6),
		}, { corner(8), stroke(P.line) })
		pcall(function()
			local c = Engine.copyOf(inst)
			if c:IsA("BasePart") then
				local m = Instance.new("Model")
				c.Parent = m
				c = m
			end
			for _, d in c:GetDescendants() do
				if d:IsA("LuaSourceContainer") then
					d:Destroy()
				end
			end
			c.Parent = vp
			local cf, size = c:GetBoundingBox()
			local cam = new("Camera", { FieldOfView = 35, Parent = vp })
			vp.CurrentCamera = cam
			local dist = (size.Magnitude / 2) / math.tan(math.rad(17.5)) * 1.02
			cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(1, 0.6, 1).Unit * dist, cf.Position)
		end)
		thumbCache[inst][px] = vp
		return vp
	end

	-- used by later modules
	App.saveArea = saveArea
	App.canGenerate = canGenerate
	App.runGenerate = runGenerate
	App.cancelJob = cancelJob
	App.busy = busy
	App.requestLive = requestLive
	App.commit = commit
	App.applyNow = applyNow
	App.switchArea = switchArea
	App.newArea = newArea
	App.deleteArea = deleteArea
	App.thumbCache = thumbCache
	App.eachThumb = eachThumb
	App.thumbnail = thumbnail
	App.pruneThumbs = pruneThumbs
end
