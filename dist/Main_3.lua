-- GENERATED part 3 of the flattened release by tools/tree.py: edit the modules, not this.
local MODULES = {}

-- #module App/Viewport/Toolbar
MODULES["App/Viewport/Toolbar"] = (function()
--[[
Smart Scatter — Toolbar: the viewport's tools, like Blender's; the one place tools live. Down the left edge, a strip
of small square tool buttons in groups (the tools the features registered: Core/Registry), the one in use lit.
Along the top, while a tool is on, a bar with what it acts on and its settings (the brush's size and shape, the
stamp's turn, size and model, the path's shapes), so the eyes can stay on the viewport.
Both follow the state they show (looked at ten times a second, rebuilt only when it changes), so no other module
has to tell them. Where Studio won't show them (no CoreGui), the panel shows the same tools as a row
(App.buildToolRow).
Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]
return function(App)
local G, saveG, P, Engine = App.G, App.saveG, App.P, App.Engine
local new, box, label, corner, stroke, pad = App.new, App.box, App.label, App.corner, App.stroke, App.pad
local SANS, SANS_B = App.SANS, App.SANS_B
local BTN, SEE = 30, 0.12
local gui, strip, bar, tip
local stripKey, barKey
local looks = {}
local function showTip(b, text)
tip.Visible = text ~= nil
if text then
tip.Text = text
tip.Position = UDim2.fromOffset(strip.AbsolutePosition.X + strip.AbsoluteSize.X + 6, b.AbsolutePosition.Y + (BTN - 24) / 2)
end
end
local function buildStrip()
for _, c in strip:GetChildren() do
if c:IsA("GuiObject") then
c:Destroy()
end
end
table.clear(looks)
for gi, g in App.toolGroups() do
local group = g.tools
if gi > 1 then
box({ Size = UDim2.fromOffset(BTN, 7), Parent = strip }, {
new("Frame", {
BackgroundColor3 = P.line,
BorderSizePixel = 0,
Position = UDim2.fromOffset(5, 3),
Size = UDim2.new(1, -10, 0, 1),
}),
})
end
for _, t in group do
local b = new("TextButton", {
Text = "",
AutoButtonColor = false,
BackgroundColor3 = P.accent,
BackgroundTransparency = 1,
Size = UDim2.fromOffset(BTN, BTN),
Parent = strip,
}, { corner(6) })
local ic = App.icon(t.icon, 16, P.dim)
ic.AnchorPoint, ic.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
ic.Parent = b
local hot = false
local function look()
local on = t.on()
local tint = t.danger and P.danger or P.accent
b.BackgroundColor3 = on and tint or P.hover
b.BackgroundTransparency = on and 0 or hot and 0.2 or 1
App.setIconColor(
ic,
on and (t.danger and Color3.new(1, 1, 1) or P.onAccent) or hot and P.text or (t.danger and tint:Lerp(P.dim, 0.3) or P.dim)
)
end
look()
table.insert(looks, look)
b.MouseEnter:Connect(function()
hot = true
look()
showTip(b, (string.match(t.name, "^([^:]+)") or t.name) .. (t.key and ("   " .. App.keyText(t.key)) or ""))
end)
b.MouseLeave:Connect(function()
hot = false
look()
showTip(b, nil)
end)
b.MouseButton1Click:Connect(function()
t.click()
for _, f in looks do
f()
end
end)
end
end
end
local function stepRadius(up)
G.radius = math.clamp(math.floor(G.radius * (up and 1.2 or 1 / 1.2) + 0.5), 4, 200)
saveG()
App.refreshSliders()
end
local function stampChanged()
if App.refreshStamp then
App.refreshStamp()
end
end
local function options()
local m = App.mode
if m == "Off" then
return nil
end
local items = {}
local title
local brushSize = {
step = "Size",
value = string.format("%d", G.radius),
dec = function()
stepRadius(false)
end,
inc = function()
stepRadius(true)
end,
}
if m == "Paint" or m == "Erase" then
title = (m == "Erase" and "Erase" or "Paint") .. " · " .. G.tool .. (App.area and (" · " .. App.area.folder.Name) or "")
if G.tool == "Brush" then
table.insert(items, brushSize)
for _, s in { "Circle", "Square" } do
table.insert(items, {
button = s,
on = G.shape == s,
click = function()
G.shape = s
saveG()
end,
})
end
elseif G.tool == "Fill" then
table.insert(items, {
step = "Reach",
value = string.format("%d", G.fillReach),
dec = function()
G.fillReach = math.clamp(G.fillReach - 16, 16, 400)
saveG()
App.refreshSliders()
end,
inc = function()
G.fillReach = math.clamp(G.fillReach + 16, 16, 400)
saveG()
App.refreshSliders()
end,
})
else
table.insert(items, { text = App.TOOL_HINT and App.TOOL_HINT[G.tool] or "" })
end
elseif m == "Stamp" then
local st = App.stamp
local models = st.models
local cur = models[st.vi] or models[1]
title = "Stamp · " .. (cur and cur.Name or "")
table.insert(items, {
step = "Turn",
value = string.format("%d°", math.floor(math.deg(st.yaw) + 0.5) % 360),
dec = function()
App.setStamp(math.deg(st.yaw) - 15)
stampChanged()
end,
inc = function()
App.setStamp(math.deg(st.yaw) + 15)
stampChanged()
end,
})
table.insert(items, {
step = "Size",
value = string.format("%.2f×", st.k),
dec = function()
App.setStamp(nil, math.max(st.k / 1.1, 0.05))
stampChanged()
end,
inc = function()
App.setStamp(nil, math.min(st.k * 1.1, 20))
stampChanged()
end,
})
if #models > 1 then
table.insert(items, {
step = "Model",
value = cur.Name,
dec = function()
App.setStamp(nil, nil, (st.vi - 2) % #models + 1)
stampChanged()
end,
inc = function()
App.setStamp(nil, nil, st.vi % #models + 1)
stampChanged()
end,
})
end
table.insert(items, { button = "Random", click = App.rollStamp })
elseif App.LAYER_MODES[m] and App.paintLayer then
title = App.LAYER_LABEL[m] .. " · " .. App.paintLayer.inst.Name
table.insert(items, brushSize)
elseif m == "Spline" then
title = App.shapeTool and ("Path · " .. App.shapeTool) or "Path"
for _, d in Engine.SHAPES do
table.insert(items, {
button = d.name,
on = App.shapeTool == d.name,
click = function()
App.pickShape(d.name)
end,
})
end
if App.hasPath() then
table.insert(items, { button = "Subdivide", click = App.subdivideSpline })
end
elseif m == "Select" then
title = "Select"
table.insert(items, { text = "Click a zone's ground, a path or a placed copy" })
elseif m == "Remove" then
title = "Remove copies"
table.insert(items, { text = "Click a copy to take it out" })
else
return nil
end
return title, items
end
local function buildBar()
for _, c in bar:GetChildren() do
if c:IsA("GuiObject") then
c:Destroy()
end
end
local title, items = options()
bar.Visible = title ~= nil
if not title then
return
end
label(title, 12, P.text, SANS_B, { Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, Parent = bar })
local function small(text, click, on)
local b = new("TextButton", {
Text = text,
Font = SANS,
TextSize = 12,
TextColor3 = on and P.onAccent or P.text,
AutoButtonColor = false,
BackgroundColor3 = on and P.accent or P.raised,
Size = UDim2.fromOffset(0, 24),
AutomaticSize = Enum.AutomaticSize.X,
Parent = bar,
}, { corner(5), pad(8, 8, 0, 0) })
b.MouseEnter:Connect(function()
if not on then
b.BackgroundColor3 = P.hover
end
end)
b.MouseLeave:Connect(function()
b.BackgroundColor3 = on and P.accent or P.raised
end)
b.MouseButton1Click:Connect(click)
return b
end
for _, it in items do
box({ BackgroundTransparency = 0, BackgroundColor3 = P.line, Size = UDim2.fromOffset(1, 16), Parent = bar })
if it.text then
label(it.text, 12, P.dim, SANS, { Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, Parent = bar })
elseif it.step then
label(it.step, 12, P.dim, SANS, { Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, Parent = bar })
small("−", it.dec).Size = UDim2.fromOffset(22, 24)
label(it.value, 12, P.text, SANS_B, {
Size = UDim2.fromOffset(0, 24),
AutomaticSize = Enum.AutomaticSize.X,
TextXAlignment = Enum.TextXAlignment.Center,
Parent = bar,
})
small("+", it.inc).Size = UDim2.fromOffset(22, 24)
else
small(it.button, it.click, it.on)
end
end
end
local function build()
gui = new("ScreenGui", {
Name = "SmartScatterToolbar",
Archivable = false,
IgnoreGuiInset = true,
DisplayOrder = 55,
ResetOnSpawn = false,
ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
local function panel(props, layout)
local f = box(props, { corner(8), stroke(P.line), layout })
f.BackgroundTransparency, f.BackgroundColor3 = SEE, P.card
return f
end
strip = panel(
{ AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), AutomaticSize = Enum.AutomaticSize.XY, Parent = gui },
new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) })
)
pad(3, 3, 3, 3).Parent = strip
bar = panel(
{
AnchorPoint = Vector2.new(0.5, 0),
Position = UDim2.new(0.5, 0, 0, 10),
AutomaticSize = Enum.AutomaticSize.XY,
Visible = false,
Parent = gui,
},
new("UIListLayout", {
FillDirection = Enum.FillDirection.Horizontal,
VerticalAlignment = Enum.VerticalAlignment.Center,
SortOrder = Enum.SortOrder.LayoutOrder,
Padding = UDim.new(0, 6),
})
)
pad(10, 5, 4, 4).Parent = bar
tip = label("", 12, P.text, SANS, {
BackgroundTransparency = 0,
BackgroundColor3 = P.raised,
Size = UDim2.fromOffset(0, 24),
AutomaticSize = Enum.AutomaticSize.X,
Visible = false,
Parent = gui,
})
corner(5).Parent = tip
pad(8, 8, 0, 0).Parent = tip
stripKey, barKey = nil, nil
if not pcall(function()
gui.Parent = game:GetService("CoreGui")
end) then
gui:Destroy()
gui = nil
end
end
local function keys()
local a = App.area
local l = App.brushTarget()
local sel = App.selected
local s = string.format(
"%s|%s|%s|%d|%s",
a and a.folder.Name or "",
a and App.kindOf(a) or "",
l and l.inst.Name or "",
a and #a.layers or 0,
sel and sel.kind or ""
)
local st = App.stamp or {}
local b = table.concat({
App.mode,
G.tool,
G.radius,
G.shape,
G.fillReach,
tostring(App.paintLayer and App.paintLayer.inst.Name),
tostring(App.shapeTool),
tostring(App.hasPath and App.hasPath()),
string.format("%.3f|%.3f|%s|%d", st.yaw or 0, st.k or 0, tostring(st.vi), st.models and #st.models or 0),
}, "|")
return s, b
end
local function refresh()
local want = App.widget.Enabled and not App.ctx.preview
if not want then
if gui then
gui.Enabled = false
end
return
end
if not (gui and gui.Parent) then
build()
if not gui then
return
end
end
gui.Enabled = true
local s, b = keys()
if s ~= stripKey then
stripKey = s
buildStrip()
else
for _, f in looks do
f()
end
end
if b ~= barKey then
barKey = b
buildBar()
end
end
App.refreshToolbar = refresh
local last = 0
App.track(App.RunService.Heartbeat:Connect(function()
if os.clock() - last >= 0.1 then
last = os.clock()
refresh()
end
end))
App.overViewportUI = function()
if not (gui and gui.Enabled) then
return false
end
local m = Vector2.new(App.rawMouse.X, App.rawMouse.Y)
for _, f in { strip, bar } do
if f.Visible then
local p, sz = f.AbsolutePosition, f.AbsoluteSize
if m.X >= p.X and m.X <= p.X + sz.X and m.Y >= p.Y and m.Y <= p.Y + sz.Y then
return true
end
end
end
return false
end
App.toolbarAvailable = function()
if App.ctx.preview then
return false
end
if not (gui and gui.Parent) then
refresh()
end
return gui ~= nil
end
App.buildToolRow = function(parent)
local row = App.col({ Parent = parent }, {
new("UIGridLayout", {
CellSize = UDim2.fromOffset(BTN, BTN),
CellPadding = UDim2.fromOffset(3, 3),
SortOrder = Enum.SortOrder.LayoutOrder,
}),
})
local n = 0
for _, g in App.toolGroups() do
for _, t in g.tools do
n += 1
local b = App.iconButton(t.icon, (string.match(t.name, "^([^:]+)") or t.name), function()
t.click()
App.rebuildAll()
end, t.on(), BTN)
b.LayoutOrder = n
b.Parent = row
end
end
return row
end
App.clearToolbar = function()
if gui then
gui:Destroy()
gui = nil
end
end
pcall(function()
if App.ctx.preview then
return
end
local old = game:GetService("CoreGui"):FindFirstChild("SmartScatterToolbar")
if old then
old:Destroy()
end
end)
end
end)()
-- #module App/Panel/Palette
MODULES["App/Panel/Palette"] = (function()
--[[
Smart Scatter — Palette: the search menu, like Blender's F3 (Space here, or whatever Settings › Shortcuts says).
Pressed anywhere in the viewport while the panel is open, it opens at the mouse: type a few letters of anything the
plugin can do, pick it with the arrow keys and Enter (or a click), and it's done. Actions that take things away
for good ask first. With nothing typed it lists the last few used, then everything, by group. What can't be done
right now isn't listed at all. A last line searches the panel's settings for what was typed.
The actions are listed here, in one place, each calling what the module that owns it put on App.
Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]
return function(App)
local G, saveG, P, Engine = App.G, App.saveG, App.P, App.Engine
local new, box, label, corner, stroke, pad = App.new, App.box, App.label, App.corner, App.stroke, App.pad
local SANS, SANS_M, SANS_B = App.SANS, App.SANS_M, App.SANS_B
local UIS = game:GetService("UserInputService")
local ROW, HEAD, SHOWN, WIDTH = 30, 22, 10, 500
local BLUR, DIM = 6, { Saturation = -0.25, Brightness = -0.04 }
local SEE = 0.08
local RECENT = 5
local GROUP_ICON = {
Generate = "logo",
Edit = "undo",
["Paint the ground"] = "brush",
Objects = "layers",
["By hand"] = "stamp",
Path = "spline",
Areas = "area",
World = "search",
Tools = "cursor",
View = "settings",
["Go to"] = "right",
}
local TOOL_ICON = { Brush = "brush", Lasso = "lasso", Box = "box", Polygon = "polygon", Fill = "fill" }
local HAND = {
{ "Place", "Spray", "spray", "place pins copies brush" },
{ "More", "More", "plus", "thicker paint" },
{ "Less", "Less", "minus", "thinner paint" },
{ "None", "Erase", "trash", "none remove paint" },
}
local CARDS = {
{ "Map scan", "world", "mapscan", nil, "find kinds repeated models duplicates" },
{ "Swap models", "world", "swap", nil, "replace kind" },
{ "Improve layout", "world", "layout", nil, "respace even gaps crowded" },
{ "Seasons", "world", "seasons", nil, "snow snowy autumn winter dry fall" },
{ "Snapshot and restore", "world", "snapshot", nil, "backup originals put back" },
{ "Fix what the scan sees", "world", "scanfix", "world", "mark road building water" },
{ "Curve of the path", "curve", "curve", nil, "strip width snap walls loop closed" },
{ "Road", "road", "road", nil, "asphalt surface style" },
{ "Objects", "objects", "objects", nil, "models list amount size" },
{ "Start from a biome", "objects", "biomes", "objects", "forest meadow desert town" },
{ "Presets", "objects", "presets", "objects", "save load share code" },
{ "Performance", "objects", "performance", "objects", "report parts heavy" },
{ "Ground", "zone", "ground", nil, "painted overlay colours fill selected parts erase all" },
{ "Pattern", "zone", "pattern", nil, "groves islands veins spots bands" },
{ "Colour zones", "zone", "zones", "zone", "color mood autumn lush frost" },
{ "Edges and wind", "zone", "edges", "zone", "soft edge lean" },
{ "Paint only on", "zone", "paintfilter", "zone", "surfaces filter" },
{ "Tidy the edge", "zone", "tidy", "zone", "holes smooth grow shrink" },
{ "Look: accent and text size", "settings", "look", nil, "theme colour font" },
{ "Viewport settings", "settings", "viewport", nil, "overlay focus grid history" },
{ "Game-ready output", "settings", "output", nil, "collision shadows streaming chunks boxes" },
{ "Shortcuts", "settings", "shortcuts", "settings", "keys keybind hotkey" },
}
local function actions()
local list = {}
local function add(a)
a.icon = a.icon or GROUP_ICON[a.group]
table.insert(list, a)
end
local a = App.area
local kind = a and App.kindOf(a)
local open = a and not a.locked
if a then
add({
id = "generate",
name = App.busy() and "Stop generating" or "Generate",
group = "Generate",
words = "place build run",
run = App.generateNow,
})
if open then
add({
id = "shuffle",
name = "Shuffle the layout",
group = "Generate",
icon = "refresh",
key = "shuffle",
words = "random new seed",
run = App.shuffle,
})
end
end
add({
id = "live",
name = G.live and "Turn Live off" or "Turn Live on",
group = "Generate",
words = "live preview boxes automatic",
run = App.toggleLive,
})
add({
id = "undo",
name = "Undo",
group = "Edit",
words = "back ctrl z",
run = function()
App.undoStep()
end,
})
add({
id = "redo",
name = "Redo",
group = "Edit",
words = "forward ctrl y",
run = function()
App.undoStep(true)
end,
})
if open and kind ~= "Path" then
for i, t in App.TOOLS do
add({
id = "tool" .. t,
name = "Paint with the " .. string.lower(t),
group = "Paint the ground",
icon = TOOL_ICON[t],
key = "tool" .. i,
run = function()
App.setTool(t)
end,
})
end
add({
id = "erase",
name = "Erase ground",
group = "Paint the ground",
icon = "trash",
key = "erase",
words = "remove unpaint",
run = function()
App.setMode("Erase")
end,
})
add({
id = "fillsel",
name = "Fill selected parts",
group = "Paint the ground",
words = "island roof platform tops",
run = App.fillSelection,
})
if (a.count or 0) > 0 then
for _, m in
{ { "holes", "Fill holes" }, { "smooth", "Smooth the edge" }, { "grow", "Grow the area" }, { "shrink", "Shrink the area" } }
do
add({
id = "tidy" .. m[1],
name = m[2],
group = "Paint the ground",
words = "tidy edge",
run = function()
App.maskOp(m[1], m[2])
end,
})
end
add({
id = "eraseall",
name = "Erase all paint",
group = "Paint the ground",
icon = "trash",
words = "clear delete everything",
danger = "Removes all painted ground in this area and what was placed on it. Your objects and settings stay.",
run = App.eraseAllPaint,
})
end
end
if a and kind ~= "Clear" then
if open then
add({
id = "addsel",
name = "Add selected models",
group = "Objects",
icon = "plus",
words = "new object add model",
run = App.addSelected,
})
end
for _, l in a.layers do
local name = l.inst.Name
add({
id = "open:" .. name,
name = name .. " settings",
group = "Objects",
words = "open rules object " .. l.type,
run = function()
App.showObject(l)
end,
})
add({
id = "stamp:" .. name,
name = "Stamp " .. name,
group = "By hand",
icon = "stamp",
words = "one copy single place rotate turn model",
run = function()
App.startStamp(l)
end,
})
if open and kind ~= "Path" and not (Engine.isLine(l) and l.s.follow == "Spline") then
for _, h in HAND do
add({
id = h[1] .. ":" .. name,
name = h[2] .. " " .. name,
group = "By hand",
icon = h[3],
words = h[4],
run = function()
App.setMode(h[1], l)
end,
})
end
end
end
if open then
add({
id = "remove",
name = "Remove single copies",
group = "By hand",
icon = "close",
words = "delete copy click",
run = function()
App.setMode("Remove")
end,
})
end
end
add({
id = "stampsel",
name = App.mode == "Stamp" and "Stop stamping" or "Stamp the selected models",
group = "By hand",
icon = "stamp",
words = "one copy single place model anywhere",
run = function()
if App.mode == "Stamp" then
App.setMode("Off")
else
App.startStamp()
end
end,
})
if open and kind ~= "Clear" then
add({
id = "drawpath",
name = App.hasPath() and "Keep drawing the path" or "Draw a path",
group = "Path",
words = "spline curve road fence points",
run = function()
App.ensureSplineFn()
App.setMode("Spline")
end,
})
for _, d in Engine.SHAPES do
add({
id = "shape" .. d.name,
name = "Path shape: " .. d.name,
group = "Path",
words = "preset loop fence ring",
run = function()
App.pickShape(d.name)
end,
})
end
if App.hasPath() then
add({ id = "subdivide", name = "Subdivide the path", group = "Path", words = "add points vertices", run = App.subdivideSpline })
add({
id = "clearpath",
name = "Clear the path",
group = "Path",
icon = "trash",
danger = "Removes every point, branch and shape of this path.",
run = function()
App.clearSplineFn(App.beginRec("Smart Scatter: Clear spline"))
App.rebuildAll()
end,
})
end
end
local COVERED = { search = true, remove = true, stamp = true, path = true }
for _, g in App.toolGroups() do
for _, t in g.tools do
if not (COVERED[t.id] or string.match(t.id, "^ground:") or string.match(t.id, "^object:")) then
add({
id = "tool:" .. t.id,
name = string.match(t.name, "^([^:]+)") or t.name,
group = "Tools",
icon = t.icon,
key = t.key,
words = t.name,
run = t.click,
})
end
end
end
add({
id = "newarea",
name = "New zone",
group = "Areas",
words = "create add scatter area",
run = function()
App.newArea()
end,
})
add({
id = "newzonefrom",
name = "New zone from the selected models",
group = "Areas",
words = "create add scatter area selection explorer",
run = App.newZoneFromSelection,
})
add({
id = "newpath",
name = "New path",
group = "Areas",
icon = "spline",
words = "create add road fence",
run = function()
App.newSplineFn()
end,
})
add({
id = "newclear",
name = "New keep-clear zone",
group = "Areas",
icon = "clear",
words = "create spawn door",
run = function()
App.newArea({ kind = "Clear" })
end,
})
for _, f in Engine.listAreas() do
if not (a and f == a.folder) then
add({
id = "switch:" .. f.Name,
name = "Switch to " .. f.Name,
group = "Areas",
words = "area open go",
run = function()
App.switchArea(f)
App.rebuildAll()
end,
})
end
end
if a then
add({ id = "lock", name = a.locked and "Unlock this area" or "Lock this area", group = "Areas", run = App.toggleLock })
if kind ~= "Clear" then
add({ id = "clearplaced", name = "Clear placed objects", group = "Areas", words = "empty remove", run = App.clearPlaced })
end
add({ id = "bake", name = "Bake to plain models", group = "Areas", words = "finish final export", run = App.bakeArea })
add({
id = "deletearea",
name = "Delete this area",
group = "Areas",
icon = "trash",
danger = "Deletes " .. a.folder.Name .. " and everything it placed.",
run = App.deleteArea,
})
end
for _, c in CARDS do
add({
id = "card:" .. c[3],
name = c[1],
group = c[2] == "world" and "World" or "Go to",
words = c[5],
run = function()
if not App.openCard(c[2], c[3], c[4]) then
App.status(c[1] .. " isn't there for this area.")
end
end,
})
end
for _, t in App.tabsFor(App.selected, App.active) do
add({
id = "tab:" .. t.id,
name = t.title .. " tab",
group = "Go to",
words = "page open properties",
run = function()
App.openTab(t.id)
end,
})
end
add({
id = "tab:settings",
name = "Settings",
group = "Go to",
words = "page open preferences options",
run = function()
App.openSettings(true)
end,
})
add({
id = "overlay",
name = App.overlayHidden and "Show the overlay" or "Hide the overlay",
group = "View",
key = "overlay",
run = function()
App.overlayHidden = not App.overlayHidden
App.rebuildOverlay()
App.drawSpline()
end,
})
for _, s in
{
{
"focus",
"Focus while a tool is on",
function()
App.refreshFocus()
end,
},
{
"toolbar",
"Tools in the viewport",
function()
App.refreshToolbar()
end,
},
{
"grid",
"Brush grid",
function()
App.clearGrid()
end,
},
{
"history",
"History timeline",
function()
App.rebuildAll()
end,
},
}
do
add({
id = "view:" .. s[1],
name = s[2] .. (G[s[1]] ~= false and ": turn off" or ": turn on"),
group = "View",
run = function()
G[s[1]] = G[s[1]] == false
saveG()
s[3]()
end,
})
end
add({
id = "tour",
name = "Replay the tour",
group = "View",
icon = "info",
words = "help learn guide",
run = function()
App.startTour()
end,
})
return list
end
local function score(words, a)
local name = string.lower(a.name)
local extra = string.lower(a.group .. " " .. (a.words or ""))
local total, spans = 0, {}
for _, w in words do
local i = string.find(name, w, 1, true)
if i then
local atWord = i == 1 or string.sub(name, i - 1, i - 1) == " "
total += (i == 1 and 6 or atWord and 4 or 2) + #w * 0.1
table.insert(spans, { i, i + #w - 1 })
elseif string.find(extra, w, 1, true) then
total += 1
elseif #w >= 2 then
local pos, hits = 1, {}
for ch in string.gmatch(w, ".") do
local j = string.find(name, ch, pos, true)
if not j then
return nil
end
table.insert(hits, { j, j })
pos = j + 1
end
total += 0.5
for _, h in hits do
table.insert(spans, h)
end
else
return nil
end
end
return total, spans
end
App.paletteScore = score
local function marked(name, spans)
local on = {}
for _, s in spans or {} do
for k = s[1], s[2] do
on[k] = true
end
end
local hex = P.accent:ToHex()
local out = {}
for k = 1, #name do
local ch = string.sub(name, k, k)
ch = ch == "&" and "&amp;" or ch == "<" and "&lt;" or ch == ">" and "&gt;" or ch
table.insert(out, on[k] and string.format('<font color="#%s">%s</font>', hex, ch) or ch)
end
return table.concat(out)
end
local function results(text, all)
local words = {}
for w in string.gmatch(string.lower(text), "%S+") do
table.insert(words, w)
end
local byId = {}
for _, a in all do
byId[a.id] = a
end
local out = {}
if #words == 0 then
local seen = {}
local recent = {}
for _, id in G.recent do
if byId[id] and not seen[id] then
seen[id] = true
table.insert(recent, { a = byId[id] })
end
end
if #recent > 0 then
table.insert(out, { head = "Recent" })
for _, r in recent do
table.insert(out, r)
end
end
local group
for _, a in all do
if a.group ~= group then
group = a.group
table.insert(out, { head = group })
end
table.insert(out, { a = a })
end
return out
end
local rank = {}
for i, id in G.recent do
rank[id] = RECENT - i + 1
end
for i, a in all do
local s, spans = score(words, a)
if s then
table.insert(out, { a = a, spans = spans, s = s + (rank[a.id] or 0) * 0.5, i = i })
end
end
table.sort(out, function(x, y)
if x.s ~= y.s then
return x.s > y.s
end
return x.i < y.i
end)
table.insert(out, {
a = {
id = "",
name = string.format('Search the settings for "%s"', text),
group = "Settings",
icon = "search",
run = function()
App.widget.Enabled = true
if App.ui.search then
App.ui.search.Text = text
end
end,
},
})
return out
end
App.paletteResults = function(text)
return results(text, actions())
end
local gui, conns, closing = nil, {}, false
local blur, dim
local function stepBack(on)
local cam = workspace.CurrentCamera
if on and cam then
blur = new("BlurEffect", { Name = "SmartScatterPaletteBlur", Archivable = false, Size = 0, Parent = cam })
dim = new("ColorCorrectionEffect", { Name = "SmartScatterPaletteDim", Archivable = false, Parent = cam })
App.tween(blur, App.FAST, { Size = BLUR })
App.tween(dim, App.FAST, DIM)
return
end
for _, e in { blur, dim } do
App.tween(e, App.FAST, e:IsA("BlurEffect") and { Size = 0 } or { Saturation = 0, Brightness = 0 })
task.delay(0.25, function()
e:Destroy()
end)
end
blur, dim = nil, nil
end
local function close()
for _, c in conns do
c:Disconnect()
end
table.clear(conns)
if gui then
gui:Destroy()
gui = nil
stepBack(false)
end
end
App.closePalette = close
local function run(a)
close()
if a.id ~= "" then
local keep = { a.id }
for _, id in G.recent do
if id ~= a.id and #keep < RECENT then
table.insert(keep, id)
end
end
G.recent = keep
saveG()
end
local function go()
local ok, err = pcall(a.run)
if not ok then
warn("[Smart Scatter] " .. a.name .. " failed: " .. tostring(err))
App.status("Couldn't do that: " .. tostring(err), "error")
end
end
if a.danger then
App.widget.Enabled = true
App.dialog(a.name .. "?", a.danger .. " Ctrl+Z brings it back.", { { a.name, "danger", go }, { "Cancel", nil, function() end } }, "trash")
else
task.defer(go)
end
end
App.openPalette = function()
if gui then
return
end
local all = actions()
stepBack(true)
gui = new("ScreenGui", {
Name = "SmartScatterPalette",
Archivable = false,
IgnoreGuiInset = true,
DisplayOrder = 60,
ResetOnSpawn = false,
ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
if not pcall(function()
gui.Parent = game:GetService("CoreGui")
end) then
gui.Parent = App.widget
end
local back = new("TextButton", { Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = gui })
table.insert(conns, back.MouseButton1Click:Connect(close))
local view = gui.AbsoluteSize.X > 0 and gui.AbsoluteSize or workspace.CurrentCamera.ViewportSize
local height = 40 + 1 + SHOWN * ROW + 8 + 24
local mx, my = App.rawMouse.X, App.rawMouse.Y
local win = box({
BackgroundTransparency = SEE,
BackgroundColor3 = P.card,
Position = UDim2.fromOffset(
math.clamp(mx - 60, 8, math.max(view.X - WIDTH - 8, 8)),
math.clamp(my - 20, 8, math.max(view.Y - height - 8, 8))
),
Size = UDim2.fromOffset(WIDTH, height),
ZIndex = 2,
Parent = gui,
}, { corner(10), stroke(P.line) })
App.shadow(win, 10)
local field = box({ Size = UDim2.new(1, 0, 0, 40), ZIndex = 2, Parent = win })
local ic = App.icon("search", 14, P.faint)
ic.Position = UDim2.fromOffset(14, 13)
ic.Parent = field
local tb = new("TextBox", {
Text = "",
PlaceholderText = "Search every action…",
PlaceholderColor3 = P.faint,
TextColor3 = P.text,
Font = SANS_M,
TextSize = 14,
TextXAlignment = Enum.TextXAlignment.Left,
ClearTextOnFocus = false,
BackgroundTransparency = 1,
Position = UDim2.fromOffset(38, 0),
Size = UDim2.new(1, -90, 1, 0),
ZIndex = 2,
Parent = field,
})
label(App.keyText("cancel"), 11, P.faint, SANS, {
AnchorPoint = Vector2.new(1, 0),
Position = UDim2.new(1, -14, 0, 0),
Size = UDim2.fromOffset(40, 40),
TextXAlignment = Enum.TextXAlignment.Right,
ZIndex = 2,
Parent = field,
})
box({
BackgroundTransparency = 0,
BackgroundColor3 = P.line,
Position = UDim2.fromOffset(0, 40),
Size = UDim2.new(1, 0, 0, 1),
ZIndex = 2,
Parent = win,
})
local list = new("ScrollingFrame", {
BackgroundTransparency = 1,
BorderSizePixel = 0,
Position = UDim2.fromOffset(0, 45),
Size = UDim2.new(1, 0, 0, SHOWN * ROW),
CanvasSize = UDim2.new(),
AutomaticCanvasSize = Enum.AutomaticSize.Y,
ScrollBarThickness = 3,
ScrollBarImageColor3 = P.line,
ZIndex = 2,
Parent = win,
}, { new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }), pad(6, 6, 0, 0) })
local foot = label("↑ ↓  move     Enter  run     " .. App.keyText("cancel") .. "  close", 11, P.faint, SANS, {
Position = UDim2.new(0, 14, 1, -26),
Size = UDim2.new(1, -28, 0, 22),
ZIndex = 2,
Parent = win,
})
local shown, rows, sel = {}, {}, 0
local function look()
for k, r in rows do
local on = k == sel
r.b.BackgroundTransparency = on and 0 or 1
r.bar.Visible = on
end
local r = rows[sel]
if r then
local top, y = list.CanvasPosition.Y, r.b.AbsolutePosition.Y - list.AbsolutePosition.Y + list.CanvasPosition.Y
if y < top then
list.CanvasPosition = Vector2.new(0, y - HEAD)
elseif y + ROW > top + SHOWN * ROW then
list.CanvasPosition = Vector2.new(0, y + ROW - SHOWN * ROW)
end
end
end
local function fill()
for _, c in list:GetChildren() do
if c:IsA("GuiObject") then
c:Destroy()
end
end
shown = results(tb.Text, all)
rows = {}
for k, item in shown do
if item.head then
label(string.upper(item.head), 10, P.faint, SANS_B, {
Size = UDim2.new(1, 0, 0, HEAD),
LayoutOrder = k,
ZIndex = 3,
Parent = list,
}).TextYAlignment =
Enum.TextYAlignment.Bottom
else
local a = item.a
local b = new("TextButton", {
Text = "",
AutoButtonColor = false,
BackgroundColor3 = P.accentSoft,
BackgroundTransparency = 1,
Size = UDim2.new(1, 0, 0, ROW),
LayoutOrder = k,
ZIndex = 3,
Parent = list,
}, { corner(6) })
local bar = box({
BackgroundTransparency = 0,
BackgroundColor3 = P.accent,
Position = UDim2.fromOffset(0, 7),
Size = UDim2.fromOffset(2, ROW - 14),
Visible = false,
ZIndex = 4,
Parent = b,
})
local tint = a.danger and P.danger or P.dim
local i = App.icon(a.icon or "right", 13, tint)
i.Position = UDim2.fromOffset(10, (ROW - 13) / 2)
i.ZIndex = 4
i.Parent = b
local right = a.key and App.keyText(a.key) or (tb.Text ~= "" and a.group or nil)
local t = label(marked(a.name, item.spans), 13, a.danger and P.danger or P.text, SANS_M, {
Position = UDim2.fromOffset(32, 0),
Size = UDim2.new(1, right and -140 or -40, 1, 0),
TextTruncate = Enum.TextTruncate.AtEnd,
ZIndex = 4,
Parent = b,
})
t.RichText = true
if right then
label(right, 11, P.faint, a.key and SANS_B or SANS, {
AnchorPoint = Vector2.new(1, 0),
Position = UDim2.new(1, -10, 0, 0),
Size = UDim2.new(0, 100, 1, 0),
TextXAlignment = Enum.TextXAlignment.Right,
ZIndex = 4,
Parent = b,
})
end
local idx = #rows + 1
rows[idx] = { b = b, bar = bar, a = a }
b.MouseEnter:Connect(function()
sel = idx
look()
end)
b.MouseButton1Down:Connect(function()
closing = false
run(a)
end)
end
end
list.CanvasPosition = Vector2.zero
sel = #rows > 0 and 1 or 0
foot.Text = string.format("%d  ·  ↑ ↓  move     Enter  run     %s  close", #rows, App.keyText("cancel"))
look()
end
fill()
table.insert(conns, tb:GetPropertyChangedSignal("Text"):Connect(fill))
table.insert(
conns,
UIS.InputBegan:Connect(function(input)
local k = input.KeyCode
if k == Enum.KeyCode.Down or k == Enum.KeyCode.Up then
if #rows > 0 then
sel = (sel - 1 + (k == Enum.KeyCode.Down and 1 or -1)) % #rows + 1
look()
end
end
end)
)
table.insert(
conns,
tb.FocusLost:Connect(function(enter)
if enter then
local r = rows[sel]
if r then
run(r.a)
else
close()
end
return
end
closing = true
task.delay(0.15, function()
if closing then
closing = false
close()
end
end)
end)
)
task.defer(function()
if gui and tb.Parent then
tb.Text = ""
tb:CaptureFocus()
end
end)
end
local cam = workspace.CurrentCamera
for _, name in { "SmartScatterPaletteBlur", "SmartScatterPaletteDim" } do
local e = cam and cam:FindFirstChild(name)
if e then
e:Destroy()
end
end
pcall(function()
if App.ctx.preview then
return
end
local g = game:GetService("CoreGui"):FindFirstChild("SmartScatterPalette")
if g then
g:Destroy()
end
end)
App.registerTool({
id = "search",
group = "Search",
icon = "search",
name = "Search every action",
key = "palette",
on = function()
return false
end,
click = function()
App.openPalette()
end,
})
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
local plugin, P, RunService = App.plugin, App.P, App.RunService
local SANS, SANS_M, SANS_B = App.SANS, App.SANS_M, App.SANS_B
local new, corner, stroke, pad, vlist, hlist, box, col, label, para =
App.new, App.corner, App.stroke, App.pad, App.vlist, App.hlist, App.box, App.col, App.label, App.para
local TOUR_KEY = "SmartScatter_tour"
local TOUR_V = 4
local function ui(name)
local o = App.ui[name]
return o and o.Parent and o or nil
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
chapter = "The panel",
title = "Everything you make",
text = "The outliner lists it all: zones you paint and fill, paths you draw, keep-clear zones, and your stamps. "
.. "Click one to work on it. A zone opens to show its objects; click an object to open its rules.\n\n"
.. "The small arrow at the end of a row renames, locks, bakes or deletes it. Double-click a name to rename it.",
target = function()
return ui("outliner")
end,
},
{
chapter = "The panel",
title = "Make something new",
text = "Zone: paint ground and fill it.\n"
.. "Path: draw a curve for fences, lamps, tiled paths or a road.\n"
.. "Keep-clear zone: ground no area may put anything on, like a spawn, a doorway or a quest spot.",
target = function()
return ui("plusBtn")
end,
},
{
chapter = "The panel",
title = "Its settings, as tabs",
text = "These tabs are for what's selected. A zone has Objects, Zone and World; a path has Curve and Road too; "
.. "an object you click opens its Object tab. World is always there: scanning a finished map, swapping its "
.. "models, seasons and the snapshot.\n\n"
.. "Lost? Type in the search box above, like road or spacing.",
target = function()
return ui("tabRow")
end,
},
{
chapter = "Tools",
title = "Tools live in the viewport",
text = function()
return "Down the viewport's left edge: painting the ground (Brush, Lasso, Box, Polygon, Fill; "
.. App.keyText("tool1")
.. " to "
.. App.keyText("tool5")
.. ", "
.. App.keyText("erase")
.. " erases), the selected object's Spray, More and Less, Stamp, Path, Remove copies, and Search ("
.. App.keyText("palette")
.. ").\n\n"
.. "Along the top, the tool in use: what it acts on and its settings. Shift erases while painting, "
.. App.keyText("size")
.. " resizes the brush with the mouse, "
.. App.keyText("cancel")
.. " stops."
end,
},
{
chapter = "Tools",
title = "It reads the map for you",
text = "Each zone is scanned: roads, paths, water, roofs and walls are found by their material and names, so "
.. "trees stay off the road and out of the pond on their own.\n\n"
.. "If it guesses wrong, select the part and use Fix what the scan sees on the World tab. Soft edges thin "
.. "things out toward the border so a zone fades into its surroundings.",
},
{
chapter = "Tools",
title = "Drawing paths",
text = function()
return "Pick Path in the viewport's strip and click to add points; drag one to move it. Shift+drag changes its "
.. "height, "
.. App.keyText("corner")
.. " makes a sharp corner, "
.. App.keyText("delete")
.. " deletes a point. Select a point and click the ground to branch off; drop an end on another point to "
.. "join them.\n\n"
.. "With a zone selected the path runs through it. Give it a width and turn on Road to lay a real road."
end,
},
{
chapter = "Objects",
title = "Add your models",
text = "Select models in the Explorer and press Add selected models. Keep the originals outside the zone, for "
.. "example in ServerStorage.\n\n"
.. "No models yet? Start from a biome (Forest, Meadow, Desert, Town) or Get sample models. Save a set you "
.. "like as a preset to reuse it anywhere.",
tab = "objects",
target = function()
return ui("step2Card")
end,
},
{
chapter = "Objects",
title = "Rules for each object",
text = "Click an object, in the list or the outliner, for its rules. Its type (tree, rock, bush…) sets smart "
.. "defaults; then tune amount, size, spacing and clumping, piles, which ground it grows on, what it keeps "
.. "away from, slopes and looks.\n\n"
.. "Mix several models in one object, Swap one for another in place, or Lock an object to keep its copies "
.. "exactly where they are.",
},
{
chapter = "Objects",
title = "Along a line",
text = "Set an object to Along and it follows a line instead of spreading out: a road edge, the zone's border "
.. "or your path. Fences and walls resize so their pieces meet end to end, even round bends; lamps keep a "
.. "steady gap and face the road.",
},
{
chapter = "Placing",
title = "Placing it all",
text = "This bar stays at the bottom. Generate places the real models. Turn Live on for a quick preview: every "
.. "change shows right away (on a big area as see-through boxes, which Generate turns into the models).\n\n"
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
.. "chunks for big maps.\n\n"
.. "Every shortcut is listed there too.",
target = function()
return ui("gearBtn")
end,
},
{
chapter = "Finish",
title = "When you're done",
text = "Zones stay editable, so you can come back and change anything. When one is final, Bake it (the arrow at "
.. "the end of its row in the outliner): its objects become plain models and the zone steps aside.\n\n"
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
local tab = step.tab and App.tabById(step.tab)
local open = App.currentTab()
if tab and open and open.id ~= step.tab and table.find(App.tabsFor(App.selected, App.active), tab) then
App.openTab(step.tab)
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
if App.settingsOpen then
App.openSettings(false)
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
local HttpService = game:GetService("HttpService")
local G = App.G
local SKIP = { SS_TopY = true, SS_Failed = true, SS_Kind = true, SS_Area = true, SS_Mask = true, SS_Layers = true, SS_Removed = true }
local AT_ONCE = { SS_Seed = true, SS_Cell = true }
local OUTPUT_STEPS = { ["Smart Scatter: Clear"] = true }
local function decode(json)
local ok, t = pcall(HttpService.JSONDecode, HttpService, json or "[]")
return (ok and type(t) == "table") and t or {}
end
local function same(a, b)
if type(a) ~= type(b) then
return false
end
if type(a) ~= "table" then
return a == b
end
for k, v in a do
if not same(v, b[k]) then
return false
end
end
for k in b do
if a[k] == nil then
return false
end
end
return true
end
local function keyOf(d)
return type(d) == "table" and type(d.p) == "table" and table.concat(d.p, ".") or nil
end
local function diffLayers(oldJSON, newJSON)
local old, new = decode(oldJSON), decode(newJSON)
local r = { dropped = {} }
local oldBy, oldOrder = {}, {}
for _, d in old do
local k = keyOf(d)
if k then
oldBy[k] = d
table.insert(oldOrder, k)
end
end
local newKeys, newOrder = {}, {}
for _, d in new do
local k = keyOf(d)
if k then
newKeys[k] = true
table.insert(newOrder, k)
local o = oldBy[k]
local s, os = type(d.s) == "table" and d.s or {}, o and type(o.s) == "table" and o.s or {}
local hand = not o
or not same(d.v, o.v)
or not same(d.pm, o.pm)
or not same(d.pn, o.pn)
or not same(d.post, o.post)
or s.seed ~= os.seed
local rules = o ~= nil and not hand and not same(d.t, o.t)
if o and not rules then
local a, b = table.clone(s), table.clone(os)
a.seed, b.seed = nil, nil
rules = not same(a, b)
end
if hand then
r.firstHand = r.firstHand or k
end
if rules then
r.rules = true
end
if hand or rules then
r.firstAny = r.firstAny or k
end
end
end
for _, k in oldOrder do
if not newKeys[k] then
table.insert(r.dropped, k)
end
end
local kept = {}
for _, k in oldOrder do
if newKeys[k] then
table.insert(kept, k)
end
end
local shared = 0
for _, k in newOrder do
if oldBy[k] then
shared += 1
if kept[shared] ~= k then
r.reordered = true
break
end
end
end
return r
end
local function diffMask(oldArea, newArea)
local c = newArea.cell
local box, gone, rows = nil, {}, {}
local function grow(cx, cz)
local x0, z0, x1, z1 = cx * c, cz * c, (cx + 1) * c, (cz + 1) * c
box = box and { math.min(box[1], x0), math.min(box[2], z0), math.max(box[3], x1), math.max(box[4], z1) } or { x0, z0, x1, z1 }
end
for cz, row in newArea.rows do
for cx in row do
if not Engine.hasCell(oldArea, cx, cz) then
grow(cx, cz)
rows[cz] = true
end
end
end
local anyGone = false
for cz, row in oldArea.rows do
for cx in row do
if not Engine.hasCell(newArea, cx, cz) then
gone[App.cellKey(cx, cz)] = true
rows[cz] = true
anyGone = true
end
end
end
return box, anyGone and gone or nil, next(rows) ~= nil and rows or nil
end
local function diffRemoved(oldJSON, newJSON)
local seen, box = {}, nil
for _, e in decode(oldJSON) do
if type(e) == "table" then
seen[table.concat(e, ",")] = (seen[table.concat(e, ",")] or 0) + 1
end
end
for _, e in decode(newJSON) do
if type(e) == "table" then
seen[table.concat(e, ",")] = (seen[table.concat(e, ",")] or 0) - 1
end
end
for k, n in seen do
if n ~= 0 then
local _, x, z = string.match(k, "^([^,]+),([^,]+),([^,]+)$")
x, z = tonumber(x), tonumber(z)
if x and z then
box = box and { math.min(box[1], x - 1), math.min(box[2], z - 1), math.max(box[3], x + 1), math.max(box[4], z + 1) }
or { x - 1, z - 1, x + 1, z + 1 }
end
end
end
return box
end
local function joinBoxes(a, b)
if not (a and b) then
return a or b
end
return { math.min(a[1], b[1]), math.min(a[2], b[2]), math.max(a[3], b[3]), math.max(a[4], b[4]) }
end
local function remember()
return {
active = App.active and Engine.layerKey(App.active),
heat = App.heatLayer and Engine.layerKey(App.heatLayer),
}
end
local function layerByKey(k)
for _, l in App.area and App.area.layers or {} do
if Engine.layerKey(l) == k then
return l
end
end
return nil
end
local function restore(keys)
App.heatLayer = keys.heat and layerByKey(keys.heat) or nil
end
local function afterHistory(steps)
local f = App.area and App.area.folder
local keys = remember()
App.resetSplineDrag(true)
App.stopGestures()
if LAYER_MODES[App.mode] then
App.setMode("Off")
end
local snap, old = App.savedAttrs, App.area
if not (old and alive(f) and snap and snap.folder == f) then
switchArea(alive(f) and f or Engine.listAreas()[1], keys.active)
restore(keys)
if G.live and App.canGenerate() then
App.runGenerate(false)
end
return
end
local outputStep = false
for name in type(steps) == "table" and steps or { [steps or ""] = true } do
outputStep = outputStep or OUTPUT_STEPS[name] == true
end
App.cancelJob()
local new = Engine.loadArea(f)
local oa, na = snap.attrs, f:GetAttributes()
local wholeNow, areaRules = outputStep, false
for k in oa do
if not SKIP[k] and not same(oa[k], na[k]) then
if AT_ONCE[k] then
wholeNow = true
else
areaRules = true
end
end
end
for k in na do
if oa[k] == nil and not SKIP[k] then
if AT_ONCE[k] then
wholeNow = true
else
areaRules = true
end
end
end
local L = diffLayers(oa.SS_Layers, na.SS_Layers)
local rules = areaRules or L.rules or L.reordered
local cameBack, gone, rows = diffMask(old, new)
local removedBox = diffRemoved(oa.SS_Removed, na.SS_Removed)
App.area = new
App.snapshotArea()
App.failure = f:GetAttribute("SS_Failed")
App.paintLayer = nil
restore(keys)
App.onAreaSwitched(f, keys.active)
if new.cell ~= old.cell then
App.analysisDirty = true
App.rebuildOverlay(true)
elseif rows then
App.analysisDirty = true
for cz in rows do
App.dirtyRows[cz] = true
end
App.recolorOverlay()
else
App.recolorOverlay()
end
App.refreshParams()
App.drawSpline()
if new.locked and not App.NO_AREA_MODES[App.mode] then
App.setMode("Off")
end
if #L.dropped > 0 then
local dropped = {}
for _, k in L.dropped do
dropped[k] = true
end
for _, lf in f:GetChildren() do
if dropped[lf:GetAttribute("SS_Key") or ""] then
Engine.dropOutput(lf)
end
end
end
if gone then
App.dropErased(gone, {})
end
App.countPlaced()
local canGen = App.canGenerate()
local runs = {}
if canGen and G.live then
if wholeNow or areaRules or L.reordered or (L.firstAny and (cameBack or removedBox)) then
table.insert(runs, { false })
elseif L.firstAny then
table.insert(runs, { false, layerByKey(L.firstAny) })
elseif cameBack or removedBox then
table.insert(runs, { false, nil, joinBoxes(cameBack, removedBox) })
end
elseif canGen then
if wholeNow then
table.insert(runs, { true, nil, nil, true })
else
local patch = joinBoxes(cameBack, removedBox)
if patch then
table.insert(runs, { false, nil, patch, true })
end
if L.firstHand then
table.insert(runs, { true, layerByKey(L.firstHand), nil, true })
end
if rules then
App.markPending()
end
end
end
if #runs > 0 then
task.spawn(function()
for _, r in runs do
App.runGenerate(r[1], r[2], r[3], r[4])
end
end)
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
task.defer(afterHistory, name)
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
if App.closePalette then
App.closePalette()
end
if App.clearToolbar then
App.clearToolbar()
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
