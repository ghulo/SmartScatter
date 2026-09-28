-- GENERATED part 3 of the flattened release by tools/tree.py: edit the modules, not this.
local MODULES = {}

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
Map = "search",
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
{ "Map scan", "Map", "mapscan", nil, "find kinds repeated models duplicates" },
{ "Swap models", "Map", "swap", nil, "replace kind" },
{ "Improve layout", "Map", "layout", nil, "respace even gaps crowded" },
{ "Seasons", "Map", "seasons", nil, "snow snowy autumn winter dry fall" },
{ "Snapshot and restore", "Map", "snapshot", nil, "backup originals put back" },
{ "Fix what the scan sees", "Map", "scanfix", nil, "mark road building water" },
{ "Curve of the path", "Map", "curve", nil, "strip width snap walls loop closed" },
{ "Road", "Map", "road", nil, "asphalt surface style" },
{ "Objects", "Scatter", "objects", nil, "models list amount size" },
{ "Start from a biome", "Scatter", "biomes", nil, "forest meadow desert town" },
{ "Pattern", "Scatter", "pattern", "scatter", "groves islands veins spots bands" },
{ "Colour zones", "Scatter", "zones", "scatter", "color mood autumn lush frost" },
{ "Edges and wind", "Scatter", "edges", "scatter", "soft edge lean" },
{ "Presets", "Scatter", "presets", "scatter", "save load share code" },
{ "Performance", "Scatter", "performance", "scatter", "report parts heavy" },
{ "Paint only on", "Brush", "paintfilter", "brush", "surfaces filter" },
{ "Tidy the edge", "Brush", "tidy", "brush", "holes smooth grow shrink" },
{ "Look: accent and text size", "Settings", "look", nil, "theme colour font" },
{ "Viewport settings", "Settings", "viewport", nil, "overlay focus grid history" },
{ "Game-ready output", "Settings", "output", nil, "collision shadows streaming chunks boxes" },
{ "Shortcuts", "Settings", "shortcuts", "settings", "keys keybind hotkey" },
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
App.goPage("Scatter")
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
add({
id = "newarea",
name = "New scatter area",
group = "Areas",
words = "create add",
run = function()
App.newArea()
end,
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
group = c[2] == "Map" and "Map" or "Go to",
words = c[5],
run = function()
if not App.openCard(c[2], c[3], c[4]) then
App.status(c[1] .. " isn't there for this area.")
end
end,
})
end
for _, t in { "Scatter", "Brush", "Map", "Settings" } do
add({
id = "tab:" .. t,
name = t .. " tab",
group = "Go to",
words = "page open",
run = function()
App.goPage(t)
end,
})
end
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
local g = game:GetService("CoreGui"):FindFirstChild("SmartScatterPalette")
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
