--[[
	Smart Scatter — Engine/Scan: Surface classes and the scan: what each ground cell is, and distance fields to roads, water and buildings.
	Adds to E (the engine API); shares internals with the other engine modules through I.
]]

return function(E, I)
	local HttpService = game:GetService("HttpService")

	--------------------------------------------------------------------------------
	-- Surface classes
	--------------------------------------------------------------------------------
	E.CLASSES = { "Grass", "Dirt", "Road", "Rock", "Sand", "Snow", "Generic", "Water", "Building" }
	E.SURFACES = { "Grass", "Dirt", "Road", "Rock", "Sand", "Snow", "Generic" } -- placeable ones
	E.CLASS_COLOR = {
		Grass = Color3.fromRGB(90, 200, 90),
		Dirt = Color3.fromRGB(176, 124, 70),
		Road = Color3.fromRGB(70, 70, 82),
		Rock = Color3.fromRGB(150, 150, 162),
		Sand = Color3.fromRGB(232, 212, 140),
		Snow = Color3.fromRGB(235, 242, 255),
		Generic = Color3.fromRGB(110, 165, 235),
		Water = Color3.fromRGB(50, 120, 255),
		Building = Color3.fromRGB(235, 70, 70),
		None = Color3.fromRGB(0, 0, 0),
	}

	local MAT_CLASS = {}
	local function mats(names, cls)
		for _, n in names do
			local ok, m = pcall(function()
				return Enum.Material[n]
			end)
			if ok and m then
				MAT_CLASS[m] = cls
			end
		end
	end
	mats({ "Grass", "LeafyGrass" }, "Grass")
	mats({ "Ground", "Mud", "Pebble" }, "Dirt")
	mats({
		"Asphalt",
		"Concrete",
		"Pavement",
		"Cobblestone",
		"Brick",
		"CeramicTiles",
		"Marble",
		"DiamondPlate",
		"Metal",
		"CorrodedMetal",
		"WoodPlanks",
		"ClayRoofTiles",
		"RoofShingles",
		"Plaster",
		"Carpet",
		"Rubber",
		"Cardboard",
	}, "Road")
	mats({ "Rock", "Slate", "Basalt", "Granite", "Limestone", "Sandstone", "CrackedLava" }, "Rock")
	mats({ "Sand", "Salt" }, "Sand")
	mats({ "Snow", "Ice", "Glacier" }, "Snow")
	mats({ "Water" }, "Water")
	function E.classOf(mat)
		return MAT_CLASS[mat] or "Generic"
	end

	--------------------------------------------------------------------------------
	-- Surface recognition for parts & meshes. Checked in order, first match wins:
	--   1. a mark on the part or any parent model/folder (attribute SS_Surface, set by "Mark selected as")
	--   2. a taught mesh (every copy of that MeshId)
	--   3. words in the part / parent names, or the MaterialVariant name
	--   4. the material
	--------------------------------------------------------------------------------
	local VALID = {}
	for _, c in E.CLASSES do
		VALID[c] = true
	end
	VALID.Path = true -- "Path" (a mark, or a name like "Trail") is the engine's "Dirt" class; see E.surfaceOf
	local WORDS = {
		{ "Water", { "water", "river", "lake", "pond", "ocean", "stream", "puddle" } },
		{ "Road", { "road", "street", "sidewalk", "pavement", "asphalt", "highway", "crosswalk", "parking", "driveway", "curb", "kerb" } },
		{ "Path", { "path", "trail", "footpath", "dirt" } },
		{
			"Building",
			{ "house", "building", "wall", "roof", "fence", "hut", "cabin", "shop", "tower", "barn", "shed", "castle", "church", "cottage" },
		},
		{ "Grass", { "grass", "lawn", "meadow" } },
		{ "Sand", { "sand", "beach" } },
		{ "Rock", { "cliff", "rock", "stone", "boulder" } },
	}
	-- Names are matched word by word: "PineTree", "pine_tree" and "Pine Trees" all hold "pine" and "tree", while
	-- "Campfire" holds no "fir" and "Trail" no "rail". A joined word also matches when it's a keyword plus another
	-- keyword ("pinetree", "oaktree") or when the keyword is long enough to be unmistakable (5+ letters: "stonewall").
	local function nameWords(name)
		name = string.gsub(name, "(%l)(%u)", "%1 %2") -- camelCase
		name = string.gsub(name, "(%a)(%d)", "%1 %2")
		local list = {}
		for w in string.gmatch(string.lower(name), "%a+") do
			table.insert(list, w)
		end
		return list, " " .. table.concat(list, " ") .. " "
	end
	local function hasKeyword(name, keywords)
		local list, joined = nameWords(name)
		for _, kw in keywords do
			if string.find(kw, " ", 1, true) then -- several words: they must follow each other
				if string.find(joined, " " .. kw .. " ", 1, true) then
					return true
				end
			else
				for _, w in list do
					if w == kw or w == kw .. "s" or w == kw .. "es" then
						return true
					end
					local head, tail = string.sub(w, 1, #kw) == kw, string.sub(w, -#kw) == kw
					if #w > #kw and (head or tail) then
						if #kw >= 5 or table.find(keywords, head and string.sub(w, #kw + 1) or string.sub(w, 1, #w - #kw)) then
							return true
						end
					end
				end
			end
		end
		return false
	end
	local function wordClass(name)
		for _, pair in WORDS do
			if hasKeyword(name, pair[2]) then
				return pair[1]
			end
		end
		return nil
	end

	local meshMap = {}
	function E.loadMeshMap()
		local out = workspace:FindFirstChild(E.OUT)
		local ok, data = pcall(HttpService.JSONDecode, HttpService, out and out:GetAttribute("SS_MeshMap") or "{}")
		meshMap = (ok and type(data) == "table") and data or {}
		return meshMap
	end
	function E.teachMesh(meshId, cls)
		if not meshId or meshId == "" then
			return
		end
		E.loadMeshMap()
		meshMap[meshId] = cls
		E.getOut():SetAttribute("SS_MeshMap", HttpService:JSONEncode(meshMap))
	end

	-- returns class, explicit (explicit = the user or a name said so; skips the "sticks up = building" guess)
	-- Parts are remembered (thousands of rays hit the same few parts) until E.freshSurfaces(), which every scan,
	-- generation and mark calls, so marks, renames and mesh lessons are picked up by the next run. Weak keys: a
	-- deleted part isn't kept alive by the memo.
	local surfMemo = setmetatable({}, { __mode = "k" })
	function E.freshSurfaces()
		surfMemo = setmetatable({}, { __mode = "k" })
		E.loadMeshMap()
	end
	local surfaceOfUncached
	function E.surfaceOf(inst, material)
		if inst == workspace.Terrain then
			return E.classOf(material), false
		end
		local hit = surfMemo[inst]
		if hit and hit[3] == material then
			return hit[1], hit[2]
		end
		local c, explicit = surfaceOfUncached(inst, material)
		if c == "Path" then
			c = "Dirt"
		end -- paths are the Dirt class everywhere (fields, filters, "Follow Paths")
		surfMemo[inst] = { c, explicit, material }
		return c, explicit
	end
	function surfaceOfUncached(inst, material)
		local cur = inst
		while cur and cur ~= workspace do
			local m = cur:GetAttribute("SS_Surface")
			if m and VALID[m] then
				return m, true
			end
			cur = cur.Parent
		end
		if inst:IsA("MeshPart") then
			local m = meshMap[inst.MeshId]
			if m and VALID[m] then
				return m, true
			end
		end
		local cur2, depth = inst, 0
		while cur2 and cur2 ~= workspace and depth < 3 do
			local w = wordClass(cur2.Name)
			if w then
				return w, true
			end
			cur2, depth = cur2.Parent, depth + 1
		end
		if inst.MaterialVariant ~= "" then
			local w = wordClass(inst.MaterialVariant)
			if w then
				return w, true
			end
		end
		return E.classOf(material), false
	end

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
		-- non-collidable parts are seen too (a floating island's mesh, a platform, a water plane are ground even
		-- with collisions off); decoration among them (leaves, flowers, effects) is passed through by E.cast
		rp.RespectCanCollide = false
		return rp, ex
	end

	-- Is a non-collidable part just decoration a ray should pass through? Nearly invisible, or small, or middling and
	-- named like foliage. A big one (40 studs or more: an island, a platform, a cliff mesh) is always ground, whatever
	-- its name ("Grass" often names the top of an island). (Remembered per part.)
	local DECOR_WORDS = { "leaf", "leaves", "foliage", "canopy", "flower", "bush", "petal", "vine", "fx", "effect", "particle" }
	local decorMemo = setmetatable({}, { __mode = "k" })
	local function isDecor(p)
		local v = decorMemo[p]
		if v == nil then
			local s = p.Size
			local big = math.max(s.X, s.Y, s.Z)
			if p.Transparency >= 0.95 then
				v = true
			elseif big >= 40 then
				v = false
			else
				v = big < 20
					or hasKeyword(p.Name, DECOR_WORDS)
					or (p.Parent ~= nil and p.Parent ~= workspace and hasKeyword(p.Parent.Name, DECOR_WORDS))
			end
			decorMemo[p] = v
		end
		return v
	end
	-- A ray for finding the ground (use it with E.rayParams): like workspace:Raycast, but it passes through
	-- decoration with collisions off and keeps going, and remembers what it passed on the params, so later rays skip
	-- it straight away.
	function E.cast(origin, dir, rp)
		for _ = 1, 8 do
			local r = workspace:Raycast(origin, dir, rp)
			if not r then
				return nil
			end
			local p = r.Instance
			if p == workspace.Terrain or not p:IsA("BasePart") or p.CanCollide or not isDecor(p) then
				return r
			end
			rp:AddToFilter(p)
			local gone = (r.Position - origin).Magnitude
			local len = dir.Magnitude
			if gone >= len then
				return nil
			end
			origin, dir = r.Position, dir.Unit * (len - gone)
		end
		return nil
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
				local r = E.cast(Vector3.new(x, top, z), down, rp)
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
									local r2 = E.cast(from - Vector3.new(0, 0.05, 0), Vector3.new(0, -300, 0), rp)
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

		-- distance to the nearest cell of a kind. Parts the area was filled from never count (a wooden deck reads as
		-- road by its material, and copies would keep off the very ground they were given)
		local function field(pred)
			local src = {}
			for i = 1, N do
				if pred(cls[i]) and not on[i] then
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

	-- shared with the modules after this one
	I.MAT_CLASS = MAT_CLASS
	I.hasKeyword = hasKeyword
	I.chamfer = chamfer
end
