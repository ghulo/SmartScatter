--[[
	Smart Scatter — Engine/Generate: rebuilds an area's objects (whole, from a layer on, or one painted patch).
	Adds to E (the engine API); shares internals with the other engine modules through I.
]]

return function(E, I)
	local CollectionService = game:GetService("CollectionService")
	local CORE = I.CORE
	local Hash = I.Hash
	local before = I.before
	local groupId = I.groupId
	local growGroup = I.growGroup
	local place = I.place
	local placeLine = I.placeLine

	-- Regenerates the area. Each layer has its own seeded randomness, so changing one layer never reshuffles
	-- another. opts.from = a layer: keep every layer placed before it untouched and only rebuild it + later ones.
	-- Locked layers are always kept. opts.region = { x0, z0, x1, z1 } (world studs): only that patch changed (a brush
	-- stroke), so every other layer keeps its copies outside it and only the patch is placed again.
	-- Returns { [layer] = count }, total.
	local function itemOf(inst)
		return {
			x = inst:GetAttribute("SS_X") or 0,
			z = inst:GetAttribute("SS_Z") or 0,
			r = inst:GetAttribute("SS_R") or 1,
			type = inst:GetAttribute("SS_Type"),
			sp = inst:GetAttribute("SS_Sp") or 1,
			cs = inst:GetAttribute("SS_Cs") or 1,
			g = inst:GetAttribute("SS_G"),
			lk = inst:GetAttribute("SS_L"),
		}
	end

	-- Output never enters Studio's undo history. Every regeneration would otherwise put a full copy of the old objects
	-- there (a big area on Live update: thousands of parts per stroke, gigabytes after a while, until Studio froze).
	-- Changes to an instance that isn't Archivable aren't recorded, so output is built hidden, shown once it's in
	-- place (it saves with the place like anything else) and hidden again before it's removed. Undo and redo restore
	-- the area's saved state, and the plugin rebuilds the objects from it.
	local function hide(inst)
		inst.Archivable = false
	end
	local function show(inst)
		inst.Archivable = true
	end
	local function drop(inst)
		inst.Archivable = false
		inst:Destroy()
	end
	E.dropOutput = drop

	-- The new output is built off-screen (unparented folders) and swapped in when complete, so the old result stays
	-- on screen until then and a cancelled run changes nothing. opts.tick(progress 0-1) -> false cancels (returns nil).
	function E.generate(a, an, density, extra, opts)
		opts = opts or {}
		E.freshSurfaces()
		E.ensureFolder(a)
		local plans = E.plan(a.layers, an, density, a)
		local ctx = {
			an = an,
			area = a,
			seed = a.seed,
			hash = Hash.new(),
			parts = 0,
			clear = an and an.clear or E.clearZones(a.folder),
			output = opts.output or { walk = true, shadows = true, query = true, chunks = false },
		}
		if a.spline then
			local rp = (E.rayParams(extra))
			-- the road surface is rebuilt from the curve (the old one goes first, so nothing snaps onto it)
			local stray = a.folder:FindFirstChild("Surface") -- 7.2-7.5 kept it inside the area
			if stray then
				drop(stray)
			end
			local oldSurface = E.roadOf(a)
			if not opts.from or not oldSurface then
				if oldSurface then -- set aside, not destroyed: a cancelled run puts it back
					ctx.oldSurface, ctx.oldSurfaceParent = oldSurface, oldSurface.Parent
					hide(oldSurface)
					oldSurface.Parent = nil
				end
				local surface = E.buildSurface(a, rp)
				ctx.newSurface = surface
				if surface then
					local roads = workspace:FindFirstChild(E.ROADS)
					if not roads then
						roads = Instance.new("Folder")
						roads.Name = E.ROADS
						roads.Parent = workspace
					end
					surface.Name = a.folder.Name
					local link = Instance.new("ObjectValue")
					link.Name = "Area"
					link.Value = a.folder
					link.Parent = surface
					hide(surface)
					surface.Parent = roads
				end
			end
			ctx.splines = {}
			local curves = E.splineCurves(a.spline)
			for _, cv in curves do
				local smp = E.splineSamples(cv, rp)
				-- joints: sharp points, and points shared with another curve or another stretch (junctions, closed ends)
				smp.joints = {}
				local raw = E.splineCurve(cv, 0.75) -- unsnapped samples, same indexing, to find where each point lies
				for i, q in cv.pts do
					local shared = q.sharp
					if not shared then
						for _, o in curves do
							for j, r in o.pts do
								if not (o.pts == cv.pts and j == i) and (r.p - q.p).Magnitude < 0.05 then
									shared = true
									break
								end
							end
							if shared then
								break
							end
						end
					end
					if shared then
						local best, bk = math.huge, nil
						for k, p in raw do
							local d = (p - q.p).Magnitude
							if d < best then
								best, bk = d, k
							end
						end
						if bk and best < 1 then
							table.insert(smp.joints, bk)
						end
					end
				end
				table.insert(ctx.splines, smp)
			end
		end

		-- other areas' objects still count for spacing
		for _, inst in CollectionService:GetTagged(E.TAG) do
			if
				inst:IsDescendantOf(workspace)
				and not inst:IsDescendantOf(a.folder)
				and CORE[inst:GetAttribute("SS_Type")]
				and not inst:GetAttribute("SS_Stacked")
			then
				ctx.hash:add(itemOf(inst))
			end
		end

		-- which layers can stay as they are
		local keep = {}
		for _, p in plans do
			local l = p.layer
			if l.s.locked or (opts.from and l ~= opts.from and before(l, opts.from)) then
				keep[E.layerKey(l)] = l
			end
		end
		local folders, counts, total = {}, {}, 0
		local stale, staged = {}, {}
		-- a patch rebuild: the layers being rebuilt keep what's outside the patch (their folder stays; new copies are
		-- merged in at the swap). Streaming chunks group copies by position, so those areas rebuild whole.
		local R = not ctx.output.chunks and opts.region or nil
		if R then -- grown by what reaches across its border: the soft edge and the widest spacing
			local pad = a.edge or 0
			for _, p in plans do
				pad = math.max(pad, (a.edge or 0) + (p.layer._r or 0) * p.layer.s.spacing * 2)
			end
			R = { R[1] - pad, R[2] - pad, R[3] + pad, R[4] + pad }
		end
		local function inPatch(x, z)
			return x >= R[1] and x <= R[3] and z >= R[2] and z <= R[4]
		end
		local partial, cut = {}, {} -- [layer] = its existing folder · copies inside the patch, dropped at the swap
		if R then
			for _, p in plans do
				if not p.line and not keep[E.layerKey(p.layer)] then
					partial[E.layerKey(p.layer)] = p.layer
				end
			end
		end
		for _, f in a.folder:GetChildren() do
			if f:GetAttribute("SS_Surface") then
				continue
			end -- the road surface is managed above
			local key = f:GetAttribute("SS_Key") or ""
			local pl = partial[key]
			if pl and not partial[pl] then
				partial[pl] = f
				local n = 0
				for _, inst in f:GetDescendants() do
					if not CORE[inst:GetAttribute("SS_Type")] then
						continue
					end
					local it = itemOf(inst)
					if inPatch(it.x, it.z) then
						table.insert(cut, inst)
					else
						if not inst:GetAttribute("SS_Stacked") then
							ctx.hash:add(it)
						end
						for _, d in inst:GetDescendants() do
							if d:IsA("BasePart") then
								ctx.parts += 1
							end
						end
						n += 1
					end
				end
				counts[pl] = n
				continue
			end
			local l = keep[key]
			if l and not folders[l] then
				folders[l] = f
				local n = 0
				for _, inst in f:GetDescendants() do
					if inst:IsA("BasePart") then
						ctx.parts += 1
					end
					if CORE[inst:GetAttribute("SS_Type")] then
						if not inst:GetAttribute("SS_Stacked") then
							ctx.hash:add(itemOf(inst))
						end
						n += 1
					end
				end
				counts[l] = n
				total += n
			else
				table.insert(stale, f)
			end
		end

		local _, ex = E.rayParams(extra)
		table.insert(ex, workspace.Terrain)
		ctx.op = OverlapParams.new()
		ctx.op.FilterType = Enum.RaycastFilterType.Exclude
		ctx.op.FilterDescendantsInstances = ex
		ctx.op.RespectCanCollide = true

		local function folderFor(l)
			local f = folders[l]
			if not f then
				f = Instance.new("Folder")
				hide(f)
				f.Name = l.inst.Name
				f:SetAttribute("SS_Key", E.layerKey(l))
				folders[l] = f
				table.insert(staged, f)
			end
			return f
		end
		-- streaming chunks: 128-stud Models that stream in and out as one piece
		local chunks = {}
		ctx.parentFor = function(l, x, z)
			local f = folderFor(l)
			if not ctx.output.chunks then
				return f
			end
			local key = math.floor(x / 128) .. "," .. math.floor(z / 128)
			chunks[f] = chunks[f] or {}
			local c = chunks[f][key]
			if not c then
				c = Instance.new("Model")
				c.Name = "Chunk " .. key
				pcall(function()
					c.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
				end)
				pcall(function()
					c.LevelOfDetail = Enum.ModelLevelOfDetail.StreamingMesh
				end)
				c.Parent = f
				chunks[f][key] = c
			end
			return c
		end

		-- progress and cancellation
		local function rebuilt(l) -- placed this run (in full, or in the patch)
			return not counts[l] or partial[l] ~= nil
		end
		local work, base = 0, 0
		for _, p in plans do
			if rebuilt(p.layer) then
				work += p.line and 40 or math.max(p.n, 1)
			end
		end
		local tick, cur = opts.tick, 0
		ctx.alive = function()
			if ctx.aborted then
				return false
			end
			if tick and not tick(math.clamp((base + cur) / math.max(work, 1), 0, 1)) then
				ctx.aborted = true
			end
			return not ctx.aborted
		end

		for _, p in plans do
			if ctx.aborted then
				break
			end
			local l = p.layer
			if rebuilt(l) then
				cur = 0
				local rng = Random.new((a.seed * 7919 + l._h + (tonumber(l.s.seed) or 0) * 104729) % 2147483647)
				if partial[l] then -- only the patch's candidates, and its share of the count
					local cand, scores, all, part = {}, {}, 0, 0
					for k, i in p.cand do
						all += p.scores[k]
						if inPatch(E.cellCentre(an, i)) then
							table.insert(cand, i)
							table.insert(scores, p.scores[k])
							part += p.scores[k]
						end
					end
					p = { layer = l, cand = cand, scores = scores, n = all > 0 and p.n * part / all or 0 }
				end
				local n = p.line and 0 or math.floor(p.n) + ((rng:NextNumber() < p.n % 1) and 1 or 0)
				local got, t = 0, 0
				if p.line then
					got = placeLine(ctx, l, rng)
				elseif #p.cand > 0 then
					local grouped = l.s.groups
					local gmin = math.max(1, math.floor(math.min(l.s.groupMin, l.s.groupMax)))
					local gmax = math.max(gmin, math.floor(math.max(l.s.groupMin, l.s.groupMax)))
					local gnext = 0
					while got < n and t < n * 14 + 30 do -- plenty of attempts so tight rules still reach the target count
						t += 1
						cur = got
						if not ctx.alive() then
							break
						end
						local k = rng:NextInteger(1, #p.cand)
						if rng:NextNumber() <= p.scores[k] then
							local gid
							if grouped then
								gnext += 1
								gid = groupId(l, gnext)
							end
							local lead = place(ctx, l, p.cand[k], rng, gid)
							if lead then
								got += 1
								if grouped then
									got += growGroup(ctx, l, lead, gid, math.min(rng:NextInteger(gmin, gmax) - 1, n - got), rng)
								end
							end
						end
					end
				end
				counts[l] = (partial[l] and counts[l] or 0) + got
				total += counts[l]
				base += p.line and 40 or math.max(p.n, 1)
			end
		end
		if ctx.aborted then
			for _, f in staged do
				f:Destroy()
			end
			if ctx.newSurface then
				drop(ctx.newSurface)
			end
			if ctx.oldSurface then
				ctx.oldSurface.Parent = ctx.oldSurfaceParent
				show(ctx.oldSurface)
			end
			return nil
		end
		-- copies removed by hand stay gone. They're taken out after everything is placed, not skipped while placing:
		-- skipping would change the random draws of every copy after them, and the rest of the layout would move.
		if next(a.removed or {}) then
			for _, f in staged do
				for _, inst in f:GetDescendants() do
					local h = inst:GetAttribute("SS_L")
					if h and E.removedAt(a, h, inst:GetAttribute("SS_X") or 0, inst:GetAttribute("SS_Z") or 0) then
						for l, n in counts do
							if l._h == h then
								counts[l] = n - 1
							end
						end
						total -= 1
						inst:Destroy()
					end
				end
			end
		end
		if ctx.oldSurface then
			drop(ctx.oldSurface)
		end
		if ctx.newSurface then
			show(ctx.newSurface)
			-- a new road clears what other areas placed on it (their next run sees the road and keeps off it)
			local onRoad = E.roadTest(a, (E.rayParams(extra)))
			for _, inst in CollectionService:GetTagged(E.TAG) do
				if
					inst.Parent
					and CORE[inst:GetAttribute("SS_Type")]
					and not inst:IsDescendantOf(a.folder)
					and inst:IsDescendantOf(E.getOut())
					and onRoad(inst:GetAttribute("SS_X") or 0, inst:GetAttribute("SS_Z") or 0)
				then
					drop(inst)
				end
			end
		end
		-- swap: one frame, no half-built states
		for _, f in stale do
			drop(f)
		end
		for _, inst in cut do
			if inst.Parent then -- a copy nested in another cut copy already went with it
				drop(inst)
			end
		end
		for _, f in staged do
			local pl = partial[f:GetAttribute("SS_Key") or ""]
			local into = pl and partial[pl]
			if into then -- a patch: its copies join the layer's folder, each shown once it's in place
				for _, inst in f:GetChildren() do
					hide(inst)
					inst.Parent = into
					show(inst)
				end
				f:Destroy()
			else
				f.Parent = a.folder
				show(f)
			end
		end
		return counts, total, ctx.parts
	end
end
