-- Regenerates the area. Each layer has its own seeded randomness, so changing one layer never reshuffles
-- another. opts.from = a layer: keep every layer placed before it untouched and only rebuild it + later ones.
-- Locked layers are always kept.
-- Returns { [layer] = count }, total.
local function itemOf(inst)
	return { x = inst:GetAttribute("SS_X") or 0, z = inst:GetAttribute("SS_Z") or 0, r = inst:GetAttribute("SS_R") or 1,
		type = inst:GetAttribute("SS_Type"), sp = inst:GetAttribute("SS_Sp") or 1, cs = inst:GetAttribute("SS_Cs") or 1,
		g = inst:GetAttribute("SS_G") }
end

-- Output never enters Studio's undo history. Every regeneration would otherwise put a full copy of the old objects
-- there (a big area on Live update: thousands of parts per stroke, gigabytes after a while, until Studio froze).
-- Changes to an instance that isn't Archivable aren't recorded, so output is built hidden, shown once it's in
-- place (it saves with the place like anything else) and hidden again before it's removed. Undo and redo restore
-- the area's saved state, and the plugin rebuilds the objects from it.
local function hide(inst) inst.Archivable = false end
local function show(inst) inst.Archivable = true end
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
	local plans = E.plan(a.layers, an, density, a.edge, a.size)
	local ctx = { an = an, seed = a.seed, hash = Hash.new(), parts = 0, clear = an and an.clear or E.clearZones(a.folder),
		output = opts.output or { walk = true, shadows = true, query = true, chunks = false } }
	if a.spline then
		local rp = (E.rayParams(extra))
		-- the road surface is rebuilt from the curve (the old one goes first, so nothing snaps onto it)
		local stray = a.folder:FindFirstChild("Surface") -- 7.2-7.5 kept it inside the area
		if stray then drop(stray) end
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
						if shared then break end
					end
				end
				if shared then
					local best, bk = math.huge, nil
					for k, p in raw do
						local d = (p - q.p).Magnitude
						if d < best then best, bk = d, k end
					end
					if bk and best < 1 then table.insert(smp.joints, bk) end
				end
			end
			table.insert(ctx.splines, smp)
		end
	end

	-- other areas' objects still count for spacing
	for _, inst in CollectionService:GetTagged(E.TAG) do
		if inst:IsDescendantOf(workspace) and not inst:IsDescendantOf(a.folder) and CORE[inst:GetAttribute("SS_Type")]
			and not inst:GetAttribute("SS_Stacked") then
			ctx.hash:add(itemOf(inst))
		end
	end

	-- which layers can stay as they are
	local keep = {}
	for _, p in plans do
		local l = p.layer
		if l.s.locked or (opts.from and l ~= opts.from and before(l, opts.from)) then keep[E.layerKey(l)] = l end
	end
	local folders, counts, total = {}, {}, 0
	local stale, staged = {}, {}
	for _, f in a.folder:GetChildren() do
		if f:GetAttribute("SS_Surface") then continue end -- the road surface is managed above
		local l = keep[f:GetAttribute("SS_Key") or ""]
		if l and not folders[l] then
			folders[l] = f
			local n = 0
			for _, inst in f:GetDescendants() do
				if inst:IsA("BasePart") then ctx.parts += 1 end
				if CORE[inst:GetAttribute("SS_Type")] then
					if not inst:GetAttribute("SS_Stacked") then ctx.hash:add(itemOf(inst)) end
					n += 1
				end
			end
			counts[l] = n; total += n
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
		if not ctx.output.chunks then return f end
		local key = math.floor(x / 128) .. "," .. math.floor(z / 128)
		chunks[f] = chunks[f] or {}
		local c = chunks[f][key]
		if not c then
			c = Instance.new("Model")
			c.Name = "Chunk " .. key
			pcall(function() c.ModelStreamingMode = Enum.ModelStreamingMode.Atomic end)
			pcall(function() c.LevelOfDetail = Enum.ModelLevelOfDetail.StreamingMesh end)
			c.Parent = f
			chunks[f][key] = c
		end
		return c
	end

	-- progress and cancellation
	local work, base = 0, 0
	for _, p in plans do
		if not counts[p.layer] then work += p.line and 40 or math.max(p.n, 1) end
	end
	local tick, cur = opts.tick, 0
	ctx.alive = function()
		if ctx.aborted then return false end
		if tick and not tick(math.clamp((base + cur) / math.max(work, 1), 0, 1)) then ctx.aborted = true end
		return not ctx.aborted
	end

	for _, p in plans do
		if ctx.aborted then break end
		local l = p.layer
		if not counts[l] then
			cur = 0
			local rng = Random.new((a.seed * 7919 + l._h + (tonumber(l.s.seed) or 0) * 104729) % 2147483647)
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
					if not ctx.alive() then break end
					local k = rng:NextInteger(1, #p.cand)
					if rng:NextNumber() <= p.scores[k] then
						local gid
						if grouped then gnext += 1; gid = groupId(l, gnext) end
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
			counts[l] = got
			total += got
			base += p.line and 40 or math.max(p.n, 1)
		end
	end
	if ctx.aborted then
		for _, f in staged do f:Destroy() end
		if ctx.newSurface then drop(ctx.newSurface) end
		if ctx.oldSurface then
			ctx.oldSurface.Parent = ctx.oldSurfaceParent
			show(ctx.oldSurface)
		end
		return nil
	end
	if ctx.oldSurface then drop(ctx.oldSurface) end
	if ctx.newSurface then show(ctx.newSurface) end
	-- swap: one frame, no half-built states
	for _, f in stale do drop(f) end
	for _, f in staged do
		f.Parent = a.folder
		show(f)
	end
	return counts, total, ctx.parts
end

return E

