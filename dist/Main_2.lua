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
-- #module App/Panel/ObjectTools
MODULES["App/Panel/ObjectTools"] = (function()
--[[
Smart Scatter — ObjectTools: the area's objects (each one model or a mix of models, with its rules) as the
controls the tabs put in their cards: the list with adding and objects whose model went missing, one object's
settings (a card per rule), biomes, presets, the performance report and removing single copies.
Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]
return function(App)
local Selection, FAST, tween, Engine, G, saveG, num = App.Selection, App.FAST, App.tween, App.Engine, App.G, App.saveG, App.num
local P, SANS, SANS_M, SANS_B, new, corner, stroke = App.P, App.SANS, App.SANS_M, App.SANS_B, App.new, App.corner, App.stroke
local pad, vlist, hlist, box, col, label, para = App.pad, App.vlist, App.hlist, App.box, App.col, App.label, App.para
local hintOn, slider, switch, switchRow, segmented = App.hintOn, App.slider, App.switch, App.switchRow, App.segmented
local recolorOverlay, rebuildOverlay, canGenerate, requestLive, commit =
App.recolorOverlay, App.rebuildOverlay, App.canGenerate, App.requestLive, App.commit
local newArea, thumbnail = App.newArea, App.thumbnail
local beginRec, endRec, button, buttonRow, explain = App.beginRec, App.endRec, App.button, App.buttonRow, App.explain
local chip, chipGrid, stepLabel, NICE = App.chip, App.chipGrid, App.stepLabel, App.NICE
local rowRefs = {}
local function gap(parent, h)
box({ Size = UDim2.new(1, 0, 0, h), Parent = parent })
end
local function showObject(l)
App.selectObject(l)
end
local function removeObject(l)
local i = App.area and table.find(App.area.layers, l)
if not i then
return
end
table.remove(App.area.layers, i)
local key = Engine.layerKey(l)
for _, f in App.area.folder:GetChildren() do
if f:GetAttribute("SS_Key") == key then
Engine.dropOutput(f)
end
end
App.lastTotal = math.max((App.lastTotal or 0) - (App.lastCounts[l] or 0), 0)
App.lastCounts[l] = nil
if App.heatLayer == l then
App.heatLayer = nil
end
commit(nil, "Remove " .. l.inst.Name)
showObject(nil)
App.status(string.format("Removed %s. Ctrl+Z brings it back.", l.inst.Name))
end
App.moveObject = function(l, to)
local layers = App.area and App.area.layers
local from = layers and table.find(layers, l)
if not from then
return
end
to = math.clamp(to, 1, #layers)
if to == from then
return
end
table.insert(layers, to, table.remove(layers, from))
commit(nil, "Reorder objects")
App.rebuildAll()
end
App.objectMenu = function(l)
local layers = App.area and App.area.layers or {}
local i = table.find(layers, l)
local items = {
{
"Open its settings",
function()
showObject(l)
end,
},
{
l.s.enabled and "Turn off" or "Turn on",
function()
l.s.enabled = not l.s.enabled
commit(l)
App.rebuildAll()
end,
P.dim,
},
}
if i and i > 1 then
table.insert(items, {
"Move up",
function()
App.moveObject(l, i - 1)
end,
P.dim,
})
end
if i and i < #layers then
table.insert(items, {
"Move down",
function()
App.moveObject(l, i + 1)
end,
P.dim,
})
end
table.insert(items, "-")
table.insert(items, {
"Remove",
function()
removeObject(l)
end,
P.danger,
})
return items
end
local function modelRow(parent, inst, text, actions)
local row = box({ Size = UDim2.new(1, 0, 0, 32), Parent = parent })
local th = thumbnail(inst, 28)
th.Position = UDim2.fromOffset(0, 2)
th.Parent = row
label(text, 13, P.text, SANS_M, { Position = UDim2.fromOffset(36, 0), Size = UDim2.new(1, -170, 1, 0), Parent = row })
local right = box({
AnchorPoint = Vector2.new(1, 0),
Position = UDim2.new(1, 0, 0, 1),
Size = UDim2.fromOffset(0, 30),
AutomaticSize = Enum.AutomaticSize.X,
Parent = row,
}, {
new("UIListLayout", {
FillDirection = Enum.FillDirection.Horizontal,
Padding = UDim.new(0, 6),
SortOrder = Enum.SortOrder.LayoutOrder,
}),
})
for i, a in actions or {} do
button(a[1], a[2], a[3], { LayoutOrder = i, Parent = right })
end
return row
end
local function controls(l)
local s, D = l.s, Engine.defaults(l.type)
local c = {}
local function reheat()
if App.heatLayer == l then
recolorOverlay()
end
end
function c.live()
requestLive(l)
reheat()
end
function c.done()
commit(l)
reheat()
end
function c.changed(rebuild)
c.done()
if rebuild then
App.refreshObjects()
end
end
function c.S(parent, key, text, min, max, fmt, step, hint)
slider(text, min, max, function()
return s[key]
end, function(v)
s[key] = v
end, fmt, step, c.live, c.done, hint, D[key]).Parent =
parent
end
function c.SW(parent, key, text, hint, rebuild)
switchRow(text, function()
return s[key]
end, function(v)
s[key] = v
end, function()
c.changed(rebuild)
end, hint).Parent =
parent
end
function c.PICK(parent, title, key, options, hint, rebuild)
stepLabel(parent, nil, title)
segmented(options, function()
return s[key]
end, function(v)
s[key] = v
end, function()
c.changed(rebuild)
end).Parent =
parent
if hint then
explain(parent, hint)
end
end
return c
end
local function buildBasics(l, cs, c)
cs.add({
id = "placement",
title = "Placement",
sub = "Spread out or along a line, how much, and what it is",
build = function(parent)
local s = l.s
local line = Engine.isLine(l)
segmented(Engine.PLACES, function()
return s.place
end, function(v)
if v == "Along" and s.place ~= "Along" then
local sp = App.area and App.area.spline
Engine.smartLine(l, sp ~= nil and #sp.pts >= 2)
else
s.place = v
end
end, function()
commit()
App.refreshObjects()
end).Parent =
parent
explain(
parent,
line and "Along: copies follow a line (a road edge, the area's border or a path), like lamps or a fence."
or "Scatter: copies spread over the painted area, following the rules below."
)
gap(parent, 6)
if not line then
c.S(parent, "density", "Amount", 0, 4, "%.2f×", 0.05, "How much of this object to place. 1× is the smart default for its type.")
gap(parent, 4)
end
stepLabel(parent, nil, "Type")
segmented(Engine.TYPES, function()
return l.type
end, function(t)
Engine.setType(l, t)
end, function()
commit()
App.refreshObjects()
end).Parent =
parent
explain(parent, "What it is. Sets sensible defaults for spacing, slopes and what it keeps away from.")
gap(parent, 6)
c.SW(
parent,
"locked",
"Lock placement",
"Keeps every copy of this object exactly where it is when the area regenerates. Changes still save; unlock to see them."
)
end,
})
end
local function buildLine(l, parent, c)
local s = l.s
parent.add({
id = "line",
title = "Line",
keys = "follow side orientation roll fit end to end post gap stagger facing axis",
more = false,
build = function(b)
local follows = table.clone(Engine.FOLLOWS)
if (App.area and App.area.spline and #App.area.spline.pts > 0) or s.follow == "Spline" then
table.insert(follows, "Spline")
end
c.PICK(
b,
"Follow",
"follow",
follows,
s.follow == "Spline" and "Follows this area's path."
or s.follow == "Border" and "Runs around the edge of the painted area, e.g. a fence around a field."
or ("Runs along " .. string.lower(s.follow) .. " inside the painted area (found by the scan)."),
true
)
local onSpline = s.follow == "Spline"
if onSpline then
gap(b, 4)
c.PICK(
b,
"Side",
"side",
Engine.SIDES,
"Center puts copies on the curve itself, turned toward the nearest road; the others set them beside it, e.g. lamps along both sides of a road.",
true
)
gap(b, 4)
c.PICK(
b,
"Orientation",
"orient",
Engine.ORIENTS,
"Upright stands straight (lamps, posts). Surface sticks to what's under it (moss on walls, lights on a ceiling). Follow bends with the curve up and down (bridge planks, rails, pipes)."
)
c.S(b, "roll", "Roll", 0, 360, "%.0f°", 5, "Turns each copy around the direction of the curve.")
end
gap(b, 4)
if not onSpline then
c.S(b, "offset", "Distance from it", 0, 40, "%.0f studs", 0.5, "Gap between the edge you follow and the side of each copy.")
elseif s.side ~= "Center" then
c.S(b, "offset", "Distance from the curve", 0, 60, "%.0f studs", 0.5, "How far to the side of the path each copy sits.")
end
c.SW(
b,
"fit",
"Line up end to end",
"Resizes each piece so they meet with no gaps or overlaps, even on bends: fences, walls, path tiles, rails.",
true
)
if not s.fit and Engine.looksLikeSegment(l) then
local row = col({ Parent = b }, { vlist(4) })
local q = para("Pieces don't meet. Resize them to fit?", { Parent = row })
q.TextColor3 = P.dim
button("Resize pieces to fit", "accent", function()
s.fit = true
c.changed(true)
end, { Parent = buttonRow(row) })
end
if s.fit then
if l.post then
modelRow(b, l.post.inst, "Post: " .. l.post.inst.Name, {
{
"Remove",
"danger",
function()
Engine.setPost(l, nil)
c.changed(true)
end,
},
})
else
hintOn(
button("Add selected as post", nil, function()
local sel = Selection:Get()[1]
if not sel or sel == l.inst or not Engine.setPost(l, sel) then
App.status("Select a post or pillar model in the Explorer first.")
return
end
App.status("Posts go at every joint and both ends.")
c.changed(true)
end, { Parent = buttonRow(b) }),
"Optional: a separate post model placed at every joint and at both ends. Without one, a fence whose model has a post on one end only gets matching end posts automatically."
)
end
else
c.S(b, "interval", "Gap between", 2, 150, "%.0f studs", 1, "Distance from one copy to the next along the line.")
c.S(b, "jitter", "Unevenness", 0, 1, "%.0f%%", 0.05, "0% is perfectly even. Higher shifts copies back and forth along the line.")
if not onSpline or s.side == "Both" then
c.SW(b, "stagger", "Stagger the two sides", "Copies on opposite sides sit between each other instead of facing pairs.")
end
end
c.S(
b,
"skip",
"Leave gaps",
0,
0.9,
"%.0f%%",
0.05,
"How much is left out, in real openings: stretches of fence with gaps between them, never a lone piece. Posts only stand where there's fence."
)
if not s.fit then
gap(b, 4)
c.PICK(
b,
"Facing",
"facing",
Engine.FACINGS,
"Face it turns the front (−Z side) toward the edge, like a lamp over a road. Along lines the long side up with it.",
true
)
end
gap(b, 4)
local alongAxis = s.fit or s.facing == "Along"
c.PICK(
b,
alongAxis and "Axis along the line" or "Model's front",
"front",
Engine.FRONTS,
alongAxis and "Which of the model's axes runs down the line, and so sets the piece length. Auto uses the longer side."
or "Which side of the model is its front, the side that faces the edge (a lantern's glass, a sign's face). Auto uses the side the model reaches out to (a lamp's arm), otherwise -Z, Roblox's front."
)
c.S(b, "maxCount", "Limit", 0, 2000, "%.0f", 10, "Maximum number of copies. 0 means no limit.")
end,
})
end
local function buildModels(l, parent, c)
parent.add({
id = "variants",
title = "Models",
keys = "swap mix share",
more = false,
build = function(b)
for _, v in l.variants do
local actions = {
{
"Swap",
nil,
function()
local pick = Selection:Get()[1]
local old = v.inst.Name
if not (pick and Engine.swapVariant(l, table.find(l.variants, v), pick)) then
App.status("Select the model to swap in, in the Explorer, then click Swap.")
return
end
App.status(string.format("Swapped %s for %s. Copies stay on the same spots where they fit.", old, pick.Name))
App.applyNow(l, "Swap model")
App.refreshObjects()
end,
},
}
if #l.variants > 1 then
table.insert(actions, {
"Remove",
"danger",
function()
Engine.removeVariant(l, table.find(l.variants, v))
commit()
App.refreshObjects()
end,
})
end
modelRow(b, v.inst, v.inst.Name, actions)
if #l.variants > 1 then
slider("Share", 0, 10, function()
return v.w
end, function(x)
v.w = x
end, "%.1f", 0.5, c.live, c.done, "How often this model is picked compared to the others in this object.", 1).Parent =
b
end
slider("Size", 0.3, 3, function()
return v.size
end, function(x)
v.size = x
end, "%.2f×", 0.05, c.live, c.done, "Size of this model on top of the object's size range.", 1).Parent =
b
end
if l.missing then
para(
string.format(
"%d more model%s not found in this place. %s kept, and come%s back when found again.",
#l.missing,
#l.missing == 1 and "" or "s",
#l.missing == 1 and "It's" or "They're",
#l.missing == 1 and "s" or ""
),
{ Parent = b }
)
end
gap(b, 4)
hintOn(
button("Add selected as models", nil, function()
local added = 0
for _, sel in Selection:Get() do
for _, inst in sel:IsA("Folder") and sel:GetChildren() or { sel } do
if Engine.addVariant(l, inst) then
added += 1
end
end
end
if added == 0 then
App.status("Select more models in the Explorer to mix them into this object.")
return
end
App.status(string.format("Added %d model%s to %s.", added, added == 1 and "" or "s", l.inst.Name))
commit(l)
App.refreshObjects()
end, { Parent = buttonRow(b) }),
"Select models (or a folder of them) in the Explorer, then click: they mix into this object, e.g. pine, oak and birch in one forest."
)
end,
})
end
local function buildSize(l, parent, c)
local s = l.s
parent.add({
id = "size",
title = "Size",
keys = "smallest largest young edges scale",
more = false,
build = function(b)
if Engine.isLine(l) and s.fit then
slider("Size", 0.2, 4, function()
return (s.scaleMin + s.scaleMax) / 2
end, function(v)
s.scaleMin, s.scaleMax = v, v
end, "%.2f×", 0.05, c.live, c.done, "Size of every piece. Pieces that join end to end all share one size.", 1).Parent =
b
else
c.S(b, "scaleMin", "Smallest", 0.2, 4, "%.2f×", 0.05, "Smallest random size a copy can be.")
c.S(b, "scaleMax", "Largest", 0.2, 4, "%.2f×", 0.05, "Largest random size. Bigger copies land in the middle of clumps.")
c.S(
b,
"edgeYoung",
"Young at the edges",
0,
1,
"%.0f%%",
0.05,
"Smaller copies toward the area's edge and its clearings, like the young fringe of a real forest."
)
end
end,
})
end
local function buildSpread(parent, c)
parent.add({
id = "spread",
title = "Spread",
keys = "spacing clumping clump room limit",
more = false,
build = function(b)
c.S(b, "spacing", "Spacing", 0.3, 3, "%.2f×", 0.05, "Gap between copies of this object, relative to their size.")
c.S(b, "clearance", "Room for others", 0, 2, "%.2f×", 0.05, "Lower lets other objects tuck in close, e.g. bushes under trees.")
c.S(b, "cluster", "Clumping", 0, 1, "%.0f%%", 0.05, "0% spreads evenly. 100% groups copies into patches.")
c.S(b, "clumpSize", "Clump size", 0.3, 4, "%.2f×", 0.05, "How big the patches are when clumping.")
c.S(b, "maxCount", "Limit", 0, 2000, "%.0f", 10, "Maximum number of copies. 0 means no limit.")
end,
})
end
local function buildGroups(l, parent, c)
local s = l.s
parent.add({
id = "groups",
title = "Groups",
keys = "piles stack tightness",
more = true,
build = function(b)
c.SW(
b,
"groups",
"Place in small groups",
"Copies gather in little piles (barrels, crates, rocks, bushes) with space between piles, instead of spreading one by one.",
true
)
if not s.groups then
return
end
c.S(b, "groupMin", "Smallest group", 1, 12, "%.0f", 1, "Fewest pieces in one pile.")
c.S(b, "groupMax", "Largest group", 1, 12, "%.0f", 1, "Most pieces in one pile.")
c.S(b, "tight", "Tightness", 0.9, 2.5, "%.2f×", 0.05, "1× means pieces touch. Higher leaves a small gap between them.")
local flat = false
for _, v in l.variants do
flat = flat or v.m.flatTop >= 0.45
end
if flat then
c.S(
b,
"stack",
"Stack on top",
0,
0.6,
"%.0f%%",
0.05,
"Chance a piece sits on top of another, like crates on crates. Only on flat tops."
)
end
c.SW(b, "sameModel", "Same model per group", "On: a pile is all barrels or all crates. Off: models mix inside a pile.")
end,
})
end
local function buildGrowsOn(l, parent, c)
local s = l.s
parent.add({
id = "surfaces",
title = "Grows on",
keys = "grass sand rock snow height band",
more = true,
build = function(b)
local grid = chipGrid(b, 4, 30)
for _, cls in Engine.SURFACES do
chip(grid, NICE[cls] or cls, function()
return s.surfaces[cls]
end, function()
s.surfaces[cls] = not s.surfaces[cls]
c.changed()
end)
end
if not Engine.isLine(l) then
gap(b, 6)
c.SW(b, "useAlt", "Only within a height band", "Keeps this object to part of the area's height, e.g. rocks only up high.", true)
if s.useAlt then
c.S(b, "altMin", "From", 0, 1, "%.0f%%", 0.05, "Bottom of the band. 0% is the lowest ground in the area.")
c.S(b, "altMax", "To", 0, 1, "%.0f%%", 0.05, "Top of the band. 100% is the highest ground in the area.")
end
end
end,
})
end
local function buildNeighbours(l, parent, c)
local s = l.s
parent.add({
id = "avoid",
title = "Keep away from",
keys = "buildings roads water distance",
more = true,
build = function(b)
c.S(b, "keepBuilding", "Buildings", 0, 60, "%.0f studs", 1, "Minimum distance from buildings and other structures.")
c.S(b, "keepRoad", "Roads", 0, 60, "%.0f studs", 1, "Minimum distance from roads and pavement.")
c.S(b, "keepWater", "Water", 0, 60, "%.0f studs", 1, "Minimum distance from water.")
end,
})
parent.add({
id = "attract",
title = "Prefer near",
keys = "hug near walls water roads face road",
more = true,
build = function(b)
segmented(Engine.HUGS, function()
return s.hug
end, function(v)
s.hug = v
end, function()
c.changed(true)
end).Parent =
b
explain(b, "Pull this object toward something: bushes near trees, crates near houses.")
if s.hug ~= "None" then
gap(b, 4)
c.S(b, "hugRange", "Within", 2, 80, "%.0f studs", 1, "How far the pull reaches.")
c.S(b, "hugStrength", "Strength", 0, 1, "%.0f%%", 0.05, "100% means only near it. 0% ignores it.")
end
if l.type == "Building" then
c.SW(b, "faceRoad", "Face the nearest road", "Turns the front (−Z side) of each building toward the closest road.")
end
local others = {}
for _, o in App.area.layers do
if o ~= l then
table.insert(others, o)
end
end
if #others > 0 then
gap(b, 6)
stepLabel(b, nil, "Near another object")
local grid = chipGrid(b, 3, 30)
chip(grid, "None", function()
return s.near == ""
end, function()
s.near = ""
c.changed(true)
end)
for _, o in others do
local key = Engine.layerKey(o)
chip(grid, o.inst.Name, function()
return s.near == key
end, function()
s.near = key
c.changed(true)
end)
end
if s.near ~= "" then
c.S(b, "nearRange", "Within", 2, 60, "%.0f studs", 1, "How far from that object's copies this one grows.")
c.S(b, "nearStrength", "Strength", 0, 1, "%.0f%%", 0.05, "100% means only near it. 0% ignores it.")
end
end
end,
})
end
local function buildSlope(parent, c)
parent.add({
id = "terrain",
title = "Slope",
keys = "steep flat lean slope",
more = true,
build = function(b)
c.S(b, "maxSlope", "Steepest", 0, 89, "%.0f°", 1, "Steepest ground this object can stand on.")
c.S(
b,
"slopePref",
"Prefers",
-1,
1,
"%+.0f%%",
0.05,
"Below 0: mostly on flat ground (trees in the valleys). Above 0: mostly on slopes (rocks and shrubs on hillsides). 0: anywhere."
)
c.S(b, "align", "Lean with the ground", 0, 1, "%.0f%%", 0.05, "0% stands straight up. 100% tilts with the slope.")
end,
})
end
local function buildLook(l, parent, c)
local s = l.s
local line = Engine.isLine(l)
parent.add({
id = "look",
title = "Look",
keys = "rotation tilt wind colour color hue saturation brightness variation details sink lift",
more = true,
build = function(b)
if not line then
c.PICK(b, "Rotation", "yawMode", Engine.YAW_MODES, nil, true)
if s.yawMode == "Fixed" then
gap(b, 4)
c.S(b, "yaw", "Fixed angle", 0, 359, "%.0f°", 5, "The direction every copy faces.")
end
end
if not (line and s.fit) then
c.S(b, "tilt", "Random tilt", 0, 45, "%.0f°", 1, "Random lean for a less uniform look.")
c.S(
b,
"lean",
"Lean with the wind",
0,
30,
"%.0f°",
1,
"Every copy leans the same way, like windswept trees. The direction is the area's Wind setting."
)
end
gap(b, 4)
c.SW(
b,
"vary",
"Variation",
"Every copy a little different: its own hue, saturation and brightness, on part colours, SurfaceAppearance meshes and decals alike; optionally with some details left out.",
true
)
if s.vary then
c.S(b, "hueVar", "Hue", 0, 0.15, "±%.0f%%", 0.005, "How far colours may drift round the colour wheel.")
c.S(b, "satVar", "Saturation", 0, 0.5, "±%.0f%%", 0.01, "Richer or more washed-out colours.")
c.S(b, "valVar", "Brightness", 0, 0.5, "±%.0f%%", 0.01, "Lighter or darker copies.")
c.SW(
b,
"perPart",
"Each part separately",
"Off: one shift for the whole copy. On: every part gets its own, e.g. leaves in slightly different greens."
)
c.S(
b,
"dropDetails",
"Leave out details",
0,
1,
"%.0f%%",
0.05,
"Chance each detail part is left out, so copies differ in shape too. Details: parts named like Apple, Fruit, Berry, Mushroom, Moss, Detail, Extra or Optional, or marked with the attribute SS_Optional."
)
else
c.S(b, "tint", "Colour shift", 0, 0.4, "%.0f%%", 0.01, "Random brightness and hue change per copy.")
end
c.S(
b,
"sink",
"Sink or lift",
-0.3,
0.6,
"%.0f%%",
0.01,
"Pushes copies into the ground (+) or lifts them (−), as a share of their height."
)
end,
})
end
local function buildActions(l, parent, head)
for i, a in
{
{
"cube",
"Select the source model in the Explorer.",
function()
Selection:Set({ l.inst })
end,
},
{
"refresh",
"Reset settings: this object's rules back to the smart defaults for its type. A line stays a line.",
function()
Engine.resetLayer(l)
commit(l)
App.refreshObjects()
end,
},
{
"trash",
"Remove this object and what it placed. Ctrl+Z brings it back.",
function()
removeObject(l)
end,
},
}
do
local b = App.iconButton(a[1], a[2], a[3], false, 28)
b.LayoutOrder = i
b.Parent = head
end
local actions = buttonRow(parent)
hintOn(
button("New look", "accent", function()
l.s.seed = (tonumber(l.s.seed) or 0) + 1
App.applyNow(l, "New look")
if App.heatLayer == l then
recolorOverlay()
end
end, { Parent = actions }),
"Rerolls just this object: new positions, same settings. The other objects stay where they are."
)
end
local function layerRules(l, parent, c)
local s = l.s
local spl = App.area and App.area.spline
if Engine.isLine(l) and spl and #spl.pts >= 2 and (App.area.count or 0) == 0 and s.follow ~= "Spline" then
s.follow = "Spline"
end
local line = Engine.isLine(l)
local onSpline = line and s.follow == "Spline"
local cs = App.cards(parent, "object")
buildBasics(l, cs, c)
buildModels(l, cs, c)
if line then
buildLine(l, cs, c)
end
buildSize(l, cs, c)
if not line then
buildSpread(cs, c)
end
if not onSpline then
cs.add({
id = "byhand",
title = "By hand",
icon = "spray",
sub = "Spray it, or brush where it grows more or less, with the viewport's tools",
keys = "brush more less erase reset place spray pins by hand painted",
build = function(b)
App.buildHandWork(l, b)
end,
})
end
if not line then
buildGroups(l, cs, c)
end
if not onSpline then
buildGrowsOn(l, cs, c)
end
if not line then
buildNeighbours(l, cs, c)
end
if not onSpline then
buildSlope(cs, c)
end
buildLook(l, cs, c)
end
local function layerRow(l, parent, drag, index)
local r = new("TextButton", {
Text = "",
AutoButtonColor = false,
BackgroundColor3 = P.card,
Size = UDim2.new(1, 0, 0, 60),
Parent = parent,
}, { corner(12), stroke(P.line) })
App.shade(r, 0.05)
App.topLight(r, 0.06, 12)
App.shadow(r, 12)
App.pressable(r, 0.985)
r.MouseEnter:Connect(function()
r.BackgroundColor3 = P.card:Lerp(P.hover, 0.45)
end)
r.MouseLeave:Connect(function()
r.BackgroundColor3 = P.card
end)
local th = thumbnail(l.inst, 44)
th.Position = UDim2.fromOffset(8, 8)
th.Parent = r
local name = label(l.inst.Name .. (#l.variants > 1 and ("  +" .. (#l.variants - 1)) or ""), 13, l.s.enabled and P.text or P.faint, SANS_B, {
Position = UDim2.fromOffset(62, 9),
Size = UDim2.new(1, -144, 0, 18),
Parent = r,
})
local kind = label("", 12, P.dim, SANS, { Position = UDim2.fromOffset(62, 27), Size = UDim2.new(1, -144, 0, 16), Parent = r })
local barTrack = box({
BackgroundTransparency = 0,
BackgroundColor3 = P.raised,
Position = UDim2.fromOffset(62, 47),
Size = UDim2.new(1, -144, 0, 3),
Parent = r,
}, { corner(2) })
local bar = box({ BackgroundTransparency = 0, BackgroundColor3 = P.accent, Size = UDim2.fromScale(0, 1), Parent = barTrack }, { corner(2) })
rowRefs[l] = { kind = kind, name = name, bar = bar }
local sw = switch(function()
return l.s.enabled
end, function(v)
l.s.enabled = v
end, function()
commit(l)
App.refreshObjects()
end)
sw.Position = UDim2.new(1, -48, 0.5, -11)
sw.ZIndex = 3
sw.Parent = r
hintOn(sw, "On or off, keeping its settings.")
local x = new("TextButton", {
Name = "Remove",
Text = "",
AutoButtonColor = false,
BackgroundColor3 = P.danger,
BackgroundTransparency = 1,
AnchorPoint = Vector2.new(0, 0.5),
Position = UDim2.new(1, -80, 0.5, 0),
Size = UDim2.fromOffset(24, 24),
ZIndex = 3,
Parent = r,
}, { corner(7) })
local xi = App.icon("close", 11, P.faint)
xi.AnchorPoint, xi.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
xi.Parent = x
x.MouseEnter:Connect(function()
x.BackgroundTransparency = 0.82
App.setIconColor(xi, P.danger)
end)
x.MouseLeave:Connect(function()
x.BackgroundTransparency = 1
App.setIconColor(xi, P.faint)
end)
App.pressable(x, 0.9)
hintOn(x, "Removes this object and what it placed. Ctrl+Z brings it back.")
x.MouseButton1Click:Connect(function()
removeObject(l)
end)
r.MouseButton1Click:Connect(function()
if not drag.dragged() then
showObject(l)
end
end)
r.MouseButton2Click:Connect(function()
App.popupMenu(nil, App.objectMenu(l))
end)
drag.add(r, index)
end
local CELL_H, CELL_THUMB = 102, 56
local function layerCell(l, parent, index)
local c = new("TextButton", {
Text = "",
AutoButtonColor = false,
BackgroundColor3 = P.card,
LayoutOrder = index,
Parent = parent,
}, { corner(10), stroke(P.line) })
c.MouseEnter:Connect(function()
c.BackgroundColor3 = P.card:Lerp(P.hover, 0.45)
end)
c.MouseLeave:Connect(function()
c.BackgroundColor3 = P.card
end)
local th = thumbnail(l.inst, CELL_THUMB)
th.AnchorPoint, th.Position = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 8)
th.ImageTransparency = l.s.enabled and 0 or 0.55
th.Parent = c
local name = label(l.inst.Name .. (#l.variants > 1 and ("  +" .. (#l.variants - 1)) or ""), 11, l.s.enabled and P.text or P.faint, SANS_B, {
Position = UDim2.fromOffset(5, CELL_THUMB + 12),
Size = UDim2.new(1, -10, 0, 14),
TextXAlignment = Enum.TextXAlignment.Center,
Parent = c,
})
local count = label("", 10, P.dim, SANS, {
Position = UDim2.fromOffset(5, CELL_THUMB + 26),
Size = UDim2.new(1, -10, 0, 12),
TextXAlignment = Enum.TextXAlignment.Center,
Parent = c,
})
rowRefs[l] = { name = name, count = count }
local dot = new("TextButton", {
Text = "",
AutoButtonColor = false,
BackgroundColor3 = l.s.enabled and P.accent or P.raised,
AnchorPoint = Vector2.new(1, 0),
Position = UDim2.new(1, -6, 0, 6),
Size = UDim2.fromOffset(14, 14),
ZIndex = 3,
Parent = c,
}, { corner(7), stroke(P.line) })
hintOn(dot, "On or off, keeping its settings.")
dot.MouseButton1Click:Connect(function()
l.s.enabled = not l.s.enabled
commit(l)
App.refreshObjects()
end)
c.MouseButton1Click:Connect(function()
showObject(l)
end)
c.MouseButton2Click:Connect(function()
App.popupMenu(nil, App.objectMenu(l))
end)
end
local function objectPage(l, parent)
local head = box({ Size = UDim2.new(1, 0, 0, 44), Parent = parent })
local th = thumbnail(l.inst, 40)
th.Position = UDim2.fromOffset(0, 2)
th.Parent = head
label(l.inst.Name, 16, P.text, SANS_B, { Position = UDim2.fromOffset(52, 2), Size = UDim2.new(1, -150, 0, 22), Parent = head })
local sub = label("", 12, P.dim, SANS, { Position = UDim2.fromOffset(52, 24), Size = UDim2.new(1, -150, 0, 16), Parent = head })
rowRefs[l] = { sub = sub }
local tools = box({
AnchorPoint = Vector2.new(1, 0.5),
Position = UDim2.new(1, 0, 0.5, 0),
Size = UDim2.fromOffset(0, 28),
AutomaticSize = Enum.AutomaticSize.X,
Parent = head,
}, { hlist(6) })
local c = controls(l)
buildActions(l, parent, tools)
if not Engine.isLine(l) then
switchRow(
"Show where it grows",
function()
return App.heatLayer == l
end,
function(v)
App.heatLayer = v and l or nil
end,
function()
rebuildOverlay()
end,
"Colours the painted area by how likely this object is to grow there with its current rules: dark is never, the accent is thickest. It follows your changes as you make them."
).Parent =
parent
end
gap(parent, 4)
layerRules(l, parent, c)
end
local function addSelected()
if not App.area then
newArea()
end
local added, skipped, last = 0, nil, nil
local function tryAdd(inst)
for _, l in App.area.layers do
if l.inst == inst then
return
end
end
if Engine.isGround(inst) then
skipped = inst.Name
return
end
local l = Engine.makeLayer(inst)
if l then
local sp = App.area.spline
if sp and #sp.pts >= 2 then
if App.area.count == 0 then
Engine.smartLine(l, true)
elseif l.s.place == "Along" then
l.s.follow, l.s.side, l.s.offset = "Spline", "Both", math.max(l.s.offset, (sp.width or 0) / 2)
end
end
table.insert(App.area.layers, l)
added += 1
last = l
end
end
for _, sel in Selection:Get() do
for _, inst in sel:IsA("Folder") and sel:GetChildren() or { sel } do
tryAdd(inst)
end
end
if added == 0 then
App.status(
skipped and ('"' .. skipped .. '" looks like ground. To make it a road, use Mark selected as.')
or "Select models, or a folder of them, in the Explorer first."
)
return
end
App.status(added == 1 and "Added 1 object." or string.format("Added %d objects.", added))
commit()
showObject(added == 1 and last or nil)
end
App.newZoneFromSelection = function()
local any = false
for _, sel in Selection:Get() do
for _, inst in sel:IsA("Folder") and sel:GetChildren() or { sel } do
any = any or ((inst:IsA("Model") or inst:IsA("BasePart")) and not Engine.isGround(inst))
end
end
if not any then
App.status("Select models (or a folder of them) in the Explorer first, then make a zone from them.")
return
end
newArea({ keepMode = true })
addSelected()
if App.area and App.area.layers[1] then
App.selectObject(App.area.layers[1])
end
App.setTool(G.tool)
App.status("Paint the ground where they should go.")
end
local function addLayers(layers, from, note)
if not App.area then
newArea()
end
local added = 0
for _, l in layers do
local dup = false
for _, o in App.area.layers do
dup = dup or o.inst == l.inst
end
if not dup then
table.insert(App.area.layers, l)
added += 1
end
end
local sp, needPath = App.area.spline, false
for _, l in layers do
needPath = needPath or (l.s.follow == "Spline" and Engine.isLine(l) and not (sp and #sp.pts >= 2))
end
App.status(
(
added == 0 and string.format("%s: this area already has all its objects.", from)
or string.format("Added %d object%s from %s.", added, added == 1 and "" or "s", from)
)
.. (note and (" " .. note) or "")
.. (needPath and " Some follow a path: draw one first." or "")
)
App.refreshObjects()
commit()
end
App.addLayers = addLayers
local function buildBiomes(b)
local grid = chipGrid(b, 4, 30)
for _, biome in Engine.BIOMES do
hintOn(
chip(grid, biome.name, nil, function()
local layers, missing = Engine.biomeLayers(biome)
if #layers == 0 then
App.status('No models with fitting names found (like "Oak Tree" or "Rock"). Try Get sample models.')
return
end
local none = #missing > 0 and ("No " .. string.lower(table.concat(missing, ", ")) .. " models found.") or nil
addLayers(layers, biome.name, none)
end),
"Adds a "
.. string.lower(biome.name)
.. " mix made from your models, found by name in ServerStorage, ReplicatedStorage and asset folders."
)
end
gap(b, 4)
hintOn(
button("Get sample models", nil, function()
local rec = beginRec("Smart Scatter: Sample models")
local folder, made = Engine.makeSamples()
endRec(rec, not made)
Selection:Set({ folder })
App.status(
made and "Sample models are in ServerStorage > SmartScatter Samples, and selected. Pick a biome, or Add selected."
or "Sample models are already in ServerStorage; selected them."
)
end, { Parent = buttonRow(b) }),
"Puts a few simple trees, a bush, a flower, a rock and a crate in ServerStorage to try things with."
)
end
local function buildReport(b)
explain(b, "See which objects cost the most parts, so you know what to simplify first.")
local out = col({ Parent = b }, { vlist(2) })
local function show()
out:ClearAllChildren()
vlist(2).Parent = out
local rows, total = Engine.report(App.area)
if total.parts == 0 then
para("Nothing placed yet.", { Parent = out })
return
end
for _, r in rows do
local row = box({ Size = UDim2.new(1, 0, 0, 22), Parent = out })
label(r.name, 12, P.text, SANS_M, { Size = UDim2.new(0.45, 0, 1, 0), Parent = row })
label(
r.copies > 0
and string.format(
"%s parts · %s per copy%s",
num(r.parts),
num(math.ceil(r.parts / r.copies)),
r.unique > 0 and (" · " .. r.unique .. " meshes") or ""
)
or (num(r.parts) .. " parts"),
12,
P.dim,
SANS,
{
Size = UDim2.new(0.55, 0, 1, 0),
Position = UDim2.fromScale(0.45, 0),
TextXAlignment = Enum.TextXAlignment.Right,
Parent = row,
}
)
end
local top = rows[1]
local share = top.parts / total.parts
para(
string.format("%s parts in all.", num(total.parts))
.. (
#rows > 1
and share >= 0.4
and string.format(
" %s is %d%% of them: a simpler model or a lower amount there helps most.",
top.name,
math.floor(share * 100 + 0.5)
)
or ""
),
{ Parent = out }
)
end
button("Check this area", nil, show, { Parent = buttonRow(b) })
end
local codeBox
local function shareCode(code)
if not codeBox then
return
end
codeBox.Text = code
codeBox:CaptureFocus()
codeBox.SelectionStart, codeBox.CursorPosition = 1, #code + 1
App.status("The code is selected in the box: press Ctrl+C to copy it.")
end
local function buildPresets(b)
local list = Engine.listPresets()
if #list == 0 then
App.emptyState(b, "No presets yet", "Save this area's objects below to reuse them in any area.")
end
for _, v in list do
local row = box({ Size = UDim2.new(1, 0, 0, 36), Parent = b })
label(v.Name, 13, P.text, SANS_M, { Size = UDim2.new(1, -220, 1, 0), Parent = row })
local acts = box({
Size = UDim2.new(0, 0, 1, 0),
AutomaticSize = Enum.AutomaticSize.X,
AnchorPoint = Vector2.new(1, 0),
Position = UDim2.fromScale(1, 0),
Parent = row,
}, { hlist(6) })
hintOn(
button("Use", "accent", function()
local layers, lost = Engine.layersFromJSON(v.Value)
addLayers(layers, v.Name, #lost > 0 and string.format("%d model%s not found in this place.", #lost, #lost == 1 and "" or "s"))
end, { Parent = acts }),
"Adds this preset's objects to the area (ones it already has are skipped)."
)
hintOn(
button("Share", nil, function()
shareCode(Engine.presetCode(v))
end, { Parent = acts }),
"Puts this preset's code in the box below: copy it and paste it into another place, or send it to a teammate."
)
button("Delete", "danger", function()
local rec = beginRec("Smart Scatter: Delete preset")
v.Parent = nil
endRec(rec)
App.refreshObjects()
end, { Parent = acts })
end
gap(b, 6)
local saveRow = box({ Size = UDim2.new(1, 0, 0, 30), Parent = b })
local nameBox = new("TextBox", {
Text = "",
PlaceholderText = "Preset name",
Font = SANS,
TextSize = 13,
TextColor3 = P.text,
PlaceholderColor3 = P.faint,
BackgroundColor3 = P.field,
ClearTextOnFocus = false,
TextXAlignment = Enum.TextXAlignment.Left,
Size = UDim2.new(1, -76, 1, 0),
Parent = saveRow,
}, { corner(8), stroke(P.line), pad(8, 8, 0, 0) })
hintOn(
button("Save", "accent", function()
local name = string.gsub(nameBox.Text, "^%s*(.-)%s*$", "%1")
if name == "" then
name = App.area.folder.Name
end
if #App.area.layers == 0 then
App.status("Add some objects first, then save them as a preset.")
return
end
local rec = beginRec("Smart Scatter: Save preset")
Engine.savePreset(name, App.area.layers)
endRec(rec)
App.status(string.format("Saved %d objects as %s.", #App.area.layers, name))
App.refreshObjects()
end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Parent = saveRow }),
"Saves this area's objects and all their settings under that name. Saving an existing name replaces it."
)
gap(b, 8)
label("Share code", 13, P.text, SANS, { Parent = b })
local codeRow = box({ Size = UDim2.new(1, 0, 0, 30), Parent = b })
codeBox = new("TextBox", {
Text = "",
PlaceholderText = "Paste a code here, or press Share on a preset",
Font = SANS,
TextSize = 12,
TextColor3 = P.text,
PlaceholderColor3 = P.faint,
BackgroundColor3 = P.field,
ClearTextOnFocus = false,
TextTruncate = Enum.TextTruncate.AtEnd,
TextXAlignment = Enum.TextXAlignment.Left,
Size = UDim2.new(1, -76, 1, 0),
Parent = codeRow,
}, { corner(8), stroke(P.line), pad(8, 8, 0, 0) })
hintOn(
button("Import", "accent", function()
local preset, err = Engine.importPresetCode(codeBox.Text)
if not preset then
App.status(err, "error")
return
end
codeBox.Text = ""
App.status(string.format("Imported %s. Press Use to add its objects to this area.", preset.Name))
App.refreshObjects()
end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Parent = codeRow }),
"Saves a pasted code as a preset. Models it needs are found in this place by where they sit or their name."
)
end
local function buildLost(list)
local lost = App.area and App.area.lost
if not (lost and #lost > 0) then
return
end
local card = col(
{ BackgroundTransparency = 0, BackgroundColor3 = P.card, Parent = list },
{ corner(10), stroke(P.danger:Lerp(P.line, 0.5)), pad(12, 12, 10, 12), vlist(4) }
)
local head = para(#lost == 1 and "1 object lost its model" or (#lost .. " objects lost their model"), { Parent = card })
head.TextColor3, head.Font, head.TextSize = P.danger, SANS_B, App.textSize(13)
explain(
card,
"The model was moved, renamed or deleted, so nothing is placed. The settings are kept: select the model in the Explorer and press Use selected."
)
for i, d in lost do
local row = col({ Parent = card }, { vlist(4) })
label(tostring(d.p[#d.p]), 13, P.text, SANS_M, { Parent = row })
label("was at " .. table.concat(d.p, " › "), 11, P.faint, SANS, { Parent = row })
local acts = buttonRow(row)
button("Use selected", "accent", function()
local sel = Selection:Get()[1]
if not sel or not (sel:IsA("Model") or sel:IsA("BasePart")) then
App.status("Select the model this object should use in the Explorer first.")
return
end
if Engine.relinkLost(App.area, i, sel) then
App.status(tostring(d.p[#d.p]) .. " now uses " .. sel.Name .. ", with all its old settings.")
commit()
else
App.status("That model can't be used for an object (it needs parts).")
end
App.refreshObjects()
end, { Parent = acts })
button("Remove", "danger", function()
table.remove(App.area.lost, i)
commit()
App.refreshObjects()
end, { Parent = acts })
end
gap(list, 8)
end
local function buildEverything(list)
slider(
"Amount of everything",
0.1,
3,
function()
return G.density
end,
function(v)
G.density = v
end,
"%.2f×",
0.05,
function()
requestLive()
end,
function()
saveG()
commit()
end,
"Scales how many of every object get placed, on top of each one's own amount.",
1
).Parent =
list
slider(
"Size of everything",
0.3,
3,
function()
return App.area.size or 1
end,
function(v)
App.area.size = v
end,
"%.2f×",
0.05,
function()
requestLive()
end,
function()
commit()
end,
"Scales every object in this area at once, on top of each one's own size. Spacing grows with it.",
1
).Parent =
list
end
local function fillList(list)
buildLost(list)
if #App.area.layers == 0 then
App.emptyState(
list,
"No objects yet",
"Select models (or a folder of them) in the Explorer, then add them. Keep the originals outside the area, e.g. in ServerStorage.",
"Add selected models",
addSelected
)
return
end
buildEverything(list)
gap(list, 2)
App.segmented({ "List", "Grid" }, function()
return G.objGrid and "Grid" or "List"
end, function(v)
G.objGrid = v == "Grid"
end, function()
saveG()
App.refreshObjects()
end).Parent =
list
if G.objGrid then
local grid = new("Frame", {
BackgroundTransparency = 1,
Size = UDim2.new(1, 0, 0, 0),
AutomaticSize = Enum.AutomaticSize.Y,
Parent = list,
}, {
new("UIGridLayout", {
CellSize = UDim2.new(1 / 3, -6, 0, CELL_H),
CellPadding = UDim2.fromOffset(8, 8),
SortOrder = Enum.SortOrder.LayoutOrder,
}),
})
for i, l in App.area.layers do
layerCell(l, grid, i)
end
else
local drag = App.reorderList(function(from, to)
App.moveObject(App.area.layers[from], to)
end)
for i, l in App.area.layers do
layerRow(l, list, drag, i)
end
end
gap(list, 2)
hintOn(
button("+  Add selected models", nil, addSelected, { Parent = buttonRow(list) }),
"Select models, or a folder of them, in the Explorer. Each becomes an object you can tune."
)
end
local function fillRemoveCopies(b)
local n = App.area and Engine.removedCount(App.area) or 0
if n == 0 then
local t = para("None taken out. The Remove copies tool in the viewport's strip takes out one that looks wrong.", { Parent = b })
t.TextColor3 = P.faint
return
end
button(string.format("Bring back %d removed", n), nil, function()
App.area.removed = {}
App.applyNow(nil, "Bring back removed")
App.refreshObjects()
end, { Parent = buttonRow(b) })
end
local function liveBox(parent, fill)
local holder = col({ Parent = parent }, { vlist(8) })
App.ui.live = App.ui.live or {}
table.insert(App.ui.live, { holder = holder, fill = fill })
return holder
end
App.refreshObjects = function()
if App.active and not (App.area and table.find(App.area.layers, App.active)) then
App.selectObject(nil)
return
end
if App.area and (App.area.relinked or 0) > 0 then
App.status(
string.format(
"Found %d model%s in a new place and reconnected %s.",
App.area.relinked,
App.area.relinked == 1 and "" or "s",
App.area.relinked == 1 and "it" or "them"
)
)
App.area.relinked = 0
App.saveArea()
end
local boxes = App.ui.live or {}
if #boxes > 0 then
local sc = App.scroll
local at = sc and sc.Parent and sc.CanvasPosition
if at then
task.defer(function()
if sc.Parent then
sc.CanvasPosition = at
end
end)
end
table.clear(rowRefs)
for _, lb in boxes do
for _, d in lb.holder:GetDescendants() do
if d:IsA("ViewportFrame") then
d.Parent = nil
end
end
for _, ch in lb.holder:GetChildren() do
if ch:IsA("GuiObject") then
ch:Destroy()
end
end
if App.area then
lb.fill(lb.holder)
end
end
end
App.refreshCounts()
end
App.refreshCounts = function()
App.refreshPerf()
App.checkShape()
if App.ui.outlinerCount and App.ui.outlinerCount.Parent then
App.ui.outlinerCount.Text = App.lastTotal > 0 and num(App.lastTotal) or ""
end
local most = 1
for l in rowRefs do
most = math.max(most, (l.s.enabled and App.lastCounts[l]) or 0)
end
for l, r in rowRefs do
if r.bar then
local share = l.s.enabled and (App.lastCounts[l] or 0) / most or 0
tween(r.bar, App.MED, { Size = UDim2.fromScale(share, 1) })
end
local n = App.lastCounts[l]
local what = Engine.isLine(l) and ("Along " .. (l.s.follow == "Spline" and "path" or string.lower(l.s.follow))) or l.type
local placed = (n and l.s.enabled) and ("  ·  " .. num(n) .. " placed") or ""
if r.sub then
r.sub.Text = (l.s.enabled and what or (what .. "  ·  off")) .. placed
end
if r.kind then
r.kind.Text = l.s.enabled and (what .. placed .. (l.s.locked and " · locked" or "")) or "Off"
end
if r.count then
r.count.Text = not l.s.enabled and "Off" or n and (num(n) .. " placed") or what
end
end
if App.ui.genBtn and not App.busy() then
local ok = canGenerate()
local failed = ok and App.failure ~= nil
App.ui.genBtn.Text = failed and "Try again" or (ok and App.hasPending()) and "Apply changes" or "Generate"
tween(App.ui.genBtn, FAST, {
BackgroundColor3 = failed and P.danger or ok and P.accent or P.raised,
TextColor3 = ok and P.onAccent or P.faint,
})
end
end
App.showObject = showObject
App.addSelected = addSelected
App.liveBox = liveBox
App.buildBiomes = buildBiomes
App.buildReport = buildReport
App.objectRules = function(l, parent)
layerRules(l, parent, controls(l))
end
App.objectList = function(parent)
return liveBox(parent, fillList)
end
App.objectInspector = function(parent)
App.ui.inspector = liveBox(parent, function(h)
if App.active then
objectPage(App.active, h)
end
end)
return App.ui.inspector
end
App.presetsBox = function(parent)
return liveBox(parent, buildPresets)
end
App.removeCopiesBox = function(parent)
return liveBox(parent, fillRemoveCopies)
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
if App.reapplyHidden then
App.reapplyHidden(m)
end
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
hide = true,
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
local last
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
last = nil
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
local RUN = {}
RUN.drop = {
min = 1,
name = function()
return "Drop to ground"
end,
run = function(list, p)
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
if p.lean and normal.Y > 0.2 then
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
end,
}
RUN.align = {
min = 2,
name = function(p)
return "Align " .. p.axis .. " " .. string.lower(p.where)
end,
run = function(list, p)
local boxes = {}
for i, inst in list do
boxes[i] = boxOf(inst)
end
for i, d in Engine.alignMoves(boxes, p.axis, p.where) do
moveBy(list[i], d)
end
return string.format("Lined up %d on %s (%s).", #list, p.axis, string.lower(p.where == "Center" and "centre" or p.where))
end,
}
RUN.distribute = {
min = 3,
name = function(p)
return "Distribute " .. p.axis
end,
run = function(list, p)
local boxes = {}
for i, inst in list do
boxes[i] = boxOf(inst)
end
for i, d in Engine.distributeMoves(boxes, p.axis, p.by) do
moveBy(list[i], d)
end
return string.format("Spaced %d evenly on %s, the outer two staying put.", #list, p.axis)
end,
}
RUN.random = {
min = 1,
name = function()
return "Randomize"
end,
run = function(list, p)
local r = Engine.randomTurns(#list, p.turn, p.size, p.seed)
for i, inst in list do
local b = boxOf(inst)
local base = Vector3.new((b.min.X + b.max.X) / 2, b.min.Y, (b.min.Z + b.max.Z) / 2)
turnAbout(inst, base, r[i].yaw)
scaleBy(inst, r[i].scale)
if p.keep then
moveBy(inst, Vector3.new(0, b.min.Y - boxOf(inst).min.Y, 0))
end
end
return string.format("Gave %d a random turn and size. Press again for another.", #list)
end,
}
local function poses(list)
local t = {}
for i, inst in list do
t[i] = { cf = inst:GetPivot(), scale = inst:IsA("Model") and inst:GetScale() or nil, size = inst:IsA("BasePart") and inst.Size or nil }
end
return t
end
local function restore(list, before)
for i, inst in list do
local was = before[i]
if was.scale then
inst:ScaleTo(was.scale)
elseif was.size then
inst.Size = was.size
end
inst:PivotTo(was.cf)
end
end
local function lastAction()
if not last then
return nil
end
for _, inst in last.list do
if not inst.Parent then
last = nil
return nil
end
end
return last
end
App.lastEdit = lastAction
local function perform(kind, p, again)
local spec = RUN[kind]
local list = again and again.list or items()
if #list < spec.min then
App.status(
spec.min > 1 and string.format("Select at least %d models (in the Explorer or the viewport) first.", spec.min)
or "Select the models to work on (in the Explorer or the viewport) first."
)
return false
end
local what = spec.name(p)
local rec = beginRec("Smart Scatter: " .. what .. (again and " (adjusted)" or ""))
local before = again and again.before or poses(list)
local ok, said = pcall(function()
if again then
restore(list, before)
end
return spec.run(list, p)
end)
endRec(rec, not ok)
if not ok then
warn("[Smart Scatter] " .. tostring(said))
App.status(what .. " didn't work: " .. tostring(said), "error")
return false
end
last = { kind = kind, p = p, list = list, before = before }
App.status(said)
local open = App.currentTab and App.currentTab()
if open and open.id == "edit" and not App.settingsOpen then
task.defer(App.rebuildAll)
end
return true
end
App.adjustLastEdit = function(changes)
local l = lastAction()
if not l then
return false
end
local p = table.clone(l.p)
for k, v in changes do
p[k] = v
end
return perform(l.kind, p, l)
end
local seed = 1
App.dropToGround = function()
return perform("drop", { lean = G.editLean })
end
App.alignSelection = function(axis, where)
return perform("align", { axis = axis, where = where })
end
App.distributeSelection = function(axis, by)
return perform("distribute", { axis = axis, by = by })
end
App.randomizeSelection = function()
seed += 1
return perform("random", { turn = G.editTurn, size = G.editSize, keep = G.editKeep, seed = seed + os.clock() * 1000 })
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
local l = lastAction()
if l then
cs.add({
id = "editlast",
title = "Adjust: " .. RUN[l.kind].name(l.p),
icon = "refresh",
sub = string.format("Change how it was done to those %d", #l.list),
keys = "adjust last again redo tweak",
build = function(b)
local p = l.p
local function set(key)
return function(v)
if p[key] ~= v then
App.adjustLastEdit({ [key] = v })
end
end
end
if l.kind == "align" or l.kind == "distribute" then
segmented(AXES, function()
return p.axis
end, function(v)
set("axis")(v)
end).Parent = b
end
if l.kind == "align" then
local names = { Min = "Lowest", Center = "Middle", Max = "Highest" }
local back = { Lowest = "Min", Middle = "Center", Highest = "Max" }
segmented({ "Lowest", "Middle", "Highest" }, function()
return names[p.where]
end, function(v)
set("where")(back[v])
end).Parent =
b
elseif l.kind == "distribute" then
segmented({ "Centers", "Gaps" }, function()
return p.by
end, function(v)
set("by")(v)
end).Parent =
b
elseif l.kind == "random" then
local turn, size = p.turn, p.size
slider(
"Turn",
0,
180,
function()
return turn
end,
function(v)
turn = v
end,
"±%d°",
5,
nil,
function()
set("turn")(turn)
end,
"How far each one may turn, either way.",
180
).Parent =
b
slider(
"Size",
0,
0.9,
function()
return size
end,
function(v)
size = v
end,
"±%.0f%%",
0.05,
nil,
function()
set("size")(size)
end,
"How much bigger or smaller each one may get.",
0.15
).Parent =
b
switchRow("Keep on the ground", function()
return p.keep
end, function(v)
set("keep")(v)
end, nil, "Their undersides stay where they were as they grow or shrink.").Parent =
b
hintOn(
button("Another roll", nil, function()
seed += 1
App.adjustLastEdit({ seed = seed + os.clock() * 1000 })
end, { Parent = buttonRow(b) }),
"The same models, another random turn and size, from how they stood before."
)
elseif l.kind == "drop" then
switchRow("Lean with the slope", function()
return p.lean
end, function(v)
set("lean")(v)
end, nil, "On: each one tilts to stand square on the ground under it. Off: they stay upright.").Parent =
b
end
App.explain(b, "They're put back as they stood, then it's done again your way. Each change is one Ctrl+Z step.")
end,
})
end
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
switchRow(
"Compact panel",
function()
return G.compact == true
end,
function(v)
G.compact = v
saveG()
task.defer(App.rebuildAll)
end,
nil,
"Leaves out the search box over the outliner and keeps the outliner shorter, so the page below has more room. Space still searches every action."
).Parent =
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
"Fixed: Shift erases while painting and raises a path point while dragging; Ctrl+Z undoes; a quick right-click closes a polygon. A plain key still works with Shift held; with Ctrl or Alt held it's Studio's unless you bound that combo.",
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
its room first). The eye on a row hides what it placed (for you, this session); the padlock locks it. With many
things a filter box narrows the list as you type. The whole list folds away, and scrolls past a few rows.
Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]
return function(App)
local G, saveG, P, SANS, SANS_M, SANS_B = App.G, App.saveG, App.P, App.SANS, App.SANS_M, App.SANS_B
local new, box, col, label, vlist, corner, pad = App.new, App.box, App.col, App.label, App.vlist, App.corner, App.pad
local ROW, CHILD, MAX_H = 28, 24, 190
local THUMB = 18
local FILTER_FROM = 8
local filter = ""
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
local quiet = {}
local function toggle(iconName, on, hint, order, click)
local t = new("TextButton", {
Text = "",
AutoButtonColor = false,
BackgroundTransparency = 1,
Size = UDim2.fromOffset(20, 22),
LayoutOrder = order,
Visible = on or sel,
Parent = right,
})
local ic = App.icon(iconName, 12, on and P.accent or P.faint)
ic.AnchorPoint, ic.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
ic.Parent = t
t.MouseEnter:Connect(function()
App.setIconColor(ic, P.text)
end)
t.MouseLeave:Connect(function()
App.setIconColor(ic, on and P.accent or P.faint)
end)
t.MouseButton1Click:Connect(click)
App.hintOn(t, hint)
if not on and not sel then
table.insert(quiet, t)
end
return t
end
if spec.hide and thing.folder then
local off = App.isHidden(thing.folder)
toggle(
off and "eyeOff" or "eye",
off,
off and "Hidden: what it placed isn't drawn (for you, until Studio closes). Click to show it." or "Hide what it placed.",
2,
function()
App.setHidden(thing.folder, not off)
App.rebuildAll()
App.status(
off and (name .. " is shown again.")
or (name .. " is hidden: its copies aren't drawn. Only for you and this session; nothing in the place changed.")
)
end
)
end
if spec.lock then
local locked = spec.lock.get(thing)
toggle(
locked and "lock" or "unlock",
locked,
locked and "Locked: nothing here regenerates or repaints. Click to unlock." or "Lock it: nothing here changes until it's unlocked.",
2,
function()
spec.lock.toggle(thing)
end
)
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
for _, t in quiet do
t.Visible = true
end
end)
b.MouseLeave:Connect(function()
b.BackgroundTransparency = 1
for _, t in quiet do
t.Visible = false
end
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
local made = {}
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
table.insert(made, b)
end
return made
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
local maxH = G.compact and math.floor(MAX_H * 0.6) or MAX_H
local order, any, selRow = 0, false, nil
local rows = {}
local total = 0
for _, spec in App.thingKinds() do
total += #spec.list()
end
if total < FILTER_FROM then
filter = ""
end
for _, spec in App.thingKinds() do
local things = thingsOf(spec)
local drag = spec.reorder and App.reorderList(function(from, to)
App.moveThing(things[from], to)
end) or nil
for index, thing in things do
order += 100
any = true
local row = thingRow(list, spec, thing, order, index, #things, drag)
local entry = { row = row, name = string.lower(thing.folder and thing.folder.Name or spec.title), kids = {} }
table.insert(rows, entry)
if App.sameThing(thing, App.selected) then
selRow = row
if App.area and (thing.kind == "Zone" or thing.kind == "Path") and #App.area.layers > 0 then
entry.kids = objectRows(list, order)
end
end
end
end
if not any then
local t = App.para("Nothing yet. + makes a zone, a path or a keep-clear zone.", { Parent = list })
t.TextColor3 = P.faint
end
local function applyFilter()
local want = string.lower(filter)
for _, e in rows do
local show = want == "" or string.find(e.name, want, 1, true) ~= nil
e.row.Visible = show
for _, k in e.kids do
k.Visible = show
end
end
end
if total >= FILTER_FROM then
local tb = new("TextBox", {
Text = filter,
PlaceholderText = "Filter by name",
PlaceholderColor3 = P.faint,
Font = SANS,
TextSize = 12,
TextColor3 = P.text,
BackgroundColor3 = P.field,
ClearTextOnFocus = false,
TextXAlignment = Enum.TextXAlignment.Left,
Size = UDim2.new(1, 0, 0, 24),
Parent = wrap,
}, { corner(6), pad(8, 8, 0, 0) })
tb.LayoutOrder = scroll.LayoutOrder
scroll.LayoutOrder += 1
tb:GetPropertyChangedSignal("Text"):Connect(function()
filter = tb.Text
applyFilter()
end)
App.ui.outlinerFilter = tb
applyFilter()
end
local function fit()
local h = list.AbsoluteSize.Y
scroll.Size = UDim2.new(1, 0, 0, math.min(h, maxH))
end
list:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
fit()
if selRow then
task.defer(function()
if selRow.Parent then
local top = selRow.AbsolutePosition.Y - list.AbsolutePosition.Y
if top + ROW > maxH then
scroll.CanvasPosition = Vector2.new(0, top - maxH / 2)
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
here; pick one of its objects and its Object tab opens. The tabs are a column of icons beside the page; the line
over the page names what's open.
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
App.TAB_COL = 38
local TAB = 30
App.buildTabColumn = function(parent)
local open, tabs = App.currentTab()
local column = new("ScrollingFrame", {
BackgroundTransparency = 1,
Size = UDim2.new(0, App.TAB_COL, 1, 0),
CanvasSize = UDim2.new(),
AutomaticCanvasSize = Enum.AutomaticSize.Y,
ScrollBarThickness = 0,
ScrollingDirection = Enum.ScrollingDirection.Y,
ZIndex = 2,
Parent = parent,
}, {
new("UIListLayout", {
HorizontalAlignment = Enum.HorizontalAlignment.Center,
Padding = UDim.new(0, 4),
SortOrder = Enum.SortOrder.LayoutOrder,
}),
App.pad(0, 0, 10, 10),
})
App.ui.tabRow = column
App.ui.tabs = {}
for i, t in tabs do
local on = t == open and not App.searching()
local b = new("TextButton", {
Text = "",
AutoButtonColor = false,
BackgroundColor3 = on and P.accentSoft or P.hover,
BackgroundTransparency = on and 0 or 1,
Size = UDim2.fromOffset(TAB, TAB),
LayoutOrder = i,
ZIndex = 2,
Parent = column,
}, { App.corner(8) })
local ic = App.icon(t.icon, 15, on and P.accent or P.dim)
ic.AnchorPoint, ic.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
ic.ZIndex = 3
ic.Parent = b
if on then
box({
BackgroundTransparency = 0,
BackgroundColor3 = P.accent,
AnchorPoint = Vector2.new(1, 0.5),
Position = UDim2.new(1, 3, 0.5, 0),
Size = UDim2.fromOffset(2, TAB - 12),
ZIndex = 3,
Parent = b,
}, { App.corner(1) })
else
b.MouseEnter:Connect(function()
b.BackgroundTransparency = 0
App.setIconColor(ic, P.text)
end)
b.MouseLeave:Connect(function()
b.BackgroundTransparency = 1
App.setIconColor(ic, P.dim)
end)
end
b.MouseButton1Click:Connect(function()
App.openTab(t.id)
end)
App.hintOn(b, t.title)
App.ui.tabs[t.id] = b
end
return column
end
App.buildCrumb = function(parent)
local open = App.currentTab()
local row = box({ Size = UDim2.new(1, 0, 0, 22), Parent = parent })
local left = box({ Size = UDim2.new(1, -96, 1, 0), ClipsDescendants = true, Parent = row }, { hlist(6) })
local function word(text, color, font, click)
local w = new(click and "TextButton" or "TextLabel", {
Text = text,
Font = font,
TextSize = 12,
TextColor3 = color,
TextTruncate = Enum.TextTruncate.AtEnd,
BackgroundTransparency = 1,
Size = UDim2.fromOffset(0, 22),
AutomaticSize = Enum.AutomaticSize.X,
Parent = left,
}, { new("UISizeConstraint", { MaxSize = Vector2.new(130, 22) }) })
if click then
w.AutoButtonColor = false
w.MouseEnter:Connect(function()
w.TextColor3 = P.accent
end)
w.MouseLeave:Connect(function()
w.TextColor3 = color
end)
w.MouseButton1Click:Connect(click)
end
return w
end
local sel, active = App.selected, App.active
if App.searching() then
word("Search results", P.dim, SANS_M)
elseif not sel then
word("Nothing selected", P.faint, SANS_M)
else
local spec = App.kindSpec(sel.kind)
local name = sel.folder and sel.folder.Name or (spec and spec.title or sel.kind)
if active then
App.hintOn(
word(name, P.dim, SANS_M, function()
App.selectObject(nil)
end),
"Back to " .. name .. " itself."
)
local sep = App.icon("right", 9, P.faint)
sep.AnchorPoint, sep.Position = Vector2.new(0, 0.5), UDim2.fromScale(0, 0.5)
sep.Parent = box({ Size = UDim2.fromOffset(9, 22), Parent = left })
word(active.inst.Name, P.text, SANS_B)
else
word(name, P.text, SANS_B)
end
end
if open and not App.searching() then
label(string.upper(open.title), 11, P.faint, SANS_B, {
AnchorPoint = Vector2.new(1, 0),
Position = UDim2.new(1, 0, 0, 0),
Size = UDim2.fromOffset(92, 22),
TextXAlignment = Enum.TextXAlignment.Right,
Parent = row,
})
end
App.ui.crumb = row
return row
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

return MODULES
