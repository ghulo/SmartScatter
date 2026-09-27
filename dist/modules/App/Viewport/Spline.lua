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

	--------------------------------------------------------------------------------
	-- Spline editing: click to add points, drag to move them along any surface (Shift+drag = height),
	-- click the curve to insert, right-click or Delete to remove, Enter/Esc to finish.
	-- Networks: select any point, then click the ground. The end of a curve extends it; any other point
	-- sprouts a new branch from there. Points that sit on each other are welded and move together.
	--------------------------------------------------------------------------------
	local sv = {} -- viewport preview: curves, strip edges, point handles, insert ghost
	local hoverPt, hoverIns, dragPt, dragRec, dragMoved, selPt -- points are { cv = curve, i = index }
	local welded = {}
	local HANDLE_PX, CURVE_PX, WELD = 14, 10, 0.05
	local VIEW = App.VIEW -- the viewport palette (Base; follows the accent theme)
	local hoverHandle, dragHandle -- "in" / "out": the selected point's curve handles
	local drawing -- hold-and-drag stroke: { cv, prepend, anchor, spacing, pts }
	local joinSnap

	local function ensureSpline()
		if not App.area then
			newArea()
		end
		App.area.spline = App.area.spline or { pts = {}, closed = false, width = 0, snap = true }
		App.area.spline.branches = App.area.spline.branches or {}
		return App.area.spline
	end
	-- the editable curves: the main curve first, then each branch (the real tables, so edits land in the area)
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
	-- the curve table the engine evaluates for an editable curve (branches are always open)
	local function curveOf(cv)
		local sp = App.area.spline
		return cv == sp and sp or { pts = cv.pts, closed = false }
	end
	local function selectPt(ref)
		selPt = ref
		if App.ui.refreshPoint then
			App.ui.refreshPoint()
		end
	end
	-- the selected point's two handles (its Bezier control points): out = p + h, in = p - h; none on sharp points
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
			and not (App.overlayHidden and App.mode ~= "Spline") -- hidden with the overlay, except while drawing it
	end
	local function removeSplineViz()
		if sv.folder then
			sv.folder:Destroy()
		end
		sv = {}
	end
	local dot -- (below) a two-tone handle
	local function svFolder()
		if sv.folder and sv.folder.Parent then
			return
		end
		sv = { handles = {}, segs = {}, curves = {} }
		sv.folder = new("Folder", { Name = "SmartScatterSpline", Archivable = false, Parent = workspace.CurrentCamera })
		local T = workspace.Terrain
		local ok, w = pcall(function() -- one adornment draws every curve; falls back to pooled boxes on older Studio builds
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
			-- the neon glow under the curve: the same lines, wide and faint
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
	-- a handle: a light fill inside a dark rim, so it reads on any ground (two spheres, the fill drawn on top)
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
	-- show a handle: radius r at p; fill colour; rim colour (dark by default, light when hovered or selected)
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
				-- light fill; the start is sage, sharp corners amber; hovered or selected: sage inside a light rim
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
		-- the selected point's handles: drag them to bend the curve through it
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
		local step = math.max(1, approx / 500) -- display resolution: ~500 segments for the whole network
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
		if sv.edge and (sp.width or 0) > 0 then -- the strip that gets filled
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
		end -- keep handles the same size on screen
	end))

	local mouseAt -- screen position to test instead of the plugin mouse (clicks while the editor is off)
	local function screenDist(p)
		local v, on = workspace.CurrentCamera:WorldToViewportPoint(p)
		if not on or v.Z <= 0 then
			return math.huge
		end
		local m = mouseAt or Vector2.new(rawMouse.X, rawMouse.Y)
		return (Vector2.new(v.X, v.Y) - m).Magnitude
	end
	-- skip(cv, i, q) -> true leaves a point out (the one being dragged, its twins)
	local function pickPoint(skip)
		local best, bd = nil, HANDLE_PX
		for _, cv in editCurves() do
			for i, q in cv.pts do
				if not (skip and skip(cv, i, q)) then
					local d = screenDist(q.p + q.n * 0.3)
					if d < bd - 0.5 then -- ties (welded points) keep the earlier curve, so the main curve wins
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
	-- skip(cv, seg) -> true leaves a stretch of curve out
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
	-- where a dragged point would join the network: onto another point (welded) or, for an end, onto a curve
	-- (a T-junction: a real point is added there on release). nil when it's free.
	local snapTo
	local function findSnap(ref, extra)
		local q = ref.cv.pts[ref.i]
		local function mine(cv, i, o)
			return (cv == ref.cv and i == ref.i) or (o.p - q.p).Magnitude < WELD or (extra and extra[o])
		end
		local hitPt = pickPoint(function(cv, i, o)
			return mine(cv, i, o) or (cv == ref.cv and math.abs(i - ref.i) == 1) -- a neighbour would fold the curve
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
	-- what a click on empty ground does with the current selection
	local function growAction()
		local sp = App.area and App.area.spline
		if not sp or #sp.pts == 0 or not validPt(selPt) then
			return "append"
		end
		local cv, i = selPt.cv, selPt.i
		local open = cv ~= sp or not sp.closed or #sp.pts < 3
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
		local n, nb = totalPoints(), #(sp.branches or {})
		App.ui.splineInfo.Text = string.format(
			"%d point%s · %s studs · %s%s%s",
			n,
			n == 1 and "" or "s",
			num(len),
			(sp.closed and #sp.pts >= 3) and "loop" or "open",
			nb > 0 and string.format(" · %d branch%s", nb, nb == 1 and "" or "es") or "",
			(sp.width or 0) > 0 and string.format(" · %d-stud strip", sp.width) or ""
		)
	end

	-- after any spline change: rebuild the strip area if it has one, save (inside the undo step), then regenerate
	local function commitSpline(rec)
		local sp = App.area.spline
		if sp and (sp.width or 0) > 0 then
			refreshParams()
			Engine.maskFromSpline(App.area, App.probeParams)
			rebuildOverlay(true)
		end
		saveArea()
		endRec(rec) -- the undo step holds the curve; the objects are rebuilt after it, and again on undo
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
	-- where a click lands: on the ground under a wall unless this spline allows points on walls
	local function pointHit()
		local hit = mouseHit()
		local sp = App.area and App.area.spline
		if hit and hit.Normal.Y < 0.55 and not (sp and sp.walls) then
			local down = workspace:Raycast(hit.Position + hit.Normal * 0.6 + Vector3.new(0, 0.5, 0), Vector3.new(0, -600, 0), App.probeParams)
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
		local sp = App.area and App.area.spline
		if dragHandle and validPt(selPt) then -- bend: the handle follows the mouse on the point's level (Shift: height)
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
					local off = ray.Origin + ray.Direction * t - q.p -- where the dragged handle should sit
					if shiftHeld() then -- keep its flat position, only change the height
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
			if shiftHeld() then -- vertical move on a camera-facing plane through the point
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
							-- raised off the ground: the curve keeps this height instead of snapping down
							local below = workspace:Raycast(q.p + Vector3.yAxis * 2, Vector3.yAxis * -500, App.probeParams)
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
					q.raised = nil -- back on a surface
				end
				snapTo = findSnap(dragPt)
				if snapTo then -- magnet: sit exactly on the point or curve it would join
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
				for _, w in welded do -- joined points travel together
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
			-- keep holding and drag to draw: a point drops every few studs (spacing grows with camera distance)
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
	-- makes a snap permanent. Returns a status line.
	function joinSnap(ref, snap)
		local sp = App.area.spline
		if snap.kind == "point" then
			local how = Engine.joinToPoint(sp, ref, snap.ref)
			if how == "closed" then
				selectPt({ cv = sp, i = 1 })
				return "Closed the loop."
			end
			return how and "Joined. The two points now move together." or nil
		end
		local at = snap.at
		Engine.joinToCurve(ref, at.cv, at.seg, at.p, at.n)
		return "Joined into the curve (a junction point was added)."
	end

	-- end of a drawn stroke: add the release point, then thin the stroke to the points that shape it
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
		-- a stroke that ends on a point or a curve joins it (skipping the stroke's own fresh points)
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
		-- what the stroke joins, as the point itself: thinning below renumbers the curve it's drawn on
		local anchor = snap and (snap.kind == "point" and snap.ref.cv.pts[snap.ref.i] or snap.at.cv.pts[snap.at.seg])
		local drop = Engine.thinStroke(d.pts, d.spacing) -- smooth the hand jitter, keep the points that shape it
		for i = #cv.pts, 1, -1 do
			if drop[cv.pts[i]] then
				table.remove(cv.pts, i)
			end
		end
		if snap then -- find it again by what it is, not where it was
			local list = snap.kind == "point" and snap.ref.cv.pts or snap.at.cv.pts
			local i = anchor and table.find(list, anchor)
			if not i then
				snap = nil -- the point it would join was thinned away: the stroke just ends there
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
		else -- a plain click only selects: no undo step, no regeneration
			endRec(rec, true)
			updateHandles()
		end
	end)
	-- a mode change, an area switch or an undo in the middle of a drag: keep (or with `cancel`, drop) what was
	-- dragged or drawn so far, and close its undo recording
	App.resetSplineDrag = function(cancel)
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
			if ref.cv ~= sp and #ref.cv.pts < 2 then -- a branch needs its root and one more point
				table.remove(sp.branches, table.find(sp.branches, ref.cv))
			elseif ref.cv == sp and #sp.pts == 0 and #(sp.branches or {}) > 0 then -- main curve gone: the first branch takes over
				sp.pts = table.remove(sp.branches, 1).pts
			end
		end)
		hoverPt = nil
		if validPt(ref) and ref.i > 1 then -- keep working from the neighbour
			selectPt({ cv = ref.cv, i = ref.i - 1 })
		elseif validPt(ref) then
			selectPt(ref)
		else
			selectPt(nil)
		end
		updateHandles()
	end
	-- sharp corner on/off for a point and its welded twins; a corner has no handles
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

	-- the selected point, for the point panel on the Area page
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
	-- a click on a spline point while the editor is off (or while painting) opens the editor on that point
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
			task.defer(function() -- Studio's own click selected whatever was under the point
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
		elseif name == "delete" then -- X: the point under the mouse, or the selected one
			local ref = hoverPt or (validPt(selPt) and selPt)
			if ref then
				deletePoint(ref)
			else
				App.status("Hover or select a point, then press X to delete it.")
			end
		elseif name == "corner" then -- C: toggle a sharp corner on the selected point
			local ref = hoverPt or (validPt(selPt) and selPt)
			if not ref then
				App.status("Select a point first, then press C for a sharp corner.")
				return
			end
			setSharp(ref, not ref.cv.pts[ref.i].sharp)
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

	-- "New spline" from the area menu: a fresh area that starts as a spline
	App.newSplineFn = function(opts)
		local n = 1
		while Engine.getOut():FindFirstChild("Path " .. n) do
			n += 1
		end
		local rec = beginRec("Smart Scatter: New Spline")
		local a = Engine.createArea("Path " .. n, nil)
		a.folder:SetAttribute("SS_Kind", "Path")
		endRec(rec)
		G.page = "" -- its home tab: where its first step is
		saveG()
		switchArea(a.folder)
		ensureSpline()
		if not (opts and opts.keepMode) then
			App.setMode("Spline")
		end
	end
	App.commitSplineFn = commitSpline
	App.ensureSplineFn = ensureSpline

	-- used by later modules
	App.removeSplineViz = removeSplineViz
end
