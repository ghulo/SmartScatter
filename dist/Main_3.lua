-- GENERATED part 3 of the flattened release by tools/tree.py: edit the modules, not this.
local MODULES = {}

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
local PAGE_PAD = 14
local CRUMB_H = 30
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
"outlinerFilter",
"tabs",
"tabRow",
"crumb",
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
}, { pad(PAGE_PAD, 12, 10, 24), vlist(2) })
local scrollPad = App.scroll:FindFirstChildOfClass("UIPadding")
App.scroll.MouseEnter:Connect(function()
tween(App.scroll, FAST, { ScrollBarImageTransparency = 0.15 })
end)
App.scroll.MouseLeave:Connect(function()
tween(App.scroll, FAST, { ScrollBarImageTransparency = 0.5 })
end)
buildTitle(head)
if App.settingsOpen or not G.compact then
box({ Size = UDim2.new(1, 0, 0, 8), Parent = head })
buildSearch(head)
end
if not App.settingsOpen then
box({ Size = UDim2.new(1, 0, 0, 8), Parent = head })
App.buildOutliner(head)
if App.toolbarAvailable and not App.toolbarAvailable() then
box({ Size = UDim2.new(1, 0, 0, 6), Parent = head })
App.buildToolRow(head)
end
end
box({ Size = UDim2.new(1, 0, 0, 2), Parent = head })
App.sheen(App.root, 0.04, 140, 150)
App.halftone(App.root, 0.07, 4, 150)
local bench = box({ BackgroundTransparency = 0, BackgroundColor3 = P.bg, ZIndex = 0, Parent = App.root })
box({ BackgroundTransparency = 0, BackgroundColor3 = P.line, Size = UDim2.new(1, 0, 0, 1), Parent = bench })
local strip, column, rail
if not App.settingsOpen then
strip = box({ BackgroundTransparency = 0, BackgroundColor3 = P.strip, Size = UDim2.new(1, 0, 0, CRUMB_H), Parent = bench }, {
pad(PAGE_PAD, PAGE_PAD, 4, 4),
})
App.buildCrumb(strip)
box({
BackgroundTransparency = 0,
BackgroundColor3 = P.line,
AnchorPoint = Vector2.new(0, 1),
Position = UDim2.new(0, -PAGE_PAD, 1, 4),
Size = UDim2.new(1, PAGE_PAD * 2, 0, 1),
Parent = strip,
})
rail = box({
BackgroundTransparency = 0,
BackgroundColor3 = P.well,
Position = UDim2.fromOffset(0, CRUMB_H),
Size = UDim2.new(0, App.TAB_COL, 1, -CRUMB_H),
Parent = bench,
})
box({
BackgroundTransparency = 0,
BackgroundColor3 = P.line,
AnchorPoint = Vector2.new(1, 0),
Position = UDim2.fromScale(1, 0),
Size = UDim2.new(0, 1, 1, 0),
Parent = rail,
})
column = App.buildTabColumn(rail)
column.Size = UDim2.fromScale(1, 1)
scrollPad.PaddingLeft = UDim.new(0, PAGE_PAD - 8)
end
local left = column and App.TAB_COL or 0
local top = strip and CRUMB_H or 0
local function fit()
local h = head.AbsoluteSize.Y
bench.Position = UDim2.fromOffset(0, h)
bench.Size = UDim2.new(1, 0, 1, -h - barH())
App.scroll.Position = UDim2.fromOffset(left, h + top)
App.scroll.Size = UDim2.new(1, -left, 1, -h - top - barH())
end
head:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
fit()
buildBar(App.root)
buildToast(App.root)
buildPage()
if turned then
local rest = scrollPad.PaddingLeft.Offset
scrollPad.PaddingLeft, scrollPad.PaddingRight = UDim.new(0, rest + 24), UDim.new(0, -12)
tween(scrollPad, MED, { PaddingLeft = UDim.new(0, rest), PaddingRight = UDim.new(0, 12) })
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
local ANY_TIME = {
palette = true,
quick = true,
overlay = true,
shuffle = true,
erase = true,
tool1 = true,
tool2 = true,
tool3 = true,
tool4 = true,
tool5 = true,
}
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
if name == "quick" then
if App.widget.Enabled and App.openQuick then
App.openQuick()
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
Select = "Click a zone's ground, a path or a placed copy; Shift + click or drag a box for more copies. Shift + wheel turns them, Alt + wheel sizes them, {quick} or the bar at the top has the rest.",
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
-- #module App/Viewport/Spline
MODULES["App/Viewport/Spline"] = (function()
--[[
Smart Scatter — Spline: the spline editor: points, branches, welding, viewport preview.
Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]
return function(App)
local beginRec, endRec, Engine, track, G, num = App.beginRec, App.endRec, App.Engine, App.track, App.G, App.num
local new, refreshParams = App.new, App.refreshParams
local saveArea, canGenerate, runGenerate = App.saveArea, App.canGenerate, App.runGenerate
local switchArea, newArea, rawMouse, mouse, shiftHeld = App.switchArea, App.newArea, App.rawMouse, App.mouse, App.shiftHeld
local gizmoFolder, setLabel = App.gizmoFolder, App.setLabel
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
sv.glow = new(
"WireframeHandleAdornment",
{ Adornee = T, AlwaysOnTop = true, Thickness = 5, ZIndex = 1, Transparency = 0.8, Color3 = VIEW.edge, Parent = sv.folder }
)
sv.halo = new(
"WireframeHandleAdornment",
{ Adornee = T, AlwaysOnTop = true, Thickness = 10, ZIndex = 1, Transparency = 0.92, Color3 = VIEW.edge, Parent = sv.folder }
)
sv.tail = new("LineHandleAdornment", {
Adornee = T,
AlwaysOnTop = true,
Thickness = 3,
ZIndex = 3,
Transparency = 0.25,
Color3 = VIEW.accent,
Visible = false,
Parent = sv.folder,
})
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
local step = math.clamp(approx / 700, 0.5, 4)
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
sv.glow:Clear()
sv.halo:Clear()
for _, L in lines do
for k = 1, #L - 1 do
sv.wire:AddLine(L[k], L[k + 1])
end
for k = 1, #L - 1, 2 do
local b = L[math.min(k + 2, #L)]
sv.glow:AddLine(L[k], b)
sv.halo:AddLine(L[k], b)
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
local STRIDE = 4
local function pickCurve(skip)
local best, bd = nil, CURVE_PX
for _, c in sv.curves or {} do
local P, n = c.P, #c.P
local near, nd = nil, math.huge
for k = 1, n, STRIDE do
if not (skip and skip(c.cv, c.S[k])) then
local d = screenDist(P[k] + c.U[k] * 0.3)
if d < nd then
near, nd = k, d
end
end
end
if near then
for k = math.max(1, near - STRIDE), math.min(n, near + STRIDE) do
if not (skip and skip(c.cv, c.S[k])) then
local d = screenDist(P[k] + c.U[k] * 0.3)
if d < bd then
best, bd = { cv = c.cv, p = P[k], n = c.U[k], seg = c.S[k] }, d
end
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
local function pointParams()
local skip = App.templates()
local road = App.area and Engine.roadOf(App.area)
if road then
table.insert(skip, road)
end
return (Engine.rayParams(skip))
end
local function commitSpline(rec)
local sp = App.area.spline
local stripChanged = false
if sp and (sp.width or 0) > 0 then
local before = App.area.rows
refreshParams()
Engine.maskFromSpline(App.area, pointParams())
local after = App.area.rows
for _, pair in { { before, after }, { after, before } } do
for cz, row in pair[1] do
local other = pair[2][cz]
for cx in row do
if not (other and other[cx]) then
App.dirtyRows[cz] = true
stripChanged = true
break
end
end
end
end
end
saveArea()
endRec(rec)
local roadMatters = false
if sp and Engine.roadWidth(sp) > 0 then
for _, l in App.area.layers do
roadMatters = roadMatters or not Engine.isLine(l)
end
end
if stripChanged or roadMatters then
App.analysisDirty = true
end
if G.live and canGenerate() then
runGenerate(false)
end
App.drawSpline()
App.refreshSplineInfo()
App.checkShape()
if not (G.live and canGenerate()) then
App.markPending()
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
local rp = pointParams()
local ray = rawMouse.UnitRay
local hit = Engine.cast(ray.Origin, ray.Direction * 5000, rp)
local sp = App.area and App.area.spline
if hit and hit.Normal.Y < 0.55 and not (sp and sp.walls) then
local down = Engine.cast(hit.Position + hit.Normal * 0.6 + Vector3.new(0, 0.5, 0), Vector3.new(0, -600, 0), rp)
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
local drawPending = false
local function requestDraw()
drawPending = true
end
track(App.RunService.Heartbeat:Connect(function()
if drawPending then
drawPending = false
App.drawSpline()
end
end))
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
requestDraw()
end
end
splineLabel(nil)
return
end
if drawing then
local hit = pointHit()
if hit and sv.tail then
local from = drawing.anchor + Vector3.new(0, 0.3, 0)
local to = hit.Position + hit.Normal * 0.3
local len = (to - from).Magnitude
sv.tail.Visible = len > 0.05
if len > 0.05 then
sv.tail.CFrame, sv.tail.Length = CFrame.lookAt(from, to), len
end
end
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
requestDraw()
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
local below = Engine.cast(q.p + Vector3.yAxis * 2, Vector3.yAxis * -500, pointParams())
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
requestDraw()
end
return
end
local wasHandle, wasPt = hoverHandle, hoverPt
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
if hoverHandle ~= wasHandle or ((hoverPt or wasPt) and not samePt(hoverPt, wasPt)) then
updateHandles()
end
local hit = pointHit()
local text
if hoverHandle then
text = "Drag to bend the curve · Shift for height"
elseif hoverPt then
text = "Drag to move · click to select · " .. App.keyText("delete") .. " to delete"
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
if App.mode ~= "Spline" or (App.overViewportUI and App.overViewportUI()) then
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
drawing = { cv = cv, prepend = prepend, anchor = hit.Position, spacing = math.clamp(camDist * 0.045, 1.2, 30), pts = { q } }
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
if sv.tail then
sv.tail.Visible = false
end
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
App.onMouseUp(function()
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
local before = App.Selection:Get()
if App.clickSplinePoint(Vector2.new(input.Position.X, input.Position.Y)) then
task.defer(function()
App.Selection:Set(before)
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
App.registerTool({
id = "path",
group = "Path",
icon = "spline",
name = "Draw a path",
when = function()
return not (App.selected and App.selected.kind == "Clear")
end,
on = function()
return App.mode == "Spline"
end,
click = function()
if App.mode == "Spline" then
App.setMode("Off")
elseif App.area and App.selected and (App.selected.kind == "Zone" or App.selected.kind == "Path") then
ensureSpline()
App.setMode("Spline")
else
App.newSplineFn()
end
end,
})
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
Smart Scatter — Stamp: one model, put down exactly where and how you want it, anywhere on the ground. No area,
painting or object needed: it's its own tool. What it stamps: the models selected in the Explorer when it starts (a
folder counts as the models in it), or an object's models (its Stamp button), or the last ones again.
The model floats under the mouse, see-through, standing just as it will; a click puts it down, a drag from where
you pressed turns it to face the mouse (15° steps; Shift turns freely). Shift + the wheel turns it and Alt + the
wheel sizes it before it's put down. Keys turn it, size it, pick the model or roll a random one; the Stamp card and the viewport's bar have the same. Stamped copies are plain models in
Workspace › Stamps: Generate, Erase and the areas never touch them; Ctrl+Z takes one back, Delete removes one.
Paint hands the viewport's mouse and keys to it while the mode is "Stamp".
Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]
return function(App)
local Engine, G, beginRec, endRec, rawMouse = App.Engine, App.G, App.beginRec, App.endRec, App.rawMouse
local UIS = game:GetService("UserInputService")
local STEP = math.rad(15)
local DRAG_PX = 6
local FOLDER = "Stamps"
local BARE = { s = {} }
local stamp = { models = {}, vi = 1, yaw = 0, k = 1, from = nil }
App.stamp = stamp
local measured = setmetatable({}, { __mode = "k" })
local function variantOf(inst)
local v = measured[inst]
if v == nil then
v = Engine.makeVariant(inst, 1, 1) or false
measured[inst] = v
end
return v or nil
end
local function current()
local inst = stamp.models[stamp.vi] or stamp.models[1]
return inst, inst and variantOf(inst)
end
local function selectedModels()
local out = {}
local placedByUs = { Engine.outFolder(), workspace:FindFirstChild(Engine.ROADS) }
local function ours(inst)
if inst:GetAttribute("SS_Type") ~= nil then
return true
end
for _, f in placedByUs do
if f and inst:IsDescendantOf(f) then
return true
end
end
return false
end
local function take(inst)
if (inst:IsA("Model") or inst:IsA("BasePart")) and not ours(inst) and variantOf(inst) then
table.insert(out, inst)
end
end
for _, s in App.Selection:Get() do
if s:IsA("Folder") then
for _, c in s:GetChildren() do
take(c)
end
else
take(s)
end
end
return out
end
App.startStamp = function(from)
local models
if from then
models = {}
for _, v in from.variants do
table.insert(models, v.inst)
end
else
models = selectedModels()
if #models == 0 then
models = #stamp.models > 0 and stamp.models or nil
from = stamp.from
end
if not models and App.brushTarget() then
from = App.brushTarget()
models = {}
for _, v in from.variants do
table.insert(models, v.inst)
end
end
end
if not models or #models == 0 then
App.status("Select a model in the Explorer (or a folder of them), then press Stamp.")
return false
end
if models ~= stamp.models then
stamp.models, stamp.vi, stamp.from = models, 1, from
local s = from and from.s
stamp.k = s and (s.scaleMin + s.scaleMax) / 2 or 1
stamp.base = stamp.k
end
if App.mode ~= "Stamp" then
App.setMode("Stamp")
end
if App.refreshStamp then
App.refreshStamp()
end
local inst = current()
App.status(
string.format(
"Stamping %s%s. Click to put it down, drag to turn it.",
inst.Name,
#models > 1 and string.format(" (and %d more)", #models - 1) or ""
)
)
return true
end
local ghost
local press
local function clearGhost()
if ghost then
ghost.clone:Destroy()
ghost = nil
end
end
local function ghostFor(inst, v, sc)
if ghost and ghost.v == v and math.abs(ghost.sc - sc) < 1e-4 and ghost.clone.Parent then
return ghost
end
clearGhost()
local c = (v.src or inst):Clone()
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
local function stand(v, pos, up)
local m, sc = v.m, stamp.k * v.size
local upV = (G.stampAlign and up and up.Y > 0.2) and up or Vector3.yAxis
local y = pos.Y
if upV == Vector3.yAxis then
local r = math.max(m.radius * sc * 0.6, 0.4)
for k = 0, 3 do
local a = k * math.pi / 2 + stamp.yaw
local h = Engine.cast(
Vector3.new(pos.X + math.cos(a) * r, pos.Y + r + 4, pos.Z + math.sin(a) * r),
Vector3.new(0, -(r * 3 + 8), 0),
App.probeParams
)
if h and h.Position.Y < y then
y = math.max(h.Position.Y, y - r * 1.5)
end
end
end
local cf = CFrame.new(pos.X, y, pos.Z) * Engine.rotateUp(upV) * CFrame.Angles(0, stamp.yaw, 0)
return cf, sc
end
local function describe(inst, extra)
return string.format(
"Stamp · %s · %d° · %.2f×%s",
inst.Name,
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
local function show(pos, up)
local inst, v = current()
if not v then
clearGhost()
return
end
local cf, sc = stand(v, pos, up)
local gh = ghostFor(inst, v, sc)
if not gh.offset then
Engine.poseCopy(gh.clone, BARE, v, sc, cf, 0)
gh.offset = cf:Inverse() * gh.clone:GetPivot()
gh.clone.Parent = App.gizmoFolder()
else
gh.clone:PivotTo(cf * gh.offset)
end
label(cf.Position, describe(inst, press and press.turning and "release to put it down" or "click to put it down, drag to turn"))
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
if press then
local m = Vector2.new(rawMouse.X, rawMouse.Y)
press.turning = press.turning or (m - press.at).Magnitude > DRAG_PX
if press.turning then
local to = onPlane(press.pos.Y)
local d = to and Vector3.new(to.X - press.pos.X, 0, to.Z - press.pos.Z)
if d and d.Magnitude > 0.5 then
local yaw = math.atan2(-d.X, -d.Z)
stamp.yaw = App.shiftHeld() and yaw or math.floor(yaw / STEP + 0.5) * STEP
end
end
show(press.pos, press.up)
return
end
local hit = App.mouseHit()
if not hit then
clearGhost()
App.setLabel("")
return
end
show(hit.Position, hit.Normal)
end
local function roll()
stamp.yaw = math.random() * math.pi * 2
stamp.base = stamp.base or stamp.k
stamp.k = stamp.base * (0.8 + math.random() * 0.4)
stamp.vi = math.random(1, math.max(#stamp.models, 1))
end
local function refresh()
if App.refreshStamp then
App.refreshStamp()
end
App.stampMove()
end
local function put(pos, up)
local inst, v = current()
if not v then
return
end
local cf, sc = stand(v, pos, up)
local rec = beginRec("Smart Scatter: Stamp " .. inst.Name)
local folder = workspace:FindFirstChild(FOLDER)
if not folder then
folder = Instance.new("Folder")
folder.Name = FOLDER
folder.Parent = workspace
end
local copy = (v.src or inst):Clone()
Engine.poseCopy(copy, BARE, v, sc, cf, 0)
for _, d in copy:GetDescendants() do
if d:IsA("BasePart") then
d.Anchored = true
end
end
if copy:IsA("BasePart") then
copy.Anchored = true
end
copy.Parent = folder
endRec(rec)
App.status(describe(inst, "put down in Workspace › Stamps. Ctrl+Z takes it back."))
if G.stampRandom then
roll()
if App.refreshStamp then
App.refreshStamp()
end
end
end
App.stampDown = function()
local hit = App.mouseHit()
if hit and current() then
press = { pos = hit.Position, up = hit.Normal, at = Vector2.new(rawMouse.X, rawMouse.Y) }
end
end
App.stampUp = function()
local pr = press
press = nil
if pr then
put(pr.pos, pr.up)
if pr.turning and App.refreshStamp then
App.refreshStamp()
end
App.stampMove()
end
end
App.registerMode("Stamp", {
move = App.stampMove,
down = App.stampDown,
up = App.stampUp,
stop = function()
App.clearStamp()
end,
header = function()
local models = stamp.models
local cur = models[stamp.vi] or models[1]
local function changed()
if App.refreshStamp then
App.refreshStamp()
end
end
local items = {
{
step = "Turn",
value = string.format("%d°", math.floor(math.deg(stamp.yaw) + 0.5) % 360),
dec = function()
App.setStamp(math.deg(stamp.yaw) - 15)
changed()
end,
inc = function()
App.setStamp(math.deg(stamp.yaw) + 15)
changed()
end,
},
{
step = "Size",
value = string.format("%.2f×", stamp.k),
dec = function()
App.setStamp(nil, math.max(stamp.k / 1.1, 0.05))
changed()
end,
inc = function()
App.setStamp(nil, math.min(stamp.k * 1.1, 20))
changed()
end,
},
}
if #models > 1 then
table.insert(items, {
step = "Model",
value = cur.Name,
dec = function()
App.setStamp(nil, nil, (stamp.vi - 2) % #models + 1)
changed()
end,
inc = function()
App.setStamp(nil, nil, stamp.vi % #models + 1)
changed()
end,
})
end
table.insert(items, { button = "Random", click = App.rollStamp })
return "Stamp · " .. (cur and cur.Name or ""), items, string.format("%.3f|%.3f|%s|%d", stamp.yaw, stamp.k, tostring(stamp.vi), #models)
end,
noArea = true,
})
App.stampKey = function(name)
if name == "turn" then
stamp.yaw = (math.floor(stamp.yaw / STEP + 0.5) + (App.shiftHeld() and -1 or 1)) * STEP % (math.pi * 2)
elseif name == "grow" or name == "shrink" then
stamp.k = math.clamp(stamp.k * (name == "grow" and 1.1 or 1 / 1.1), 0.05, 20)
stamp.base = stamp.k
elseif name == "model" then
stamp.vi = stamp.vi % math.max(#stamp.models, 1) + 1
elseif name == "shuffle" then
roll()
elseif name == "size" then
return true
elseif name == "cancel" and press then
press = nil
else
return false
end
refresh()
return true
end
local HOLD = 0.2
local camAt, holdUntil = nil, 0
App.wheelDoes = function()
if App.shiftHeld() then
return "turn"
elseif UIS:IsKeyDown(Enum.KeyCode.LeftAlt) or UIS:IsKeyDown(Enum.KeyCode.RightAlt) then
return "size"
end
return nil
end
App.holdCamera = function()
holdUntil = os.clock() + HOLD
end
local function wheel(dir)
if App.mode ~= "Stamp" or not current() then
return
end
local does = App.wheelDoes()
if does == "turn" then
stamp.yaw = (math.floor(stamp.yaw / STEP + 0.5) + dir) * STEP % (math.pi * 2)
elseif does == "size" then
stamp.k = math.clamp(stamp.k * 1.1 ^ dir, 0.05, 20)
stamp.base = stamp.k
else
return
end
App.holdCamera()
refresh()
end
App.stampWheel = wheel
App.track(rawMouse.WheelForward:Connect(function()
wheel(1)
end))
App.track(rawMouse.WheelBackward:Connect(function()
wheel(-1)
end))
App.track(App.RunService.Heartbeat:Connect(function()
if App.mode == "Off" then
camAt = nil
return
end
local cam = workspace.CurrentCamera
if not cam then
return
end
if camAt and os.clock() < holdUntil then
cam.CFrame, cam.Focus = camAt.cf, camAt.focus
else
camAt = { cf = cam.CFrame, focus = cam.Focus }
end
end))
App.setStamp = function(yaw, k, vi)
stamp.yaw = yaw and math.rad(yaw) % (math.pi * 2) or stamp.yaw
if k then
stamp.k, stamp.base = k, k
end
stamp.vi = vi or stamp.vi
if App.mode == "Stamp" then
App.stampMove()
end
end
App.rollStamp = function()
roll()
refresh()
end
App.registerTool({
id = "stamp",
group = "Stamp",
icon = "stamp",
name = "Stamp (the selected models, or the last ones)",
on = function()
return App.mode == "Stamp"
end,
click = function()
if App.mode == "Stamp" then
App.setMode("Off")
else
App.startStamp()
end
end,
})
App.clearStamp = function()
press = nil
clearGhost()
end
end
end)()
-- #module App/Viewport/Select
MODULES["App/Viewport/Select"] = (function()
--[[
Smart Scatter — Select: the strip's Select tool. Point at something Smart Scatter made and it's named by the mouse;
a click selects it (Core/Selection), so the panel shows it:
  a placed copy     its zone, with its object active
  a path            the path (its curve, or a point of it, within a few pixels on screen)
  painted ground    the zone painted there (a keep-clear zone if no zone is)
Shift + click picks more copies of the same zone (or takes one back out), and a drag over the ground boxes them;
what's done then is done to each. The viewport's header shows what's picked, with the same changes as buttons.
A click on a placed copy also picks that one copy: it's outlined, Shift + the wheel turns it and Alt + the wheel
sizes it (as the stamp's), the stamp's keys work on it, and the quick menu (its key, Z) has the rest (another model,
moving it, giving it back to the rules, removing it). A copy changed this way becomes a stamp's pin of its object
(Engine/Pins), so generating puts it back just as it was left.
Studio's own selection is left as it was. Paint hands the viewport's mouse to it while the mode is "Select".
Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]
return function(App)
local Engine, HttpService = App.Engine, game:GetService("HttpService")
local rawMouse, P = App.rawMouse, App.P
local STEP = math.rad(15)
local NEAR_PX = 10
local cache = setmetatable({}, { __mode = "k" })
local function shapeOf(f)
local c = cache[f]
if not c then
c = {}
cache[f] = c
end
local mask = f:GetAttribute("SS_Mask") or ""
if c.mask ~= mask then
c.mask, c.cells = mask, {}
for cz, rest in string.gmatch(mask, "(-?%d+):([^|]*)") do
for s, e in string.gmatch(rest, "(-?%d+)~(-?%d+)") do
for cx = tonumber(s), tonumber(e) do
c.cells[cx * 1000003 + tonumber(cz)] = true
end
end
end
c.cell = f:GetAttribute("SS_Cell") or Engine.MASK_CELL
end
local spline = f:GetAttribute("SS_Spline") or ""
if c.spline ~= spline then
c.spline, c.curves = spline, {}
local ok, sd = pcall(HttpService.JSONDecode, HttpService, spline ~= "" and spline or "null")
if ok and type(sd) == "table" then
for _, list in { { sd.pts }, sd.branches or {}, sd.loops or {} } do
for _, pts in list do
local curve = {}
for _, q in type(pts) == "table" and pts or {} do
if type(q) == "table" and #q >= 3 then
table.insert(curve, Vector3.new(q[1], q[2], q[3]))
end
end
if #curve > 0 then
table.insert(c.curves, curve)
end
end
end
end
end
return c
end
local cam = function()
return workspace.CurrentCamera
end
local function screen(p)
local v, on = cam():WorldToViewportPoint(p)
return Vector2.new(v.X, v.Y), on and v.Z > 0
end
local function segDist(m, a, b)
local pa, oka = screen(a)
local pb, okb = screen(b)
if not (oka or okb) then
return math.huge
end
local ab = pb - pa
local t = ab.Magnitude > 1e-3 and math.clamp((m - pa):Dot(ab) / ab:Dot(ab), 0, 1) or 0
return (m - (pa + ab * t)).Magnitude
end
App.pickAt = function()
local out = Engine.outFolder()
if not out then
return nil
end
local ray = rawMouse.UnitRay
local rp = RaycastParams.new()
rp.FilterType = Enum.RaycastFilterType.Include
rp.FilterDescendantsInstances = { out }
local hit = workspace:Raycast(ray.Origin, ray.Direction * 5000, rp)
if hit then
local key, area, copy
local cur = hit.Instance
while cur and cur ~= out do
copy = copy or (cur:GetAttribute("SS_Type") and cur or nil)
key = key or cur:GetAttribute("SS_Key")
if cur.Parent == out then
area = cur
end
cur = cur.Parent
end
if area and not (App.isHidden and App.isHidden(area)) then
return App.thingOf(area), key, key and copy or nil
end
end
local m = Vector2.new(rawMouse.X, rawMouse.Y)
local best, bestD = nil, NEAR_PX
for _, f in Engine.listAreas() do
for _, curve in shapeOf(f).curves do
for i = 1, #curve do
local d = segDist(m, curve[i], curve[math.min(i + 1, #curve)])
if d < bestD then
best, bestD = f, d
end
end
end
end
if best then
return App.thingOf(best)
end
local g = App.mouseHit()
if g then
local clear
for _, f in Engine.listAreas() do
local c = shapeOf(f)
local k = math.floor(g.Position.X / c.cell) * 1000003 + math.floor(g.Position.Z / c.cell)
if c.cells[k] then
local t = App.thingOf(f)
if t.kind ~= "Clear" then
return t
end
clear = clear or t
end
end
return clear
end
return nil
end
local picks, moving, press = {}, false, nil
local MAX_PICKS = 300
local DRAG_PX = 6
local function lightHover(copy)
App.gizmoFolder()
local h = App.gz.copyHover
if not (h and h.Parent) then
if not copy then
return
end
h = Instance.new("Highlight")
h.DepthMode = Enum.HighlightDepthMode.Occluded
h.OutlineTransparency = 0
h.FillTransparency = 1
h.Parent = App.gz.folder
App.gz.copyHover = h
end
h.OutlineColor = P.accent
h.Adornee = copy
end
local function copyOf(e)
if e.copy and e.copy.Parent then
return e.copy
end
e.copy = nil
local a = App.area
if not (a and a.folder == e.folder) then
return nil
end
for _, f in a.folder:GetChildren() do
if f:GetAttribute("SS_Key") == e.key then
for _, d in f:GetDescendants() do
local x, z = d:GetAttribute("SS_X"), d:GetAttribute("SS_Z")
if x and z and d:GetAttribute("SS_Type") and math.abs(x - e.x) < 0.05 and math.abs(z - e.z) < 0.05 then
e.copy = d
return d
end
end
end
end
return nil
end
local function pickedCopy()
local e = picks[#picks]
return e and copyOf(e) or nil
end
local function outline()
App.gizmoFolder()
local pool = App.gz.copyBoxes or {}
App.gz.copyBoxes = pool
local n = 0
for _, e in picks do
local c = copyOf(e)
if c then
n += 1
local sb = pool[n]
if not sb then
sb = Instance.new("SelectionBox")
sb.LineThickness = 0.04
sb.SurfaceTransparency = 0.88
sb.Parent = App.gz.folder
pool[n] = sb
end
sb.Color3, sb.SurfaceColor3 = P.accent, P.accent
sb.Adornee = c
end
end
for i = n + 1, #pool do
pool[i].Adornee = nil
end
return n
end
local function describe(copy)
local pose = App.area and Engine.copyPose(App.area, copy)
if not pose then
return copy.Name
end
return string.format("%s · %d° · %.2f×", copy.Name, math.floor(math.deg(pose.yaw) + 0.5) % 360, pose.k)
end
local function showPicked()
outline()
local copy = pickedCopy()
if copy then
App.gz.anchor.CFrame = CFrame.new(copy:GetPivot().Position)
App.setLabel(
moving and "Click where it should stand"
or #picks > 1 and string.format("%d copies  ·  %s for more", #picks, App.keyText("quick"))
or (describe(copy) .. "  ·  " .. App.keyText("quick") .. " for more")
)
end
end
local function unpick()
picks, moving, press = {}, false, nil
outline()
lightHover(nil)
if App.closeViewMenu then
App.closeViewMenu()
end
if App.viewRect then
App.viewRect(nil)
end
end
local function follow()
local mine = picks
task.spawn(function()
for _ = 1, 60 do
task.wait(0.05)
if picks ~= mine or App.mode ~= "Select" then
return
end
local all = true
for _, e in picks do
all = all and copyOf(e) ~= nil
end
if all then
break
end
end
if picks == mine and App.mode == "Select" then
showPicked()
end
end)
end
local function ready()
local a = App.area
if #picks == 0 or not a or a.folder ~= picks[1].folder then
return nil
end
if a.locked then
App.status("This area is locked. Unlock it to change its copies.")
return nil
end
if not App.canGenerate() then
App.status("The area can't be rebuilt right now: the Generate button says why.")
return nil
end
return a
end
local function edit(what, change)
local a = ready()
if not a then
return false
end
local box, done
for _, e in picks do
local copy = copyOf(e)
local pose = copy and Engine.copyPose(a, copy)
if not pose and not copy and e.pin and e.l.pins and table.find(e.l.pins, e.pin) then
local q = e.pin
pose = { l = e.l, vi = q[6], x = q[1], z = q[2], yaw = q[4], k = q[5], pin = q }
end
if pose then
local l = pose.l
local fromX, fromZ = pose.x, pose.z
local c = change(pose)
local pin
if copy then
pin = Engine.pinCopy(a, copy, c)
else
pin = Engine.changePin(l, pose.pin, c)
end
if pin then
local v = l.variants[pin[6]] or l.variants[1]
local r = v.m.radius * pin[5] * v.size * 2 + 6
local x0, z0 = math.min(fromX, pin[1]) - r, math.min(fromZ, pin[2]) - r
local x1, z1 = math.max(fromX, pin[1]) + r, math.max(fromZ, pin[2]) + r
box = box and { math.min(box[1], x0), math.min(box[2], z0), math.max(box[3], x1), math.max(box[4], z1) } or { x0, z0, x1, z1 }
e.copy, e.x, e.z, e.l, e.pin = nil, pin[1], pin[2], l, pin
done = true
end
end
end
if not done then
App.status(
#picks == 1 and "This copy can't be changed by itself (a piece of a line, or a preview box)."
or "These copies can't be changed by themselves."
)
return false
end
outline()
App.applyNow(nil, what, box, true)
follow()
return true
end
local function several(one, many)
return #picks > 1 and many or one
end
local function turn(dir)
return edit(several("Turn a copy", "Turn copies"), function(pose)
return { yaw = (math.floor(pose.yaw / STEP + 0.5) + dir) * STEP }
end)
end
local function size(dir)
return edit(several("Size a copy", "Size copies"), function(pose)
return { k = math.clamp(pose.k * 1.1 ^ dir, 0.05, 20) }
end)
end
local function nextModel(dir)
return edit(several("Change a copy's model", "Change copies' models"), function(pose)
return { vi = (pose.vi - 1 + (dir or 1)) % #pose.l.variants + 1 }
end)
end
local function moveTo(pos)
local a = App.area
if #picks ~= 1 then
return false
end
if not (a and Engine.hasCell(a, math.floor(pos.X / a.cell), math.floor(pos.Z / a.cell))) then
App.status("Click on this zone's painted ground to move it there.")
return false
end
return edit("Move a copy", function()
return { x = pos.X, z = pos.Z }
end)
end
local function remove()
local a = App.area
if #picks == 0 or not a or a.folder ~= picks[1].folder or a.locked then
return false
end
local rec = App.beginRec("Smart Scatter: " .. several("Remove copy", "Remove copies"))
local n = 0
for _, e in picks do
local copy = copyOf(e)
local h = copy and Engine.removeCopy(a, copy)
if h then
n += 1
for _, l in a.layers do
if l._h == h and App.lastCounts[l] then
App.lastCounts[l] = math.max(App.lastCounts[l] - 1, 0)
end
end
end
end
App.saveArea()
App.endRec(rec)
unpick()
App.setLabel("")
App.refreshCounts()
App.status(n == 1 and "Removed. Ctrl+Z brings it back." or string.format("Removed %d. Ctrl+Z brings them back.", n))
return n > 0
end
local function canGoBack()
local a, n = App.area, 0
for _, e in picks do
local copy = copyOf(e)
if a and copy and Engine.canUnpinCopy(a, copy) then
n += 1
end
end
return n
end
local function backToRules()
local a = ready()
if not a then
return false
end
local first
for _, e in picks do
local copy = copyOf(e)
local pose = copy and Engine.copyPose(a, copy)
if pose and Engine.unpinCopy(a, copy) then
local i = table.find(a.layers, pose.l) or 1
first = math.min(first or i, i)
e.copy, e.pin = nil, nil
end
end
if not first then
return false
end
outline()
App.applyNow(a.layers[first], "Give copies back to their rules")
follow()
return true
end
local function entry(thing, key, copy)
return { folder = thing.folder, key = key, copy = copy, x = copy:GetAttribute("SS_X") or 0, z = copy:GetAttribute("SS_Z") or 0 }
end
local function indexOf(copy)
for i, e in picks do
if copyOf(e) == copy then
return i
end
end
return nil
end
local function pick(thing, key, copy, add)
if add and #picks > 0 and picks[1].folder == thing.folder and App.mode == "Select" then
local i = indexOf(copy)
if i then
table.remove(picks, i)
elseif #picks < MAX_PICKS then
table.insert(picks, entry(thing, key, copy))
end
picks = table.clone(picks)
moving = false
showPicked()
if #picks == 0 then
App.setLabel("")
end
return nil
end
local object
App.select(thing)
for _, l in App.area and App.area.layers or {} do
if Engine.layerKey(l) == key then
object = l
end
end
App.select(thing, object)
if App.mode ~= "Select" then
return object
end
picks = { entry(thing, key, copy) }
moving = false
lightHover(nil)
showPicked()
return object
end
local function boxPick(a, b, add)
local out = Engine.outFolder()
local cam = workspace.CurrentCamera
if not (out and cam) then
return 0
end
local x0, x1, y0, y1 = math.min(a.X, b.X), math.max(a.X, b.X), math.min(a.Y, b.Y), math.max(a.Y, b.Y)
local keep = add and #picks > 0 and picks[1].folder or nil
local found = {}
for _, area in out:GetChildren() do
if area:GetAttribute("SS_Area") and (not keep or area == keep) and not (App.isHidden and App.isHidden(area)) then
for _, f in area:GetChildren() do
local key = f:GetAttribute("SS_Key")
if key and not f:GetAttribute("SS_Ghost") then
for _, d in f:GetDescendants() do
if d:GetAttribute("SS_Type") and d:GetAttribute("SS_X") then
local v = cam:WorldToViewportPoint(d:GetPivot().Position)
if v.Z > 0 and v.X >= x0 and v.X <= x1 and v.Y >= y0 and v.Y <= y1 then
found[area] = found[area] or {}
table.insert(found[area], { key, d })
end
end
end
end
end
end
end
local chosen = keep or (App.area and found[App.area.folder] and App.area.folder) or nil
if not chosen then
for area, list in found do
if not chosen or #list > #found[chosen] then
chosen = area
end
end
end
local list = chosen and found[chosen]
if not list then
return 0
end
local thing = App.thingOf(chosen)
if not keep then
if not App.sameThing(App.selected, thing) then
App.select(thing)
end
if App.mode ~= "Select" then
return 0
end
picks = {}
end
local next = table.clone(picks)
for _, pair in list do
if #next >= MAX_PICKS then
break
end
if not indexOf(pair[2]) then
table.insert(next, entry(thing, pair[1], pair[2]))
end
end
picks = next
moving = false
showPicked()
return #picks
end
local function menu()
local a, copy = App.area, pickedCopy()
local pose = a and copy and Engine.copyPose(a, copy)
local items = {}
if pose or #picks > 1 then
table.insert(items, {
"Turn 15°",
function()
turn(1)
end,
})
table.insert(items, {
"Turn 15° back",
function()
turn(-1)
end,
})
table.insert(items, {
"Bigger",
function()
size(1)
end,
})
table.insert(items, {
"Smaller",
function()
size(-1)
end,
})
if #picks == 1 and pose and #pose.l.variants > 1 then
table.insert(items, {
"Another of its models",
function()
nextModel(1)
end,
})
end
if #picks == 1 then
table.insert(items, {
"Move it…",
function()
moving = true
showPicked()
App.status("Click this zone's painted ground where it should stand. Esc leaves it where it is.")
end,
})
end
table.insert(items, "-")
if canGoBack() > 0 then
table.insert(items, { several("Back to its rules", "Back to their rules"), backToRules, P.dim })
end
end
if #picks == 1 then
table.insert(items, {
"Its object's settings",
function()
App.openTab("object")
end,
P.dim,
})
end
table.insert(items, "-")
table.insert(items, { several("Remove", string.format("Remove %d", #picks)), remove, P.danger })
return items
end
local function header()
local a, copy = App.area, pickedCopy()
if #picks == 0 or not copy then
return "Select", { { text = "Click a zone, a path or a copy · Shift + click or drag a box for more copies" } }, "none"
end
local one = #picks == 1
local pose = one and a and Engine.copyPose(a, copy) or nil
local items = {
{
step = "Turn",
value = pose and string.format("%d°", math.floor(math.deg(pose.yaw) + 0.5) % 360) or "15°",
dec = function()
turn(-1)
end,
inc = function()
turn(1)
end,
},
{
step = "Size",
value = pose and string.format("%.2f×", pose.k) or "10%",
dec = function()
size(-1)
end,
inc = function()
size(1)
end,
},
}
if pose and #pose.l.variants > 1 then
table.insert(items, {
step = "Model",
value = pose.l.variants[pose.vi].inst.Name,
dec = function()
nextModel(-1)
end,
inc = function()
nextModel(1)
end,
})
end
if one then
table.insert(items, {
button = "Move",
on = moving,
click = function()
moving = not moving
showPicked()
end,
})
end
local back = canGoBack()
if back > 0 then
table.insert(items, { button = several("Back to its rules", "Back to their rules"), click = backToRules })
end
table.insert(items, { button = several("Remove", string.format("Remove %d", #picks)), click = remove, danger = true })
local title = one and copy.Name or string.format("%d copies", #picks)
local key = string.format(
"%d|%s|%s|%d|%s",
#picks,
tostring(moving),
pose and string.format("%.3f|%.3f|%d", pose.yaw, pose.k, pose.vi) or "",
back,
title
)
return title, items, key
end
App.selectMove = function()
if press and (Vector2.new(rawMouse.X, rawMouse.Y) - press.px).Magnitude > DRAG_PX then
press.dragging = true
end
if press and press.dragging then
App.viewRect(press.px, Vector2.new(rawMouse.X, rawMouse.Y))
App.setLabel("")
return
end
local thing, key, copy = App.pickAt()
local g = App.mouseHit()
App.gizmoFolder()
for _, k in { "ring", "disc", "halo", "sq", "dot" } do
if App.gz[k] then
App.gz[k].Visible = false
end
end
outline()
local mine = copy ~= nil and indexOf(copy) ~= nil
lightHover(not moving and not mine and copy or nil)
if moving or (#picks > 0 and (mine or not thing)) then
showPicked()
elseif thing and g then
App.gz.anchor.CFrame = CFrame.new(g.Position)
local what = thing.folder and thing.folder.Name or "?"
if key then
what ..= " · " .. (string.match(key, "([^%.]+)$") or key)
end
App.setLabel((copy and #picks > 0 and App.shiftHeld()) and "Click to add it" or ("Click to select " .. what))
else
App.setLabel("")
end
end
App.selectDown = function()
if moving then
local g = App.mouseHit()
if g and moveTo(g.Position) then
moving = false
end
return
end
local add = App.shiftHeld()
local thing, key, copy = App.pickAt()
if not copy then
press = { px = Vector2.new(rawMouse.X, rawMouse.Y), add = add, thing = thing }
return
end
if not add and #picks == 1 and indexOf(copy) then
return
end
local object = pick(thing, key, copy, add)
if #picks > 1 then
App.status(string.format("%d copies picked. Shift + wheel turns them, Alt + wheel sizes them; the bar at the top has the rest.", #picks))
elseif #picks == 1 then
App.status(
"Selected "
.. (thing.folder and thing.folder.Name or thing.kind)
.. (object and (" · " .. object.inst.Name) or "")
.. ". Shift + wheel turns this copy, Alt + wheel sizes it, "
.. App.keyText("quick")
.. " has more; Shift + click adds copies."
)
end
end
App.selectUp = function()
local pr = press
press = nil
if not pr then
return
end
App.viewRect(nil)
if pr.dragging then
local n = boxPick(pr.px, Vector2.new(rawMouse.X, rawMouse.Y), pr.add)
App.status(
n > 0 and string.format("%d cop%s picked. The bar at the top turns, sizes and removes them.", n, n == 1 and "y" or "ies")
or "No copies in that box."
)
return
end
if pr.add and #picks > 0 then
return
end
unpick()
App.setLabel("")
if pr.thing then
App.select(pr.thing)
App.status("Selected " .. (pr.thing.folder and pr.thing.folder.Name or pr.thing.kind) .. ".")
end
end
local function wheel(dir)
if App.mode ~= "Select" or #picks == 0 then
return
end
local does = App.wheelDoes()
if not does then
return
end
App.holdCamera()
if does == "turn" then
turn(dir)
else
size(dir)
end
end
App.track(rawMouse.WheelForward:Connect(function()
wheel(1)
end))
App.track(rawMouse.WheelBackward:Connect(function()
wheel(-1)
end))
App.selectKey = function(name)
if name == "cancel" and (moving or press or #picks > 0) then
if moving or press then
moving, press = false, nil
App.viewRect(nil)
showPicked()
else
unpick()
App.setLabel("")
end
return true
end
if #picks == 0 then
return false
end
if name == "turn" then
turn(App.shiftHeld() and -1 or 1)
elseif name == "grow" or name == "shrink" then
size(name == "grow" and 1 or -1)
elseif name == "model" then
nextModel(1)
elseif name == "delete" then
remove()
else
return false
end
return true
end
App.openQuick = function()
local items, title = {}, nil
if App.mode == "Select" and #picks > 0 then
for _, it in menu() do
if type(it) == "table" then
table.insert(items, it)
end
end
title = #picks == 1 and "COPY" or string.format("%d COPIES", #picks)
else
for _, g in App.toolGroups() do
local t = g.tools[1]
if t and t.id ~= "search" then
table.insert(items, { (string.match(t.name, "^([^:(]+)") or t.name):gsub("%s+$", ""), t.click, t.on() and P.accent or nil })
end
end
title = "TOOLS"
end
if App.viewPie(items, title) then
return
end
if title ~= "TOOLS" then
App.popupMenu(App.ui.outliner or App.root, menu(), title)
elseif App.openPalette then
App.openPalette()
end
end
App.pickedCopy = pickedCopy
App.pickedCopies = function()
local t = {}
for _, e in picks do
local c = copyOf(e)
if c then
table.insert(t, c)
end
end
return t
end
App.pickCopy = pick
App.boxPick = boxPick
App.copyMenu = menu
App.copyHeader = header
App.copyEdit = { turn = turn, size = size, model = nextModel, move = moveTo, remove = remove, back = backToRules }
App.onSelect(function(thing)
if #picks > 0 and not (thing and thing.folder == picks[1].folder) then
unpick()
end
end)
App.registerMode("Select", { move = App.selectMove, down = App.selectDown, up = App.selectUp, stop = unpick, header = header, noArea = true })
App.registerTool({
id = "select",
group = "Select",
icon = "cursor",
name = "Select: click a zone, a path or a placed copy; Shift + click or drag a box for more copies",
on = function()
return App.mode == "Select"
end,
click = function()
App.setMode(App.mode == "Select" and "Off" or "Select")
end,
})
end
end)()
-- #module App/Viewport/ArrayTool
MODULES["App/Viewport/ArrayTool"] = (function()
--[[
Smart Scatter — ArrayTool: the strip's Array tool. With a model selected in the Explorer (or an array selected: its
model), press on the ground and drag: a line runs from the press to the mouse, and on letting go an array of the
model lines up along it, as many as fit at the model's own spacing. A plain click makes a row of six running the
way the camera looks. The array is then selected, its tab open to tune it (Panel/ArrayTools).
Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]
return function(App)
local rawMouse = App.rawMouse
local DRAG_PX = 6
local press
local line
local function source()
local src = App.arraySource()
if not src and App.selected and App.selected.kind == "Array" then
local v = App.selected.folder:FindFirstChild("Source")
src = v and v.Value
end
return src
end
local function onGround(y)
local ray = rawMouse.UnitRay
if math.abs(ray.Direction.Y) > 1e-3 then
local t = (y - ray.Origin.Y) / ray.Direction.Y
if t > 0 then
return ray.Origin + ray.Direction * t
end
end
return nil
end
local function clearLine()
if line then
line:Destroy()
line = nil
end
end
local function move()
App.gizmoFolder()
local hit = App.mouseHit()
if not press then
if hit then
App.gz.anchor.CFrame = CFrame.new(hit.Position)
local src = source()
App.setLabel(src and ("Array of " .. src.Name .. " · press and drag along where they go") or "Select a model in the Explorer first")
end
return
end
local to = onGround(press.at.Y)
if not to then
return
end
local d = Vector3.new(to.X - press.at.X, 0, to.Z - press.at.Z)
if not line then
line = App.new("LineHandleAdornment", {
Adornee = workspace.Terrain,
AlwaysOnTop = true,
Thickness = 4,
ZIndex = 5,
Color3 = App.VIEW.accent,
Parent = App.gizmoFolder(),
})
end
line.Visible = d.Magnitude > 0.05
if d.Magnitude > 0.05 then
local from = press.at + Vector3.new(0, 0.3, 0)
line.CFrame, line.Length = CFrame.lookAt(from, from + d), d.Magnitude
end
local n = math.max(math.floor(d.Magnitude / press.spacing) + 1, 2)
App.gz.anchor.CFrame = CFrame.new(to)
App.setLabel(string.format("%d × %s · let go to make it", n, press.src.Name))
end
local function down()
local src = source()
local hit = App.mouseHit()
if not src then
App.status("Select a model in the Explorer first: the array repeats it.")
return
end
if hit then
press = { at = hit.Position, px = Vector2.new(rawMouse.X, rawMouse.Y), src = src, spacing = App.arraySpacing(src) }
end
end
local function up()
local pr = press
press = nil
clearLine()
if not pr then
return
end
local to = onGround(pr.at.Y)
local dragged = (Vector2.new(rawMouse.X, rawMouse.Y) - pr.px).Magnitude > DRAG_PX and to ~= nil
local dir, count
if dragged then
local d = Vector3.new(to.X - pr.at.X, 0, to.Z - pr.at.Z)
dir = d.Magnitude > 1e-3 and d.Unit or Vector3.new(0, 0, -1)
count = math.max(math.floor(d.Magnitude / pr.spacing) + 1, 2)
else
local look = workspace.CurrentCamera.CFrame.LookVector
local flat = Vector3.new(look.X, 0, look.Z)
dir = flat.Magnitude > 1e-3 and flat.Unit or Vector3.new(0, 0, -1)
count = 6
end
App.setMode("Off")
App.newArray(pr.src, CFrame.lookAt(pr.at, pr.at + dir), { shape = "Line", count = count, spacing = pr.spacing })
App.status(string.format("Array of %d %s made. Tune it on its Array tab.", count, pr.src.Name))
end
local function stop()
press = nil
clearLine()
end
App.registerMode("Array", {
move = move,
down = down,
up = up,
stop = stop,
header = function()
local src = source()
return "Array" .. (src and (" · " .. src.Name) or ""),
{ { text = src and "Press and drag along where the copies go" or "Select a model in the Explorer first" } },
src and src.Name or ""
end,
noArea = true,
})
App.registerTool({
id = "array",
group = "Stamp",
order = 2,
icon = "grid",
name = "Array: drag along the ground to line up copies of the selected model",
on = function()
return App.mode == "Array"
end,
click = function()
if App.mode == "Array" then
App.setMode("Off")
elseif source() then
App.setMode("Array")
else
App.status("Select a model in the Explorer first: the array repeats it.")
end
end,
})
end
end)()
-- #module App/Viewport/Focus
MODULES["App/Viewport/Focus"] = (function()
--[[
Smart Scatter — Focus: while a tool of the plugin is on in the viewport (painting, erasing, drawing the path,
brushing one object, removing copies), the world steps back a touch so the tool stands out: it loses a little
colour (a colour correction on the camera, never saved with the place). Settings › Viewport can turn it off.
What the tool is doing is said in one place, the viewport's header (Viewport/Toolbar); App.focusState tells it
whether the tool takes things away (its name is red then).
Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]
return function(App)
local G, tween, MED = App.G, App.tween, App.MED
local new = App.new
local LAYER_MODES = App.LAYER_MODES
local LOOK = { Saturation = -0.18, Brightness = -0.03, Contrast = 0 }
local cc
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
return erase and "Erase" or "Paint", on(area, G.tool), erase
elseif m == "Spline" and App.shapeTool then
return App.shapeTool, on(area, App.shapeTool == "Rectangle" and "drag corner to corner" or "drag from the centre"), false
elseif m == "Spline" then
return "Draw path", on(area), false
elseif m == "Stamp" then
local inst = App.stamp and App.stamp.models[App.stamp.vi]
return "Stamp", inst and inst.Name or nil, false
elseif m == "Remove" then
return "Remove copies", on(area, "click one"), true
elseif m == "Select" then
return "Select", "click a zone, a path or a copy", false
elseif m == "Array" then
return "Array", "drag along where the copies go", false
elseif LAYER_MODES[m] then
local act = shift and App.LAYER_OPPOSITE[m] or m
local name = App.paintLayer and App.paintLayer.inst.Name or nil
return App.LAYER_LABEL[act], (area and name) and (area .. "  ›  " .. name) or on(area, name), act == "None" or act == "Less"
end
return nil, nil, false
end
local shown = false
App.focusState = describe
App.refreshFocus = function()
local what = describe()
local on = G.focus ~= false and what ~= nil
if on then
local cam = workspace.CurrentCamera
if cam and not (cc and cc.Parent == cam) then
cc = new(
"ColorCorrectionEffect",
{ Name = "SmartScatterFocus", Archivable = false, Saturation = 0, Brightness = 0, Contrast = 0, Parent = cam }
)
end
if not shown and cc then
tween(cc, MED, LOOK)
end
shown = true
elseif shown then
shown = false
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
end
local cam = workspace.CurrentCamera
local old = cam and not App.ctx.preview and cam:FindFirstChild("SmartScatterFocus")
if old then
old:Destroy()
end
pcall(function()
if App.ctx.preview then
return
end
local g = game:GetService("CoreGui"):FindFirstChild("SmartScatterFocus")
if g then
g:Destroy()
end
end)
end
end)()
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
local stripNeeds = 0
local function placeStrip()
if not (gui and strip and strip.Parent) then
return
end
local room = gui.AbsoluteSize.Y
local wrap = stripNeeds > room - 16
local layout = strip:FindFirstChildOfClass("UIListLayout")
layout.Wraps = wrap
strip.AutomaticSize = wrap and Enum.AutomaticSize.X or Enum.AutomaticSize.XY
strip.Size = wrap and UDim2.fromOffset(0, math.max(room - 16, BTN * 3)) or UDim2.fromOffset(0, 0)
strip.Position = UDim2.fromOffset(10, math.max(8, math.floor((room - strip.AbsoluteSize.Y) / 2)))
end
local function buildStrip()
for _, c in strip:GetChildren() do
if c:IsA("GuiObject") then
c:Destroy()
end
end
table.clear(looks)
stripNeeds = 6
for gi, g in App.toolGroups() do
local group = g.tools
if gi > 1 then
stripNeeds += 7 + 2
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
stripNeeds += BTN + 2
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
local function options()
local m = App.mode
if m == "Off" then
return nil
end
local handler = App.modeHandlers[m]
if handler and handler.header then
return handler.header()
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
local _, _, takes = App.focusState()
label(title, 12, takes and P.danger or P.text, SANS_B, { Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, Parent = bar })
table.insert(items, { text = App.keyText("cancel") .. " to stop", quiet = true })
local function small(text, click, on, danger)
local b = new("TextButton", {
Text = text,
Font = SANS,
TextSize = 12,
TextColor3 = on and P.onAccent or danger and P.danger or P.text,
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
label(it.text, 12, it.quiet and P.faint or P.dim, SANS, {
Size = UDim2.fromOffset(0, 24),
AutomaticSize = Enum.AutomaticSize.X,
Parent = bar,
})
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
small(it.button, it.click, it.on, it.danger)
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
{ Position = UDim2.fromOffset(10, 8), AutomaticSize = Enum.AutomaticSize.XY, Parent = gui },
new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) })
)
pad(3, 3, 3, 3).Parent = strip
strip:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeStrip)
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeStrip)
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
local handler = App.modeHandlers[App.mode]
local b = table.concat({
App.mode,
G.tool,
G.radius,
G.shape,
G.fillReach,
tostring(App.paintLayer and App.paintLayer.inst.Name),
tostring(App.shapeTool),
tostring(App.hasPath and App.hasPath()),
handler and handler.header and tostring(select(3, handler.header())) or "",
tostring(select(3, App.focusState())),
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
placeStrip()
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
local menu
App.closeViewMenu = function()
if menu then
menu:Destroy()
menu = nil
end
end
local RING, PIE_W, PIE_H = 96, 118, 28
App.viewPie = function(items, title)
App.closeViewMenu()
if not App.toolbarAvailable() then
return false
end
local list = {}
for _, it in items do
if type(it) == "table" and #list < 8 then
table.insert(list, it)
end
end
if #list == 0 then
return false
end
local screen = gui.AbsoluteSize
local at = Vector2.new(
math.clamp(App.rawMouse.X, RING + PIE_W / 2 + 6, math.max(RING + PIE_W / 2 + 6, screen.X - RING - PIE_W / 2 - 6)),
math.clamp(App.rawMouse.Y, RING + PIE_H, math.max(RING + PIE_H, screen.Y - RING - PIE_H))
)
local catcher = new("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 20, Parent = gui })
menu = catcher
catcher.MouseButton1Click:Connect(App.closeViewMenu)
catcher.MouseButton2Click:Connect(App.closeViewMenu)
if title then
local mid = label(title, 11, P.dim, SANS_B, {
AnchorPoint = Vector2.new(0.5, 0.5),
Position = UDim2.fromOffset(at.X, at.Y),
Size = UDim2.fromOffset(0, 22),
AutomaticSize = Enum.AutomaticSize.X,
BackgroundTransparency = SEE,
BackgroundColor3 = P.card,
TextXAlignment = Enum.TextXAlignment.Center,
ZIndex = 21,
Parent = catcher,
})
corner(11).Parent = mid
pad(9, 9, 0, 0).Parent = mid
end
for i, it in list do
local ang = -math.pi / 2 + (i - 1) * 2 * math.pi / #list
local b = new("TextButton", {
Text = it[1],
Font = SANS,
TextSize = 12,
TextColor3 = it[3] or P.text,
TextTruncate = Enum.TextTruncate.AtEnd,
BackgroundColor3 = P.card,
BackgroundTransparency = SEE,
AutoButtonColor = false,
AnchorPoint = Vector2.new(0.5, 0.5),
Position = UDim2.fromOffset(at.X + math.cos(ang) * RING * 1.25, at.Y + math.sin(ang) * RING * 0.8),
Size = UDim2.fromOffset(PIE_W, PIE_H),
ZIndex = 22,
Parent = catcher,
}, { corner(7), stroke(P.line), pad(6, 6, 0, 0) })
b.MouseEnter:Connect(function()
b.BackgroundColor3, b.BackgroundTransparency = P.hover, 0
end)
b.MouseLeave:Connect(function()
b.BackgroundColor3, b.BackgroundTransparency = P.card, SEE
end)
b.MouseButton1Click:Connect(function()
App.closeViewMenu()
it[2]()
end)
end
return true
end
local rect
App.viewRect = function(a, b)
if not (a and b and gui and gui.Parent) then
if rect then
rect.Visible = false
end
return
end
if not (rect and rect.Parent) then
rect = box({ BackgroundTransparency = 0.85, BackgroundColor3 = P.accent, ZIndex = 15, Parent = gui }, { stroke(P.accent) })
end
rect.Visible = true
rect.Position = UDim2.fromOffset(math.min(a.X, b.X), math.min(a.Y, b.Y))
rect.Size = UDim2.fromOffset(math.abs(a.X - b.X), math.abs(a.Y - b.Y))
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
for _, r in App.registeredActions() do
add({ id = r.id, name = r.name, group = r.group, icon = r.icon, words = r.words, key = r.key, danger = r.danger, run = r.run })
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
id = "newarray",
name = "New array from the selected model",
group = "Areas",
icon = "grid",
words = "repeat copies row grid circle radial duplicate",
run = App.newArrayFromSelection,
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
text = "The icons down this side are tabs, for what's selected (hover one for its name). A zone has Objects, Zone and World; a path has Curve and Road too; "
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

return MODULES
