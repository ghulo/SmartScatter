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
	{ "Building", { "house", "building", "wall", "roof", "fence", "hut", "cabin", "shop", "tower", "barn", "shed", "castle", "church", "cottage" } },
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
