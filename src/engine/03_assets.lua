--------------------------------------------------------------------------------
-- Asset types + smart defaults (the "brain" — tweak freely)
--------------------------------------------------------------------------------
E.TYPES = { "Building", "Tree", "Rock", "Prop", "Bush", "Flower" }
E.HUGS = { "None", "Trees", "Buildings", "Roads", "Paths", "Water" }
E.PLACES = { "Scatter", "Along" }
E.FOLLOWS = { "Roads", "Paths", "Water", "Houses", "Border" }
E.SIDES = { "Center", "Both", "Left", "Right" }
E.ORIENTS = { "Upright", "Surface", "Follow" }
E.FACINGS = { "Face it", "Along", "Away", "Random" }
local FOLLOW_FIELD = { Roads = "Roads", Paths = "Paths", Water = "Water", Houses = "Buildings", Border = "Edge" }
E.YAW_MODES = { "Random", "Snap", "Fixed" }
local COVERAGE = { Building = 0.10, Tree = 0.35, Rock = 0.05, Prop = 0.06, Bush = 0.14, Flower = 0.10 }
local MIN_COUNT_R = 1.6 -- tiny assets still "claim" at least this radius when working out how many to place
local CORE = { Building = 1.0, Tree = 0.2, Rock = 0.8, Prop = 0.9, Bush = 0.6, Flower = 0.5 }
local PRIORITY = { Building = 1, Tree = 2, Rock = 3, Prop = 3.5, Bush = 4, Flower = 5 }

local function surf(list)
	local t = {}
	for _, s in E.SURFACES do
		t[s] = false
	end
	for _, s in list do
		t[s] = true
	end
	return t
end

