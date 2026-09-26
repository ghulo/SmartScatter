--------------------------------------------------------------------------------
-- Rules → suitability → counts
--------------------------------------------------------------------------------
local scaleRange -- (defined just below; placement and lines use it too)
-- a layer's size range, times the area's "Size of everything" (set on the layer by E.plan)
scaleRange = function(l)
	local s, k = l.s, l._size or 1
	return math.min(s.scaleMin, s.scaleMax) * k, math.max(s.scaleMin, s.scaleMax) * k
end

local function prep(l)
	local lo, hi = scaleRange(l)
	local avg = (lo + hi) / 2
	local wsum, rsum = 0, 0
	for _, v in l.variants do
		if v.w > 0 then wsum += v.w; rsum += v.w * v.m.radius * v.size end
	end
	l._r = (wsum > 0 and rsum / wsum or l.m.radius) * avg
	l._core = l._r * CORE[l.type]
	l._wsum = wsum
end

local function score(l, an, i)
	local s, c = l.s, an.cls[i]
	if not s.surfaces[c] and not an.on[i] then return 0 end -- parts picked for the area take anything
	if math.deg(math.acos(math.clamp(an.ny[i], -1, 1))) > s.maxSlope then return 0 end
	if s.useAlt and an.yMax - an.yMin > 1 then
		local t = (an.y[i] - an.yMin) / (an.yMax - an.yMin)
		if t < math.min(s.altMin, s.altMax) or t > math.max(s.altMin, s.altMax) then return 0 end
	end
	local d, cr = an.dist, l._core
	local kB, kR, kW = s.keepBuilding + cr, s.keepRoad + cr, s.keepWater + cr
	if d.Buildings[i] < kB then return 0 end
	if not s.surfaces.Road and d.Roads[i] < kR then return 0 end
	if d.Water[i] < kW then return 0 end
	if s.hug == "None" or not d[s.hug] then return 1 end
	local base = (s.hug == "Buildings" and kB) or (s.hug == "Roads" and kR) or (s.hug == "Water" and kW) or 0
	local near = math.clamp(1 - math.max(d[s.hug][i] - base, 0) / math.max(s.hugRange, 1), 0, 1)
	return (1 - s.hugStrength) + s.hugStrength * near
end

local function isLine(l) return l.s.place == "Along" end
E.isLine = isLine
-- lines claim their spot early (lamps along a road go in before the forest), buildings still come first
local function prio(l) return (isLine(l) and l.type ~= "Building") and 1.5 or PRIORITY[l.type] end
local function before(a, b) -- placement order: big categories first, then bigger assets, then stable by key
	if prio(a) ~= prio(b) then return prio(a) < prio(b) end
	if a.type ~= b.type then return PRIORITY[a.type] < PRIORITY[b.type] end
	if math.abs(a.m.radius - b.m.radius) > 1e-3 then return a.m.radius > b.m.radius end
	return E.layerKey(a) < E.layerKey(b)
end

local function ordered(layers)
	local t = {}
	for _, l in layers do
		local weight = 0
		for _, v in l.variants do weight += math.max(v.w, 0) end
		if l.s.enabled and l.s.density > 0 and l.inst.Parent and weight > 0 then -- all shares at 0: places nothing
			l._h = strHash(l.s.key ~= "" and l.s.key or E.layerKey(l))
			table.insert(t, l)
		end
	end
	table.sort(t, before)
	return t
end

-- size: the area's "Size of everything" multiplier (1 when left out)
function E.plan(layers, an, density, edge, size)
	local list = ordered(layers)
	for _, l in list do l._size = size or 1 end
	local perType = {}
	for _, l in list do if not isLine(l) then perType[l.type] = (perType[l.type] or 0) + 1 end end
	local plans = {}
	for _, l in list do
		prep(l)
		if isLine(l) or not an then table.insert(plans, { layer = l, line = true }); continue end -- no painted area: everything follows the spline
		local cand, scores, sum = {}, {}, 0
		for i = 1, an.nx * an.nz do
			if an.inM[i] then
				local sc = score(l, an, i)
				if sc > 0 and edge and edge > 0 then -- soft falloff toward the painted border
					sc *= math.clamp((an.dist.Edge[i] - an.G * 0.5) / edge, 0, 1)
				end
				if sc > 0 and l.paint then
					local gx, gz = (i - 1) % an.nx, (i - 1) // an.nx
					sc *= E.paintValue(l, math.floor((an.x0 + (gx + 0.5) * an.G) / an.cell), math.floor((an.z0 + (gz + 0.5) * an.G) / an.cell))
				end
				if sc > 0 then table.insert(cand, i); table.insert(scores, sc); sum += sc end
			end
		end
		if (l._wsum or 0) <= 0 then sum = 0 end
		local r = math.max(l._r * l.s.spacing * (l.s.groups and math.max(l.s.tight, 0.9) * 0.55 or 1), MIN_COUNT_R)
		local n = sum * an.G * an.G * COVERAGE[l.type] * l.s.density * density / perType[l.type] / (math.pi * r * r)
		n = math.min(n, 5000)
		if l.s.maxCount > 0 then n = math.min(n, l.s.maxCount) end
		table.insert(plans, { layer = l, cand = cand, scores = scores, n = n })
	end
	return plans
end


-- How heavy a run would be, before placing anything: roughly how many copies and parts. Live update checks this so a
-- huge area can't stall Studio.
function E.estimate(a, an, density)
	local copies, parts = 0, 0
	for _, p in E.plan(a.layers, an, density, a.edge, a.size) do
		if not p.line then
			local wsum, psum = 0, 0
			for _, v in p.layer.variants do
				wsum += v.w
				psum += v.w * #v.m.parts
			end
			local each = wsum > 0 and psum / wsum or 1
			copies += p.n
			parts += p.n * each
		end
	end
	return math.floor(copies), math.floor(parts)
end
