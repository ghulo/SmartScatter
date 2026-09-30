-- GENERATED part 2 of the flattened release by tools/tree.py: edit the modules, not this.
local MODULES = {}

-- #module Engine/Layout
MODULES["Engine/Layout"] = (function()
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
local HAND = "SS_HandPlaced"
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
function h.nearest(x, z, reach, skip)
local best, bv = math.huge, nil
local cx, cz = math.floor(x / size), math.floor(z / size)
if h.lo.X > h.hi.X then
return best, bv
end
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
if best <= ring * size then
break
end
end
return best, bv
end
return h
end
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
function E.relayout(points, spots, opts)
local d = math.max(opts.spacing or 1, 0.5)
local crowd, gap = opts.crowd or 0.5, opts.gap or 1.7
local step = opts.step or d / 3
local rng = Random.new(tonumber(opts.seed) or 1)
local all = hashOf(d)
for i, p in points do
all.add(p.x, p.z, i)
end
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
tooClose = dist < math.max(crowd * d, ((p.r or 0) + (o.r or 0)) * 0.9)
end
if tooClose then
crowded += 1
table.insert(pool, i)
else
kept.add(p.x, p.z, i)
end
end
end
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
local list = {}
for s in inHole do
table.insert(list, s)
end
table.sort(list, function(a, b)
if D[a] ~= D[b] then
return D[a] < D[b]
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
local usedI, usedT = {}, {}
local out = { moves = {}, adds = {}, removes = {}, crowded = crowded, bad = bad, holes = holes }
local function move(i, t)
usedI[i], usedT[t] = true, true
table.insert(out.moves, { i = i, x = targets[t].x, z = targets[t].z })
end
if #pool * #targets <= 200000 then
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
else
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
local function boxOf(inst)
if inst:IsA("BasePart") then
return inst.CFrame, inst.Size
end
return inst:GetBoundingBox()
end
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
local a = { rows = rows, count = count, cell = g, topY = hi.Y + 20, edge = 0, patches = 0, size = 1, seed = 1 }
local an, stopped = E.analyze(a, insts, opts.tick)
if not an then
return nil, stopped and "Stopped." or "Nothing to read there."
end
local l = E.makeLayer(copies[1].inst)
if not l then
return nil, "This kind's model can't be read (it needs parts)."
end
local s = l.s
s.useAlt, s.hug, s.slopePref, s.near = false, "None", 0, ""
l.paint = nil
E.heat(l, an, a)
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
local rp = an.rp
local ol = OverlapParams.new()
ol.FilterType = Enum.RaycastFilterType.Exclude
local ignore = table.clone(insts)
table.insert(ignore, workspace.Terrain)
ol.FilterDescendantsInstances = ignore
local offsets = {}
for _, c in copies do
local r = E.cast(Vector3.new(c.x, an.top, c.z), Vector3.new(0, -an.len, 0), rp)
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
local turned = math.sqrt(sumC ^ 2 + sumS ^ 2) / #yaws < 0.8
local rng = Random.new((tonumber(opts.seed) or 1) + 17)
local function standAt(x, z, c)
local r = E.cast(Vector3.new(x, an.top, z), Vector3.new(0, -an.len, 0), rp)
if not r or math.deg(math.acos(math.clamp(r.Normal.Y, -1, 1))) > s.maxSlope then
return nil
end
local hits = workspace:GetPartBoundsInRadius(r.Position + Vector3.new(0, c.h / 2 + 0.5, 0), math.max(c.r * 0.6, 0.5), ol)
for _, p in hits do
local ground = p == r.Instance or p.Position.Y < r.Position.Y
if not ground and (p.CanCollide or (p.Transparency < 1 and math.max(p.Size.X, p.Size.Y, p.Size.Z) > c.r * 0.5)) then
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
inst.Parent = nil
end
end
return added
end
end
end)()
-- #module App/Panel/StampTools
MODULES["App/Panel/StampTools"] = (function()
--[[
Smart Scatter — StampTools: the Stamp card (Brush tab), for putting single models down by hand anywhere, no area
needed (Viewport/Stamp does the stamping). Before stamping: stamp what's selected in the Explorer, or one of the
area's objects. While stamping: which model, its turn and size, standing along the surface, a random one after
each stamp, and its keys. The object's own Stamp button (Panel/HandTools) starts the same tool.
Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]
return function(App)
local G, saveG, P = App.G, App.saveG, App.P
local col, vlist, para = App.col, App.vlist, App.para
local slider, switchRow, button, buttonRow, hintOn, chip, chipGrid =
App.slider, App.switchRow, App.button, App.buttonRow, App.hintOn, App.chip, App.chipGrid
local key = App.keyText
local function controls(parent, rebuild)
local st = App.stamp
if #st.models > 1 then
local grid = chipGrid(parent, 3, 28, 104)
for i, inst in st.models do
chip(grid, inst.Name, function()
return st.vi == i
end, function()
App.setStamp(nil, nil, i)
rebuild()
end)
end
end
slider("Turn", 0, 359, function()
return math.floor(math.deg(st.yaw) + 0.5) % 360
end, function(v)
App.setStamp(v)
end, "%d°", 1, nil, nil, "Which way it faces. Drag in the viewport to aim it, or " .. key("turn") .. " to turn it in 15° steps.", 0).Parent =
parent
slider("Size", 0.1, 5, function()
return st.k
end, function(v)
App.setStamp(nil, v)
end, "%.2f×", 0.05, nil, nil, "1× is the model's own size. " .. key("shrink") .. " and " .. key("grow") .. " in the viewport.", 1).Parent =
parent
switchRow("Stand along the surface", function()
return G.stampAlign
end, function(v)
G.stampAlign = v
end, saveG, "On: it leans with slopes and can go on walls. Off: it stands upright, settled on the lowest ground under it.").Parent =
parent
switchRow("A random one after each stamp", function()
return G.stampRandom
end, function(v)
G.stampRandom = v
end, saveG, "After each stamp the next gets a random turn, a size a little either side of the one set, and a random model of these.").Parent =
parent
local acts = buttonRow(parent)
hintOn(
button("Random now", nil, App.rollStamp, { Parent = acts }),
"A random turn, size and model for the next stamp (" .. key("shuffle") .. " in the viewport)."
)
button("Stop stamping", nil, function()
App.setMode("Off")
end, { Parent = acts })
App.keyChips(parent, {
{ key("turn"), "turn" },
{ "Shift", "turn freely" },
{ "Shift + wheel", "turn" },
{ key("shrink") .. " " .. key("grow"), "size" },
{ "Alt + wheel", "size" },
{ key("model"), "model" },
{ key("shuffle"), "random" },
{ key("cancel"), "stop" },
})
end
App.stampControls = controls
App.stampViews = {}
App.refreshStamp = function()
for _, f in App.stampViews do
f()
end
end
App.buildStampCard = function(b)
local box = col({ Parent = b }, { vlist(6) })
local function build()
for _, c in box:GetChildren() do
if c:IsA("GuiObject") then
c:Destroy()
end
end
if App.mode == "Stamp" then
local inst = App.stamp.models[App.stamp.vi]
local head = para(
string.format(
"Stamping %s. Click the ground to put it down, press and drag to turn it. Stamps go in Workspace › Stamps.",
inst and inst.Name or "?"
),
{ Parent = box }
)
head.TextColor3 = P.text
controls(box, build)
return
end
App.explain(
box,
"One model, exactly where you click, anywhere on the ground: no area needed. Select a model (or a folder of them) in the Explorer, then:"
)
local go = App.primaryButton("Stamp selected models", function()
App.startStamp()
end)
go.Parent = buttonRow(box)
hintOn(go, "The selected models float under the mouse; click to put one down. Pick up where you left off with no selection.")
local a = App.area
if a and #a.layers > 0 then
App.label("Or one of this area's objects", 12, P.dim, App.SANS_B, { Size = UDim2.new(1, 0, 0, 20), Parent = box })
local grid = chipGrid(box, 3, 28, 104)
for _, l in a.layers do
chip(grid, l.inst.Name, nil, function()
App.startStamp(l)
end)
end
end
end
build()
App.stampViews.card = function()
if box.Parent then
build()
end
end
end
end
end)()
-- #module App/Panel/HandTools
MODULES["App/Panel/HandTools"] = (function()
--[[
Smart Scatter — HandTools: one object, by hand, as its Object tab shows it. The tools themselves (Spray, More,
Less, Erase, Reset) are in the viewport's strip and act on the active object; here: what they do, what was done
to this object by hand, and taking it back.
Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]
return function(App)
local P = App.P
local para, button, buttonRow, hintOn = App.para, App.button, App.buttonRow, App.hintOn
App.HAND_TOOLS = {
{
mode = "Place",
icon = "spray",
text = "Spray",
how = "Drag over the ground: copies land where you brush, at the object's spacing, and stay put when the area rebuilds.",
},
{ mode = "More", icon = "plus", text = "More", how = "Brush where you want it thicker, up to three times as much." },
{ mode = "Less", icon = "minus", text = "Less", how = "Brush where you want it thinner. Twice over clears it." },
{
mode = "None",
icon = "trash",
text = "Erase",
danger = true,
how = "Brush where you want none of it, copies put down by hand too. It stays gone when the area rebuilds.",
},
{
mode = "Clear",
icon = "refresh",
text = "Reset",
how = "Brush over More, Less and Erase to take them back: it grows there by its rules alone again.",
},
}
for i, t in App.HAND_TOOLS do
App.registerTool({
id = "object:" .. t.mode,
group = "Object",
order = i,
icon = t.icon,
name = t.text .. ": " .. t.how,
danger = t.danger,
when = function()
return App.brushTarget() ~= nil
end,
on = function()
return App.mode == t.mode and App.paintLayer == App.brushTarget()
end,
click = function()
App.setMode(t.mode, App.brushTarget())
end,
})
end
App.buildHandWork = function(l, parent)
local what = {}
if l.pins then
table.insert(what, #l.pins .. " put down by hand")
end
if l.paint then
table.insert(what, "painted more or less in places")
end
local line = para(
#what > 0 and (table.concat(what, " · ") .. ".")
or "Nothing done by hand yet. Pick Spray, More, Less, Erase or Reset in the viewport's strip: they act on this object.",
{ Parent = parent }
)
line.TextColor3 = #what > 0 and P.text or P.faint
if not (l.paint or l.pins) then
return
end
local row = buttonRow(parent)
if l.paint then
hintOn(
button("Reset all painting", nil, function()
l.paint = nil
if App.paintLayer == l then
App.recolorOverlay()
end
App.applyNow(l, "Reset painting")
App.refreshObjects()
end, { Parent = row }),
"Forgets every More, Less and Erase for this object: it grows by its rules alone again."
)
end
if l.pins then
local rm = App.dangerButton(string.format("Remove %d put down by hand", #l.pins), function()
l.pins = nil
App.applyNow(l, "Remove hand-placed")
App.refreshObjects()
end, { confirm = "Click again to remove" })
rm.Parent = row
hintOn(rm, "Takes out every copy of it you put down with Spray. Ctrl+Z brings them back.")
end
end
end
end)()
-- #module App/Panel/MapTools
MODULES["App/Panel/MapTools"] = (function()
--[[
Smart Scatter — MapTools: working on a finished map, as the controls the Map tab puts in its cards. The map scan
(every repeated model, grouped into kinds by shape), swapping a kind for other models (tried on a few copies
first), improving a kind's layout (re-spacing crowded and empty spots, previewed in the viewport), seasons
(snowy, autumn or dry, fully or in patches), and the snapshot (the originals kept before anything changes them,
and putting them back).
Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]
return function(App)
local Selection, Engine, G, saveG, P, num = App.Selection, App.Engine, App.G, App.saveG, App.P, App.num
local SANS, SANS_M, SANS_B, box, col, label, vlist = App.SANS, App.SANS_M, App.SANS_B, App.box, App.col, App.label, App.vlist
local button, buttonRow, hintOn, explain, beginRec, endRec = App.button, App.buttonRow, App.hintOn, App.explain, App.beginRec, App.endRec
local SHOWN = 12
App.kinds = nil
local scanning, showAll, scope = false, false, "the whole map"
local function alive(k)
local out = {}
for _, c in k.copies do
if c.inst.Parent then
table.insert(out, c.inst)
end
end
return out
end
local restoreButton
local function keepOriginals(list)
local rec = beginRec("Smart Scatter: Keep originals")
local n = Engine.snapshot(list)
endRec(rec, n == 0)
return n
end
local lastRoots, lastScanned = nil, false
local runScan
local function scanAgain()
if lastScanned then
runScan(lastRoots or false, true)
end
end
function runScan(roots, quiet)
if scanning then
return
end
if roots == false then
roots = nil
elseif roots == nil and G.scanSelection then
roots = {}
for _, s in Selection:Get() do
table.insert(roots, s)
end
if #roots == 0 then
App.status("Select the models or folders to scan in the Explorer first, or turn off Only the selection.")
return
end
end
for _, r in roots or {} do
if not r.Parent then
return
end
end
scanning = true
lastRoots, lastScanned = roots, true
App.rebuildAll()
if not quiet then
App.status("Scanning the map…")
end
task.spawn(function()
local ok, kinds = pcall(Engine.scanKinds, { roots = roots, pause = task.wait })
scanning = false
if not ok then
App.status("The scan stopped: " .. tostring(kinds), "error")
App.rebuildAll()
return
end
App.kinds, showAll = kinds, false
scope = roots and (#roots == 1 and roots[1].Name or (#roots .. " selected")) or "the whole map"
local copies = 0
for _, k in kinds do
copies += k.count
end
if not quiet then
App.status(#kinds == 0 and "No repeated models found." or string.format("Found %d kinds, %s copies in all.", #kinds, num(copies)))
end
App.rebuildAll()
end)
end
local swap = { key = nil, with = {}, size = 1, match = false, turn = 0, scripts = false, tags = true, attributes = true }
local selectedModels
local function swapKind()
for _, k in App.kinds or {} do
if k.key == swap.key then
return k
end
end
return nil
end
local function kindRow(parent, k)
local list = alive(k)
local row = box({ Size = UDim2.new(1, 0, 0, 36), Parent = parent })
local th = App.thumbnail(k.copies[1].inst, 30)
th.Position = UDim2.fromOffset(0, 3)
th.Parent = row
label(k.name, 13, P.text, SANS_M, { Position = UDim2.fromOffset(40, 1), Size = UDim2.new(1, -170, 0, 18), Parent = row })
label(string.format("%s cop%s", num(#list), #list == 1 and "y" or "ies"), 11, P.dim, SANS, {
Position = UDim2.fromOffset(40, 18),
Size = UDim2.new(1, -170, 0, 16),
Parent = row,
})
hintOn(row, string.format("%s: %s copies of %d part%s each.", k.name, num(#list), k.parts, k.parts == 1 and "" or "s"))
local acts = box({
AnchorPoint = Vector2.new(1, 0.5),
Position = UDim2.new(1, 0, 0.5, 0),
Size = UDim2.fromOffset(0, 30),
AutomaticSize = Enum.AutomaticSize.X,
Parent = row,
}, { App.hlist(6) })
hintOn(
button("Select", nil, function()
local now = alive(k)
Selection:Set(now)
App.status(string.format("Selected %s %s.", num(#now), #now == 1 and "copy" or "copies"))
end, { LayoutOrder = 1, Parent = acts }),
"Selects every copy of this kind in the Explorer and the viewport."
)
local picked = swap.key == k.key
hintOn(
button("Swap", picked and "accent" or nil, function()
if swap.key ~= k.key then
swap.key, swap.preview, swap.ref, swap.with = k.key, nil, nil, {}
end
for _, inst in selectedModels(k) do
table.insert(swap.with, { inst = inst, w = 1 })
break
end
swap.jump = true
App.status(
#swap.with > 0 and string.format("Swapping %s for %s: Try on 5 to check it, or Swap all.", k.name, swap.with[1].inst.Name)
or string.format("Now select the model to swap in for %s, and press Use selected models.", k.name)
)
App.rebuildAll()
end, { LayoutOrder = 2, Parent = acts }),
"Swap every copy of this kind for another model, or a mix. Tip: select the new model first, then press Swap."
)
end
App.buildMapScan = function(b)
App.switchRow("Only the selection", function()
return G.scanSelection == true
end, function(v)
G.scanSelection = v
end, function()
saveG()
end, "On: scans only inside the models and folders selected in the Explorer. Off: the whole Workspace.").Parent =
b
local go = App.primaryButton(scanning and "Scanning…" or (App.kinds and "Scan again" or "Scan the map"), function()
runScan()
end)
go.Parent = b
hintOn(
go,
"Finds every model that appears more than once, by its shape: renamed, turned and resized copies still match. What Smart Scatter placed, and characters, are left out."
)
local kinds = App.kinds
if not kinds then
explain(b, "Groups the copies in a finished map into kinds, so you can pick every copy of one at once.")
return
end
if #kinds == 0 then
App.emptyState(b, "No repeated models", "Nothing in " .. scope .. " appears more than once.")
return
end
local copies = 0
for _, k in kinds do
copies += k.count
end
App.para(string.format("%d kind%s · %s copies · in %s", #kinds, #kinds == 1 and "" or "s", num(copies), scope), { Parent = b }).Font =
SANS_B
local list = col({ Parent = b }, { vlist(4) })
for i, k in kinds do
if i > SHOWN and not showAll then
break
end
kindRow(list, k)
end
if #kinds > SHOWN then
button(showAll and "Show fewer" or string.format("Show all %d", #kinds), "ghost", function()
showAll = not showAll
App.rebuildAll()
end, { Parent = buttonRow(b) })
end
end
function selectedModels(k)
local out, own = {}, {}
for _, c in k and k.copies or {} do
own[c.inst] = true
end
for _, sel in Selection:Get() do
for _, inst in sel:IsA("Folder") and sel:GetChildren() or { sel } do
if (inst:IsA("Model") or inst:IsA("BasePart")) and not own[inst] and Engine.keyOf(inst) then
table.insert(out, inst)
end
end
end
return out
end
local function doSwap(k, copies, preview)
keepOriginals(alive(k))
local rec = beginRec(preview and "Smart Scatter: Try swap" or "Smart Scatter: Swap models")
swap.ref = swap.ref or Engine.kindRef(k.copies)
local ok, pairsOrErr = pcall(Engine.swapCopies, copies, swap.with, {
ref = swap.ref,
size = swap.size,
match = swap.match,
turn = swap.turn,
scripts = swap.scripts,
tags = swap.tags,
attributes = swap.attributes,
seed = #k.copies,
})
endRec(rec, not ok)
if not ok then
App.status("The swap stopped: " .. tostring(pairsOrErr), "error")
return nil
end
local newOf = {}
for _, pr in pairsOrErr do
newOf[pr.old] = pr.new
end
for _, c in k.copies do
c.inst = newOf[c.inst] or c.inst
end
return pairsOrErr
end
App.buildSwap = function(b)
local k = swapKind()
if not k then
swap.key, swap.preview, swap.ref = nil, nil, nil
explain(
b,
App.kinds and "Press Swap on a kind in the Map scan to replace its copies with another model or a mix."
or "Scan the map first, then press Swap on a kind."
)
return
end
if swap.jump then
swap.jump = false
App.scrollIntoView(b.Parent)
end
local head = box({ Size = UDim2.new(1, 0, 0, 36), Parent = b })
local th = App.thumbnail(k.copies[1].inst, 32)
th.Position = UDim2.fromOffset(0, 2)
th.Parent = head
label("Swap " .. k.name, 13, P.text, SANS_B, { Position = UDim2.fromOffset(40, 1), Size = UDim2.new(1, -40, 0, 18), Parent = head })
label(string.format("%s copies in the map", num(#alive(k))), 11, P.dim, SANS, {
Position = UDim2.fromOffset(40, 18),
Size = UDim2.new(1, -40, 0, 16),
Parent = head,
})
if #swap.with == 0 then
App.hintBox(b, "Select the model to swap in (or several to mix) in the Explorer, then press Use selected models.")
end
label("For", 13, P.text, SANS, { Parent = b })
for i, w in swap.with do
local row = box({ Size = UDim2.new(1, 0, 0, 32), Parent = b })
local t = App.thumbnail(w.inst, 28)
t.Position = UDim2.fromOffset(0, 2)
t.Parent = row
label(w.inst.Name, 13, P.text, SANS_M, { Position = UDim2.fromOffset(36, 0), Size = UDim2.new(1, -120, 1, 0), Parent = row })
button("Remove", "danger", function()
table.remove(swap.with, i)
App.rebuildAll()
end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Parent = row })
if #swap.with > 1 then
App.slider("Share", 0, 10, function()
return w.w
end, function(v)
w.w = v
end, "%.1f", 0.5, nil, nil, "How often this model is picked compared to the others.", 1).Parent =
b
end
end
local pickRow = buttonRow(b)
hintOn(
button(#swap.with == 0 and "Use selected models" or "Add selected models", #swap.with == 0 and "accent" or nil, function()
local found = selectedModels(k)
if #found == 0 then
App.status("Select the new model, or several to mix, in the Explorer first (not a copy of this kind).")
return
end
for _, inst in found do
local dup = false
for _, w in swap.with do
dup = dup or w.inst == inst
end
if not dup then
table.insert(swap.with, { inst = inst, w = 1 })
end
end
App.rebuildAll()
end, { Parent = pickRow }),
"Select the model to swap in, or several to mix (a folder works too), in the Explorer, then click."
)
if #swap.with == 0 then
return
end
App.slider("Size", 0.2, 4, function()
return swap.size
end, function(v)
swap.size = v
end, "%.2f×", 0.05, nil, nil, "On top of each copy's own scale.", 1).Parent =
b
App.switchRow(
"Same size as the old ones",
function()
return swap.match
end,
function(v)
swap.match = v
end,
nil,
"On: each new copy is made as big as the one it replaces. Off: the new model keeps its own size, bigger or smaller where the old copies were."
).Parent =
b
label("Turn", 13, P.text, SANS, { Parent = b })
App.segmented({ "0°", "90°", "180°", "270°" }, function()
return swap.turn .. "°"
end, function(v)
swap.turn = tonumber(string.match(v, "%d+")) or 0
end).Parent =
b
explain(b, "If the new model faces another way than the old one, turn every copy about its up.")
for _, o in
{
{ "scripts", "Carry over scripts", "Copies the old copy's scripts into the new one." },
{ "tags", "Carry over tags", "The old copy's CollectionService tags go on the new one." },
{ "attributes", "Carry over attributes", "The old copy's attributes go on the new one." },
}
do
App.switchRow(o[2], function()
return swap[o[1]]
end, function(v)
swap[o[1]] = v
end, nil, o[3]).Parent = b
end
local acts = buttonRow(b)
local n = #alive(k)
if swap.preview then
hintOn(
button("Undo the try", nil, function()
local only = {}
for _, pr in swap.preview do
only[pr.new] = true
end
local rec = beginRec("Smart Scatter: Undo try")
local back, map = Engine.restoreSnapshot(only)
endRec(rec, back == 0)
for _, c in k.copies do
c.inst = map[c.inst] or c.inst
end
swap.preview = nil
App.status(string.format("Put %d back as they were.", back))
App.rebuildAll()
end, { Parent = acts }),
"Puts the tried copies back as they were."
)
else
hintOn(
button("Try on 5", nil, function()
local copies, list = {}, {}
for _, c in k.copies do
if c.inst.Parent then
table.insert(list, c)
end
end
for i = 1, math.min(5, #list) do
table.insert(copies, list[math.floor((i - 0.5) * #list / math.min(5, #list)) + 1])
end
local done = doSwap(k, copies, true)
if done then
swap.preview = done
local sel = {}
for _, pr in done do
table.insert(sel, pr.new)
end
Selection:Set(sel)
App.status(string.format("Swapped %d copies to try (selected). Swap all, or undo the try.", #done))
end
App.rebuildAll()
end, { Parent = acts }),
"Swaps 5 copies spread over the map, and selects them, so you can check the look first."
)
end
hintOn(
button(string.format("Swap all %s", num(n)), "accent", function()
local tried, copies = {}, {}
for _, pr in swap.preview or {} do
tried[pr.new] = true
end
for _, c in k.copies do
if not tried[c.inst] then
table.insert(copies, c)
end
end
local done = doSwap(k, copies, false)
if done then
App.status(
string.format(
"Swapped %s copies. The originals are kept: Restore original in the Snapshot card puts them back.",
num(#done + #(swap.preview or {}))
)
)
scanAgain()
swap.key, swap.preview, swap.ref = nil, nil, nil
end
App.rebuildAll()
end, { Parent = acts }),
"Swaps every copy of this kind. Their originals are kept in the snapshot first."
)
App.keptNote(b)
end
local tidy = { key = nil, spacing = 1, crowd = 0.5, gap = 1.7, fill = true, fixRules = true, remove = false, plan = nil }
local tidyBusy = false
local PREVIEW = "SmartScatterLayoutPreview"
local function clearPreview()
local cam = workspace.CurrentCamera
local f = cam and cam:FindFirstChild(PREVIEW)
if f then
f:Destroy()
end
end
clearPreview()
local function drawPreview(plan)
clearPreview()
local f = App.new("Folder", { Name = PREVIEW, Archivable = false, Parent = workspace.CurrentCamera })
local T = workspace.Terrain
local MOVE, ADD, OUT = Color3.fromRGB(245, 166, 60), Color3.fromRGB(110, 210, 120), Color3.fromRGB(235, 80, 70)
local flat = CFrame.Angles(math.rad(90), 0, 0)
local function disc(at, r, color, inner)
App.new("CylinderHandleAdornment", {
Adornee = T,
CFrame = CFrame.new(at + Vector3.new(0, 0.3, 0)) * flat,
Radius = r,
InnerRadius = inner or 0,
Height = 0.2,
Color3 = color,
Transparency = inner and 0.1 or 0.35,
AlwaysOnTop = true,
ZIndex = 3,
Parent = f,
})
end
local function dot(at, color)
App.new("SphereHandleAdornment", {
Adornee = T,
CFrame = CFrame.new(at + Vector3.new(0, 0.6, 0)),
Radius = 0.9,
Color3 = color,
AlwaysOnTop = true,
ZIndex = 4,
Parent = f,
})
end
local r = math.max(plan.spacing * 0.2, 1)
for _, mv in plan.moves do
local a, b = mv.from + Vector3.new(0, 0.6, 0), mv.to + Vector3.new(0, 0.6, 0)
dot(mv.from, MOVE)
App.new("LineHandleAdornment", {
Adornee = T,
CFrame = CFrame.lookAt(a, b),
Length = (b - a).Magnitude,
Thickness = 3,
Color3 = MOVE,
AlwaysOnTop = true,
ZIndex = 3,
Parent = f,
})
disc(mv.to, r, MOVE)
end
for _, ad in plan.adds do
disc(ad.to, r, ADD)
end
for _, inst in plan.removes do
if inst.Parent then
local cf = inst:GetPivot()
disc(cf.Position, r * 1.3, OUT, r * 1.1)
end
end
end
local function tidyKind()
for _, k in App.kinds or {} do
if k.key == tidy.key then
return k
end
end
return nil
end
local function dropPlan()
tidy.plan = nil
clearPreview()
end
local function runPlan()
local k = tidyKind()
if tidyBusy or not k then
return
end
tidyBusy = true
dropPlan()
App.status("Reading the ground around " .. k.name .. "…")
App.rebuildAll()
task.spawn(function()
local rows = 0
local ok, plan, why = pcall(Engine.layoutPlan, k, {
spacing = tidy.spacing,
crowd = tidy.crowd,
gap = tidy.gap,
fill = tidy.fill,
fixRules = tidy.fixRules,
remove = tidy.remove,
seed = 11,
tick = function(p)
rows += 1
if rows % 8 == 0 then
App.showProgress("Scanning", p)
task.wait()
end
return true
end,
})
App.showProgress(nil)
tidyBusy = false
if not ok then
App.status("The plan stopped: " .. tostring(plan), "error")
elseif not plan then
App.status(why or "Nothing to plan.")
else
tidy.plan = plan
drawPreview(plan)
local nothing = #plan.moves + #plan.adds + #plan.removes == 0
App.status(
nothing and (k.name .. " is already well spaced: nothing to change.")
or "The plan is in the viewport: orange moves, green is added, red is taken out. Apply, or change the settings and plan again."
)
end
App.rebuildAll()
end)
end
local function applyPlan()
local k, plan = tidyKind(), tidy.plan
if not (k and plan) then
return
end
local touched = table.clone(plan.removes)
for _, mv in plan.moves do
table.insert(touched, mv.inst)
end
keepOriginals(touched)
local rec = beginRec("Smart Scatter: Improve layout")
local ok, added = pcall(Engine.layoutApply, plan)
endRec(rec, not ok)
dropPlan()
if not ok then
App.status("Stopped: " .. tostring(added), "error")
App.rebuildAll()
return
end
for _, inst in added do
table.insert(k.copies, { inst = inst, scale = 1 })
end
local sel = table.clone(added)
for _, mv in plan.moves do
table.insert(sel, mv.inst)
end
Selection:Set(sel)
App.status(
string.format(
"%s: moved %d, added %d, took out %d (the changed ones are selected). Restore original in the Snapshot card puts it all back.",
k.name,
#plan.moves,
#added,
#plan.removes
)
)
App.rebuildAll()
end
App.buildImproveLayout = function(b)
local kinds = {}
for _, k in App.kinds or {} do
if #alive(k) >= 3 then
table.insert(kinds, k)
end
end
if #kinds == 0 then
tidy.key = nil
dropPlan()
explain(b, App.kinds and "No kind has enough copies (3 or more) to space out." or "Scan the map first, then pick a kind to space out.")
return
end
if not tidyKind() then
tidy.key = kinds[1].key
dropPlan()
end
label("Kind", 13, P.text, SANS, { Parent = b })
local grid = App.chipGrid(b, 2, 30)
for i, k in kinds do
if i > 8 then
break
end
App.chip(grid, string.format("%s  ×%s", k.name, num(#alive(k))), function()
return tidy.key == k.key
end, function()
if tidy.key ~= k.key then
tidy.key = k.key
dropPlan()
App.rebuildAll()
end
end).LayoutOrder =
i
end
local k = tidyKind()
local list, hand = alive(k), 0
for _, inst in list do
hand += Engine.isHandPlaced(inst) and 1 or 0
end
local function changed()
if tidy.plan then
dropPlan()
App.rebuildAll()
end
end
App.slider(
"Spacing",
0.5,
2,
function()
return tidy.spacing
end,
function(v)
tidy.spacing = v
end,
"%.2f×",
0.05,
nil,
changed,
"1× keeps the kind's own typical spacing, the usual gap between neighbours. Lower packs it closer, higher spreads it out.",
1
).Parent =
b
App.slider("Crowded under", 0.2, 0.9, function()
return tidy.crowd
end, function(v)
tidy.crowd = v
end, "%.0f%%", 0.05, nil, changed, "A copy closer than this to another (as a share of the spacing), or overlapping it, is crowded.", 0.5).Parent =
b
App.slider(
"Empty over",
1.2,
3,
function()
return tidy.gap
end,
function(v)
tidy.gap = v
end,
"%.0f%%",
0.05,
nil,
changed,
"A spot farther than this from every copy (as a share of the spacing) is a hole. Lower fills smaller holes.",
1.7
).Parent =
b
for _, o in
{
{ "fill", "Fill holes with new copies", "Holes left once the crowded copies have moved get new copies, cloned from the kind." },
{
"fixRules",
"Move ones that break the rules",
"Copies standing where the kind never should (on a road, in water, too steep) move too.",
},
{ "remove", "Take out extras that can't move", "Crowded copies with no hole to go to are taken out. Off: they stay where they are." },
}
do
App.switchRow(o[2], function()
return tidy[o[1]]
end, function(v)
tidy[o[1]] = v
end, changed, o[3]).Parent = b
end
explain(
b,
hand > 0
and string.format(
"%d hand-placed cop%s stay%s exactly where %s.",
hand,
hand == 1 and "y" or "ies",
hand == 1 and "s" or "",
hand == 1 and "it is" or "they are"
)
or "Mark copies you placed on purpose as hand-placed: they never move, and others make room around them."
)
local handRow = buttonRow(b)
local function mark(on)
local sel = Selection:Get()
if #sel == 0 then
App.status("Select the copies (or a folder of them) in the Explorer first.")
return
end
local rec = beginRec(on and "Smart Scatter: Mark hand-placed" or "Smart Scatter: Unmark hand-placed")
Engine.setHandPlaced(sel, on)
endRec(rec)
App.status(string.format("%s %d as hand-placed.", on and "Marked" or "Unmarked", #sel))
dropPlan()
App.rebuildAll()
end
hintOn(
button("Mark selected as hand-placed", nil, function()
mark(true)
end, { Parent = handRow }),
"The selected copies, or everything in a selected folder, never move or go."
)
button("Unmark", "ghost", function()
mark(false)
end, { Parent = handRow })
local plan = tidy.plan
if plan then
local stats = col({ BackgroundTransparency = 0, BackgroundColor3 = P.raised, Parent = b }, {
App.corner(10),
App.pad(12, 12, 10, 10),
vlist(4),
})
label(
string.format("Spacing %.0f studs · crowded %d · breaking rules %d · holes %d", plan.spacing, plan.crowded, plan.bad, plan.holes),
12,
P.dim,
SANS,
{ Parent = stats }
)
label(string.format("Move %d · add %d · take out %d", #plan.moves, #plan.adds, #plan.removes), 13, P.text, SANS_B, { Parent = stats })
label(
string.format("Evenness %d%% → %d%%", math.floor(plan.evenBefore * 100 + 0.5), math.floor(plan.evenAfter * 100 + 0.5)),
13,
plan.evenAfter >= plan.evenBefore and P.accent or P.danger,
SANS_B,
{ Parent = stats }
)
end
local acts = buttonRow(b)
if plan and #plan.moves + #plan.adds + #plan.removes > 0 then
hintOn(
button("Apply", "accent", applyPlan, { Parent = acts }),
"Carries out the plan as one step (Ctrl+Z undoes it). Every copy it touches is kept in the snapshot first."
)
end
hintOn(
button(tidyBusy and "Planning…" or (plan and "Plan again" or "Plan"), if plan then nil else "accent", runPlan, { Parent = acts }),
"Reads the ground around the kind with its placement rules and works out what to move, add or take out. Nothing changes until you Apply."
)
if plan then
button("Clear preview", "ghost", function()
dropPlan()
App.rebuildAll()
end, { Parent = acts })
end
App.keptNote(b)
end
local season = {
name = "Snow",
strength = 1,
patchy = 0,
patchSize = 90,
selection = false,
terrainColors = true,
terrainMaterials = false,
}
local seasonBusy = false
local function runSeason(off)
if seasonBusy then
return
end
local roots
if season.selection then
roots = Selection:Get()
if #roots == 0 then
App.status("Select the models or folders to change in the Explorer first, or turn off Only the selection.")
return
end
end
seasonBusy = true
App.status(off and "Taking the season off…" or ("Turning the map " .. string.lower(season.name) .. "…"))
App.rebuildAll()
task.spawn(function()
local rec = beginRec(off and "Smart Scatter: Season off" or ("Smart Scatter: " .. season.name))
local ok, n, terrainOk = pcall(function()
if off then
return Engine.clearSeason({ roots = roots, pause = task.wait })
end
return Engine.applySeason({
season = season.name,
strength = season.strength,
patchy = season.patchy,
patchSize = season.patchSize,
seed = 7,
roots = roots,
terrainColors = season.terrainColors,
terrainMaterials = season.terrainMaterials,
pause = task.wait,
})
end)
endRec(rec, not ok)
seasonBusy = false
if not ok then
App.status("Stopped: " .. tostring(n), "error")
elseif off then
App.status(string.format("Season off: %s parts back to their own colours.", num(n)))
else
App.status(
string.format("%s: %s parts changed.", season.name, num(n))
.. (terrainOk == false and " The terrain was too big to keep a copy of, so its grass stayed; try Only the selection." or "")
)
end
App.rebuildAll()
end)
end
App.buildSeasons = function(b)
local grid = App.chipGrid(b, 3, 30)
for i, name in Engine.SEASONS do
local c = App.chip(grid, name, function()
return season.name == name
end, function()
season.name = name
App.rebuildAll()
end)
c.LayoutOrder = i
hintOn(c, Engine.SEASON_HINT[name])
end
App.slider("Strength", 0, 1, function()
return season.strength
end, function(v)
season.strength = v
end, "%.0f%%", 0.05, nil, nil, "How far into the season: 100% is fully snowy, autumn or dry.", 1).Parent =
b
App.slider("Patchy", 0, 1, function()
return season.patchy
end, function(v)
season.patchy = v
end, "%.0f%%", 0.05, nil, nil, "0%: the same everywhere. Higher: stronger in some places and lighter in others, like the first snow.", 0).Parent =
b
if season.patchy > 0 then
App.slider("Patch size", 20, 300, function()
return season.patchSize
end, function(v)
season.patchSize = v
end, "%.0f studs", 5, nil, nil, "How big the stronger and lighter patches are.", 90).Parent =
b
end
for _, o in
{
{ "selection", "Only the selection", "On: changes only the models and folders selected in the Explorer. Off: the whole Workspace." },
{ "terrainColors", "Terrain grass colour", "Tints the terrain's grass for the season." },
{
"terrainMaterials",
season.name == "Dry" and "Terrain grass to dry ground" or "Terrain grass to snow",
"Turns the terrain's grass itself around the map. The terrain there is kept first, so it comes back exactly.",
},
}
do
if not (o[1] == "terrainMaterials" and season.name == "Autumn") then
App.switchRow(o[2], function()
return season[o[1]]
end, function(v)
season[o[1]] = v
end, nil, o[3]).Parent = b
end
end
local info = Engine.seasonInfo()
explain(
b,
info
and string.format(
"The map is %s now (%d%%). Applying again starts from the original colours.",
string.lower(info.season),
info.strength * 100
)
or "Colours keep their originals, so a season can be switched or taken off again exactly. What Smart Scatter places has its own Colour zones."
)
local row = buttonRow(b)
button(seasonBusy and "Working…" or ("Make it " .. string.lower(season.name == "Snow" and "snowy" or season.name)), "accent", function()
runSeason(false)
end, { Parent = row })
if info then
hintOn(
button("Take it off", nil, function()
runSeason(true)
end, { Parent = row }),
"Every colour back to its own, and the terrain as it was."
)
end
end
function restoreButton(row)
local armed = 0
local restore
restore = button("Restore original", "danger", function()
if os.clock() - armed > 3 then
armed = os.clock()
restore.Text = "Click again to restore"
task.delay(3, function()
if os.clock() - armed >= 2.9 then
restore.Text = "Restore original"
end
end)
return
end
armed = 0
local rec = beginRec("Smart Scatter: Restore original")
local back = Engine.restoreSnapshot()
endRec(rec, back == 0)
swap.preview = nil
dropPlan()
scanAgain()
App.status(string.format("Put %s copies back as they were. Ctrl+Z undoes it.", num(back)))
App.rebuildAll()
end, { Parent = row })
hintOn(restore, "Puts every changed copy back exactly as it was kept, where it was. Ctrl+Z undoes it.")
return restore
end
local function keptNote(b)
local info = Engine.snapshotInfo()
if info and info.changed > 0 then
explain(b, string.format("The originals are kept (%s changed so far).", num(info.changed)))
restoreButton(buttonRow(b))
else
explain(b, "The originals are kept automatically before anything changes: Restore original puts them back.")
end
end
App.keptNote = keptNote
App.buildSnapshot = function(b)
local info = Engine.snapshotInfo()
local text
if not info then
text = "Nothing kept yet. Keep the originals before swapping models or changing seasons, and put them back with one click."
else
text = string.format(
"%s cop%s kept%s. %s",
num(info.saved),
info.saved == 1 and "y" or "ies",
info.time and os.date(" on %d %b, %H:%M", info.time) or "",
info.changed > 0 and string.format("%s changed since.", num(info.changed)) or "Nothing changed since."
)
end
explain(b, text)
local row = buttonRow(b)
local kinds = App.kinds
hintOn(
button("Keep originals", "accent", function()
if not (App.kinds and #App.kinds > 0) then
App.status("Scan the map first: the snapshot keeps the copies it finds.")
return
end
local list = {}
for _, k in App.kinds do
for _, inst in alive(k) do
table.insert(list, inst)
end
end
local rec = beginRec("Smart Scatter: Keep originals")
local added = Engine.snapshot(list)
endRec(rec, added == 0)
App.status(
added == 0 and "Every copy found is already kept."
or string.format("Kept the originals of %s copies (ServerStorage › SmartScatter Snapshot).", num(added))
)
App.rebuildAll()
end, { Parent = row }),
kinds and "Keeps a copy of every model the scan found, as it is now. Copies kept before stay as they were."
or "Scan the map first; this keeps a copy of every model it finds."
)
if info and info.changed > 0 then
restoreButton(row)
end
if info then
hintOn(
button("Forget", "ghost", function()
App.dialog(
"Forget the snapshot?",
"The map stays as it is now, but the kept originals are deleted, so changed copies can't be put back any more.",
{
{
"Forget it",
"danger",
function()
local rec = beginRec("Smart Scatter: Forget snapshot")
Engine.clearSnapshot()
endRec(rec)
App.status("Snapshot forgotten.")
App.rebuildAll()
end,
},
{ "Keep it", nil, function() end },
}
)
end, { Parent = row }),
"Deletes the kept originals (the map stays as it is)."
)
end
end
end
end)()
-- #module App/Panel/ArrayTools
MODULES["App/Panel/ArrayTools"] = (function()
--[[
Smart Scatter — ArrayTools: arrays, one model repeated in a pattern (Engine/Arrays does the maths). An array is a
Model in Workspace › Arrays: its settings in an attribute (SS_Array), its source model and the path it may follow
as ObjectValues (Source, Path), its origin as its pivot (so moving it with Studio's Move tool moves the array),
and its copies in a folder (Copies) rebuilt from the settings whenever they change.
The copies stay out of the undo history, as an area's objects do: a setting changed is one undo step, and undo
brings the setting back and the copies are rebuilt from it. Bake turns an array into a plain model.
Here: making one, reading and saving its settings, building its copies, the outliner's Array kind and its tab.
The strip's Array tool (click and drag to make one) is Viewport/ArrayTool.
Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]
return function(App)
local Engine, P, beginRec, endRec = App.Engine, App.P, App.beginRec, App.endRec
local HttpService = game:GetService("HttpService")
local FOLDER, ATTR = "Arrays", "SS_Array"
local BARE = { s = {} }
local LIVE_MAX = 250
local function folder(make)
local f = workspace:FindFirstChild(FOLDER)
if not f and make then
f = Instance.new("Folder")
f.Name = FOLDER
f.Parent = workspace
end
return f
end
local function isArray(m)
return m ~= nil and m:IsA("Model") and m:GetAttribute(ATTR) ~= nil
end
App.isArrayModel = isArray
App.arrays = function()
local out = {}
for _, m in (folder() and folder():GetChildren() or {}) do
if isArray(m) then
table.insert(out, m)
end
end
return out
end
App.arrayThing = function(m)
return { kind = "Array", folder = m }
end
local function read(m)
local ok, t = pcall(HttpService.JSONDecode, HttpService, m:GetAttribute(ATTR) or "{}")
return Engine.arrayDefaults(ok and type(t) == "table" and t or {})
end
App.readArray = read
local function linked(m, name)
local v = m:FindFirstChild(name)
return v and v:IsA("ObjectValue") and v.Value or nil
end
local measured = setmetatable({}, { __mode = "k" })
local function variantOf(inst)
local v = measured[inst]
if v == nil then
v = Engine.makeVariant(inst, 1, 1) or false
measured[inst] = v
end
return v or nil
end
local function groundParams()
local skip = App.templates()
local f = folder()
if f then
table.insert(skip, f)
end
return (Engine.rayParams(skip))
end
local built = setmetatable({}, { __mode = "k" })
local function pathOf(m)
local f = linked(m, "Path")
if not (f and f:IsDescendantOf(workspace)) then
return nil
end
local a = Engine.loadArea(f)
local sp = a.spline
if not (sp and #sp.pts >= 2) then
return nil
end
local pts = Engine.splineCurve(sp, 1)
return pts, sp.closed == true and #sp.pts >= 3
end
local function build(m, s)
s = s or read(m)
local src = linked(m, "Source")
local v = src and src.Parent and variantOf(src)
local holder = Instance.new("Folder")
holder.Name = "Copies"
holder.Archivable = false
local placed = 0
if v then
local P, closed
if s.shape == "Path" then
P, closed = pathOf(m)
end
local pivot = m:GetPivot()
local look = Vector3.new(pivot.LookVector.X, 0, pivot.LookVector.Z)
local origin = CFrame.lookAt(pivot.Position, pivot.Position + (look.Magnitude > 1e-3 and look.Unit or Vector3.new(0, 0, -1)))
local rp = s.ground and groundParams()
for _, c in Engine.arrayCopies(s, P, closed) do
local at = s.shape == "Path" and CFrame.new(c.pos) * CFrame.Angles(0, c.yaw, 0)
or origin * CFrame.new(c.pos) * CFrame.Angles(0, c.yaw, 0)
local pos = at.Position
if rp then
local hit = Engine.cast(pos + Vector3.new(0, 60, 0), Vector3.new(0, -400, 0), rp)
if hit then
pos = Vector3.new(pos.X, hit.Position.Y, pos.Z)
end
end
at = at.Rotation + pos + Vector3.new(0, s.lift, 0)
local copy = (v.src or src):Clone()
Engine.poseCopy(copy, BARE, v, c.scale, at, 0)
for _, d in copy:GetDescendants() do
if d:IsA("BasePart") then
d.Anchored = true
end
end
if copy:IsA("BasePart") then
copy.Anchored = true
end
copy.Parent = holder
placed += 1
end
end
local old = m:FindFirstChild("Copies")
if old then
Engine.dropOutput(old)
end
holder.Parent = m
holder.Archivable = true
built[m] = m:GetAttribute(ATTR)
return placed, v ~= nil
end
App.buildArray = build
local function follow()
for _, m in App.arrays() do
if built[m] ~= m:GetAttribute(ATTR) or not m:FindFirstChild("Copies") then
build(m)
end
end
end
App.track(App.ChangeHistoryService.OnUndo:Connect(function()
task.defer(follow)
end))
App.track(App.ChangeHistoryService.OnRedo:Connect(function()
task.defer(follow)
end))
App.saveArray = function(m, s, what)
local rec = beginRec("Smart Scatter: " .. (what or "Array"))
m:SetAttribute(ATTR, HttpService:JSONEncode(s))
endRec(rec)
build(m, s)
if App.refreshCounts then
App.refreshCounts()
end
end
App.previewArray = function(m, s)
local n = s.shape == "Grid" and s.rows * s.cols or s.count
if n <= LIVE_MAX then
build(m, s)
end
end
App.linkArray = function(m, name, value, what)
local rec = beginRec("Smart Scatter: " .. what)
local v = m:FindFirstChild(name)
if value and not v then
v = Instance.new("ObjectValue")
v.Name = name
v.Parent = m
end
if v then
if value then
v.Value = value
else
v.Parent = nil
end
end
endRec(rec)
build(m)
end
App.arraySource = function()
local ours = { workspace:FindFirstChild(Engine.OUT), workspace:FindFirstChild(Engine.ROADS), folder() }
for _, s in App.Selection:Get() do
if (s:IsA("Model") or s:IsA("BasePart")) and s:GetAttribute("SS_Type") == nil and variantOf(s) then
local mine = false
for _, f in ours do
mine = mine or (f ~= nil and s:IsDescendantOf(f))
end
if not mine then
return s
end
end
end
return nil
end
App.newArray = function(src, origin, s)
local v = variantOf(src)
if not v then
App.status("That model has no parts to repeat.")
return nil
end
s = Engine.arrayDefaults(s or {})
local n = 1
local f = folder()
while f and f:FindFirstChild("Array " .. n) do
n += 1
end
local rec = beginRec("Smart Scatter: New array")
f = folder(true)
local m = Instance.new("Model")
m.Name = "Array " .. n
m:SetAttribute(ATTR, HttpService:JSONEncode(s))
local link = Instance.new("ObjectValue")
link.Name = "Source"
link.Value = src
link.Parent = m
m.WorldPivot = origin
m.Parent = f
endRec(rec)
build(m, s)
App.select(App.arrayThing(m))
return m
end
App.arraySpacing = function(src)
local v = variantOf(src)
if not v then
return 8
end
return math.max(math.floor(math.max(v.m.size.X, v.m.size.Z) * 1.1 * 10 + 0.5) / 10, 0.5)
end
App.newArrayFromSelection = function()
local src = App.arraySource()
if not src then
App.status("Select a model in the Explorer first, then make an array of it.")
return
end
local cam = workspace.CurrentCamera.CFrame
local hit = Engine.cast(cam.Position, cam.LookVector * 1000, groundParams())
local at = hit and hit.Position or (cam.Position + cam.LookVector * 40)
local flat = Vector3.new(cam.LookVector.X, 0, cam.LookVector.Z)
flat = flat.Magnitude > 1e-3 and flat.Unit or Vector3.new(0, 0, -1)
App.newArray(src, CFrame.lookAt(at, at + flat), { spacing = App.arraySpacing(src) })
App.status("Array made: tune it on its Array tab.")
end
local function bake(m)
local rec = beginRec("Smart Scatter: Bake array")
m:SetAttribute(ATTR, nil)
for _, name in { "Source", "Path" } do
local v = m:FindFirstChild(name)
if v then
v.Parent = nil
end
end
endRec(rec)
App.select(nil)
App.status(m.Name .. " is plain models now.")
end
local function delete(m)
local rec = beginRec("Smart Scatter: Delete array")
m.Parent = nil
endRec(rec)
App.select(nil)
App.status("Array deleted. Ctrl+Z brings it back.")
end
App.registerKind({
kind = "Array",
icon = "grid",
title = "Array",
order = 35,
list = function()
local out = {}
for _, m in App.arrays() do
table.insert(out, App.arrayThing(m))
end
return out
end,
count = function(thing)
local c = thing.folder:FindFirstChild("Copies")
return c and #c:GetChildren() or 0
end,
thumb = function(thing)
local src = thing.folder:FindFirstChild("Source")
return src and src:IsA("ObjectValue") and src.Value or nil
end,
reorder = true,
menu = function(thing)
return {
{
"Rename",
function()
App.startRename(thing)
end,
},
{
"Bake to plain models",
function()
bake(thing.folder)
end,
P.dim,
},
"-",
{
"Delete",
function()
delete(thing.folder)
end,
P.danger,
},
}
end,
})
local slider, segmented, switchRow, button, buttonRow, hintOn = App.slider, App.segmented, App.switchRow, App.button, App.buttonRow, App.hintOn
local label, box, para = App.label, App.box, App.para
local function buildTab(page)
local m = App.selected and App.selected.folder
if not (m and isArray(m)) then
return
end
local s = read(m)
local cs = App.cards(page, "array")
local function S(parent, key, text, min, max, fmt, step, hint, def)
slider(
text,
min,
max,
function()
return s[key]
end,
function(v)
s[key] = v
end,
fmt,
step,
function()
App.previewArray(m, s)
end,
function()
App.saveArray(m, s, "Array " .. string.lower(text))
end,
hint,
def
).Parent =
parent
end
local function pick(parent, key, options, rebuild)
segmented(options, function()
return s[key]
end, function(v)
s[key] = v
end, function()
App.saveArray(m, s, "Array " .. key)
if rebuild then
App.rebuildAll()
end
end).Parent =
parent
end
cs.add({
id = "arraymodel",
title = "Model",
icon = "cube",
sub = "What's repeated",
keys = "model source swap select",
build = function(b)
local src = linked(m, "Source")
local row = box({ Size = UDim2.new(1, 0, 0, 36), Parent = b })
if src then
local th = App.thumbnail(src, 32)
th.Position = UDim2.fromOffset(0, 2)
th.Parent = row
end
label(src and src.Name or "Its model is gone: select another and press Swap.", 13, src and P.text or P.danger, App.SANS_M, {
Position = UDim2.fromOffset(40, 0),
Size = UDim2.new(1, -40, 1, 0),
Parent = row,
})
local acts = buttonRow(b)
hintOn(
button("Swap for selected", nil, function()
local pick2 = App.arraySource()
if not pick2 then
App.status("Select the model to use in the Explorer first.")
return
end
App.linkArray(m, "Source", pick2, "Array model")
App.rebuildAll()
end, { Parent = acts }),
"Repeats the model selected in the Explorer instead, in the same pattern."
)
if src then
button("Select model", nil, function()
App.Selection:Set({ src })
end, { Parent = acts })
end
end,
})
cs.add({
id = "arrayshape",
title = "Shape",
icon = "grid",
sub = "Line, grid, circle, or along a path",
keys = "line grid circle path count spacing rows columns radius face",
build = function(b)
pick(b, "shape", Engine.ARRAY_SHAPES, true)
if s.shape == "Line" then
S(b, "count", "Count", 1, 200, "%d", 1, "How many copies.", 6)
S(b, "spacing", "Spacing", 0.5, 100, "%.1f studs", 0.5, "From one copy to the next.")
elseif s.shape == "Grid" then
S(b, "rows", "Rows", 1, 40, "%d", 1, "Rows, down the array's front.", 3)
S(b, "cols", "Columns", 1, 40, "%d", 1, "Columns, to its right.", 3)
S(b, "spacingZ", "Row spacing", 0.5, 100, "%.1f studs", 0.5, "From one row to the next.")
S(b, "spacingX", "Column spacing", 0.5, 100, "%.1f studs", 0.5, "From one column to the next.")
elseif s.shape == "Circle" then
S(b, "count", "Count", 1, 200, "%d", 1, "How many copies round the circle.", 6)
S(b, "radius", "Radius", 1, 300, "%.1f studs", 0.5, "How far from the centre.", 20)
App.stepLabel(b, nil, "Facing")
pick(b, "face", Engine.ARRAY_FACES)
else
local paths = {}
for _, f in Engine.listAreas() do
if f:GetAttribute("SS_Spline") then
table.insert(paths, f)
end
end
local on = linked(m, "Path")
if #paths == 0 then
local t = para("No paths yet. Draw one (the strip's Path tool), then pick it here.", { Parent = b })
t.TextColor3 = P.dim
else
App.stepLabel(b, nil, "Along")
local grid = App.chipGrid(b, 3, 28, 96)
for _, f in paths do
App.chip(grid, f.Name, function()
return on == f
end, function()
App.linkArray(m, "Path", f, "Array path")
App.rebuildAll()
end)
end
end
App.stepLabel(b, nil, "Copies")
pick(b, "pathMode", { "Count", "Spacing" }, true)
if s.pathMode == "Spacing" then
S(b, "spacing", "Spacing", 0.5, 100, "%.1f studs", 0.5, "From one copy to the next along the path; as many as fit.")
else
S(b, "count", "Count", 1, 500, "%d", 1, "How many, spread evenly from one end to the other (round a loop).", 6)
end
end
end,
})
cs.add({
id = "arrayvary",
title = "Variation",
icon = "blend",
sub = "Turn, size and spot, copy by copy",
keys = "rotate turn spiral random jitter size scale seed",
build = function(b)
S(b, "scale", "Size", 0.1, 5, "%.2f×", 0.05, "1× is the model's own size.", 1)
S(b, "yawStep", "Turn each copy by", -180, 180, "%d°", 1, "Each copy turns this much more than the one before: spirals, fans.", 0)
S(b, "yawJitter", "Random turn", 0, 180, "±%d°", 1, "Each copy turns a random amount, up to this.", 0)
S(b, "scaleJitter", "Random size", 0, 0.9, "±%.0f%%", 0.05, "Each copy a little bigger or smaller.", 0)
S(b, "posJitter", "Random nudge", 0, 20, "±%.1f studs", 0.1, "Each copy nudged off its spot.", 0)
hintOn(
button("New random", nil, function()
s.seed += 1
App.saveArray(m, s, "Array new random")
end, { Parent = buttonRow(b) }),
"The same settings, other random turns, sizes and nudges."
)
end,
})
cs.add({
id = "arraystand",
title = "Standing",
icon = "mountain",
sub = "On the ground, or level",
keys = "ground drop snap level lift height",
build = function(b)
switchRow("Drop onto the ground", function()
return s.ground
end, function(v)
s.ground = v
end, function()
App.saveArray(m, s, "Array ground")
end, "On: each copy stands on the ground under it. Off: they all stay at the array's height, level.").Parent =
b
S(b, "lift", "Lift", -20, 50, "%.1f studs", 0.1, "Raises every copy (or sinks it, below 0).", 0)
end,
})
cs.add({
id = "arrayfinish",
title = "Finish",
icon = "wand",
sub = "Keep it as plain models, or remove it",
keys = "bake delete remove plain",
more = true,
build = function(b)
local acts = buttonRow(b)
hintOn(
button("Bake to plain models", nil, function()
bake(m)
end, { Parent = acts }),
"The copies stay where they are as plain models; the array's settings go."
)
local del = App.dangerButton("Delete array", function()
delete(m)
end, { confirm = "Click again to delete" })
del.Parent = acts
end,
})
end
App.registerTab({ id = "array", icon = "grid", title = "Array", order = 10, kinds = { Array = true }, build = buildTab })
end
end)()
-- #module App/Panel/EditTools
MODULES["App/Panel/EditTools"] = (function()
--[[
Smart Scatter — EditTools: helpers for the models selected in Studio (the Explorer or the viewport), whatever made
them: drop them onto the ground, line them up, space them evenly, give them random turns and sizes, or replace
them with another model. Each is one undo step. The Edit tab has them (it's there whatever is selected in the
outliner), and the search menu. The maths is Engine/Edit's; Replace is the map tools' swap (Engine/Kinds), so
Restore original on the World tab puts replaced models back too.
Copies an area or an array placed are left alone: its next rebuild would put them back where its rules say.
Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]
return function(App)
local Engine, G, saveG, P, beginRec, endRec = App.Engine, App.G, App.saveG, App.P, App.beginRec, App.endRec
local Selection = App.Selection
local function items()
local sel = Selection:Get()
local set = {}
for _, s in sel do
set[s] = true
end
local skip = { workspace:FindFirstChild(Engine.OUT), workspace:FindFirstChild(Engine.ROADS) }
local arrays = workspace:FindFirstChild("Arrays")
local out = {}
for _, s in sel do
if (s:IsA("Model") or s:IsA("BasePart")) and s:IsDescendantOf(workspace) and s ~= workspace.Terrain then
local ok = true
for _, f in skip do
ok = ok and not (f and s:IsDescendantOf(f))
end
if arrays and s:IsDescendantOf(arrays) then
local copies = s:FindFirstAncestor("Copies")
ok = ok and not (copies and copies:IsDescendantOf(arrays))
end
local up = s.Parent
while ok and up and up ~= workspace do
ok = not set[up]
up = up.Parent
end
if ok then
table.insert(out, s)
end
end
end
return out
end
App.editItems = items
local function boxOf(inst)
local cf, size
if inst:IsA("BasePart") then
cf, size = inst.CFrame, inst.Size
else
cf, size = inst:GetBoundingBox()
end
local h = size / 2
local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
for _, sx in { -1, 1 } do
for _, sy in { -1, 1 } do
for _, sz in { -1, 1 } do
local p = cf:PointToWorldSpace(Vector3.new(h.X * sx, h.Y * sy, h.Z * sz))
lo, hi = lo:Min(p), hi:Max(p)
end
end
end
return { min = lo, max = hi }
end
local function moveBy(inst, d)
if d.Magnitude > 1e-6 then
inst:PivotTo(inst:GetPivot() + d)
end
end
local function turnAbout(inst, at, yaw)
local r = CFrame.new(at) * CFrame.Angles(0, yaw, 0) * CFrame.new(-at)
inst:PivotTo(r * inst:GetPivot())
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
local function step(what, fn, min)
local list = items()
if #list < (min or 1) then
App.status(
min and min > 1 and string.format("Select at least %d models (in the Explorer or the viewport) first.", min)
or "Select the models to work on (in the Explorer or the viewport) first."
)
return
end
local rec = beginRec("Smart Scatter: " .. what)
local ok, said = pcall(fn, list)
endRec(rec, not ok)
if not ok then
warn("[Smart Scatter] " .. tostring(said))
App.status(what .. " didn't work: " .. tostring(said), "error")
return
end
App.status(said or string.format("%s: %d done. Ctrl+Z undoes it.", what, #list))
end
local function groundUnder(inst, b, rp)
local c = (b.min + b.max) / 2
local rx, rz = (b.max.X - b.min.X) * 0.35, (b.max.Z - b.min.Z) * 0.35
local top = b.max.Y + 4
local best, normal
local mid = Engine.cast(Vector3.new(c.X, top, c.Z), Vector3.new(0, -2000, 0), rp)
if not mid then
return nil
end
best, normal = mid.Position.Y, mid.Normal
for _, o in { Vector3.new(rx, 0, 0), Vector3.new(-rx, 0, 0), Vector3.new(0, 0, rz), Vector3.new(0, 0, -rz) } do
local h = Engine.cast(Vector3.new(c.X + o.X, top, c.Z + o.Z), Vector3.new(0, -2000, 0), rp)
if h and h.Position.Y < best and mid.Position.Y - h.Position.Y < math.max(rx, rz) * 1.5 then
best = h.Position.Y
end
end
return best, normal, Vector3.new(c.X, best, c.Z)
end
App.dropToGround = function()
step("Drop to ground", function(list)
local skip = App.templates()
for _, inst in list do
table.insert(skip, inst)
end
local rp = Engine.rayParams(skip)
local missed = 0
for _, inst in list do
local b = boxOf(inst)
local y, normal, base = groundUnder(inst, b, rp)
if y then
moveBy(inst, Vector3.new(0, y - b.min.Y, 0))
if G.editLean and normal.Y > 0.2 then
local r = CFrame.new(base) * Engine.rotateUp(normal) * CFrame.new(-base)
inst:PivotTo(r * inst:GetPivot())
end
else
missed += 1
end
end
return string.format(
"Dropped %d onto the ground%s.",
#list - missed,
missed > 0 and string.format(" (%d had no ground under them)", missed) or ""
)
end)
end
App.alignSelection = function(axis, where)
step("Align " .. axis .. " " .. string.lower(where), function(list)
local boxes = {}
for i, inst in list do
boxes[i] = boxOf(inst)
end
for i, d in Engine.alignMoves(boxes, axis, where) do
moveBy(list[i], d)
end
return string.format("Lined up %d on %s (%s).", #list, axis, string.lower(where == "Center" and "centre" or where))
end, 2)
end
App.distributeSelection = function(axis, by)
step("Distribute " .. axis, function(list)
local boxes = {}
for i, inst in list do
boxes[i] = boxOf(inst)
end
for i, d in Engine.distributeMoves(boxes, axis, by) do
moveBy(list[i], d)
end
return string.format("Spaced %d evenly on %s, the outer two staying put.", #list, axis)
end, 3)
end
local seed = 1
App.randomizeSelection = function()
seed += 1
step("Randomize", function(list)
local r = Engine.randomTurns(#list, G.editTurn, G.editSize, seed + os.clock() * 1000)
for i, inst in list do
local b = boxOf(inst)
local base = Vector3.new((b.min.X + b.max.X) / 2, b.min.Y, (b.min.Z + b.max.Z) / 2)
turnAbout(inst, base, r[i].yaw)
scaleBy(inst, r[i].scale)
if G.editKeep then
moveBy(inst, Vector3.new(0, b.min.Y - boxOf(inst).min.Y, 0))
end
end
return string.format("Gave %d a random turn and size. Press again for another.", #list)
end)
end
local replacement
App.pickReplacement = function()
local s = Selection:Get()[1]
if not (s and (s:IsA("Model") or s:IsA("BasePart"))) then
App.status("Select the model to replace with (in the Explorer), then press this.")
return
end
replacement = s
App.status(s.Name .. " is what Replace puts in. Now select the models to replace.")
if App.refreshEditTab then
App.refreshEditTab()
end
end
App.replaceSelection = function()
if not (replacement and replacement.Parent) then
App.status("Pick the model to replace with first: select it and press Use the selected.")
return
end
local made = {}
step("Replace", function(list)
for i, inst in list do
if inst ~= replacement then
for _, pair in
Engine.swapCopies({ { inst = inst, scale = 1 } }, { { inst = replacement, w = 1 } }, { match = G.editMatch, seed = i })
do
table.insert(made, pair.new)
end
end
end
return string.format("Replaced %d with %s. Restore original (World tab) or Ctrl+Z puts them back.", #made, replacement.Name)
end)
if #made > 0 then
Selection:Set(made)
end
end
local slider, segmented, switchRow, button, buttonRow, hintOn = App.slider, App.segmented, App.switchRow, App.button, App.buttonRow, App.hintOn
local para = App.para
local AXES = { "X", "Y", "Z" }
App.registerTab({
id = "edit",
icon = "align",
title = "Edit",
order = 85,
kinds = "all",
build = function(page)
local cs = App.cards(page, "edit")
cs.add({
id = "editsel",
title = "The selection",
icon = "cursor",
sub = "What these helpers work on",
keys = "selected models explorer viewport",
build = function(b)
local t = para("", { Parent = b })
local function count()
local n = #items()
t.Text = n > 0 and string.format("%d selected in Studio.", n)
or "Select models or parts in the Explorer or the viewport. (Copies an area or an array placed are left alone.)"
t.TextColor3 = n > 0 and P.text or P.dim
end
count()
local conn
conn = Selection.SelectionChanged:Connect(function()
if not t.Parent then
conn:Disconnect()
return
end
count()
end)
end,
})
cs.add({
id = "editground",
title = "Drop to the ground",
icon = "mountain",
sub = "Each one onto whatever is under it",
keys = "ground drop snap floor land settle",
build = function(b)
switchRow("Lean with the slope", function()
return G.editLean
end, function(v)
G.editLean = v
end, saveG, "On: each one tilts to stand square on the ground under it. Off: they stay upright.").Parent =
b
hintOn(
button("Drop to the ground", "accent", App.dropToGround, { Parent = buttonRow(b) }),
"Each selected model lands on what's under it; selected models don't land on each other."
)
end,
})
cs.add({
id = "editalign",
title = "Align and space",
icon = "align",
sub = "Line them up, or space them evenly",
keys = "align line up distribute space evenly gap center centre min max",
build = function(b)
segmented(AXES, function()
return G.editAxis
end, function(v)
G.editAxis = v
end, saveG).Parent = b
App.stepLabel(b, nil, "Align to the selection's")
local row = buttonRow(b)
for _, w in { { "Min", "Lowest" }, { "Center", "Middle" }, { "Max", "Highest" } } do
hintOn(
button(w[2], nil, function()
App.alignSelection(G.editAxis, w[1])
end, { Parent = row }),
"Every selected one moves on the chosen axis to the selection's " .. string.lower(w[2]) .. " edge (or middle)."
)
end
App.stepLabel(b, nil, "Space evenly by")
segmented({ "Centers", "Gaps" }, function()
return G.editBy
end, function(v)
G.editBy = v
end, saveG).Parent =
b
hintOn(
button("Distribute", nil, function()
App.distributeSelection(G.editAxis, G.editBy)
end, { Parent = buttonRow(b) }),
"The two outermost stay put; the rest spread evenly between them: the same distance centre to centre, or the same gap between neighbours."
)
end,
})
cs.add({
id = "editrandom",
title = "Randomize",
icon = "refresh",
sub = "A random turn and size for each",
keys = "random turn rotate size scale vary jitter",
build = function(b)
slider("Turn", 0, 180, function()
return G.editTurn
end, function(v)
G.editTurn = v
end, "±%d°", 5, nil, saveG, "How far each one may turn, either way.", 180).Parent =
b
slider("Size", 0, 0.9, function()
return G.editSize
end, function(v)
G.editSize = v
end, "±%.0f%%", 0.05, nil, saveG, "How much bigger or smaller each one may get.", 0.15).Parent =
b
switchRow("Keep on the ground", function()
return G.editKeep
end, function(v)
G.editKeep = v
end, saveG, "Their undersides stay where they were as they grow or shrink.").Parent =
b
hintOn(button("Randomize", nil, App.randomizeSelection, { Parent = buttonRow(b) }), "Each press, another random turn and size.")
end,
})
cs.add({
id = "editreplace",
title = "Replace",
icon = "swap",
sub = "Put another model in each one's place",
keys = "replace swap exchange model",
build = function(b)
local t = para("", { Parent = b })
local function show()
local ok = replacement and replacement.Parent
t.Text = ok and ("Replacing with " .. replacement.Name .. ".")
or "Pick the model to put in: select it, then Use the selected."
t.TextColor3 = ok and P.text or P.dim
end
show()
App.refreshEditTab = function()
if t.Parent then
show()
end
end
local row = buttonRow(b)
hintOn(button("Use the selected", nil, App.pickReplacement, { Parent = row }), "The model selected now is what Replace puts in.")
hintOn(
button("Replace the selected", "accent", App.replaceSelection, { Parent = row }),
"Each selected model makes way for the replacement: same spot, same turn, its base where the old one's was."
)
switchRow("Match each one's size", function()
return G.editMatch
end, function(v)
G.editMatch = v
end, saveG, "On: each new one is as big as the one it replaces. Off: the replacement keeps its own size.").Parent =
b
end,
})
end,
})
local function any()
return #Selection:Get() > 0
end
App.registerAction({
id = "edit:drop",
name = "Drop the selection to the ground",
group = "Edit",
icon = "mountain",
words = "ground snap land floor",
when = any,
run = App.dropToGround,
})
for _, axis in AXES do
for _, w in { { "Min", "lowest" }, { "Center", "middle" }, { "Max", "highest" } } do
App.registerAction({
id = "edit:align" .. axis .. w[1],
name = string.format("Align the selection on %s, to its %s", axis, w[2]),
group = "Edit",
icon = "align",
words = "align line up",
when = any,
run = function()
App.alignSelection(axis, w[1])
end,
})
end
App.registerAction({
id = "edit:distribute" .. axis,
name = "Space the selection evenly on " .. axis,
group = "Edit",
icon = "align",
words = "distribute spread even",
when = any,
run = function()
App.distributeSelection(axis, G.editBy)
end,
})
end
App.registerAction({
id = "edit:random",
name = "Randomize the selection's turn and size",
group = "Edit",
icon = "refresh",
words = "random rotate scale",
when = any,
run = App.randomizeSelection,
})
App.registerAction({
id = "edit:replace",
name = "Replace the selection",
group = "Edit",
icon = "swap",
words = "swap exchange model",
when = any,
run = App.replaceSelection,
})
end
end)()
-- #module App/Panel/Tabs/Objects
MODULES["App/Panel/Tabs/Objects"] = (function()
--[[
Smart Scatter — Objects tab (a zone or a path): what it places. The list (click one to open it in the Object tab),
adding models from the Explorer, how much and how big everything is; a biome, presets and the cost report under
More options, and bringing back copies taken out one by one.
Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]
return function(App)
App.registerTab({
id = "objects",
icon = "layers",
title = "Objects",
order = 10,
kinds = { Zone = true, Path = true },
build = function(page)
local a = App.area
local cs = App.cards(page, "objects")
local empty = #a.layers == 0
cs.add({
id = "objects",
title = "Objects",
icon = "layers",
sub = App.kindOf(a) == "Path" and "What lines the path, and how much of everything"
or "The models that fill this zone, and how much of everything",
keys = "add models amount size everything list lost",
build = function(b)
App.objectList(b)
App.ui.step2Card = b.Parent
end,
})
cs.add({
id = "biomes",
title = "Start from a biome",
sub = "A ready mix of objects made from your models",
keys = "forest meadow desert town sample models",
more = not empty,
build = App.buildBiomes,
})
cs.add({ id = "presets", title = "Presets", keys = "save share code import reuse", more = true, build = App.presetsBox })
cs.add({
id = "performance",
title = "Performance",
sub = "Which objects cost the most parts",
keys = "report parts meshes heavy lag simplify",
more = true,
build = App.buildReport,
})
cs.add({
id = "removecopies",
title = "Copies taken out",
icon = "close",
sub = "Single copies removed with the strip's Remove copies tool stay out",
keys = "remove delete copy copies bring back",
more = true,
build = App.removeCopiesBox,
})
end,
})
end
end)()
-- #module App/Panel/Tabs/Object
MODULES["App/Panel/Tabs/Object"] = (function()
--[[
Smart Scatter — Object tab: the active object (the one picked in the outliner or the Objects list). Its name and
actions, then its rules, a card each; what was done to it by hand is one of them. Only there while an object is
active.
Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]
return function(App)
App.registerTab({
id = "object",
icon = "tag",
title = "Object",
order = 20,
kinds = { Zone = true, Path = true },
when = function(_, active)
return active ~= nil
end,
build = function(page)
App.objectInspector(page)
end,
})
end
end)()
-- #module App/Panel/Tabs/Zone
MODULES["App/Panel/Tabs/Zone"] = (function()
--[[
Smart Scatter — Zone tab (a zone or a keep-clear zone): the ground itself. What's painted and the overlay's colours;
then, for a zone, the look of the whole zone (pattern, colour zones, edges and wind); under More options, which
surfaces painting sticks to and tidying the painted edge.
Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]
return function(App)
App.registerTab({
id = "zone",
icon = "area",
title = "Zone",
order = 30,
kinds = { Zone = true, Clear = true },
build = function(page)
local clear = App.kindOf(App.area) == "Clear"
local cs = App.cards(page, "zone")
if clear then
cs.add({
id = "clearzone",
title = "Keep-clear zone",
icon = "clear",
sub = "Nothing from any area goes here: spawns, doorways, a quest NPC's spot",
build = function(b)
App.explain(b, "Paint where nothing may go with the ground tools in the viewport's strip. Every area keeps off it.")
end,
})
end
local card = cs.add({
id = "ground",
title = "Ground",
icon = "brush",
sub = clear and "Where nothing may go" or "What's painted, and what the colours mean",
keys = "paint ground brush lasso box polygon fill erase all delete size shape reach selected parts overlay colours",
build = App.buildGround,
})
App.ui.step1Card = card
if not clear then
cs.add({
id = "pattern",
title = "Pattern",
sub = "Where everything thickens and thins together",
keys = "groves natural islands veins spots bands strength noise patches",
build = App.buildPattern,
})
cs.add({
id = "zones",
title = "Colour zones",
sub = "Tint objects by the pattern: autumn, dry, lush, frost",
keys = "color mood autumn dry lush frost tint season",
more = true,
build = App.buildZones,
})
cs.add({
id = "edges",
title = "Edges and wind",
sub = "Fade into the surroundings, and which way things lean",
keys = "soft edges border fade wind direction lean",
more = true,
build = function(b)
App.buildEdges(b)
App.buildWind(b)
end,
})
end
cs.add({
id = "paintfilter",
title = "Paint only on",
sub = "Painting and erasing stick to these surfaces",
keys = "filter surfaces grass road rock sand snow",
more = true,
build = App.buildPaintFilter,
})
cs.add({
id = "tidy",
title = "Tidy the edge",
sub = "Fill holes, smooth, grow or shrink what's painted",
keys = "fill holes smooth grow shrink cleanup",
more = true,
build = App.buildTidy,
})
end,
})
end
end)()
-- #module App/Panel/Tabs/Path
MODULES["App/Panel/Tabs/Path"] = (function()
--[[
Smart Scatter — Curve and Road tabs: a path's own settings, for a Path or a zone that has one drawn. Curve: the
path itself (length, points, Subdivide, Clear, the selected point), its strip and what it sticks to. Road: a solid
road or dirt path down the middle.
Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]
return function(App)
local function hasCurve(thing)
return thing.kind == "Path" or App.hasPath()
end
App.registerTab({
id = "curve",
icon = "spline",
title = "Curve",
order = 5,
kinds = { Path = true, Zone = true },
when = hasCurve,
build = function(page)
local cs = App.cards(page, "curve")
local card = cs.add({
id = "path",
title = "Path",
icon = "spline",
sub = "Its points, branches and loops",
keys = "draw path spline points vertex corner branch loop clear shape preset subdivide",
build = App.buildPathInfo,
})
if App.kindOf(App.area) == "Path" then
App.ui.step1Card = card
end
if App.hasPath() then
cs.add({
id = "curve",
title = "Curve",
sub = "The strip beside it, and what it sticks to",
keys = "strip width snap surfaces walls closed loop",
build = App.buildCurve,
})
end
end,
})
App.registerTab({
id = "road",
icon = "road",
title = "Road",
order = 6,
kinds = { Path = true, Zone = true },
when = function(thing)
return App.hasPath() and hasCurve(thing)
end,
build = function(page)
App.cards(page, "road").add({
id = "road",
title = "Road",
sub = "A solid road or path down the middle",
keys = "road asphalt dirt style width thickness",
build = App.buildRoad,
})
end,
})
end
end)()
-- #module App/Panel/Tabs/Stamp
MODULES["App/Panel/Tabs/Stamp"] = (function()
--[[
Smart Scatter — Stamps: the one outliner entry for everything stamped (Workspace › Stamps, plain models no area
owns), and its Stamp tab: what the stamp puts down and how (Panel/StampTools). The tool itself is the strip's.
Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]
return function(App)
App.registerKind({
kind = "Stamps",
icon = "stamp",
title = "Stamps",
order = 40,
list = function()
return { App.stampsThing() }
end,
count = function(thing)
return thing.folder and #thing.folder:GetChildren() or 0
end,
})
App.registerTab({
id = "stamp",
icon = "stamp",
title = "Stamp",
order = 10,
kinds = { Stamps = true },
build = function(page)
App.cards(page, "stamp").add({
id = "stamp",
title = "Stamp",
icon = "stamp",
sub = "One model, exactly where you click: no area needed",
keys = "stamp single one copy model place put rotate turn size anywhere",
build = App.buildStampCard,
})
end,
})
end
end)()
-- #module App/Panel/Tabs/World
MODULES["App/Panel/Tabs/World"] = (function()
--[[
Smart Scatter — World tab (always there, whatever is selected): the finished map as a whole. Scanning it for
repeated models and keeping the originals, swapping models, re-spacing a layout, seasons; and telling the scan
what a part is when it guesses wrong.
Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]
return function(App)
App.registerTab({
id = "world",
icon = "search",
title = "World",
order = 90,
kinds = "all",
build = function(page)
local cs = App.cards(page, "world")
cs.add({
id = "mapscan",
title = "Map scan",
icon = "search",
sub = "Every repeated model in a finished map, grouped by shape",
keys = "scan kinds copies find repeated models select duplicates",
build = App.buildMapScan,
})
cs.add({
id = "swap",
title = "Swap models",
sub = "Replace every copy of a kind with another model or a mix",
keys = "swap replace model mix kind copies preview try",
build = App.buildSwap,
})
cs.add({
id = "layout",
title = "Improve layout",
sub = "Re-space crowded and empty spots, by the placement rules",
keys = "layout spacing crowded empty holes gaps respace even tidy hand placed",
build = App.buildImproveLayout,
})
cs.add({
id = "seasons",
title = "Seasons",
sub = "Snowy, autumn or dry, fully or in patches",
keys = "season snow winter autumn fall dry summer colour color terrain",
build = App.buildSeasons,
})
cs.add({
id = "snapshot",
title = "Snapshot",
sub = "Keep the originals, and put them back with one click",
keys = "save keep originals restore backup revert",
build = App.buildSnapshot,
})
if App.area then
cs.add({
id = "scanfix",
title = "Fix what the scan sees",
keys = "mark road path building water rescan",
more = true,
build = App.buildScanFix,
})
end
end,
})
end
end)()
-- #module App/Panel/Tabs/Settings
MODULES["App/Panel/Tabs/Settings"] = (function()
--[[
Smart Scatter — Settings page (the ⚙ at the top): the plugin's own settings, the same in every area. Look and text
size, the viewport overlay, game-ready output and the tour; shortcuts under More options.
Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]
return function(App)
local G, saveG, P, SANS, SANS_B = App.G, App.saveG, App.P, App.SANS, App.SANS_B
local box, label, para, hlist = App.box, App.label, App.para, App.hlist
local hintOn, switchRow, button, buttonRow, commit = App.hintOn, App.switchRow, App.button, App.buttonRow, App.commit
local function buildLook(b)
local swatches = App.chipGrid(b, 5, 32, 88)
for _, a in App.ACCENTS do
App.chip(swatches, a.name, function()
return G.accent == a.name
end, function()
if G.accent ~= a.name then
G.accent = a.name
saveG()
task.defer(App.applyTheme)
end
end, Color3.fromHex(a.dark))
end
App.explain(b, "The accent the whole plugin wears: buttons, glow, the brush, painted ground and paths.")
switchRow("Colour blobs in the background", function()
return G.blobs ~= false
end, function(v)
G.blobs = v
saveG()
task.defer(App.rebuildAll)
end, nil, "Soft blobs of colour behind the panel, drifting slowly. Off: a plain background.").Parent =
b
label("Text size", 13, P.text, SANS, { Parent = b })
App.segmented({ "Small", "Normal", "Large" }, function()
return App.TEXT_SIZES[G.textScale] or "Normal"
end, function(v)
for scale, name in App.TEXT_SIZES do
if name == v then
G.textScale = scale
end
end
saveG()
task.defer(App.rebuildAll)
end).Parent =
b
end
local function buildViewport(b)
switchRow("Show overlay", function()
return G.overlay
end, function(v)
G.overlay = v
end, function()
saveG()
App.rebuildOverlay()
App.drawSpline()
end, "Shows the painted area coloured by the surface under it, and the path.").Parent =
b
switchRow(
"Focus when a tool is on",
function()
return G.focus
end,
function(v)
G.focus = v
end,
function()
saveG()
if App.refreshFocus then
App.refreshFocus()
end
end,
"While a tool is on, the world loses a little colour so the tool stands out, and the viewport's top left says what the tool is doing and on what, like Blender's."
).Parent =
b
switchRow("Brush grid", function()
return G.grid
end, function(v)
G.grid = v
end, function()
saveG()
if App.clearGrid then
App.clearGrid()
end
end, "A grid on the ground round the brush, on the area's cells: it shows what a stroke fills. Like Blender's floor grid.").Parent =
b
switchRow("History timeline", function()
return G.history
end, function(v)
G.history = v
end, function()
saveG()
task.defer(App.rebuildAll)
end, "A tick for every step Smart Scatter takes, over the bottom bar: click one to go back (or forward) to it.").Parent =
b
end
local function buildOutput(b)
local function outSwitch(text, key, hint)
switchRow(text, function()
return G[key]
end, function(v)
G[key] = v
end, function()
saveG()
commit()
end, hint).Parent =
b
end
outSwitch("Walk through plants", "walk", "Flowers and bushes get no collision, so players never snag on them.")
outSwitch("No shadows on small stuff", "shadows", "Flowers and tiny parts skip shadows. Big win on lower-end devices.")
outSwitch("Flowers ignore clicks", "query", "Flowers won't block raycasts, clicks, tools or weapons.")
outSwitch(
"Streaming chunks",
"chunks",
"Groups output into 128-stud models that stream in and out together, with low-detail stand-ins far away."
)
outSwitch(
"Big previews as boxes",
"liveBoxes",
"With Live on, a light area shows the real models as you change it; a big one shows a see-through box per copy, quick to redo, until Generate places the models. Off: Live places the real models every time."
)
box({ Size = UDim2.new(1, 0, 0, 4), Parent = b })
App.ui.perf = para("", { Parent = b })
App.refreshPerf()
end
local function buildShortcuts(b)
App.explain(
b,
"Click a key to change it, then press the new one (Esc keeps the old). Hold Ctrl, Alt or Shift with it for a combo, like Ctrl+Shift+G. A key already in use swaps over."
)
local group
for _, a in App.KEYMAP do
if a.group ~= group then
group = a.group
label(group, 12, P.dim, SANS_B, { Size = UDim2.new(1, 0, 0, 24), Parent = b })
end
local row = box({ Size = UDim2.new(1, 0, 0, 32), Parent = b })
local name = label(a.label, 13, P.text, SANS, { Size = UDim2.new(1, -96, 1, 0), Parent = row })
local key = button(App.keyText(a.id), nil, nil, {
AnchorPoint = Vector2.new(1, 0.5),
Position = UDim2.new(1, 0, 0.5, 0),
AutomaticSize = Enum.AutomaticSize.X,
Size = UDim2.fromOffset(84, 26),
Font = SANS_B,
Parent = row,
})
key:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
name.Size = UDim2.new(1, -(key.AbsoluteSize.X + 12), 1, 0)
end)
local lit = App.glow(key, 8, 0.8)
key.MouseButton1Click:Connect(function()
if App.capturingKey then
return
end
App.capturingKey = true
key.Text = "Press a key"
lit:pulse(true)
App.captureKey(key, function(k)
App.capturingKey = false
if not k then
key.Text = App.keyText(a.id)
lit:pulse(false)
return
end
local moved = App.bindKey(a.id, k)
local studio = App.STUDIO_KEYS[k]
App.status(
(
moved
and string.format("%s is now %s. %s moved to %s.", a.label, App.keyText(a.id), moved.label, App.keyText(moved.id))
or string.format("%s is now %s.", a.label, App.keyText(a.id))
) .. (studio and string.format(" Careful: in Studio %s also %s.", App.keyText(a.id), studio) or ""),
studio and "error" or nil
)
App.rebuildAll()
end)
end)
end
local fixed = label(
"Fixed: Shift erases while painting and raises a path point while dragging; Ctrl+Z undoes; a quick right-click closes a polygon; Shift + right-click on a placed copy (Select) opens its menu. A plain key still works with Shift held; with Ctrl or Alt held it's Studio's unless you bound that combo.",
12,
P.faint,
SANS,
{ Parent = b }
)
fixed.TextWrapped, fixed.AutomaticSize, fixed.Size = true, Enum.AutomaticSize.Y, UDim2.new(1, 0, 0, 0)
box({ Size = UDim2.new(1, 0, 0, 4), Parent = b })
button("Reset all shortcuts", "ghost", function()
App.resetKeys()
App.status("Shortcuts are back to their defaults.")
App.rebuildAll()
end, { Parent = buttonRow(b) })
end
local function updateWords(s, host)
if s.status == "checking" then
return "Checking for updates…"
elseif s.status == "downloading" then
return string.format("Downloading %s (%d of %d)…", tostring(s.version), (s.done or 0) + 1, s.of or 1)
elseif s.status == "current" then
local text = "Up to date."
if s.refused then
text = "Up to date, as far as GitHub's cache shows (up to five minutes behind). To look for the newest itself, "
.. "let Smart Scatter reach api.github.com (Plugins › Manage Plugins)."
elseif s.cached then
text = "Up to date. A release from the last five minutes may not show yet: Check now looks for it."
end
return text, "Check now", "check"
elseif s.status == "ready" then
return "Smart Scatter " .. tostring(s.version) .. " is ready. Updating takes a second and needs no restart.", "Update now", "apply"
elseif s.detail == "start" then
return tostring(s.version) .. " wouldn't start, so this version stays.", "Check again", "check"
elseif s.detail == "download" then
return "The update didn't download fully. It tries again by itself in a minute.", "Try now", "check"
end
return "Couldn't check for updates. Check your connection, and that Studio lets Smart Scatter reach "
.. tostring(host or "its update site")
.. " (Plugins › Manage Plugins).",
"Try again",
"check"
end
local function buildUpdates(b)
local updates = App.ctx.updates
if type(updates) ~= "table" or updates.state().status == "off" then
return
end
local words = para("", { Parent = b })
local row = buttonRow(b)
local made
local function render()
if not words.Parent then
return
end
local s = updates.state()
local text, action, call = updateWords(s, updates.host)
words.Text = text
words.TextColor3 = s.status == "failed" and P.danger or P.faint
if made then
made:Destroy()
made = nil
end
row.Visible = action ~= nil
if action then
made = button(action, s.status == "ready" and "accent" or nil, updates[call], { Parent = row })
end
end
updates.changed = render
render()
end
local function buildAbout(b)
hintOn(
button("Replay the tour", nil, function()
App.startTour()
end, { Parent = buttonRow(b) }),
"A three-minute walk through everything: what it's for, areas, paths, objects and their rules, placing and finishing."
)
local about = box({ Size = UDim2.new(1, 0, 0, 40), Parent = b }, { hlist(10) })
App.new("ImageLabel", { Image = App.LOGO.mark, BackgroundTransparency = 1, Size = UDim2.fromOffset(32, 32), Parent = about })
local words = App.col({ Size = UDim2.new(1, -42, 0, 0), Parent = about }, { App.vlist(0) })
label("Smart Scatter  " .. tostring(App.ctx.version or "dev"), 13, P.text, SANS_B, { Size = UDim2.new(1, 0, 0, 18), Parent = words })
label("made by Ghulo", 12, P.faint, SANS, { Size = UDim2.new(1, 0, 0, 16), Parent = words })
buildUpdates(b)
end
App.buildSettingsPage = function(page)
local cs = App.cards(page, "settings")
cs.add({
id = "look",
title = "Look",
sub = "Accent colour and text size",
keys = "theme accent colour color text size font blobs background",
build = buildLook,
})
cs.add({ id = "viewport", title = "Viewport", sub = "What's drawn over the 3D view", keys = "overlay", build = buildViewport })
cs.add({
id = "output",
title = "Game-ready output",
keys = "collision walk shadows clicks raycast streaming chunks live preview boxes ghost performance parts",
build = buildOutput,
})
cs.add({
id = "about",
title = "Tour and about",
sub = "A walk through everything, the version and updates",
keys = "tour help version update updates release new",
build = buildAbout,
})
cs.add({
id = "shortcuts",
title = "Shortcuts",
sub = "Every key, and changing them",
keys = "keys keyboard keybind hotkey",
more = true,
build = buildShortcuts,
})
end
end
end)()
-- #module App/Panel/Backdrop
MODULES["App/Panel/Backdrop"] = (function()
--[[
Smart Scatter — Backdrop: a few big, soft blobs of colour behind the panel (the accent and two neighbouring
shades of it, so they follow the colour theme), wandering slowly round their spots and gently changing shape.
They sit under everything, the page scrolls over them and they carry on across panel rebuilds; cards let a
little of them through. The soft round shape is drawn in code once (EditableImage), so nothing is uploaded; where
that's unavailable each blob is a few stacked see-through circles instead. Settings › Look turns them off.
Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]
return function(App)
local G, P, new = App.G, App.P, App.new
local TweenService = game:GetService("TweenService")
local BLOBS = {
{ at = Vector2.new(0.95, 0.06), size = 1.15, hue = 0, sat = 1.15, val = 1.0, drift = Vector2.new(-0.08, 0.05), secs = 17 },
{ at = Vector2.new(0.02, 0.48), size = 1.0, hue = 0.08, sat = 1.25, val = 0.95, drift = Vector2.new(0.07, -0.06), secs = 21 },
{ at = Vector2.new(0.9, 0.92), size = 1.1, hue = -0.07, sat = 1.1, val = 1.05, drift = Vector2.new(-0.06, -0.05), secs = 19 },
}
local function shadeOf(b)
local h, sa, v = P.accent:ToHSV()
return Color3.fromHSV((h + b.hue) % 1, math.clamp(sa * b.sat, 0, 1), math.clamp(v * b.val, 0, 1))
end
local SIDE = 96
local soft
local function softContent()
if soft == nil then
local ok, c = pcall(function()
local img = game:GetService("AssetService"):CreateEditableImage({ Size = Vector2.new(SIDE, SIDE) })
local buf = buffer.create(SIDE * SIDE * 4)
local mid = (SIDE - 1) / 2
for y = 0, SIDE - 1 do
for x = 0, SIDE - 1 do
local d = math.min(math.sqrt((x - mid) ^ 2 + (y - mid) ^ 2) / mid, 1)
local a = (1 - d * d) ^ 2
local i = (y * SIDE + x) * 4
buffer.writeu8(buf, i, 255)
buffer.writeu8(buf, i + 1, 255)
buffer.writeu8(buf, i + 2, 255)
buffer.writeu8(buf, i + 3, math.floor(a * 255 + 0.5))
end
end
img:WritePixelsBuffer(Vector2.zero, Vector2.new(SIDE, SIDE), buf)
return Content.fromObject(img)
end)
soft = ok and c or false
end
return soft or nil
end
local function blob(parent, color, strength)
local holder = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Active = false, Parent = parent }, {
new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Width }),
})
local c = softContent()
local img = c
and new("ImageLabel", {
BackgroundTransparency = 1,
Size = UDim2.fromScale(1, 1),
ImageColor3 = color,
ImageTransparency = 1 - strength,
Active = false,
Parent = holder,
})
if img and pcall(function()
img.ImageContent = c
end) then
return holder
elseif img then
img:Destroy()
end
for k = 1, 5 do
local s = 1 - (k - 1) * 0.18
new("Frame", {
BackgroundColor3 = color,
BackgroundTransparency = 1 - strength / 3.2,
AnchorPoint = Vector2.new(0.5, 0.5),
Position = UDim2.fromScale(0.5, 0.5),
Size = UDim2.fromScale(s, s),
Active = false,
Parent = holder,
}, { App.corner(9999) })
end
return holder
end
local rng = Random.new()
local function wander(h, b)
local shape = h:FindFirstChildOfClass("UIAspectRatioConstraint")
local reach = math.sqrt(b.drift.X ^ 2 + b.drift.Y ^ 2) * 1.5
local function go()
if not h.Parent then
return
end
local a = rng:NextNumber(0, math.pi * 2)
local r = reach * rng:NextNumber(0.35, 1)
local toX, toY = b.at.X + math.cos(a) * r, b.at.Y + math.sin(a) * r
local k = b.size * rng:NextNumber(0.92, 1.08)
local info = TweenInfo.new(b.secs * rng:NextNumber(0.25, 0.45), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local tw = TweenService:Create(h, info, {
Position = UDim2.fromScale(toX, toY),
Size = UDim2.fromScale(k, k),
Rotation = h.Rotation + rng:NextNumber(-40, 40),
})
if shape then
TweenService:Create(shape, info, { AspectRatio = rng:NextNumber(0.8, 1.25) }):Play()
end
tw.Completed:Connect(function(state)
if state == Enum.PlaybackState.Completed then
go()
end
end)
tw:Play()
end
go()
end
local layer, made
App.backdrop = function(widget)
local light = settings().Studio.Theme.Name == "Light"
local key = G.blobs ~= false and (P.accent:ToHex() .. (light and "L" or "D")) or "off"
if layer and layer.Parent == widget and made == key then
return key ~= "off"
end
if layer then
layer:Destroy()
layer = nil
end
for _, old in widget:GetChildren() do
if old.Name == "SS_Backdrop" then
old:Destroy()
end
end
made = key
if key == "off" then
return false
end
layer = new("Frame", {
BackgroundTransparency = 0,
BackgroundColor3 = P.bg,
Size = UDim2.fromScale(1, 1),
ClipsDescendants = true,
Active = false,
ZIndex = 0,
Name = "SS_Backdrop",
Parent = widget,
})
for _, b in BLOBS do
local h = blob(layer, shadeOf(b), light and 0.2 or 0.3)
h.Size = UDim2.fromScale(b.size, b.size)
h.Position = UDim2.fromScale(b.at.X, b.at.Y)
wander(h, b)
end
for _, d in layer:GetDescendants() do
if d:IsA("GuiObject") then
d.ZIndex = 0
end
if d:IsA("ImageLabel") then
local t = d.ImageTransparency
d.ImageTransparency = 1
App.tween(d, TweenInfo.new(0.8, Enum.EasingStyle.Quad), { ImageTransparency = t })
end
end
return true
end
App.blobsOn = function()
return G.blobs ~= false
end
end
end)()
-- #module App/Panel/Outliner
MODULES["App/Panel/Outliner"] = (function()
--[[
Smart Scatter — Outliner: everything Smart Scatter made in this place, a row per thing, by kind (the kinds the
features registered: zones, paths, keep-clear zones, stamps). Click one to select it; the selected zone or path
opens to its objects (each with its picture), and a click on one makes it the active object. Double-click a name
to rename it; the … at the end of a row, or a right-click on the row, has what can be done to it. Rows drag up and
down: zones, paths and arrays into any order, a zone's objects into the order they're placed in (the first takes
its room first). The whole list folds away, and scrolls past a few rows.
Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]
return function(App)
local G, saveG, P, SANS, SANS_M, SANS_B = App.G, App.saveG, App.P, App.SANS, App.SANS_M, App.SANS_B
local new, box, col, label, vlist, corner, pad = App.new, App.box, App.col, App.label, App.vlist, App.corner, App.pad
local ROW, CHILD, MAX_H = 28, 24, 190
local THUMB = 18
local renaming
App.startRename = function(thing)
renaming = thing
App.rebuildAll()
end
local function thingsOf(spec)
local things = spec.list()
if spec.reorder then
local at = {}
for i, t in things do
at[t] = i
end
table.sort(things, function(a, b)
local oa, ob = a.folder:GetAttribute("SS_Order") or math.huge, b.folder:GetAttribute("SS_Order") or math.huge
if oa ~= ob then
return oa < ob
end
return at[a] < at[b]
end)
end
return things
end
App.moveThing = function(thing, to)
local spec = App.kindSpec(thing.kind)
if not (spec and spec.reorder) then
return
end
local things = thingsOf(spec)
local from
for i, t in things do
if App.sameThing(t, thing) then
from = i
end
end
to = math.clamp(to, 1, #things)
if not from or from == to then
return
end
table.insert(things, to, table.remove(things, from))
local rec = App.beginRec("Smart Scatter: Reorder")
for i, t in things do
t.folder:SetAttribute("SS_Order", i)
end
App.endRec(rec)
App.rebuildAll()
end
local function menuOf(spec, thing, index, n)
local items = spec.menu and spec.menu(thing) or {}
if spec.reorder and n > 1 then
local at = table.find(items, "-") or #items + 1
if index < n then
table.insert(items, at, {
"Move down",
function()
App.moveThing(thing, index + 1)
end,
P.dim,
})
end
if index > 1 then
table.insert(items, at, {
"Move up",
function()
App.moveThing(thing, index - 1)
end,
P.dim,
})
end
end
return items
end
local function thingRow(list, spec, thing, order, index, n, drag)
local sel = App.sameThing(thing, App.selected)
local b = new("TextButton", {
Text = "",
AutoButtonColor = false,
BackgroundColor3 = sel and P.accentSoft or P.card,
BackgroundTransparency = sel and 0 or 1,
Size = UDim2.new(1, 0, 0, ROW),
LayoutOrder = order,
Parent = list,
}, { corner(6) })
local pictured = spec.thumb and spec.thumb(thing)
if pictured then
local th = App.thumbnail(pictured, THUMB)
th.AnchorPoint, th.Position = Vector2.new(0, 0.5), UDim2.new(0, 5, 0.5, 0)
th.Parent = b
else
local ic = App.icon(spec.icon, 13, sel and P.accent or P.dim)
ic.AnchorPoint, ic.Position = Vector2.new(0, 0.5), UDim2.new(0, 8, 0.5, 0)
ic.Parent = b
end
local name = thing.folder and thing.folder.Name or spec.title
if renaming and App.sameThing(renaming, thing) then
local tb = new("TextBox", {
Text = name,
Font = SANS_B,
TextSize = 13,
TextColor3 = P.text,
BackgroundColor3 = P.field,
ClearTextOnFocus = false,
TextXAlignment = Enum.TextXAlignment.Left,
Position = UDim2.fromOffset(28, 3),
Size = UDim2.new(1, -66, 1, -6),
Parent = b,
}, { corner(5), pad(6, 6, 0, 0) })
tb.FocusLost:Connect(function(enter)
if enter or tb.Text ~= name then
App.renameThing(thing, tb.Text)
end
renaming = nil
task.defer(App.rebuildAll)
end)
task.defer(function()
tb:CaptureFocus()
tb.SelectionStart, tb.CursorPosition = 1, #tb.Text + 1
end)
else
label(name, 13, sel and P.text or P.dim, sel and SANS_B or SANS_M, {
Position = UDim2.fromOffset(28, 0),
Size = UDim2.new(1, -110, 1, 0),
Parent = b,
})
end
local right = box({
AnchorPoint = Vector2.new(1, 0.5),
Position = UDim2.new(1, -4, 0.5, 0),
Size = UDim2.fromOffset(0, 22),
AutomaticSize = Enum.AutomaticSize.X,
Parent = b,
}, { App.hlist(4) })
local n = spec.count and spec.count(thing)
local count = label(n and n > 0 and App.num(n) or "", 11, P.faint, SANS, {
Size = UDim2.fromOffset(0, 22),
AutomaticSize = Enum.AutomaticSize.X,
LayoutOrder = 1,
Parent = right,
})
if sel then
App.ui.outlinerCount = count
end
if thing.folder and thing.folder:GetAttribute("SS_Locked") then
local lock = label("locked", 11, P.faint, SANS, {
Size = UDim2.fromOffset(0, 22),
AutomaticSize = Enum.AutomaticSize.X,
LayoutOrder = 2,
Parent = right,
})
lock.TextXAlignment = Enum.TextXAlignment.Right
end
if spec.menu then
local more = App.iconButton("down", "Rename, lock, bake, delete… (or right-click the row)", nil, false, 22)
more.LayoutOrder = 3
more.BackgroundTransparency = 1
more.Parent = right
more.MouseButton1Click:Connect(function()
App.popupMenu(more, menuOf(spec, thing, index, n))
end)
b.MouseButton2Click:Connect(function()
App.popupMenu(nil, menuOf(spec, thing, index, n))
end)
end
if drag then
drag.add(b, index)
end
if not sel then
b.MouseEnter:Connect(function()
b.BackgroundTransparency = 0
b.BackgroundColor3 = P.hover
end)
b.MouseLeave:Connect(function()
b.BackgroundTransparency = 1
end)
end
local lastClick = 0
b.MouseButton1Click:Connect(function()
if drag and drag.dragged() then
return
end
local now = os.clock()
if sel and spec.menu and now - lastClick < 0.35 and thing.folder then
App.startRename(thing)
return
end
lastClick = now
if not sel then
App.select(thing)
elseif App.active then
App.selectObject(nil)
end
end)
return b
end
local function objectRows(list, order)
local drag = App.reorderList(function(from, to)
App.moveObject(App.area.layers[from], to)
end)
for i, l in App.area.layers do
local on = l == App.active
local b = new("TextButton", {
Text = "",
AutoButtonColor = false,
BackgroundColor3 = on and P.accentSoft or P.card,
BackgroundTransparency = on and 0 or 1,
Size = UDim2.new(1, 0, 0, CHILD),
LayoutOrder = order + i,
Parent = list,
}, { corner(6) })
box({
BackgroundTransparency = 0,
BackgroundColor3 = P.line,
Position = UDim2.fromOffset(14, 0),
Size = UDim2.new(0, 1, 1, i == #App.area.layers and -CHILD / 2 or 0),
Parent = b,
})
box({
BackgroundTransparency = 0,
BackgroundColor3 = P.line,
Position = UDim2.new(0, 14, 0.5, 0),
Size = UDim2.fromOffset(10, 1),
Parent = b,
})
label(
l.inst.Name .. (#l.variants > 1 and ("  +" .. (#l.variants - 1)) or ""),
12,
on and P.accent or (l.s.enabled and P.text or P.faint),
on and SANS_B or SANS,
{
Position = UDim2.fromOffset(34 + THUMB, 0),
Size = UDim2.new(1, -(84 + THUMB), 1, 0),
Parent = b,
}
)
local th = App.thumbnail(l.inst, THUMB)
th.AnchorPoint, th.Position = Vector2.new(0, 0.5), UDim2.new(0, 28, 0.5, 0)
th.Parent = b
local what = App.Engine.isLine(l) and "along" or string.lower(l.type)
local tag = label(l.s.enabled and what or "off", 11, P.faint, SANS, {
AnchorPoint = Vector2.new(1, 0),
Position = UDim2.new(1, -8, 0, 0),
Size = UDim2.fromOffset(60, CHILD),
Parent = b,
})
tag.TextXAlignment = Enum.TextXAlignment.Right
if not on then
b.MouseEnter:Connect(function()
b.BackgroundTransparency = 0
b.BackgroundColor3 = P.hover
end)
b.MouseLeave:Connect(function()
b.BackgroundTransparency = 1
end)
end
b.MouseButton1Click:Connect(function()
if not drag.dragged() then
App.selectObject(l)
end
end)
b.MouseButton2Click:Connect(function()
App.popupMenu(nil, App.objectMenu(l))
end)
drag.add(b, i)
end
end
App.buildOutliner = function(parent)
local wrap = col({ Parent = parent }, { vlist(4) })
local head =
new("TextButton", { Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), Parent = wrap })
local chev = App.icon("right", 10, P.faint)
chev.AnchorPoint, chev.Position = Vector2.new(0, 0.5), UDim2.new(0, 2, 0.5, 0)
chev.Rotation = G.outliner and 90 or 0
chev.Parent = head
local title = label("OUTLINER", 11, P.faint, SANS_B, { Position = UDim2.fromOffset(18, 0), Size = UDim2.new(1, -18, 1, 0), Parent = head })
head.MouseEnter:Connect(function()
title.TextColor3 = P.text
end)
head.MouseLeave:Connect(function()
title.TextColor3 = P.faint
end)
head.MouseButton1Click:Connect(function()
G.outliner = not G.outliner
saveG()
App.rebuildAll()
end)
App.hintOn(head, "Everything Smart Scatter made in this place. Click one to work on it.")
App.ui.outliner = wrap
if not G.outliner then
local sel = App.selected
local spec = sel and App.kindSpec(sel.kind)
title.Text = sel and ("OUTLINER  ·  " .. string.upper(sel.folder and sel.folder.Name or (spec and spec.title or ""))) or "OUTLINER"
return wrap
end
local scroll = new("ScrollingFrame", {
BackgroundTransparency = 1,
Size = UDim2.new(1, 0, 0, 0),
CanvasSize = UDim2.new(),
AutomaticCanvasSize = Enum.AutomaticSize.Y,
ScrollBarThickness = 3,
ScrollBarImageColor3 = P.faint,
ScrollingDirection = Enum.ScrollingDirection.Y,
VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
Parent = wrap,
})
local list = col({ Parent = scroll }, { vlist(1) })
local order, any, selRow = 0, false, nil
for _, spec in App.thingKinds() do
local things = thingsOf(spec)
local drag = spec.reorder and App.reorderList(function(from, to)
App.moveThing(things[from], to)
end) or nil
for index, thing in things do
order += 100
any = true
local row = thingRow(list, spec, thing, order, index, #things, drag)
if App.sameThing(thing, App.selected) then
selRow = row
if App.area and (thing.kind == "Zone" or thing.kind == "Path") and #App.area.layers > 0 then
objectRows(list, order)
end
end
end
end
if not any then
local t = App.para("Nothing yet. + makes a zone, a path or a keep-clear zone.", { Parent = list })
t.TextColor3 = P.faint
end
local function fit()
local h = list.AbsoluteSize.Y
scroll.Size = UDim2.new(1, 0, 0, math.min(h, MAX_H))
end
list:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
fit()
if selRow then
task.defer(function()
if selRow.Parent then
local top = selRow.AbsolutePosition.Y - list.AbsolutePosition.Y
if top + ROW > MAX_H then
scroll.CanvasPosition = Vector2.new(0, top - MAX_H / 2)
end
end
end)
end
return wrap
end
end
end)()
-- #module App/Panel/Properties
MODULES["App/Panel/Properties"] = (function()
--[[
Smart Scatter — Properties: the tabs for what's selected (Core/Selection), from the tabs the features registered
(Core/Registry), and the page of the open one. Like Blender's properties editor: pick a thing and its settings are
here; pick one of its objects and its Object tab opens.
Which tab is open: the one picked, while the selection keeps it; else the last one used for that kind of thing;
else the one for its next step (an unpainted zone: Zone; an undrawn path: Curve; else Objects).
Also the search results (every matching card of the selection's tabs and of Settings) and, with no areas at all,
the welcome.
Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]
return function(App)
local G, saveG, P, SANS_B, SANS_M = App.G, App.saveG, App.P, App.SANS_B, App.SANS_M
local new, box, col, label, vlist, hlist = App.new, App.box, App.col, App.label, App.vlist, App.hlist
local Engine = App.Engine
App.propTab = nil
local shownFor, lastActive
local function homeTab(thing)
if not thing then
return "world"
end
if thing.kind == "Stamps" then
return "stamp"
end
local a = App.area
if thing.kind == "Clear" then
return "zone"
end
if thing.kind == "Path" then
return App.hasPath() and "objects" or "curve"
end
return (a and (a.count or 0) == 0 and not App.hasPath()) and "zone" or "objects"
end
App.currentTab = function()
local tabs = App.tabsFor(App.selected, App.active)
local want = App.propTab or (App.selected and G.tabs[App.selected.kind]) or homeTab(App.selected)
for _, t in tabs do
if t.id == want then
return t, tabs
end
end
local home = homeTab(App.selected)
for _, t in tabs do
if t.id == home then
return t, tabs
end
end
return tabs[1], tabs
end
App.openTab = function(id)
App.settingsOpen = false
if App.searching() and App.clearSearch then
App.clearSearch()
end
App.propTab = id
if App.selected then
G.tabs[App.selected.kind] = id
saveG()
end
App.rebuildAll()
end
App.onSelect(function(thing, active)
if not App.sameThing(thing, shownFor) then
shownFor = thing
App.propTab = nil
end
if active and active ~= lastActive then
App.propTab = "object"
elseif not active and App.propTab == "object" then
App.propTab = "objects"
end
lastActive = active
end)
App.buildTabRow = function(parent)
local open, tabs = App.currentTab()
local strip = box({ Size = UDim2.new(1, 0, 0, 34), Parent = parent })
App.ui.tabRow = strip
local bar = box({ Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = strip }, {
new("UIGridLayout", {
CellSize = UDim2.new(1 / math.max(#tabs, 1), 0, 1, 0),
CellPadding = UDim2.fromOffset(0, 0),
SortOrder = Enum.SortOrder.LayoutOrder,
}),
})
box({
BackgroundTransparency = 0,
BackgroundColor3 = P.line,
AnchorPoint = Vector2.new(0, 1),
Position = UDim2.new(0, 0, 1, 0),
Size = UDim2.new(1, 0, 0, 1),
Parent = strip,
})
App.ui.tabs = {}
local fits = {}
for i, t in tabs do
local on = t == open and not App.searching()
local b = new("TextButton", { Text = "", AutoButtonColor = false, BackgroundTransparency = 1, LayoutOrder = i, Parent = bar })
if on then
box({
BackgroundTransparency = 0,
BackgroundColor3 = P.accent,
AnchorPoint = Vector2.new(0.5, 1),
Position = UDim2.fromScale(0.5, 1),
Size = UDim2.new(1, -12, 0, 2),
ZIndex = 3,
Parent = b,
}, { App.corner(1) })
end
local row = box({ Size = UDim2.fromScale(1, 1), Parent = b }, {
new("UIListLayout", {
FillDirection = Enum.FillDirection.Horizontal,
HorizontalAlignment = Enum.HorizontalAlignment.Center,
VerticalAlignment = Enum.VerticalAlignment.Center,
Padding = UDim.new(0, 5),
}),
})
local fg = on and P.text or P.dim
local ic = App.icon(t.icon, 13, on and P.accent or fg)
ic.Parent = row
local text = label(t.title, 12, fg, on and SANS_B or SANS_M, {
Size = UDim2.fromOffset(0, 16),
AutomaticSize = Enum.AutomaticSize.X,
Parent = row,
})
fits[text] = ic
if not on then
b.MouseEnter:Connect(function()
text.TextColor3 = P.text
App.setIconColor(ic, P.text)
end)
b.MouseLeave:Connect(function()
text.TextColor3 = P.dim
App.setIconColor(ic, P.dim)
end)
end
b.MouseButton1Click:Connect(function()
App.openTab(t.id)
end)
App.hintOn(b, t.title)
App.ui.tabs[t.id] = b
end
local function fit()
local cell = bar.AbsoluteSize.X / math.max(#tabs, 1)
local both, names = true, true
for text, ic in fits do
both = both and cell >= text.TextBounds.X + ic.AbsoluteSize.X + 5 + 10
names = names and cell >= text.TextBounds.X + 8
end
for text, ic in fits do
text.Visible = both or names
ic.Visible = both or not names
end
end
bar:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
task.defer(fit)
return strip
end
App.buildProperties = function(page)
if App.searching() then
App.buildSearchResults(page)
return
end
if not App.selected and #Engine.listAreas() == 0 then
App.buildWelcome(page)
return
end
local open = App.currentTab()
if open then
open.build(page)
end
end
App.buildSearchResults = function(page)
local any = false
local function section(title, onOpen, build)
local holder = col({ Parent = page }, { vlist(10) })
local head = new("TextButton", {
Text = "",
AutoButtonColor = false,
BackgroundTransparency = 1,
Size = UDim2.new(1, 0, 0, 20),
Parent = holder,
}, { hlist(4) })
local name = label(
string.upper(title),
11,
P.faint,
SANS_B,
{ Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, Parent = head }
)
local go = App.icon("right", 10, P.faint)
go.Parent = head
head.MouseEnter:Connect(function()
name.TextColor3 = P.accent
App.setIconColor(go, P.accent)
end)
head.MouseLeave:Connect(function()
name.TextColor3 = P.faint
App.setIconColor(go, P.faint)
end)
head.MouseButton1Click:Connect(onOpen)
local before = App.cardCount
build(holder)
if App.cardCount == before then
holder:Destroy()
else
any = true
end
end
for _, t in App.tabsFor(App.selected, App.active) do
section(t.title, function()
App.openTab(t.id)
end, t.build)
end
section("Settings", function()
App.openSettings(true)
end, App.buildSettingsPage)
if not any then
App.emptyState(page, "Nothing found", "Try another word, like road, colour, spacing or shortcut.")
end
end
end
end)()
-- #module App/Panel/Shell
MODULES["App/Panel/Shell"] = (function()
--[[
Smart Scatter — Shell: the panel's frame. At the top the name with + New and Settings, the search box, the
outliner (Panel/Outliner) and the selection's tabs (Panel/Properties); under them the page that scrolls; the bar
pinned to the bottom (Generate, Live update, Shuffle, Undo, the history) and toasts; and the whole-panel rebuild,
which follows the selection.
Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]
return function(App)
local FAST, MED, tween, beginRec, endRec, track = App.FAST, App.MED, App.tween, App.beginRec, App.endRec, App.track
local G, saveG, num, P, makePalette, SANS, SANS_B = App.G, App.saveG, App.num, App.P, App.makePalette, App.SANS, App.SANS_B
local new, corner, pad, vlist, hlist, box, col, label = App.new, App.corner, App.pad, App.vlist, App.hlist, App.box, App.col, App.label
local para, hintOn, rebuildOverlay, saveArea, canGenerate = App.para, App.hintOn, App.rebuildOverlay, App.saveArea, App.canGenerate
local runGenerate, commit = App.runGenerate, App.commit
App.perfNote = function()
if App.area and App.area.folder.Parent and App.Engine.isPreview(App.area) then
return "Some are still a preview (boxes): press Generate to place the real models.", false
end
local heavy = App.lastParts > 20000
return heavy and "That's heavy. Lower the amount or use simpler models." or App.lastParts > 8000 and "Getting heavy for phones." or "", heavy
end
App.refreshPerf = function()
if not App.ui.perf then
return
end
local note, heavy = App.perfNote()
App.ui.perf.Text = string.format("This area: %s objects, %s parts.  %s", num(App.lastTotal), num(App.lastParts), note)
App.ui.perf.TextColor3 = heavy and P.danger or P.dim
end
App.shuffle = function()
if not App.area then
return
end
local rec = beginRec("Smart Scatter: Shuffle")
App.area.seed = math.random(1, 999999)
saveArea()
endRec(rec)
runGenerate(true)
end
App.generateNow = function()
if App.busy() then
App.cancelJob()
App.status("Stopped. Nothing was changed.")
return
end
local ok, why = canGenerate()
if not ok then
App.status(why or "Nothing to generate yet.")
return
end
if App.worldChanged() then
App.analysisDirty = true
end
runGenerate(true, nil, nil, true)
end
App.toggleLive = function()
G.live = not G.live
saveG()
if App.ui.liveLook then
App.ui.liveLook()
end
if G.live then
commit()
end
App.status(
G.live
and (G.liveBoxes and "Live on: changes show as you make them (a big area as see-through boxes until Generate)." or "Live update on: every change rebuilds as you make it.")
or "Live off: changes wait for Generate."
)
end
App.undoStep = function(redo)
local chs = App.ChangeHistoryService
local ok, can = pcall(redo and chs.GetCanRedo or chs.GetCanUndo, chs)
if ok and can == false then
App.status(redo and "Nothing to redo." or "Nothing to undo.")
return
end
pcall(redo and chs.Redo or chs.Undo, chs)
end
local buildTimeline
local STRIP_H = 22
local function barH()
return 60 + (G.history and STRIP_H or 0)
end
local SHOWN_STEPS = 60
local function ago(t)
local d = os.time() - t
return d < 60 and "just now" or d < 3600 and (math.floor(d / 60) .. " min ago") or (math.floor(d / 3600) .. " h ago")
end
function buildTimeline(foot)
local strip = box({ Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, STRIP_H - 6), Parent = foot })
App.ui.history = strip
local function draw()
strip:ClearAllChildren()
local H = App.history
local n = #H.list
if n == 0 then
label("History · your steps show up here", 11, P.faint, SANS, { Size = UDim2.fromScale(1, 1), Parent = strip })
return
end
local first = math.max(0, n - SHOWN_STEPS)
local count = n - first + 1
box({
BackgroundTransparency = 0,
BackgroundColor3 = P.line,
AnchorPoint = Vector2.new(0, 1),
Position = UDim2.fromScale(0, 1),
Size = UDim2.new(1, 0, 0, 1),
Parent = strip,
})
for i = first, n do
local x = count > 1 and (i - first) / (count - 1) or 0
local here, done = i == H.pos, i < H.pos
local hit = new("TextButton", {
Text = "",
AutoButtonColor = false,
BackgroundTransparency = 1,
AnchorPoint = Vector2.new(0.5, 0),
Position = UDim2.new(x, 0, 0, 0),
Size = UDim2.new(0, 10, 1, 0),
Parent = strip,
})
local line = box({
BackgroundTransparency = 0,
BackgroundColor3 = here and P.accent or done and P.dim or P.line,
AnchorPoint = Vector2.new(0.5, 1),
Position = UDim2.new(0.5, 0, 1, 0),
Size = UDim2.fromOffset(here and 3 or 2, here and 16 or (i == 0 and 6 or 10)),
Parent = hit,
}, { corner(1) })
hit.MouseEnter:Connect(function()
if not here then
line.BackgroundColor3 = P.text
end
end)
hit.MouseLeave:Connect(function()
line.BackgroundColor3 = here and P.accent or done and P.dim or P.line
end)
hintOn(hit, function()
local what = i == 0 and "Before your first step" or string.gsub(H.list[i].name, "^Smart Scatter: ", "")
local when = i > 0 and ("  ·  " .. ago(H.list[i].time)) or ""
return what .. when .. (here and "  ·  you're here" or "  ·  click to go here (Studio edits in between go with it)")
end)
hit.MouseButton1Click:Connect(function()
if i ~= App.history.pos then
local from = App.history.pos
App.historyJump(i)
App.status(
i < from and string.format("Went back %d step%s.", from - i, from - i == 1 and "" or "s")
or string.format("Went forward %d step%s.", i - from, i - from == 1 and "" or "s")
)
end
end)
end
end
draw()
App.onHistoryChanged = function()
if App.ui.history == strip and strip.Parent then
draw()
end
end
end
local function buildBar(parent)
local foot = box({
BackgroundTransparency = 0,
BackgroundColor3 = P.header,
AnchorPoint = Vector2.new(0, 1),
Position = UDim2.fromScale(0, 1),
Size = UDim2.new(1, 0, 0, barH()),
ZIndex = 3,
Parent = parent,
})
App.ui.foot = foot
App.glass(foot)
App.fadeLine(foot, nil, 0.16)
local line = box({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 2), ZIndex = 4, Parent = foot })
App.ui.progress = box({
BackgroundTransparency = 0,
BackgroundColor3 = P.accent,
Size = UDim2.fromScale(0, 1),
Visible = false,
ZIndex = 4,
Parent = line,
})
App.ui.progressSweep = App.sweep(App.ui.progress, 0.6)
App.sheen(foot, 0.025, 40)
if G.history then
buildTimeline(foot)
end
local inner = box({ Position = UDim2.fromOffset(12, 11 + (G.history and STRIP_H or 0)), Size = UDim2.new(1, -24, 0, 38), Parent = foot })
local right = box({
AnchorPoint = Vector2.new(1, 0),
Position = UDim2.fromScale(1, 0),
Size = UDim2.fromOffset(0, 38),
AutomaticSize = Enum.AutomaticSize.X,
Parent = inner,
}, { hlist(6) })
App.ui.genBtn = new("TextButton", {
Text = "Generate",
Font = SANS_B,
TextSize = 14,
TextColor3 = P.onAccent,
BackgroundColor3 = P.accent,
AutoButtonColor = false,
Size = UDim2.new(1, -162, 1, 0),
TextTruncate = Enum.TextTruncate.AtEnd,
Parent = inner,
}, { corner(10), pad(8, 8, 0, 0) })
App.shade(App.ui.genBtn, 0.12)
App.topLight(App.ui.genBtn, 0.35, 8)
App.ui.genSweep = App.sweep(App.ui.genBtn, 0.3)
local press = new("UIScale", { Parent = App.ui.genBtn })
App.ui.genBar = box({
BackgroundTransparency = 0.82,
BackgroundColor3 = Color3.new(1, 1, 1),
Size = UDim2.fromScale(0, 1),
Visible = false,
Parent = App.ui.genBtn,
}, { corner(10) })
App.ui.genBtn.MouseEnter:Connect(function()
if canGenerate() then
tween(App.ui.genBtn, FAST, { BackgroundColor3 = (App.failure and P.danger or P.accent):Lerp(Color3.new(1, 1, 1), 0.1) })
end
end)
App.ui.genBtn.MouseLeave:Connect(function()
tween(press, FAST, { Scale = 1 })
App.refreshCounts()
end)
App.ui.genBtn.MouseButton1Down:Connect(function()
if canGenerate() then
tween(press, FAST, { Scale = 0.98 })
end
end)
App.ui.genBtn.MouseButton1Up:Connect(function()
tween(press, MED, { Scale = 1 })
end)
App.ui.genBtn.MouseButton1Click:Connect(App.generateNow)
hintOn(App.ui.genBtn, function()
if App.busy() then
return "Click to stop. Nothing changes until it's done."
end
local ok, why = canGenerate()
if not ok then
return (why or "Nothing to generate yet.") .. " Then this places everything."
end
if App.failure then
return "The last Generate failed: " .. tostring(App.failure) .. ". Click to try again."
end
if App.hasPending() then
return "You've changed settings, ground or the path since the last Generate. Click to place them."
end
return "Places the real models now. With Live on, a big area's changes show as see-through boxes first; this turns them into the models."
end)
local live = new("TextButton", {
Text = "",
AutoButtonColor = false,
Size = UDim2.fromOffset(66, 38),
LayoutOrder = 1,
Parent = right,
}, { corner(10) })
local liveStroke = App.stroke(P.line)
liveStroke.Parent = live
local dot = box({
BackgroundTransparency = 0,
AnchorPoint = Vector2.new(0, 0.5),
Position = UDim2.new(0, 12, 0.5, 0),
Size = UDim2.fromOffset(8, 8),
Parent = live,
}, { corner(4) })
local liveText = label("Live", 13, P.dim, App.SANS_M, { Position = UDim2.fromOffset(28, 0), Size = UDim2.new(1, -30, 1, 0), Parent = live })
App.ui.liveGlow = App.glow(live, 10, 0.6)
App.pressable(live, 0.95)
local function liveLook()
live.BackgroundColor3 = G.live and P.accentSoft or P.raised
liveStroke.Color = G.live and P.accentLine or P.line
dot.BackgroundColor3 = G.live and P.accent or P.faint
liveText.TextColor3 = G.live and P.accent or P.dim
end
liveLook()
App.ui.liveLook = liveLook
live.MouseButton1Click:Connect(App.toggleLive)
hintOn(
live,
"On: every change shows right away (a big area as see-through boxes until Generate). Off: changes wait for Generate; brushing one object and its buttons always show at once."
)
local shuffle = App.iconButton("refresh", "Shuffle: a new random layout with the same settings. Ctrl+Z goes back.", App.shuffle, false, 38)
shuffle.LayoutOrder = 2
shuffle.Parent = right
local undo = App.iconButton("undo", "Undo the last step (Ctrl+Z)", function()
App.undoStep()
end, false, 38)
undo.LayoutOrder = 3
undo.Parent = right
end
local running = false
App.showProgress = function(phase, progress)
local bar, btn = App.ui.progress, App.ui.genBtn
local on = phase ~= nil
if on ~= running then
running = on
if bar then
bar.Visible = on
App.ui.progressSweep:play(on)
end
if App.ui.liveGlow then
App.ui.liveGlow:pulse(on)
end
if App.ui.genSweep then
App.ui.genSweep:play(on)
end
if btn and App.ui.genBar then
App.ui.genBar.Visible = on
end
end
if not on then
App.refreshCounts()
return
end
local p = math.clamp(progress or 0, 0.02, 1)
if bar then
bar.Size = UDim2.fromScale(p, 1)
end
if btn and App.ui.genBar then
App.ui.genBar.Size = UDim2.fromScale(p, 1)
btn.Text = string.format("%s…  %d%%   ·   click to stop", phase, math.floor(p * 100 + 0.5))
btn.Font = SANS_B
btn.BackgroundColor3 = P.accent
btn.TextColor3 = P.onAccent
end
end
local flashToken = 0
App.flashDone = function(text)
local btn = App.ui.genBtn
if not btn then
return
end
flashToken += 1
local my = flashToken
btn.Text = text
task.delay(1.5, function()
if my == flashToken and not App.busy() then
App.refreshCounts()
end
end)
end
local toastToken = 0
local function hideToast(t, speed)
toastToken += 1
local my = toastToken
tween(t.group, speed or MED, { GroupTransparency = 1 })
task.delay(0.3, function()
if my == toastToken then
t.group.Visible = false
end
end)
end
App.status = function(msg, tone)
local t = App.ui.toast
if not t then
return
end
if msg == "" then
hideToast(t, FAST)
return
end
toastToken += 1
local my = toastToken
t.group.Visible = true
local err = tone == "error"
t.text.Text = msg
t.dot.BackgroundColor3 = err and P.danger or P.accent
t.glow:set(err)
if t.group.GroupTransparency > 0.5 then
t.group.Position = UDim2.new(0.5, 0, 1, -barH() - 2)
tween(t.group, MED, { GroupTransparency = 0, Position = UDim2.new(0.5, 0, 1, -barH() - 10) })
end
task.delay(err and 6 + #msg * 0.02 or math.min(2.2 + #msg * 0.012, 5), function()
if my == toastToken and App.ui.toast == t then
hideToast(t)
end
end)
end
local hinted = {}
App.hint = function(key, msg)
hinted[key] = (hinted[key] or 0) + 1
if hinted[key] <= 2 then
App.status(msg)
end
end
local function buildToast(parent)
local group = new("CanvasGroup", {
BackgroundTransparency = 1,
GroupTransparency = 1,
AnchorPoint = Vector2.new(0.5, 1),
Position = UDim2.new(0.5, 0, 1, -barH() - 10),
Size = UDim2.new(1, -24, 0, 0),
AutomaticSize = Enum.AutomaticSize.Y,
ZIndex = 60,
Parent = parent,
})
local pill = col({
BackgroundTransparency = 0.04,
BackgroundColor3 = P.card,
AnchorPoint = Vector2.new(0.5, 0),
Position = UDim2.fromScale(0.5, 0),
Size = UDim2.new(1, -8, 0, 0),
ZIndex = 60,
Parent = group,
}, { corner(12), App.stroke(P.line), pad(34, 14, 9, 9) })
App.shade(pill, 0.06)
App.topLight(pill, 0.1, 12)
local dot = box({
BackgroundTransparency = 0,
BackgroundColor3 = P.accent,
AnchorPoint = Vector2.new(0, 0.5),
Position = UDim2.new(0, -20, 0.5, 0),
Size = UDim2.fromOffset(8, 8),
ZIndex = 61,
Parent = pill,
}, { corner(4) })
local text = para("", { ZIndex = 61, Parent = pill })
text.TextColor3 = P.text
local t = { group = group, text = text, dot = dot, glow = App.glow(pill, 12, 0.6, P.danger) }
new("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 62, Parent = group }).MouseButton1Click:Connect(
function()
hideToast(t, FAST)
end
)
group.Visible = false
App.ui.toast = t
end
local searchText = ""
local function clearSearch()
searchText = ""
App.setSearch("")
end
App.clearSearch = clearSearch
App.settingsOpen = false
App.openSettings = function(on)
App.settingsOpen = on
clearSearch()
App.rebuildAll()
end
local function buildTitle(parent)
local row = box({ Size = UDim2.new(1, 0, 0, 30), Parent = parent })
if App.settingsOpen then
App.pageHead(row, "Settings", nil, function()
App.openSettings(false)
end)
else
new("ImageLabel", {
Image = App.LOGO.mark,
BackgroundTransparency = 1,
AnchorPoint = Vector2.new(0, 0.5),
Position = UDim2.new(0, 0, 0.5, 0),
Size = UDim2.fromOffset(20, 20),
Parent = row,
})
label("Smart Scatter", 14, P.text, SANS_B, { Position = UDim2.fromOffset(28, 0), Size = UDim2.new(1, -110, 1, 0), Parent = row })
end
local right = box({
AnchorPoint = Vector2.new(1, 0),
Position = UDim2.fromScale(1, 0),
Size = UDim2.fromOffset(0, 30),
AutomaticSize = Enum.AutomaticSize.X,
Parent = row,
}, { hlist(6) })
if not App.settingsOpen then
local plus = App.iconButton("plus", "New: a zone, a path or a keep-clear zone", function(b)
App.openNewMenu(b)
end, false, 30)
plus.LayoutOrder = 1
plus.Parent = right
App.ui.plusBtn = plus
end
local gear = App.iconButton("settings", App.settingsOpen and "Back to your things" or "Settings", function()
App.openSettings(not App.settingsOpen)
end, App.settingsOpen, 30)
gear.LayoutOrder = 2
gear.Parent = right
App.ui.gearBtn = gear
end
local buildPage, enterCards
local function buildSearch(parent)
local row = box({ BackgroundTransparency = 0, BackgroundColor3 = P.field, Size = UDim2.new(1, 0, 0, 32), Parent = parent }, { corner(9) })
local st = App.stroke(P.line)
st.Parent = row
App.glass(row)
local ic = App.icon("search", 13, P.faint)
ic.AnchorPoint, ic.Position = Vector2.new(0, 0.5), UDim2.new(0, 11, 0.5, 0)
ic.Parent = row
local tb = new("TextBox", {
Text = searchText,
PlaceholderText = "Search settings  ·  " .. App.keyText("palette") .. " for any action",
Font = SANS,
TextSize = 13,
TextColor3 = P.text,
PlaceholderColor3 = P.faint,
BackgroundTransparency = 1,
ClearTextOnFocus = false,
TextXAlignment = Enum.TextXAlignment.Left,
Position = UDim2.fromOffset(30, 0),
Size = UDim2.new(1, -62, 1, 0),
Parent = row,
})
App.ui.search = tb
local x = App.iconButton("close", "Clear the search", function()
tb.Text = ""
end, false, 24)
x.AnchorPoint, x.Position = Vector2.new(1, 0.5), UDim2.new(1, -4, 0.5, 0)
x.Visible = searchText ~= ""
x.Parent = row
tb.Focused:Connect(function()
st.Color = P.accentLine
end)
tb.FocusLost:Connect(function()
st.Color = App.blobsOn() and Color3.new(1, 1, 1) or P.line
end)
local token = 0
tb:GetPropertyChangedSignal("Text"):Connect(function()
if tb.Text == searchText then
return
end
searchText = tb.Text
x.Visible = searchText ~= ""
token += 1
local my = token
task.delay(0.2, function()
if my ~= token or App.ui.search ~= tb then
return
end
App.setSearch(searchText)
buildPage()
end)
end)
end
local SHELL = {
"plusBtn",
"gearBtn",
"outliner",
"outlinerCount",
"tabs",
"tabRow",
"search",
"foot",
"progress",
"progressSweep",
"genBtn",
"genSweep",
"genBar",
"liveGlow",
"history",
"toast",
"popup",
}
function buildPage()
local sc = App.scroll
if not sc then
return
end
local keep = {}
for _, k in SHELL do
keep[k] = App.ui[k]
end
App.ui = keep
App.hideTip()
App.pruneThumbs(false, sc)
for _, ch in sc:GetChildren() do
if ch:IsA("GuiObject") then
ch:Destroy()
end
end
App.ui.builtShape = App.shapeKey()
local page = col({ Parent = sc }, { vlist(10) })
if App.settingsOpen and not App.searching() then
App.buildSettingsPage(page)
else
App.buildProperties(page)
end
App.refreshScan()
App.refreshObjects()
end
App.scrollIntoView = function(obj)
task.defer(function()
task.defer(function()
local sc = App.scroll
if not (sc and obj.Parent and obj:IsDescendantOf(sc)) then
return
end
local top = obj.AbsolutePosition.Y - sc.AbsolutePosition.Y + sc.CanvasPosition.Y
tween(sc, MED, { CanvasPosition = Vector2.new(0, math.max(top - 10, 0)) })
end)
end)
end
local ENTER = TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
function enterCards()
local k = 0
for _, c in App.scroll:GetDescendants() do
if k >= 8 then
break
end
if c:IsA("GuiObject") and c:GetAttribute("SS_Card") then
local sc = new("UIScale", { Scale = 0.97, Parent = c })
local rest = c.BackgroundTransparency
c.BackgroundTransparency = 1
task.delay(k * 0.045, function()
if c.Parent then
tween(sc, ENTER, { Scale = 1 })
tween(c, MED, { BackgroundTransparency = rest })
end
end)
k += 1
end
end
end
local builtPage
local firstBuild = true
local function pageKey()
if App.settingsOpen then
return "settings"
end
local t = App.currentTab()
local sel = App.selected
local what = "none"
if sel then
what = sel.kind .. ":" .. (sel.folder and sel.folder:GetFullName() or "")
end
return what .. "|" .. (t and t.id or "")
end
App.rebuildAll = function()
local key = pageKey()
local keepScroll = builtPage == key and App.scroll and App.scroll.Parent and App.scroll.CanvasPosition
local turned = builtPage ~= nil and builtPage ~= key
builtPage = key
if App.root then
App.pruneThumbs()
App.root:Destroy()
end
App.ui = {}
local blobs = App.backdrop(App.widget)
App.root = box({
Size = UDim2.fromScale(1, 1),
BackgroundTransparency = blobs and 1 or 0,
BackgroundColor3 = P.bg,
ZIndex = 1,
Parent = App.widget,
})
App.root.InputBegan:Connect(function(input)
if App.panelKey then
App.panelKey(input)
end
end)
App.root.InputEnded:Connect(function(input)
if input.UserInputType == Enum.UserInputType.MouseButton1 and App.releaseMouse then
App.releaseMouse()
end
end)
local head = col({
BackgroundTransparency = App.blobsOn() and 1 or 0,
BackgroundColor3 = P.bg,
ZIndex = 2,
Parent = App.root,
}, { pad(14, 14, 12, 8), vlist(0) })
App.scroll = new("ScrollingFrame", {
Size = UDim2.new(1, 0, 1, -barH()),
CanvasSize = UDim2.new(),
BackgroundTransparency = 1,
AutomaticCanvasSize = Enum.AutomaticSize.Y,
ScrollBarThickness = 4,
ScrollBarImageColor3 = P.faint,
ScrollBarImageTransparency = 0.5,
VerticalScrollBarInset = Enum.ScrollBarInset.Always,
ScrollingDirection = Enum.ScrollingDirection.Y,
Parent = App.root,
}, { pad(14, 12, 10, 24), vlist(2) })
local scrollPad = App.scroll:FindFirstChildOfClass("UIPadding")
App.scroll.MouseEnter:Connect(function()
tween(App.scroll, FAST, { ScrollBarImageTransparency = 0.15 })
end)
App.scroll.MouseLeave:Connect(function()
tween(App.scroll, FAST, { ScrollBarImageTransparency = 0.5 })
end)
buildTitle(head)
box({ Size = UDim2.new(1, 0, 0, 8), Parent = head })
buildSearch(head)
if not App.settingsOpen then
box({ Size = UDim2.new(1, 0, 0, 8), Parent = head })
App.buildOutliner(head)
if App.toolbarAvailable and not App.toolbarAvailable() then
box({ Size = UDim2.new(1, 0, 0, 6), Parent = head })
App.buildToolRow(head)
end
box({ Size = UDim2.new(1, 0, 0, 4), Parent = head })
App.buildTabRow(head)
end
box({ Size = UDim2.new(1, 0, 0, 6), Parent = head })
App.sheen(App.root, 0.04, 140, 150)
App.halftone(App.root, 0.07, 4, 150)
local function fit()
local h = head.AbsoluteSize.Y
App.scroll.Position = UDim2.fromOffset(0, h)
App.scroll.Size = UDim2.new(1, 0, 1, -h - barH())
end
head:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
fit()
buildBar(App.root)
buildToast(App.root)
buildPage()
if turned then
scrollPad.PaddingLeft, scrollPad.PaddingRight = UDim.new(0, 38), UDim.new(0, -12)
tween(scrollPad, MED, { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 12) })
end
if turned or firstBuild then
enterCards()
end
firstBuild = false
if App.tour and App.renderTour then
App.renderTour()
end
if keepScroll then
task.defer(function()
if App.scroll then
App.scroll.CanvasPosition = keepScroll
end
end)
end
end
local function applyTheme()
makePalette()
App.pruneThumbs(true)
App.rebuildAll()
rebuildOverlay()
if App.removeSplineViz then
App.removeSplineViz()
App.drawSpline()
end
end
App.applyTheme = applyTheme
local rebuildQueued = false
App.onSelect(function()
if rebuildQueued then
return
end
rebuildQueued = true
task.defer(function()
rebuildQueued = false
App.rebuildAll()
end)
end)
track(settings().Studio.ThemeChanged:Connect(applyTheme))
end
end)()
-- #module App/Viewport/Paint
MODULES["App/Viewport/Paint"] = (function()
--[[
Smart Scatter — Paint: painting the area in the viewport: brush, lasso, box, polygon, smart fill, gizmos, keys.
Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]
return function(App)
local beginRec, endRec, plugin, Engine, track, G, saveG = App.beginRec, App.endRec, App.plugin, App.Engine, App.track, App.G, App.saveG
local LAYER_MODES, P, SANS_M, new, corner, stroke, pad = App.LAYER_MODES, App.P, App.SANS_M, App.new, App.corner, App.stroke, App.pad
local refreshSliders, VIEW, refreshParams, probe = App.refreshSliders, App.VIEW, App.refreshParams, App.probe
local flushRows, rebuildOverlay, saveArea = App.flushRows, App.rebuildOverlay, App.saveArea
local canGenerate, runGenerate, newArea = App.canGenerate, App.runGenerate, App.newArea
local UIS = game:GetService("UserInputService")
local rawMouse = plugin:GetMouse()
local mouse = setmetatable({}, {
__index = function(_, k)
local v = rawMouse[k]
if typeof(v) == "RBXScriptSignal" then
return {
Connect = function(_, fn)
return track(v:Connect(fn))
end,
}
end
return v
end,
})
local down, lastPos, strokeRec, strokeChanged = false, nil, nil, false
local strokeTouched = {}
local strokeErased = {}
local strokeWiped = {}
local function cellKey(cx, cz)
return cx * 1000003 + cz
end
App.cellKey = cellKey
local strokeBox
local function touched(cx, cz)
local c = App.area.cell
local x0, z0, x1, z1 = cx * c, cz * c, (cx + 1) * c, (cz + 1) * c
local b = strokeBox
strokeBox = b and { math.min(b[1], x0), math.min(b[2], z0), math.max(b[3], x1), math.max(b[4], z1) } or { x0, z0, x1, z1 }
end
local gestureOn = true
local gestureAction
local shapePts, boxStart
local lastClick = 0
local function shiftHeld()
local ok, v = pcall(function()
return UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift)
end)
return ok and v
end
local function erasing()
return (App.mode == "Erase") ~= (shiftHeld() == true)
end
local function layerAction()
return shiftHeld() and App.LAYER_OPPOSITE[App.mode] or App.mode
end
local function activeTool()
return LAYER_MODES[App.mode] and "Brush" or G.tool
end
App.gz = {}
local function gizmoFolder()
if App.gz.folder and App.gz.folder.Parent then
return App.gz.folder
end
App.gz = {}
App.gz.folder = new("Folder", { Name = "SmartScatterBrush", Archivable = false, Parent = workspace.CurrentCamera })
local T = workspace.Terrain
App.gz.ring =
new("CylinderHandleAdornment", { Adornee = T, Height = 0.1, Transparency = 0.1, AlwaysOnTop = true, ZIndex = 2, Parent = App.gz.folder })
App.gz.disc = new(
"CylinderHandleAdornment",
{ Adornee = T, Height = 0.05, Transparency = 0.84, AlwaysOnTop = true, ZIndex = 1, Parent = App.gz.folder }
)
App.gz.halo = new(
"CylinderHandleAdornment",
{ Adornee = T, Height = 0.06, Transparency = 0.86, AlwaysOnTop = true, ZIndex = 1, Parent = App.gz.folder }
)
App.gz.sq = new("BoxHandleAdornment", { Adornee = T, Transparency = 0.84, AlwaysOnTop = true, ZIndex = 1, Parent = App.gz.folder })
App.gz.dot =
new("SphereHandleAdornment", { Adornee = T, Radius = 0.3, Transparency = 0, AlwaysOnTop = true, ZIndex = 3, Parent = App.gz.folder })
App.gz.anchor = new("Part", {
Anchored = true,
CanCollide = false,
CanQuery = false,
CanTouch = false,
Transparency = 1,
Locked = true,
Archivable = false,
Size = Vector3.one * 0.2,
Parent = App.gz.folder,
})
App.gz.bb = new("BillboardGui", {
Adornee = App.gz.anchor,
Size = UDim2.fromOffset(240, 26),
StudsOffsetWorldSpace = Vector3.new(0, 1.5, 0),
SizeOffset = Vector2.new(0, 0.9),
AlwaysOnTop = true,
LightInfluence = 0,
ResetOnSpawn = false,
Parent = App.gz.folder,
})
local pill = new("Frame", {
BackgroundColor3 = P.bg,
BackgroundTransparency = 0.08,
AnchorPoint = Vector2.new(0.5, 0.5),
Position = UDim2.fromScale(0.5, 0.5),
Size = UDim2.fromOffset(0, 24),
AutomaticSize = Enum.AutomaticSize.X,
Parent = App.gz.bb,
}, { corner(12), stroke(P.line), pad(10, 10, 0, 0) })
App.gz.text = new("TextLabel", {
BackgroundTransparency = 1,
Font = SANS_M,
TextSize = 13,
TextColor3 = P.text,
Text = "",
Size = UDim2.fromOffset(0, 24),
AutomaticSize = Enum.AutomaticSize.X,
Parent = pill,
})
App.gz.lines = {}
return App.gz.folder
end
local function removeGizmo()
if App.gz.folder then
App.gz.folder:Destroy()
end
App.gz = {}
end
local function toolColor()
if LAYER_MODES[App.mode] then
local act = layerAction()
return (act == "None" or act == "Less") and P.danger or act == "Clear" and VIEW.muted or VIEW.accent
end
return erasing() and VIEW.blocked or VIEW.accent
end
local function drawPath(pts, closed, color)
gizmoFolder()
local n = #pts
local segs = closed and n or n - 1
for i = 1, math.max(segs, #App.gz.lines) do
local seg = App.gz.lines[i]
if i <= segs and n >= 2 then
if not seg then
seg = new(
"BoxHandleAdornment",
{ Adornee = workspace.Terrain, AlwaysOnTop = true, ZIndex = 4, Transparency = 0.05, Parent = App.gz.folder }
)
App.gz.lines[i] = seg
end
local a, b = pts[i], pts[i % n + 1]
local len = (b - a).Magnitude
seg.Visible = len > 1e-3
if len > 1e-3 then
seg.Size = Vector3.new(0.35, 0.2, len + 0.35)
seg.CFrame = CFrame.lookAt((a + b) / 2 + Vector3.new(0, 0.3, 0), b + Vector3.new(0, 0.3, 0))
seg.Color3 = color
end
elseif seg then
seg.Visible = false
end
end
end
local function clearPath()
if App.gz.lines then
for _, s in App.gz.lines do
s.Visible = false
end
end
end
local NICE_SURF = { Dirt = "Path", Generic = "Other", None = "Nothing" }
local function setLabel(t)
if App.gz.text then
App.gz.text.Text = t
App.gz.bb.Enabled = t ~= ""
end
end
local function mouseHit()
if not App.probeParams then
refreshParams()
end
local ray = mouse.UnitRay
return Engine.cast(ray.Origin, ray.Direction * 5000, App.probeParams)
end
App.modeHandlers = {}
App.registerMode = function(mode, spec)
App.modeHandlers[mode] = spec
if spec.noArea then
App.NO_AREA_MODES[mode] = true
end
end
local sizing
local smoothUp, lastRingAt
local function updateGizmo(hit)
if App.modeHandlers[App.mode] then
gizmoFolder()
for _, k in { "ring", "disc", "halo", "sq", "dot" } do
if App.gz[k] then
App.gz[k].Visible = false
end
end
end
if App.mode == "Spline" or App.mode == "Remove" or App.modeHandlers[App.mode] then
if App.clearGrid then
App.clearGrid()
end
return
end
gizmoFolder()
if App.gz.pick then
App.gz.pick.Adornee = nil
end
local tool = activeTool()
local show = hit ~= nil
local R = G.radius
local brush = show and tool == "Brush"
local col = toolColor()
App.gz.ring.Visible = brush and G.shape == "Circle"
App.gz.disc.Visible = App.gz.ring.Visible
App.gz.halo.Visible = App.gz.ring.Visible
App.gz.sq.Visible = brush and G.shape == "Square"
App.gz.dot.Visible = show
App.gz.bb.Enabled = show
if App.drawGrid then
App.drawGrid(show and hit.Position or nil)
end
if not show then
return
end
local p = hit.Position
if not smoothUp or not lastRingAt or (p - lastRingAt).Magnitude > R * 1.5 then
smoothUp = hit.Normal
else
smoothUp = smoothUp:Lerp(hit.Normal, 0.3).Unit
end
lastRingAt = p
local up = Engine.rotateUp(smoothUp)
local flat = CFrame.new(p) * up
App.gz.ring.Radius, App.gz.ring.InnerRadius = R, math.max(R - math.max(0.3, R * 0.025), 0)
App.gz.ring.CFrame = flat * CFrame.Angles(math.pi / 2, 0, 0)
App.gz.disc.Radius = R
App.gz.disc.CFrame = App.gz.ring.CFrame
local glowW = math.max(0.5, R * 0.05)
App.gz.halo.Radius, App.gz.halo.InnerRadius = R + glowW, R
App.gz.halo.CFrame = App.gz.ring.CFrame
App.gz.sq.Size = Vector3.new(R * 2, 0.08, R * 2)
App.gz.sq.CFrame = CFrame.new(p)
for _, a in { App.gz.ring, App.gz.disc, App.gz.halo, App.gz.sq, App.gz.dot } do
a.Color3 = col
end
App.gz.dot.CFrame = CFrame.new(p)
App.gz.anchor.CFrame = CFrame.new(p)
local surf = Engine.surfaceOf(hit.Instance, hit.Material)
local what = LAYER_MODES[App.mode] and (App.LAYER_LABEL[layerAction()] .. (App.paintLayer and (" · " .. App.paintLayer.inst.Name) or ""))
or ((erasing() and "Erase" or "Paint") .. " · " .. (NICE_SURF[surf] or surf))
if not LAYER_MODES[App.mode] and App.groundNote then
local note = App.groundNote(p.X, p.Z)
if note ~= "" then
what ..= "  ·  " .. note
end
end
if tool == "Polygon" and App.polyPts then
what ..= string.format("  ·  %d points · Enter or click the first to close", #App.polyPts)
elseif tool == "Box" and down and boxStart then
what = string.format("%.0f × %.0f studs", math.abs(p.X - boxStart.X), math.abs(p.Z - boxStart.Z))
elseif tool == "Lasso" and down then
what ..= "  ·  release to fill"
elseif tool == "Fill" then
what ..= "  ·  click to fill connected " .. string.lower(NICE_SURF[surf] or surf)
end
setLabel(sizing and string.format("Brush size %d  ·  click to keep, Esc to cancel", R) or what)
end
local function allow(cx, cz)
if not App.paintFilterOn then
return true
end
return G.paintOn[probe(cx, cz).cls] == true
end
local function applyCell(cx, cz, on, yHint)
if Engine.hasCell(App.area, cx, cz) == on then
return false
end
local info = probe(cx, cz, yHint)
if on and not allow(cx, cz) then
return false
end
Engine.setCell(App.area, cx, cz, on)
if not on then
strokeErased[cellKey(cx, cz)] = true
end
touched(cx, cz)
if on then
App.area.topY = (App.area.count <= 1) and info.y or math.max(App.area.topY, info.y)
end
App.dirtyRows[cz] = true
strokeChanged = true
return true
end
local pinRng = Random.new(os.time())
local function placeStamp(pos, erase)
local l, R = App.paintLayer, G.radius
if not l then
return
end
local changed
if erase then
changed = Engine.erasePins(l, pos.X, pos.Z, R) > 0
else
changed = #Engine.brushPins(App.area, l, pos.X, pos.Z, R, pinRng) > 0
end
if changed then
local c = App.area.cell
touched(math.floor((pos.X - R) / c), math.floor((pos.Z - R) / c))
touched(math.floor((pos.X + R) / c), math.floor((pos.Z + R) / c))
strokeChanged = true
end
end
local function stamp(pos)
local act = LAYER_MODES[App.mode] and gestureAction
if act == "Place" then
placeStamp(pos)
return
elseif act == "None" then
placeStamp(pos, true)
table.insert(strokeWiped, { pos.X, pos.Z, G.radius, G.shape == "Square" })
end
local c, R = App.area.cell, G.radius
local sq = G.shape == "Square"
for cx = math.floor((pos.X - R) / c), math.floor((pos.X + R) / c) do
for cz = math.floor((pos.Z - R) / c), math.floor((pos.Z + R) / c) do
local dx, dz = (cx + 0.5) * c - pos.X, (cz + 0.5) * c - pos.Z
local inside
if sq then
inside = math.abs(dx) <= R and math.abs(dz) <= R
else
inside = dx * dx + dz * dz <= R * R
end
if inside then
if LAYER_MODES[App.mode] then
local key = cx * 1000003 + cz
if App.paintLayer and Engine.hasCell(App.area, cx, cz) and not strokeTouched[key] then
strokeTouched[key] = true
local v = Engine.paintValue(App.paintLayer, cx, cz)
local nv = 1
if act == "More" then
nv = v + 0.5
elseif act == "Less" then
nv = v - 0.5
elseif act == "None" then
nv = 0
end
if nv ~= v then
Engine.setPaint(App.paintLayer, cx, cz, nv)
touched(cx, cz)
strokeChanged = true
App.dirtyRows[cz] = true
end
end
else
applyCell(cx, cz, gestureOn, pos.Y)
end
end
end
end
end
local function strokeTo(pos)
local step = math.max(G.radius * 0.3, App.area.cell * 0.75)
if not lastPos then
stamp(pos)
lastPos = pos
return
end
local d = pos - lastPos
local len = math.sqrt(d.X * d.X + d.Z * d.Z)
if len < step then
return
end
local n = math.ceil(len / step)
for i = 1, n do
stamp(lastPos:Lerp(pos, i / n))
end
lastPos = pos
end
local function fillShape(pts)
if #pts < 3 then
return
end
local poly, ysum = {}, 0
for _, p in pts do
table.insert(poly, { p.X, p.Z })
ysum += p.Y
end
local yHint = ysum / #pts
local changed = Engine.fillPolygon(App.area, poly, gestureOn, function(cx, cz)
if not gestureOn then
return true
end
probe(cx, cz, yHint)
return allow(cx, cz)
end)
for _, cc in changed do
App.dirtyRows[cc[2]] = true
if gestureOn then
App.area.topY = math.max(App.area.topY, probe(cc[1], cc[2]).y)
else
strokeErased[cellKey(cc[1], cc[2])] = true
end
end
if #changed > 0 then
strokeChanged = true
end
end
local function smartFill(hit)
local c = App.area.cell
local sx, sz = math.floor(hit.Position.X / c), math.floor(hit.Position.Z / c)
local start = probe(sx, sz, hit.Position.Y)
local R2 = (G.fillReach / c) ^ 2
local seen = { [sx * 1000003 + sz] = true }
local queue, qi = { sx, sz, start.y }, 1
local count, cap = 0, 60000
while qi < #queue and count < cap do
local cx, cz, py = queue[qi], queue[qi + 1], queue[qi + 2]
qi += 3
local ok, info
if gestureOn then
info = probe(cx, cz, py)
ok = info.cls == start.cls and math.abs(info.y - py) < 2.5
else
ok = Engine.hasCell(App.area, cx, cz)
info = ok and probe(cx, cz, py)
end
if ok then
applyCell(cx, cz, gestureOn, py)
count += 1
for d = 1, 4 do
local nx = cx + (d == 1 and 1 or d == 2 and -1 or 0)
local nz = cz + (d == 3 and 1 or d == 4 and -1 or 0)
local k = nx * 1000003 + nz
if not seen[k] and (nx - sx) ^ 2 + (nz - sz) ^ 2 <= R2 then
seen[k] = true
table.insert(queue, nx)
table.insert(queue, nz)
table.insert(queue, info.y)
end
end
end
end
end
local function beginGesture(name)
strokeChanged = false
table.clear(strokeTouched)
table.clear(strokeErased)
table.clear(strokeWiped)
strokeRec = beginRec(name)
end
local function dropErased(erased, wiped, l)
local a, c, n = App.area, App.area.cell, 0
if next(erased) then
n += Engine.dropWhere(a, function(x, z)
return erased[cellKey(math.floor(x / c), math.floor(z / c))] == true
end)
end
if #wiped > 0 and l then
n += Engine.dropWhere(a, function(x, z)
for _, w in wiped do
local dx, dz = x - w[1], z - w[2]
if (w[4] and math.max(math.abs(dx), math.abs(dz)) or math.sqrt(dx * dx + dz * dz)) <= w[3] then
return true
end
end
return false
end, Engine.layerKey(l), true)
end
if n > 0 then
App.countPlaced()
end
end
App.dropErased = dropErased
local function finishGesture()
local rec, changed, box = strokeRec, strokeChanged, strokeBox
local erased, wiped = table.clone(strokeErased), table.clone(strokeWiped)
strokeRec, strokeChanged, strokeBox = nil, false, nil
down = false
lastPos, shapePts, boxStart = nil, nil, nil
clearPath()
flushRows()
local layerPaint = LAYER_MODES[App.mode] and App.paintLayer
if changed then
saveArea()
end
endRec(rec, not changed)
if changed then
if not layerPaint then
App.analysisDirty = true
end
if layerPaint and box then
App.applyNow(layerPaint, nil, box)
elseif G.live and canGenerate() then
runGenerate(false, nil, box)
elseif App.area then
dropErased(erased, wiped, layerPaint)
App.markPending()
end
end
if not changed then
return
end
if layerPaint then
App.refreshObjects()
return
end
if not (G.live and canGenerate()) then
App.refreshScan()
App.refreshCounts()
App.status(select(2, canGenerate()) or "Area updated. Press Generate.")
end
end
local function fillSelection()
if not App.area or App.area.locked then
return
end
local parts = {}
for _, s in App.Selection:Get() do
for _, p in s:IsA("BasePart") and { s } or s:GetDescendants() do
if p:IsA("BasePart") and not p:FindFirstAncestor(Engine.OUT) then
table.insert(parts, p)
end
end
end
if #parts == 0 then
App.status("Select the parts to fill in the Explorer first: an island, a roof, a platform.")
return
end
gestureOn = true
beginGesture("Smart Scatter: Fill Selected Parts")
for _, cc in Engine.fillFromParts(App.area, parts) do
App.dirtyRows[cc[2]] = true
end
strokeChanged = true
finishGesture()
end
local function closePolygon()
if App.polyPts and #App.polyPts >= 3 then
gestureOn = not erasing()
beginGesture("Smart Scatter: Polygon")
fillShape(App.polyPts)
App.polyPts = nil
finishGesture()
else
App.polyPts = nil
clearPath()
end
end
local function cancelShape()
App.polyPts = nil
if down then
finishGesture()
end
clearPath()
end
local function sizeTo()
local ray, y = mouse.UnitRay, sizing.hit.Position.Y
if math.abs(ray.Direction.Y) < 1e-3 then
return
end
local t = (y - ray.Origin.Y) / ray.Direction.Y
if t <= 0 then
return
end
local d = ray.Origin + ray.Direction * t - sizing.hit.Position
G.radius = math.clamp(math.floor(math.sqrt(d.X * d.X + d.Z * d.Z) + 0.5), 4, 200)
refreshSliders()
updateGizmo(sizing.hit)
end
local function startSizing()
local hit = not down and activeTool() == "Brush" and mouseHit()
if hit then
sizing = { hit = hit, from = G.radius }
updateGizmo(hit)
end
end
local function endSizing(keep)
if not sizing then
return
end
if not keep then
G.radius = sizing.from
end
sizing = nil
saveG()
refreshSliders()
updateGizmo(mouseHit())
end
local removeParams = RaycastParams.new()
removeParams.FilterType = Enum.RaycastFilterType.Include
local function copyUnderMouse()
if not App.area then
return nil
end
removeParams.FilterDescendantsInstances = { App.area.folder }
local ray = mouse.UnitRay
local r = workspace:Raycast(ray.Origin, ray.Direction * 5000, removeParams)
return r and Engine.copyAt(App.area, r.Instance)
end
local function markCopy(copy)
gizmoFolder()
for _, k in { "ring", "disc", "halo", "sq", "dot" } do
App.gz[k].Visible = false
end
App.gz.bb.Enabled = copy ~= nil
App.gz.pick = App.gz.pick
or new("Highlight", {
FillTransparency = 0.6,
OutlineTransparency = 0,
DepthMode = Enum.HighlightDepthMode.Occluded,
Parent = App.gz.folder,
})
App.gz.pick.FillColor, App.gz.pick.OutlineColor = P.danger, P.danger
App.gz.pick.Adornee = copy
if copy then
App.gz.anchor.CFrame = copy:GetPivot()
setLabel("Click to remove " .. copy.Name)
end
end
local function removeUnderMouse()
local copy = copyUnderMouse()
if not copy then
return
end
local rec = beginRec("Smart Scatter: Remove copy")
local h = Engine.removeCopy(App.area, copy)
for _, l in App.area.layers do
if l._h == h and App.lastCounts[l] then
App.lastCounts[l] = math.max(App.lastCounts[l] - 1, 0)
end
end
saveArea()
endRec(rec)
markCopy(nil)
App.refreshCounts()
App.status(string.format("Removed. %d removed in this area.", Engine.removedCount(App.area)))
end
mouse.Move:Connect(function()
if App.mode == "Off" or App.mode == "Spline" then
return
end
if App.mode == "Remove" then
markCopy(copyUnderMouse())
return
end
local handler = App.modeHandlers[App.mode]
if handler then
handler.move()
return
end
if sizing then
sizeTo()
return
end
local hit = mouseHit()
updateGizmo(hit)
if not hit then
return
end
local tool = activeTool()
if down then
if tool == "Brush" then
strokeTo(hit.Position)
elseif tool == "Lasso" and shapePts then
local last = shapePts[#shapePts]
if (hit.Position - last).Magnitude >= math.max(1.5, App.area.cell * 0.5) and #shapePts < 2000 then
table.insert(shapePts, hit.Position)
drawPath(shapePts, true, toolColor())
end
elseif tool == "Box" and boxStart then
local a, b = boxStart, hit.Position
local y = math.max(a.Y, b.Y)
drawPath(
{ Vector3.new(a.X, y, a.Z), Vector3.new(b.X, y, a.Z), Vector3.new(b.X, y, b.Z), Vector3.new(a.X, y, b.Z) },
true,
toolColor()
)
end
elseif tool == "Polygon" and App.polyPts then
local pts = table.clone(App.polyPts)
table.insert(pts, hit.Position)
drawPath(pts, false, toolColor())
end
end)
mouse.Button1Down:Connect(function()
if App.mode == "Off" or App.mode == "Spline" or (App.overViewportUI and App.overViewportUI()) then
return
end
if sizing then
endSizing(true)
return
end
if App.mode == "Remove" then
if App.area and not App.area.locked then
removeUnderMouse()
end
return
end
local handler = App.modeHandlers[App.mode]
if handler then
handler.down()
return
end
if not App.area then
newArea({ keepMode = true })
end
if App.area.locked then
App.status("This area is locked. Unlock it in the area menu to paint or edit.")
return
end
local hit = mouseHit()
if not hit then
return
end
local tool = activeTool()
if tool == "Polygon" then
local now = os.clock()
local p = hit.Position
if App.polyPts and #App.polyPts >= 3 then
local first = App.polyPts[1]
local near = (Vector3.new(p.X, 0, p.Z) - Vector3.new(first.X, 0, first.Z)).Magnitude <= math.max(3, App.area.cell * 1.5)
if near or now - lastClick < 0.3 then
lastClick = 0
closePolygon()
return
end
end
lastClick = now
App.polyPts = App.polyPts or {}
table.insert(App.polyPts, p)
drawPath(App.polyPts, false, toolColor())
updateGizmo(hit)
return
end
down = true
gestureOn = not erasing()
gestureAction = LAYER_MODES[App.mode] and layerAction() or nil
if tool == "Brush" then
beginGesture(LAYER_MODES[App.mode] and "Smart Scatter: Paint Layer" or "Smart Scatter: Paint Area")
lastPos = nil
strokeTo(hit.Position)
elseif tool == "Lasso" then
beginGesture("Smart Scatter: Lasso")
shapePts = { hit.Position }
elseif tool == "Box" then
beginGesture("Smart Scatter: Box")
boxStart = hit.Position
elseif tool == "Fill" then
beginGesture("Smart Scatter: Fill")
smartFill(hit)
finishGesture()
end
end)
local upHandlers = {}
App.onMouseUp = function(fn)
table.insert(upHandlers, fn)
end
local pressed, sawHeld = false, false
local function releaseMouse()
if not pressed then
return
end
pressed, sawHeld = false, false
for _, fn in upHandlers do
local ok, err = pcall(fn)
if not ok then
warn("[Smart Scatter] " .. tostring(err))
end
end
end
App.releaseMouse = releaseMouse
mouse.Button1Down:Connect(function()
pressed, sawHeld = true, false
end)
mouse.Button1Up:Connect(releaseMouse)
track(UIS.InputEnded:Connect(function(input)
if input.UserInputType == Enum.UserInputType.MouseButton1 then
releaseMouse()
end
end))
track(UIS.WindowFocusReleased:Connect(releaseMouse))
track(App.RunService.Heartbeat:Connect(function()
if not pressed then
return
end
local ok, held = pcall(UIS.IsMouseButtonPressed, UIS, Enum.UserInputType.MouseButton1)
if not ok then
return
end
if held then
sawHeld = true
elseif sawHeld then
releaseMouse()
end
end))
App.onMouseUp(function()
local handler = App.modeHandlers[App.mode]
if handler then
if handler.up then
handler.up()
end
return
end
if not down then
return
end
local tool = activeTool()
if tool == "Lasso" and shapePts then
fillShape(shapePts)
elseif tool == "Box" and boxStart then
local hit = mouseHit()
if hit then
local a, b = boxStart, hit.Position
fillShape({ a, Vector3.new(b.X, a.Y, a.Z), b, Vector3.new(a.X, b.Y, b.Z) })
end
end
finishGesture()
end)
local endStroke = function()
if down then
finishGesture()
end
end
local TOOL_KEY = { tool1 = "Brush", tool2 = "Lasso", tool3 = "Box", tool4 = "Polygon", tool5 = "Fill" }
local lastKeyAt = {}
local ANY_TIME =
{ palette = true, overlay = true, shuffle = true, erase = true, tool1 = true, tool2 = true, tool3 = true, tool4 = true, tool5 = true }
local NEEDS_AREA = { erase = true, tool1 = true, tool2 = true, tool3 = true, tool4 = true, tool5 = true }
local function onKey(name)
if App.mode == "Off" and not (ANY_TIME[name] and App.widget.Enabled and (App.area or not NEEDS_AREA[name])) then
return
end
if os.clock() - (lastKeyAt[name] or 0) < 0.08 then
return
end
lastKeyAt[name] = os.clock()
if name == "palette" then
if App.widget.Enabled and App.openPalette then
App.openPalette()
end
return
end
if App.mode == "Stamp" and App.stampKey(name) then
return
end
if App.mode == "Select" and App.selectKey and App.selectKey(name) then
return
end
if name == "shuffle" then
if App.area and not App.area.locked and App.shuffle then
App.shuffle()
end
return
elseif name == "overlay" then
App.overlayHidden = not App.overlayHidden
rebuildOverlay()
if App.drawSpline then
App.drawSpline()
end
App.status(App.overlayHidden and "Overlay hidden. Press it again to show it." or "Overlay shown.")
return
end
if App.mode == "Spline" then
App.splineKey(name)
return
end
if sizing and (name == "size" or name == "close" or name == "cancel") then
endSizing(name ~= "cancel")
elseif TOOL_KEY[name] and not LAYER_MODES[App.mode] then
App.setTool(TOOL_KEY[name])
elseif name == "erase" and not LAYER_MODES[App.mode] then
App.setMode(App.mode == "Erase" and "Paint" or "Erase")
elseif name == "size" then
startSizing()
elseif name == "grow" or name == "shrink" then
G.radius = math.clamp(math.floor(G.radius * (name == "grow" and 1.2 or 1 / 1.2) + 0.5), 4, 200)
saveG()
refreshSliders()
updateGizmo(mouseHit())
elseif name == "close" then
closePolygon()
elseif name == "back" then
if App.polyPts then
table.remove(App.polyPts)
if #App.polyPts == 0 then
App.polyPts = nil
end
clearPath()
if App.polyPts then
drawPath(App.polyPts, false, toolColor())
end
end
elseif name == "cancel" then
if App.polyPts or down then
cancelShape()
else
App.setMode("Off")
end
end
end
local ALIASES = { KeypadEnter = "close" }
local CHAR = { LeftBracket = "[", RightBracket = "]", Return = "\r", Backspace = "\b", Escape = "\27", Space = " ", Tab = "\t" }
for n, d in { One = "1", Two = "2", Three = "3", Four = "4", Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9", Zero = "0" } do
CHAR[n] = d
end
local function charOf(key)
return CHAR[key] or (#key == 1 and string.lower(key)) or nil
end
local function actionFor(key)
if App.capturingKey then
return nil
end
local mods = App.modsHeld()
local exact = App.combo(key, mods)
for _, a in App.KEYMAP do
if App.keyOf(a.id) == exact then
return a.id
end
end
if mods.Ctrl or mods.Alt then
return nil
end
for _, a in App.KEYMAP do
if App.keyOf(a.id) == key then
return a.id
end
end
return ALIASES[key]
end
track(UIS.InputBegan:Connect(function(input)
if input.UserInputType ~= Enum.UserInputType.Keyboard or UIS:GetFocusedTextBox() then
return
end
local name = actionFor(input.KeyCode.Name)
if name then
onKey(name)
end
end))
App.panelKey = function(input)
if input.UserInputType == Enum.UserInputType.Keyboard and not UIS:GetFocusedTextBox() then
local name = actionFor(input.KeyCode.Name)
if name then
onKey(name)
end
end
end
local function shiftChanged(input)
local k = input.KeyCode
if (k == Enum.KeyCode.LeftShift or k == Enum.KeyCode.RightShift) and App.mode ~= "Off" then
if App.gz.folder then
updateGizmo(mouseHit())
end
if App.refreshFocus then
App.refreshFocus()
end
end
end
track(UIS.InputBegan:Connect(shiftChanged))
track(UIS.InputEnded:Connect(shiftChanged))
mouse.KeyDown:Connect(function(k)
for _, a in App.KEYMAP do
local key = App.splitCombo(App.keyOf(a.id))
if charOf(key) == k then
local name = actionFor(key)
if name then
onKey(name)
end
return
end
end
end)
local rightClicks, rmbAt, rmbPos = {}, nil, nil
App.onRightClick = function(fn)
table.insert(rightClicks, fn)
end
mouse.Button2Down:Connect(function()
rmbAt, rmbPos = os.clock(), Vector2.new(rawMouse.X, rawMouse.Y)
end)
mouse.Button2Up:Connect(function()
if not rmbAt then
return
end
local quick = os.clock() - rmbAt < 0.35 and (Vector2.new(rawMouse.X, rawMouse.Y) - rmbPos).Magnitude < 6
rmbAt = nil
if quick then
for _, fn in rightClicks do
fn()
end
end
end)
App.onRightClick(function()
if sizing then
endSizing(false)
elseif App.polyPts and App.mode ~= "Spline" then
closePolygon()
end
end)
local MODE_TEXT = {
Brush = "Drag to paint. Hold Shift to erase. {size} (or {shrink} {grow}) resizes.",
Lasso = "Drag an outline. It fills when you let go.",
Box = "Drag a rectangle. It fills when you let go.",
Polygon = "Click points. Click the first point, double-click, right-click or press {close} to close.",
Fill = "Click the ground to fill everything connected of that surface.",
Spline = "Click to add points. Drag to move, Shift+drag for height, {delete} deletes a point, {close} to finish.",
Place = "Spray: drag to put copies down where you brush. Shift takes hand-placed ones away. {size} resizes.",
Stamp = "Click to put one copy down, drag to turn it. {turn} turns, {shrink} {grow} size, {model} the model, {shuffle} a random one.",
Select = "Click a zone's ground, a path or a placed copy. On a copy: Shift + wheel turns it, Alt + wheel sizes it, Shift + right-click (or a second click) has more.",
Array = "Press on the ground and drag along where the copies go. A click makes a row of six.",
More = "Brush where you want more of it. Shift brushes less.",
Less = "Brush where you want less of it (twice clears it). Shift brushes more.",
None = "Brush to erase it there, copies placed by hand too. Shift brings it back to normal.",
Clear = "Brush to bring it back to normal there. Shift erases it.",
Remove = "Click a placed copy to take it out. It stays gone when you generate again.",
}
local function modeText(k)
return (string.gsub(MODE_TEXT[k] or "", "{(%w+)}", App.keyText))
end
local function showMode()
rebuildOverlay()
if App.drawSpline then
App.drawSpline()
end
if App.refreshFocus then
App.refreshFocus()
end
for _, k in { "refreshMode", "refreshShapes", "refreshPoint" } do
if App.ui[k] then
App.ui[k]()
end
end
end
local function stopGestures()
endSizing(false)
endStroke()
App.polyPts = nil
clearPath()
if App.resetSplineDrag then
App.resetSplineDrag()
end
for _, h in App.modeHandlers do
if h.stop then
h.stop()
end
end
end
App.setMode = function(m, layer)
if m == App.mode and (not LAYER_MODES[m] or layer == App.paintLayer) then
m = "Off"
end
if not App.NO_AREA_MODES[m] and App.area and App.area.locked then
App.status("This area is locked. Unlock it in the area menu to paint or edit.")
m = "Off"
end
if m == "Remove" and not App.area then
App.status("Generate an area first, then remove single copies from it.")
m = "Off"
end
stopGestures()
if not App.NO_AREA_MODES[m] and not App.area then
if m == "Spline" then
App.newSplineFn({ keepMode = true })
else
newArea({ keepMode = true })
end
end
App.mode = m
App.paintLayer = LAYER_MODES[m] and layer or nil
if App.mode ~= "Off" then
plugin:Activate(true)
refreshParams()
gizmoFolder()
local t = modeText(MODE_TEXT[App.mode] and App.mode or G.tool)
App.hint(App.mode .. G.tool, (App.mode == "Erase" and not LAYER_MODES[App.mode]) and ("Erasing. " .. t) or t)
updateGizmo(mouseHit())
else
removeGizmo()
plugin:Deactivate()
end
showMode()
end
App.setTool = function(t)
G.tool = t
saveG()
App.polyPts = nil
clearPath()
if App.ui.refreshTool then
App.ui.refreshTool()
end
if App.refreshFocus then
App.refreshFocus()
end
if App.mode ~= "Paint" and App.mode ~= "Erase" then
App.setMode("Paint")
else
App.hint("Paint" .. t, modeText(t))
updateGizmo(mouseHit())
end
end
local GROUND_ICON = { Brush = "brush", Lasso = "lasso", Box = "box", Polygon = "polygon", Fill = "fill" }
local function groundOK()
local k = App.selected and App.selected.kind
return k ~= "Path" and k ~= "Stamps"
end
for i, t in App.TOOLS do
App.registerTool({
id = "ground:" .. t,
group = "Ground",
order = i,
icon = GROUND_ICON[t],
name = t,
key = "tool" .. i,
when = groundOK,
on = function()
return App.mode == "Paint" and G.tool == t
end,
click = function()
if App.mode == "Paint" and G.tool == t then
App.setMode("Off")
else
App.setTool(t)
end
end,
})
end
App.registerTool({
id = "ground:erase",
group = "Ground",
order = 10,
icon = "trash",
name = "Erase ground",
key = "erase",
danger = true,
when = groundOK,
on = function()
return App.mode == "Erase"
end,
click = function()
App.setMode(App.mode == "Erase" and "Off" or "Erase")
end,
})
App.registerTool({
id = "remove",
group = "Remove",
icon = "close",
name = "Remove single copies",
danger = true,
when = function()
return App.area ~= nil and App.kindOf(App.area) ~= "Clear"
end,
on = function()
return App.mode == "Remove"
end,
click = function()
App.setMode("Remove")
end,
})
track(plugin.Deactivation:Connect(function()
if App.mode ~= "Off" then
stopGestures()
App.mode = "Off"
App.paintLayer = nil
removeGizmo()
showMode()
end
end))
App.stopGestures = stopGestures
App.fillSelection = fillSelection
App.rawMouse = rawMouse
App.mouse = mouse
App.shiftHeld = shiftHeld
App.gizmoFolder = gizmoFolder
App.removeGizmo = removeGizmo
App.setLabel = setLabel
App.mouseHit = mouseHit
end
end)()
-- #module App/Viewport/Grid
MODULES["App/Viewport/Grid"] = (function()
--[[
Smart Scatter — Grid: a floor grid round the brush while painting, like Blender's viewport grid, but lying on the
ground (hills and all) and drawn on the area's own cells, so it shows exactly what a stroke fills. It fades out
toward its edge and every 4th line is stronger. Heights come from the overlay's ground probe (cached per cell),
lines over flat ground are one line, not a line per cell, and it's redrawn only when the brush reaches another
cell. Settings › Viewport can turn it off.
Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]
return function(App)
local G, P, new = App.G, App.P, App.new
local MAJOR = 4
local LIFT = 0.07
local last
local function pool()
local gz = App.gz
gz.grid = gz.grid or { lines = {}, used = 0 }
return gz.grid
end
local function line(a, b, transparency, major)
local g = pool()
g.used += 1
local l = g.lines[g.used]
if not l then
l = new("LineHandleAdornment", {
Adornee = workspace.Terrain,
AlwaysOnTop = false,
ZIndex = 0,
Parent = App.gizmoFolder(),
})
g.lines[g.used] = l
end
l.CFrame = CFrame.lookAt(a, b)
l.Length = (b - a).Magnitude
l.Thickness = major and 2 or 1
l.Color3 = major and Color3.new(1, 1, 1):Lerp(P.accent, 0.25) or Color3.fromRGB(225, 225, 225)
l.Transparency = transparency
l.Visible = true
end
App.clearGrid = function()
local g = App.gz and App.gz.grid
if g then
for _, l in g.lines do
l.Visible = false
end
g.used = 0
end
last = nil
end
App.drawGrid = function(p)
if not (App.gz and App.gz.grid) then
last = nil
end
local a = App.area
if not (p and a and G.grid ~= false) then
App.clearGrid()
return
end
local c = a.cell
local R = math.clamp(G.radius * 2.2, 32, 96)
local hx, hz = math.floor(p.X / c), math.floor(p.Z / c)
local key = hx .. "," .. hz .. "," .. R
if key == last then
return
end
last = key
local g = pool()
for i = 1, g.used do
g.lines[i].Visible = false
end
g.used = 0
local n = math.ceil(R / c)
local heights = {}
local function y(ix, iz)
local k = ix * 100003 + iz
local v = heights[k]
if not v then
v = App.probe(ix, iz, p.Y).y + LIFT
heights[k] = v
end
return v
end
local function fade(x, z)
return math.sqrt((x - p.X) ^ 2 + (z - p.Z) ^ 2) / R
end
for pass = 1, 2 do
for k = -n, n + 1 do
local fixed = (pass == 1 and hz or hx) + k
local major = fixed % MAJOR == 0
local runStart, runY, runT
local function flush(i)
if runStart then
local x0, x1 = runStart * c, i * c
local fx = fixed * c
local A = pass == 1 and Vector3.new(x0, runY, fx) or Vector3.new(fx, runY, x0)
local B = pass == 1 and Vector3.new(x1, runY, fx) or Vector3.new(fx, runY, x1)
line(A, B, runT, major)
runStart = nil
end
end
for i = (pass == 1 and hx or hz) - n, (pass == 1 and hx or hz) + n do
local ix, iz = pass == 1 and i or fixed, pass == 1 and fixed or i
local mx, mz = (pass == 1 and (i + 0.5) * c or fixed * c), (pass == 1 and fixed * c or (i + 0.5) * c)
local d = fade(mx, mz)
if d > 1 then
flush(i)
else
local h = y(ix, iz)
local t = math.clamp((major and 0.35 or 0.6) + (major and 0.65 or 0.4) * d ^ 1.6, 0, 1)
local tq = math.floor(t * 5 + 0.5) / 5
if runStart and (math.abs(h - runY) > 0.35 or tq ~= runT) then
flush(i)
end
if not runStart then
runStart, runY, runT = i, h, tq
end
end
end
flush((pass == 1 and hx or hz) + n + 1)
end
end
end
end
end)()

return MODULES