function E.defaults(t)
	local d = {
		enabled = true,
		density = 1,
		scaleMin = 0.8,
		scaleMax = 1.2,
		spacing = 1,
		cluster = 0.3,
		align = 0,
		maxSlope = 35,
		sink = 0.02,
		tilt = 4,
		tint = 0.08,
		surfaces = surf({ "Grass", "Dirt", "Generic" }),
		keepBuilding = 4,
		keepRoad = 3,
		keepWater = 2,
		hug = "None",
		hugRange = 12,
		hugStrength = 0.6,
		faceRoad = false,
		clearance = 1,
		clumpSize = 1,
		maxCount = 0,
		yawMode = "Random",
		yaw = 0,
		useAlt = false,
		altMin = 0,
		altMax = 1,
		groups = false,
		groupMin = 2,
		groupMax = 4,
		tight = 1.1,
		stack = 0,
		sameModel = true,
		-- "Along": a line of copies following an edge (lamps along a road, a fence around the area…)
		place = "Scatter",
		follow = "Roads",
		offset = 2,
		interval = 20,
		jitter = 0.1,
		skip = 0,
		facing = "Face it",
		fit = false,
		stagger = false,
		side = "Center",
		orient = "Upright",
		roll = 0, -- when following a spline
		front = "Auto", -- which side of the model leads along a line (see E.FRONTS)
		seed = 0, -- per-layer reroll on top of the area seed
		-- Variation (off: just the simple colour shift, `tint`): random hue, saturation and brightness per copy or
		-- per part, on part colours, SurfaceAppearance tints and decals; and optional details left out at random
		vary = false,
		hueVar = 0.03,
		satVar = 0.1,
		valVar = 0.15,
		perPart = false,
		dropDetails = 0,
		edgeYoung = 0, -- 0-1: smaller copies toward the area's edge and its clearings, like a forest's young fringe
		lean = 0, -- degrees: lean with the area's wind (its direction is the area's), a little more or less each
		near = "",
		nearRange = 16,
		nearStrength = 0.7, -- grow close to copies of another object in the area (its key)
		locked = false, -- keep what's placed: regenerating the area leaves this layer's copies where they are
		key = "", -- the layer's randomness identity once its first model is swapped (so the spots stay the same)
	}
	if t == "Building" then
		d.scaleMin, d.scaleMax, d.spacing, d.cluster, d.maxSlope, d.tilt, d.tint = 1, 1, 1.15, 0, 14, 0, 0
		d.surfaces = surf({ "Grass", "Dirt", "Generic", "Sand", "Snow" })
		d.keepBuilding, d.keepRoad, d.keepWater = 3, 2, 6
		d.hug, d.hugRange, d.hugStrength, d.faceRoad = "Roads", 30, 0.85, true
		d.yawMode = "Snap"
	elseif t == "Prop" then -- barrels, crates, sacks…: little piles, some stacked
		d.scaleMin, d.scaleMax, d.spacing, d.cluster, d.align, d.maxSlope, d.sink, d.tilt, d.tint = 0.9, 1.1, 2.2, 0.2, 0.15, 20, 0, 2, 0.04
		d.surfaces = surf({ "Grass", "Dirt", "Road", "Rock", "Sand", "Snow", "Generic" })
		d.keepBuilding, d.keepRoad, d.keepWater = 1, 0, 2
		d.hug, d.hugRange, d.hugStrength = "Buildings", 24, 0.5
		d.groups, d.groupMin, d.groupMax, d.tight, d.stack = true, 2, 5, 1.05, 0.15
	elseif t == "Tree" then
		d.spacing, d.cluster = 0.75, 0.3
		d.surfaces = surf({ "Grass", "Dirt", "Generic", "Snow" })
		d.keepBuilding, d.keepRoad, d.keepWater = 6, 4, 3
	elseif t == "Rock" then
		d.scaleMin, d.scaleMax, d.cluster, d.align, d.maxSlope, d.sink, d.tilt, d.tint = 0.6, 1.5, 0.35, 1, 75, 0.2, 20, 0.06
		d.surfaces = surf({ "Grass", "Dirt", "Rock", "Sand", "Snow", "Generic" })
		d.keepBuilding, d.keepRoad, d.keepWater = 2, 2, 0
	elseif t == "Bush" then
		d.scaleMin, d.scaleMax, d.spacing, d.cluster, d.align, d.maxSlope, d.sink, d.tilt, d.tint = 0.75, 1.3, 0.9, 0.45, 0.5, 40, 0.1, 6, 0.1
		d.keepBuilding, d.keepRoad, d.keepWater = 1, 2, 1
		d.hug, d.hugRange, d.hugStrength = "Trees", 12, 0.6
	elseif t == "Flower" then
		d.scaleMin, d.scaleMax, d.spacing, d.cluster, d.align, d.maxSlope, d.sink, d.tilt, d.tint = 0.7, 1.3, 1.1, 0.75, 1, 45, 0.05, 10, 0.12
		d.surfaces = surf({ "Grass", "Generic" })
		d.keepBuilding, d.keepRoad, d.keepWater = 1, 1, 1
		d.hug, d.hugRange, d.hugStrength = "Paths", 10, 0.4
	end
	return d
end

--------------------------------------------------------------------------------
-- Asset analysis
--------------------------------------------------------------------------------
local function partsOf(inst)
	local t = {}
	if inst:IsA("BasePart") then
		table.insert(t, inst)
	end
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(t, d)
		end
	end
	return t
end

-- How much of a model's footprint its top is flat over (0-1): the parts whose top face is level and within a hair
-- of the highest point. A crate or barrel is close to 1, a tree or a rock close to 0. Only flat-topped pieces take
-- another piece stacked on them.
local function flatTopOf(parts, ref, topY, size)
	local area = 0
	for _, p in parts do
		if p.Transparency < 1 then
			local cf, h = p.CFrame, p.Size / 2
			local axes, half = { cf.RightVector, cf.UpVector, cf.LookVector }, { h.X, h.Y, h.Z }
			for k = 1, 3 do -- the part's axis that stands vertical (a barrel's cylinder often lies along X)
				local up = axes[k].Y
				if math.abs(up) > 0.98 then
					local a, b = axes[k % 3 + 1], axes[(k + 1) % 3 + 1]
					local ha, hb = half[k % 3 + 1], half[(k + 1) % 3 + 1]
					local top = cf.Position + axes[k] * (up > 0 and half[k] or -half[k])
					local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
					for sa = -1, 1, 2 do
						for sb = -1, 1, 2 do
							local l = ref:PointToObjectSpace(top + a * ha * sa + b * hb * sb)
							lo = lo:Min(l)
							hi = hi:Max(l)
						end
					end
					if topY - hi.Y < 0.15 then
						area += (hi.X - lo.X) * (hi.Z - lo.Z)
					end
					break
				end
			end
		end
	end
	return math.clamp(area / math.max(size.X * size.Z, 1e-3), 0, 1)
