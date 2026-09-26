--------------------------------------------------------------------------------
-- Scan: surface classes + distance fields
--------------------------------------------------------------------------------
function E.rayParams(extra)
	local ex = { workspace.CurrentCamera }
	local out = workspace:FindFirstChild(E.OUT)
	if out then
		table.insert(ex, out)
	end -- everything we place, including what a running generation adds
	-- (road surfaces live in their own folder, outside it: they are ground, so scans see a road and things stand on it)
	for _, e in extra or {} do
		table.insert(ex, e)
	end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = ex
	rp.RespectCanCollide = true -- leaves and decorative non-collidable parts are ignored
	return rp, ex
end

-- two-pass chamfer distance transform
local function chamfer(src, nx, nz, G)
	local N = nx * nz
	local d = table.create(N, 1e9)
	for i in src do
		d[i] = 0
	end
	local a, b = G, G * 1.41421
	for iz = 1, nz do
		for ix = 1, nx do
			local i = (iz - 1) * nx + ix
			local v = d[i]
			if ix > 1 then
				v = math.min(v, d[i - 1] + a)
			end
			if iz > 1 then
				v = math.min(v, d[i - nx] + a)
				if ix > 1 then
					v = math.min(v, d[i - nx - 1] + b)
				end
				if ix < nx then
					v = math.min(v, d[i - nx + 1] + b)
				end
			end
			d[i] = v
		end
	end
	for iz = nz, 1, -1 do
		for ix = nx, 1, -1 do
			local i = (iz - 1) * nx + ix
			local v = d[i]
			if ix < nx then
				v = math.min(v, d[i + 1] + a)
			end
			if iz < nz then
				v = math.min(v, d[i + nx] + a)
				if ix < nx then
					v = math.min(v, d[i + nx + 1] + b)
				end
				if ix > 1 then
					v = math.min(v, d[i + nx - 1] + b)
				end
			end
			d[i] = v
		end
	end
	return d
end

-- tick (optional): called as the scan runs with its progress (0-1); returning false aborts (returns nil, true)
function E.analyze(a, extra, tick)
	if a.count == 0 then
		return nil
	end
	local minCX, maxCX, minCZ, maxCZ = math.huge, -math.huge, math.huge, -math.huge
	for cz, row in a.rows do
		minCZ = math.min(minCZ, cz)
		maxCZ = math.max(maxCZ, cz)
		for cx in row do
			minCX = math.min(minCX, cx)
			maxCX = math.max(maxCX, cx)
		end
	end
	local margin = 48 -- look outside the area so nearby roads/buildings still count
	local x0, x1 = minCX * a.cell - margin, (maxCX + 1) * a.cell + margin
	local z0, z1 = minCZ * a.cell - margin, (maxCZ + 1) * a.cell + margin
	local G = 4
	while ((x1 - x0) / G) * ((z1 - z0) / G) > 90000 do
		G *= 2
	end
	local nx, nz = math.ceil((x1 - x0) / G), math.ceil((z1 - z0) / G)
	local N = nx * nz

	local rp = E.rayParams(extra)
	E.freshSurfaces()
	local zones = E.clearZones(a.folder)
	local picked = {} -- the area's own parts (Fill selected parts), and whether a hit is on one
	for _, p in a.on or {} do
		picked[p] = true
	end
	local function onPicked(inst)
		while inst and inst ~= workspace do
			if picked[inst] then
				return true
			end
			inst = inst.Parent
		end
		return false
	end
	local on = {}
	local roofMemo = {} -- part -> true when it stands well above the ground under it (a roof, a platform)
	local top, len = a.topY + 400, 1400
	local cls, ys, ny, inM = table.create(N, "None"), table.create(N, 0), table.create(N, 1), table.create(N, false)
	local stats, maskCells = {}, 0
	local down = Vector3.new(0, -len, 0)

	for iz = 1, nz do
		if tick and not tick(iz / nz) then
			return nil, true
		end
		for ix = 1, nx do
			local i = (iz - 1) * nx + ix
			local x, z = x0 + (ix - 0.5) * G, z0 + (iz - 0.5) * G
			local r = workspace:Raycast(Vector3.new(x, top, z), down, rp)
			local c = "None"
			if r then
				local explicit
				c, explicit = E.surfaceOf(r.Instance, r.Material)
				ys[i], ny[i] = r.Position.Y, r.Normal.Y
				if next(picked) and onPicked(r.Instance) then
					on[i] = true -- chosen as ground: never taken for a roof
				elseif c ~= "Water" and not explicit and r.Instance ~= workspace.Terrain then
					local p = r.Instance
					-- follow the ray down through stacked parts to the real ground;
					-- if the top surface is well above it, it's a roof / structure
					if not (p.Size.X > 80 and p.Size.Z > 80) then
						local roof = roofMemo[p]
						if roof == nil then
							local lowest, from = r.Position.Y, r.Position
							for _ = 1, 8 do
								local r2 = workspace:Raycast(from - Vector3.new(0, 0.05, 0), Vector3.new(0, -300, 0), rp)
								if not r2 then
									break
								end
								lowest = r2.Position.Y
								local q = r2.Instance
								if q == workspace.Terrain or (q.Size.X > 80 and q.Size.Z > 80) then
									break
								end
								from = r2.Position
							end
							roof = r.Position.Y - lowest > 3
							roofMemo[p] = roof
						end
						if roof then
							c = "Building"
						end
					end
				end
			end
			cls[i] = c
			local inside = E.hasCell(a, math.floor(x / a.cell), math.floor(z / a.cell)) and not E.isCleared(zones, x, z)
			inM[i] = inside
			if inside then
				stats[c] = (stats[c] or 0) + 1
				maskCells += 1
			end
		end
	end

	local function field(pred)
		local src = {}
		for i = 1, N do
			if pred(cls[i]) then
				src[i] = true
			end
		end
		return chamfer(src, nx, nz, G)
	end
	local outside = {}
	local yMin, yMax = math.huge, -math.huge
	for i = 1, N do
		if not inM[i] then
			outside[i] = true
		elseif cls[i] ~= "None" then
			yMin = math.min(yMin, ys[i])
			yMax = math.max(yMax, ys[i])
		end
	end
	return {
		x0 = x0,
		z0 = z0,
		G = G,
		nx = nx,
		nz = nz,
		top = top,
		len = len,
		rp = rp,
		cell = a.cell,
		cls = cls,
		y = ys,
		ny = ny,
		inM = inM,
		on = on,
		clear = zones,
		stats = stats,
		maskCells = maskCells,
		yMin = yMin,
		yMax = yMax,
		dist = {
			Edge = chamfer(outside, nx, nz, G),
			Buildings = field(function(c)
				return c == "Building"
			end),
			Roads = field(function(c)
				return c == "Road"
			end),
			Water = field(function(c)
				return c == "Water"
			end),
			Paths = field(function(c)
				return c == "Dirt"
			end),
		},
	}
end

function E.indexAt(an, x, z)
	local ix, iz = math.floor((x - an.x0) / an.G), math.floor((z - an.z0) / an.G)
	if ix < 0 or iz < 0 or ix >= an.nx or iz >= an.nz then
		return nil
	end
	return iz * an.nx + ix + 1
end
