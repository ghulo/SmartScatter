-- GENERATED part 2 of the flattened release by tools/tree.py: edit the modules, not this.
local MODULES = {}

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
label(
string.format("%s cop%s · %d part%s", num(#list), #list == 1 and "y" or "ies", k.parts, k.parts == 1 and "" or "s"),
11,
P.dim,
SANS,
{ Position = UDim2.fromOffset(40, 18), Size = UDim2.new(1, -170, 0, 16), Parent = row }
)
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
label(
string.format("%d kinds · %s copies · in %s", #kinds, num(copies), scope),
12,
P.faint,
SANS_B,
{ Size = UDim2.new(1, 0, 0, 20), Parent = b }
)
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
-- #module App/Panel/Tabs/Scatter
MODULES["App/Panel/Tabs/Scatter"] = (function()
--[[
Smart Scatter — Scatter tab: what fills the area. The objects and how much of everything, or one object's rules
when it's open; then the look of the whole area (pattern, colour zones, edges, wind), biomes, presets and the
performance report under More options.
Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]
return function(App)
local vlist, col = App.vlist, App.col
local function buildObject(page)
App.pageHead(page, "All objects", nil, function()
App.showObject(nil)
end)
App.objectInspector(col({ Parent = page }, { vlist(10) }))
end
App.buildScatterTab = function(page)
local a = App.area
if a and App.expanded and not App.searching() then
buildObject(page)
return
end
local cs = App.cards(page, "scatter")
local kind = a and App.kindOf(a)
if kind == "Clear" then
cs.add({
id = "clearzone",
title = "Keep-clear zone",
icon = "clear",
sub = "Nothing from any area goes here: spawns, doorways, a quest NPC's spot",
build = function(b)
App.goNote(b, "This zone holds no objects. Paint where to keep clear on the Brush tab.", "Paint the zone", "Brush")
end,
})
return
end
local shaped = a and ((a.count or 0) > 0 or App.hasPath())
cs.add({
id = "objects",
title = "Objects",
icon = "layers",
sub = "The models that fill this area, and how much of everything",
keys = "add models amount size everything list lost",
build = function(b)
if a and not shaped then
if kind == "Path" then
App.goNote(b, "Draw the path first, on the Map tab. Then add what lines it.", "Draw the path", "Map")
else
App.goNote(b, "Paint the ground first, on the Brush tab. Then add what fills it.", "Paint the area", "Brush")
end
end
if a then
App.objectList(b)
else
App.emptyState(b, "No area yet", "Make a scatter area or a path first: the + next to the area picker.")
end
App.ui.step2Card = b.Parent
end,
})
if not a then
return
end
local empty = #a.layers == 0
cs.add({
id = "biomes",
title = "Start from a biome",
sub = "A ready mix of objects made from your models",
keys = "forest meadow desert town sample models",
more = not empty,
build = App.buildBiomes,
})
cs.add({
id = "pattern",
title = "Pattern",
sub = "Where everything thickens and thins together",
keys = "groves natural islands veins spots bands strength noise patches",
more = true,
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
cs.add({
id = "presets",
title = "Presets",
keys = "save share code import reuse",
more = true,
build = App.presetsBox,
})
cs.add({
id = "performance",
title = "Performance",
sub = "Which objects cost the most parts",
keys = "report parts meshes heavy lag simplify",
more = true,
build = App.buildReport,
})
if App.searching() then
for i, l in a.layers do
local holder = col({ LayoutOrder = 200000 + i, Parent = page }, { vlist(10) })
App.label(l.inst.Name, 13, App.P.text, App.SANS_B, { Parent = holder })
local before = App.cardCount
App.objectRules(l, holder)
if App.cardCount == before then
holder:Destroy()
end
end
end
end
end
end)()
-- #module App/Panel/Tabs/Brush
MODULES["App/Panel/Tabs/Brush"] = (function()
--[[
Smart Scatter — Brush tab: working by hand in the viewport. Paint the area's ground, brush one object more or
less (or place copies exactly), take single copies out; then which surfaces painting sticks to and cleaning up
the painted edge under More options.
Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]
return function(App)
local Engine, P, SANS = App.Engine, App.P, App.SANS
local label, hintOn = App.label, App.hintOn
local picked
local function paintable(l)
return not (Engine.isLine(l) and l.s.follow == "Spline")
end
local function buildObjectBrush(b)
local list = {}
for _, l in App.area.layers do
if paintable(l) then
table.insert(list, l)
end
end
if #list == 0 then
App.goNote(
b,
#App.area.layers == 0 and "Add objects on the Scatter tab first." or "Objects along a path can't be brushed.",
#App.area.layers == 0 and "Add objects" or nil,
"Scatter"
)
return
end
if not table.find(list, picked) then
picked = App.paintLayer and table.find(list, App.paintLayer) and App.paintLayer or list[1]
end
for _, l in list do
local on = picked == l
local row = App.new("TextButton", {
Text = "",
AutoButtonColor = false,
BackgroundColor3 = on and P.accentSoft or P.raised,
Size = UDim2.new(1, 0, 0, 48),
Parent = b,
}, { App.corner(10) })
local st = App.stroke(on and P.accentLine or P.line)
st.Parent = row
local th = App.thumbnail(l.inst, 38)
th.Position = UDim2.fromOffset(5, 5)
th.Parent = row
label(l.inst.Name .. (#l.variants > 1 and ("  +" .. (#l.variants - 1)) or ""), 13, on and P.accent or P.text, App.SANS_B, {
Position = UDim2.fromOffset(52, 7),
Size = UDim2.new(1, -60, 0, 18),
Parent = row,
})
local n = App.lastCounts[l]
local bits = { n and (App.num(n) .. " placed") or l.type }
if l.pins then
table.insert(bits, #l.pins .. " by hand")
end
if l.paint then
table.insert(bits, "painted")
end
label(table.concat(bits, " · "), 11, P.dim, SANS, { Position = UDim2.fromOffset(52, 25), Size = UDim2.new(1, -60, 0, 16), Parent = row })
if not on then
row.MouseEnter:Connect(function()
row.BackgroundColor3 = P.hover
end)
row.MouseLeave:Connect(function()
row.BackgroundColor3 = P.raised
end)
end
App.pressable(row, 0.985)
row.MouseButton1Click:Connect(function()
if picked ~= l then
if App.LAYER_MODES[App.mode] then
App.setMode(App.mode, l)
end
picked = l
App.rebuildAll()
end
end)
hintOn(row, "Brush " .. l.inst.Name .. ".")
end
App.buildLayerPaint(picked, {
add = function(spec)
spec.build(b)
end,
})
end
App.buildBrushTab = function(page)
local a = App.area
local cs = App.cards(page, "brush")
local kind = a and App.kindOf(a)
if kind == "Path" then
cs.add({
id = "pathbrush",
title = "Draw the path",
icon = "spline",
sub = "Paths are drawn, not painted",
keys = "draw path spline points",
build = function(b)
App.goNote(b, "Draw and shape the path on the Map tab.", "Go to Map", "Map")
end,
})
else
local painted = a and (a.count or 0) > 0
local card = cs.add({
id = "paint",
title = kind == "Clear" and "Paint the zone" or "Paint the area",
icon = kind == "Clear" and "clear" or "brush",
sub = kind == "Clear" and "Where nothing from any area may go"
or painted and string.format("%s studs² painted. Keep painting, or tune what fills it.", App.num(a.count * a.cell * a.cell))
or "Pick a tool, then paint the ground in the viewport",
keys = "paint ground brush lasso box polygon fill erase all delete size shape reach selected parts",
build = App.buildPaintTools,
})
App.ui.step1Card = card
end
if a and kind ~= "Clear" then
if kind ~= "Path" then
cs.add({
id = "objectbrush",
title = "Paint one object",
sub = "More, less or none of it where you brush; or place copies exactly",
keys = "more less erase reset place pins object brush by hand",
build = buildObjectBrush,
})
end
cs.add({
id = "removecopies",
title = "Remove single copies",
sub = "Click a copy that looks wrong to take it out; it stays out",
keys = "remove delete copy copies bring back",
build = App.removeCopiesBox,
})
end
if kind ~= "Path" then
cs.add({
id = "paintfilter",
title = "Paint only on",
sub = "Painting and erasing stick to these surfaces",
keys = "filter surfaces grass road rock sand snow",
more = true,
build = App.buildPaintFilter,
})
if a then
cs.add({
id = "tidy",
title = "Tidy the edge",
sub = "Fill holes, smooth, grow or shrink what's painted",
keys = "fill holes smooth grow shrink cleanup",
more = true,
build = App.buildTidy,
})
end
end
end
end
end)()
-- #module App/Panel/Tabs/Map
MODULES["App/Panel/Tabs/Map"] = (function()
--[[
Smart Scatter — Map tab: the map itself. The path (drawing it, its curve and its road); scanning a finished map
for kinds and keeping its originals in a snapshot; and telling the scan what the parts of the map are.
Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]
return function(App)
App.buildMapTab = function(page)
local a = App.area
local cs = App.cards(page, "map")
local kind = a and App.kindOf(a)
local drawn = App.hasPath()
if a and kind ~= "Clear" then
local isPath = kind == "Path"
local card = cs.add({
id = "path",
title = isPath and "Draw the path" or "Path through this area",
icon = "spline",
tag = not isPath and "Optional" or nil,
sub = drawn and (isPath and "Click to add more points, or drag one to move it" or "Objects set to follow it line it")
or (isPath and "Click in the viewport to place points" or "A road, fence or row of lamps along a curve you draw"),
keys = "draw path spline points vertex corner branch loop clear shape preset square rectangle triangle hexagon octagon circle subdivide fence",
build = App.buildDrawTools,
})
if isPath then
App.ui.step1Card = card
end
if drawn then
cs.add({
id = "curve",
title = "Curve",
sub = "The strip beside it, and what it sticks to",
keys = "strip width snap surfaces walls closed loop",
build = App.buildCurve,
})
cs.add({
id = "road",
title = "Road",
sub = "A solid road or path down the middle",
keys = "road asphalt dirt style width thickness",
build = App.buildRoad,
})
end
end
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
icon = "refresh",
sub = "Replace every copy of a kind with another model or a mix",
keys = "swap replace model mix kind copies preview try",
build = App.buildSwap,
})
cs.add({
id = "layout",
title = "Improve layout",
icon = "layers",
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
if a then
cs.add({
id = "scanfix",
title = "Fix what the scan sees",
keys = "mark road path building water rescan",
more = kind ~= "Clear",
build = App.buildScanFix,
})
end
end
end
end)()
-- #module App/Panel/Tabs/Settings
MODULES["App/Panel/Tabs/Settings"] = (function()
--[[
Smart Scatter — Settings tab: the plugin's own settings, the same in every area. Look and text size, the
viewport overlay, game-ready output and the tour; shortcuts under More options.
Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]
return function(App)
local G, saveG, P, SANS, SANS_B = App.G, App.saveG, App.P, App.SANS, App.SANS_B
local box, label, para, hlist = App.box, App.label, App.para, App.hlist
local hintOn, switchRow, button, buttonRow, commit = App.hintOn, App.switchRow, App.button, App.buttonRow, App.commit
local function buildLook(b)
local swatches = App.chipGrid(b, 5, 32)
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
"While painting, drawing a path or brushing an object, the world greys and dims a little, a thin frame runs round the viewport and the corner says what the tool is doing, like Blender's edit mode."
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
"Live previews as boxes",
"liveBoxes",
"With Live on, changes show as a see-through box per copy: quick, even on big areas. Generate places the real models. Off: Live places the real models every time."
)
box({ Size = UDim2.new(1, 0, 0, 4), Parent = b })
App.ui.perf = para("", { Parent = b })
App.refreshPerf()
end
local function buildShortcuts(b)
App.explain(b, "Click a key to change it, then press the new one (Esc keeps the old). A key already in use swaps over.")
local group
for _, a in App.KEYMAP do
if a.group ~= group then
group = a.group
label(group, 12, P.dim, SANS_B, { Size = UDim2.new(1, 0, 0, 24), Parent = b })
end
local row = box({ Size = UDim2.new(1, 0, 0, 32), Parent = b })
label(a.label, 13, P.text, SANS, { Size = UDim2.new(1, -96, 1, 0), Parent = row })
local key = button(App.keyText(a.id), nil, nil, {
AnchorPoint = Vector2.new(1, 0.5),
Position = UDim2.new(1, 0, 0.5, 0),
AutomaticSize = Enum.AutomaticSize.None,
Size = UDim2.fromOffset(84, 26),
Font = SANS_B,
Parent = row,
})
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
"Fixed: Shift erases while painting and raises a path point while dragging; Ctrl+Z undoes; a quick right-click closes a polygon or deletes a path point.",
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
local function buildAbout(b)
hintOn(
button("Replay the tour", nil, function()
App.startTour()
end, { Parent = buttonRow(b) }),
"A three-minute walk through everything: what it's for, areas, paths, objects and their rules, placing and finishing."
)
local about = box({ Size = UDim2.new(1, 0, 0, 40), Parent = b }, { hlist(10) })
App.new("ImageLabel", { Image = App.LOGO.mark, BackgroundTransparency = 1, Size = UDim2.fromOffset(32, 32), Parent = about })
label("Smart Scatter  v" .. tostring(App.ctx.version or "dev") .. "  ·  made by Ghulo", 12, P.faint, SANS, {
Size = UDim2.new(1, -42, 1, 0),
Parent = about,
})
end
App.buildSettingsTab = function(page)
local cs = App.cards(page, "settings")
cs.add({
id = "look",
title = "Look",
sub = "Accent colour and text size",
keys = "theme accent colour color text size font",
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
sub = "A walk through everything, and the version",
keys = "tour help version",
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
-- #module App/Panel/Shell
MODULES["App/Panel/Shell"] = (function()
--[[
Smart Scatter — Shell: the panel around the tabs. The header (area picker), the tab bar (Scatter · Brush · Map ·
Settings), the search box, the page that scrolls under them, the bar pinned to the bottom (Generate, Live
update, Shuffle, Undo) and toasts; and the whole-panel rebuild. Each tab is its own module in Panel/Tabs.
Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]
return function(App)
local FAST, MED, tween, beginRec, endRec, track = App.FAST, App.MED, App.tween, App.beginRec, App.endRec, App.track
local G, saveG, num, P, makePalette, SANS, SANS_B = App.G, App.saveG, App.num, App.P, App.makePalette, App.SANS, App.SANS_B
local new, corner, pad, vlist, hlist, box, col, label = App.new, App.corner, App.pad, App.vlist, App.hlist, App.box, App.col, App.label
local para, hintOn, rebuildOverlay, saveArea, canGenerate = App.para, App.hintOn, App.rebuildOverlay, App.saveArea, App.canGenerate
local runGenerate, commit, buildHeader = App.runGenerate, App.commit, App.buildHeader
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
Size = UDim2.new(1, -174, 1, 0),
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
App.ui.genBtn.MouseButton1Click:Connect(function()
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
end)
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
return "Places the real models now. With Live on, changes show as see-through boxes first; this turns them into the models."
end)
local live = new("TextButton", {
Text = "",
AutoButtonColor = false,
Size = UDim2.fromOffset(78, 38),
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
live.MouseButton1Click:Connect(function()
G.live = not G.live
saveG()
liveLook()
if G.live then
commit()
end
App.status(
G.live
and (G.liveBoxes and "Live preview on: changes show as see-through boxes. Generate places the real models." or "Live update on: every change rebuilds as you make it.")
or "Live off: changes wait for Generate."
)
end)
hintOn(
live,
"On: every change shows right away as see-through boxes, a quick preview; Generate places the real models. Off: changes wait for Generate."
)
local shuffle = App.iconButton("refresh", "Shuffle: a new random layout with the same settings. Ctrl+Z goes back.", App.shuffle, false, 38)
shuffle.LayoutOrder = 2
shuffle.Parent = right
local undo = App.iconButton("undo", "Undo the last step (Ctrl+Z)", function()
local chs = App.ChangeHistoryService
local ok, can = pcall(chs.GetCanUndo, chs)
if ok and can == false then
App.status("Nothing to undo.")
return
end
pcall(chs.Undo, chs)
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
local TABS = {
{ name = "Scatter", icon = "layers", hint = "What fills the area: objects, their rules, pattern and presets.", build = "buildScatterTab" },
{ name = "Brush", icon = "brush", hint = "Work by hand: paint the ground, brush one object, remove copies.", build = "buildBrushTab" },
{
name = "Map",
icon = "spline",
hint = "The path and its road; scanning a finished map, swapping its models, seasons and the snapshot.",
build = "buildMapTab",
},
{ name = "Settings", icon = "settings", hint = "The plugin's look, output and shortcuts.", build = "buildSettingsTab" },
}
local TAB = {}
for _, t in TABS do
TAB[t.name] = t
end
local OWNER =
{ Paint = "Brush", Erase = "Brush", More = "Brush", Less = "Brush", Clear = "Brush", Place = "Brush", Remove = "Brush", Spline = "Map" }
local function homeTab()
local a = App.area
if not a then
return "Scatter"
end
local kind = App.kindOf(a)
if kind == "Path" then
return App.hasPath() and "Scatter" or "Map"
end
if kind == "Clear" or (a.count or 0) == 0 then
return "Brush"
end
return "Scatter"
end
local searchText = ""
local function clearSearch()
searchText = ""
App.setSearch("")
end
App.goPage = function(name)
if G.page == name and not App.searching() then
return
end
clearSearch()
G.page = name
saveG()
local owner = OWNER[App.mode]
if owner and owner ~= (TAB[name] and name or homeTab()) then
App.setMode("Off")
end
App.rebuildAll()
end
local function buildTabs(parent)
local bar = box({ BackgroundTransparency = 0, BackgroundColor3 = P.raised, Size = UDim2.new(1, 0, 0, 36), Parent = parent }, {
corner(10),
pad(3, 3, 3, 3),
new("UIGridLayout", {
CellSize = UDim2.new(1 / #TABS, -3, 1, 0),
CellPadding = UDim2.fromOffset(3, 0),
SortOrder = Enum.SortOrder.LayoutOrder,
}),
})
App.ui.tabs = {}
local fits = {}
for i, t in TABS do
local on = G.page == t.name and not App.searching()
local b = new("TextButton", {
Text = "",
AutoButtonColor = false,
BackgroundTransparency = on and 0 or 1,
BackgroundColor3 = P.card,
LayoutOrder = i,
Parent = bar,
}, { corner(8) })
if on then
App.stroke(P.accentLine).Parent = b
end
local row = box({ Size = UDim2.fromScale(1, 1), Parent = b }, {
new("UIListLayout", {
FillDirection = Enum.FillDirection.Horizontal,
HorizontalAlignment = Enum.HorizontalAlignment.Center,
VerticalAlignment = Enum.VerticalAlignment.Center,
Padding = UDim.new(0, 5),
}),
})
local fg = on and P.accent or P.dim
local ic = App.icon(t.icon, 13, fg)
ic.Parent = row
local text = label(t.name, 12, fg, SANS_B, { Size = UDim2.fromOffset(0, 16), AutomaticSize = Enum.AutomaticSize.X, Parent = row })
fits[ic] = text
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
App.goPage(t.name)
end)
hintOn(b, t.hint)
App.ui.tabs[t.name] = b
end
local function fit()
local cell = bar.AbsoluteSize.X / #TABS - 3
for ic, text in fits do
ic.Visible = cell >= text.TextBounds.X + 13 + 5 + 12
end
end
bar:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
task.defer(fit)
end
local buildPage
local function buildSearch(parent)
local row = box({ BackgroundTransparency = 0, BackgroundColor3 = P.field, Size = UDim2.new(1, 0, 0, 32), Parent = parent }, { corner(9) })
local st = App.stroke(P.line)
st.Parent = row
local ic = App.icon("search", 13, P.faint)
ic.AnchorPoint, ic.Position = Vector2.new(0, 0.5), UDim2.new(0, 11, 0.5, 0)
ic.Parent = row
local tb = new("TextBox", {
Text = searchText,
PlaceholderText = "Search every setting",
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
st.Color = P.line
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
"areaPick",
"areaName",
"plusBtn",
"tabs",
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
local function buildResults(page)
local any = false
for _, t in TABS do
local holder = col({ Parent = page }, { vlist(10) })
local head = new("TextButton", {
Text = "",
AutoButtonColor = false,
BackgroundTransparency = 1,
Size = UDim2.new(1, 0, 0, 20),
Parent = holder,
}, { hlist(4) })
local name = label(
string.upper(t.name),
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
head.MouseButton1Click:Connect(function()
App.goPage(t.name)
end)
hintOn(head, "Open the " .. t.name .. " tab.")
local before = App.cardCount
App[t.build](holder)
if App.cardCount == before then
holder:Destroy()
else
any = true
end
end
if not any then
App.emptyState(page, "Nothing found", "Try another word, like road, colour, spacing or shortcut.")
end
end
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
App.pruneThumbs()
for _, ch in sc:GetChildren() do
if ch:IsA("GuiObject") then
ch:Destroy()
end
end
App.ui.builtShape = App.shapeKey()
local page = col({ Parent = sc }, { vlist(10) })
if App.searching() then
buildResults(page)
elseif not App.area and (G.page == "Scatter" or G.page == "Brush") then
App.buildWelcome(page)
else
App[TAB[G.page].build](page)
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
local builtPage
App.rebuildAll = function()
if not TAB[G.page] then
G.page = homeTab()
end
local keepScroll = builtPage == G.page and App.scroll and App.scroll.Parent and App.scroll.CanvasPosition
local turned = builtPage ~= nil and builtPage ~= G.page
builtPage = G.page
if App.root then
App.pruneThumbs()
App.root:Destroy()
end
App.ui = {}
App.root = box({ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0, BackgroundColor3 = P.bg, Parent = App.widget })
local head = col({ BackgroundTransparency = 0, BackgroundColor3 = P.bg, ZIndex = 2, Parent = App.root }, { pad(14, 14, 12, 8), vlist(0) })
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
buildHeader(head)
box({ Size = UDim2.new(1, 0, 0, 8), Parent = head })
buildTabs(head)
box({ Size = UDim2.new(1, 0, 0, 8), Parent = head })
buildSearch(head)
box({ Size = UDim2.new(1, 0, 0, 10), Parent = head })
App.fadeLine(head, nil, 0.16)
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
local sizing
local function updateGizmo(hit)
if App.mode == "Stamp" then
gizmoFolder()
for _, k in { "ring", "disc", "halo", "sq", "dot" } do
if App.gz[k] then
App.gz[k].Visible = false
end
end
end
if App.mode == "Spline" or App.mode == "Remove" or App.mode == "Stamp" then
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
local up = Engine.rotateUp(hit.Normal)
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
strokeRec = beginRec(name)
end
local function finishGesture()
local rec, changed, box = strokeRec, strokeChanged, strokeBox
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
if G.live and canGenerate() then
runGenerate(false, layerPaint or nil, box)
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
if App.mode == "Stamp" then
App.stampMove()
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
if App.mode == "Off" or App.mode == "Spline" then
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
if App.mode == "Stamp" then
if App.area and not App.area.locked then
App.stampDown()
end
return
end
if App.clickSplinePoint and App.clickSplinePoint() then
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
mouse.Button1Up:Connect(function()
if App.mode == "Stamp" then
App.stampUp()
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
local function onKey(name)
if App.mode == "Off" then
return
end
if os.clock() - (lastKeyAt[name] or 0) < 0.08 then
return
end
lastKeyAt[name] = os.clock()
if App.mode == "Stamp" and App.stampKey(name) then
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
local function ctrlHeld()
return UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl)
end
local function actionFor(key)
if App.capturingKey then
return nil
end
for _, a in App.KEYMAP do
if App.keyOf(a.id) == key then
if #(charOf(key) or "") == 1 and ctrlHeld() then
return nil
end
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
local key = App.keyOf(a.id)
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
Spline = "Click to add points. Drag to move, Shift+drag for height, {delete} or right-click deletes, {close} to finish.",
Place = "Drag to put copies down exactly where you brush. Shift erases it there instead. {size} resizes.",
Stamp = "Click to put one copy down, drag to turn it. {turn} turns, {shrink} {grow} size, {model} the model, {shuffle} a random one.",
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
for _, k in { "refreshMode", "refreshLayerBrush", "refreshSplineBtn", "refreshShapes", "refreshPoint", "refreshRemoveBtn" } do
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
if App.clearStamp then
App.clearStamp()
end
end
App.setMode = function(m, layer)
if m == App.mode and (not LAYER_MODES[m] or layer == App.paintLayer) then
m = "Off"
end
if m ~= "Off" and App.area and App.area.locked then
App.status("This area is locked. Unlock it in the area menu to paint or edit.")
m = "Off"
end
if m == "Remove" and not App.area then
App.status("Generate an area first, then remove single copies from it.")
m = "Off"
end
stopGestures()
if m ~= "Off" and not App.area then
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
-- #module App/Viewport/Spline
MODULES["App/Viewport/Spline"] = (function()
--[[
Smart Scatter — Spline: the spline editor: points, branches, welding, viewport preview.
Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]
return function(App)
local beginRec, endRec, Engine, track, G, saveG, num = App.beginRec, App.endRec, App.Engine, App.track, App.G, App.saveG, App.num
local new, refreshParams = App.new, App.refreshParams
local rebuildOverlay, saveArea, canGenerate, runGenerate = App.rebuildOverlay, App.saveArea, App.canGenerate, App.runGenerate
local switchArea, newArea, rawMouse, mouse, shiftHeld = App.switchArea, App.newArea, App.rawMouse, App.mouse, App.shiftHeld
local gizmoFolder, setLabel, mouseHit = App.gizmoFolder, App.setLabel, App.mouseHit
local sv = {}
local hoverPt, hoverIns, dragPt, dragRec, dragMoved, selPt
local welded = {}
local HANDLE_PX, CURVE_PX, WELD = 14, 10, 0.05
local VIEW = App.VIEW
local hoverHandle, dragHandle
local drawing
local joinSnap
local function ensureSpline()
if not App.area then
newArea()
end
App.area.spline = App.area.spline or { pts = {}, closed = false, width = 0, snap = true }
App.area.spline.branches = App.area.spline.branches or {}
return App.area.spline
end
local function editCurves()
local sp = App.area and App.area.spline
if not sp then
return {}
end
local list = { sp }
for _, b in sp.branches or {} do
table.insert(list, b)
end
return list
end
local function validPt(ref)
return ref ~= nil and ref.cv.pts[ref.i] ~= nil and table.find(editCurves(), ref.cv) ~= nil
end
local function samePt(a, b)
return a ~= nil and b ~= nil and a.cv == b.cv and a.i == b.i
end
local function totalPoints()
local n = 0
for _, cv in editCurves() do
n += #cv.pts
end
return n
end
local function curveOf(cv)
local sp = App.area.spline
return cv == sp and sp or { pts = cv.pts, closed = cv.closed == true }
end
local function selectPt(ref)
selPt = ref
if App.ui.refreshPoint then
App.ui.refreshPoint()
end
end
local function handlePositions()
if App.mode ~= "Spline" or not validPt(selPt) or #selPt.cv.pts < 2 then
return nil
end
local q = selPt.cv.pts[selPt.i]
if q.sharp then
return nil
end
local h = q.h or Engine.autoHandle(curveOf(selPt.cv), selPt.i)
if h.Magnitude < 0.05 then
return nil
end
return q.p + h, q.p - h, q
end
local function splineVisible()
return App.area ~= nil
and App.area.spline ~= nil
and #App.area.spline.pts > 0
and App.widget.Enabled
and (G.overlay or App.mode ~= "Off")
and not (App.overlayHidden and App.mode ~= "Spline")
end
local function removeSplineViz()
if sv.folder then
sv.folder:Destroy()
end
sv = {}
end
local dot
local function svFolder()
if sv.folder and sv.folder.Parent then
return
end
sv = { handles = {}, segs = {}, curves = {} }
sv.folder = new("Folder", { Name = "SmartScatterSpline", Archivable = false, Parent = workspace.CurrentCamera })
local T = workspace.Terrain
local ok, w = pcall(function()
return new(
"WireframeHandleAdornment",
{ Adornee = T, AlwaysOnTop = true, Thickness = 3, ZIndex = 3, Color3 = VIEW.accent, Parent = sv.folder }
)
end)
if ok and w then
sv.wire = w
sv.edge = new(
"WireframeHandleAdornment",
{ Adornee = T, AlwaysOnTop = true, Thickness = 1.5, ZIndex = 2, Transparency = 0.45, Color3 = VIEW.paper, Parent = sv.folder }
)
sv.halo = new(
"WireframeHandleAdornment",
{ Adornee = T, AlwaysOnTop = true, Thickness = 7, ZIndex = 1, Transparency = 0.9, Color3 = VIEW.edge, Parent = sv.folder }
)
end
for _, k in { "hOut", "hIn" } do
sv[k] = dot(9)
sv[k .. "Bar"] = new(
"BoxHandleAdornment",
{ Adornee = T, AlwaysOnTop = true, ZIndex = 7, Transparency = 0.2, Color3 = VIEW.paper, Visible = false, Parent = sv.folder }
)
end
sv.ghost = new("SphereHandleAdornment", {
Adornee = T,
Radius = 0.5,
AlwaysOnTop = true,
ZIndex = 5,
Transparency = 0.25,
Color3 = VIEW.accent,
Visible = false,
Parent = sv.folder,
})
end
function dot(z)
local d = {
rim = new(
"SphereHandleAdornment",
{ Adornee = workspace.Terrain, AlwaysOnTop = true, ZIndex = z, Color3 = VIEW.ink, Parent = sv.folder }
),
fill = new("SphereHandleAdornment", { Adornee = workspace.Terrain, AlwaysOnTop = true, ZIndex = z + 1, Parent = sv.folder }),
}
return d
end
local function showDot(d, p, r, fill, rim, transparency)
d.rim.Visible, d.fill.Visible = true, true
d.rim.CFrame, d.fill.CFrame = CFrame.new(p), CFrame.new(p)
d.rim.Radius, d.fill.Radius = r, r * 0.68
d.rim.Color3, d.fill.Color3 = rim or VIEW.ink, fill
d.rim.Transparency, d.fill.Transparency = transparency or 0, transparency or 0
end
local function hideDot(d)
d.rim.Visible, d.fill.Visible = false, false
end
local function handleRadius(p)
local cam = workspace.CurrentCamera
return math.clamp((cam.CFrame.Position - p).Magnitude * 0.011, 0.35, 6)
end
local function updateHandles()
if not sv.folder or not App.area or not App.area.spline then
return
end
local flat = {}
for _, cv in editCurves() do
for i in cv.pts do
table.insert(flat, { cv = cv, i = i })
end
end
local main = App.area.spline
for k = 1, math.max(#flat, #sv.handles) do
local h = sv.handles[k]
local ref = flat[k]
if ref then
local q = ref.cv.pts[ref.i]
if not h then
h = dot(6)
sv.handles[k] = h
end
local hot = samePt(ref, hoverPt) or samePt(ref, dragPt)
local sel = samePt(ref, selPt)
local start = ref.cv == main and ref.i == 1
local fill = (hot or sel) and VIEW.accent or q.sharp and VIEW.corner or start and VIEW.accent or VIEW.paper
showDot(
h,
q.p + q.n * 0.3,
handleRadius(q.p) * ((hot or sel) and 1.3 or 1),
fill,
(hot or sel) and VIEW.paper or nil,
App.mode == "Spline" and 0 or 0.45
)
elseif h then
hideDot(h)
end
end
local out, inn, q = handlePositions()
for _, it in { { "hOut", out, "out" }, { "hIn", inn, "in" } } do
local ball, bar, pos = sv[it[1]], sv[it[1] .. "Bar"], it[2]
if ball then
bar.Visible = pos ~= nil
if pos then
local hot = hoverHandle == it[3] or dragHandle == it[3]
local a, b = q.p + q.n * 0.3, pos + q.n * 0.3
showDot(ball, b, handleRadius(pos) * (hot and 0.8 or 0.55), hot and VIEW.accent or VIEW.paper)
local w = handleRadius(pos) * 0.12
bar.Size = Vector3.new(w, w, (b - a).Magnitude)
bar.CFrame = CFrame.lookAt((a + b) / 2, b)
else
hideDot(ball)
end
end
end
end
App.drawSpline = function()
if not splineVisible() then
removeSplineViz()
return
end
svFolder()
local sp = App.area.spline
local approx = 0
for _, cv in editCurves() do
for i = 2, #cv.pts do
approx += (cv.pts[i].p - cv.pts[i - 1].p).Magnitude
end
end
local step = math.max(1, approx / 500)
sv.curves = {}
local lines = {}
for _, cv in editCurves() do
if #cv.pts >= 2 then
local P, U, S, Wd = Engine.splineCurve(curveOf(cv), step)
table.insert(sv.curves, { cv = cv, P = P, U = U, S = S, W = Wd })
local lifted = table.create(#P)
for k = 1, #P do
lifted[k] = P[k] + U[k] * 0.3
end
table.insert(lines, lifted)
end
end
if sv.wire then
sv.wire:Clear()
sv.edge:Clear()
sv.halo:Clear()
for _, L in lines do
for k = 1, #L - 1 do
sv.wire:AddLine(L[k], L[k + 1])
sv.halo:AddLine(L[k], L[k + 1])
end
end
else
local n = 0
for _, L in lines do
for k = 1, #L - 1 do
n += 1
local seg = sv.segs[n]
if not seg then
seg = new(
"BoxHandleAdornment",
{ Adornee = workspace.Terrain, AlwaysOnTop = true, ZIndex = 3, Color3 = VIEW.accent, Parent = sv.folder }
)
sv.segs[n] = seg
end
local a, b = L[k], L[k + 1]
local len = (b - a).Magnitude
seg.Visible = len > 1e-3
if len > 1e-3 then
seg.Size = Vector3.new(0.3, 0.2, len + 0.3)
seg.CFrame = CFrame.lookAt((a + b) / 2, b)
end
end
end
for k = n + 1, #sv.segs do
sv.segs[k].Visible = false
end
end
if sv.edge and (sp.width or 0) > 0 then
local R = sp.width / 2
for ci, c in sv.curves do
local P, L = c.P, lines[ci]
local A, B = {}, {}
for k = 1, #P do
local t = P[math.min(k + 1, #P)] - P[math.max(k - 1, 1)]
local side = Vector3.new(-t.Z, 0, t.X)
side = side.Magnitude > 1e-4 and side.Unit or Vector3.xAxis
A[k], B[k] = L[k] + side * R * c.W[k], L[k] - side * R * c.W[k]
end
for k = 1, #P - 1 do
sv.edge:AddLine(A[k], A[k + 1])
sv.edge:AddLine(B[k], B[k + 1])
end
end
end
updateHandles()
end
track(workspace.CurrentCamera:GetPropertyChangedSignal("CFrame"):Connect(function()
if App.mode == "Spline" and sv.folder then
updateHandles()
end
end))
local mouseAt
local function screenDist(p)
local v, on = workspace.CurrentCamera:WorldToViewportPoint(p)
if not on or v.Z <= 0 then
return math.huge
end
local m = mouseAt or Vector2.new(rawMouse.X, rawMouse.Y)
return (Vector2.new(v.X, v.Y) - m).Magnitude
end
local function pickPoint(skip)
local best, bd = nil, HANDLE_PX
for _, cv in editCurves() do
for i, q in cv.pts do
if not (skip and skip(cv, i, q)) then
local d = screenDist(q.p + q.n * 0.3)
if d < bd - 0.5 then
best, bd = { cv = cv, i = i }, d
end
end
end
end
return best
end
local function pickHandle()
local out, inn, q = handlePositions()
if out and screenDist(out + q.n * 0.3) < HANDLE_PX then
return "out"
end
if inn and screenDist(inn + q.n * 0.3) < HANDLE_PX then
return "in"
end
return nil
end
local function pickCurve(skip)
local best, bd = nil, CURVE_PX
for _, c in sv.curves or {} do
for k, p in c.P do
if not (skip and skip(c.cv, c.S[k])) then
local d = screenDist(p + c.U[k] * 0.3)
if d < bd then
best, bd = { cv = c.cv, p = p, n = c.U[k], seg = c.S[k] }, d
end
end
end
end
return best
end
local snapTo
local function findSnap(ref, extra)
local q = ref.cv.pts[ref.i]
local function mine(cv, i, o)
return (cv == ref.cv and i == ref.i) or (o.p - q.p).Magnitude < WELD or (extra and extra[o])
end
local hitPt = pickPoint(function(cv, i, o)
return mine(cv, i, o) or (cv == ref.cv and math.abs(i - ref.i) == 1)
end)
if hitPt then
return { kind = "point", ref = hitPt }
end
local isEnd = ref.i == 1 or ref.i == #ref.cv.pts
if not isEnd then
return nil
end
local hitCv = pickCurve(function(cv, seg)
return cv == ref.cv and (seg == ref.i or seg == ref.i - 1 or seg == ref.i - 2 or seg == ref.i + 1)
end)
if hitCv then
return { kind = "curve", at = hitCv }
end
return nil
end
local function growAction()
local sp = App.area and App.area.spline
if not sp or #sp.pts == 0 or not validPt(selPt) then
return "append"
end
local cv, i = selPt.cv, selPt.i
local open = not cv.closed or #cv.pts < 3
if open and i == #cv.pts then
return "append"
elseif open and cv == sp and i == 1 then
return "prepend"
end
return "branch"
end
App.refreshSplineInfo = function()
if not App.ui.splineInfo then
return
end
local sp = App.area and App.area.spline
if not sp or #sp.pts == 0 then
App.ui.splineInfo.Text = "No spline yet. Press Draw, then click in the viewport to place points."
return
end
local len = 0
for _, cv in Engine.splineCurves(sp) do
local P = Engine.splineCurve(cv, 2)
for k = 2, #P do
len += (P[k] - P[k - 1]).Magnitude
end
end
local n, nb, nl = totalPoints(), 0, 0
for _, b in sp.branches or {} do
if b.closed then
nl += 1
else
nb += 1
end
end
App.ui.splineInfo.Text = string.format(
"%d point%s · %s studs · %s%s%s%s",
n,
n == 1 and "" or "s",
num(len),
(sp.closed and #sp.pts >= 3) and "loop" or "open",
nb > 0 and string.format(" · %d branch%s", nb, nb == 1 and "" or "es") or "",
nl > 0 and string.format(" · %d more loop%s", nl, nl == 1 and "" or "s") or "",
(sp.width or 0) > 0 and string.format(" · %d-stud strip", sp.width) or ""
)
end
local function commitSpline(rec)
local sp = App.area.spline
if sp and (sp.width or 0) > 0 then
refreshParams()
Engine.maskFromSpline(App.area, App.probeParams)
rebuildOverlay(true)
end
saveArea()
endRec(rec)
App.analysisDirty = true
if G.live and canGenerate() then
runGenerate(false)
end
App.drawSpline()
App.refreshSplineInfo()
App.checkShape()
if not (G.live and canGenerate()) then
App.refreshScan()
App.refreshCounts()
App.status(select(2, canGenerate()) or "Spline updated. Press Generate.")
end
end
local function splineEdit(name, fn)
local rec = beginRec("Smart Scatter: " .. name)
fn()
commitSpline(rec)
end
local function pointHit()
local hit = mouseHit()
local sp = App.area and App.area.spline
if hit and hit.Normal.Y < 0.55 and not (sp and sp.walls) then
local down = Engine.cast(hit.Position + hit.Normal * 0.6 + Vector3.new(0, 0.5, 0), Vector3.new(0, -600, 0), App.probeParams)
if down and down.Normal.Y >= 0.55 then
return down
end
end
return hit
end
local function splineLabel(hit, text)
gizmoFolder()
App.gz.ring.Visible, App.gz.disc.Visible, App.gz.sq.Visible = false, false, false
App.gz.dot.Visible = hit ~= nil and not hoverPt
if hit then
App.gz.dot.CFrame = CFrame.new(hit.Position)
App.gz.dot.Color3 = VIEW.accent
App.gz.anchor.CFrame = CFrame.new(hit.Position)
end
setLabel(hit and text or "")
end
mouse.Move:Connect(function()
if App.mode ~= "Spline" then
return
end
if App.shapeTool then
App.shapeMove()
return
end
local sp = App.area and App.area.spline
if dragHandle and validPt(selPt) then
local q = selPt.cv.pts[selPt.i]
local ray = rawMouse.UnitRay
local nrm = Vector3.yAxis
if shiftHeld() then
local look = workspace.CurrentCamera.CFrame.LookVector
nrm = Vector3.new(look.X, 0, look.Z)
nrm = nrm.Magnitude > 1e-3 and nrm.Unit or Vector3.xAxis
end
local denom = ray.Direction:Dot(nrm)
if math.abs(denom) > 1e-4 then
local t = (q.p - ray.Origin):Dot(nrm) / denom
if t > 0 then
local off = ray.Origin + ray.Direction * t - q.p
if shiftHeld() then
local cur = q.h or Engine.autoHandle(curveOf(selPt.cv), selPt.i)
local was = dragHandle == "out" and cur or -cur
off = Vector3.new(was.X, off.Y, was.Z)
end
q.h = dragHandle == "out" and off or -off
dragMoved = true
App.drawSpline()
end
end
splineLabel(nil)
return
end
if drawing then
local hit = pointHit()
if hit and (hit.Position - drawing.anchor).Magnitude >= drawing.spacing then
local q = { p = hit.Position, n = hit.Normal }
local cv = drawing.cv
if drawing.prepend then
table.insert(cv.pts, 1, q)
else
table.insert(cv.pts, q)
end
table.insert(drawing.pts, q)
drawing.anchor = hit.Position
selPt = { cv = cv, i = drawing.prepend and 1 or #cv.pts }
App.drawSpline()
end
splineLabel(hit, "Drawing · release to finish")
return
end
if dragPt and validPt(dragPt) then
local q = dragPt.cv.pts[dragPt.i]
local before = q.p
if shiftHeld() then
local ray = rawMouse.UnitRay
local look = workspace.CurrentCamera.CFrame.LookVector
local nrm = Vector3.new(look.X, 0, look.Z)
if nrm.Magnitude > 1e-3 then
nrm = nrm.Unit
local denom = ray.Direction:Dot(nrm)
if math.abs(denom) > 1e-4 then
local t = (q.p - ray.Origin):Dot(nrm) / denom
if t > 0 then
q.p = Vector3.new(q.p.X, (ray.Origin + ray.Direction * t).Y, q.p.Z)
local below = Engine.cast(q.p + Vector3.yAxis * 2, Vector3.yAxis * -500, App.probeParams)
q.raised = not below or q.p.Y - below.Position.Y > 0.5 or nil
end
end
end
splineLabel(nil)
else
local hit = pointHit()
if hit then
q.p = hit.Position
q.n = hit.Normal
q.raised = nil
end
snapTo = findSnap(dragPt)
if snapTo then
local target = snapTo.kind == "point" and snapTo.ref.cv.pts[snapTo.ref.i] or snapTo.at
q.p, q.n = target.p, target.n
end
splineLabel(
hit,
snapTo and (snapTo.kind == "point" and "Release to join these points" or "Release to join the curve here") or "Moving point"
)
end
if q.p ~= before then
dragMoved = true
for _, w in welded do
local o = w.cv.pts[w.i]
if o then
o.p, o.n, o.raised = q.p, q.n, q.raised
end
end
App.drawSpline()
end
return
end
hoverHandle = pickHandle()
hoverPt = not hoverHandle and pickPoint() or nil
hoverIns = not hoverHandle and not hoverPt and pickCurve() or nil
if sv.ghost then
sv.ghost.Visible = hoverIns ~= nil
if hoverIns then
sv.ghost.CFrame = CFrame.new(hoverIns.p + hoverIns.n * 0.3)
sv.ghost.Radius = handleRadius(hoverIns.p) * 0.8
end
end
updateHandles()
local hit = mouseHit()
local text
if hoverHandle then
text = "Drag to bend the curve · Shift for height"
elseif hoverPt then
text = "Drag to move · click to select · right-click to delete"
elseif hoverIns then
text = "Click to insert a point here"
elseif not sp or #sp.pts == 0 then
text = "Click to start the spline · hold and drag to draw it"
else
local act = growAction()
text = act == "branch" and "Click to start a branch from the selected point"
or act == "prepend" and "Click to extend from the start"
or "Click to add a point · hold and drag to draw"
end
splineLabel(hit, text)
end)
mouse.Button1Down:Connect(function()
if App.mode ~= "Spline" then
return
end
if App.shapeTool then
App.shapeDown()
return
end
if hoverHandle and validPt(selPt) then
dragHandle = hoverHandle
dragRec = beginRec("Smart Scatter: Spline handle")
dragMoved = false
return
end
local sp = ensureSpline()
snapTo = nil
dragRec = beginRec("Smart Scatter: Spline")
dragMoved = false
table.clear(welded)
if hoverPt and validPt(hoverPt) then
dragPt = hoverPt
local at = dragPt.cv.pts[dragPt.i].p
for _, cv in editCurves() do
for i, q in cv.pts do
if (q.p - at).Magnitude < WELD and not (cv == dragPt.cv and i == dragPt.i) then
table.insert(welded, { cv = cv, i = i })
end
end
end
elseif hoverIns then
table.insert(hoverIns.cv.pts, hoverIns.seg + 1, { p = hoverIns.p, n = hoverIns.n })
dragPt = { cv = hoverIns.cv, i = hoverIns.seg + 1 }
dragMoved = true
else
local hit = pointHit()
if not hit then
endRec(dragRec, true)
dragRec = nil
return
end
local q = { p = hit.Position, n = hit.Normal }
local act = growAction()
local cv, prepend
if act == "branch" then
local root = selPt.cv.pts[selPt.i]
cv = { pts = { { p = root.p, n = root.n }, q }, closed = false }
table.insert(sp.branches, cv)
elseif act == "prepend" then
cv, prepend = sp, true
table.insert(sp.pts, 1, q)
else
cv = validPt(selPt) and selPt.cv or sp
table.insert(cv.pts, q)
end
local camDist = (workspace.CurrentCamera.CFrame.Position - hit.Position).Magnitude
drawing = { cv = cv, prepend = prepend, anchor = hit.Position, spacing = math.clamp(camDist * 0.07, 2, 40), pts = { q } }
dragMoved = true
selectPt({ cv = cv, i = prepend and 1 or #cv.pts })
hoverIns = nil
App.drawSpline()
return
end
selectPt(dragPt)
hoverIns = nil
App.drawSpline()
end)
function joinSnap(ref, snap)
local sp = App.area.spline
if snap.kind == "point" then
local how = Engine.joinToPoint(sp, ref, snap.ref)
if how == "closed" then
selectPt({ cv = ref.cv, i = 1 })
return "Closed the loop."
end
return how and "Joined. The two points now move together." or nil
end
local at = snap.at
Engine.joinToCurve(ref, at.cv, at.seg, at.p, at.n)
return "Joined into the curve (a junction point was added)."
end
local function finishDrawing()
local d = drawing
drawing = nil
local hit = pointHit()
local cv = d.cv
if hit and (hit.Position - d.anchor).Magnitude >= d.spacing * 0.4 then
local q = { p = hit.Position, n = hit.Normal }
if d.prepend then
table.insert(cv.pts, 1, q)
else
table.insert(cv.pts, q)
end
table.insert(d.pts, q)
end
local own = {}
for k = 2, #d.pts do
own[d.pts[k]] = true
end
local endRef = { cv = cv, i = d.prepend and 1 or #cv.pts }
local snap = #d.pts >= 2 and findSnap(endRef, own)
if snap then
local target = snap.kind == "point" and snap.ref.cv.pts[snap.ref.i] or snap.at
local q = cv.pts[endRef.i]
q.p, q.n = target.p, target.n
end
local anchor = snap and (snap.kind == "point" and snap.ref.cv.pts[snap.ref.i] or snap.at.cv.pts[snap.at.seg])
local drop = Engine.thinStroke(d.pts, d.spacing)
for i = #cv.pts, 1, -1 do
if drop[cv.pts[i]] then
table.remove(cv.pts, i)
end
end
if snap then
local list = snap.kind == "point" and snap.ref.cv.pts or snap.at.cv.pts
local i = anchor and table.find(list, anchor)
if not i then
snap = nil
elseif snap.kind == "point" then
snap.ref = { cv = snap.ref.cv, i = i }
else
snap.at.seg = i
end
end
local joined
if snap then
joined = joinSnap({ cv = cv, i = d.prepend and 1 or #cv.pts }, snap)
end
if not (joined and joined == "Closed the loop.") then
selectPt({ cv = cv, i = d.prepend and 1 or #cv.pts })
end
if joined then
App.status(joined)
end
end
mouse.Button1Up:Connect(function()
if App.mode == "Spline" and App.shapeTool then
App.shapeUp()
return
end
if App.mode == "Spline" and dragHandle then
dragHandle = nil
local rec = dragRec
dragRec = nil
if dragMoved then
commitSpline(rec)
else
endRec(rec, true)
end
return
end
if drawing and App.area then
finishDrawing()
local rec = dragRec
dragRec = nil
commitSpline(rec)
return
end
if App.mode ~= "Spline" or not dragPt then
return
end
local joined = snapTo and validPt(dragPt) and dragMoved and joinSnap(dragPt, snapTo)
snapTo = nil
dragPt = nil
table.clear(welded)
local rec = dragRec
dragRec = nil
if dragMoved then
commitSpline(rec)
if joined then
App.status(joined)
end
else
endRec(rec, true)
updateHandles()
end
end)
App.resetSplineDrag = function(cancel)
if App.cancelShape then
App.cancelShape()
end
local rec, moved = dragRec, dragMoved
if drawing and App.area and not cancel then
finishDrawing()
end
drawing, dragPt, dragHandle, snapTo, dragRec, dragMoved = nil, nil, nil, nil, nil, false
table.clear(welded)
if rec then
if moved and not cancel and App.area then
commitSpline(rec)
else
endRec(rec, true)
end
end
end
local function deletePoint(ref)
local sp = App.area and App.area.spline
if not sp or not validPt(ref) then
return
end
splineEdit("Spline", function()
table.remove(ref.cv.pts, ref.i)
if ref.cv ~= sp and #ref.cv.pts < 3 then
ref.cv.closed = nil
end
if ref.cv ~= sp and #ref.cv.pts < 2 then
table.remove(sp.branches, table.find(sp.branches, ref.cv))
elseif ref.cv == sp and #sp.pts == 0 and #(sp.branches or {}) > 0 then
sp.pts = table.remove(sp.branches, 1).pts
end
end)
hoverPt = nil
if validPt(ref) and ref.i > 1 then
selectPt({ cv = ref.cv, i = ref.i - 1 })
elseif validPt(ref) then
selectPt(ref)
else
selectPt(nil)
end
updateHandles()
end
local function setSharp(ref, on)
local q = ref.cv.pts[ref.i]
splineEdit("Spline corner", function()
for _, cv in editCurves() do
for _, o in cv.pts do
if (o.p - q.p).Magnitude < WELD then
o.sharp = on or nil
if on then
o.h = nil
end
end
end
end
end)
App.status(on and "Sharp corner. Press C again to smooth it." or "Smooth point.")
if App.ui.refreshPoint then
App.ui.refreshPoint()
end
end
App.selectedPoint = function()
return App.mode == "Spline" and validPt(selPt) and selPt.cv.pts[selPt.i] or nil
end
App.pointAction = function(what)
if not validPt(selPt) then
return
end
if what == "sharp" then
setSharp(selPt, not selPt.cv.pts[selPt.i].sharp)
elseif what == "resetHandle" then
local q = selPt.cv.pts[selPt.i]
splineEdit("Spline handle", function()
q.h = nil
end)
if App.ui.refreshPoint then
App.ui.refreshPoint()
end
elseif what == "delete" then
deletePoint(selPt)
end
end
App.onRightClick(function()
if App.mode == "Spline" and hoverPt then
deletePoint(hoverPt)
end
end)
App.clickSplinePoint = function(at)
if App.mode == "Spline" or not sv.folder or not App.area or not App.area.spline or App.area.locked then
return false
end
mouseAt = at
local ref = pickPoint()
mouseAt = nil
if not ref then
return false
end
App.setMode("Spline")
if App.mode ~= "Spline" then
return false
end
selectPt(ref)
App.drawSpline()
App.status("Editing the spline: drag points, or select one and click the ground to extend or branch.")
return true
end
track(game:GetService("UserInputService").InputBegan:Connect(function(input)
if input.UserInputType ~= Enum.UserInputType.MouseButton1 or App.mode ~= "Off" or not App.widget.Enabled then
return
end
if App.clickSplinePoint(Vector2.new(input.Position.X, input.Position.Y)) then
task.defer(function()
App.Selection:Set({})
end)
end
end))
App.splineKey = function(name)
if name == "back" then
local sp = App.area and App.area.spline
if sp and #sp.pts > 0 then
deletePoint(hoverPt or (validPt(selPt) and selPt) or { cv = sp, i = #sp.pts })
end
elseif name == "delete" then
local ref = hoverPt or (validPt(selPt) and selPt)
if ref then
deletePoint(ref)
else
App.status("Hover or select a point, then press X to delete it.")
end
elseif name == "corner" then
local ref = hoverPt or (validPt(selPt) and selPt)
if not ref then
App.status("Select a point first, then press C for a sharp corner.")
return
end
setSharp(ref, not ref.cv.pts[ref.i].sharp)
elseif name == "cancel" and App.shapeTool then
App.cancelShape()
elseif name == "close" or name == "cancel" then
selectPt(nil)
App.setMode("Off")
end
end
App.clearSplineFn = function(rec)
local sp = App.area and App.area.spline
if not sp then
return
end
table.clear(sp.pts)
sp.branches = {}
hoverPt = nil
selectPt(nil)
if (sp.width or 0) > 0 then
App.area.rows, App.area.count = {}, 0
end
commitSpline(rec)
end
App.newSplineFn = function(opts)
local n = 1
while Engine.getOut():FindFirstChild("Path " .. n) do
n += 1
end
local rec = beginRec("Smart Scatter: New Spline")
local a = Engine.createArea("Path " .. n, nil)
a.folder:SetAttribute("SS_Kind", "Path")
endRec(rec)
G.page = ""
saveG()
switchArea(a.folder)
ensureSpline()
if not (opts and opts.keepMode) then
App.setMode("Spline")
end
end
App.subdivideSpline = function()
local sp = App.area and App.area.spline
if not sp or totalPoints() < 2 then
App.status("Draw a path or place a shape first, then subdivide it.")
return
end
local list = validPt(selPt) and { selPt.cv } or editCurves()
local added = 0
splineEdit("Subdivide", function()
for _, cv in list do
if #cv.pts + #cv.pts <= 512 then
added += Engine.subdivide(curveOf(cv))
end
end
end)
hoverPt = nil
if validPt(selPt) then
selectPt({ cv = selPt.cv, i = math.min(selPt.i * 2 - 1, #selPt.cv.pts) })
end
App.status(
added > 0 and string.format("Added %d point%s, one halfway along each side.", added, added == 1 and "" or "s")
or "That curve already has plenty of points."
)
end
App.commitSplineFn = commitSpline
App.ensureSplineFn = ensureSpline
App.splinePointHit = pointHit
App.splineLabel = splineLabel
App.selectSplinePoint = selectPt
App.removeSplineViz = removeSplineViz
end
end)()
-- #module App/Viewport/Shapes
MODULES["App/Viewport/Shapes"] = (function()
--[[
Smart Scatter — Shapes: path shape presets (square, rectangle, triangle, hexagon, octagon, circle), for a fence
round a field, a ring road or a plaza in one drag. Pick one on the Path card, then drag in the viewport: from the
centre out (a corner follows the mouse and the turn snaps to 15°; Shift turns it freely), or corner to corner for the
rectangle. The shape is a real closed curve of the path from the first move, so what shows while dragging is what
you get, each corner on the ground under it. An empty path becomes the shape; otherwise it's a loop of its own in the
same path (same width and objects). One shape per pick, then it's back to editing points, Blender style.
The spline editor (Viewport/Spline) hands its mouse over while a shape is picked.
Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]
return function(App)
local Engine, beginRec, endRec, rawMouse = App.Engine, App.beginRec, App.endRec, App.rawMouse
local MIN = 2
local placing
App.shapeTool = nil
local function refresh()
if App.ui.refreshShapes then
App.ui.refreshShapes()
end
if App.refreshFocus then
App.refreshFocus()
end
end
local function onPlane(y)
local ray = rawMouse.UnitRay
if ray.Direction.Y < -1e-3 then
local t = (y - ray.Origin.Y) / ray.Direction.Y
if t > 0 then
return ray.Origin + ray.Direction * t
end
end
local hit = App.splinePointHit()
return hit and hit.Position
end
local function ground(v, up, reach)
local hit = Engine.cast(v + Vector3.new(0, reach, 0), Vector3.new(0, -reach * 3 - 50, 0), App.probeParams)
if hit then
return hit.Position, hit.Normal
end
return v, up
end
local function fill(to, free)
local pl = placing
local corners, smooth = Engine.shapePoints(pl.kind, pl.from, to, free)
local dx, dz = to.X - pl.from.X, to.Z - pl.from.Z
local size = math.sqrt(dx * dx + dz * dz)
local pts = pl.cv.pts
table.clear(pts)
for _, c in corners do
local p, n = ground(c, pl.up, 10 + size * 0.6)
table.insert(pts, { p = p, n = n, sharp = not smooth or nil })
end
pl.size = size
pl.text = pl.kind == "Rectangle" and string.format("Rectangle · %s × %s studs", App.num(math.abs(dx)), App.num(math.abs(dz)))
or string.format("%s · %s studs across", pl.kind, App.num(size * 2))
end
local function unplace(pl)
local sp = App.area and App.area.spline
if not sp then
return
end
if pl.main then
table.clear(sp.pts)
sp.closed = pl.wasClosed
else
local i = table.find(sp.branches, pl.cv)
if i then
table.remove(sp.branches, i)
end
end
end
App.pickShape = function(kind)
if App.shapeTool == kind then
App.cancelShape()
return
end
if App.mode ~= "Spline" then
App.ensureSplineFn()
App.setMode("Spline")
if App.mode ~= "Spline" then
return
end
end
App.cancelShape()
App.shapeTool = kind
App.selectSplinePoint(nil)
refresh()
App.status(
kind == "Rectangle" and "Drag from one corner of the rectangle to the opposite one."
or string.format("Drag from the centre of the %s outward. It turns in 15° steps; hold Shift to turn freely.", string.lower(kind))
)
end
App.shapeDown = function()
local hit = App.splinePointHit()
if not hit then
return
end
local sp = App.ensureSplineFn()
local main = #sp.pts == 0
local cv = main and sp or { pts = {}, closed = true }
placing = {
kind = App.shapeTool,
from = hit.Position,
up = hit.Normal,
cv = cv,
main = main,
wasClosed = sp.closed,
rec = beginRec("Smart Scatter: " .. App.shapeTool),
size = 0,
}
if main then
sp.closed = true
else
table.insert(sp.branches, cv)
end
end
App.shapeMove = function()
if not placing then
local hit = App.splinePointHit()
App.splineLabel(
hit,
App.shapeTool == "Rectangle" and "Rectangle · drag from one corner to the other"
or App.shapeTool .. " · drag from its centre outward"
)
return
end
local to = onPlane(placing.from.Y)
if to then
fill(to, App.shiftHeld())
App.drawSpline()
end
App.splineLabel({ Position = to or placing.from }, placing.text or placing.kind)
end
App.shapeUp = function()
local pl = placing
placing = nil
if not pl then
return
end
if pl.size < MIN or #pl.cv.pts < 3 then
unplace(pl)
endRec(pl.rec, true)
App.drawSpline()
App.status("Hold and drag to size the shape.")
return
end
App.shapeTool = nil
App.selectSplinePoint({ cv = pl.cv, i = 1 })
App.commitSplineFn(pl.rec)
refresh()
App.status(
pl.kind
.. " placed. Drag a corner to move it, click an edge to add a point, "
.. App.keyText("delete")
.. " deletes one, and Subdivide adds one on every side."
)
end
App.cancelShape = function()
local pl = placing
placing = nil
if pl then
unplace(pl)
endRec(pl.rec, true)
if App.drawSpline then
App.drawSpline()
end
end
if App.shapeTool then
App.shapeTool = nil
refresh()
end
end
end
end)()
-- #module App/Viewport/Stamp
MODULES["App/Viewport/Stamp"] = (function()
--[[
Smart Scatter — Stamp: puts one copy of an object down exactly where and how you want it. The real model floats
under the mouse, see-through, standing just as it will (it's posed by the same placement code, on the same ground);
a click puts it down, a drag from where you pressed turns it to face the mouse (15° steps; Shift turns freely).
Keys turn it, size it, pick the model or roll a random one; the panel has the same as sliders. Each stamp is a pin
that keeps its turn, size and model (Engine/Pins), so it comes back exactly so every time the area is generated,
and no rule moves or refuses it. One undo step each.
Paint hands the viewport's mouse and keys to it while the mode is "Stamp".
Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]
return function(App)
local Engine, G, beginRec, endRec, rawMouse = App.Engine, App.G, App.beginRec, App.endRec, App.rawMouse
local STEP = math.rad(15)
local DRAG_PX = 6
local stamp = { yaw = 0, k = 1, vi = 1 }
App.stamp = stamp
local ghost
local press
local function layer()
local l = App.mode == "Stamp" and App.paintLayer or nil
if l and stamp.layer ~= l then
stamp.layer, stamp.vi = l, 1
stamp.k = (l.s.scaleMin + l.s.scaleMax) / 2 * (App.area and App.area.size or 1)
end
return l
end
local function clearGhost()
if ghost then
ghost.clone:Destroy()
ghost = nil
end
end
local function ghostFor(v, sc)
if ghost and ghost.v == v and math.abs(ghost.sc - sc) < 1e-4 and ghost.clone.Parent then
return ghost
end
clearGhost()
local c = (v.src or v.inst):Clone()
c.Archivable = false
local all = c:GetDescendants()
table.insert(all, c)
for _, d in all do
if d:IsA("BasePart") then
d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch, d.CastShadow, d.Locked = true, false, false, false, false, true
d.Transparency = 1 - (1 - d.Transparency) * 0.5
elseif d:IsA("Decal") then
d.Transparency = 1 - (1 - d.Transparency) * 0.5
elseif d:IsA("Script") or d:IsA("LocalScript") then
d:Destroy()
end
end
ghost = { clone = c, v = v, sc = sc }
return ghost
end
local function aim(l, x, z, seed)
if not App.area or (App.area.count or 0) == 0 then
return nil, nil, "paint the area first: stamps go on its ground"
end
App.readGround(App.area)
local an = App.lastAnalysis
if not an then
return nil, nil, "the ground couldn't be read"
end
stamp.vi = math.clamp(stamp.vi, 1, #l.variants)
local p = Engine.stampPin(x, z, stamp.yaw, stamp.k, stamp.vi, seed or 1)
local pose = Engine.stampPose(App.area, an, l, p)
return p, pose, not pose and "outside the area, or no ground here" or nil
end
local function describe(l, extra)
local v = l.variants[stamp.vi] or l.variants[1]
return string.format(
"Stamp · %s · %d° · %.2f×%s",
v.inst.Name,
math.floor(math.deg(stamp.yaw) + 0.5) % 360,
stamp.k,
extra and ("  ·  " .. extra) or ""
)
end
local function label(at, text)
App.gizmoFolder()
App.gz.anchor.CFrame = CFrame.new(at)
App.setLabel(text)
end
local function show(l, x, z, y)
local _, pose, why = aim(l, x, z)
if not pose then
clearGhost()
label(Vector3.new(x, y, z), describe(l, "can't go here: " .. why))
return
end
local gh = ghostFor(pose.v, pose.sc)
if not gh.offset then
Engine.poseCopy(gh.clone, l, pose.v, pose.sc, pose.cf, pose.sink)
gh.offset = pose.cf:Inverse() * gh.clone:GetPivot()
gh.clone.Parent = App.gizmoFolder()
else
gh.clone:PivotTo(pose.cf * gh.offset)
end
label(pose.cf.Position, describe(l, press and press.turning and "release to put it down" or "click to put it down, drag to turn"))
end
local function onPlane(y)
local ray = rawMouse.UnitRay
if math.abs(ray.Direction.Y) > 1e-3 then
local t = (y - ray.Origin.Y) / ray.Direction.Y
if t > 0 then
return ray.Origin + ray.Direction * t
end
end
return nil
end
App.stampMove = function()
local l = layer()
if not l then
return
end
if press then
local m = Vector2.new(rawMouse.X, rawMouse.Y)
press.turning = press.turning or (m - press.at).Magnitude > DRAG_PX
if press.turning then
local to = onPlane(press.y)
if to and (Vector3.new(to.X - press.x, 0, to.Z - press.z)).Magnitude > 0.5 then
local yaw = math.atan2(-(to.X - press.x), -(to.Z - press.z))
stamp.yaw = App.shiftHeld() and yaw or math.floor(yaw / STEP + 0.5) * STEP
end
end
show(l, press.x, press.z, press.y)
return
end
local hit = App.mouseHit()
if not hit then
clearGhost()
App.setLabel("")
return
end
show(l, hit.Position.X, hit.Position.Z, hit.Position.Y)
end
local function roll(l)
local s = l.s
stamp.yaw = s.yawMode == "Fixed" and math.rad(s.yaw) or s.yawMode == "Snap" and math.random(0, 3) * math.pi / 2 or math.random() * math.pi * 2
local size = App.area and App.area.size or 1
stamp.k = (s.scaleMin + (s.scaleMax - s.scaleMin) * math.random()) * size
local sum = 0
for _, v in l.variants do
sum += math.max(v.w, 0)
end
local r = math.random() * sum
for i, v in l.variants do
r -= math.max(v.w, 0)
if r <= 0 and v.w > 0 then
stamp.vi = i
break
end
end
end
local function refresh()
if App.ui.refreshStamp then
App.ui.refreshStamp()
end
App.stampMove()
end
local function put(l, x, z)
local p, pose, why = aim(l, x, z, math.random(1, 2 ^ 30))
if not pose then
App.status("Can't stamp there: " .. why .. ".", "error")
return
end
local rec = beginRec("Smart Scatter: Stamp " .. l.inst.Name)
local made = Engine.placeStamp(
App.area,
App.lastAnalysis,
l,
p,
{ walk = G.walk, shadows = G.shadows, query = G.query, chunks = false, ghost = false }
)
if not made then
endRec(rec, true)
App.status("Can't stamp there: it's a keep-clear zone.", "error")
return
end
l.pins = l.pins or {}
table.insert(l.pins, p)
App.saveArea()
endRec(rec)
App.lastCounts[l] = (App.lastCounts[l] or 0) + 1
App.lastTotal = (App.lastTotal or 0) + 1
App.refreshCounts()
App.status(describe(l, "put down. Ctrl+Z takes it back."))
if G.stampRandom then
roll(l)
if App.ui.refreshStamp then
App.ui.refreshStamp()
end
end
end
App.stampDown = function()
local hit = App.mouseHit()
if not (layer() and hit) then
return
end
press = { x = hit.Position.X, z = hit.Position.Z, y = hit.Position.Y, at = Vector2.new(rawMouse.X, rawMouse.Y) }
end
App.stampUp = function()
local l, pr = layer(), press
press = nil
if l and pr then
put(l, pr.x, pr.z)
if pr.turning and App.ui.refreshStamp then
App.ui.refreshStamp()
end
App.stampMove()
end
end
App.stampKey = function(name)
local l = layer()
if not l then
return false
end
if name == "turn" then
stamp.yaw = (math.floor(stamp.yaw / STEP + 0.5) + (App.shiftHeld() and -1 or 1)) * STEP % (math.pi * 2)
elseif name == "grow" or name == "shrink" then
stamp.k = math.clamp(stamp.k * (name == "grow" and 1.1 or 1 / 1.1), 0.05, 20)
elseif name == "model" then
stamp.vi = stamp.vi % #l.variants + 1
elseif name == "shuffle" then
roll(l)
elseif name == "size" then
return true
elseif name == "cancel" and press then
press = nil
elseif name == "cancel" then
return false
else
return false
end
refresh()
return true
end
App.setStamp = function(yaw, k, vi)
stamp.yaw = yaw and math.rad(yaw) % (math.pi * 2) or stamp.yaw
stamp.k = k or stamp.k
stamp.vi = vi or stamp.vi
if App.mode == "Stamp" then
App.stampMove()
end
end
App.rollStamp = function()
local l = layer() or App.paintLayer
if l then
roll(l)
refresh()
end
end
App.clearStamp = function()
press = nil
clearGhost()
end
end
end)()
-- #module App/Viewport/Focus
MODULES["App/Viewport/Focus"] = (function()
--[[
Smart Scatter — Focus: while a tool of the plugin is on in the viewport (painting, erasing, drawing the path,
brushing one object, removing copies), the world steps back a little, so the tool stands out, the way Blender's
edit mode and local view feel: the scene fades toward grey and dims (a colour correction on the camera, never
saved with the place), a faint frame in the accent runs round the viewport, and quiet text in its top-left corner
says the mode and what it's working on, Blender style. Red while it takes things away. Settings › Viewport can
turn it off.
Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]
return function(App)
local G, P, tween, MED, FAST = App.G, App.P, App.tween, App.MED, App.FAST
local new, box, corner, label = App.new, App.box, App.corner, App.label
local SANS_M, SANS_B = App.SANS_M, App.SANS_B
local LAYER_MODES = App.LAYER_MODES
local LOOK = { Saturation = -0.35, Brightness = -0.05, Contrast = -0.06 }
local cc
local gui, group, frame, glowLine, dot, title, detail, keyRow
local function describe()
local m = App.mode
local shift = App.shiftHeld and App.shiftHeld()
local area = App.area and App.area.folder.Name or nil
local function on(...)
local bits = {}
for _, b in { ... } do
if b then
table.insert(bits, b)
end
end
return table.concat(bits, "  ·  ")
end
if m == "Paint" or m == "Erase" then
local erase = (m == "Erase") ~= (shift == true)
return erase and "Erasing ground" or "Painting ground", on(G.tool, area), erase
elseif m == "Spline" and App.shapeTool then
return "Placing a " .. string.lower(App.shapeTool),
on(App.shapeTool == "Rectangle" and "corner to corner" or "drag from the centre", area),
false
elseif m == "Spline" then
return "Drawing the path", on(area), false
elseif m == "Remove" then
return "Removing copies", on("click one to take it out", area), true
elseif LAYER_MODES[m] then
local act = shift and App.LAYER_OPPOSITE[m] or m
local name = App.paintLayer and App.paintLayer.inst.Name or "object"
return App.LAYER_LABEL[act] .. " · one object", on(name, area), act == "None" or act == "Less"
end
return nil, nil, false
end
local function build()
gui = new("ScreenGui", {
Name = "SmartScatterFocus",
Archivable = false,
IgnoreGuiInset = true,
DisplayOrder = 50,
ResetOnSpawn = false,
ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
group = new("CanvasGroup", { BackgroundTransparency = 1, GroupTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = gui })
frame = box({ Size = UDim2.fromScale(1, 1), Parent = group })
local line = App.stroke(P.accent)
line.Thickness, line.Transparency = 2, 0.55
line.Parent = frame
local inner = box({ Position = UDim2.fromOffset(2, 2), Size = UDim2.new(1, -4, 1, -4), Parent = group })
glowLine = App.stroke(P.accent)
glowLine.Thickness, glowLine.Transparency = 6, 0.9
glowLine.Parent = inner
local cornerText =
box({ Position = UDim2.fromOffset(16, 12), Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY, Parent = group })
dot = box({
BackgroundTransparency = 0,
BackgroundColor3 = P.accent,
Position = UDim2.fromOffset(0, 6),
Size = UDim2.fromOffset(7, 7),
Parent = cornerText,
}, { corner(4) })
local lines = box(
{ Position = UDim2.fromOffset(14, 0), Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY, Parent = cornerText },
{
new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 1) }),
}
)
title = label(
"",
14,
Color3.new(1, 1, 1),
SANS_B,
{ Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 1, Parent = lines }
)
detail = label(
"",
12,
Color3.fromRGB(215, 215, 215),
SANS_M,
{ Size = UDim2.fromOffset(0, 16), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2, Parent = lines }
)
keyRow = box({ Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 3, Parent = lines }, {
new("UIListLayout", {
FillDirection = Enum.FillDirection.Horizontal,
VerticalAlignment = Enum.VerticalAlignment.Center,
Padding = UDim.new(0, 10),
SortOrder = Enum.SortOrder.LayoutOrder,
}),
})
for _, t in { title, detail } do
t.TextStrokeColor3, t.TextStrokeTransparency = Color3.new(0, 0, 0), 0.55
t.TextTruncate = Enum.TextTruncate.None
end
pcall(function()
gui.Parent = game:GetService("CoreGui")
end)
end
local shown = false
App.refreshFocus = function()
local what, where, erase = describe()
local on = G.focus ~= false and what ~= nil
if on then
if not (gui and gui.Parent) then
build()
end
local col = erase and P.danger or P.accent
frame:FindFirstChildOfClass("UIStroke").Color = col
glowLine.Color = col
dot.BackgroundColor3 = col
title.Text = what
keyRow:ClearAllChildren()
new("UIListLayout", {
FillDirection = Enum.FillDirection.Horizontal,
VerticalAlignment = Enum.VerticalAlignment.Center,
Padding = UDim.new(0, 10),
SortOrder = Enum.SortOrder.LayoutOrder,
Parent = keyRow,
})
local painting = App.mode == "Paint" or App.mode == "Erase" or LAYER_MODES[App.mode] ~= nil
keyRow.Visible = painting and App.overlayLegend ~= nil
if keyRow.Visible then
for i, e in App.overlayLegend() do
local item = box({ Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = i, Parent = keyRow }, {
new("UIListLayout", {
FillDirection = Enum.FillDirection.Horizontal,
VerticalAlignment = Enum.VerticalAlignment.Center,
Padding = UDim.new(0, 4),
}),
})
local sw = box(
{ BackgroundTransparency = 0, BackgroundColor3 = e[1], Size = UDim2.fromOffset(9, 9), Parent = item },
{ corner(2) }
)
App.stroke(Color3.new(0, 0, 0)).Parent = sw
local t = label(
e[2],
11,
Color3.fromRGB(225, 225, 225),
SANS_M,
{ Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, Parent = item }
)
t.TextStrokeColor3, t.TextStrokeTransparency = Color3.new(0, 0, 0), 0.55
end
end
detail.Text = (where ~= "" and (where .. "  ·  ") or "") .. App.keyText("cancel") .. " to stop"
local cam = workspace.CurrentCamera
if cam and not (cc and cc.Parent == cam) then
cc = new(
"ColorCorrectionEffect",
{ Name = "SmartScatterFocus", Archivable = false, Saturation = 0, Brightness = 0, Contrast = 0, Parent = cam }
)
end
if not shown then
tween(group, MED, { GroupTransparency = 0 })
if cc then
tween(cc, MED, LOOK)
end
end
if cc then
cc.TintColor = Color3.new(1, 1, 1):Lerp(col, 0.05)
end
shown = true
elseif shown then
shown = false
if group then
tween(group, FAST, { GroupTransparency = 1 })
end
if cc then
local gone = cc
cc = nil
tween(gone, MED, { Saturation = 0, Brightness = 0, Contrast = 0 })
task.delay(0.3, function()
gone:Destroy()
end)
end
end
end
App.clearFocus = function()
shown = false
if cc then
cc:Destroy()
cc = nil
end
if gui then
gui:Destroy()
gui = nil
end
end
local cam = workspace.CurrentCamera
local old = cam and cam:FindFirstChild("SmartScatterFocus")
if old then
old:Destroy()
end
pcall(function()
local g = game:GetService("CoreGui"):FindFirstChild("SmartScatterFocus")
if g then
g:Destroy()
end
end)
end
end)()
-- #module App/Panel/Tour
MODULES["App/Panel/Tour"] = (function()
--[[
Smart Scatter — Tour: a guided tour of everything, shown once to each new user (and on demand from Settings).
Dims the panel except the part being explained, with a card next to it. Seen-state is a plugin setting, so every
person who installs the plugin gets it once on their own machine.
Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]
return function(App)
local plugin, P, G, RunService = App.plugin, App.P, App.G, App.RunService
local SANS, SANS_M, SANS_B = App.SANS, App.SANS_M, App.SANS_B
local new, corner, stroke, pad, vlist, hlist, box, col, label, para =
App.new, App.corner, App.stroke, App.pad, App.vlist, App.hlist, App.box, App.col, App.label, App.para
local TOUR_KEY = "SmartScatter_tour"
local TOUR_V = 3
local function ui(name)
local o = App.ui[name]
return o and o.Parent and o or nil
end
local function inArea()
return App.area ~= nil
end
local function shapeTab()
return inArea() and App.kindOf(App.area) == "Path" and "Map" or "Brush"
end
local STEPS = {
{
chapter = "Welcome",
image = "mark",
title = "Welcome to Smart Scatter",
text = "It fills your map by rules instead of by hand. You mark where things go, pick your models, and it places "
.. "them: trees keep off roads and roofs, rocks cluster, lamps line a road, fences meet round bends.\n\n"
.. "This tour shows everything in about three minutes. You can leave it any time and replay it from Settings.",
},
{
chapter = "Welcome",
title = "What it's good for",
text = "• Forests, jungles and flower fields that look natural\n"
.. "• Rocks, rubble and debris around cliffs and ruins\n"
.. "• Villages: crates, barrels and props around houses\n"
.. "• Street lamps, fences, walls and tiled paths along a curve\n"
.. "• Dressing a big open world or an obby's themed zones in minutes\n\n"
.. "Not for: one special prop you'd rather place by hand.",
},
{
chapter = "Areas",
title = "Your areas",
text = "Everything you make lives in an area. Click here to switch between them, rename one, lock it so nothing "
.. "changes, bake it into plain models when you're done, or delete it.",
target = function()
return ui("areaPick")
end,
},
{
chapter = "Areas",
title = "Three kinds",
text = "Scatter area: paint ground and fill it.\n"
.. "Path: draw a curve for fences, lamps, tiled paths or a road.\n"
.. "Keep-clear zone: ground no area may put anything on, like a spawn, a doorway or a quest spot.",
target = function()
return ui("plusBtn")
end,
},
{
chapter = "Areas",
title = "Four tabs",
text = "Scatter: what fills the area, its objects and their rules.\n"
.. "Brush: work by hand, painting ground or one object, removing copies.\n"
.. "Map: the path and its road; scanning a finished map to swap, re-space or re-season it.\n"
.. "Settings: the plugin itself.\n\n"
.. "Each tab shows the basics first; the rest is under More options. Lost? Type in the search box "
.. "below the tabs, like road or spacing.",
target = function()
local t = App.ui.tabs and App.ui.tabs.Scatter
return t and t.Parent or nil
end,
},
{
chapter = "Shape",
title = "Mark the ground",
text = function()
if inArea() and App.kindOf(App.area) == "Path" then
return "Press Draw path, then click in the viewport to place points. Hold and drag to draw freely."
end
return "Brush paints, Lasso and Box fill a shape, Polygon clicks corners, Fill takes a whole field in one click. "
.. "Shift erases, "
.. App.keyText("size")
.. " resizes the brush with the mouse, "
.. App.keyText("cancel")
.. " stops.\n\n"
.. "Fill selected parts turns the tops of picked parts (an island, a roof) into ground."
end,
tab = shapeTab,
target = function()
return ui("step1Card") or ui("welcomeChoice")
end,
},
{
chapter = "Shape",
title = "It reads the map for you",
text = "Each area is scanned: roads, paths, water, roofs and walls are found by their material and names, so "
.. "trees stay off the road and out of the pond on their own.\n\n"
.. "If it guesses wrong, select the part and use Mark selected as. Soft edges thin things out toward the "
.. "border so an area fades into its surroundings.",
},
{
chapter = "Paths",
title = "Drawing paths",
text = function()
return "Click to add points; drag one to move it. Shift+drag changes its height, "
.. App.keyText("corner")
.. " makes a sharp corner, "
.. App.keyText("delete")
.. " deletes a point. Select a point and click the ground to branch off; drop an end on another "
.. "point to join them.\n\n"
.. "Give the path a width and turn on Road to lay a real road or dirt path along it."
end,
},
{
chapter = "Objects",
title = "Add your models",
text = "Select models in the Explorer and press Add selected models. Keep the originals outside the "
.. "area, for example in ServerStorage.\n\n"
.. "No models yet? Start from a biome (Forest, Meadow, Desert, Town) or Get sample models. "
.. "Save a set you like as a preset to reuse it in any area.",
tab = function()
return "Scatter"
end,
target = function()
return ui("step2Card")
end,
},
{
chapter = "Objects",
title = "Rules for each object",
text = "Click an object for its settings. Its type (tree, rock, bush…) sets smart defaults; then tune amount, "
.. "size, spacing and clumping, piles, which ground it grows on, what it keeps away from, slopes and looks.\n\n"
.. "Mix several models in one object, Swap one for another in place, or Lock an object to keep its copies "
.. "exactly where they are.",
},
{
chapter = "Objects",
title = "Along a line",
text = "Set an object to Along and it follows a line instead of spreading out: a road edge, the area's border "
.. "or your path. Fences and walls resize so their pieces meet end to end, even round bends; lamps keep a "
.. "steady gap and face the road.",
},
{
chapter = "Placing",
title = "Placing it all",
text = "This bar stays at the bottom. Generate places the real models. Turn Live on for a quick preview: every "
.. "change shows right away as see-through boxes, and Generate turns them into the models.\n\n"
.. "Shuffle gives a new random layout, and Undo (or Ctrl+Z) takes back any step. The ticks above the bar "
.. "are your history: click one to jump back (or forward) to that step.",
target = function()
return ui("foot")
end,
},
{
chapter = "Placing",
title = "Settings",
text = "Text size, the overlay, and game-ready output: no collision on plants, fewer shadows, streaming "
.. "chunks for big maps. Preview as boxes places quick stand-ins while you tune a huge area.\n\n"
.. "Every shortcut is listed here too.",
target = function()
return App.ui.tabs and App.ui.tabs.Settings
end,
},
{
chapter = "Finish",
title = "When you're done",
text = "Areas stay editable, so you can come back and change anything. When an area is final, Bake it from the area menu: its "
.. "objects become plain models and the area steps aside.\n\n"
.. "Hover over anything for a tip, and right-click a slider to reset it. The plugin updates itself.",
},
{
chapter = "Finish",
image = "card",
title = "Have fun building",
text = "Smart Scatter is made by Ghulo.\n\n" .. "Replay this tour any time from Settings.",
},
}
local layer
local function finish()
App.tour = nil
pcall(function()
plugin:SetSetting(TOUR_KEY, TOUR_V)
end)
if layer then
layer:Destroy()
layer = nil
end
end
local function scrollTo(target)
local sc = App.scroll
if not (sc and target:IsDescendantOf(sc)) then
return
end
local top = target.AbsolutePosition.Y - sc.AbsolutePosition.Y + sc.CanvasPosition.Y
sc.CanvasPosition = Vector2.new(0, math.max(top - 12, 0))
end
local render
local function go(i)
if not App.tour then
return
end
App.tour.i = math.clamp(i, 1, #STEPS)
render()
end
render = function()
if layer then
layer:Destroy()
layer = nil
end
local root = App.root
App.hideTip()
if not App.tour or not root then
return
end
local i = App.tour.i
local step = STEPS[i]
local tab = step.tab and inArea() and step.tab()
if tab and G.page ~= tab then
App.goPage(tab)
return
end
local target = step.target and step.target()
if target then
scrollTo(target)
end
if App.tour.root ~= root then
App.tour.root = root
root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
if App.tour and App.root == root then
App.renderTour()
end
end)
end
layer = box({ Size = UDim2.fromScale(1, 1), ZIndex = 300, Parent = root })
local my = layer
RunService.Heartbeat:Wait()
if layer ~= my or not root.Parent then
return
end
local rw, rh = root.AbsoluteSize.X, root.AbsoluteSize.Y
local ox, oy = root.AbsolutePosition.X, root.AbsolutePosition.Y
local function shade(x, y, w, h)
if w <= 0 or h <= 0 then
return
end
new("TextButton", {
Text = "",
AutoButtonColor = false,
BackgroundColor3 = Color3.new(0, 0, 0),
BackgroundTransparency = 0.45,
Position = UDim2.fromOffset(x, y),
Size = UDim2.fromOffset(w, h),
ZIndex = 301,
Parent = layer,
})
end
local hx, hy, hw, hh
if target then
local m = 4
hx = math.clamp(target.AbsolutePosition.X - ox - m, 0, rw)
hy = math.clamp(target.AbsolutePosition.Y - oy - m, 0, rh)
hw = math.clamp(target.AbsoluteSize.X + m * 2, 0, rw - hx)
hh = math.clamp(target.AbsoluteSize.Y + m * 2, 0, rh - hy)
shade(0, 0, rw, hy)
shade(0, hy + hh, rw, rh - hy - hh)
shade(0, hy, hx, hh)
shade(hx + hw, hy, rw - hx - hw, hh)
local ring = box({
Position = UDim2.fromOffset(hx, hy),
Size = UDim2.fromOffset(hw, hh),
ZIndex = 302,
Parent = layer,
}, { corner(10) })
local st = stroke(P.accent)
st.Thickness = 2
st.Parent = ring
else
shade(0, 0, rw, rh)
end
local w = math.min(rw - 24, 300)
local card = col({
BackgroundTransparency = 0,
BackgroundColor3 = P.card,
Size = UDim2.fromOffset(w, 0),
ZIndex = 303,
Parent = layer,
}, { corner(12), stroke(P.line), pad(16, 16, 14, 14), vlist(8) })
local function z(o)
o.ZIndex = 304
for _, d in o:GetDescendants() do
if d:IsA("GuiObject") then
d.ZIndex = 304
end
end
return o
end
local dots = z(box({ Size = UDim2.new(1, 0, 0, 8), Parent = card }, { hlist(5) }))
for k = 1, #STEPS do
z(box({
BackgroundTransparency = 0,
BackgroundColor3 = k == i and P.accent or P.line,
Size = UDim2.fromOffset(k == i and 18 or 8, 6),
Parent = dots,
}, { corner(3) }))
end
z(label(string.upper(step.chapter) .. "  ·  " .. i .. " of " .. #STEPS, 10, P.faint, SANS_B, { Parent = card }))
if step.image == "mark" then
z(new("ImageLabel", { Image = App.LOGO.mark, BackgroundTransparency = 1, Size = UDim2.fromOffset(56, 56), Parent = card }))
elseif step.image == "card" then
local holder = z(box({ Size = UDim2.new(1, 0, 0, 160), Parent = card }))
z(new("ImageLabel", {
Image = App.LOGO.card,
BackgroundTransparency = 1,
AnchorPoint = Vector2.new(0.5, 0),
Position = UDim2.fromScale(0.5, 0),
Size = UDim2.fromOffset(131, 160),
Parent = holder,
}))
end
local t = z(label(step.title, 17, P.text, SANS_B, { Parent = card }))
t.TextWrapped = true
t.TextTruncate = Enum.TextTruncate.None
t.AutomaticSize = Enum.AutomaticSize.Y
t.Size = UDim2.new(1, 0, 0, 0)
local body = z(para(type(step.text) == "function" and step.text() or step.text, { Parent = card }))
body.TextSize = App.textSize(13)
body.TextColor3 = P.dim
box({ Size = UDim2.new(1, 0, 0, 4), Parent = card })
local row = z(box({ Size = UDim2.new(1, 0, 0, 32), Parent = card }))
local function btn(text, primary, onClick)
local b = new("TextButton", {
Text = text,
Font = primary and SANS_B or SANS_M,
TextSize = 13,
TextColor3 = primary and P.onAccent or P.text,
BackgroundColor3 = primary and P.accent or P.raised,
AutoButtonColor = false,
Size = UDim2.fromOffset(0, 32),
AutomaticSize = Enum.AutomaticSize.X,
ZIndex = 304,
}, { corner(8), pad(14, 14, 0, 0) })
local rest = b.BackgroundColor3
b.MouseEnter:Connect(function()
b.BackgroundColor3 = rest:Lerp(Color3.new(1, 1, 1), 0.1)
end)
b.MouseLeave:Connect(function()
b.BackgroundColor3 = rest
end)
b.MouseButton1Click:Connect(onClick)
return b
end
local last = i == #STEPS
if not last then
local skip = new("TextButton", {
Text = "Skip tour",
Font = SANS,
TextSize = 13,
TextColor3 = P.faint,
BackgroundTransparency = 1,
Size = UDim2.fromOffset(70, 32),
TextXAlignment = Enum.TextXAlignment.Left,
ZIndex = 304,
Parent = row,
})
skip.MouseEnter:Connect(function()
skip.TextColor3 = P.text
end)
skip.MouseLeave:Connect(function()
skip.TextColor3 = P.faint
end)
skip.MouseButton1Click:Connect(finish)
end
local right = box({
Size = UDim2.new(0, 0, 1, 0),
AutomaticSize = Enum.AutomaticSize.X,
AnchorPoint = Vector2.new(1, 0),
Position = UDim2.fromScale(1, 0),
ZIndex = 304,
Parent = row,
}, { hlist(6) })
if i > 1 then
btn("Back", false, function()
go(i - 1)
end).Parent = right
end
btn(last and "Got it" or (i == 1 and "Show me" or "Next"), true, function()
if last then
finish()
else
go(i + 1)
end
end).Parent =
right
local x = math.floor((rw - w) / 2)
card.Position = UDim2.fromOffset(x, 0)
RunService.Heartbeat:Wait()
if layer ~= my then
return
end
local ch = card.AbsoluteSize.Y
local y
if not target then
y = (rh - ch) / 2
elseif hy + hh + 10 + ch <= rh - 8 then
y = hy + hh + 10
elseif hy - 10 - ch >= 8 then
y = hy - 10 - ch
else
y = rh - ch - 12
end
card.Position = UDim2.fromOffset(x, math.floor(math.max(y, 8)))
end
App.renderTour = function()
task.spawn(render)
end
App.startTour = function()
if App.mode ~= "Off" then
App.setMode("Off")
end
App.tour = { i = 1 }
if G.page == "Settings" then
App.goPage("")
else
App.renderTour()
end
end
App.maybeStartTour = function()
local ok, seen = pcall(function()
return plugin:GetSetting(TOUR_KEY)
end)
if ok and type(seen) == "number" and seen >= TOUR_V then
return
end
if not App.widget.Enabled then
return
end
task.delay(0.5, function()
if App.root and not App.tour then
App.startTour()
end
end)
end
end
end)()
-- #module App/Core/Lifecycle
MODULES["App/Core/Lifecycle"] = (function()
--[[
Smart Scatter — Lifecycle: undo/redo reload, wiring and cleanup.
Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]
return function(App)
local ChangeHistoryService, ctx, plugin, Engine, conns = App.ChangeHistoryService, App.ctx, App.plugin, App.Engine, App.conns
local track, LAYER_MODES, toggleBtn, clearOverlay = App.track, App.LAYER_MODES, App.toggleBtn, App.clearOverlay
local switchArea, eachThumb, closePopup, removeGizmo = App.switchArea, App.eachThumb, App.closePopup, App.removeGizmo
local removeSplineViz = App.removeSplineViz
local function alive(folder)
return folder ~= nil and folder:IsDescendantOf(workspace)
end
local function afterHistory()
local f = App.area and App.area.folder
local keep = App.expanded and Engine.layerKey(App.expanded)
App.resetSplineDrag(true)
App.stopGestures()
if LAYER_MODES[App.mode] then
App.setMode("Off")
end
switchArea(alive(f) and f or Engine.listAreas()[1])
if keep and App.area then
for _, l in App.area.layers do
if Engine.layerKey(l) == keep then
App.expanded = l
end
end
App.rebuildAll()
end
if App.canGenerate() then
App.runGenerate(false)
end
end
App.afterHistory = afterHistory
local function onHistory(name)
local echoes = App.historyEchoes
if echoes and echoes.rebuild > 0 then
echoes.rebuild -= 1
return
end
if type(name) ~= "string" or not string.find(name, "Smart Scatter", 1, true) then
return
end
task.defer(afterHistory)
end
track(ChangeHistoryService.OnUndo:Connect(onHistory))
track(ChangeHistoryService.OnRedo:Connect(onHistory))
track(toggleBtn.Click:Connect(function()
App.widget.Enabled = not App.widget.Enabled
end))
track(App.widget:GetPropertyChangedSignal("Enabled"):Connect(function()
toggleBtn:SetActive(App.widget.Enabled)
if App.widget.Enabled then
local f = App.area and App.area.folder
switchArea(alive(f) and f or Engine.listAreas()[1])
App.maybeStartTour()
else
if App.mode ~= "Off" then
App.setMode("Off")
end
closePopup()
clearOverlay()
App.drawSpline()
end
end))
switchArea(Engine.listAreas()[1])
toggleBtn:SetActive(App.widget.Enabled)
App.maybeStartTour()
ctx.offerUpdate = function(version, apply)
App.dialog(
"Update available",
"Smart Scatter " .. tostring(version) .. " is ready. Updating takes a second, needs no restart and changes nothing in your place.",
{ { "Update now", "accent", apply }, { "Later", nil, function() end } },
"info",
"accent"
)
end
if ctx.reloaded then
App.status("Updated to v" .. tostring(ctx.version) .. ".")
end
return function()
App.cancelJob()
pcall(App.stopGestures)
if App.mode ~= "Off" then
App.mode = "Off"
pcall(function()
plugin:Deactivate()
end)
end
for _, c in conns do
c:Disconnect()
end
removeGizmo()
removeSplineViz()
clearOverlay()
if App.clearFocus then
App.clearFocus()
end
if App.root then
App.root:Destroy()
App.root = nil
end
eachThumb(function(vp)
vp:Destroy()
end)
end
end
end)()

return MODULES