end

-- Bounds in a world-aligned frame at the pivot. "Up" and "front" (-Z) come from how the template
-- sits in the world, NOT from its pivot rotation (pivots are often rotated, e.g. a cylinder trunk).
local function measure(inst)
	local parts = partsOf(inst)
	if #parts == 0 then
		return nil
	end
	local pivot = inst:GetPivot()
	local ref = CFrame.new(pivot.Position)
	local mn, mx = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, p in parts do
		local h = p.Size / 2
		for sx = -1, 1, 2 do
			for sy = -1, 1, 2 do
				for sz = -1, 1, 2 do
					local l = ref:PointToObjectSpace(p.CFrame:PointToWorldSpace(Vector3.new(h.X * sx, h.Y * sy, h.Z * sz)))
					mn = mn:Min(l)
					mx = mx:Max(l)
				end
			end
		end
	end
	local size, c = mx - mn, (mx + mn) / 2
	return {
		size = size,
		bottom = mn.Y,
		cx = c.X,
		cz = c.Z,
		radius = math.max(size.X, size.Z) / 2,
		parts = parts,
		rel = ref:ToObjectSpace(pivot),
		flatTop = flatTopOf(parts, ref, mx.Y, size),
	}
end

local KEYWORDS = {
	{
		"Building",
		{
			"house",
			"building",
			"hut",
			"cabin",
			"shop",
			"store",
			"tower",
			"barn",
			"shed",
			"home",
			"castle",
			"church",
			"cottage",
			"tent",
			"well",
			"stall",
		},
	},
	{ "Tree", { "tree", "pine", "oak", "birch", "palm", "spruce", "fir", "maple", "willow", "cedar", "sakura" } },
	{
		"Prop",
		{
			"barrel",
			"crate",
			"box",
			"keg",
			"sack",
			"bag",
			"pallet",
			"chest",
			"bucket",
			"vase",
			"pot",
			"cart",
			"bench",
			"lamp",
			"tire",
			"tyre",
			"cone",
			"jar",
			"basket",
			"log pile",
			"hay",
		},
	},
	{ "Rock", { "rock", "stone", "boulder", "pebble", "cliff", "crystal" } },
	{ "Flower", { "flower", "grass", "daisy", "tulip", "rose", "weed", "clover", "mushroom", "reed", "lily", "sprout", "petal" } },
	{ "Bush", { "bush", "shrub", "hedge", "fern", "plant", "cactus" } },
}

-- the type a name says ("Oak Tree" → Tree), or nil
local function typeByName(name)
	for _, pair in KEYWORDS do
		if hasKeyword(name, pair[2]) then
			return pair[1]
		end
	end
	return nil
end

local function classify(inst, m)
	local named = typeByName(inst.Name)
	if named then
		return named
	end
	local total, stone, built = 0, 0, 0
	for _, p in m.parts do
		local v = p.Size.X * p.Size.Y * p.Size.Z
		total += v
		local c = MAT_CLASS[p.Material]
		if c == "Rock" then
			stone += v
		elseif c == "Road" then
			built += v
		end
	end
	local foot, h = math.max(m.size.X, m.size.Z), m.size.Y
	if total > 0 and stone / total > 0.6 then
		return "Rock"
	end
	local crafted = 0
	for _, part in m.parts do
		local mt = part.Material
		if
			mt == Enum.Material.Wood
			or mt == Enum.Material.WoodPlanks
			or mt == Enum.Material.Metal
			or mt == Enum.Material.CorrodedMetal
			or mt == Enum.Material.DiamondPlate
			or mt == Enum.Material.Fabric
		then
			crafted += part.Size.X * part.Size.Y * part.Size.Z
		end
	end
	if total > 0 and crafted / total > 0.5 and foot <= 10 and h <= 10 then
		return "Prop"
	end
	if foot <= 3 and h <= 5 then
		return "Flower"
	end
	-- a flat slab (a paving tile, a plank, a stepping stone) is a prop, not a building, whatever it's made of
	if h <= 1.5 and h < foot * 0.15 then
		return "Prop"
	end
	if total > 0 and built / total > 0.4 and foot >= 8 then
		return "Building"
	end
	if foot >= 24 then
		return "Building"
	end
	if h >= 10 and h >= foot * 1.2 then
		return "Tree"
	end
	if h >= 14 then
		return "Tree"
	end
	return "Bush"
