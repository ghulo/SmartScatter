-- GENERATED part 3 of the flattened release by tools/tree.py: edit the modules, not this.
local MODULES = {}

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
local placedByUs = { workspace:FindFirstChild(Engine.OUT), workspace:FindFirstChild(Engine.ROADS) }
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
A click on a placed copy also picks that one copy: it's outlined, Shift + the wheel turns it and Alt + the wheel
sizes it (as the stamp's), the stamp's keys work on it, and a right-click on a copy has the rest (another model,
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
local out = workspace:FindFirstChild(Engine.OUT)
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
if area then
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
local picked, moving = nil, false
local function light(name, copy, fill)
App.gizmoFolder()
local h = App.gz[name]
if not (h and h.Parent) then
if not copy then
return
end
h = Instance.new("Highlight")
h.DepthMode = Enum.HighlightDepthMode.Occluded
h.OutlineTransparency = 0
h.Parent = App.gz.folder
App.gz[name] = h
end
h.FillColor, h.OutlineColor = P.accent, P.accent
h.FillTransparency = fill
h.Adornee = copy
end
local function pickedCopy()
if not picked then
return nil
end
if picked.copy and picked.copy.Parent then
return picked.copy
end
picked.copy = nil
local a = App.area
if not (a and a.folder == picked.folder) then
return nil
end
for _, f in a.folder:GetChildren() do
if f:GetAttribute("SS_Key") == picked.key then
for _, d in f:GetDescendants() do
local x, z = d:GetAttribute("SS_X"), d:GetAttribute("SS_Z")
if x and z and d:GetAttribute("SS_Type") and math.abs(x - picked.x) < 0.05 and math.abs(z - picked.z) < 0.05 then
picked.copy = d
return d
end
end
end
end
return nil
end
local function describe(copy)
local pose = App.area and Engine.copyPose(App.area, copy)
if not pose then
return copy.Name
end
return string.format("%s · %d° · %.2f×", copy.Name, math.floor(math.deg(pose.yaw) + 0.5) % 360, pose.k)
end
local function showPicked()
local copy = pickedCopy()
light("copySel", copy, 0.8)
if copy then
App.gz.anchor.CFrame = CFrame.new(copy:GetPivot().Position)
App.setLabel(moving and "Click where it should stand" or (describe(copy) .. "  ·  right-click for more"))
end
end
local function unpick()
picked, moving = nil, false
light("copySel", nil, 0.8)
light("copyHover", nil, 1)
if App.closeViewMenu then
App.closeViewMenu()
end
end
local function follow()
local mine = picked
task.spawn(function()
for _ = 1, 60 do
task.wait(0.05)
if picked ~= mine or App.mode ~= "Select" then
return
end
if pickedCopy() then
showPicked()
return
end
end
end)
end
local function edit(what, change)
local a = App.area
if not (picked and a and a.folder == picked.folder) then
return false
end
if a.locked then
App.status("This area is locked. Unlock it to change its copies.")
return false
end
if not App.canGenerate() then
App.status("The area can't be rebuilt right now: the Generate button says why.")
return false
end
local copy = pickedCopy()
local pose = copy and Engine.copyPose(a, copy)
if not pose and not copy and picked.pin and picked.l.pins and table.find(picked.l.pins, picked.pin) then
local q = picked.pin
pose = { l = picked.l, vi = q[6], x = q[1], z = q[2], yaw = q[4], k = q[5], pin = q }
end
if not pose then
App.status(copy and "This copy can't be changed by itself (a piece of a line, or a preview box)." or "That copy is gone.")
return false
end
local l = pose.l
local fromX, fromZ = pose.x, pose.z
local c = change(pose)
local pin
if copy then
pin = Engine.pinCopy(a, copy, c)
else
pin = Engine.changePin(l, pose.pin, c)
end
if not pin then
return false
end
local v = l.variants[pin[6]] or l.variants[1]
local r = v.m.radius * pin[5] * v.size * 2 + 6
local box = { math.min(fromX, pin[1]) - r, math.min(fromZ, pin[2]) - r, math.max(fromX, pin[1]) + r, math.max(fromZ, pin[2]) + r }
picked.copy, picked.x, picked.z, picked.l, picked.pin = nil, pin[1], pin[2], l, pin
light("copySel", nil, 0.8)
App.applyNow(l, what, box, true)
follow()
return true
end
local function turn(dir)
return edit("Turn a copy", function(pose)
return { yaw = (math.floor(pose.yaw / STEP + 0.5) + dir) * STEP }
end)
end
local function size(dir)
return edit("Size a copy", function(pose)
return { k = math.clamp(pose.k * 1.1 ^ dir, 0.05, 20) }
end)
end
local function nextModel()
return edit("Change a copy's model", function(pose)
return { vi = pose.vi % #pose.l.variants + 1 }
end)
end
local function moveTo(pos)
local a = App.area
if not (a and Engine.hasCell(a, math.floor(pos.X / a.cell), math.floor(pos.Z / a.cell))) then
App.status("Click on this zone's painted ground to move it there.")
return false
end
return edit("Move a copy", function()
return { x = pos.X, z = pos.Z }
end)
end
local function remove()
local a, copy = App.area, pickedCopy()
if not (a and copy) or a.locked then
return false
end
local rec = App.beginRec("Smart Scatter: Remove copy")
local h = Engine.removeCopy(a, copy)
for _, l in a.layers do
if l._h == h and App.lastCounts[l] then
App.lastCounts[l] = math.max(App.lastCounts[l] - 1, 0)
end
end
App.saveArea()
App.endRec(rec)
unpick()
App.setLabel("")
App.refreshCounts()
App.status("Removed. Ctrl+Z brings it back.")
return true
end
local function backToRules()
local a, copy = App.area, pickedCopy()
if not (a and copy) or a.locked or not App.canGenerate() then
return false
end
local pose = Engine.copyPose(a, copy)
if not (pose and Engine.unpinCopy(a, copy)) then
return false
end
picked.copy, picked.pin = nil, nil
light("copySel", nil, 0.8)
App.applyNow(pose.l, "Give a copy back to its rules")
follow()
return true
end
local function pick(thing, key, copy)
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
picked = { folder = thing.folder, key = key, copy = copy, x = copy:GetAttribute("SS_X") or 0, z = copy:GetAttribute("SS_Z") or 0 }
moving = false
light("copyHover", nil, 1)
showPicked()
return object
end
local function menu()
local a, copy = App.area, pickedCopy()
local pose = a and copy and Engine.copyPose(a, copy)
local items = {}
if pose then
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
if #pose.l.variants > 1 then
table.insert(items, { "Another of its models", nextModel })
end
table.insert(items, {
"Move it…",
function()
moving = true
showPicked()
App.status("Click this zone's painted ground where it should stand. Esc leaves it where it is.")
end,
})
table.insert(items, "-")
if Engine.canUnpinCopy(a, copy) then
table.insert(items, { "Back to its rules", backToRules, P.dim })
end
end
table.insert(items, {
"Its object's settings",
function()
App.openTab("object")
end,
P.dim,
})
table.insert(items, "-")
table.insert(items, { "Remove", remove, P.danger })
return items
end
App.selectMove = function()
local thing, key, copy = App.pickAt()
local g = App.mouseHit()
App.gizmoFolder()
for _, k in { "ring", "disc", "halo", "sq", "dot" } do
if App.gz[k] then
App.gz[k].Visible = false
end
end
local mine = pickedCopy()
light("copySel", mine, 0.8)
light("copyHover", not moving and copy ~= mine and copy or nil, 1)
if moving or (mine and (copy == mine or not thing)) then
showPicked()
elseif thing and g then
App.gz.anchor.CFrame = CFrame.new(g.Position)
local what = thing.folder and thing.folder.Name or "?"
if key then
what ..= " · " .. (string.match(key, "([^%.]+)$") or key)
end
App.setLabel("Click to select " .. what)
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
local thing, key, copy = App.pickAt()
if not thing then
unpick()
return
end
local object
if copy then
object = pick(thing, key, copy)
else
unpick()
App.select(thing)
end
App.status(
"Selected "
.. (thing.folder and thing.folder.Name or thing.kind)
.. (object and (" · " .. object.inst.Name) or "")
.. (copy and ". Shift + wheel turns this copy, Alt + wheel sizes it, right-click has more." or ".")
)
end
App.onRightClick(function()
if App.mode ~= "Select" or moving then
return
end
local thing, key, copy = App.pickAt()
if not copy then
return
end
if copy ~= pickedCopy() then
pick(thing, key, copy)
end
if picked then
App.viewMenu(menu(), string.upper(copy.Name))
end
end)
local function wheel(dir)
if App.mode ~= "Select" or not picked then
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
if name == "cancel" and (moving or picked) then
if moving then
moving = false
showPicked()
else
unpick()
App.setLabel("")
end
return true
end
if not picked then
return false
end
if name == "turn" then
turn(App.shiftHeld() and -1 or 1)
elseif name == "grow" or name == "shrink" then
size(name == "grow" and 1 or -1)
elseif name == "model" then
nextModel()
elseif name == "delete" then
remove()
else
return false
end
return true
end
App.pickedCopy = pickedCopy
App.pickCopy = pick
App.copyMenu = menu
App.copyEdit = { turn = turn, size = size, model = nextModel, move = moveTo, remove = remove, back = backToRules }
App.onSelect(function(thing)
if picked and not (thing and thing.folder == picked.folder) then
unpick()
end
end)
App.registerMode("Select", { move = App.selectMove, down = App.selectDown, stop = unpick, noArea = true })
App.registerTool({
id = "select",
group = "Select",
icon = "cursor",
name = "Select: click a zone, a path or a placed copy",
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
App.registerMode("Array", { move = move, down = down, up = up, stop = stop, noArea = true })
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
brushing one object, removing copies), the world steps back a touch so the tool stands out, and the viewport's top
left says what's going on, the way Blender's does: the tool, then what it works on, then how to stop. Small, plain
text; no frame, no badges. The world only loses a little colour (a colour correction on the camera, never saved
with the place). The tool's name turns red while it takes things away. Settings › Viewport can turn it off.
Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]
return function(App)
local G, P, tween, MED, FAST = App.G, App.P, App.tween, App.MED, App.FAST
local new, box, label = App.new, App.box, App.label
local SANS, SANS_M = App.SANS, App.SANS_M
local LAYER_MODES = App.LAYER_MODES
local LOOK = { Saturation = -0.18, Brightness = -0.03, Contrast = 0 }
local WHITE = Color3.fromRGB(235, 235, 235)
local cc
local gui, group, tick, title, detail, stop
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
local corner =
box({ Position = UDim2.fromOffset(14, 12), Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY, Parent = group })
tick = box({
BackgroundTransparency = 0,
BackgroundColor3 = P.accent,
Position = UDim2.fromOffset(0, 3),
Size = UDim2.fromOffset(2, 13),
Parent = corner,
})
local lines = box(
{ Position = UDim2.fromOffset(9, 0), Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY, Parent = corner },
{
new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 0) }),
}
)
local function line(size, font, order)
local t = label("", size, WHITE, font, {
Size = UDim2.fromOffset(0, size + 5),
AutomaticSize = Enum.AutomaticSize.X,
LayoutOrder = order,
Parent = lines,
})
t.TextTruncate = Enum.TextTruncate.None
t.TextStrokeColor3, t.TextStrokeTransparency = Color3.new(0, 0, 0), 0.8
return t
end
title = line(14, SANS_M, 1)
detail = line(12, SANS, 2)
detail.TextTransparency = 0.3
stop = line(11, SANS, 3)
stop.TextTransparency = 0.5
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
local col = erase and P.danger:Lerp(WHITE, 0.25) or WHITE
tick.BackgroundColor3 = erase and P.danger or P.accent
title.Text = what
title.TextColor3 = col
detail.Text = where or ""
detail.Visible = where ~= nil and where ~= ""
stop.Text = App.keyText("cancel") .. " to stop"
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
elseif m == "Array" then
title = "Array"
table.insert(items, { text = "Press and drag along where the copies go" })
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
local menu
App.closeViewMenu = function()
if menu then
menu:Destroy()
menu = nil
end
end
App.viewMenu = function(items, title)
App.closeViewMenu()
if not App.toolbarAvailable() then
App.popupMenu(App.ui.outliner or App.root, items, title)
return
end
local at = Vector2.new(App.rawMouse.X, App.rawMouse.Y)
local catcher = new("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 20, Parent = gui })
menu = catcher
catcher.MouseButton1Click:Connect(App.closeViewMenu)
catcher.MouseButton2Click:Connect(App.closeViewMenu)
local W = 210
local list = box({
BackgroundTransparency = SEE,
BackgroundColor3 = P.card,
Position = UDim2.fromOffset(at.X + 4, at.Y + 4),
Size = UDim2.fromOffset(W, 0),
AutomaticSize = Enum.AutomaticSize.Y,
ZIndex = 21,
Parent = catcher,
}, { corner(8), stroke(P.line), pad(4, 4, 4, 4), App.vlist(1) })
if title then
local head = label(title, 11, P.faint, SANS_B, { Size = UDim2.new(1, 0, 0, 22), ZIndex = 22, Parent = list })
pad(8, 8, 0, 0).Parent = head
end
for _, it in items do
if it == "-" then
box({ BackgroundTransparency = 0, BackgroundColor3 = P.line, Size = UDim2.new(1, 0, 0, 1), ZIndex = 22, Parent = list })
continue
end
local b = new("TextButton", {
Text = it[1],
Font = SANS,
TextSize = 13,
TextColor3 = it[3] or P.text,
TextXAlignment = Enum.TextXAlignment.Left,
BackgroundColor3 = P.hover,
BackgroundTransparency = 1,
AutoButtonColor = false,
Size = UDim2.new(1, 0, 0, 26),
ZIndex = 22,
Parent = list,
}, { corner(5), pad(8, 8, 0, 0) })
b.MouseEnter:Connect(function()
b.BackgroundTransparency = 0
end)
b.MouseLeave:Connect(function()
b.BackgroundTransparency = 1
end)
b.MouseButton1Click:Connect(function()
App.closeViewMenu()
it[2]()
end)
end
local function keepOn()
local screen = gui.AbsoluteSize
list.Position = UDim2.fromOffset(
math.max(4, math.min(at.X + 4, screen.X - W - 8)),
math.max(4, math.min(at.Y + 4, screen.Y - list.AbsoluteSize.Y - 8))
)
end
list:GetPropertyChangedSignal("AbsoluteSize"):Connect(keepOn)
keepOn()
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
local SKIP =
{ SS_TopY = true, SS_Failed = true, SS_Kind = true, SS_Area = true, SS_Mask = true, SS_Layers = true, SS_Removed = true, SS_Order = true }
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
