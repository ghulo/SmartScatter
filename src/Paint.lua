--[[
	Smart Scatter — Paint: painting the area in the viewport: brush, lasso, box, polygon, smart fill, gizmos, keys.
	Part of Main; loaded in order by the bundle. Shared state and cross-module functions live on App.
]]

return function(App)
	local beginRec, endRec, plugin, Engine, track, G, saveG = App.beginRec, App.endRec, App.plugin, App.Engine, App.track, App.G, App.saveG
	local LAYER_MODES, P, SANS_M, new, corner, stroke, pad = App.LAYER_MODES, App.P, App.SANS_M, App.new, App.corner, App.stroke, App.pad
	local refreshSliders, PAINT_COLOR, refreshParams, probe = App.refreshSliders, App.PAINT_COLOR, App.refreshParams, App.probe
	local NEUTRAL, flushRows, rebuildOverlay, saveArea = App.NEUTRAL, App.flushRows, App.rebuildOverlay, App.saveArea
	local canGenerate, runGenerate, newArea = App.canGenerate, App.runGenerate, App.newArea

	--------------------------------------------------------------------------------
	-- Area painting: brush, lasso, box, polygon and smart fill, with an in-viewport preview
	--------------------------------------------------------------------------------
	local UIS = game:GetService("UserInputService")
	local rawMouse = plugin:GetMouse()
	local mouse = setmetatable({}, {
		__index = function(_, k) -- auto-track mouse connections
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
	local gestureOn = true -- paint (true) or erase (false), fixed when a gesture starts
	local shapePts, boxStart -- lasso points · box corner
	-- App.polyPts: polygon points (Vector3)
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
	local function activeTool()
		return LAYER_MODES[App.mode] and "Brush" or G.tool
	end

	-- viewport preview: brush ring, shape outlines and a small label near the cursor (all adornments, no physics)
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
		if App.mode == "Clear" then
			return NEUTRAL
		end
		if App.mode == "Less" then
			return P.danger
		end
		if LAYER_MODES[App.mode] then
			return PAINT_COLOR
		end
		return erasing() and P.danger or PAINT_COLOR
	end
	-- polyline preview from a pool of thin boxes
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
		return workspace:Raycast(ray.Origin, ray.Direction * 5000, App.probeParams)
	end

	-- F resizes the brush like Blender's sculpt brushes: the ring stays put and follows the mouse's distance from
	-- its centre; a click, F or Enter keeps the size, Esc or a right-click puts it back
	local sizing -- { hit = the ground under the ring, from = the size before }
	local function updateGizmo(hit)
		if App.mode == "Spline" then
			return
		end
		gizmoFolder()
		local tool = activeTool()
		local show = hit ~= nil
		local R = G.radius
		local brush = show and tool == "Brush"
		local col = toolColor()
		App.gz.ring.Visible = brush and G.shape == "Circle"
		App.gz.disc.Visible = App.gz.ring.Visible
		App.gz.sq.Visible = brush and G.shape == "Square"
		App.gz.dot.Visible = show
		App.gz.bb.Enabled = show
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
		App.gz.sq.Size = Vector3.new(R * 2, 0.08, R * 2)
		App.gz.sq.CFrame = CFrame.new(p) -- the square brush is aligned to the world grid, like the cells it paints
		for _, a in { App.gz.ring, App.gz.disc, App.gz.sq, App.gz.dot } do
			a.Color3 = col
		end
		App.gz.dot.CFrame = CFrame.new(p)
		App.gz.anchor.CFrame = CFrame.new(p)
		local surf = Engine.surfaceOf(hit.Instance, hit.Material)
		local what = LAYER_MODES[App.mode] and (App.mode .. (App.paintLayer and (" · " .. App.paintLayer.inst.Name) or ""))
			or ((erasing() and "Erase" or "Paint") .. " · " .. (NICE_SURF[surf] or surf))
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

	-- which cells a paint op may touch: "Paint only on" surface filter
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
		if on and not allow(cx, cz) then -- the filter limits where paint goes, never what can be erased
			return false
		end
		Engine.setCell(App.area, cx, cz, on)
		if on then
			App.area.topY = (App.area.count <= 1) and info.y or math.max(App.area.topY, info.y)
		end
		App.dirtyRows[cz] = true
		strokeChanged = true
		return true
	end

	local function stamp(pos)
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
							strokeTouched[key] = true -- each stroke changes a cell once
							local v = Engine.paintValue(App.paintLayer, cx, cz)
							local nv = 1
							if App.mode == "More" then
								nv = v + 0.5
							elseif App.mode == "Less" then
								nv = v - 0.5
							end
							if nv ~= v then
								Engine.setPaint(App.paintLayer, cx, cz, nv)
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
	-- stamps along the drag so fast strokes never leave gaps
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

	-- smart fill: the connected ground of the surface you click (bounded by roads, paths, water, walls…)
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
				ok = Engine.hasCell(App.area, cx, cz) -- erase: the connected painted patch
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
		-- this gesture's recording and result: a new gesture may start while the regeneration below waits its turn
		local rec, changed = strokeRec, strokeChanged
		strokeRec, strokeChanged = nil, false
		down = false
		lastPos, shapePts, boxStart = nil, nil, nil
		clearPath()
		flushRows()
		-- the undo step holds just the edit (the ground or the layer painting); it's closed before the objects are
		-- rebuilt, and undo rebuilds them the same way
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
				runGenerate(false, layerPaint or nil)
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

	-- "Fill selected parts": the tops of the parts picked in the Explorer (an island, a roof, a platform) join the
	-- area, and scans take them as ground. One undo step, like a stroke.
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
		strokeChanged = true -- the parts are remembered even when their cells were already painted
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
		local t = (y - ray.Origin.Y) / ray.Direction.Y -- where the mouse ray meets the ring's level
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

	mouse.Move:Connect(function()
		if App.mode == "Off" or App.mode == "Spline" then
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
		if sizing then -- the click that ends F-resizing doesn't paint
			endSizing(true)
			return
		end
		if App.clickSplinePoint and App.clickSplinePoint() then -- clicked a spline point: edit it instead of painting
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

	-- keys: [ ] resize the brush · F resizes it with the mouse · Enter closes a polygon · Backspace removes its last point · Esc cancels
	local lastKeyAt = {}
	local function onKey(name)
		if App.mode == "Off" then
			return
		end
		-- keys arrive through UserInputService and, while the viewport has focus, through the plugin mouse too
		-- (either can miss them depending on focus): the second copy of one press is dropped
		if os.clock() - (lastKeyAt[name] or 0) < 0.08 then
			return
		end
		lastKeyAt[name] = os.clock()
		if App.mode == "Spline" then
			App.splineKey(name)
			return
		end
		if sizing and (name == "size" or name == "close" or name == "cancel") then
			endSizing(name ~= "cancel")
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
			cancelShape()
		end
	end
	local KEYS = {
		[Enum.KeyCode.LeftBracket] = "shrink",
		[Enum.KeyCode.RightBracket] = "grow",
		[Enum.KeyCode.Return] = "close",
		[Enum.KeyCode.KeypadEnter] = "close",
		[Enum.KeyCode.Backspace] = "back",
		[Enum.KeyCode.Delete] = "back",
		[Enum.KeyCode.Escape] = "cancel",
		[Enum.KeyCode.C] = "corner",
		[Enum.KeyCode.F] = "size",
		[Enum.KeyCode.X] = "delete",
	}
	local function ctrlHeld()
		return UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl)
	end
	track(UIS.InputBegan:Connect(function(input)
		local name = KEYS[input.KeyCode]
		if name and not UIS:GetFocusedTextBox() and not ((name == "corner" or name == "delete") and ctrlHeld()) then -- Ctrl+C, Ctrl+X stay copy and cut
			onKey(name)
		end
	end))
	mouse.KeyDown:Connect(function(k)
		local name = (k == "[" and "shrink")
			or (k == "]" and "grow")
			or (k == "\r" and "close")
			or (k == "\b" and "back")
			or (k == "\27" and "cancel")
			or (k == "c" and not ctrlHeld() and "corner")
			or (k == "f" and "size")
			or (k == "x" and not ctrlHeld() and "delete")
			or nil
		if name then
			onKey(name)
		end
	end)
	-- right-click: only a quick click without dragging counts; holding the button to orbit the camera does nothing
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
		Brush = "Drag to paint. Hold Shift to erase. F (or [ ]) resizes.",
		Lasso = "Drag an outline. It fills when you let go.",
		Box = "Drag a rectangle. It fills when you let go.",
		Polygon = "Click points. Click the first point, double-click, right-click or press Enter to close.",
		Fill = "Click the ground to fill everything connected of that surface.",
		Spline = "Click to add points. Drag to move, Shift+drag for height, X or right-click deletes, Enter to finish.",
		More = "Brush where you want more of this layer.",
		Less = "Brush where you want less. Twice removes it there.",
		Clear = "Brush to undo your painting for this layer.",
	}
	-- everything that shows the current mode: viewport preview and the panel's tool states
	local function showMode()
		rebuildOverlay()
		if App.drawSpline then
			App.drawSpline()
		end
		for _, k in { "refreshMode", "refreshLayerBrush", "refreshSplineBtn", "refreshPoint" } do
			if App.ui[k] then
				App.ui[k]()
			end
		end
	end
	-- stop whatever is in the middle of happening: a stroke, a polygon, a spline drag
	local function stopGestures()
		endSizing(false)
		endStroke()
		App.polyPts = nil
		clearPath()
		if App.resetSplineDrag then
			App.resetSplineDrag()
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
		stopGestures()
		if m ~= "Off" and not App.area then -- painting needs an area, drawing a path needs a path
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
			local t = MODE_TEXT[(LAYER_MODES[App.mode] or App.mode == "Spline") and App.mode or G.tool]
			App.status((App.mode == "Erase" and not LAYER_MODES[App.mode]) and ("Erasing. " .. t) or t)
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
		if App.mode ~= "Paint" and App.mode ~= "Erase" then
			App.setMode("Paint")
		else
			App.status(MODE_TEXT[t])
			updateGizmo(mouseHit())
		end
	end

	-- another tool took over the viewport (Move, Select…): our mode ends too
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

	-- used by later modules
	App.rawMouse = rawMouse
	App.mouse = mouse
	App.shiftHeld = shiftHeld
	App.gizmoFolder = gizmoFolder
	App.removeGizmo = removeGizmo
	App.setLabel = setLabel
	App.mouseHit = mouseHit
end