end

local function merge(d, s)
	if type(s) ~= "table" then
		return d
	end
	for k, v in s do
		if d[k] ~= nil and type(v) == type(d[k]) then
			if type(v) == "table" then
				for kk, vv in v do
					if d[k][kk] ~= nil then
						d[k][kk] = vv
					end
				end
			else
				d[k] = v
			end
		end
	end
	return d
end

local function strHash(str)
	local h = 5381
	for i = 1, #str do
		h = (h * 33 + string.byte(str, i)) % 2147483647
	end
	return h
end

-- ground pieces (roads, plates, marked surfaces) are never scatter layers: layers are hidden from the scan,
-- so a road added by mistake would make the scatter ignore that road
function E.isGround(inst)
	if inst:GetAttribute("SS_Surface") then
		return true
	end
	return inst:IsA("BasePart") and inst.Size.Y < 2 and math.max(inst.Size.X, inst.Size.Z) >= 16
end

-- Procedural models (Roblox's ProceduralModel) rebuild their geometry every time they're copied: hundreds of copies
-- meant hundreds of generators running at once, and Studio crawled. A template holding one is frozen instead: its
-- generated parts, as they are now, in a plain Model with the same pivot, and that frozen copy is what gets placed.
local function isProcedural(inst)
	if inst.ClassName == "ProceduralModel" then
		return true
	end
	for _, d in inst:GetDescendants() do
		if d.ClassName == "ProceduralModel" then
			return true
		end
	end
	return false
end
local function frozenCopy(inst)
	local m = Instance.new("Model")
	m.Name = inst.Name
	for _, p in partsOf(inst) do
		local c = p:Clone()
		if not c then -- generated parts may not be Archivable, and those can't be cloned as they are
			local was = p.Archivable
			pcall(function()
				p.Archivable = true
				c = p:Clone()
				p.Archivable = was
			end)
		end
		if not c then
			continue
		end
		for _, d in c:GetDescendants() do
			if d:IsA("BasePart") or d:IsA("LuaSourceContainer") then
				d:Destroy()
			end -- parts come on their own
		end
		c.Parent = m
	end
	m.WorldPivot = inst:GetPivot()
	return m
end
-- a copy of a model that's safe to place many times (and to show in a thumbnail)
function E.copyOf(inst)
	return isProcedural(inst) and frozenCopy(inst) or inst:Clone()
end

-- a variant = one model a layer can place; a layer mixes its variants by weight ("share")
function E.makeVariant(inst, w, size)
	if not inst or not (inst:IsA("Model") or inst:IsA("BasePart")) then
		return nil
	end
	if CollectionService:HasTag(inst, E.TAG) or E.isGround(inst) then
		return nil
	end
	local m = measure(inst)
	if not m then
		return nil
	end
	return { inst = inst, m = m, w = tonumber(w) or 1, size = tonumber(size) or 1, src = isProcedural(inst) and frozenCopy(inst) or nil }
end

-- vlist (optional): { {inst=, w=, size=}, ... } — the first entry must be `inst`
function E.makeLayer(inst, t, s, vlist)
	local first = E.makeVariant(inst, vlist and vlist[1] and vlist[1].w, vlist and vlist[1] and vlist[1].size)
	if not first then
		return nil
	end
	t = (t and COVERAGE[t]) and t or classify(inst, first.m)
	local l = { inst = inst, type = t, s = merge(E.defaults(t), s), m = first.m, variants = { first } }
	if s == nil then
		local function has(list)
			return hasKeyword(inst.Name, list)
		end
		if has({ "fence", "railing", "rail", "barrier", "guardrail", "wall", "palisade" }) then
			l.s.place, l.s.facing, l.s.fit, l.s.offset, l.s.tilt, l.s.jitter = "Along", "Along", true, 1, 0, 0
			l.s.scaleMin, l.s.scaleMax = 1, 1
		elseif
			has({
				"lamp",
				"lantern",
				"streetlight",
				"streetlamp",
				"street light",
				"light pole",
				"post",
				"pole",
				"sign",
				"signpost",
				"hydrant",
				"bollard",
				"torch",
			})
		then
			l.s.place, l.s.facing, l.s.offset, l.s.interval, l.s.tilt, l.s.jitter = "Along", "Face it", 1.5, 28, 0, 0.05
			l.s.scaleMin, l.s.scaleMax = 1, 1
		end
	end
	for i = 2, #(vlist or {}) do
		local v = E.makeVariant(vlist[i].inst, vlist[i].w, vlist[i].size)
		if v then
			table.insert(l.variants, v)
		end
	end
	return l
end

function E.addVariant(l, inst)
	for _, v in l.variants do
		if v.inst == inst then
			return false
		end
	end
	local v = E.makeVariant(inst, 1, 1)
	if not v then
		return false
	end
	table.insert(l.variants, v)
	return true
end

-- swap one model for another: same share and size, and the layer keeps its randomness, so the new model lands on
-- the same spots (where it fits)
function E.swapVariant(l, idx, inst)
	local old = l.variants[idx]
	if not old or old.inst == inst then
		return false
	end
	local v = E.makeVariant(inst, old.w, old.size)
	if not v then
		return false
	end
	if l.s.key == "" then
		l.s.key = E.layerKey(l)
	end
	l.variants[idx] = v
	l.inst, l.m = l.variants[1].inst, l.variants[1].m
	return true
end

function E.removeVariant(l, idx)
	if #l.variants <= 1 or type(idx) ~= "number" or not l.variants[idx] then
		return false
	end
	table.remove(l.variants, idx)
	l.inst, l.m = l.variants[1].inst, l.variants[1].m
	return true
end

--------------------------------------------------------------------------------
-- Biomes: a ready set of objects made from the models already in the place, picked by name ("Oak Tree", "Bush_2")
--------------------------------------------------------------------------------
E.BIOMES = {
	{ name = "Forest", mix = { Tree = 1.3, Bush = 1, Flower = 0.7, Rock = 0.6 } },
	{ name = "Meadow", mix = { Flower = 1.6, Bush = 0.6, Tree = 0.25, Rock = 0.3 } },
	{ name = "Desert", mix = { Rock = 1.2, Bush = 0.5, Prop = 0.3 }, surfaces = { "Sand", "Rock", "Dirt", "Generic" } },
	{ name = "Town", mix = { Building = 1, Prop = 1, Tree = 0.35, Bush = 0.5 } },
}

-- models that look like templates, by the type their name says: everything in ServerStorage and ReplicatedStorage,
-- and in Workspace only inside a folder named like a template library ("Assets", "Prefabs", "Models"…), so the map's
-- own houses aren't taken for templates
local LIBRARY = { "asset", "template", "prefab", "model", "prop", "library", "sample" }
function E.findTemplates()
	local byType, out, roads = {}, workspace:FindFirstChild(E.OUT), workspace:FindFirstChild(E.ROADS)
	local function scan(root, needLibrary)
		for _, c in root:GetDescendants() do
			if not (c:IsA("Model") or c:IsA("MeshPart")) or c:FindFirstAncestorWhichIsA("Model") then
				continue
			end
			if (out and c:IsDescendantOf(out)) or (roads and c:IsDescendantOf(roads)) or CollectionService:HasTag(c, E.TAG) then
				continue
			end
			if needLibrary then
				local ok, cur = false, c.Parent
				while cur and cur ~= workspace and not ok do
					ok = hasKeyword(cur.Name, LIBRARY)
					cur = cur.Parent
				end
				if not ok then
					continue
				end
			end
			local t = typeByName(c.Name)
			if t and not E.isGround(c) then
				byType[t] = byType[t] or {}
				table.insert(byType[t], c)
			end
		end
	end
	scan(game:GetService("ServerStorage"), false)
	scan(game:GetService("ReplicatedStorage"), false)
	scan(workspace, true)
	return byType
end

-- the biome's objects (one per type, up to 4 models mixed in each) and the types no model was found for
function E.biomeLayers(biome)
	local found, layers, missing = E.findTemplates(), {}, {}
	for _, t in E.TYPES do
		local weight = biome.mix[t]
		if not weight then
			continue
		end
		local list = found[t]
		if not list then
			table.insert(missing, t)
			continue
		end
		table.sort(list, function(a, b)
			return a.Name < b.Name
		end)
		local vlist = {}
		for i = 1, math.min(#list, 4) do
			table.insert(vlist, { inst = list[i], w = 1, size = 1 })
		end
		local l = E.makeLayer(vlist[1].inst, t, nil, vlist)
		if l then
			l.s.density = weight
			if biome.surfaces then
				l.s.surfaces = surf(biome.surfaces)
			end
			table.insert(layers, l)
		end
	end
	return layers, missing
end

-- a few simple models to try the plugin with, in ServerStorage > SmartScatter Samples (made once)
function E.makeSamples()
	local ss = game:GetService("ServerStorage")
	local f = ss:FindFirstChild("SmartScatter Samples")
	if f then
		return f, false
	end
	f = Instance.new("Folder")
	f.Name = "SmartScatter Samples"
	local function model(name, parts)
		local m = Instance.new("Model")
		m.Name = name
		for i, p in parts do
			local part = Instance.new("Part")
			part.Anchored, part.TopSurface, part.BottomSurface = true, Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
			part.Name, part.Size, part.CFrame, part.Color, part.Material = p[1], p[2], CFrame.new(p[3]), p[4], p[5] or Enum.Material.SmoothPlastic
			if p[6] then
				part.Shape = p[6]
			end
			part.Parent = m
			if i == 1 then
				m.PrimaryPart = part
			end
		end
		m.Parent = f
	end
	local bark, leaf, dark = Color3.fromRGB(106, 76, 52), Color3.fromRGB(88, 150, 76), Color3.fromRGB(52, 102, 62)
	local wood = Enum.Material.Wood
	model("Oak Tree", {
		{ "Trunk", Vector3.new(1.4, 8, 1.4), Vector3.new(0, 4, 0), bark, wood },
		{ "Leaves", Vector3.new(9, 8, 9), Vector3.new(0, 11, 0), leaf, Enum.Material.Grass, Enum.PartType.Ball },
	})
	model("Pine Tree", {
		{ "Trunk", Vector3.new(1, 3, 1), Vector3.new(0, 1.5, 0), bark, wood },
		{ "Low", Vector3.new(7, 3, 7), Vector3.new(0, 4.5, 0), dark },
		{ "Mid", Vector3.new(4.6, 3, 4.6), Vector3.new(0, 7.5, 0), dark },
		{ "Top", Vector3.new(2, 3, 2), Vector3.new(0, 10.5, 0), dark },
	})
	model("Bush", { { "Leaves", Vector3.new(4, 3, 4), Vector3.new(0, 1.5, 0), leaf, Enum.Material.Grass, Enum.PartType.Ball } })
	model("Flower", {
		{ "Stem", Vector3.new(0.2, 1.2, 0.2), Vector3.new(0, 0.6, 0), Color3.fromRGB(80, 140, 70) },
		{ "Petals", Vector3.new(0.8, 0.8, 0.8), Vector3.new(0, 1.3, 0), Color3.fromRGB(236, 196, 90), nil, Enum.PartType.Ball },
	})
	model("Rock", { { "Stone", Vector3.new(4, 2.4, 3.2), Vector3.new(0, 1.2, 0), Color3.fromRGB(128, 126, 122), Enum.Material.Slate } })
	model("Crate", { { "Box", Vector3.new(3, 3, 3), Vector3.new(0, 1.5, 0), Color3.fromRGB(160, 118, 72), Enum.Material.WoodPlanks } })
	f.Parent = ss
	return f, true
end

-- a line layer's post: placed at every joint and at both ends of a run (fence posts, pillars between wall panels)
function E.setPost(l, inst)
	l.post = inst and E.makeVariant(inst, 1, 1) or nil
	return inst == nil or l.post ~= nil
end

function E.variantList(l)
	local t = {}
	for _, v in l.variants do
		table.insert(t, { inst = v.inst, w = v.w, size = v.size })
	end
	return t
end

-- per-layer paint: density multiplier per mask cell (1 = untouched, 0 = none, up to 3)
function E.paintValue(l, cx, cz)
	local r = l.paint and l.paint[cz]
	return r and r[cx] or 1
end
function E.setPaint(l, cx, cz, v)
	v = math.clamp(math.floor(v * 4 + 0.5) / 4, 0, 3)
	l.paint = l.paint or {}
	local r = l.paint[cz]
	if math.abs(v - 1) < 1e-3 then
		if r then
			r[cx] = nil
			if next(r) == nil then
				l.paint[cz] = nil
			end
		end
	else
		if not r then
			r = {}
			l.paint[cz] = r
		end
		r[cx] = v
	end
end
local function encodePaint(paint)
	local out = {}
	for cz, r in paint or {} do
		for cx, v in r do
			table.insert(out, cz .. ":" .. cx .. ":" .. v)
		end
	end
	return table.concat(out, ";")
end
local function decodePaint(str)
	local paint
	for cz, cx, v in string.gmatch(str or "", "(-?%d+):(-?%d+):([%d%.]+)") do
		paint = paint or {}
		cz, cx = tonumber(cz), tonumber(cx)
		paint[cz] = paint[cz] or {}
		paint[cz][cx] = tonumber(v)
	end
	return paint
end

-- A piece meant to join its neighbours along a line: flat (a path tile, a plank) or long and thin (a fence panel,
-- a wall, a rail). Lamps, lanterns, benches and posts are not: they keep a gap between copies.
function E.looksLikeSegment(l)
	local m = l.m
	if not m then
		return false
	end
	local long, short = math.max(m.size.X, m.size.Z), math.min(m.size.X, m.size.Z)
	if m.size.Y > long then
		return false
	end -- taller than long: a lamp with an arm, a sign post, a pole
	return m.size.Y < long * 0.2 or (long >= short * 4 and long >= 3)
end

-- Sensible settings for a layer that has just become a line: segments resize to meet end to end, anything else
-- keeps its spacing; with a spline drawn, the line follows it.
function E.smartLine(l, hasSpline)
	l.s.place = "Along"
	l.s.fit = E.looksLikeSegment(l)
	if hasSpline then
		l.s.follow = "Spline"
	end
end

-- a new type brings that type's rules; the amount, the reroll and everything about following a line stay
function E.setType(layer, t)
	local s = layer.s
	local keep = {
		enabled = s.enabled,
		density = s.density,
		seed = s.seed,
		place = s.place,
		follow = s.follow,
		offset = s.offset,
		interval = s.interval,
		jitter = s.jitter,
		skip = s.skip,
		facing = s.facing,
		fit = s.fit,
		stagger = s.stagger,
		side = s.side,
		orient = s.orient,
		roll = s.roll,
		front = s.front,
		locked = s.locked,
		key = s.key,
		vary = s.vary,
		hueVar = s.hueVar,
		satVar = s.satVar,
		valVar = s.valVar,
		perPart = s.perPart,
		dropDetails = s.dropDetails,
		edgeYoung = s.edgeYoung,
		lean = s.lean,
		near = s.near,
		nearRange = s.nearRange,
		nearStrength = s.nearStrength,
	}
	layer.type = t
	layer.s = merge(E.defaults(t), keep)
end

-- every rule back to the smart defaults for the layer's type; a line stays a line (what it follows and whether
-- its pieces join end to end)
function E.resetLayer(layer)
	local s = layer.s
	local line = s.place == "Along"
	layer.s = merge(
		E.defaults(layer.type),
		{ enabled = s.enabled, place = s.place, follow = line and s.follow or nil, fit = line and s.fit or nil, locked = s.locked, key = s.key }
	)
end
