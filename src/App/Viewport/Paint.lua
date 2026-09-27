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
	-- what this gesture took away, so its copies go at once (Live off: nothing else rebuilds until Generate)
	local strokeErased = {} -- ground cells erased: [cellKey(cx, cz)] = true
	local strokeWiped = {} -- where the one-object Erase brushed: { x, z, R, square }
	local function cellKey(cx, cz)
		return cx * 1000003 + cz
	end
	App.cellKey = cellKey
	local strokeBox -- { x0, z0, x1, z1 } in studs: the patch this gesture changed, so only it is rebuilt
	local function touched(cx, cz)
		local c = App.area.cell
		local x0, z0, x1, z1 = cx * c, cz * c, (cx + 1) * c, (cz + 1) * c
		local b = strokeBox
		strokeBox = b and { math.min(b[1], x0), math.min(b[2], z0), math.max(b[3], x1), math.max(b[4], z1) } or { x0, z0, x1, z1 }
	end
	local gestureOn = true -- paint (true) or erase (false), fixed when a gesture starts
	local gestureAction -- the one-layer brush: what this gesture does (the mode, or its opposite with Shift)
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
	-- what the one-layer brush does right now: its mode, or the opposite while Shift is held
	local function layerAction()
		return shiftHeld() and App.LAYER_OPPOSITE[App.mode] or App.mode
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
		-- the neon halo: a wider, faint ring just outside the brush's edge
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
		return Engine.cast(ray.Origin, ray.Direction * 5000, App.probeParams)
	end

	-- The size key (B) resizes the brush like Blender's sculpt brushes: the ring stays put and follows the mouse's distance from
	-- its centre; a click, the key again or Enter keeps the size, Esc or a right-click puts it back
	local sizing -- { hit = the ground under the ring, from = the size before }
	local function updateGizmo(hit)
		if App.mode == "Stamp" then -- the stamp shows the model itself (Viewport/Stamp), not a brush
			gizmoFolder()
			for _, k in { "ring", "disc", "halo", "sq", "dot" } do
				if App.gz[k] then
					App.gz[k].Visible = false
				end
			end
		end
		if App.mode == "Spline" or App.mode == "Remove" or App.mode == "Stamp" then
			if App.clearGrid then -- (no grid for these tools)
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
		if App.drawGrid then -- the floor grid round the brush (Viewport/Grid)
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
		App.gz.sq.CFrame = CFrame.new(p) -- the square brush is aligned to the world grid, like the cells it paints
		for _, a in { App.gz.ring, App.gz.disc, App.gz.halo, App.gz.sq, App.gz.dot } do
			a.Color3 = col
		end
		App.gz.dot.CFrame = CFrame.new(p)
		App.gz.anchor.CFrame = CFrame.new(p)
		local surf = Engine.surfaceOf(hit.Instance, hit.Material)
		local what = LAYER_MODES[App.mode] and (App.LAYER_LABEL[layerAction()] .. (App.paintLayer and (" · " .. App.paintLayer.inst.Name) or ""))
			or ((erasing() and "Erase" or "Paint") .. " · " .. (NICE_SURF[surf] or surf))
		if not LAYER_MODES[App.mode] and App.groundNote then -- why the ground under the brush is coloured as it is
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

	-- the object brush: Place puts copies of the object down where it's dragged (Engine/Pins); Erase takes them away
	-- again (along with the object's painting, below). The stroke's patch is rebuilt when it ends.
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
		elseif act == "None" then -- erasing the object: what was placed by hand here goes too
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
							strokeTouched[key] = true -- each stroke changes a cell once
							local v = Engine.paintValue(App.paintLayer, cx, cz)
							local nv = 1 -- (Reset: back to normal)
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
			else
				strokeErased[cellKey(cc[1], cc[2])] = true
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
		table.clear(strokeErased)
		table.clear(strokeWiped)
		strokeRec = beginRec(name)
	end
	-- Taking away never waits for Generate: the copies on ground a gesture erased, or where it erased one object,
	-- go now (stamps stay on erased ground: they stand on their own). Adding waits for Generate, or Live's preview.
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
		-- this gesture's recording and result: a new gesture may start while the regeneration below waits its turn
		local rec, changed, box = strokeRec, strokeChanged, strokeBox
		local erased, wiped = table.clone(strokeErased), table.clone(strokeWiped)
		strokeRec, strokeChanged, strokeBox = nil, false, nil
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
				runGenerate(false, layerPaint or nil, box)
			elseif App.area then
				dropErased(erased, wiped, layerPaint)
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

	-- Remove mode: point at one placed copy, it lights up, a click takes it out. The spot is remembered in the
	-- area, so later generates leave it empty; "Bring back" in the Objects list clears them.
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
		if App.mode == "Off" or App.mode == "Spline" or (App.overViewportUI and App.overViewportUI()) then
			return -- (a click on the viewport's tool strip or bar is theirs, not the ground's)
		end
		if sizing then -- the click that ends F-resizing doesn't paint
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

	-- keys: every action and its key come from the keymap (State), so they follow what the user set in Settings
	local TOOL_KEY = { tool1 = "Brush", tool2 = "Lasso", tool3 = "Box", tool4 = "Polygon", tool5 = "Fill" }
	local lastKeyAt = {}
	local function onKey(name)
		if App.mode == "Off" and name ~= "palette" then
			return
		end
		-- keys arrive through UserInputService and, while the viewport has focus, through the plugin mouse too
		-- (either can miss them depending on focus): the second copy of one press is dropped
		if os.clock() - (lastKeyAt[name] or 0) < 0.08 then
			return
		end
		lastKeyAt[name] = os.clock()
		if name == "palette" then -- the search menu opens anywhere in the viewport while the panel is open, tool or not
			if App.widget.Enabled and App.openPalette then
				App.openPalette()
			end
			return
		end
		if App.mode == "Stamp" and App.stampKey(name) then -- the stamp's own keys (turn, size, model, a random one)
			return
		end
		-- anywhere while working (painting, erasing, drawing a path)
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
		elseif name == "cancel" then -- what's half done goes; with nothing half done, the tool stops
			if App.polyPts or down then
				cancelShape()
			else
				App.setMode("Off")
			end
		end
	end
	-- keys that always do the same as a bound one (the keypad's Enter, Delete), whatever the keymap says
	local ALIASES = { KeypadEnter = "close" } -- (not Delete: in Studio it deletes the selected parts too)
	-- what the plugin mouse reports for a KeyCode (it gives characters, not KeyCodes)
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
	-- the action on a key; a plain letter or digit held with Ctrl stays Studio's (Ctrl+C copies, Ctrl+X cuts)
	local function actionFor(key)
		if App.capturingKey then -- Settings is listening for a new key: it isn't an action
			return nil
		end
		for _, a in App.KEYMAP do
			if App.keyOf(a.id) == key then
				if #(charOf(key) or "") == 1 and ctrlHeld() then
					return nil -- Ctrl with a letter is Studio's (Ctrl+C, Ctrl+D…), not this shortcut
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
	-- Shift turns a brush into its opposite: the ring shows it the moment the key goes down or up
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
		Brush = "Drag to paint. Hold Shift to erase. {size} (or {shrink} {grow}) resizes.",
		Lasso = "Drag an outline. It fills when you let go.",
		Box = "Drag a rectangle. It fills when you let go.",
		Polygon = "Click points. Click the first point, double-click, right-click or press {close} to close.",
		Fill = "Click the ground to fill everything connected of that surface.",
		Spline = "Click to add points. Drag to move, Shift+drag for height, {delete} or right-click deletes, {close} to finish.",
		Place = "Spray: drag to put copies down where you brush. Shift takes hand-placed ones away. {size} resizes.",
		Stamp = "Click to put one copy down, drag to turn it. {turn} turns, {shrink} {grow} size, {model} the model, {shuffle} a random one.",
		More = "Brush where you want more of it. Shift brushes less.",
		Less = "Brush where you want less of it (twice clears it). Shift brushes more.",
		None = "Brush to erase it there, copies placed by hand too. Shift brings it back to normal.",
		Clear = "Brush to bring it back to normal there. Shift erases it.",
		Remove = "Click a placed copy to take it out. It stays gone when you generate again.",
	}
	-- a mode's hint, with the keys it names as they're bound ({size} → F, or whatever the user picked)
	local function modeText(k)
		return (string.gsub(MODE_TEXT[k] or "", "{(%w+)}", App.keyText))
	end
	-- everything that shows the current mode: viewport preview and the panel's tool states
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
	-- stop whatever is in the middle of happening: a stroke, a polygon, a spline drag
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
