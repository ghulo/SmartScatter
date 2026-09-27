--[[
	Smart Scatter — Engine/Layout: improving a finished map's layout, one kind at a time. Copies that crowd each
	other, or break the kind's placement rules (a tree on a road), move into the empty holes of the kind's
	territory; holes left over can get new copies, extras that can't move can go. Copies marked hand-placed never
	change. The rules are the plugin's own, relaxed to what the map's copies already do, so a map's style stays.
	E.relayout is the pure part (tested offline); E.layoutPlan reads the map for it, E.layoutApply carries it out.
	Adds to E (the engine API); shares internals with the other engine modules through I.
]]

return function(E, I)
	local chamfer = I.chamfer

	--------------------------------------------------------------------------------
	-- Hand-placed copies
	--------------------------------------------------------------------------------
	local HAND = "SS_HandPlaced"
	-- a copy is hand-placed when it, or anything it's in (a whole folder), is marked
	function E.isHandPlaced(inst)
		local cur = inst
		while cur and cur ~= workspace and cur ~= game do
			if cur:GetAttribute(HAND) then
				return true
			end
			cur = cur.Parent
		end
		return false
	end
	function E.setHandPlaced(list, on)
		for _, inst in list do
			inst:SetAttribute(HAND, on and true or nil)
		end
	end

	--------------------------------------------------------------------------------
	-- The spacing itself (pure: points in, what to do out)
	--------------------------------------------------------------------------------
	-- a grid of points for "what's near here", cell size `size`
	local function hashOf(size)
		local h = { size = size, cells = {}, lo = Vector3.new(math.huge, 0, math.huge), hi = Vector3.new(-math.huge, 0, -math.huge) }
		function h.add(x, z, v)
			local cx, cz = math.floor(x / size), math.floor(z / size)
			h.lo, h.hi = Vector3.new(math.min(h.lo.X, cx), 0, math.min(h.lo.Z, cz)), Vector3.new(math.max(h.hi.X, cx), 0, math.max(h.hi.Z, cz))
			local k = cx .. "," .. cz
			local c = h.cells[k]
			if not c then
				c = {}
				h.cells[k] = c
			end
			table.insert(c, { x = x, z = z, v = v })
		end
		-- the nearest point within `reach` (distance, value), or math.huge. skip: a value to pass over, or a
		-- function saying which values to pass over. Looks ring by ring outward, stopping once nothing nearer can be.
		function h.nearest(x, z, reach, skip)
			local best, bv = math.huge, nil
			local cx, cz = math.floor(x / size), math.floor(z / size)
			if h.lo.X > h.hi.X then
				return best, bv -- (nothing added yet)
			end
			-- no further than the reach, nor past the last cell anything was added to
			local span = math.max(math.abs(cx - h.lo.X), math.abs(cx - h.hi.X), math.abs(cz - h.lo.Z), math.abs(cz - h.hi.Z))
			local n = math.min(math.ceil(reach / size), span)
			local skipFn = type(skip) == "function" and skip
			for ring = 0, n do
				for dx = -ring, ring do
					for dz = -ring, ring do
						if math.max(math.abs(dx), math.abs(dz)) == ring then
							for _, p in h.cells[(cx + dx) .. "," .. (cz + dz)] or {} do
								if p.v ~= skip and not (skipFn and skipFn(p.v)) then
									local d = math.sqrt((p.x - x) ^ 2 + (p.z - z) ^ 2)
									if d < best and d <= reach then
										best, bv = d, p.v
									end
								end
							end
						end
					end
				end
				if best <= ring * size then -- every cell further out is at least this far
					break
				end
			end
			return best, bv
		end
		return h
	end

	-- how even a set of points is, 0-1: 1 when every point's nearest neighbour is equally far (a spread-out, even
	-- layout), lower the more some crowd while others stand alone
	function E.evenness(points)
		if #points < 3 then
			return 1
		end
		local near = {}
		local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
		for _, p in points do
			x0, x1, z0, z1 = math.min(x0, p.x), math.max(x1, p.x), math.min(z0, p.z), math.max(z1, p.z)
		end
		local reach = math.max(x1 - x0, z1 - z0, 1)
		local h = hashOf(math.max(reach / math.sqrt(#points), 1))
		for i, p in points do
			h.add(p.x, p.z, i)
		end
		local sum = 0
		for i, p in points do
			local d = h.nearest(p.x, p.z, reach, i)
			if d < math.huge then
				table.insert(near, d)
				sum += d
			end
		end
		if #near < 2 or sum <= 0 then
			return 1
		end
		local mean, var = sum / #near, 0
		for _, d in near do
			var += (d - mean) ^ 2
		end
		return math.clamp(1 - math.sqrt(var / #near) / mean, 0, 1)
	end

	-- the usual gap between neighbours: the median distance from each point to its nearest one
	function E.typicalSpacing(points)
		local reach = 1
		for _, p in points do
			reach = math.max(reach, math.abs(p.x - points[1].x), math.abs(p.z - points[1].z))
		end
		local h = hashOf(math.max(reach / math.sqrt(math.max(#points, 1)), 1))
		for i, p in points do
			h.add(p.x, p.z, i)
		end
		local near = {}
		for i, p in points do
			local d = h.nearest(p.x, p.z, reach * 2 + 1, i)
			if d < math.huge then
				table.insert(near, d)
			end
		end
		table.sort(near)
		return near[math.max(1, math.ceil(#near / 2))] or 0
	end

	-- Plans the spacing. points: the copies { { x, z, r (footprint radius), fixed (hand-placed), bad (breaks the
	-- rules) } }. spots: where a copy may stand, a grid of cell centres { { x, z } } `step` studs apart (the kind's
	-- territory where its rules allow it). opts: spacing (studs), crowd (a copy closer than crowd × spacing to
	-- another, or overlapping it, is crowded), gap (a spot farther than gap × spacing from every copy is a hole),
	-- step, fill (new copies for holes left over), remove (take out extras that can't move), seed.
	-- Returns { moves = { { i, x, z } }, adds = { { x, z } }, removes = { i }, crowded, bad, holes }.
	function E.relayout(points, spots, opts)
		local d = math.max(opts.spacing or 1, 0.5)
		local crowd, gap = opts.crowd or 0.5, opts.gap or 1.7
		local step = opts.step or d / 3
		local rng = Random.new(tonumber(opts.seed) or 1)
		local all = hashOf(d)
		for i, p in points do
			all.add(p.x, p.z, i)
		end
		-- 1. who stays: hand-placed copies always; then the most spread-out first, so in a crowded clump the one
		-- with the most room keeps its place and the others go into the pool
		local order = {}
		local room = {}
		for i, p in points do
			room[i] = all.nearest(p.x, p.z, d * 3, i)
			table.insert(order, i)
		end
		table.sort(order, function(a, b)
			local fa, fb = points[a].fixed and 1 or 0, points[b].fixed and 1 or 0
			if fa ~= fb then
				return fa > fb
			end
			if room[a] ~= room[b] then
				return room[a] > room[b]
			end
			return a < b
		end)
		local kept = hashOf(d)
		local pool, crowded, bad = {}, 0, 0
		local maxR = 0
		for _, p in points do
			maxR = math.max(maxR, p.r or 0)
		end
		for _, i in order do
			local p = points[i]
			if p.fixed then
				kept.add(p.x, p.z, i)
			elseif p.bad then
				bad += 1
				table.insert(pool, i)
			else
				local _, q = kept.nearest(p.x, p.z, math.max(crowd * d, ((p.r or 0) + maxR) * 0.9))
				local tooClose = false
				if q then
					local o = points[q]
					local dist = math.sqrt((o.x - p.x) ^ 2 + (o.z - p.z) ^ 2)
					tooClose = dist < math.max(crowd * d, ((p.r or 0) + (o.r or 0)) * 0.9) -- (or their footprints overlap)
				end
				if tooClose then
					crowded += 1
					table.insert(pool, i)
				else
					kept.add(p.x, p.z, i)
				end
			end
		end

		-- 2. the holes: spots far from every copy that stays, grown out to the whole hole (the room around them
		-- that's still more than most of a spacing from any copy), so a hole is filled evenly, not just its middle
		local key = function(x, z)
			return math.floor(x / step + 0.5) .. "," .. math.floor(z / step + 0.5)
		end
		local byKey, D = {}, {}
		for s, sp in spots do
			byKey[key(sp.x, sp.z)] = s
			D[s] = kept.nearest(sp.x, sp.z, gap * d + d)
		end
		local inHole, queue, holes = {}, {}, 0
		for s = 1, #spots do
			if D[s] >= gap * d and not inHole[s] then
				holes += 1
				inHole[s] = true
				table.insert(queue, s)
				while #queue > 0 do
					local c = table.remove(queue)
					local cx, cz = spots[c].x, spots[c].z
					for dx = -1, 1 do
						for dz = -1, 1 do
							local n = byKey[key(cx + dx * step, cz + dz * step)]
							if n and not inHole[n] and D[n] >= 0.75 * d then
								inHole[n] = true
								table.insert(queue, n)
							end
						end
					end
				end
			end
		end
		-- 3. fill the holes, their middles first. The typical spacing is the median gap to the nearest neighbour, so
		-- half the copies stand closer than it: a random fill matches it with gaps of about 0.85 of it, a little uneven
		-- like the rest
		local list = {}
		for s in inHole do
			table.insert(list, s)
		end
		table.sort(list, function(a, b)
			if D[a] ~= D[b] then
				return D[a] > D[b]
			end
			return a < b
		end)
		local targets = {}
		local placed = hashOf(d)
		for _, s in list do
			local sp = spots[s]
			local want = d * (0.78 + rng:NextNumber() * 0.14)
			if kept.nearest(sp.x, sp.z, want) >= want and placed.nearest(sp.x, sp.z, want) >= want then
				placed.add(sp.x, sp.z, #targets + 1)
				table.insert(targets, { x = sp.x, z = sp.z })
			end
		end

		-- 4. the pool moves into the holes, shortest moves first; what's left is added or taken out
		local usedI, usedT = {}, {}
		local out = { moves = {}, adds = {}, removes = {}, crowded = crowded, bad = bad, holes = holes }
		local function move(i, t)
			usedI[i], usedT[t] = true, true
			table.insert(out.moves, { i = i, x = targets[t].x, z = targets[t].z })
		end
		if #pool * #targets <= 200000 then -- every pairing, shortest first
			local pairsList = {}
			for _, i in pool do
				for t, tg in targets do
					table.insert(pairsList, { i = i, t = t, d = (points[i].x - tg.x) ^ 2 + (points[i].z - tg.z) ^ 2 })
				end
			end
			table.sort(pairsList, function(a, b)
				if a.d ~= b.d then
					return a.d < b.d
				end
				if a.i ~= b.i then
					return a.i < b.i
				end
				return a.t < b.t
			end)
			for _, pr in pairsList do
				if not usedI[pr.i] and not usedT[pr.t] then
					move(pr.i, pr.t)
				end
			end
		else -- a huge map: each hole takes the nearest copy still free
			local free = hashOf(d)
			for _, i in pool do
				free.add(points[i].x, points[i].z, i)
			end
			for t, tg in targets do
				local _, i = free.nearest(tg.x, tg.z, math.huge, function(v)
					return usedI[v]
				end)
				if i then
					move(i, t)
				end
			end
		end
		table.sort(out.moves, function(a, b)
			return a.i < b.i
		end)
		if opts.fill then
			for t, tg in targets do
				if not usedT[t] then
					table.insert(out.adds, { x = tg.x, z = tg.z })
				end
			end
		end
		if opts.remove then
			for _, i in pool do
				if not usedI[i] then
					table.insert(out.removes, i)
				end
			end
			table.sort(out.removes)
		end
		return out
	end

	--------------------------------------------------------------------------------
	-- Reading the map for a plan, and carrying it out
	--------------------------------------------------------------------------------
	local function boxOf(inst)
		if inst:IsA("BasePart") then
			return inst.CFrame, inst.Size
		end
		return inst:GetBoundingBox()
	end
	-- a copy's footprint: its middle on the ground plane, its radius, its underside's height and its height
	local function footOf(inst)
		local cf, size = boxOf(inst)
		local ex = math.abs(cf.RightVector.X) * size.X + math.abs(cf.UpVector.X) * size.Y + math.abs(cf.LookVector.X) * size.Z
		local ey = math.abs(cf.RightVector.Y) * size.X + math.abs(cf.UpVector.Y) * size.Y + math.abs(cf.LookVector.Y) * size.Z
		local ez = math.abs(cf.RightVector.Z) * size.X + math.abs(cf.UpVector.Z) * size.Y + math.abs(cf.LookVector.Z) * size.Z
		return { x = cf.Position.X, z = cf.Position.Z, r = math.max(ex, ez) / 2, base = cf.Position.Y - ey / 2, h = ey }
	end
	local function percentile(list, q)
		if #list == 0 then
			return nil
		end
		table.sort(list)
		return list[math.clamp(math.floor(#list * q + 0.5), 1, #list)]
	end
	local function yawOf(cf)
		local look = cf.LookVector
		return math.atan2(-look.X, -look.Z)
	end

	-- Reads the map around a kind and plans its new layout. kind: { name, copies = { { inst } } } from
	-- E.scanKinds. opts: spacing (× the kind's own typical spacing), crowd, gap, fill, remove, fixRules (move
	-- copies that break the rules), seed, tick (progress 0-1; returning false stops). Returns the plan (for
	-- E.layoutApply and a preview), or nil and why.
	function E.layoutPlan(kind, opts)
		opts = opts or {}
		local copies, insts = {}, {}
		for _, c in kind.copies do
			local inst = c.inst
			if inst.Parent and (inst:IsA("Model") or inst:IsA("BasePart")) then
				local f = footOf(inst)
				f.inst, f.fixed = inst, E.isHandPlaced(inst)
				table.insert(copies, f)
				table.insert(insts, inst)
			end
		end
		if #copies < 3 then
			return nil, "It needs at least 3 copies to see how they're spaced."
		end
		local typical = E.typicalSpacing(copies)
		local d = math.max(typical * (opts.spacing or 1), 0.5)

		-- the kind's territory: its copies, grown by a couple of spacings and shrunk back (so holes inside it and
		-- bays in its edge are in, open ground beyond it isn't), then a little margin
		local lo, hi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
		for _, c in copies do
			lo = lo:Min(Vector3.new(c.x, c.base, c.z))
			hi = hi:Max(Vector3.new(c.x, c.base + c.h, c.z))
		end
		local R = 2 * d
		local g = math.max(2, math.floor(d / 3))
		while ((hi.X - lo.X) / g + 4 * R / g) * ((hi.Z - lo.Z) / g + 4 * R / g) > 250000 do
			g *= 2
		end
		local pad = R + d
		local gx0, gz0 = math.floor((lo.X - pad) / g), math.floor((lo.Z - pad) / g)
		local nx, nz = math.floor((hi.X + pad) / g) - gx0 + 1, math.floor((hi.Z + pad) / g) - gz0 + 1
		local N = nx * nz
		local src = {}
		for _, c in copies do
			src[(math.floor(c.z / g) - gz0) * nx + (math.floor(c.x / g) - gx0) + 1] = true
		end
		local near = chamfer(src, nx, nz, g)
		local out = {}
		for i = 1, N do
			if near[i] > R then
				out[i] = true
			end
		end
		local toOut = chamfer(out, nx, nz, g)
		local closed = {}
		for i = 1, N do
			if near[i] <= R and toOut[i] >= R - g then
				closed[i] = true
			end
		end
		local toClosed = chamfer(closed, nx, nz, g)
		local rows, count = {}, 0
		for i = 1, N do
			if toClosed[i] <= 0.6 * d then
				local cx, cz = (i - 1) % nx + gx0, (i - 1) // nx + gz0
				rows[cz] = rows[cz] or {}
				rows[cz][cx] = true
				count += 1
			end
		end

		-- the ground there, read the way an area reads it (the kind's own copies left out of the rays)
		local a = { rows = rows, count = count, cell = g, topY = hi.Y + 20, edge = 0, patches = 0, size = 1, seed = 1 }
		local an, stopped = E.analyze(a, insts, opts.tick)
		if not an then
			return nil, stopped and "Stopped." or "Nothing to read there."
		end

		-- its rules: the smart defaults for what it is, relaxed to what its copies already do in this map
		local l = E.makeLayer(copies[1].inst)
		if not l then
			return nil, "This kind's model can't be read (it needs parts)."
		end
		local s = l.s
		s.useAlt, s.hug, s.slopePref, s.near = false, "None", 0, ""
		l.paint = nil
		E.heat(l, an, a) -- (works out its footprint core, which the keep-away distances add to)
		local core = l._core or 0
		local classes, slopes, roads, water, builds, n = {}, {}, {}, {}, {}, 0
		for _, c in copies do
			local i = E.indexAt(an, c.x, c.z)
			if i then
				n += 1
				local cls = an.cls[i]
				classes[cls] = (classes[cls] or 0) + 1
				table.insert(slopes, math.deg(math.acos(math.clamp(an.ny[i], -1, 1))))
				table.insert(roads, an.dist.Roads[i])
				table.insert(water, an.dist.Water[i])
				table.insert(builds, an.dist.Buildings[i])
			end
		end
		for cls, k in classes do
			-- where the copies stand is allowed; roads and buildings only when a good share of them stand there on
			-- purpose (a lamp kind), not when a few ended up there by mistake
			local share = k / math.max(n, 1)
			if cls ~= "None" and cls ~= "Water" and ((cls ~= "Road" and cls ~= "Building") and (share >= 0.03 or k >= 2) or share >= 0.3) then
				s.surfaces[cls] = true
			end
		end
		s.maxSlope = math.min(89, math.max(s.maxSlope, (percentile(slopes, 0.95) or 0) + 5))
		local function relax(key, list)
			local p = percentile(list, 0.1)
			if p then
				s[key] = math.max(0, math.min(s[key], p - core - an.G))
			end
		end
		relax("keepRoad", roads)
		relax("keepWater", water)
		relax("keepBuilding", builds)
		local suit = E.heat(l, an, a)

		-- the copies that break the rules, and the spots a copy may stand on
		for _, c in copies do
			local i = E.indexAt(an, c.x, c.z)
			c.bad = opts.fixRules ~= false and not c.fixed and i ~= nil and suit(i) <= 0
		end
		local spots = {}
		for i = 1, an.nx * an.nz do
			if an.inM[i] and suit(i) > 0 then
				local x, z = E.cellCentre(an, i)
				table.insert(spots, { x = x, z = z })
			end
		end
		local plan = E.relayout(copies, spots, {
			spacing = d,
			crowd = opts.crowd,
			gap = opts.gap,
			step = an.G,
			fill = opts.fill,
			remove = opts.remove,
			seed = opts.seed,
		})

		-- where each move and addition really stands: on the ground, clear of anything else, a spot at a time
		local rp = an.rp
		local ol = OverlapParams.new()
		ol.FilterType = Enum.RaycastFilterType.Exclude
		local offsets = {}
		for _, c in copies do
			local r = workspace:Raycast(Vector3.new(c.x, an.top, c.z), Vector3.new(0, -an.len, 0), rp)
			c.ground = r and r.Position.Y or c.base
			table.insert(offsets, math.clamp(c.base - c.ground, -c.h * 0.5, 2))
		end
		local usualSink = percentile(offsets, 0.5) or 0
		local yaws, sumC, sumS = {}, 0, 0
		for _, c in copies do
			local y = yawOf(c.inst:GetPivot())
			table.insert(yaws, y)
			sumC += math.cos(y)
			sumS += math.sin(y)
		end
		local turned = math.sqrt(sumC ^ 2 + sumS ^ 2) / #yaws < 0.8 -- the copies face every which way
		local rng = Random.new((tonumber(opts.seed) or 1) + 17)
		local function standAt(x, z, c)
			local r = workspace:Raycast(Vector3.new(x, an.top, z), Vector3.new(0, -an.len, 0), rp)
			if not r or math.deg(math.acos(math.clamp(r.Normal.Y, -1, 1))) > s.maxSlope then
				return nil
			end
			local ignore = table.clone(insts)
			table.insert(ignore, r.Instance)
			table.insert(ignore, workspace.Terrain)
			ol.FilterDescendantsInstances = ignore
			local hits = workspace:GetPartBoundsInRadius(r.Position + Vector3.new(0, c.h / 2 + 0.5, 0), math.max(c.r * 0.6, 0.5), ol)
			for _, p in hits do
				-- something is there already (a rock, a bench, a wall); a flower or a tuft of grass doesn't count
				if p.CanCollide or (p.Transparency < 1 and math.max(p.Size.X, p.Size.Y, p.Size.Z) > c.r * 0.5) then
					return nil
				end
			end
			return r.Position.Y
		end
		local result = {
			kind = kind.name,
			spacing = d,
			typical = typical,
			moves = {},
			adds = {},
			removes = {},
			crowded = plan.crowded,
			bad = plan.bad,
			holes = plan.holes,
		}
		local final = {}
		local moved, gone = {}, {}
		for _, mv in plan.moves do
			local c = copies[mv.i]
			local y = standAt(mv.x, mv.z, c)
			if y then
				-- how deep it sits in the ground goes with it; for one breaking the rules its own reading isn't to be
				-- trusted (standing on a road part, say), so it takes the kind's usual depth
				local offset = c.bad and usualSink or math.clamp(c.base - c.ground, -c.h * 0.5, 2)
				local shift = Vector3.new(mv.x - c.x, y + offset - c.base, mv.z - c.z)
				table.insert(
					result.moves,
					{ inst = c.inst, cf = c.inst:GetPivot() + shift, from = Vector3.new(c.x, c.base, c.z), to = Vector3.new(mv.x, y, mv.z) }
				)
				moved[mv.i] = true
				table.insert(final, { x = mv.x, z = mv.z })
			end
		end
		for _, i in plan.removes do
			gone[i] = true
			table.insert(result.removes, copies[i].inst)
		end
		for i, c in copies do
			if not moved[i] and not gone[i] then
				table.insert(final, { x = c.x, z = c.z })
			end
		end
		local sources = {}
		for _, c in copies do
			if not c.fixed and not c.bad then
				table.insert(sources, c)
			end
		end
		if #sources == 0 then
			sources = copies
		end
		for _, ad in plan.adds do
			local c = sources[rng:NextInteger(1, #sources)]
			local y = standAt(ad.x, ad.z, c)
			if y then
				local pivot = c.inst:GetPivot()
				local turn = turned and CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0) or CFrame.identity
				local rot = turn * pivot.Rotation
				-- where its pivot sits against its footprint, turned with it, then lifted onto the ground
				local rel = pivot.Position - Vector3.new(c.x, c.base, c.z)
				local at = Vector3.new(ad.x, y + usualSink, ad.z) + turn:VectorToWorldSpace(rel)
				table.insert(result.adds, { src = c.inst, cf = CFrame.new(at) * rot, to = Vector3.new(ad.x, y, ad.z) })
				table.insert(final, { x = ad.x, z = ad.z })
			end
		end
		result.evenBefore = E.evenness(copies)
		result.evenAfter = E.evenness(final)
		return result
	end

	-- Carries out a plan: moves, additions and removals as one change, every touched copy kept in the snapshot
	-- first (Restore original puts the map back as it was). Returns the copies added.
	function E.layoutApply(plan)
		local keep = {}
		for _, mv in plan.moves do
			table.insert(keep, mv.inst)
		end
		for _, inst in plan.removes do
			table.insert(keep, inst)
		end
		E.snapshot(keep)
		for _, mv in plan.moves do
			if mv.inst.Parent then
				mv.inst:PivotTo(mv.cf)
				E.snapshotChanged(mv.inst)
			end
		end
		local added = {}
		for _, ad in plan.adds do
			if ad.src.Parent then
				local new = E.copyOf(ad.src)
				if new then
					new:SetAttribute(HAND, nil)
					new:PivotTo(ad.cf)
					new.Parent = ad.src.Parent
					E.snapshotAdded(new)
					table.insert(added, new)
				end
			end
		end
		for _, inst in plan.removes do
			if inst.Parent then
				E.snapshotChanged(inst, false)
				inst:Destroy()
			end
		end
		return added
	end
end
