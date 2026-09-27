-- GENERATED from src/Engine by tools/tree.py (a flattened copy for older loaders): edit the modules, not this.
local MODULES = {}

-- #module Scan
MODULES["Scan"] = (function()
--[[
Smart Scatter — Engine/Scan: Surface classes and the scan: what each ground cell is, and distance fields to roads, water and buildings.
Adds to E (the engine API); shares internals with the other engine modules through I.
]]

return function(E, I)
local HttpService = game:GetService("HttpService")

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

function E.rayParams(extra)
local ex = { workspace.CurrentCamera }
local out = workspace:FindFirstChild(E.OUT)
if out then
table.insert(ex, out)
end -- everything we place, including what a running generation adds
for _, e in extra or {} do
table.insert(ex, e)
end
local rp = RaycastParams.new()
rp.FilterType = Enum.RaycastFilterType.Exclude
rp.FilterDescendantsInstances = ex
rp.RespectCanCollide = true -- leaves and decorative non-collidable parts are ignored
return rp, ex
end

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

I.MAT_CLASS = MAT_CLASS
I.hasKeyword = hasKeyword
end
end)()
-- #module Assets
MODULES["Assets"] = (function()
--[[
Smart Scatter — Engine/Assets: Asset types and smart defaults (the "brain"), layers and their settings.
Adds to E (the engine API); shares internals with the other engine modules through I.
]]

return function(E, I)
local CollectionService = game:GetService("CollectionService")
local MAT_CLASS = I.MAT_CLASS
local hasKeyword = I.hasKeyword

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
vary = false,
hueVar = 0.03,
satVar = 0.1,
valVar = 0.15,
perPart = false,
dropDetails = 0,
slopePref = 0, -- -1 (flat ground) … 1 (steep ground): where on the slopes it'd rather grow (0 = anywhere)
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

function E.isGround(inst)
if inst:GetAttribute("SS_Surface") then
return true
end
return inst:IsA("BasePart") and inst.Size.Y < 2 and math.max(inst.Size.X, inst.Size.Z) >= 16
end

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
function E.copyOf(inst)
return isProcedural(inst) and frozenCopy(inst) or inst:Clone()
end

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

E.BIOMES = {
{ name = "Forest", mix = { Tree = 1.3, Bush = 1, Flower = 0.7, Rock = 0.6 } },
{ name = "Meadow", mix = { Flower = 1.6, Bush = 0.6, Tree = 0.25, Rock = 0.3 } },
{ name = "Desert", mix = { Rock = 1.2, Bush = 0.5, Prop = 0.3 }, surfaces = { "Sand", "Rock", "Dirt", "Generic" } },
{ name = "Town", mix = { Building = 1, Prop = 1, Tree = 0.35, Bush = 0.5 } },
}

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

function E.smartLine(l, hasSpline)
l.s.place = "Along"
l.s.fit = E.looksLikeSegment(l)
if hasSpline then
l.s.follow = "Spline"
end
end

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

function E.resetLayer(layer)
local s = layer.s
local line = s.place == "Along"
layer.s = merge(
E.defaults(layer.type),
{ enabled = s.enabled, place = s.place, follow = line and s.follow or nil, fit = line and s.fit or nil, locked = s.locked, key = s.key }
)
end

I.encodePaint = encodePaint
I.decodePaint = decodePaint
I.COVERAGE = COVERAGE
I.MIN_COUNT_R = MIN_COUNT_R
I.CORE = CORE
I.PRIORITY = PRIORITY
I.strHash = strHash
I.partsOf = partsOf
I.FOLLOW_FIELD = FOLLOW_FIELD
end
end)()
-- #module Areas
MODULES["Areas"] = (function()
--[[
Smart Scatter — Engine/Areas: saving and loading (attributes on the area folder), the painted mask, removed copies, outputs.
Adds to E (the engine API); shares internals with the other engine modules through I.
]]

return function(E, I)
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local decodePaint = I.decodePaint
local encodePaint = I.encodePaint

local SEP = "\31"
local function nameAt(inst)
local parent = inst.Parent
if not parent then
return inst.Name
end
local n, k = 0, 0
for _, c in parent:GetChildren() do
if c.Name == inst.Name then
n += 1
if c == inst then
k = n
end
end
end
return n > 1 and (inst.Name .. SEP .. k) or inst.Name
end
local function pathOf(inst)
local p, cur = {}, inst
while cur and cur ~= game do
table.insert(p, 1, nameAt(cur))
cur = cur.Parent
end
return p
end
local function childAt(parent, entry)
local name, k = string.match(entry, "^(.*)" .. SEP .. "(%d+)$")
if not name then
return parent:FindFirstChild(entry)
end
k = tonumber(k)
for _, c in parent:GetChildren() do
if c.Name == name then
k -= 1
if k == 0 then
return c
end
end
end
return nil
end
local function resolve(path)
local cur = game
for _, n in path do
if type(n) ~= "string" then
return nil
end
cur = cur and childAt(cur, n)
end
return cur
end
function E.layerKey(l)
return table.concat(pathOf(l.inst), ".")
end

local function plainName(entry)
return type(entry) == "string" and (string.match(entry, "^(.*)" .. SEP .. "%d+$") or entry) or nil
end

local function findModel(path, index)
local hit = resolve(path)
if hit then
return hit, false
end
local name = plainName(path[#path])
if not name then
return nil
end
if not index.built then
index.built = true
local out = workspace:FindFirstChild(E.OUT)
for _, root in { game:GetService("ServerStorage"), game:GetService("ReplicatedStorage"), workspace } do
for _, c in root:GetDescendants() do
if
(c:IsA("Model") or c:IsA("BasePart"))
and not (out and c:IsDescendantOf(out))
and not (c:IsA("BasePart") and c:FindFirstAncestorWhichIsA("Model"))
then
local seen = index[c.Name]
index[c.Name] = seen == nil and c or false -- false: two candidates, don't guess
end
end
end
end
local found = index[name]
return found or nil, found ~= nil and found ~= false
end

local function encodeMask(rows)
local out = {}
for cz, row in rows do
local xs = {}
for cx in row do
table.insert(xs, cx)
end
if #xs > 0 then
table.sort(xs)
local segs, s, p = {}, xs[1], xs[1]
for i = 2, #xs do
if xs[i] == p + 1 then
p = xs[i]
else
table.insert(segs, s .. "~" .. p)
s, p = xs[i], xs[i]
end
end
table.insert(segs, s .. "~" .. p)
table.insert(out, cz .. ":" .. table.concat(segs, ","))
end
end
return table.concat(out, "|")
end

function E.getOut()
local out = workspace:FindFirstChild(E.OUT)
if not out then
out = Instance.new("Folder")
out.Name = E.OUT
out.Parent = workspace
end
return out
end

function E.listAreas()
local t = {}
local out = workspace:FindFirstChild(E.OUT)
if out then
for _, c in out:GetChildren() do
if c:IsA("Folder") and c:GetAttribute("SS_Area") then
table.insert(t, c)
end
end
end
table.sort(t, function(a, b)
return a.Name < b.Name
end)
return t
end

function E.setCell(a, cx, cz, on)
local row = a.rows[cz]
if on then
if not row then
row = {}
a.rows[cz] = row
end
if not row[cx] then
row[cx] = true
a.count += 1
return true
end
elseif row and row[cx] then
row[cx] = nil
a.count -= 1
if next(row) == nil then
a.rows[cz] = nil
end
return true
end
return false
end
function E.hasCell(a, cx, cz)
local r = a.rows[cz]
return r ~= nil and r[cx] == true
end

function E.layersToJSON(layers, withPaint, lost)
local data = {}
for _, l in layers do
local v = {}
for _, x in l.variants do
table.insert(v, { p = pathOf(x.inst), w = x.w, z = x.size })
end
for _, x in l.missing or {} do
table.insert(v, x)
end -- models not found this time: kept for when they're back
table.insert(data, {
p = pathOf(l.inst),
t = l.type,
s = l.s,
v = v,
pm = withPaint ~= false and encodePaint(l.paint) or nil,
pn = withPaint ~= false and l.pins or nil, -- copies put down by hand (Engine/Pins); like painting, an area's own
post = l.post and pathOf(l.post.inst) or l.missingPost,
})
end
for _, d in lost or {} do
table.insert(data, d)
end
return HttpService:JSONEncode(data)
end
function E.layersFromJSON(json)
local layers, lost, relinked = {}, {}, 0
local index = {} -- models by name, built on the first path that doesn't resolve
local ok, data = pcall(HttpService.JSONDecode, HttpService, json or "[]")
if ok and type(data) == "table" then
for _, d in data do
if type(d) ~= "table" then
continue
end
local vlist, missing = {}, {}
for _, v in (type(d.v) == "table" and d.v or { { p = d.p, w = 1, z = 1 } }) do
local inst, moved = nil, false
if type(v) == "table" and type(v.p) == "table" then
inst, moved = findModel(v.p, index)
end
if inst then
table.insert(vlist, { inst = inst, w = v.w, size = v.z })
if moved then
relinked += 1
end
elseif type(v) == "table" then
table.insert(missing, v)
end
end
local l = vlist[1] and E.makeLayer(vlist[1].inst, d.t, d.s, vlist)
if l then
l.paint = decodePaint(d.pm)
l.pins = E.readPins(d.pn)
l.missing = #missing > 0 and missing or nil
local post = type(d.post) == "table" and findModel(d.post, index)
if post then
E.setPost(l, post)
elseif type(d.post) == "table" then
l.missingPost = d.post
end
table.insert(layers, l)
elseif type(d.p) == "table" then
table.insert(lost, d)
end
end
end
return layers, lost, relinked
end
function E.relinkLost(a, i, inst)
local d = a.lost and a.lost[i]
if not d or not inst then
return false
end
local copy = HttpService:JSONDecode(HttpService:JSONEncode(d))
local p = pathOf(inst)
copy.p = p
local vs = type(copy.v) == "table" and copy.v or {}
vs[1] = type(vs[1]) == "table" and vs[1] or { w = 1, z = 1 }
vs[1].p = p
copy.v = vs
local layers = E.layersFromJSON(HttpService:JSONEncode({ copy }))
if not layers[1] or layers[1].inst ~= inst then
return false
end
table.remove(a.lost, i)
table.insert(a.layers, layers[1])
return true
end

local PRESETS = "SmartScatterPresets"
function E.listPresets()
local t = {}
local f = game:GetService("ServerStorage"):FindFirstChild(PRESETS)
for _, c in f and f:GetChildren() or {} do
if c:IsA("StringValue") then
table.insert(t, c)
end
end
table.sort(t, function(a, b)
return a.Name < b.Name
end)
return t
end
function E.savePreset(name, layers)
return E.savePresetJSON(name, E.layersToJSON(layers, false)) -- painting belongs to an area, not to a preset
end
function E.savePresetJSON(name, json)
local ss = game:GetService("ServerStorage")
local f = ss:FindFirstChild(PRESETS)
if not f then
f = Instance.new("Folder")
f.Name = PRESETS
f.Parent = ss
end
local v = f:FindFirstChild(name)
if not (v and v:IsA("StringValue")) then
v = Instance.new("StringValue")
end
v.Name = name
v.Value = json
v.Parent = f
return v
end

E.AREA_LOOK = { "edge", "size", "patches", "pattern", "patchSize", "zones", "zoneMood", "windDir" }
function E.copyLook(from, to)
for _, k in E.AREA_LOOK do
to[k] = from[k]
end
end

local CODE = "SmartScatter/1 " -- the format's name and version; a later format gets a new number
function E.presetCode(preset)
return CODE .. HttpService:JSONEncode({ n = preset.Name, l = preset.Value })
end
function E.importPresetCode(text)
local code = string.match(text or "", "^%s*(.-)%s*$")
if string.sub(code, 1, #CODE) ~= CODE then
return nil, "That isn't a Smart Scatter preset code."
end
local ok, d = pcall(HttpService.JSONDecode, HttpService, string.sub(code, #CODE + 1))
local okL, layers = pcall(HttpService.JSONDecode, HttpService, ok and type(d) == "table" and d.l or "")
if not (ok and type(d) == "table" and type(d.n) == "string" and okL and type(layers) == "table") then
return nil, "The code is cut off or changed. Copy all of it and paste it again."
end
local name = string.sub(string.match(d.n, "^%s*(.-)%s*$"), 1, 60)
return E.savePresetJSON(name ~= "" and name or "Shared preset", d.l)
end

function E.report(a)
local rows, total = {}, { copies = 0, parts = 0 }
local function measure(name, root)
local row, meshIds = { name = name, copies = 0, parts = 0, meshes = 0, unique = 0 }, {}
for _, d in root:GetDescendants() do
if d:IsA("BasePart") then
row.parts += 1
if d:IsA("MeshPart") then
row.meshes += 1
if not meshIds[d.MeshId] then
meshIds[d.MeshId] = true
row.unique += 1
end
end
end
if d:GetAttribute("SS_Type") then
row.copies += 1
end
end
if row.parts > 0 then
table.insert(rows, row)
total.copies += row.copies
total.parts += row.parts
end
end
for _, f in a.folder:GetChildren() do
if f:IsA("Folder") or f:IsA("Model") then
measure(f.Name, f)
end
end
local road = E.roadOf(a)
if road then
measure("Road", road)
end
table.sort(rows, function(x, y)
return x.parts > y.parts
end)
return rows, total
end

function E.bake(a, name)
local out = Instance.new("Folder")
out.Name = name or (a.folder.Name .. " (baked)")
local n = 0
for _, layerFolder in a.folder:GetChildren() do
local dst = Instance.new("Folder")
dst.Name = layerFolder.Name
for _, inst in layerFolder:GetDescendants() do
if CollectionService:HasTag(inst, E.TAG) then
CollectionService:RemoveTag(inst, E.TAG)
for k in inst:GetAttributes() do
if string.sub(k, 1, 3) == "SS_" then
inst:SetAttribute(k, nil)
end
end
n += 1
end
end
for _, c in layerFolder:GetChildren() do
c.Parent = dst
end -- models (or streaming chunks) keep their grouping
dst.Parent = out
layerFolder.Parent = nil
end
local road = E.roadOf(a) -- a path's road goes with it, no longer rebuilt from the curve
if road then
local link = road:FindFirstChild("Area")
if link then
link:Destroy()
end
road.Name = "Road"
road.Parent = out
end
out.Parent = workspace
return out, n
end

function E.loadArea(folder)
local a = {
folder = folder,
rows = {},
count = 0,
cell = folder:GetAttribute("SS_Cell") or E.MASK_CELL,
topY = folder:GetAttribute("SS_TopY") or 0,
seed = folder:GetAttribute("SS_Seed") or 1,
edge = folder:GetAttribute("SS_Edge") or 12,
size = folder:GetAttribute("SS_Size") or 1, -- "Size of everything": multiplies every object's size range
patches = folder:GetAttribute("SS_Patches") or 0, -- groves and clearings shared by all objects (0 = off)
patchSize = folder:GetAttribute("SS_PatchSize") or 60,
pattern = folder:GetAttribute("SS_Pattern") or "Groves", -- which noise the patches follow (E.PATTERNS)
zones = folder:GetAttribute("SS_Zones") or 0, -- colour zones' strength (0 = off)
zoneMood = folder:GetAttribute("SS_ZoneMood") or "Autumn", -- their colour (E.ZONE_MOODS)
windDir = folder:GetAttribute("SS_Wind") or 0, -- the way leaning objects lean (degrees, 0 = +Z)
layers = {},
}
for cz, rest in string.gmatch(folder:GetAttribute("SS_Mask") or "", "(-?%d+):([^|]*)") do
for s, e in string.gmatch(rest, "(-?%d+)~(-?%d+)") do
for cx = tonumber(s), tonumber(e) do
E.setCell(a, cx, tonumber(cz), true)
end
end
end
a.layers, a.lost, a.relinked = E.layersFromJSON(folder:GetAttribute("SS_Layers"))
a.locked = folder:GetAttribute("SS_Locked") == true
a.removed = {}
local okR, rem = pcall(HttpService.JSONDecode, HttpService, folder:GetAttribute("SS_Removed") or "[]")
for _, e in (okR and type(rem) == "table") and rem or {} do
if type(e) == "table" and tonumber(e[1]) and tonumber(e[2]) and tonumber(e[3]) then
a.removed[e[1]] = a.removed[e[1]] or {}
table.insert(a.removed[e[1]], { e[2], e[3] })
end
end
a.on = {}
local okO, on = pcall(HttpService.JSONDecode, HttpService, folder:GetAttribute("SS_On") or "[]")
for _, p in (okO and type(on) == "table") and on or {} do
local inst = type(p) == "table" and resolve(p)
if inst and inst:IsA("BasePart") then
table.insert(a.on, inst)
end
end
local okS, sd = pcall(HttpService.JSONDecode, HttpService, folder:GetAttribute("SS_Spline") or "null")
if okS and type(sd) == "table" and type(sd.pts) == "table" then
local function readPts(list)
local pts = {}
for _, q in list do
if type(q) == "table" and #q >= 6 then
local n = Vector3.new(q[4], q[5], q[6])
local pt = {
p = Vector3.new(q[1], q[2], q[3]),
n = n.Magnitude > 1e-4 and n.Unit or Vector3.yAxis,
sharp = (q[7] or 0) % 2 == 1 or nil,
raised = (q[7] or 0) >= 2 or nil,
}
if tonumber(q[8]) and q[8] ~= 1 then
pt.w = q[8]
end
if tonumber(q[9]) and q[9] ~= 1 then
pt.s = q[9]
end
if #q >= 12 then
pt.h = Vector3.new(q[10], q[11], q[12])
end
table.insert(pts, pt)
end
end
return pts
end
local sp = {
pts = readPts(sd.pts),
closed = sd.closed == true,
width = tonumber(sd.width) or 0,
snap = sd.snap ~= false,
walls = sd.walls == true,
branches = {},
}
if type(sd.surface) == "table" then
sp.surface = {
on = sd.surface.on == true,
style = tostring(sd.surface.style or "Asphalt"),
thick = tonumber(sd.surface.thick) or 1,
width = tonumber(sd.surface.width),
}
end
for _, b in (type(sd.branches) == "table" and sd.branches or {}) do
local pts = type(b) == "table" and readPts(b) or {}
if #pts >= 2 then
table.insert(sp.branches, { pts = pts, closed = false })
end
end
a.spline = sp
end
if a.cell > E.MASK_CELL and a.cell % E.MASK_CELL == 0 then
local k = a.cell // E.MASK_CELL
local old = a.rows
a.rows, a.count = {}, 0
for cz, row in old do
for cx in row do
for i = 0, k - 1 do
for j = 0, k - 1 do
E.setCell(a, cx * k + i, cz * k + j, true)
end
end
end
end
for _, l in a.layers do
if l.paint then
local np = {}
for cz, r in l.paint do
for cx, v in r do
for j = 0, k - 1 do
local row = np[cz * k + j] or {}
np[cz * k + j] = row
for i = 0, k - 1 do
row[cx * k + i] = v
end
end
end
end
l.paint = np
end
end
a.cell = E.MASK_CELL
end
return a
end

function E.fillPolygon(a, poly, on, allow)
local changed, c, n = {}, a.cell, #poly
if n < 3 then
return changed
end
local minZ, maxZ = math.huge, -math.huge
for _, p in poly do
minZ = math.min(minZ, p[2])
maxZ = math.max(maxZ, p[2])
end
for cz = math.floor(minZ / c), math.floor(maxZ / c) do
local z = (cz + 0.5) * c
local xs = {}
for i = 1, n do
local p, q = poly[i], poly[i % n + 1]
if (p[2] <= z and q[2] > z) or (q[2] <= z and p[2] > z) then
table.insert(xs, p[1] + (z - p[2]) / (q[2] - p[2]) * (q[1] - p[1]))
end
end
table.sort(xs)
for k = 1, #xs - 1, 2 do
for cx = math.ceil(xs[k] / c - 0.5), math.floor(xs[k + 1] / c - 0.5) do
if E.hasCell(a, cx, cz) ~= on and (not allow or allow(cx, cz)) then
E.setCell(a, cx, cz, on)
table.insert(changed, { cx, cz })
end
end
end
end
return changed
end

local N8 = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }
function E.maskMorph(a, op)
local minCX, maxCX, minCZ, maxCZ = math.huge, -math.huge, math.huge, -math.huge
for cz, row in a.rows do
minCZ = math.min(minCZ, cz)
maxCZ = math.max(maxCZ, cz)
for cx in row do
minCX = math.min(minCX, cx)
maxCX = math.max(maxCX, cx)
end
end
if minCX == math.huge then
return {}
end
local has = E.hasCell
local set, unset = {}, {}
if op == "holes" then
local x0, x1, z0, z1 = minCX - 1, maxCX + 1, minCZ - 1, maxCZ + 1
local W = x1 - x0 + 1
local seen, queue, qi = {}, {}, 1
local function push(cx, cz)
local k = (cz - z0) * W + (cx - x0)
if not seen[k] and not has(a, cx, cz) then
seen[k] = true
table.insert(queue, cx)
table.insert(queue, cz)
end
end
for cx = x0, x1 do
push(cx, z0)
push(cx, z1)
end
for cz = z0, z1 do
push(x0, cz)
push(x1, cz)
end
while qi < #queue do
local cx, cz = queue[qi], queue[qi + 1]
qi += 2
for d = 1, 4 do
local nx, nz = cx + N8[d][1], cz + N8[d][2]
if nx >= x0 and nx <= x1 and nz >= z0 and nz <= z1 then
push(nx, nz)
end
end
end
for cz = minCZ, maxCZ do
for cx = minCX, maxCX do
if not has(a, cx, cz) and not seen[(cz - z0) * W + (cx - x0)] then
table.insert(set, { cx, cz })
end
end
end
else
for cz = minCZ - 1, maxCZ + 1 do
for cx = minCX - 1, maxCX + 1 do
local on = has(a, cx, cz)
local nOn = 0
for d = 1, 8 do
if has(a, cx + N8[d][1], cz + N8[d][2]) then
nOn += 1
end
end
if op == "grow" then
if not on and nOn > 0 then
table.insert(set, { cx, cz })
end
elseif op == "shrink" then
if on and nOn < 8 then
table.insert(unset, { cx, cz })
end
elseif op == "smooth" then -- by neighbours in the 3x3 block (3 or fewer: off, 6 or more: on): rounds corners, fills notches, drops specks
local total = nOn + (on and 1 or 0)
if on and total <= 3 then
table.insert(unset, { cx, cz })
elseif not on and total >= 6 then
table.insert(set, { cx, cz })
end
end
end
end
end
for _, c in set do
E.setCell(a, c[1], c[2], true)
end
for _, c in unset do
E.setCell(a, c[1], c[2], false)
end
table.move(unset, 1, #unset, #set + 1, set)
return set
end

function E.ensureFolder(a)
local f = a.folder
if f and f:IsDescendantOf(workspace) then
return
end
local ok = f ~= nil and pcall(function()
f.Parent = E.getOut()
end)
if not ok then
local n = Instance.new("Folder")
n.Name = f and f.Name or "Area"
n.Parent = E.getOut()
a.folder = n
end
end

function E.saveArea(a)
E.ensureFolder(a)
local f = a.folder
f:SetAttribute("SS_Area", true)
f:SetAttribute("SS_Cell", a.cell)
f:SetAttribute("SS_TopY", a.topY)
f:SetAttribute("SS_Seed", a.seed)
f:SetAttribute("SS_Edge", a.edge or 12)
f:SetAttribute("SS_Size", (a.size and a.size ~= 1) and a.size or nil)
f:SetAttribute("SS_Patches", (a.patches or 0) > 0 and a.patches or nil)
f:SetAttribute("SS_PatchSize", (a.patchSize and a.patchSize ~= 60) and a.patchSize or nil)
f:SetAttribute("SS_Pattern", (a.pattern and a.pattern ~= "Groves") and a.pattern or nil)
f:SetAttribute("SS_Zones", (a.zones or 0) > 0 and a.zones or nil)
f:SetAttribute("SS_ZoneMood", (a.zoneMood and a.zoneMood ~= "Autumn") and a.zoneMood or nil)
f:SetAttribute("SS_Wind", (a.windDir or 0) ~= 0 and a.windDir or nil)
f:SetAttribute("SS_Mask", encodeMask(a.rows))
local sp = a.spline
if sp and #sp.pts > 0 then
local function pack(list)
local pts = {}
for _, q in list do
table.insert(pts, {
math.floor(q.p.X * 100 + 0.5) / 100,
math.floor(q.p.Y * 100 + 0.5) / 100,
math.floor(q.p.Z * 100 + 0.5) / 100,
math.floor(q.n.X * 1000 + 0.5) / 1000,
math.floor(q.n.Y * 1000 + 0.5) / 1000,
math.floor(q.n.Z * 1000 + 0.5) / 1000,
(q.sharp and 1 or 0) + (q.raised and 2 or 0), -- flags: 1 sharp, 2 raised
math.floor((q.w or 1) * 100 + 0.5) / 100,
math.floor((q.s or 1) * 100 + 0.5) / 100,
})
if q.h then
local e = pts[#pts]
table.insert(e, math.floor(q.h.X * 100 + 0.5) / 100)
table.insert(e, math.floor(q.h.Y * 100 + 0.5) / 100)
table.insert(e, math.floor(q.h.Z * 100 + 0.5) / 100)
end
end
return pts
end
local br = {}
for _, b in sp.branches or {} do
if #b.pts >= 2 then
table.insert(br, pack(b.pts))
end
end
f:SetAttribute(
"SS_Spline",
HttpService:JSONEncode({
pts = pack(sp.pts),
closed = sp.closed,
width = sp.width,
snap = sp.snap,
walls = sp.walls,
branches = #br > 0 and br or nil,
surface = sp.surface,
})
)
else
f:SetAttribute("SS_Spline", nil)
end
f:SetAttribute("SS_Layers", E.layersToJSON(a.layers, nil, a.lost))
f:SetAttribute("SS_Locked", a.locked or nil)
local on = {}
for _, p in a.on or {} do
if p.Parent then
table.insert(on, pathOf(p))
end
end
f:SetAttribute("SS_On", #on > 0 and HttpService:JSONEncode(on) or nil)
local rem = {}
for h, list in a.removed or {} do
for _, p in list do
table.insert(rem, { h, p[1], p[2] })
end
end
f:SetAttribute("SS_Removed", #rem > 0 and HttpService:JSONEncode(rem) or nil)
end

function E.copyAt(a, inst)
local cur = inst
while cur and cur ~= a.folder do
if cur:GetAttribute("SS_Type") and cur:IsDescendantOf(a.folder) then
return cur
end
cur = cur.Parent
end
return nil
end
function E.removeCopy(a, copy)
local h = copy:GetAttribute("SS_L")
if not h then
return nil
end
if copy:GetAttribute("SS_Pin") then -- put down by hand: its pin goes, so it isn't put back
for _, l in a.layers do
if l._h == h then
E.unpin(l, copy:GetAttribute("SS_X") or 0, copy:GetAttribute("SS_Z") or 0)
end
end
E.dropOutput(copy)
return h
end
a.removed = a.removed or {}
a.removed[h] = a.removed[h] or {}
table.insert(a.removed[h], { copy:GetAttribute("SS_X") or 0, copy:GetAttribute("SS_Z") or 0 })
E.dropOutput(copy)
return h
end
function E.removedCount(a)
local n = 0
for _, list in a.removed or {} do
n += #list
end
return n
end
local function removedAt(a, h, x, z)
for _, p in (a.removed and a.removed[h]) or {} do
if math.abs(p[1] - x) < 0.3 and math.abs(p[2] - z) < 0.3 then
return true
end
end
return false
end
E.removedAt = removedAt

function E.clearZones(except)
local t = {}
for _, f in E.listAreas() do
if f ~= except and f:GetAttribute("SS_Kind") == "Clear" then
local z = E.loadArea(f)
if z.count > 0 then
table.insert(t, z)
end
end
end
return t
end
function E.isCleared(zones, x, z)
for _, zn in zones or {} do
if E.hasCell(zn, math.floor(x / zn.cell), math.floor(z / zn.cell)) then
return true
end
end
return false
end

function E.fillFromParts(a, parts)
local changed, c = {}, a.cell
local rp = RaycastParams.new()
rp.FilterType = Enum.RaycastFilterType.Include
rp.FilterDescendantsInstances = parts
for _, p in parts do
if not table.find(a.on, p) then
table.insert(a.on, p)
end
local cf, h = p.CFrame, p.Size / 2
local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
for sx = -1, 1, 2 do
for sy = -1, 1, 2 do
for sz = -1, 1, 2 do
local w = cf:PointToWorldSpace(Vector3.new(h.X * sx, h.Y * sy, h.Z * sz))
lo, hi = lo:Min(w), hi:Max(w)
end
end
end
if (hi.X - lo.X) * (hi.Z - lo.Z) / (c * c) > 250000 then
continue
end -- a baseplate: paint that by hand
for cz = math.floor(lo.Z / c), math.floor(hi.Z / c) do
for cx = math.floor(lo.X / c), math.floor(hi.X / c) do
local o = Vector3.new((cx + 0.5) * c, hi.Y + 1, (cz + 0.5) * c)
if workspace:Raycast(o, Vector3.new(0, lo.Y - hi.Y - 2, 0), rp) and E.setCell(a, cx, cz, true) then
table.insert(changed, { cx, cz })
end
end
end
a.topY = math.max(a.topY or 0, hi.Y)
end
return changed
end

function E.createArea(name, layersFrom)
local f = Instance.new("Folder")
f.Name = name
f.Parent = E.getOut()
local a = {
folder = f,
rows = {},
count = 0,
cell = E.MASK_CELL,
topY = 0,
seed = math.random(1, 999999),
edge = 12,
layers = {},
on = {},
removed = {},
}
for _, l in layersFrom or {} do
local c = E.makeLayer(l.inst, l.type, l.s, E.variantList(l))
if c then
if l.post then
E.setPost(c, l.post.inst)
end
table.insert(a.layers, c)
end
end
E.saveArea(a)
return a
end

function E.roadOf(a)
local roads = workspace:FindFirstChild(E.ROADS)
for _, f in roads and roads:GetChildren() or {} do
local link = f:FindFirstChild("Area")
if link and link:IsA("ObjectValue") and link.Value == a.folder then
return f
end
end
return nil
end
function E.clearOutputs(a)
for _, c in a.folder:GetChildren() do
E.dropOutput(c)
end -- not kept for undo: undo rebuilds from the area
local surface = E.roadOf(a)
if surface then
E.dropOutput(surface)
end
end
end
end)()
-- #module Paths
MODULES["Paths"] = (function()
--[[
Smart Scatter — Engine/Paths: splines (smooth curves through clicked points) and the road surfaces laid along them.
Adds to E (the engine API); shares internals with the other engine modules through I.
]]

return function(E, I)
local function knot(t, a, b)
return t + math.max((b - a).Magnitude, 1e-4) ^ 0.5
end
local function catmull(p0, p1, p2, p3, t)
local t1 = knot(0, p0, p1)
local t2 = knot(t1, p1, p2)
local t3 = knot(t2, p2, p3)
local u = t1 + (t2 - t1) * t
local a1 = p0:Lerp(p1, u / t1)
local a2 = p1:Lerp(p2, (u - t1) / (t2 - t1))
local a3 = p2:Lerp(p3, (u - t2) / (t3 - t2))
local b1 = a1:Lerp(a2, u / t2)
local b2 = a2:Lerp(a3, (u - t1) / (t3 - t1))
return b1:Lerp(b2, (u - t1) / (t2 - t1))
end

function E.autoHandle(sp, i)
local pts, n = sp.pts, #sp.pts
if n < 2 then
return Vector3.zero
end
local closed = sp.closed and n >= 3
local function at(k)
if closed then
return pts[(k - 1) % n + 1].p
end
return pts[math.clamp(k, 1, n)].p
end
return (at(i + 1) - at(i - 1)) / 6
end

local function bezier(a, c1, c2, b, t)
local u = 1 - t
return a * (u * u * u) + c1 * (3 * u * u * t) + c2 * (3 * u * t * t) + b * (t * t * t)
end

function E.splineCurve(sp, step)
local pts = sp.pts
local n = #pts
local P, U, S, W, Z, R = {}, {}, {}, {}, {}, {}
if n == 0 then
return P, U, S, W, Z, R
end
local function raised(q)
return q.raised and 1 or 0
end
if n == 1 then
return { pts[1].p }, { pts[1].n }, { 1 }, { pts[1].w or 1 }, { pts[1].s or 1 }, { raised(pts[1]) }
end
local closed = sp.closed and n >= 3
local function cp(i)
if closed then
return pts[(i - 1) % n + 1].p
end
if i < 1 then
return pts[1].p * 2 - pts[2].p
end
if i > n then
return pts[n].p * 2 - pts[n - 1].p
end
return pts[i].p
end
local segs = closed and n or n - 1
for i = 1, segs do
local j = i % n + 1
local a, b = pts[i], pts[j]
local steps = math.max(1, math.ceil((b.p - a.p).Magnitude / step))
local c1, c2
if a.h or b.h then
c1 = a.p + (a.h or (a.sharp and Vector3.zero or E.autoHandle(sp, i)))
c2 = b.p - (b.h or (b.sharp and Vector3.zero or E.autoHandle(sp, j)))
end
local wa, wb, za, zb, ra, rb = a.w or 1, b.w or 1, a.s or 1, b.s or 1, raised(a), raised(b)
for k = 0, steps - 1 do
local t = k / steps
if c1 then
table.insert(P, bezier(a.p, c1, c2, b.p, t))
else
table.insert(P, catmull(a.sharp and a.p * 2 - b.p or cp(i - 1), cp(i), cp(i + 1), b.sharp and b.p * 2 - a.p or cp(i + 2), t))
end
local nn = a.n:Lerp(b.n, t)
table.insert(U, nn.Magnitude > 1e-4 and nn.Unit or Vector3.yAxis)
table.insert(S, i)
local e = t * t * (3 - 2 * t)
table.insert(W, wa + (wb - wa) * e)
table.insert(Z, za + (zb - za) * e)
table.insert(R, ra + (rb - ra) * e)
end
end
local last = closed and pts[1] or pts[n]
table.insert(P, last.p)
table.insert(U, last.n)
table.insert(S, segs)
table.insert(W, last.w or 1)
table.insert(Z, last.s or 1)
table.insert(R, raised(last))
return P, U, S, W, Z, R
end

local function insideSolid(p, rp)
local T = workspace.Terrain
local ok, mats, occ = pcall(function()
local lo = Vector3.new(math.floor(p.X / 4), math.floor(p.Y / 4), math.floor(p.Z / 4)) * 4 -- the voxel p is in
return T:ReadVoxels(Region3.new(lo, lo + Vector3.new(4, 4, 4)), 4)
end)
if ok and mats.Size.X > 0 then
local m, o = mats[1][1][1], occ[1][1][1]
if m ~= Enum.Material.Air and m ~= Enum.Material.Water and o > 0.5 then
return true
end
end
local op = OverlapParams.new()
op.FilterType = rp.FilterType
op.FilterDescendantsInstances = rp.FilterDescendantsInstances
op.RespectCanCollide = true
for _, part in workspace:GetPartBoundsInRadius(p, 0.05, op) do
if part ~= T and part.CanCollide then
return true
end
end
return false
end

local function project(pos, up, rp)
local hit = workspace:Raycast(pos + up * 4, -up * 12, rp) or workspace:Raycast(pos + up * 60, -up * 120, rp)
if hit and (pos - hit.Position):Dot(up) > 1.5 and insideSolid(pos + up * 0.5, rp) then
local top = workspace:Raycast(pos + up * 60, -up * 120, rp)
if top and (top.Position - pos):Dot(up) > -1.5 then
hit = top
end
end
if hit then
return hit.Position, hit.Normal
end
return pos, up
end
function E.splineSamples(sp, rp)
local P, U, _, W, Z, R = E.splineCurve(sp, 0.75)
if sp.snap then
for k = 1, #P do
local up = sp.walls and U[k] or Vector3.yAxis
local g, gn = project(P[k], up, rp)
local lift = math.max((P[k] - g):Dot(up), 0) * R[k]
P[k], U[k] = g + up * lift, lift > 0.05 and gn:Lerp(up, R[k]).Unit or gn
end
end
return { P = P, U = U, W = W, Z = Z, R = R, snap = sp.snap, rp = rp }
end

function E.joinToPoint(sp, ref, target)
if ref.cv == sp and target.cv == sp and #sp.pts >= 4 and ((ref.i == #sp.pts and target.i == 1) or (ref.i == 1 and target.i == #sp.pts)) then
table.remove(sp.pts, ref.i)
sp.closed = true
return "closed"
end
local q, o = ref.cv.pts[ref.i], target.cv.pts[target.i]
if not (q and o) then
return nil
end -- a stale reference: nothing to join
q.p, q.n = o.p, o.n
return "joined"
end
function E.joinToCurve(ref, cv, seg, p, n)
local q = ref.cv.pts[ref.i] -- before the insert: it may shift indices on the same curve
local a, b = cv.pts[seg], cv.pts[seg + 1] or cv.pts[1]
local t = 0.5
if a and b and (b.p - a.p).Magnitude > 1e-3 then
t = math.clamp((p - a.p):Dot(b.p - a.p) / (b.p - a.p).Magnitude ^ 2, 0, 1)
end
local function mix(k)
local va, vb = a and a[k] or 1, b and b[k] or 1
local v = va + (vb - va) * t
return math.abs(v - 1) > 1e-3 and v or nil
end
table.insert(cv.pts, seg + 1, { p = p, n = n, w = mix("w"), s = mix("s") })
q.p, q.n = p, n
end
function E.thinStroke(s, spacing)
local drop = {}
if #s <= 2 then
return drop
end
for _ = 1, 3 do
local p = table.create(#s)
for k, q in s do
p[k] = q.p
end
for k = 2, #s - 1 do
s[k].p = p[k] * 0.5 + (p[k - 1] + p[k + 1]) * 0.25
end
end
local keep = { [1] = true, [#s] = true }
local tol = spacing * 0.3
local function rdp(a, b)
local A, B = s[a].p, s[b].p
local ab = Vector3.new(B.X - A.X, 0, B.Z - A.Z)
local len = ab.Magnitude
local worst, wi = 0, nil
for k = a + 1, b - 1 do
local v = Vector3.new(s[k].p.X - A.X, 0, s[k].p.Z - A.Z)
local dist = len > 1e-4 and math.abs(v.X * ab.Z - v.Z * ab.X) / len or v.Magnitude
dist = math.max(dist, math.abs(s[k].p.Y - (A.Y + (B.Y - A.Y) * (k - a) / (b - a))) * 0.5)
if dist > worst then
worst, wi = dist, k
end
end
if wi and worst > tol then
keep[wi] = true
rdp(a, wi)
rdp(wi, b)
end
end
rdp(1, #s)
for k, q in s do
if not keep[k] then
drop[q] = true
end
end
return drop
end

function E.splineCurves(sp)
local list = {}
if not sp then
return list
end
if #sp.pts >= 2 then
table.insert(list, sp)
end
for _, b in sp.branches or {} do
if #b.pts >= 2 then
table.insert(list, { pts = b.pts, closed = false, snap = sp.snap, width = sp.width, walls = sp.walls })
end
end
return list
end

E.ROAD_STYLES = {
{ name = "Asphalt", mat = Enum.Material.Asphalt, color = Color3.fromRGB(64, 64, 70) },
{ name = "Concrete", mat = Enum.Material.Concrete, color = Color3.fromRGB(150, 150, 150) },
{ name = "Cobble", mat = Enum.Material.Cobblestone, color = Color3.fromRGB(128, 122, 116) },
{ name = "Brick", mat = Enum.Material.Brick, color = Color3.fromRGB(143, 76, 58) },
{ name = "Dirt", mat = Enum.Material.Ground, color = Color3.fromRGB(107, 84, 58) },
{ name = "Sand", mat = Enum.Material.Sand, color = Color3.fromRGB(216, 199, 149) },
{ name = "Planks", mat = Enum.Material.WoodPlanks, color = Color3.fromRGB(139, 106, 74) },
}
local function surfaceStyle(name)
for _, st in E.ROAD_STYLES do
if st.name == name then
return st
end
end
return E.ROAD_STYLES[1]
end
local function wedge(parent, style, size, cf)
local w = Instance.new("WedgePart")
w.Anchored = true
w.TopSurface, w.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
w.Material, w.Color = style.mat, style.color
w.CastShadow = false
w.Size, w.CFrame = size, cf
w.Parent = parent
end
local function triangle(parent, style, a, b, c, thick)
local ab, ac, bc = b - a, c - a, c - b
local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
if abd > acd and abd > bcd then
c, a = a, c
elseif acd > bcd and acd > abd then
a, b = b, a
end
ab, ac, bc = b - a, c - a, c - b
local nrm = ac:Cross(ab)
if nrm.Magnitude < 1e-4 or bc.Magnitude < 1e-3 then
return 0
end
local right = nrm.Unit
local up = bc:Cross(right).Unit
local back = bc.Unit
local height = math.abs(ab:Dot(up))
if height < 1e-3 then
return 0
end
local sink = (right.Y >= 0 and -right or right) * (thick / 2) -- the top face sits on the triangle, depth goes down
local n = 0
local d0, d1 = math.abs(ab:Dot(back)), math.abs(ac:Dot(back))
if d0 > 1e-3 then
wedge(parent, style, Vector3.new(thick, height, d0), CFrame.fromMatrix((a + b) / 2 + sink, right, up, back))
n += 1
end
if d1 > 1e-3 then
wedge(parent, style, Vector3.new(thick, height, d1), CFrame.fromMatrix((a + c) / 2 + sink, -right, up, -back))
n += 1
end
return n
end
function E.roadWidth(sp)
local sf = sp and sp.surface
if not (sf and sf.on) then
return 0
end
return math.max(tonumber(sf.width) or sp.width or 0, 0)
end

function E.buildSurface(a, rp)
local sp = a.spline
local sf = sp and sp.surface
local width = E.roadWidth(sp)
if width <= 0 then
return nil, 0
end
local style = surfaceStyle(sf.style)
local thick = math.clamp(tonumber(sf.thick) or 1, 0.2, 20)
local R0 = width / 2
local folder = Instance.new("Folder")
folder.Name = "Surface"
folder:SetAttribute("SS_Surface", (style.name == "Dirt" or style.name == "Sand") and "Path" or "Road") -- also how scans read it
local parts = 0
local all = {}
for ci, cv in E.splineCurves(sp) do
all[ci] = { smp = E.splineSamples(cv, rp) }
end
local function nearest(j, q)
local Pj, Wj = all[j].smp.P, all[j].smp.W
local best, bw, atEnd = math.huge, 1, false
for k = 1, #Pj - 1 do
local a, b = Pj[k], Pj[k + 1]
local ab = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
local aq = Vector3.new(q.X - a.X, 0, q.Z - a.Z)
local L2 = ab:Dot(ab)
local t = L2 > 1e-9 and math.clamp(aq:Dot(ab) / L2, 0, 1) or 0
local d = (aq - ab * t).Magnitude
if d < best then
best, bw = d, Wj[k] + (Wj[k + 1] - Wj[k]) * t
atEnd = (k == 1 and t < 1e-3) or (k == #Pj - 1 and t > 1 - 1e-3)
end
end
return best, R0 * bw, atEnd
end
for ci, rec in all do
local smp = rec.smp
local P, W = smp.P, smp.W
local n = #P
if n >= 2 then
local loop = (P[1] - P[n]).Magnitude < 0.05
local st, lastDir, run, lastW = { 1 }, nil, 0, W[1]
for k = 2, n - 1 do
local d = P[k + 1] - P[k]
run += (P[k] - P[k - 1]).Magnitude
local dir = Vector3.new(d.X, 0, d.Z).Magnitude > 0.05 and d.Unit or lastDir
local ref = P[k] - P[st[#st]]
ref = ref.Magnitude > 1e-5 and ref.Unit or dir
if dir and ref and (dir:Dot(ref) < 0.9965 or run >= 48 or math.abs(W[k] - lastW) > 0.04) then
table.insert(st, k)
run, lastW = 0, W[k]
end
lastDir = dir
end
table.insert(st, n)
local lift = 0.04 + (ci - 1) * 0.03 -- branches sit a hair higher where they overlap the main road
local function flat(v)
if not v then
return nil
end
v = Vector3.new(v.X, 0, v.Z)
return v.Magnitude > 0.05 and v.Unit or nil
end
local function ground(q)
local hit = workspace:Raycast(q + Vector3.new(0, 60, 0), Vector3.new(0, -120, 0), rp)
return hit and hit.Position or q
end
local cache = {}
local function edgeAt(k)
local hitC = cache[k]
if hitC then
return hitC[1], hitC[2], hitC[3]
end
local m = 6
local prev = k > 1 and math.max(k - m, 1) or (loop and n - m) or nil
local nxt = k < n and math.min(k + m, n) or (loop and 1 + m) or nil
local t0 = flat(prev and (P[k] - P[prev]) or nil)
local t1 = flat(nxt and (P[nxt] - P[k]) or nil)
local t = (t0 and t1) and (t0 + t1) or t0 or t1 or Vector3.zAxis
t = t.Magnitude > 1e-5 and t.Unit or (t1 or t0 or Vector3.zAxis)
local right = t:Cross(Vector3.yAxis)
local miter = (t0 and t1) and 1 / math.max(math.cos(math.acos(math.clamp(t0:Dot(t1), -1, 1)) / 2), 0.5) or 1
local half = R0 * (W[k] or 1) * miter
local l, r, c = P[k] + right * half, P[k] - right * half, P[k]
if smp.snap then
local up = smp.R and smp.R[k] or 0
local y = P[k].Y
l, r, c = ground(l), ground(r), ground(c)
if up > 0 then
l = l:Lerp(Vector3.new(l.X, math.max(y, l.Y), l.Z), up)
r = r:Lerp(Vector3.new(r.X, math.max(y, r.Y), r.Z), up)
c = c:Lerp(Vector3.new(c.X, math.max(y, c.Y), c.Z), up)
end
end
l, r, c = l + Vector3.yAxis * lift, r + Vector3.yAxis * lift, c + Vector3.yAxis * lift
cache[k] = { l, r, c }
return l, r, c
end
if smp.snap then
local j, guard = 1, 0
while j < #st and guard < 4000 do
guard += 1
local k0, k1 = st[j], st[j + 1]
local split
if k1 - k0 >= 2 then
local l0, r0, c0 = edgeAt(k0)
local l1, r1, c1 = edgeAt(k1)
local stepK = math.max(1, math.floor((k1 - k0) / math.max(math.ceil((k1 - k0) * 0.75 / 6), 1)))
local worst = 0.3
for k = k0 + stepK, k1 - 1, stepK do
local f = (k - k0) / (k1 - k0)
local lk, rk, ck = edgeAt(k)
local d = math.max(
math.abs(lk.Y - (l0.Y + (l1.Y - l0.Y) * f)),
math.abs(rk.Y - (r0.Y + (r1.Y - r0.Y) * f)),
math.abs(ck.Y - (c0.Y + (c1.Y - c0.Y) * f))
)
if d > worst then
worst, split = d, k
end
end
end
if split then
table.insert(st, j + 1, split)
else
j += 1
end
end
end
local L, Rr, C = {}, {}, {}
for j, k in st do
L[j], Rr[j], C[j] = edgeAt(k)
end
local function trim(fromStart)
local kEnd = fromStart and 1 or n
for j = 1, ci - 1 do
local d, hw, atEnd = nearest(j, P[kEnd])
if d < hw - 0.05 and not atEnd then
local function inside(q)
local dd, hh = nearest(j, q)
return dd < hh
end
local function cross(side)
local prevK = kEnd
local step = fromStart and 1 or -1
local k = kEnd
while k >= 1 and k <= n do
local l, r = edgeAt(k)
local q = side == 1 and l or r
if not inside(q) then
if k == kEnd then
return q, k
end
local lp, rp2 = edgeAt(prevK)
local a0 = side == 1 and lp or rp2
local lo, hi = 0, 1
for _ = 1, 10 do
local mid = (lo + hi) / 2
if inside(a0:Lerp(q, mid)) then
lo = mid
else
hi = mid
end
end
return a0:Lerp(q, hi), k
end
prevK = k
k += step
end
return nil
end
local lx, kl = cross(1)
local rx, kr = cross(-1)
if not lx or not rx then
return "gone"
end -- the whole road lies inside the other one
return { l = lx, r = rx, k = fromStart and math.max(kl, kr) or math.min(kl, kr) }
end
end
return nil
end
if not loop then
local cut0, cut1 = trim(true), trim(false)
if cut0 == "gone" or cut1 == "gone" then
continue
end
if cut0 or cut1 then
local nL, nR, nC = {}, {}, {}
local function push(l, r, c)
table.insert(nL, l)
table.insert(nR, r)
table.insert(nC, c or (l + r) / 2)
end
if cut0 then
push(cut0.l, cut0.r)
end
for idx, k in st do
if (not cut0 or k >= cut0.k) and (not cut1 or k <= cut1.k) then
push(L[idx], Rr[idx], C[idx])
end
end
if cut1 then
push(cut1.l, cut1.r)
end
if #nL < 2 then
continue
end
L, Rr, C = nL, nR, nC
end
end
for j = 1, #L - 1 do
local across, along = L[j] - Rr[j], L[j + 1] - L[j]
local mid = (L[j] + Rr[j]) / 2
local flatAcross = math.abs(C[j].Y - mid.Y) < 0.05 and math.abs(C[j + 1].Y - (L[j + 1].Y + Rr[j + 1].Y) / 2) < 0.05
if not flatAcross then
for _, side in { { L, C }, { C, Rr } } do
local A, B = side[1], side[2]
parts += triangle(folder, style, A[j], B[j], B[j + 1], thick)
parts += triangle(folder, style, A[j], B[j + 1], A[j + 1], thick)
end
elseif ((Rr[j + 1] - Rr[j]) - along).Magnitude < 0.02 and math.abs(across.Unit:Dot(along.Unit)) < 0.01 then
local nrm = along:Cross(across).Unit
if nrm.Y < 0 then
nrm = -nrm
end
local b = Instance.new("Part")
b.Anchored = true
b.TopSurface, b.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
b.Material, b.Color, b.CastShadow = style.mat, style.color, false
b.Size = Vector3.new(across.Magnitude, thick, along.Magnitude)
b.CFrame = CFrame.fromMatrix((L[j] + Rr[j + 1]) / 2 - nrm * (thick / 2), across.Unit, nrm)
b.Parent = folder
parts += 1
else
parts += triangle(folder, style, L[j], Rr[j], Rr[j + 1], thick)
parts += triangle(folder, style, L[j], Rr[j + 1], L[j + 1], thick)
end
end
end
end
if parts == 0 then -- no curve long enough for a road yet
folder:Destroy()
return nil, 0
end
return folder, parts
end

function E.roadTest(a, rp)
local sp, cells, g = a.spline, {}, 2
for _, cv in E.splineCurves(sp) do
local smp = E.splineSamples(cv, rp)
for k, p in smp.P do
local R = E.roadWidth(sp) / 2 * smp.W[k]
for cx = math.floor((p.X - R) / g), math.floor((p.X + R) / g) do
for cz = math.floor((p.Z - R) / g), math.floor((p.Z + R) / g) do
local dx, dz = (cx + 0.5) * g - p.X, (cz + 0.5) * g - p.Z
if dx * dx + dz * dz <= R * R then
cells[cx * 1000003 + cz] = true
end
end
end
end
end
return function(x, z)
return cells[math.floor(x / g) * 1000003 + math.floor(z / g)] == true
end
end

function E.maskFromSpline(a, rp)
local sp = a.spline
a.rows, a.count = {}, 0
if not sp or (sp.width or 0) <= 0 then
return
end
local c, R0, road = a.cell, sp.width / 2, E.roadWidth(sp) / 2 -- the road down the middle stays empty
local top = -math.huge
for _, cv in E.splineCurves(sp) do
local smp = E.splineSamples(cv, rp)
local lastX, lastZ
for k, p in smp.P do
top = math.max(top, p.Y)
local R = R0 * smp.W[k] -- the strip widens and narrows with each point's width
if not lastX or (p.X - lastX) ^ 2 + (p.Z - lastZ) ^ 2 >= (c * 0.5) ^ 2 or k == #smp.P then
lastX, lastZ = p.X, p.Z
if road <= 0 then
E.setCell(a, math.floor(p.X / c), math.floor(p.Z / c), true) -- a strip narrower than a cell still counts
end
for cx = math.floor((p.X - R) / c), math.floor((p.X + R) / c) do
for cz = math.floor((p.Z - R) / c), math.floor((p.Z + R) / c) do
local dx, dz = (cx + 0.5) * c - p.X, (cz + 0.5) * c - p.Z
local d2, rr = dx * dx + dz * dz, road * smp.W[k] + c * 0.5
if d2 <= R * R and d2 > rr * rr then
E.setCell(a, cx, cz, true)
end
end
end
end
end
end
if top > -math.huge then
a.topY = top
end
end

I.triangle = triangle
I.project = project
end
end)()
-- #module Planning
MODULES["Planning"] = (function()
--[[
Smart Scatter — Engine/Planning: rules -> suitability per cell -> how many copies of each object.
Adds to E (the engine API); shares internals with the other engine modules through I.
]]

return function(E, I)
local CORE = I.CORE
local COVERAGE = I.COVERAGE
local MIN_COUNT_R = I.MIN_COUNT_R
local PRIORITY = I.PRIORITY
local strHash = I.strHash

local scaleRange -- (defined just below; placement and lines use it too)
scaleRange = function(l)
local s, k = l.s, l._size or 1
return math.min(s.scaleMin, s.scaleMax) * k, math.max(s.scaleMin, s.scaleMax) * k
end

local function prep(l)
local lo, hi = scaleRange(l)
local avg = (lo + hi) / 2
local wsum, rsum = 0, 0
for _, v in l.variants do
if v.w > 0 then
wsum += v.w
rsum += v.w * v.m.radius * v.size
end
end
l._r = (wsum > 0 and rsum / wsum or l.m.radius) * avg
l._core = l._r * CORE[l.type]
l._wsum = wsum
end

local function score(l, an, i)
local s, c = l.s, an.cls[i]
if not s.surfaces[c] and not an.on[i] then
return 0
end -- parts picked for the area take anything
if math.deg(math.acos(math.clamp(an.ny[i], -1, 1))) > s.maxSlope then
return 0
end
if s.useAlt and an.yMax - an.yMin > 1 then
local t = (an.y[i] - an.yMin) / (an.yMax - an.yMin)
if t < math.min(s.altMin, s.altMax) or t > math.max(s.altMin, s.altMax) then
return 0
end
end
local d, cr = an.dist, l._core
local kB, kR, kW = s.keepBuilding + cr, s.keepRoad + cr, s.keepWater + cr
if d.Buildings[i] < kB then
return 0
end
if not s.surfaces.Road and d.Roads[i] < kR then
return 0
end
if d.Water[i] < kW then
return 0
end
if s.hug == "None" or not d[s.hug] then
return 1
end
local base = (s.hug == "Buildings" and kB) or (s.hug == "Roads" and kR) or (s.hug == "Water" and kW) or 0
local near = math.clamp(1 - math.max(d[s.hug][i] - base, 0) / math.max(s.hugRange, 1), 0, 1)
return (1 - s.hugStrength) + s.hugStrength * near
end

local function isLine(l)
return l.s.place == "Along"
end
E.isLine = isLine
local function prio(l)
return (isLine(l) and l.type ~= "Building") and 1.5 or PRIORITY[l.type]
end
local function before(a, b) -- placement order: big categories first, then bigger assets, then stable by key
if prio(a) ~= prio(b) then
return prio(a) < prio(b)
end
if a.type ~= b.type then
return PRIORITY[a.type] < PRIORITY[b.type]
end
if math.abs(a.m.radius - b.m.radius) > 1e-3 then
return a.m.radius > b.m.radius
end
return E.layerKey(a) < E.layerKey(b)
end

local function ordered(layers)
local t = {}
for _, l in layers do
local weight = 0
for _, v in l.variants do
weight += math.max(v.w, 0)
end
if l.s.enabled and l.s.density > 0 and l.inst.Parent and weight > 0 then -- all shares at 0: places nothing
l._h = strHash(l.s.key ~= "" and l.s.key or E.layerKey(l))
table.insert(t, l)
end
end
table.sort(t, before)
for _, l in t do
l._nearH = nil
if l.s.near ~= "" then
for _, o in t do
if o ~= l and E.layerKey(o) == l.s.near then
l._nearH = o._h
local li, oi = table.find(t, l), table.find(t, o)
if oi > li then
table.remove(t, li)
table.insert(t, table.find(t, o) + 1, l)
end
end
end
end
end
return t
end

local function n2(x, z, o) -- Roblox's noise, -0.5..0.5 in practice, stretched to 0-1
return math.clamp(0.5 + math.noise(x, z, o) * 1.6, 0, 1)
end
local function smooth(t)
return t * t * (3 - 2 * t)
end
E.PATTERNS = { "Groves", "Natural", "Islands", "Veins", "Spots", "Bands" }
E.PATTERN_HINT = {
Groves = "Soft, even rolling patches.",
Natural = "Patches with smaller patches inside them, like a real forest floor.",
Islands = "Clear-cut clusters with open ground between them.",
Veins = "Winding lines of growth, like streams or hedgerows.",
Spots = "Round clusters spread evenly over the area.",
Bands = "Wavy rows across the area, along the wind direction.",
}
local PATTERN = {
Groves = function(x, z, f, o)
return n2(x / f, z / f, o)
end,
Natural = function(x, z, f, o) -- three octaves: big shapes, then detail inside them
local v = n2(x / f, z / f, o) * 0.6 + n2(x * 2.1 / f, z * 2.1 / f, o + 17) * 0.28
return math.clamp(v + n2(x * 4.3 / f, z * 4.3 / f, o + 31) * 0.12, 0, 1)
end,
Islands = function(x, z, f, o) -- the same noise, cut sharply at the middle
return smooth(math.clamp((n2(x / f, z / f, o) - 0.42) / 0.16, 0, 1))
end,
Veins = function(x, z, f, o) -- ridges: high only where the noise crosses its middle
local r = 1 - math.abs(n2(x / f, z / f, o) - 0.5) * 2
return smooth(math.clamp((r - 0.55) / 0.4, 0, 1))
end,
Spots = function(x, z, f, o) -- distance to the nearest point of a jittered grid (cellular noise)
local cx, cz, best = math.floor(x / f), math.floor(z / f), math.huge
for dx = -1, 1 do
for dz = -1, 1 do
local gx, gz = cx + dx, cz + dz
local px = (gx + 0.5 + math.noise(gx * 0.37, gz * 0.37, o) * 1.2) * f
local pz = (gz + 0.5 + math.noise(gx * 0.37, gz * 0.37, o + 5) * 1.2) * f
best = math.min(best, (Vector2.new(x - px, z - pz)).Magnitude)
end
end
return smooth(math.clamp(1 - best / (f * 0.45), 0, 1))
end,
Bands = function(x, z, f, o, a) -- rows across the wind direction, bent a little by noise
local w = math.rad(a.windDir or 0)
local along = x * math.cos(w) - z * math.sin(w)
local wave = math.sin((along / f + math.noise(x / (f * 2), z / (f * 2), o) * 0.8) * math.pi * 2)
return smooth(math.clamp(0.5 + wave * 0.9, 0, 1))
end,
}
function E.patternAt(a, x, z)
local fn = PATTERN[a.pattern or "Groves"] or PATTERN.Groves
return fn(x, z, math.max(a.patchSize or 60, 8), (a.seed % 991) * 0.37, a)
end
local function patchAt(a, x, z)
local k = a.patches or 0
if k <= 0 then
return 1
end
return 1 - k + k * E.patternAt(a, x, z)
end
E.patchAt = patchAt

E.ZONE_MOODS = { "Autumn", "Dry", "Lush", "Frost" }
E.ZONE_HINT = {
Autumn = "Warmer, yellow and orange toward the open ground.",
Dry = "Faded and paler toward the open ground, like late summer.",
Lush = "Deeper and richer toward the open ground.",
Frost = "Cold and pale toward the open ground.",
}
local ZONE = {
Autumn = { -0.09, 0.08, 0.05 },
Dry = { -0.04, -0.28, 0.14 },
Lush = { 0.02, 0.18, -0.14 },
Frost = { 0.02, -0.4, 0.3 },
}
function E.zoneShift(a, x, z)
local k = a.zones or 0
if k <= 0 then
return nil
end
local mood = ZONE[a.zoneMood or "Autumn"] or ZONE.Autumn
local w = k * (1 - E.patternAt(a, x, z))
return mood[1] * w, mood[2] * w, mood[3] * w
end

function E.cellCentre(an, i)
return an.x0 + ((i - 1) % an.nx + 0.5) * an.G, an.z0 + ((i - 1) // an.nx + 0.5) * an.G
end

local function suitability(l, an, i, a)
local sc = score(l, an, i)
if sc <= 0 then
return 0
end
if a.edge and a.edge > 0 then -- soft falloff toward the painted border
sc *= math.clamp((an.dist.Edge[i] - an.G * 0.5) / a.edge, 0, 1)
if sc <= 0 then
return 0
end
end
local pref = l.s.slopePref or 0
if pref ~= 0 then -- how steep the ground is, from flat (0) to the steepest it may stand on (1)
local t = math.clamp(math.deg(math.acos(math.clamp(an.ny[i], -1, 1))) / math.max(l.s.maxSlope, 1), 0, 1)
sc *= pref > 0 and (1 - pref + pref * t) or (1 + pref * t)
end
local x, z = E.cellCentre(an, i)
sc *= patchAt(a, x, z)
if sc > 0 and l.paint then
sc *= E.paintValue(l, math.floor(x / an.cell), math.floor(z / an.cell))
end
return sc
end
function E.heat(l, an, a)
l._size = a.size or 1
prep(l)
return function(i)
return an.inM[i] and suitability(l, an, i, a) or 0
end
end

function E.plan(layers, an, density, a)
local list = ordered(layers)
for _, l in list do
l._size = a.size or 1
end
local perType = {}
for _, l in list do
if not isLine(l) then
perType[l.type] = (perType[l.type] or 0) + 1
end
end
local plans = {}
for _, l in list do
prep(l)
if isLine(l) or not an then
table.insert(plans, { layer = l, line = true })
continue
end -- no painted area: everything follows the spline
local cand, scores, sum = {}, {}, 0
for i = 1, an.nx * an.nz do
if an.inM[i] then
local sc = suitability(l, an, i, a)
if sc > 0 then
table.insert(cand, i)
table.insert(scores, sc)
sum += sc
end
end
end
if (l._wsum or 0) <= 0 then
sum = 0
end
local r = math.max(l._r * l.s.spacing * (l.s.groups and math.max(l.s.tight, 0.9) * 0.55 or 1), MIN_COUNT_R)
local n = sum * an.G * an.G * COVERAGE[l.type] * l.s.density * density / perType[l.type] / (math.pi * r * r)
n = math.min(n, 5000)
if l.s.maxCount > 0 then
n = math.min(n, l.s.maxCount)
end
table.insert(plans, { layer = l, cand = cand, scores = scores, n = n })
end
return plans
end

function E.estimate(a, an, density)
local copies, parts = 0, 0
for _, p in E.plan(a.layers, an, density, a) do
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

I.score = score
I.isLine = isLine
I.before = before
I.scaleRange = scaleRange
end
end)()
-- #module Placement
MODULES["Placement"] = (function()
--[[
Smart Scatter — Engine/Placement: putting one copy down (spacing, footing, orientation, variation).
Adds to E (the engine API); shares internals with the other engine modules through I.
]]

return function(E, I)
local CollectionService = game:GetService("CollectionService")
local CORE = I.CORE
local hasKeyword = I.hasKeyword
local isLine = I.isLine
local partsOf = I.partsOf
local scaleRange = I.scaleRange
local score = I.score
local triangle = I.triangle

local CELL = 8
local BIG = 32 -- reach above this goes in the list
local Hash = {}
Hash.__index = Hash
local function ckey(cx, cz)
return cx * 73856093 + cz
end
local function reach(it)
return it.r * math.max(it.sp or 1, it.cs or 1, 1)
end
function Hash.new()
return setmetatable({ cells = {}, big = {}, maxReach = 0 }, Hash)
end
function Hash:add(it)
local rch = reach(it)
if rch > BIG then
table.insert(self.big, it)
return
end
local k = ckey(math.floor(it.x / CELL), math.floor(it.z / CELL))
local c = self.cells[k]
if not c then
c = {}
self.cells[k] = c
end
table.insert(c, it)
if rch > self.maxReach then
self.maxReach = rch
end
end
local LONG = 1.3 -- one side this much longer than the other counts as long
local function footprint(item, m, sc)
local hx, hz = m.size.X * sc / 2, m.size.Z * sc / 2
if math.max(hx, hz) >= math.min(hx, hz) * LONG then
item.hx, item.hz = hx, hz
end
end
local function extent(it, ux, uz)
if not it.hx then
return it.r
end
if not it.yaw then
return math.min(it.hx, it.hz)
end
local c, s = math.cos(it.yaw), math.sin(it.yaw)
return it.hx * math.abs(ux * c - uz * s) + it.hz * math.abs(ux * s + uz * c)
end
local function minDist(o, it, ro, ri)
if o.type == it.type then
if it.g and o.g == it.g then -- same pile: allowed to touch; pieces of one fence are already laid end to end
return it.fit and 0 or (ro + ri) * 0.9
end
return ro * o.sp + ri * it.sp
elseif o.type == "Building" or it.type == "Building" then -- keep canopies off roofs
return o.type == "Building" and (ro + ri * 0.6 * it.cs) or (ri + ro * 0.6 * o.cs)
elseif o.line and it.line then -- two objects lined up along a path: side by side, never inside each other
return (ro + ri) * 0.85
end
return ro * CORE[o.type] * o.cs + ri * CORE[it.type] * it.cs
end
local function tooClose(o, it)
local dx, dz = it.x - o.x, it.z - o.z
local d = math.sqrt(dx * dx + dz * dz)
local ko, ki = minDist(o, it, 1, 0), minDist(o, it, 0, 1) -- the rules are linear in each reach
if d > 1e-6 and d >= (ko * extent(o, dx / d, dz / d) + ki * extent(it, dx / d, dz / d)) then
return false
end
for _, t in { o, it } do
if t.hx and t.yaw then
local c, s = math.cos(t.yaw), math.sin(t.yaw)
for _, a in { { c, -s }, { s, c } } do
if math.abs(dx * a[1] + dz * a[2]) >= ko * extent(o, a[1], a[2]) + ki * extent(it, a[1], a[2]) then
return false
end
end
end
end
return true
end
function Hash:conflicts(it)
for _, o in self.big do
if tooClose(o, it) then
return true
end
end
local range = reach(it) + self.maxReach
for cx = math.floor((it.x - range) / CELL), math.floor((it.x + range) / CELL) do
for cz = math.floor((it.z - range) / CELL), math.floor((it.z + range) / CELL) do
local c = self.cells[ckey(cx, cz)]
if c then
for _, o in c do
if tooClose(o, it) then
return true
end
end
end
end
end
return false
end

function Hash:nearest(x, z, range, t)
local best
for _, o in self.big do
if o.type == t or o.lk == t then
local d = math.sqrt((o.x - x) ^ 2 + (o.z - z) ^ 2) - o.r * 0.5
if d <= range and (not best or d < best) then
best = d
end
end
end
for cx = math.floor((x - range) / CELL), math.floor((x + range) / CELL) do
for cz = math.floor((z - range) / CELL), math.floor((z + range) / CELL) do
local c = self.cells[ckey(cx, cz)]
if c then
for _, o in c do
if o.type == t or o.lk == t then
local d = math.sqrt((o.x - x) ^ 2 + (o.z - z) ^ 2) - o.r * 0.5
if not best or d < best then
best = d
end
end
end
end
end
end
return best and math.max(best, 0)
end

local function rotateUp(up)
local d = Vector3.yAxis:Dot(up)
if d > 0.9999 then
return CFrame.identity
end
if d < -0.9999 then
return CFrame.Angles(math.pi, 0, 0)
end -- straight down: any axis will do
return CFrame.fromAxisAngle(Vector3.yAxis:Cross(up).Unit, math.acos(math.clamp(d, -1, 1)))
end
E.rotateUp = rotateUp

E.FRONTS = { "Auto", "-Z", "+Z", "-X", "+X" }
local FRONT_YAW = { ["-Z"] = 0, ["+Z"] = math.pi, ["-X"] = -math.pi / 2, ["+X"] = math.pi / 2 }
local function frontOf(s)
local f = s and s.front
return FRONT_YAW[f] and f or nil
end
local function alongXOf(s, m) -- true when the model's X axis runs along the line
local f = frontOf(s)
if f then
return f == "+X" or f == "-X"
end
return m.size.X >= m.size.Z
end
local function lengthOf(s, m)
return alongXOf(s, m) and m.size.X or m.size.Z
end

local function overhangYaw(v)
if v._over ~= nil then
return v._over or nil
end
local m = v.m
local H = m.size.Y
local ref = v.inst:GetPivot().Position
local base, top, wb, wt = Vector3.zero, Vector3.zero, 0, 0
for _, p in m.parts do
local cf, sz = p.CFrame, p.Size
local vol = math.max(sz.X * sz.Y * sz.Z, 1e-3)
local lowY = math.huge
for sx = -1, 1, 2 do
for sy = -1, 1, 2 do
for sz2 = -1, 1, 2 do
lowY = math.min(lowY, (cf * Vector3.new(sz.X / 2 * sx, sz.Y / 2 * sy, sz.Z / 2 * sz2)).Y - ref.Y)
end
end
end
local rel = cf.Position - ref
if lowY - m.bottom < H * 0.1 then
base += rel * vol
wb += vol
end -- stands on the ground
if rel.Y - m.bottom > H * 0.65 then
top += rel * vol
wt += vol
end -- up top
end
v._over = false
if wb > 0 and wt > 0 and H > math.max(m.size.X, m.size.Z) then -- taller than wide: a lamp, a sign post
local d = top / wt - base / wb
d = Vector3.new(d.X, 0, d.Z)
if d.Magnitude > math.max(0.5, math.max(m.size.X, m.size.Z) * 0.2) then
v._over = math.atan2(d.X, -d.Z)
local b = base / wb
v._foot = Vector2.new(b.X, b.Z) -- what it stands on: that goes on the line, not the middle of its arm
end
end
return v._over or nil
end

local function groupId(l, n)
return (l._h % 100000) * 100000 + n
end

local function pickVariant(l, rng)
local r = rng:NextNumber() * l._wsum
for _, v in l.variants do
if v.w > 0 then
r -= v.w
if r <= 0 then
return v
end
end
end
return l.variants[#l.variants]
end

local function capInfo(v, s)
local alongX = alongXOf(s, v.m)
if v._cap ~= nil and v._capX == alongX then
return v._cap or nil
end
v._capX = alongX
local m = v.m
local A = alongX and Vector3.xAxis or Vector3.zAxis
local L = alongX and m.size.X or m.size.Z
local origin = v.inst:GetPivot().Position
local c = alongX and m.cx or m.cz
local only, sum, cnt, neg, pos = {}, 0, 0, false, false
for i, p in partsOf(v.inst) do
local cf, sz = p.CFrame, p.Size
local ext = math.abs(cf.RightVector:Dot(A)) * sz.X + math.abs(cf.UpVector:Dot(A)) * sz.Y + math.abs(cf.LookVector:Dot(A)) * sz.Z
local off = (cf.Position - origin):Dot(A) - c
if ext < L * 0.4 and math.abs(off) > L * 0.25 then
only[i] = true
sum += off
cnt += 1
if off < 0 then
neg = true
else
pos = true
end
end
end
v._cap = (cnt > 0 and neg ~= pos) and { only = only, off = sum / cnt, alongX = alongX } or false
return v._cap or nil
end

local function squeeze(clone, m, sc, f, alongX)
local A = alongX and Vector3.xAxis or Vector3.zAxis
local pivot = clone:GetPivot()
local origin = pivot.Position
local c = (alongX and m.cx or m.cz) * sc
local L = (alongX and m.size.X or m.size.Z) * sc
for _, p in partsOf(clone) do
local cf = p.CFrame
local along = (cf.Position - origin):Dot(A)
local dx, dy, dz = math.abs(cf.RightVector:Dot(A)), math.abs(cf.UpVector:Dot(A)), math.abs(cf.LookVector:Dot(A))
local sz = p.Size
if dx * sz.X + dy * sz.Y + dz * sz.Z > L * 0.4 then
local k = Vector3.new(1 + (f - 1) * dx * dx, 1 + (f - 1) * dy * dy, 1 + (f - 1) * dz * dz)
p.Size = sz * k
local mesh = p:FindFirstChildWhichIsA("SpecialMesh")
if mesh and mesh.MeshType == Enum.MeshType.FileMesh then
mesh.Scale *= k
end -- file meshes ignore part size
end
p.CFrame = cf + A * ((c - along) * (1 - f))
end
local pp = clone:IsA("Model") and clone.PrimaryPart
if pp then
pp.PivotOffset = pp.CFrame:ToObjectSpace(pivot)
end
end

local tag, recolor, dropDetails -- (below)

local function shifted(c, dh, ds, dv)
local h, s, v = c:ToHSV()
return Color3.fromHSV((h + dh) % 1, math.clamp(s + ds, 0, 1), math.clamp(v * (1 + dv), 0, 1))
end
recolor = function(parts, s, rng, zone)
local function roll()
if s.vary then
return rng:NextNumber(-s.hueVar, s.hueVar), rng:NextNumber(-s.satVar, s.satVar), rng:NextNumber(-s.valVar, s.valVar)
elseif s.tint > 0 then -- (brightness drawn first, as always: existing layouts keep their colours)
local dv = rng:NextNumber(-s.tint, s.tint)
return rng:NextNumber(-s.tint, s.tint) * 0.15, 0, dv
end
return nil
end
local dh, ds, dv = roll()
if not dh and not zone then
return
end
local zh, zs, zv = 0, 0, 0
if zone then
zh, zs, zv = zone[1], zone[2], zone[3]
end
local each = s.vary and s.perPart
for _, p in parts do
if each then -- (the copy's own roll above stays drawn, as always: existing layouts keep their colours)
dh, ds, dv = roll()
end
local h, sa, v = (dh or 0) + zh, (ds or 0) + zs, (dv or 0) + zv
p.Color = shifted(p.Color, h, sa, v)
for _, d in p:GetChildren() do
if d:IsA("SurfaceAppearance") then
pcall(function()
d.Color = shifted(d.Color, h, sa, v)
end) -- (older Studio builds have no SurfaceAppearance.Color)
elseif d:IsA("Decal") then -- (Texture is a Decal too)
d.Color3 = shifted(d.Color3, h, sa, v)
end
end
end
end
local DETAIL_WORDS = { "detail", "optional", "extra", "deco", "decoration", "apple", "fruit", "berry", "mushroom", "moss" }
dropDetails = function(clone, chance, rng)
local main = clone:IsA("Model") and clone.PrimaryPart or clone
for _, p in partsOf(clone) do
if p ~= main and p ~= clone and (p:GetAttribute("SS_Optional") or hasKeyword(p.Name, DETAIL_WORDS)) and rng:NextNumber() < chance then
p:Destroy()
end
end
end

local function ghostOf(v, sc, cf, sink)
local m = v.m
local p = Instance.new("Part")
p.Name = v.inst.Name
p.Size = m.size * sc
p.CFrame = cf * CFrame.new(0, m.size.Y * sc / 2 - sink, 0)
p.Transparency, p.CastShadow, p.CanCollide, p.CanTouch, p.CanQuery = 0.55, false, false, false, false
p.Material, p.Color = Enum.Material.SmoothPlastic, Color3.fromRGB(143, 186, 151)
return p
end

local function emit(ctx, l, v, sc, cf, rng, x, z, item, sink, gid, stacked, stretch, only, uprightPosts)
if E.isCleared(ctx.clear, x, z) then
return nil
end
local s, m = l.s, v.m
local out = ctx.output
if out.ghost then
local box = ghostOf(v, sc, cf, sink)
ctx.parts += 1
return tag(ctx, l, box, x, z, item, gid, stacked)
end
local clone = (v.src or v.inst):Clone() -- src: a procedural model, frozen
if only then -- keep just these parts (by index in partsOf order): an end post taken from the model itself
for i, p in partsOf(clone) do
if not only[i] and p ~= clone then
p:Destroy()
end
end
end
if clone:IsA("Model") then
if math.abs(sc - 1) > 1e-3 then
clone:ScaleTo(clone:GetScale() * sc)
end
else
clone.Size *= sc
end
if stretch and math.abs(stretch - 1) > 0.005 then
squeeze(clone, m, sc, math.min(stretch, 1.15), alongXOf(s, m))
end
local cx, cz = m.cx, m.cz
if isLine(l) then -- a lamp stands on the line by its pole, whichever way it faces
overhangYaw(v)
if v._foot then
cx, cz = v._foot.X, v._foot.Y
end
end
clone:PivotTo(cf * CFrame.new(-cx * sc, -m.bottom * sc - sink, -cz * sc) * m.rel)
if uprightPosts and math.abs(cf.RightVector.Y) + math.abs(cf.LookVector.Y) > 0.02 then
local A = alongXOf(s, m) and cf.RightVector or cf.LookVector
local L = lengthOf(s, m) * sc
for _, p in partsOf(clone) do
local pcf, sz = p.CFrame, p.Size
local ext = math.abs(pcf.RightVector:Dot(A)) * sz.X + math.abs(pcf.UpVector:Dot(A)) * sz.Y + math.abs(pcf.LookVector:Dot(A)) * sz.Z
local axes = { { pcf.RightVector, sz.X }, { pcf.UpVector, sz.Y }, { pcf.LookVector, sz.Z } }
table.sort(axes, function(a, b)
return a[2] > b[2]
end)
local ax, len = axes[1][1], axes[1][2]
if ext < L * 0.4 and len >= math.max(axes[2][2], axes[3][2]) * 1.5 then -- tall and thin across the run: a post
if ax.Y < 0 then
ax = -ax
end
local rot = ax:Cross(Vector3.yAxis)
local ang = math.acos(math.clamp(ax.Y, -1, 1))
if rot.Magnitude > 1e-4 and ang > 1e-3 then
local bottom = pcf.Position - ax * (len / 2) -- keep its foot where it was
local upright = CFrame.fromAxisAngle(rot.Unit, ang) * pcf.Rotation
p.CFrame = CFrame.new(bottom + Vector3.yAxis * (len / 2)) * upright
end
end
end
end
if s.vary and s.dropDetails > 0 then
dropDetails(clone, s.dropDetails, rng)
end
local zh, zs, zv = E.zoneShift(ctx.area, x, z)
recolor(partsOf(clone), s, rng, zh and { zh, zs, zv } or nil)
local small = l.type == "Flower" or l.type == "Bush"
local parts = partsOf(clone)
ctx.parts += #parts
for _, p in parts do
p.Anchored = true
if out.walk and small then
p.CanCollide = false
p.CanTouch = false
end
if out.shadows and (l.type == "Flower" or p.Size.Magnitude < 2.5) then
p.CastShadow = false
end
if out.query and l.type == "Flower" then
p.CanQuery = false
end
end
return tag(ctx, l, clone, x, z, item, gid, stacked)
end

function tag(ctx, l, clone, x, z, item, gid, stacked)
local s = l.s
CollectionService:AddTag(clone, E.TAG)
clone:SetAttribute("SS_Type", l.type)
clone:SetAttribute("SS_L", l._h) -- which object it is (kept copies still count for "grows near")
clone:SetAttribute("SS_X", x)
clone:SetAttribute("SS_Z", z)
clone:SetAttribute("SS_R", item.r)
if item.pin then -- put down by hand (Engine/Pins): removing it takes the pin away
clone:SetAttribute("SS_Pin", true)
end
if item.hx and item.yaw then -- its outline, for the next runs that keep it
clone:SetAttribute("SS_Fp", Vector3.new(item.hx, item.yaw, item.hz))
end
clone:SetAttribute("SS_Sp", s.spacing)
clone:SetAttribute("SS_Cs", s.clearance)
if gid then
clone:SetAttribute("SS_G", gid)
end
if stacked then
clone:SetAttribute("SS_Stacked", true)
end
clone.Parent = ctx.parentFor(l, x, z)
if not stacked then
ctx.hash:add(item)
end
return clone
end

local function mitre(clone, A, J, nB, atEnd, pieceLen)
local wide = {}
for _, p in partsOf(clone) do
local pcf, sz = p.CFrame, p.Size
local axes = { { pcf.RightVector, sz.X, "X" }, { pcf.UpVector, sz.Y, "Y" }, { pcf.LookVector, sz.Z, "Z" } }
local best, bd = nil, 0
for _, ax in axes do
local d = math.abs(ax[1]:Dot(A))
if d > bd then
best, bd = ax, d
end
end
if best and bd > 0.9 and best[2] > pieceLen * 0.4 then -- a long part running with the piece
local axis = best[1]:Dot(A) > 0 and best[1] or -best[1]
local half = best[2] / 2
local e = pcf.Position + axis * (atEnd and half or -half) -- the end face's centre
local denom = axis:Dot(nB)
if math.abs(denom) > 0.2 then
local shift = (J - e):Dot(nB) / denom -- how far that end must move along the part to reach the plane
local lat, ld = nil, math.huge
for _, ax in axes do
if ax ~= best then
local up = math.abs(ax[1].Y)
if up < ld then
lat, ld = ax, up
end
end
end
local isWide = lat and lat[2] > 0.5
if isWide then -- the inner side corner: whichever needs the end pulled back the most
for sgn = -1, 1, 2 do
local sc = (J - (e + lat[1] * (lat[2] / 2 * sgn))):Dot(nB) / denom
if (atEnd and sc < shift) or (not atEnd and sc > shift) then
shift = sc
end
end
end
if isWide then
shift = math.clamp(shift, -best[2] * 0.45, best[2] * 0.45)
end
if math.abs(shift) < best[2] * 0.5 then
local grow = atEnd and shift or -shift
local size = sz
if best[3] == "X" then
size = Vector3.new(sz.X + grow, sz.Y, sz.Z)
elseif best[3] == "Y" then
size = Vector3.new(sz.X, sz.Y + grow, sz.Z)
else
size = Vector3.new(sz.X, sz.Y, sz.Z + grow)
end
p.Size = size
p.CFrame = pcf + axis * (shift / 2)
if isWide then
local upAx
for _, ax in axes do
if ax ~= best and ax ~= lat then
upAx = ax
end
end
table.insert(wide, { p = p, along = best[3], across = lat[3], up = upAx[3], sign = axis:Dot(best[1]) > 0 and 1 or -1 })
end
end
end
end
end
return wide
end

local AXIS = { X = "RightVector", Y = "UpVector", Z = "LookVector" }
local function fillJoint(ea, eb, nB)
local function frame(e, atEnd)
local p = e.p
local cf, sz = p.CFrame, p.Size
local along = cf[AXIS[e.along]] * e.sign
local across, up = cf[AXIS[e.across]], cf[AXIS[e.up]]
if up.Y < 0 then
up = -up
end
local L, W, H = sz[e.along], sz[e.across], sz[e.up]
local c = p.Position + along * (L / 2) * (atEnd and 1 or -1) + up * (H / 2) -- top of the end face
return c + across * (W / 2), c - across * (W / 2), along, H
end
local a1, a2, dirA, H = frame(ea, true)
local b1, b2 = frame(eb, false)
if (a1 - b2).Magnitude + (a2 - b1).Magnitude < (a1 - b1).Magnitude + (a2 - b2).Magnitude then
b1, b2 = b2, b1
end
local ai, bi, ao, bo = a1, b1, a2, b2 -- inner corners (touching) and outer ones (apart)
if (a1 - b1).Magnitude > (a2 - b2).Magnitude then
ai, bi, ao, bo = a2, b2, a1, b1
end
if (ao - bo).Magnitude < 0.02 then
return 0
end
local I = (ai + bi) / 2
local denom = dirA:Dot(nB)
if math.abs(denom) < 0.2 then
return 0
end
local s = (I - ao):Dot(nB) / denom -- along A's outer edge to the bisector: where the two outer edges meet
if s < 0 or s > (ao - ai).Magnitude * 2 then
return 0
end
local O = ao + dirA * s
local tmp = Instance.new("Folder")
local style = { mat = ea.p.Material, color = ea.p.Color }
local n = triangle(tmp, style, I, ao, O, H) + triangle(tmp, style, I, O, bo, H)
for _, w in tmp:GetChildren() do
w.MaterialVariant, w.Transparency, w.Reflectance = ea.p.MaterialVariant, ea.p.Transparency, ea.p.Reflectance
w.CastShadow, w.CanCollide, w.CanQuery, w.CanTouch = ea.p.CastShadow, ea.p.CanCollide, ea.p.CanQuery, ea.p.CanTouch
w.Name = "JointFill"
w.Parent = ea.p.Parent
end
tmp:Destroy()
return n
end

local function flatAround(an, ix, iz, y, r)
local k = math.clamp(math.ceil(r / an.G), 1, 3)
for jz = math.max(iz - k, 0), math.min(iz + k, an.nz - 1) do
for jx = math.max(ix - k, 0), math.min(ix + k, an.nx - 1) do
local j = jz * an.nx + jx + 1
if an.cls[j] ~= "None" and math.abs(an.y[j] - y) > 0.25 then
return false
end
end
end
return true
end

local KEEP_CLASS = { Buildings = "Building", Roads = "Road", Water = "Water" }
local function clearAt(an, i, x, z, field, k)
if k <= 0 or an.dist[field][i] >= k + an.G * 1.5 then
return true
end -- well away: the field is exact enough
local want, G = KEEP_CLASS[field], an.G
local r = math.ceil(k / G) + 1
local ix, iz = (i - 1) % an.nx, (i - 1) // an.nx
for jz = math.max(iz - r, 0), math.min(iz + r, an.nz - 1) do
for jx = math.max(ix - r, 0), math.min(ix + r, an.nx - 1) do
if an.cls[jz * an.nx + jx + 1] == want then
local cx0, cz0 = an.x0 + jx * G, an.z0 + jz * G
local dx = math.max(cx0 - x, 0, x - (cx0 + G))
local dz = math.max(cz0 - z, 0, z - (cz0 + G))
if dx * dx + dz * dz < k * k then
return false
end
end
end
end
return true
end

local function placeAt(ctx, l, i, x, z, rng, g)
g = g or {}
local v = g.v or pickVariant(l, rng)
local an, s, m = ctx.an, l.s, v.m
i = i or E.indexAt(an, x, z)
if not i or (not an.inM[i] and not g.line) then
return nil
end -- lines come from the area's own edge
if g.line and E.isCleared(ctx.clear, x, z) then
return nil
end -- (the area's own cells already leave zones out)
local ix, iz = (i - 1) % an.nx, (i - 1) // an.nx
if (g.member or g.pin) and not g.stackOn then
if score(l, an, i) <= 0 then
return nil
end
if l.paint and E.paintValue(l, math.floor(x / an.cell), math.floor(z / an.cell)) <= 0 then
return nil
end
end

local keep = 0.5
if g.member or g.line or g.pin then
else
if s.cluster > 0 then -- natural clumps
local f = (m.radius * 8 + 10) * math.max(s.clumpSize, 0.1)
keep = math.clamp(0.5 + math.noise(x / f, z / f, (ctx.seed % 997) + (l._h % 1000) * 0.173) * 2.2, 0, 1)
if rng:NextNumber() > 1 - s.cluster * (1 - keep) then
return nil
end
end
if s.hug == "Trees" then -- undergrowth: gather around trees already placed
local d = ctx.hash:nearest(x, z, s.hugRange + 16, "Tree")
local near = d and math.clamp(1 - d / math.max(s.hugRange, 1), 0, 1) or 0
if rng:NextNumber() > (1 - s.hugStrength) + s.hugStrength * near then
return nil
end
end
if l._nearH then -- grows close to another object's copies (placed before it)
local d = ctx.hash:nearest(x, z, s.nearRange + 16, l._nearH)
local near = d and math.clamp(1 - d / math.max(s.nearRange, 1), 0, 1) or 0
if rng:NextNumber() > (1 - s.nearStrength) + s.nearStrength * near then
return nil
end
end
end

local lo, hi = scaleRange(l)
local t = s.cluster > 0 and math.clamp(rng:NextNumber() * 0.7 + keep * 0.3, 0, 1) or rng:NextNumber()
local sc = g.sc or (lo + (hi - lo) * t) * v.size
if s.edgeYoung > 0 and not g.line and not g.sc then -- the young fringe: smaller toward the edge and clearings
local reach = 12 + m.radius * sc * 4
local open = math.clamp(an.dist.Edge[i] / reach, 0, 1) * math.clamp(E.patchAt(ctx.area, x, z) * 1.25, 0, 1)
sc *= 1 - s.edgeYoung * 0.6 * (1 - open)
end
local item = {
x = x,
z = z,
r = math.max(m.radius * sc, 0.25),
type = l.type,
sp = s.spacing,
cs = s.clearance,
g = g.gid,
fit = g.stretch ~= nil,
lk = l._h,
pin = g.pin,
}
if not g.line and not g.stackOn then
footprint(item, m, sc)
end

local base = g.stackOn
local hit, y
if base then
y = base.top
else
if not g.post and ctx.hash:conflicts(item) then
return nil
end -- posts sit on the joints of their own panels
if not g.line then
local cr = l._core or 0
if not clearAt(an, i, x, z, "Water", s.keepWater + cr) then
return nil
end
if not clearAt(an, i, x, z, "Buildings", s.keepBuilding + cr) then
return nil
end
if not s.surfaces.Road and not clearAt(an, i, x, z, "Roads", s.keepRoad + cr) then
return nil
end
end
hit = workspace:Raycast(Vector3.new(x, an.top, z), Vector3.new(0, -an.len, 0), an.rp)
if not hit or hit.Material == Enum.Material.Water then
return nil
end
if not s.surfaces[(E.surfaceOf(hit.Instance, hit.Material))] and not (an and i and an.on[i]) then
return nil
end
if math.deg(math.acos(math.clamp(hit.Normal.Y, -1, 1))) > s.maxSlope then
return nil
end
y = hit.Position.Y
end
local yaw
local function pickYaw()
if s.yawMode == "Fixed" then
return math.rad(s.yaw)
end
if s.yawMode == "Snap" then
return rng:NextInteger(0, 3) * math.pi / 2
end
return rng:NextNumber(0, math.pi * 2)
end

if l.type == "Building" and not base then
if g.yaw then
yaw = g.yaw
elseif s.faceRoad and an.dist.Roads[i] < 90 then -- turn the front (-Z / LookVector) toward the nearest road
local f = an.dist.Roads
local function at(a, b)
a = math.clamp(a, 0, an.nx - 1)
b = math.clamp(b, 0, an.nz - 1)
return f[b * an.nx + a + 1]
end
local gx, gz = at(ix + 2, iz) - at(ix - 2, iz), at(ix, iz + 2) - at(ix, iz - 2)
if gx * gx + gz * gz > 1e-6 then
yaw = math.atan2(gx, gz)
end
end
yaw = yaw or pickYaw()
local hx, hz = m.size.X * sc / 2, m.size.Z * sc / 2
local rot = CFrame.Angles(0, yaw, 0)
local nxs, nzs = math.clamp(math.ceil(hx * 2 / an.G), 2, 8), math.clamp(math.ceil(hz * 2 / an.G), 2, 8)
local mnY, mxY = y, y
for a = 0, nxs do
for b = 0, nzs do
local o = rot:VectorToWorldSpace(Vector3.new(-hx + 2 * hx * a / nxs, 0, -hz + 2 * hz * b / nzs))
local j = E.indexAt(an, x + o.X, z + o.Z)
if not j then
return nil
end
if not an.inM[j] then
return nil
end -- the whole house stays inside the painted area
local c = an.cls[j]
if not s.surfaces[c] and not an.on[j] then
return nil
end
if an.dist.Buildings[j] < s.keepBuilding then
return nil
end
if not s.surfaces.Road and an.dist.Roads[j] < s.keepRoad then
return nil
end
if an.dist.Water[j] < s.keepWater then
return nil
end
mnY = math.min(mnY, an.y[j])
mxY = math.max(mxY, an.y[j])
end
end
if mxY - mnY > math.max(1.5, math.max(hx, hz) * 0.08) then
return nil
end
y = mnY
else
yaw = g.yaw or pickYaw()
local rr = math.max(item.r * CORE[l.type] * 0.6, 0.4)
if s.align < 1 and not base and not flatAround(an, ix, iz, y, rr) then
for k = 0, 3 do
local a = k * math.pi / 2 + yaw
local h2 = workspace:Raycast(Vector3.new(x + math.cos(a) * rr, an.top, z + math.sin(a) * rr), Vector3.new(0, -an.len, 0), an.rp)
if h2 and h2.Position.Y < y then
y = math.max(h2.Position.Y, y - rr * 1.5)
end
end
end
end

if item.hx then -- now it's turned: its real outline must fit where only its narrow side was tried
item.yaw = yaw
if not base and not g.post and ctx.hash:conflicts(item) then
return nil
end
end

local up = (s.align > 0 and hit) and Vector3.yAxis:Lerp(hit.Normal, s.align).Unit or Vector3.yAxis
local cf = CFrame.new(x, y, z) * rotateUp(up) * CFrame.Angles(0, yaw, 0)
if s.tilt > 0 and not base and not (g.line and s.fit) then
cf *= CFrame.Angles(math.rad(rng:NextNumber(-s.tilt, s.tilt)), 0, math.rad(rng:NextNumber(-s.tilt, s.tilt)))
end
if s.lean > 0 and not base and not (g.line and s.fit) then -- all the same way, like a windswept stand of trees
local wd = math.rad(ctx.area.windDir or 0)
local axis = Vector3.yAxis:Cross(Vector3.new(math.sin(wd), 0, math.cos(wd))) -- turns "up" toward the wind
cf = CFrame.new(cf.Position) * CFrame.fromAxisAngle(axis, math.rad(s.lean) * rng:NextNumber(0.7, 1.3)) * cf.Rotation
end

if l.type ~= "Flower" and not base then -- don't clip into the user's own geometry
local h = math.max(m.size.Y * sc - 1, 1)
local real = l.type == "Building" or g.line
local w = real and m.size.X * sc or math.max(1, item.r * CORE[l.type] * 2)
local d = real and m.size.Z * sc or w
if g.stretch then -- as long as the piece really gets (squeeze stretches at most 15%)
local st = math.min(g.stretch, 1.15)
if alongXOf(s, m) then
w *= st
else
d *= st
end
end
for _, p in workspace:GetPartBoundsInBox(cf * CFrame.new(0, 1 + h / 2, 0), Vector3.new(w * 0.95, h, d * 0.95), ctx.op) do
if p ~= hit.Instance then
return nil
end
end
end

local sink = base and 0 or s.sink * m.size.Y * sc
if not emit(ctx, l, v, sc, cf, rng, x, z, item, sink, g.gid, base ~= nil, g.stretch) then
return nil -- not made after all (a keep-clear zone): it mustn't count as placed
end
return { x = x, z = z, r = item.r, sc = sc, v = v, top = y - sink + m.size.Y * sc, stacked = base ~= nil }
end

local function place(ctx, l, i, rng, gid)
local an = ctx.an
local ix, iz = (i - 1) % an.nx, (i - 1) // an.nx
local x = an.x0 + (ix + rng:NextNumber()) * an.G
local z = an.z0 + (iz + rng:NextNumber()) * an.G
return placeAt(ctx, l, i, x, z, rng, gid and { gid = gid } or nil)
end

local function growGroup(ctx, l, lead, gid, want, rng)
local s = l.s
local members, got, tries = { lead }, 0, 0
while got < want and tries < want * 10 + 6 do
tries += 1
local basePiece = members[rng:NextInteger(1, #members)]
local v = s.sameModel and lead.v or pickVariant(l, rng)
local sc = lead.sc / lead.v.size * v.size * rng:NextNumber(0.92, 1.08)
local info
local fits = basePiece.v.m.flatTop >= 0.45 and v.m.radius * math.min(sc, basePiece.sc) <= basePiece.r * 1.1
if s.stack > 0 and fits and not basePiece.stacked and rng:NextNumber() < s.stack then
local jitter = basePiece.r * 0.08
info = placeAt(
ctx,
l,
nil,
basePiece.x + rng:NextNumber(-jitter, jitter),
basePiece.z + rng:NextNumber(-jitter, jitter),
rng,
{ v = v, sc = math.min(sc, basePiece.sc), member = true, gid = gid, stackOn = basePiece }
)
else
local ang = rng:NextNumber(0, math.pi * 2)
local d = (basePiece.r + v.m.radius * sc) * math.max(s.tight, 0.9)
info = placeAt(
ctx,
l,
nil,
basePiece.x + math.cos(ang) * d,
basePiece.z + math.sin(ang) * d,
rng,
{ v = v, sc = sc, member = true, gid = gid }
)
end
if info then
table.insert(members, info)
got += 1
end
end
return got
end

I.Hash = Hash
I.FRONT_YAW = FRONT_YAW
I.frontOf = frontOf
I.alongXOf = alongXOf
I.lengthOf = lengthOf
I.overhangYaw = overhangYaw
I.groupId = groupId
I.pickVariant = pickVariant
I.capInfo = capInfo
I.emit = emit
I.mitre = mitre
I.fillJoint = fillJoint
I.placeAt = placeAt
I.place = place
I.growGroup = growGroup
end
end)()
-- #module Lines
MODULES["Lines"] = (function()
--[[
Smart Scatter — Engine/Lines: copies following an edge or a path (roads, water, houses, fences end to end).
Adds to E (the engine API); shares internals with the other engine modules through I.
]]

return function(E, I)
local FOLLOW_FIELD = I.FOLLOW_FIELD
local FRONT_YAW = I.FRONT_YAW
local Hash = I.Hash
local alongXOf = I.alongXOf
local capInfo = I.capInfo
local emit = I.emit
local fillJoint = I.fillJoint
local frontOf = I.frontOf
local groupId = I.groupId
local lengthOf = I.lengthOf
local mitre = I.mitre
local overhangYaw = I.overhangYaw
local pickVariant = I.pickVariant
local placeAt = I.placeAt
local project = I.project
local scaleRange = I.scaleRange

local function traceLines(an, f, target, anyMask)
local nx, nz, G, x0, z0 = an.nx, an.nz, an.G, an.x0, an.z0
local function v(ix, iz)
return f[iz * nx + ix + 1] - target
end
local function inside(ix, iz)
return an.inM[iz * nx + ix + 1]
end
local function px(ix)
return x0 + (ix + 0.5) * G
end
local function pz(iz)
return z0 + (iz + 0.5) * G
end
local pos, links = {}, {}
local function edgePoint(ix, iz, vertical)
local id = (iz * nx + ix) * 2 + (vertical and 1 or 0)
if not pos[id] then
local a = v(ix, iz)
local jx, jz = vertical and ix or ix + 1, vertical and iz + 1 or iz
local b = v(jx, jz)
local t = math.clamp(a / (a - b), 0, 1)
pos[id] = { px(ix) + (px(jx) - px(ix)) * t, pz(iz) + (pz(jz) - pz(iz)) * t }
end
return id
end
local function ok(val, jx, jz)
return inside(jx, jz) or (anyMask and val < 0)
end
local function link(a, b)
links[a] = links[a] or {}
table.insert(links[a], b)
links[b] = links[b] or {}
table.insert(links[b], a)
end
for iz = 0, nz - 2 do
for ix = 0, nx - 2 do
local a, b, c, d = v(ix, iz), v(ix + 1, iz), v(ix + 1, iz + 1), v(ix, iz + 1)
if ok(a, ix, iz) and ok(b, ix + 1, iz) and ok(c, ix + 1, iz + 1) and ok(d, ix, iz + 1) then
if math.max(a, b, c, d) < 1e8 then
local code = (a < 0 and 1 or 0) + (b < 0 and 2 or 0) + (c < 0 and 4 or 0) + (d < 0 and 8 or 0)
if code ~= 0 and code ~= 15 then
local S = function()
return edgePoint(ix, iz, false)
end -- bottom edge a-b
local E_ = function()
return edgePoint(ix + 1, iz, true)
end -- right edge b-c
local N = function()
return edgePoint(ix, iz + 1, false)
end -- top edge d-c
local W = function()
return edgePoint(ix, iz, true)
end -- left edge a-d
if code == 1 or code == 14 then
link(S(), W())
elseif code == 2 or code == 13 then
link(S(), E_())
elseif code == 3 or code == 12 then
link(W(), E_())
elseif code == 4 or code == 11 then
link(E_(), N())
elseif code == 6 or code == 9 then
link(S(), N())
elseif code == 7 or code == 8 then
link(W(), N())
elseif code == 5 or code == 10 then -- saddle: decide by the centre
local mid = (a + b + c + d) / 4
if (mid < 0) == (code == 5) then
link(S(), E_())
link(W(), N())
else
link(S(), W())
link(E_(), N())
end
end
end
end
end
end
end
local used, lines = {}, {}
local function other(id, from)
for _, n in links[id] do
if n ~= from and not used[id .. ":" .. n] then
return n
end
end
return nil
end
local function walk(start)
local pts, prev, cur = { pos[start] }, nil, start
while true do
local nxt = other(cur, prev)
if not nxt then
break
end
used[cur .. ":" .. nxt] = true
used[nxt .. ":" .. cur] = true
if nxt == start then
return pts, true
end
table.insert(pts, pos[nxt])
prev, cur = cur, nxt
end
return pts, false
end
local ids = {}
for id in links do
table.insert(ids, id)
end
table.sort(ids) -- deterministic
local seen = {}
local function mark(pts)
for _, p in pts do
seen[p] = true
end
end
for _, id in ids do
if #links[id] == 1 and not seen[pos[id]] then
local pts, closed = walk(id)
mark(pts)
table.insert(lines, { pts = pts, closed = closed })
end
end
for _, id in ids do
if not seen[pos[id]] then
local pts, closed = walk(id)
mark(pts)
table.insert(lines, { pts = pts, closed = closed })
end
end
local out = {}
for _, ln in lines do
local P = ln.pts
if ln.closed then
table.insert(P, P[1])
end
local len = 0
for k = 2, #P do
len += math.sqrt((P[k][1] - P[k - 1][1]) ^ 2 + (P[k][2] - P[k - 1][2]) ^ 2)
end
if len >= G * 1.5 then
local step = G * 0.5
local R, k, acc = { { P[1][1], P[1][2] } }, 2, 0
local want = step
local cx, cz = P[1][1], P[1][2]
while k <= #P do
local dx, dz = P[k][1] - cx, P[k][2] - cz
local seg = math.sqrt(dx * dx + dz * dz)
if acc + seg >= want and seg > 1e-6 then
local t = (want - acc) / seg
cx, cz = cx + dx * t, cz + dz * t
table.insert(R, { cx, cz })
acc, want = 0, step
else
acc += seg
cx, cz = P[k][1], P[k][2]
k += 1
end
end
if not ln.closed then
table.insert(R, { P[#P][1], P[#P][2] })
elseif #R > 2 then
table.remove(R)
end
local n = #R
for _ = 1, 8 do -- Laplacian smoothing, ends pinned on open lines
local S2 = table.create(n)
for i = 1, n do
local a, b
if ln.closed then
a, b = R[(i - 2) % n + 1], R[i % n + 1]
elseif i == 1 or i == n then
S2[i] = R[i]
continue
else
a, b = R[i - 1], R[i + 1]
end
S2[i] = { R[i][1] * 0.5 + (a[1] + b[1]) * 0.25, R[i][2] * 0.5 + (a[2] + b[2]) * 0.25 }
end
R = S2
end
if ln.closed then
table.insert(R, { R[1][1], R[1][2] })
end
table.insert(out, { pts = R, closed = ln.closed })
end
end
return out
end

local BLOCKS_LINE = { Road = true, Dirt = true, Water = true, Building = true }

local function gapper(skip, rng)
if skip <= 0 then
return function()
return true
end
end
skip = math.min(skip, 0.95)
local runMean, gapMean = 4, 4 * skip / (1 - skip)
if gapMean < 1 then
gapMean, runMean = 1, (1 - skip) / skip
end
local keeping, left = true, rng:NextInteger(1, math.max(math.floor(runMean * 1.4 + 0.5), 1))
return function()
while left <= 0 do
keeping = not keeping
left = keeping and math.max(math.floor(runMean * rng:NextNumber(0.6, 1.4) + 0.5), 1)
or math.max(math.floor(gapMean * rng:NextNumber(0.5, 1.5) + 0.5), 1)
end
left -= 1
return keeping
end
end
local function gapMask(n, skip, rng)
local mask, nextKeep = table.create(n), gapper(skip, rng)
for k = 1, n do
mask[k] = nextKeep()
end
if skip > 0 and n > 2 then
for k = 1, n do -- a single piece between two openings looks like a mistake: drop it
if mask[k] and not mask[k - 1] and not mask[k + 1] then
mask[k] = false
end
end
end
return mask
end

local function fitPieces(total, at3, pieceL, joints, halfW)
if total < 0.05 then
return {}
end
halfW = halfW or 0
local function at(d)
local p = at3(d)
return Vector3.new(p.X, 0, p.Z)
end
local tol = math.clamp(pieceL * 0.05, 0.15, 1.2) -- how far a piece may stray from the curve
if halfW > 0.5 then
tol = math.min(tol, 0.35)
end -- a wide piece's edge is in plain view: keep it tight
local minL = math.min(pieceL * 0.3, total) -- never squeeze below this
local n = math.max(math.ceil(total / math.max(pieceL / 8, 0.1)), 2)
local h = total / n
local G = table.create(n + 1)
for i = 0, n do
G[i + 1] = at3(i * h)
end
local function turn(u, v)
if u.Magnitude < 1e-6 or v.Magnitude < 1e-6 then
return 0
end
return math.acos(math.clamp(u.Unit:Dot(v.Unit), -1, 1))
end
local CORNER = math.rad(28)
local breaks = { 0 }
local i = 2
while i <= n do
if turn(G[i] - G[i - 1], G[i + 1] - G[i]) > CORNER then
local lo, hi = math.max((i - 2) * h, 0), math.min(i * h, total)
local best, bestD, e = -1, (i - 1) * h, h / 16
for k = 0, 32 do -- refine: the point of sharpest turn in this window
local d = lo + (hi - lo) * k / 32
local t = turn(at3(d) - at3(d - e), at3(d + e) - at3(d))
if t > best then
best, bestD = t, d
end
end
if bestD - breaks[#breaks] > 0.05 and total - bestD > 0.05 then
table.insert(breaks, bestD)
end
i += 2
else
i += 1
end
end
for _, jd in joints or {} do
if jd > 0.05 and jd < total - 0.05 then
table.insert(breaks, jd)
end
end
table.sort(breaks)
for k = #breaks, 2, -1 do
if breaks[k] - breaks[k - 1] < math.max(minL * 0.5, 0.3) then
table.remove(breaks, k)
end
end
if #breaks > 1 and total - breaks[#breaks] < math.max(minL * 0.5, 0.3) then
table.remove(breaks)
end
table.insert(breaks, total)
local function bow(d0, d1)
local a, b = at(d0), at(d1)
local a3, b3 = at3(d0), at3(d1)
local ab = b - a
local L2 = ab:Dot(ab)
local worst = 0
for k = 1, 7 do
local dk = d0 + (d1 - d0) * k / 8
local p = at(dk)
local t = L2 > 1e-9 and math.clamp((p - a):Dot(ab) / L2, 0, 1) or k / 8
local vy = math.abs(at3(dk).Y - (a3.Y + (b3.Y - a3.Y) * t))
worst = math.max(worst, (p - (a + ab * t)).Magnitude, vy - 0.5)
end
local L = (at(d1) - at(d0)).Magnitude
if halfW > 0.5 and L > 1e-3 then
worst += halfW * 8 * worst * worst / (L * L)
end
return worst
end
local lmax = table.create(n + 1, pieceL)
local r = 1
for k = 1, n + 1 do
local d = (k - 1) * h
while r < #breaks - 1 and d > breaks[r + 1] do
r += 1
end
local d0, d1 = math.max(d - pieceL / 2, breaks[r]), math.min(d + pieceL / 2, breaks[r + 1])
if d1 - d0 > minL * 0.5 then
local s = bow(d0, d1)
if s > tol then
lmax[k] = math.clamp((d1 - d0) * math.sqrt(tol / s), minL, pieceL)
end
end
end
local w = math.max(math.ceil(pieceL * 0.5 / h), 1) -- ease: lengths start shrinking half a piece before a bend
local rho = table.create(n + 1)
for k = 1, n + 1 do
local m = pieceL
for j = math.max(k - w, 1), math.min(k + w, n + 1) do
m = math.min(m, lmax[j])
end
rho[k] = 1 / m -- pieces per stud
end
local function rhoAt(d)
local x = math.clamp(d / h, 0, n)
local k = math.min(math.floor(x), n - 1)
return rho[k + 1] + (rho[k + 2] - rho[k + 1]) * (x - k)
end
local out = {}
local function add(d0, d1, depth) -- split a piece that still cuts across the curve
if depth < 4 and d1 - d0 > minL * 1.2 and bow(d0, d1) > tol * 1.5 then
local mid = (d0 + d1) / 2
add(d0, mid, depth + 1)
add(mid, d1, depth + 1)
else
table.insert(out, { d0, d1 })
end
end
for rr = 1, #breaks - 1 do
local b0, b1 = breaks[rr], breaks[rr + 1]
local steps = math.max(math.ceil((b1 - b0) / (h * 0.5)), 1)
local ds = (b1 - b0) / steps
local F = table.create(steps + 1)
F[1] = 0
for k = 1, steps do
local d = b0 + (k - 1) * ds
F[k + 1] = F[k] + (rhoAt(d) + rhoAt(d + ds)) * 0.5 * ds
end
local count = math.max(math.ceil(F[steps + 1] - 0.15), 1)
local prev, k = b0, 1
for j = 1, count do
local target = F[steps + 1] * j / count
local d = b1
if j < count then
while k < steps and F[k + 1] < target do
k += 1
end
local f0, f1 = F[k], F[k + 1]
d = b0 + (k - 1 + (f1 > f0 and (target - f0) / (f1 - f0) or 0)) * ds
end
if d - prev > 0.05 then
add(prev, d, 0)
prev = d
end
end
if b1 - prev > 0.05 then
add(prev, b1, 0)
end
end
return out
end
E.fitPieces = fitPieces

local NUDGE = { 0, 0.25, -0.25, 0.45, -0.45 }

local function placeSpline(ctx, l, rng)
if not ctx.splines or #ctx.splines == 0 then
return 0
end
local s, m = l.s, l.m
local facing = s.fit and "Along" or s.facing -- end-to-end pieces always run along the line
local lo, hi = scaleRange(l)
local avg = (lo + hi) / 2
local long = lengthOf(s, m)
local alongX = alongXOf(s, m)
local front = frontOf(s) -- nil: the smart guess
local pieceL = long * avg * l.variants[1].size * 0.98
local wideSeg = (alongX and m.size.Z or m.size.X) > 0.6
local interval = s.fit and pieceL or math.max(s.interval, 1)
local gid = groupId(l, 99998)
local got, cap = 0, s.maxCount > 0 and s.maxCount or 5000
local off = math.max(s.offset, 0)
local side = s.side
local sp = ctx.area and ctx.area.spline
if E.roadWidth(sp) > 0 and not s.fit then
off += E.roadWidth(sp) / 2 + (l._r or 0)
if side ~= "Left" and side ~= "Right" then
side = "Both"
end
end
local sides = (side == "Both" and off > 0) and { -off, off } or (side == "Left" and { -off }) or (side == "Right" and { off }) or { 0 }
local roll = math.rad(s.roll or 0)

local function tangent(Q, k)
local a, b = Q[math.max(k - 1, 1)], Q[math.min(k + 1, #Q)]
local t = b - a
return t.Magnitude > 1e-5 and t.Unit or Vector3.zAxis
end
local curRp, curveSide = nil, 0
local PROBES = { 3, 6, 10, 15, 22, 30 }
local function edgeSide(pos, right)
if not curRp then
return 0
end
local score = 0
for _, d in PROBES do
for sgn = -1, 1, 2 do
local q = pos + right * (d * sgn)
local h = workspace:Raycast(q + Vector3.new(0, 40, 0), Vector3.new(0, -80, 0), curRp)
if h then
local c = h.Position.Y - pos.Y > 3 and "Building" or E.surfaceOf(h.Instance, h.Material)
if c == "Road" then
score += sgn
elseif c == "Building" then
score -= sgn
end
end
end
end
return score > 0 and 1 or (score < 0 and -1 or 0)
end
local function frame(pos, t, n, side, pitch, v)
local up, fwd
if s.orient == "Upright" and pitch then -- an end-to-end piece: follows the slope of its chord, no roll
fwd = t
up = Vector3.yAxis - t * t.Y
elseif s.orient == "Upright" then
up, fwd = Vector3.yAxis, Vector3.new(t.X, 0, t.Z)
elseif s.orient == "Surface" then
up = n
fwd = t - n * t:Dot(n)
else -- Follow: pitch with the curve, up stays as close to the surface normal as the tangent allows
fwd = t
up = n - t * n:Dot(t)
end
if up.Magnitude < 1e-4 then
up = Vector3.yAxis
end
up = up.Unit
if fwd.Magnitude < 1e-4 then
fwd = up:Cross(Vector3.xAxis)
if fwd.Magnitude < 1e-4 then
fwd = up:Cross(Vector3.zAxis)
end
end
fwd = (fwd - up * fwd:Dot(up)).Unit
local right = fwd:Cross(up)
local cf
local look = fwd
if (facing == "Face it" or facing == "Away") and side == 0 then
local sg = edgeSide(pos, right)
if sg == 0 then
sg = curveSide
end
if sg ~= 0 then
look = ((sg > 0) == (facing == "Face it")) and right or -right
elseif facing == "Away" then
look = -fwd
end
elseif facing == "Face it" then
look = side > 0 and -right or right
elseif facing == "Away" then
look = side > 0 and right or -right
elseif facing == "Random" then
look = CFrame.fromAxisAngle(up, rng:NextNumber(0, math.pi * 2)):VectorToWorldSpace(fwd)
end
if front then
cf = CFrame.fromMatrix(pos, look:Cross(up), up) * CFrame.Angles(0, FRONT_YAW[front], 0)
if roll ~= 0 then
cf *= CFrame.fromAxisAngle(alongX and Vector3.xAxis or Vector3.zAxis, roll)
end
else
if facing == "Along" then
cf = alongX and CFrame.fromMatrix(pos, fwd, up) or CFrame.fromMatrix(pos, right, up)
else
cf = CFrame.fromMatrix(pos, look:Cross(up), up)
local oy = v and facing ~= "Random" and overhangYaw(v)
if oy then
cf *= CFrame.Angles(0, oy, 0)
end
end
if roll ~= 0 then
cf *= (facing == "Along" and alongX) and CFrame.Angles(roll, 0, 0) or CFrame.Angles(0, 0, roll)
end
end
if s.tilt > 0 and not s.fit then -- end-to-end pieces stay true so their joints meet
cf *= CFrame.Angles(math.rad(rng:NextNumber(-s.tilt, s.tilt)), 0, math.rad(rng:NextNumber(-s.tilt, s.tilt)))
end
return cf
end
local mines, minD = {}, interval * 0.5
local function put(pos, t, n, side, sc, v, stretch)
if got >= cap or E.isCleared(ctx.clear, pos.X, pos.Z) then
return
end
local mine = mines[side]
if not mine then
mine = Hash.new()
mines[side] = mine
end
local probe = { x = pos.X, z = pos.Z, r = minD * 0.5, type = "L", sp = 1, cs = 1 }
if not s.fit and mine:conflicts(probe) then
return
end
local r = math.max(v.m.radius * sc, 0.25)
local item = { x = pos.X, z = pos.Z, r = r, type = l.type, sp = s.spacing, cs = s.clearance, g = gid, line = true }
if not s.fit and ctx.hash:conflicts(item) then
return nil
end
local clone = emit(
ctx,
l,
v,
sc,
frame(pos, t, n, side, s.fit, v),
rng,
pos.X,
pos.Z,
item,
s.sink * v.m.size.Y * sc,
gid,
false,
stretch,
nil,
s.fit and s.orient == "Upright"
)
if clone then -- (none is made in a keep-clear zone)
got += 1
end
if not s.fit then
mine:add(probe)
end
return clone
end

for _, smp in ctx.splines do
curRp, curveSide = smp.rp, 0
if (facing == "Face it" or facing == "Away") and table.find(sides, 0) and #smp.P >= 2 then
local votes = 0
for k = 1, #smp.P, math.max(#smp.P // 16, 1) do
local t = tangent(smp.P, k)
local r = Vector3.new(t.X, 0, t.Z):Cross(Vector3.yAxis)
if r.Magnitude > 1e-4 then
votes += edgeSide(smp.P[k], r.Unit)
end
end
curveSide = votes > 0 and 1 or (votes < 0 and -1 or 0)
end
for si, side in sides do
local Q, W = smp.P, smp.U
if side ~= 0 then
Q, W = table.create(#smp.P), table.create(#smp.P)
for k = 1, #smp.P do
local t, n = tangent(smp.P, k), smp.U[k]
local up = s.orient == "Upright" and Vector3.yAxis or n
local right = t:Cross(up)
if right.Magnitude < 1e-4 then
right = t:Cross(Vector3.yAxis)
end
local q = smp.P[k] + right.Unit * side * (smp.W and smp.W[k] or 1) -- edges follow the strip's width
if smp.snap then
Q[k], W[k] = project(q, n, smp.rp)
else
Q[k], W[k] = q, n
end
end
end
local acc = { 0 }
for k = 2, #Q do
acc[k] = acc[k - 1] + (Q[k] - Q[k - 1]).Magnitude
end
local total = acc[#Q]
local function at(d)
d = math.clamp(d, 0, total)
local lo2, hi2 = 1, #Q
while hi2 - lo2 > 1 do
local mid = (lo2 + hi2) // 2
if acc[mid] <= d then
lo2 = mid
else
hi2 = mid
end
end
local t = (d - acc[lo2]) / math.max(acc[hi2] - acc[lo2], 1e-6)
local zs = smp.Z and (smp.Z[lo2] + (smp.Z[hi2] - smp.Z[lo2]) * t) or 1
return Q[lo2]:Lerp(Q[hi2], t), W[lo2]:Lerp(W[hi2], t), lo2, zs
end
if s.fit then
local joints = {}
for _, k in smp.joints or {} do
table.insert(joints, acc[k])
end
local halfW = (alongX and m.size.Z or m.size.X) * avg * l.variants[1].size / 2
local pieces = fitPieces(total, function(d)
return (at(d))
end, pieceL, joints, halfW)
local keep = gapMask(#pieces, s.skip, rng)
if l.post and #pieces > 0 then -- posts at every joint and both ends of the fence that's there
local loop = (Q[1] - Q[#Q]).Magnitude < 0.05
local marks = {}
for k, pc in pieces do
if keep[k] or keep[k - 1] or (loop and k == 1 and keep[#pieces]) then
table.insert(marks, { pc[1], k })
end
end
if not loop and keep[#pieces] then
table.insert(marks, { total, #pieces + 1 })
end
local pv = l.post
for _, mk in marks do
if got >= cap then
break
end
local pos, n, _, zs = at(mk[1])
local prev, nxt = pieces[mk[2] - 1] or (loop and pieces[#pieces]), pieces[mk[2]]
local t = Vector3.zero
if prev then
t += at(prev[2]) - at(prev[1])
end
if nxt then
t += at(nxt[2]) - at(nxt[1])
end
t = t.Magnitude > 1e-4 and t.Unit or Vector3.zAxis
local sc = avg * pv.size * zs
local item = {
x = pos.X,
z = pos.Z,
r = math.max(pv.m.radius * sc, 0.25),
type = l.type,
sp = s.spacing,
cs = s.clearance,
g = gid,
}
if
emit(
ctx,
l,
pv,
sc,
frame(pos, t, n.Magnitude > 1e-4 and n.Unit or Vector3.yAxis, side),
rng,
pos.X,
pos.Z,
item,
s.sink * pv.m.size.Y * sc,
gid,
false
)
then
got += 1
end
end
end
local placed = {}
for k, pc in pieces do
if got >= cap or not ctx.alive() then
break
end
local a, na = at(pc[1])
local dir = at(pc[2]) - a
local len = dir.Magnitude
local cliff = s.orient == "Upright" and len > 0.05 and math.abs(dir.Y / len) > 0.866
if len > 0.05 and keep[k] and not cliff then
local v = pickVariant(l, rng)
local sc = avg * v.size
local _, n = at((pc[1] + pc[2]) / 2)
n = n.Magnitude > 1e-4 and n.Unit or na
local f = len * (wideSeg and 1.0005 or 1.02) / (lengthOf(s, v.m) * sc)
local clone = put(a + dir / 2, dir.Unit, n, side, sc, v, f)
if clone then
placed[k] =
{ v = v, sc = sc, f = math.min(f, 1.15), a = a, b = a + dir, t = dir.Unit, n = n, clone = clone, len = len }
end
end
end
local loopRun = (Q[1] - Q[#Q]).Magnitude < 0.05
for k, pk in placed do
local nxt = placed[k + 1] or (loopRun and k == #pieces and placed[1]) or nil
if nxt then
local nB = pk.t + nxt.t
if nB.Magnitude > 1e-3 and pk.t:Dot(nxt.t) < 0.9998 then
nB = nB.Unit
local wa = mitre(pk.clone, pk.t, pk.b, nB, true, pk.len)
local wb = mitre(nxt.clone, nxt.t, nxt.a, nB, false, nxt.len)
for i = 1, math.min(#wa, #wb) do
ctx.parts += fillJoint(wa[i], wb[i], nB)
end
end
end
end
if not l.post and facing == "Along" and roll == 0 then
local k = 1
while k <= #pieces do
if placed[k] then
local j = k
while placed[j + 1] do
j += 1
end
local loop = (Q[1] - Q[#Q]).Magnitude < 0.05 and k == 1 and j == #pieces
local ci = not loop and capInfo(placed[k].v, s)
if ci and got < cap then
local cf0 = frame(placed[k].a:Lerp(placed[k].b, 0.5), placed[k].t, placed[k].n, side, true)
local offDir = cf0:VectorToWorldSpace(ci.alongX and Vector3.xAxis or Vector3.zAxis):Dot(placed[k].t)
local pk = placed[(offDir * ci.off < 0) and j or k] -- posts at piece starts: cap the stretch's end
local e = offDir * ci.off * pk.sc -- post offset from the centre along the fence (unsqueezed)
local halfL = lengthOf(s, pk.v.m) * pk.sc * pk.f / 2
local inset = halfL - math.abs(e) * pk.f
local post = e < 0 and pk.b - pk.t * inset or pk.a + pk.t * inset
local pos = post - pk.t * e
local item = { x = post.X, z = post.Z, r = 0.5, type = l.type, sp = s.spacing, cs = s.clearance, g = gid }
emit(
ctx,
l,
pk.v,
pk.sc,
frame(pos, pk.t, pk.n, side, true),
rng,
post.X,
post.Z,
item,
s.sink * pk.v.m.size.Y * pk.sc,
gid,
false,
nil,
ci.only,
s.orient == "Upright"
)
got += 1
end
k = j + 1
else
k += 1
end
end
end
else
local d = math.min(interval * 0.5, total * 0.5)
if s.stagger and si == 2 then
d += interval * 0.5
end
local nextKeep = gapper(s.skip, rng)
while d <= total and got < cap and ctx.alive() do
local dd = math.clamp(d + (rng:NextNumber() - 0.5) * s.jitter * interval, 0, total)
if nextKeep() then
local v = pickVariant(l, rng)
local scale = (lo + hi) / 2 + (hi - lo) * (rng:NextNumber() - 0.5)
for _, shift in NUDGE do
local pos, n, k, zs = at(math.clamp(dd + shift * interval, 0, total))
if put(pos, tangent(Q, k), n.Magnitude > 1e-4 and n.Unit or Vector3.yAxis, side, scale * v.size * zs, v) then
break
end
if got >= cap then
break
end
end
end
d += interval
end
end
end
end
return got
end

local function placeLine(ctx, l, rng)
if l.s.follow == "Spline" or not ctx.an then
return placeSpline(ctx, l, rng)
end
local an, s = ctx.an, l.s
local facing = s.fit and "Along" or s.facing -- end-to-end pieces always run along the line
local fieldName = FOLLOW_FIELD[s.follow] or "Roads"
local f = an.dist[fieldName]
if not f then
return 0
end
local lo, hi = scaleRange(l)
local m = l.m
local long = lengthOf(s, m)
local short = alongXOf(s, m) and m.size.Z or m.size.X
local front = frontOf(s)
local avg = (lo + hi) / 2
local depth = facing == "Along" and short
or (facing == "Random" and math.max(m.size.X, m.size.Z))
or ((front == "-X" or front == "+X") and m.size.X or m.size.Z)
local target = s.offset + depth * avg / 2 + an.G * 0.5
local pieceL = long * avg * l.variants[1].size * 0.98 -- a hair of overlap so joints never show daylight
local interval = s.fit and pieceL or math.max(s.interval, 1)
local gid = groupId(l, 99999)
local mine = Hash.new()
local minD = s.fit and pieceL * 0.2 or math.min(interval * 0.5, target * 1.2)
local got, cap = 0, s.maxCount > 0 and s.maxCount or 5000

local function blocked(x, z)
local j = E.indexAt(an, x, z)
if not j then
return true
end
local c = an.cls[j]
return BLOCKS_LINE[c] == true
end
local function normalToward(x, z, tx, tz)
local ja, jb = E.indexAt(an, x - tz * an.G, z + tx * an.G), E.indexAt(an, x + tz * an.G, z - tx * an.G)
local fa, fb = ja and f[ja] or 1e9, jb and f[jb] or 1e9
if fb < fa then
return tz, -tx
end
return -tz, tx
end
local function yawFor(x, z, tx, tz, v)
if front and facing ~= "Random" then
local dx, dz = tx, tz
if facing ~= "Along" then
local nx_, nz_ = normalToward(x, z, tx, tz)
if facing == "Away" then
dx, dz = -nx_, -nz_
else
dx, dz = nx_, nz_
end
end
return math.atan2(-dx, -dz) + FRONT_YAW[front]
end
if facing == "Along" then
if m.size.X >= m.size.Z then
return math.atan2(-tz, tx)
end
return math.atan2(tx, tz)
elseif facing == "Random" then
return rng:NextNumber(0, math.pi * 2)
end
local nx_, nz_ = normalToward(x, z, tx, tz)
local oy = v and overhangYaw(v) or 0 -- a lamp's arm is its front
if facing == "Away" then
return math.atan2(nx_, nz_) + oy
end
return math.atan2(-nx_, -nz_) + oy -- LookVector (-Z) toward the feature
end
local function put(x, z, tx, tz, sc, v, stretch)
if got >= cap then
return
end
local i = E.indexAt(an, x, z)
if not i then
return
end
if l.paint then
local p = E.paintValue(l, math.floor(x / an.cell), math.floor(z / an.cell))
if p <= 0 or (p < 1 and rng:NextNumber() >= p) then
return
end
end
local probe = { x = x, z = z, r = minD * 0.5, type = "L", sp = 1, cs = 1 }
if mine:conflicts(probe) then
return
end
local info = placeAt(ctx, l, i, x, z, rng, { v = v, sc = sc, yaw = yawFor(x, z, tx, tz, v), line = true, gid = gid, stretch = stretch })
if info then
got += 1
mine:add(probe)
end
end

for ci, ln in traceLines(an, f, target, fieldName == "Edge") do
local P = ln.pts
local acc = { 0 }
for k = 2, #P do
acc[k] = acc[k - 1] + math.sqrt((P[k][1] - P[k - 1][1]) ^ 2 + (P[k][2] - P[k - 1][2]) ^ 2)
end
local total = acc[#P]
local function at(d) -- binary search: callers probe back and forth along the line
d = math.clamp(d, 0, total)
local lo, hi = 1, #P
while hi - lo > 1 do
local mid = (lo + hi) // 2
if acc[mid] <= d then
lo = mid
else
hi = mid
end
end
local k = hi
local a, b = P[k - 1], P[k]
local t = (d - acc[k - 1]) / math.max(acc[k] - acc[k - 1], 1e-6)
return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t
end

if s.fit then
local pieces = fitPieces(total, function(d)
local x, z = at(d)
return Vector3.new(x, 0, z)
end, pieceL, nil, short * avg * l.variants[1].size / 2)
local keep = gapMask(#pieces, s.skip, rng)
for k, pc in pieces do
if got >= cap or not ctx.alive() then
break
end
local ax, az = at(pc[1])
local bx, bz = at(pc[2])
local tx, tz = bx - ax, bz - az
local tl = math.sqrt(tx * tx + tz * tz)
if tl > 0.05 then
tx, tz = tx / tl, tz / tl
local cx, cz = (ax + bx) / 2, (az + bz) / 2
if keep[k] and not blocked(ax, az) and not blocked(cx, cz) and not blocked(bx, bz) then
local v = pickVariant(l, rng)
local sc = avg * v.size
put(cx, cz, tx, tz, sc, v, tl * (short > 0.6 and 1.0005 or 1.02) / (lengthOf(s, v.m) * sc))
end
end
end
if l.post and #pieces > 0 then -- posts at every joint and both ends of the fence that's there
local marks = {}
for k, pc in pieces do
if keep[k] or keep[k - 1] or (ln.closed and k == 1 and keep[#pieces]) then
table.insert(marks, pc[1])
end
end
if not ln.closed and keep[#pieces] then
table.insert(marks, total)
end
for _, d in marks do
if got >= cap then
break
end
local x, z = at(d)
local x1, z1 = at(d - 1)
local x2, z2 = at(d + 1)
local tx, tz = x2 - x1, z2 - z1
local tl = math.sqrt(tx * tx + tz * tz)
local i = E.indexAt(an, x, z)
if i and tl > 1e-3 and not blocked(x, z) then
local info = placeAt(
ctx,
l,
i,
x,
z,
rng,
{ v = l.post, sc = avg * l.post.size, yaw = yawFor(x, z, tx / tl, tz / tl), line = true, gid = gid, post = true }
)
if info then
got += 1
end
end
end
end
else
local d = math.min(interval * 0.5, total * 0.5)
if s.stagger and ci % 2 == 0 then
d += interval * 0.5
end -- every other traced edge starts half a gap later
local nextKeep = gapper(s.skip, rng)
while d <= total and got < cap and ctx.alive() do
local dd = math.clamp(d + (rng:NextNumber() - 0.5) * s.jitter * interval, 0, total)
local x, z = at(dd)
local h = math.max(an.G, 2)
local x1, z1 = at(dd - h)
local x2, z2 = at(dd + h)
local tx, tz = x2 - x1, z2 - z1
local tl = math.sqrt(tx * tx + tz * tz)
if tl > 1e-3 and nextKeep() and not blocked(x, z) then
local v = pickVariant(l, rng)
put(x, z, tx / tl, tz / tl, (lo + (hi - lo) * rng:NextNumber()) * v.size, v)
end
d += interval
end
end
end
return got
end

I.placeLine = placeLine
end
end)()
-- #module Pins
MODULES["Pins"] = (function()
--[[
Smart Scatter — Engine/Pins: copies put down by hand with the object brush. Each is a pin on its object
(l.pins = { { x, z, seed }, … }, saved with the area like the object's painting): generating places the pins
first, on their exact spots, under the object's rules (surfaces, slope, spacing), then fills in the rest as usual.
A pin's seed picks its model, size and turn, so it looks the same every time.
Adds to E (the engine API); shares internals with the other engine modules through I.
]]

return function(E, I)
local placeAt = I.placeAt
local scaleRange = I.scaleRange

local function pinSpacing(l)
local lo, hi = scaleRange(l)
return math.max(l.m.radius * (lo + hi) / 2 * l.s.spacing * 2, 1)
end
E.pinSpacing = pinSpacing

local function roomFor(l, x, z, gap)
for _, p in l.pins or {} do
local dx, dz = p[1] - x, p[2] - z
if dx * dx + dz * dz < gap * gap then
return false
end
end
return true
end

function E.brushPins(a, l, x, z, R, rng)
l._size = a.size or 1 -- ("Size of everything", as generating sets it)
local gap = pinSpacing(l)
local want = math.clamp(math.floor(R * R / (gap * gap) * 0.9), 1, 40)
local added = {}
for _ = 1, want * 4 do
if #added >= want then
break
end
local ang, d = rng:NextNumber() * math.pi * 2, math.sqrt(rng:NextNumber()) * R
local px, pz = x + math.cos(ang) * d, z + math.sin(ang) * d
if E.hasCell(a, math.floor(px / a.cell), math.floor(pz / a.cell)) and roomFor(l, px, pz, gap) then
local pin = { math.floor(px * 100 + 0.5) / 100, math.floor(pz * 100 + 0.5) / 100, rng:NextInteger(1, 2 ^ 30) }
l.pins = l.pins or {}
table.insert(l.pins, pin)
table.insert(added, pin)
end
end
return added
end

function E.erasePins(l, x, z, R)
local n, keep = 0, {}
for _, p in l.pins or {} do
local dx, dz = p[1] - x, p[2] - z
if dx * dx + dz * dz <= R * R then
n += 1
else
table.insert(keep, p)
end
end
l.pins = #keep > 0 and keep or nil
return n
end

function E.unpin(l, x, z)
for k, p in l.pins or {} do
if math.abs(p[1] - x) < 0.05 and math.abs(p[2] - z) < 0.05 then
table.remove(l.pins, k)
if #l.pins == 0 then
l.pins = nil
end
return true
end
end
return false
end

function E.readPins(list)
local out = {}
for _, p in type(list) == "table" and list or {} do
if type(p) == "table" and tonumber(p[1]) and tonumber(p[2]) and tonumber(p[3]) then
table.insert(out, { tonumber(p[1]), tonumber(p[2]), tonumber(p[3]) })
end
end
return #out > 0 and out or nil
end

function I.placePins(ctx, l, wanted)
local n = 0
for _, p in l.pins or {} do
if not wanted or wanted(p[1], p[2]) then
if placeAt(ctx, l, nil, p[1], p[2], Random.new(p[3]), { pin = true }) then
n += 1
end
end
end
return n
end
end
end)()
-- #module Generate
MODULES["Generate"] = (function()
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
local placePins = I.placePins

local function itemOf(inst)
local fp = inst:GetAttribute("SS_Fp") -- a long copy's outline: half sizes and turn (see Placement's footprint)
return {
hx = fp and fp.X,
yaw = fp and fp.Y,
hz = fp and fp.Z,
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

local keep = {}
for _, p in plans do
local l = p.layer
if l.s.locked or (opts.from and l ~= opts.from and before(l, opts.from)) then
keep[E.layerKey(l)] = l
end
end
local folders, counts, total = {}, {}, 0
local stale, staged = {}, {}
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
local pinned = p.line and 0 or placePins(ctx, l, partial[l] and inPatch or nil)
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
counts[l] = (partial[l] and counts[l] or 0) + got + pinned
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
end)()
-- #module Kinds
MODULES["Kinds"] = (function()
--[[
Smart Scatter — Engine/Kinds: reading a finished map. Every repeated model is found and grouped into kinds by its
shape, not its name, so renamed, turned and scaled copies still match; and the snapshot that keeps the originals
of what later tools change (swapping models, seasons), so they can be put back.
Adds to E (the engine API); shares internals with the other engine modules through I.
]]

return function(E, I)
local STEP = 40 -- a side is known to 1/40 of the copy's longest side: tells shapes apart, forgives float error
local SNAPSHOT = "SmartScatter Snapshot"

function E.shapeKey(parts)
local unit = 0
for _, p in parts do
unit = math.max(unit, p.size.X, p.size.Y, p.size.Z)
end
if #parts == 0 or unit <= 0 then
return nil, 0
end
local keys = table.create(#parts)
for i, p in parts do
local d = { p.size.X, p.size.Y, p.size.Z }
table.sort(d, function(a, b)
return a > b
end)
local q = function(v)
return math.floor(v / unit * STEP + 0.5)
end
keys[i] = string.format("%s/%d,%d,%d", p.kind, q(d[1]), q(d[2]), q(d[3]))
end
table.sort(keys)
return #parts .. "|" .. table.concat(keys, "|"), unit
end

local function partKind(p)
if p:IsA("MeshPart") then
return "MeshPart:" .. p.MeshId
elseif p:IsA("Part") then
local sm = p:FindFirstChildOfClass("SpecialMesh")
if sm then
return "Mesh:" .. sm.MeshType.Name .. ":" .. sm.MeshId
end
return "Part:" .. p.Shape.Name
end
return p.ClassName
end
local function describe(inst)
local parts = {}
local list = inst:IsA("BasePart") and { inst } or inst:GetDescendants()
for _, p in list do
if p:IsA("BasePart") then
table.insert(parts, { kind = partKind(p), size = p.Size })
end
end
return parts
end
function E.keyOf(inst)
return E.shapeKey(describe(inst))
end

local function shapedPart(p)
return p:IsA("MeshPart") or p:IsA("UnionOperation") or (p:IsA("Part") and p:FindFirstChildOfClass("SpecialMesh") ~= nil)
end
local function skipped(inst)
if inst:IsA("Terrain") or inst:IsA("Camera") then
return true
end
if inst.Name == E.OUT or inst.Name == E.ROADS then -- what the plugin placed: its areas own it
return inst.Parent == workspace
end
return inst:IsA("Model") and inst:FindFirstChildOfClass("Humanoid") ~= nil -- players and NPCs
end

function E.scanKinds(opts)
opts = opts or {}
local roots = opts.roots or { workspace }
local keyOf, sizeOf, count, seen = {}, {}, {}, 0
local function visit(inst)
if skipped(inst) then
return
end
if inst:IsA("Model") or (inst:IsA("BasePart") and shapedPart(inst)) then
local key, size = E.keyOf(inst)
if key then
keyOf[inst], sizeOf[inst] = key, size
count[key] = (count[key] or 0) + 1
end
end
seen += 1
if opts.pause and seen % 3000 == 0 then
opts.pause()
end
for _, c in inst:GetChildren() do
visit(c)
end
end
for _, r in roots do
visit(r)
end
local byKey, list = {}, {}
local function pick(inst)
if skipped(inst) then
return
end
local key = keyOf[inst]
if key and count[key] >= 2 then
local k = byKey[key]
if not k then
k = { key = key, copies = {}, names = {}, parts = #describe(inst) }
byKey[key] = k
table.insert(list, k)
end
table.insert(k.copies, { inst = inst, size = sizeOf[inst] })
k.names[inst.Name] = (k.names[inst.Name] or 0) + 1
if not opts.nested then
return
end
end
for _, c in inst:GetChildren() do
pick(c)
end
end
for _, r in roots do
pick(r)
end
local kinds = {}
for _, k in list do
if #k.copies >= 2 then -- (a shape repeated only inside other copies has one left here)
local name, most = "?", 0
for n, c in k.names do
if c > most or (c == most and n < name) then
name, most = n, c
end
end
local ref = k.copies[1].size
for _, c in k.copies do
c.scale = ref > 0 and c.size / ref or 1
c.size = nil
end
table.insert(kinds, { key = k.key, name = name, count = #k.copies, copies = k.copies, parts = k.parts })
end
end
table.sort(kinds, function(a, b)
if a.count ~= b.count then
return a.count > b.count
end
return a.name < b.name
end)
return kinds
end

local function folder(make)
local ss = game:GetService("ServerStorage")
local f = ss:FindFirstChild(SNAPSHOT)
if not f and make then
f = Instance.new("Folder")
f.Name = SNAPSHOT
f:SetAttribute("SS_Saved", os.time())
f.Parent = ss
end
return f
end
local function entries()
local f = folder(false)
return f and f:GetChildren() or {}
end
local index = {}
local function entryOf(inst)
local e = index[inst]
local ok = e and e.Parent == folder(false) and e:FindFirstChild("Now") and e.Now.Value == inst
if not ok then
index = {}
for _, x in entries() do
local now = x:FindFirstChild("Now")
if now and now.Value then
index[now.Value] = x
end
end
e = index[inst]
end
return e
end

function E.snapshot(list)
local have = {}
for _, e in entries() do
local now = e:FindFirstChild("Now")
if now and now.Value then
have[now.Value] = true
end
end
local f, added = nil, 0
for _, inst in list do
if not have[inst] and inst.Parent then
local old = inst.Archivable
inst.Archivable = true -- (a clone of a non-archivable instance is nil)
local copy = inst:Clone()
inst.Archivable = old
if copy then
f = f or folder(true)
local e = Instance.new("Folder")
e.Name = inst.Name
local where = Instance.new("ObjectValue")
where.Name = "Where"
where.Value = inst.Parent
where.Parent = e
local now = Instance.new("ObjectValue")
now.Name = "Now"
now.Value = inst
now.Parent = e
copy.Name = "Original"
copy.Parent = e
e.Parent = f
index[inst] = e
have[inst] = true
added += 1
end
end
end
return added
end

function E.snapshotChanged(inst, now)
local e = entryOf(inst)
if not e then
return false
end
e.Now.Value = now or inst
index[inst] = nil
index[now or inst] = e
e:SetAttribute("SS_Changed", true)
return true
end

function E.snapshotInfo()
local f = folder(false)
if not f then
return nil
end
local changed = 0
local list = f:GetChildren()
for _, e in list do
if e:GetAttribute("SS_Changed") then
changed += 1
end
end
return { saved = #list, changed = changed, time = f:GetAttribute("SS_Saved") }
end

function E.restoreSnapshot(only)
local back, map = 0, {}
for _, e in entries() do
local orig, now, where = e:FindFirstChild("Original"), e:FindFirstChild("Now"), e:FindFirstChild("Where")
if orig and now and e:GetAttribute("SS_Changed") and (not only or only[now.Value]) then
local was = now.Value
if was and was.Parent then
was:Destroy()
end
local copy = orig:Clone()
copy.Name = e.Name
copy.Parent = (where and where.Value and where.Value:IsDescendantOf(game)) and where.Value or workspace
now.Value = copy
index[copy] = e
e:SetAttribute("SS_Changed", nil)
back += 1
if was then
map[was] = copy
end
end
end
return back, map
end

function E.clearSnapshot()
local f = folder(false)
if f then
f:Destroy()
end
index = {}
end

local CollectionService = game:GetService("CollectionService")
local AXES = { Vector3.xAxis, -Vector3.xAxis, Vector3.yAxis, -Vector3.yAxis, Vector3.zAxis, -Vector3.zAxis }
local function snapAxis(v)
local best, bd = Vector3.yAxis, -math.huge
for _, a in AXES do
local d = a:Dot(v)
if d > bd then
best, bd = a, d
end
end
return best
end
local function turnBetween(a, b)
local d = a:Dot(b)
if d > 0.5 then
return CFrame.identity
elseif d < -0.5 then
local side = math.abs(a.X) > 0.5 and Vector3.zAxis or Vector3.xAxis
return CFrame.fromAxisAngle(side, math.pi)
end
return CFrame.fromAxisAngle(a:Cross(b).Unit, math.pi / 2)
end
local function boxOf(inst)
if inst:IsA("BasePart") then
return inst.CFrame, inst.Size
end
return inst:GetBoundingBox()
end
local function baseOf(inst, up)
local cf, size = boxOf(inst)
local reach = math.abs(cf.RightVector:Dot(up)) * size.X + math.abs(cf.UpVector:Dot(up)) * size.Y + math.abs(cf.LookVector:Dot(up)) * size.Z
return cf.Position - up * (reach / 2)
end
local function extent(inst)
local _, size = boxOf(inst)
return math.max(size.X, size.Y, size.Z)
end
local function scaleBy(inst, f)
if math.abs(f - 1) < 1e-4 then
return
end
if inst:IsA("Model") then
inst:ScaleTo(inst:GetScale() * f)
else
inst.Size *= f
end
end
local function upOfCopies(copies)
local sum = Vector3.zero
for _, c in copies do
if c.inst.Parent then
sum += c.inst:GetPivot():VectorToObjectSpace(Vector3.yAxis)
end
end
return snapAxis(sum)
end
local function median(list)
if #list == 0 then
return 1
end
table.sort(list)
return list[math.ceil(#list / 2)]
end

function E.kindRef(copies)
local scales, sizes = {}, {}
for _, c in copies do
if c.inst.Parent then
table.insert(scales, c.scale or 1)
table.insert(sizes, extent(c.inst) / (c.scale or 1))
end
end
return { scale = median(scales), size = median(sizes), up = upOfCopies(copies) }
end

function E.swapCopies(copies, with, opts)
opts = opts or {}
local ref = opts.ref or E.kindRef(copies)
local total = 0
for _, w in with do
total += math.max(w.w or 1, 0)
end
if total <= 0 then
return {}
end
local list = {}
for _, c in copies do
if c.inst.Parent then
table.insert(list, c.inst)
end
end
E.snapshot(list)
local rng = Random.new(tonumber(opts.seed) or 1)
local out = {}
for n, c in copies do
local old = c.inst
if old.Parent then
local r, pick = rng:NextNumber() * total, with[#with]
for _, w in with do
r -= math.max(w.w or 1, 0)
if r <= 0 then
pick = w
break
end
end
local new = E.copyOf(pick.inst)
if new then
local tUp = snapAxis(pick.inst:GetPivot():VectorToObjectSpace(Vector3.yAxis))
local f = opts.match and (c.scale or 1) * ref.size / math.max(extent(pick.inst), 1e-3) or (c.scale or 1) / ref.scale
f *= opts.size or 1
scaleBy(new, f)
local pivot = old:GetPivot()
local turn = CFrame.fromAxisAngle(tUp, math.rad(opts.turn or 0))
new:PivotTo(CFrame.new(pivot.Position) * pivot.Rotation * turnBetween(tUp, ref.up) * turn)
local up = pivot:VectorToWorldSpace(ref.up)
new:PivotTo(new:GetPivot() + (baseOf(old, up) - baseOf(new, up)))
if opts.scripts then
for _, d in old:GetDescendants() do
if d:IsA("LuaSourceContainer") then
d:Clone().Parent = new
end
end
end
if opts.tags then
for _, t in CollectionService:GetTags(old) do
CollectionService:AddTag(new, t)
end
end
if opts.attributes then
for k, v in old:GetAttributes() do
if new:GetAttribute(k) == nil then
new:SetAttribute(k, v)
end
end
end
new.Parent = old.Parent
E.snapshotChanged(old, new)
old:Destroy()
table.insert(out, { old = old, new = new })
end
end
if opts.pause and n % 200 == 0 then
opts.pause()
end
end
return out
end
end
end)()
-- #module Seasons
MODULES["Seasons"] = (function()
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

local LEAF_WORDS = { "leaf", "leaves", "foliage", "bush", "shrub", "grass", "canopy", "needle", "pine", "fern", "hedge", "ivy", "moss" }
local function isFoliage(p, c)
if p.Material == Enum.Material.Grass or p.Material == Enum.Material.LeafyGrass then
return true
end
local h, s, v = c:ToHSV()
if h > 0.17 and h < 0.45 and s > 0.25 and v > 0.12 then
return true
end
return hasKeyword(p.Name, LEAF_WORDS) or (p.Parent and hasKeyword(p.Parent.Name, LEAF_WORDS))
end
local function isTop(p)
if hasKeyword(p.Name, { "roof", "rooftop" }) then
return true
end
local s = p.Size
local up = p.CFrame.UpVector.Y
return (p:IsA("WedgePart") and up > 0.5) or (up > 0.9 and s.Y <= math.min(s.X, s.Z) * 0.5)
end
local function pickOf(p)
local unit = p.Parent and p.Parent:IsA("Model") and p.Parent or p
local pos = unit:GetPivot().Position
local n = math.sin(pos.X * 12.9898 + pos.Y * 4.1414 + pos.Z * 78.233) * 43758.5453
return n - math.floor(n)
end

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
local function setKept(obj, prop, to)
if obj:GetAttribute(ORIG) == nil then
obj:SetAttribute(ORIG, obj[prop])
end
obj[prop] = to
end
local function original(obj, prop)
local o = obj:GetAttribute(ORIG)
return typeof(o) == "Color3" and o or obj[prop]
end

local TERRAIN_GREEN = { Enum.Material.Grass, Enum.Material.LeafyGrass }
local TERRAIN_TO = { Snow = Enum.Material.Snow, Dry = Enum.Material.Ground } -- (autumn keeps its grass)

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
local function recolor(p)
local base = original(p, "Color")
local amount = amountAt(p.Position)
local kind = { foliage = isFoliage(p, base), top = season == "Snow" and isTop(p), pick = pickOf(p) }
setKept(p, "Color", E.seasonColor(base, season, amount, kind))
for _, d in p:GetChildren() do
if d:IsA("SurfaceAppearance") then
pcall(function() -- (older Studio builds have no SurfaceAppearance.Color)
setKept(d, "Color", E.seasonColor(original(d, "Color"), season, amount, kind))
end)
elseif d:IsA("Decal") then
setKept(d, "Color3", E.seasonColor(original(d, "Color3"), season, amount, kind))
end
end
n += 1
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
terrainOk = pcall(function()
local saved = t:CopyRegion(Region3int16.new(v16(c0), v16(c1 - Vector3.one)))
local f = stateFolder(true)
saved.Name = "Terrain"
saved.Parent = f
f:SetAttribute("SS_TerrainCorner", c0)
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

function E.seasonInfo()
local f = stateFolder(false)
if not f or not f:GetAttribute("SS_Season") then
return nil
end
return { season = f:GetAttribute("SS_Season"), strength = f:GetAttribute("SS_Strength") or 1, parts = f:GetAttribute("SS_Parts") or 0 }
end

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
end)()

--[[
	Smart Scatter — Engine: the placement engine, with no UI. The plugin (App) drives it; the test suite too.
	Area mask → scan (surface classes + distance fields) → plan (rules → counts) → place → lines along edges and paths.
	Kinds reads a finished map: repeated models grouped by shape, and the snapshot that keeps their originals;
	Seasons turns it snowy, autumn or dry.
	Upright placement: a model's "up" is how it stands in the world, never its pivot rotation.

	Each module below is `return function(E, I) … end` and runs once, in ORDER:
	  E — the engine's API: what the plugin and the suite call.
	  I — internals the modules share with each other (helpers, tables); not for use outside the engine.
	A module may use what an earlier one put on E or I. To add a module: create it here and add its name to ORDER.
]]

local ORDER = { "Scan", "Assets", "Areas", "Paths", "Planning", "Placement", "Lines", "Pins", "Generate", "Kinds", "Seasons" }

local function module(name)
	return MODULES[name]
end

local E = {}
E.TAG = "SmartScatter" -- CollectionService tag on every placed copy
E.OUT = "SmartScatter" -- workspace folder holding the areas
E.ROADS = "SmartScatter Roads" -- road surfaces, one folder per area (kept outside E.OUT so raycasts hit them)
E.MASK_CELL = 4 -- area mask resolution in studs (older 8-stud areas are upgraded on load)

local I = {}
for _, name in ORDER do
	module(name)(E, I)
end
return E
