--[[
	Smart Scatter — Engine/Seasons: turning a finished map snowy, autumn or dry, fully or in patches. Part colours,
	SurfaceAppearance tints and decals change; optionally the terrain's grass colours, or its grass itself. Every
	change keeps what it replaced (an attribute on the part, a copy of the terrain), so a season can be switched or
	taken off again exactly.
	Adds to E (the engine API); shares internals with the other engine modules through I.
]]

return function(E, I)
	local hasKeyword = I.hasKeyword
	local ORIG = "SS_SeasonOrig" -- the colour a part, tint or decal had before any season
	local STATE = "SmartScatter Season" -- ServerStorage: what's applied, and the terrain as it was

	E.SEASONS = { "Snow", "Autumn", "Dry" }
	E.SEASON_HINT = {
		Snow = "Leaves and grass go white, roofs and flat tops get snow, everything else turns cold and pale.",
		Autumn = "Leaves turn orange, red, yellow and brown, each tree its own; the rest warms up a little.",
		Dry = "Leaves and grass fade to straw and brown; the rest bleaches a little in the sun.",
	}

	--------------------------------------------------------------------------------
	-- Colours
	--------------------------------------------------------------------------------
	local AUTUMN = {
		Color3.fromRGB(214, 110, 32), -- orange
		Color3.fromRGB(184, 52, 30), -- red
		Color3.fromRGB(226, 178, 48), -- yellow
		Color3.fromRGB(150, 88, 40), -- brown
		Color3.fromRGB(200, 140, 40), -- gold
	}
	local SNOW = Color3.fromRGB(236, 241, 248)
	local STRAW = Color3.fromRGB(196, 170, 104)
	local DEAD = Color3.fromRGB(140, 110, 70)

	-- a target colour at the original's brightness, so light and dark parts stay light and dark
	local function atBrightness(target, c)
		local h, s, _ = target:ToHSV()
		local _, _, v = c:ToHSV()
		local _, _, tv = target:ToHSV()
		return Color3.fromHSV(h, s, math.clamp(v * 0.55 + tv * 0.45, 0, 1))
	end
	local function hsvShift(c, dh, ds, dv)
		local h, s, v = c:ToHSV()
		return Color3.fromHSV((h + dh) % 1, math.clamp(s + ds, 0, 1), math.clamp(v * (1 + dv), 0, 1))
	end

	-- A colour in a season. amount 0-1 (0 = as it is). kind.foliage: leaves, grass, bushes; kind.top: a roof or a
	-- flat top snow settles on; kind.pick 0-1: which autumn colour this copy takes (the same for its parts).
	function E.seasonColor(c, season, amount, kind)
		if amount <= 0 then
			return c
		end
		kind = kind or {}
		if season == "Snow" then
			if kind.foliage or kind.top then
				return c:Lerp(SNOW, amount * (kind.foliage and 0.82 or 0.9))
			end
			return hsvShift(c, 0.02 * amount, -0.35 * amount, 0.18 * amount):Lerp(SNOW, 0.12 * amount)
		elseif season == "Autumn" then
			if kind.foliage then
				local t = AUTUMN[math.clamp(math.floor((kind.pick or 0) * #AUTUMN) + 1, 1, #AUTUMN)]
				return c:Lerp(atBrightness(t, c), amount)
			end
			return hsvShift(c, -0.03 * amount, 0.05 * amount, 0.03 * amount)
		elseif season == "Dry" then
			if kind.foliage then
				local t = (kind.pick or 0) < 0.7 and STRAW or DEAD
				return c:Lerp(atBrightness(t, c), amount * 0.9)
			end
			return hsvShift(c, -0.01 * amount, -0.2 * amount, 0.08 * amount)
		end
		return c
	end

	-- is it greenery? its material, its colour (clearly green) or its name
	local LEAF_WORDS = { "leaf", "leaves", "foliage", "bush", "shrub", "grass", "canopy", "needle", "pine", "fern", "hedge", "ivy", "moss" }
	-- names: [name] = whether it names greenery (a map repeats the same few names thousands of times)
	local function isFoliage(p, c, names)
		if p.Material == Enum.Material.Grass or p.Material == Enum.Material.LeafyGrass then
			return true
		end
		local h, s, v = c:ToHSV()
		if h > 0.17 and h < 0.45 and s > 0.25 and v > 0.12 then
			return true
		end
		local function leafy(name)
			local k = names[name]
			if k == nil then
				k = hasKeyword(name, LEAF_WORDS)
				names[name] = k
			end
			return k
		end
		return leafy(p.Name) or (p.Parent ~= nil and leafy(p.Parent.Name))
	end
	-- does snow settle on it: a roof, or a flat slab facing up
	local function isTop(p)
		if hasKeyword(p.Name, { "roof", "rooftop" }) then
			return true
		end
		local s = p.Size
		local up = p.CFrame.UpVector.Y
		return (p:IsA("WedgePart") and up > 0.5) or (up > 0.9 and s.Y <= math.min(s.X, s.Z) * 0.5)
	end
	-- a number 0-1 that's the same for every part of one copy, and differs between copies
	-- picks: [model] = its number, worked out once for all its parts
	local function pickOf(p, picks)
		local unit = p.Parent and p.Parent:IsA("Model") and p.Parent or p
		local v = picks[unit]
		if not v then
			local pos = unit:GetPivot().Position
			local n = math.sin(pos.X * 12.9898 + pos.Y * 4.1414 + pos.Z * 78.233) * 43758.5453
			v = n - math.floor(n)
			picks[unit] = v
		end
		return v
	end

	--------------------------------------------------------------------------------
	-- Applying a season to a map
	--------------------------------------------------------------------------------
	local function stateFolder(make)
		local ss = game:GetService("ServerStorage")
		local f = ss:FindFirstChild(STATE)
		if not f and make then
			f = Instance.new("Folder")
			f.Name = STATE
			f.Parent = ss
		end
		return f
	end
	local function skipped(inst)
		if inst:IsA("Terrain") or inst:IsA("Camera") then
			return true
		end
		if (inst.Name == E.OUT or inst.Name == E.ROADS) and inst.Parent == workspace then -- areas colour themselves
			return true
		end
		return inst:IsA("Model") and inst:FindFirstChildOfClass("Humanoid") ~= nil
	end
	-- sets a colour property, keeping the first value it ever had as the original. Returns whether it changed
	-- (a colour the season leaves as it is gets no attribute at all)
	local function setKept(obj, prop, to)
		local kept = obj:GetAttribute(ORIG) ~= nil
		if not kept and obj[prop] == to then
			return false
		end
		if not kept then
			obj:SetAttribute(ORIG, obj[prop])
		end
		obj[prop] = to
		return true
	end
	local function original(obj, prop)
		local o = obj:GetAttribute(ORIG)
		return typeof(o) == "Color3" and o or obj[prop]
	end

	local TERRAIN_GREEN = { Enum.Material.Grass, Enum.Material.LeafyGrass }
	local TERRAIN_TO = { Snow = Enum.Material.Snow, Dry = Enum.Material.Ground } -- (autumn keeps its grass)

	-- the terrain cells (4 studs each) around what's in the roots, grown a little: where terrain changes stay
	local function cellsAround(roots)
		local lo, hi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
		for _, r in roots do
			for _, d in r:IsA("BasePart") and { r } or r:GetDescendants() do
				if d:IsA("BasePart") then
					lo, hi = lo:Min(d.Position), hi:Max(d.Position)
				end
			end
		end
		if lo.X > hi.X then
			return nil
		end
		local pad = 64
		local function cell(v, f)
			return Vector3.new(f(v.X / 4), f(v.Y / 4), f(v.Z / 4))
		end
		return cell(lo - Vector3.new(pad, pad, pad), math.floor), cell(hi + Vector3.new(pad, pad, pad), math.ceil)
	end
	local function v16(v)
		return Vector3int16.new(v.X, v.Y, v.Z)
	end

	-- puts the terrain back as it was before any season changed its materials
	local function restoreTerrain()
		local f = stateFolder(false)
		local saved = f and f:FindFirstChild("Terrain")
		if saved and saved:IsA("TerrainRegion") then
			local corner = f:GetAttribute("SS_TerrainCorner")
			if typeof(corner) == "Vector3" then
				workspace.Terrain:PasteRegion(saved, Vector3int16.new(corner.X, corner.Y, corner.Z), true)
			end
			saved:Destroy()
			f:SetAttribute("SS_TerrainCorner", nil)
		end
		local t = workspace.Terrain
		for _, m in TERRAIN_GREEN do
			local o = t:GetAttribute("SS_SeasonOrig_" .. m.Name)
			if typeof(o) == "Color3" then
				t:SetMaterialColor(m, o)
				t:SetAttribute("SS_SeasonOrig_" .. m.Name, nil)
			end
		end
	end

	-- Puts the map in a season. opts: season (E.SEASONS), strength 0-1, patchy 0-1 (0: the same everywhere;
	-- higher: stronger in some places than others, following a pattern of patchSize studs), seed, roots (default
	-- the whole Workspace; what Smart Scatter placed and characters are left out), terrainColors (grass colours),
	-- terrainMaterials (grass turns to snow or dry ground, Snow and Dry only), pause. Starts from the original
	-- colours, so one season replaces another. Returns how many parts changed, and false if the terrain couldn't
	-- be changed (too big an area to keep a copy of, say).
	function E.applySeason(opts)
		local season, strength = opts.season or "Snow", math.clamp(opts.strength or 1, 0, 1)
		local roots = opts.roots or { workspace }
		local noise = { pattern = "Natural", patchSize = opts.patchSize or 90, seed = tonumber(opts.seed) or 7 }
		local patchy = math.clamp(opts.patchy or 0, 0, 1)
		local function amountAt(pos)
			if patchy <= 0 then
				return strength
			end
			return strength * (1 - patchy + patchy * E.patternAt(noise, pos.X, pos.Z))
		end
		local n, seen = 0, 0
		local names, picks = {}, {}
		local function recolor(p)
			local base = original(p, "Color")
			local amount = amountAt(p.Position)
			local kind = { foliage = isFoliage(p, base, names), top = season == "Snow" and isTop(p), pick = pickOf(p, picks) }
			local changed = setKept(p, "Color", E.seasonColor(base, season, amount, kind))
			for _, d in p:GetChildren() do
				if d:IsA("SurfaceAppearance") then
					pcall(function() -- (older Studio builds have no SurfaceAppearance.Color)
						setKept(d, "Color", E.seasonColor(original(d, "Color"), season, amount, kind))
					end)
				elseif d:IsA("Decal") then
					setKept(d, "Color3", E.seasonColor(original(d, "Color3"), season, amount, kind))
				end
			end
			n += changed and 1 or 0
		end
		local function visit(inst)
			if skipped(inst) then
				return
			end
			if inst:IsA("BasePart") then
				recolor(inst)
			end
			seen += 1
			if opts.pause and seen % 2000 == 0 then
				opts.pause()
			end
			for _, c in inst:GetChildren() do
				visit(c)
			end
		end
		for _, r in roots do
			visit(r)
		end

		-- the terrain: back to how it was first, then this season
		restoreTerrain()
		local t = workspace.Terrain
		if opts.terrainColors then
			for _, m in TERRAIN_GREEN do
				local c = t:GetMaterialColor(m)
				t:SetAttribute("SS_SeasonOrig_" .. m.Name, c)
				t:SetMaterialColor(m, E.seasonColor(c, season, strength, { foliage = true, pick = 0.3 }))
			end
		end
		local to, terrainOk = TERRAIN_TO[season], true
		if opts.terrainMaterials and to and strength > 0 then
			local c0, c1 = cellsAround(roots)
			if c0 then
				-- the terrain there is kept first (pasted back when the season changes or comes off)
				terrainOk = pcall(function()
					local saved = t:CopyRegion(Region3int16.new(v16(c0), v16(c1 - Vector3.one)))
					local f = stateFolder(true)
					saved.Name = "Terrain"
					saved.Parent = f
					f:SetAttribute("SS_TerrainCorner", c0)
					-- in blocks, so a whole map is never one huge call
					local B = 128 -- cells (512 studs)
					for x = c0.X, c1.X - 1, B do
						for y = c0.Y, c1.Y - 1, B do
							for z = c0.Z, c1.Z - 1, B do
								local lo = Vector3.new(x, y, z)
								local hi = Vector3.new(math.min(x + B, c1.X), math.min(y + B, c1.Y), math.min(z + B, c1.Z))
								local region = Region3.new(lo * 4, hi * 4)
								for _, m in TERRAIN_GREEN do
									t:ReplaceMaterial(region, 4, m, to)
								end
								if opts.pause then
									opts.pause()
								end
							end
						end
					end
				end)
			end
		end
		local f = stateFolder(true)
		f:SetAttribute("SS_Season", season)
		f:SetAttribute("SS_Strength", strength)
		f:SetAttribute("SS_Parts", n)
		return n, terrainOk
	end

	-- { season, strength, parts } of the season on the map, or nil
	function E.seasonInfo()
		local f = stateFolder(false)
		if not f or not f:GetAttribute("SS_Season") then
			return nil
		end
		return { season = f:GetAttribute("SS_Season"), strength = f:GetAttribute("SS_Strength") or 1, parts = f:GetAttribute("SS_Parts") or 0 }
	end

	-- Takes the season off: every colour back to its original, and the terrain as it was. roots: where to look
	-- (default the whole Workspace). Returns how many parts went back.
	function E.clearSeason(opts)
		opts = opts or {}
		local n, seen = 0, 0
		local function back(obj, prop)
			local o = obj:GetAttribute(ORIG)
			if typeof(o) == "Color3" then
				obj[prop] = o
			end
			if o ~= nil then
				obj:SetAttribute(ORIG, nil)
			end
		end
		for _, r in opts.roots or { workspace } do
			for _, d in r:GetDescendants() do
				if d:IsA("BasePart") and d:GetAttribute(ORIG) ~= nil then
					back(d, "Color")
					n += 1
				elseif d:IsA("SurfaceAppearance") and d:GetAttribute(ORIG) ~= nil then
					pcall(back, d, "Color")
				elseif d:IsA("Decal") and d:GetAttribute(ORIG) ~= nil then
					back(d, "Color3")
				end
				seen += 1
				if opts.pause and seen % 4000 == 0 then
					opts.pause()
				end
			end
		end
		restoreTerrain()
		local f = stateFolder(false)
		if f then
			f:Destroy()
		end
		return n
	end
end
