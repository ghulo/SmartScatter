--[[
	Smart Scatter regression suite. Paste into Studio's command bar (or run through the MCP) with the live engine in
	ServerStorage.SmartScatterSource. It builds its own little world far from the user's map, runs every placement
	path against it, checks the results against fixed limits, and removes everything it made.
	Returns one line per check: PASS/FAIL, the numbers, and a final summary.
]]
local SRC = game:GetService("ServerStorage"):FindFirstChild("SmartScatterSource")
-- a fresh engine: a module tree is required from a copy (require caches by instance; the live copy isn't
-- archivable, so it's copied by hand), a flattened one (older loaders) is compiled from its source
local function fresh(m)
	local c = Instance.new(m.ClassName)
	c.Name = m.Name
	if m:IsA("ModuleScript") then
		c.Source = m.Source
	end
	for _, k in m:GetChildren() do
		fresh(k).Parent = c
	end
	return c
end
local E = #SRC.Engine:GetChildren() > 0 and require(fresh(SRC.Engine)) or loadstring(SRC.Engine.Source)()
local O = Vector3.new(6000, 0, 6000) -- the test world's origin, far away from anything real
local results, fails = {}, 0
local function check(name, ok, detail)
	if not ok then
		fails += 1
	end
	table.insert(results, (ok and "PASS " or "FAIL ") .. name .. "  |  " .. detail)
end

-- ── the test world ───────────────────────────────────────────────────────────
local world = Instance.new("Folder")
world.Name = "SS_TestWorld"
world.Parent = workspace
local function part(props)
	local p = Instance.new(props.class or "Part")
	props.class = nil
	p.Anchored = true
	for k, v in props do
		p[k] = v
	end
	p.Parent = props.Parent or world
	return p
end
part({ Name = "Ground", Size = Vector3.new(600, 2, 600), CFrame = CFrame.new(O + Vector3.new(0, -1, 0)), Material = Enum.Material.Grass })
part({ Name = "Road", Size = Vector3.new(20, 0.4, 300), CFrame = CFrame.new(O + Vector3.new(-120, 0.2, 0)), Material = Enum.Material.Asphalt })
part({ Name = "House", Size = Vector3.new(24, 14, 20), CFrame = CFrame.new(O + Vector3.new(-60, 7, -80)), Material = Enum.Material.Brick })
part({ Name = "Pond", Size = Vector3.new(40, 0.3, 40), CFrame = CFrame.new(O + Vector3.new(-60, 0.15, 80)), Material = Enum.Material.Water })
-- a terrain mound (about 43° at its foot, flatter on top, 30 studs high) and, beyond it, a 16-stud rock wall: a real cliff
workspace.Terrain:FillBall(O + Vector3.new(120, -80, 0), 110, Enum.Material.Grass)
workspace.Terrain:FillBlock(CFrame.new(O + Vector3.new(232, 8, 0)), Vector3.new(12, 16, 60), Enum.Material.Rock)
-- let the terrain settle before anything raycasts it (a freshly opened place can take a few frames)
for _ = 1, 120 do
	task.wait()
	local h = workspace:Raycast(O + Vector3.new(120, 400, 0), Vector3.new(0, -800, 0))
	if h and h.Position.Y > 20 then
		break
	end
end

-- ── test models (kept in the folder, not placed in the scan area) ────────────
local assets = Instance.new("Folder")
assets.Name = "Assets"
assets.Parent = world
local function model(name, parts)
	local m = Instance.new("Model")
	m.Name = name
	for i, pp in parts do
		local p = part(pp)
		p.Parent = m
		if i == 1 then
			m.PrimaryPart = p
		end
	end
	m.Parent = assets
	m:PivotTo(CFrame.new(O + Vector3.new(0, 300, 0))) -- templates float high up, like real template folders do
	return m
end
local tree = model("TestTree", {
	{ Name = "Trunk", Size = Vector3.new(1.2, 8, 1.2), CFrame = CFrame.new(0, 4, 0) },
	{ Name = "Leaves", Size = Vector3.new(8, 8, 8), CFrame = CFrame.new(0, 11, 0), Shape = Enum.PartType.Ball, CanCollide = false },
})
local rock = model("TestRock", { { Name = "Stone", Size = Vector3.new(5, 3, 6), CFrame = CFrame.new(0, 1.5, 0), Material = Enum.Material.Slate } })
local fence = model("TestFence", { -- a post on one end only, pivot on the post (the case that caused gaps)
	{ Name = "Base", Size = Vector3.new(0.5, 3.2, 0.5), CFrame = CFrame.new(-3.75, 1.6, 0) },
	{ Name = "Rail", Size = Vector3.new(8, 0.4, 0.3), CFrame = CFrame.new(0, 1.2, 0) },
	{ Name = "Rail", Size = Vector3.new(8, 0.4, 0.3), CFrame = CFrame.new(0, 2.5, 0) },
})
local templates = { tree, rock, fence }

-- ── helpers ──────────────────────────────────────────────────────────────────
local rpG = E.rayParams(templates)
local function ground(p)
	return workspace:Raycast(Vector3.new(p.X, p.Y + 400, p.Z), Vector3.new(0, -800, 0), rpG)
end
-- clearance of a model: the smallest gap between the 4 lowest corners of its lowest part and the ground under them
local function clearance(m)
	local low, lp = math.huge, nil
	for _, p in m:GetDescendants() do
		if p:IsA("BasePart") and p.Transparency < 1 then
			local cf, s = p.CFrame, p.Size / 2
			for sx = -1, 1, 2 do
				for sy = -1, 1, 2 do
					for sz = -1, 1, 2 do
						local w = cf * Vector3.new(s.X * sx, s.Y * sy, s.Z * sz)
						if w.Y < low then
							low, lp = w.Y, p
						end
					end
				end
			end
		end
	end
	if not lp then
		return 0
	end
	local cf, s, cs = lp.CFrame, lp.Size / 2, {}
	for sx = -1, 1, 2 do
		for sy = -1, 1, 2 do
			for sz = -1, 1, 2 do
				table.insert(cs, cf * Vector3.new(s.X * sx, s.Y * sy, s.Z * sz))
			end
		end
	end
	table.sort(cs, function(a, b)
		return a.Y < b.Y
	end)
	local g = math.huge
	for i = 1, 4 do
		local h = ground(cs[i])
		if h then
			g = math.min(g, cs[i].Y - h.Position.Y)
		end
	end
	return g
end
local function placed(folder)
	local t = {}
	for _, m in folder:GetDescendants() do
		if m:IsA("Model") and m:GetAttribute("SS_Type") then
			table.insert(t, m)
		end
	end
	return t
end
local made = {} -- every area a test made (removed at the end)
local function newArea(name, layers)
	local a = E.createArea(name, {})
	a.layers = layers
	a.seed = 4242 -- the same layout every run, so a result never depends on luck
	return a
end
-- clears what the earlier tests placed: other areas' copies count for spacing, so a test that needs open ground
-- starts from it
local function isolate()
	for _, other in made do
		E.clearOutputs(other)
	end
end
local function paintRect(a, x0, z0, x1, z1)
	E.fillPolygon(a, { { O.X + x0, O.Z + z0 }, { O.X + x1, O.Z + z0 }, { O.X + x1, O.Z + z1 }, { O.X + x0, O.Z + z1 } }, true)
end
local function splineAlong(xs, zf)
	local pts = {}
	for _, x in xs do
		local h = ground(O + Vector3.new(x, 0, zf(x)))
		table.insert(pts, { p = h.Position, n = h.Normal })
	end
	return pts
end
local function run(a)
	table.insert(made, a)
	local t0 = os.clock()
	local an = E.analyze(a, templates)
	local t1 = os.clock()
	local counts, total = E.generate(a, an, 1, templates, {})
	return total or 0, (t1 - t0) * 1000, (os.clock() - t1) * 1000, an
end

local ok, err = pcall(function()
	local top = ground(O + Vector3.new(120, 0, 0))
	check("test world built", top and top.Position.Y > 20, "hill top at " .. (top and string.format("%.1f", top.Position.Y) or "nothing"))
	-- 1. scatter over flat ground, a road, a house, a pond and the hill
	do
		local a = newArea("SS_Test_Scatter", { E.makeLayer(tree, "Tree"), E.makeLayer(rock, "Rock") })
		paintRect(a, -200, -150, 200, 150)
		local total, scanMs, placeMs, an = run(a)
		local float, worst, onRoad, inWater, onRoof, outside = 0, 0, 0, 0, 0, 0
		local bad = {}
		local nearWater, nearRoad, nearHouse = math.huge, math.huge, math.huge
		for _, m in placed(a.folder) do
			local c = clearance(m)
			if c > 0.3 then
				float += 1
				worst = math.max(worst, c)
			end
			-- classify the spot the model stands on (its base point), not its pivot, which leans with the model's tilt
			local p = Vector3.new(m:GetAttribute("SS_X"), 0, m:GetAttribute("SS_Z"))
			local gh = ground(p) or {}
			local cls = E.surfaceOf(gh.Instance or workspace.Terrain, gh.Material)
			if cls == "Road" then
				onRoad += 1
			elseif cls == "Water" then
				inWater += 1
			elseif cls == "Building" then
				onRoof += 1
			end
			if cls == "Road" or cls == "Water" or cls == "Building" then
				table.insert(bad, string.format("%s %s(%.1f,%.1f)", m.Name, cls, p.X - O.X, p.Z - O.Z))
			end
			if not E.hasCell(a, math.floor(m:GetAttribute("SS_X") / a.cell), math.floor(m:GetAttribute("SS_Z") / a.cell)) then
				outside += 1
			end
			if m.Name == tree.Name then
				local lx, lz = p.X - O.X, p.Z - O.Z
				local function rectDist(x0, z0, x1, z1)
					local dx, dz = math.max(x0 - lx, 0, lx - x1), math.max(z0 - lz, 0, lz - z1)
					return math.sqrt(dx * dx + dz * dz)
				end
				nearWater = math.min(nearWater, rectDist(-80, 60, -40, 100))
				nearRoad = math.min(nearRoad, rectDist(-130, -150, -110, 150))
				nearHouse = math.min(nearHouse, rectDist(-72, -90, -48, -70))
			end
		end
		-- trees default to keeping 3 studs from water, 4 from roads, 6 from buildings (plus their trunk)
		check(
			"trees keep their distance from water, roads, houses",
			nearWater >= 3 and nearRoad >= 4 and nearHouse >= 6,
			string.format("closest: water %.1f, road %.1f, house %.1f", nearWater, nearRoad, nearHouse)
		)
		check("scatter places things", total > 150, total .. " placed")
		check("scatter: nothing floats", float == 0, float .. " floating (worst " .. string.format("%.1f", worst) .. ")")
		check(
			"scatter: stays off roads, water, roofs",
			onRoad + inWater + onRoof == 0,
			string.format("road %d, water %d, roof %d ", onRoad, inWater, onRoof) .. table.concat(bad, " ", 1, math.min(#bad, 6))
		)
		check("scatter: stays inside the paint", outside == 0, outside .. " outside")
		local cls = {}
		for _, c in an.cls do
			cls[c] = (cls[c] or 0) + 1
		end
		check(
			"scan recognises road, water, building",
			(cls.Road or 0) > 0 and (cls.Water or 0) > 0 and (cls.Building or 0) > 0,
			string.format("road %d, water %d, building %d cells", cls.Road or 0, cls.Water or 0, cls.Building or 0)
		)
		check("scan and placement are quick", scanMs < 400 and placeMs < 600, string.format("scan %.0f ms, place %.0f ms", scanMs, placeMs))
	end

	-- 2. a fence over the hill and down its steep face
	do
		local l = E.makeLayer(fence) -- a name with "fence" becomes an end-to-end line
		l.s.follow = "Spline"
		local a = newArea("SS_Test_Fence", { l })
		a.spline = {
			pts = splineAlong({ 30, 60, 90, 120, 150, 180, 210, 240, 270 }, function()
				return 0
			end),
			closed = false,
			width = 0,
			snap = true,
			branches = {},
		}
		local total = run(a)
		local off, lean, gapEnds = 0, 0, 0
		local ends, where, loose = {}, {}, {}
		for _, m in placed(a.folder) do
			local b = m:FindFirstChild("Base")
			if b then
				lean = math.max(lean, math.deg(math.acos(math.clamp(b.CFrame.UpVector.Y, -1, 1))))
				local foot = b.CFrame * Vector3.new(0, -b.Size.Y / 2, 0)
				local g = ground(foot)
				if g and math.abs(foot.Y - g.Position.Y) > 0.6 then
					off += 1
					if #where < 5 then
						table.insert(where, string.format("x%.0f %+.1f", foot.X - O.X, foot.Y - g.Position.Y))
					end
				end
			end
			local r = m:FindFirstChild("Rail")
			if r then
				for _, sx in { 1, -1 } do
					local e = r.CFrame * Vector3.new(sx * r.Size.X / 2, 0, 0)
					table.insert(ends, { m, e })
				end
			end
		end
		for _, e in ends do -- every rail end meets another piece, except the two ends of the run and cliff openings
			local best = math.huge
			for _, o in ends do
				if o[1] ~= e[1] then
					best = math.min(best, (o[2] - e[2]).Magnitude)
				end
			end
			if best > 0.6 then
				gapEnds += 1
				if #loose < 6 then
					table.insert(loose, string.format("x%.0f(%.1f)", e[2].X - O.X, best))
				end
			end
		end
		check("fence places pieces", total > 15, total .. " pieces")
		check("fence: posts stand upright", lean < 2, string.format("max lean %.1f°", lean))
		check("fence: posts on the ground", off <= 1, off .. " posts more than 0.6 off the ground " .. table.concat(where, " "))
		check(
			"fence: joints meet",
			gapEnds <= 6, -- the two ends of the run, plus an opening at the foot and the top of the wall
			gapEnds .. " loose rail ends (run ends + cliff opening allowed) " .. table.concat(loose, " ")
		)
	end

	-- 3. trees along both sides of a winding path over the hill (the first test's forest covers this ground)
	do
		isolate()
		local l = E.makeLayer(tree, "Tree")
		l.s.place, l.s.follow, l.s.side, l.s.offset, l.s.interval, l.s.jitter = "Along", "Spline", "Both", 12, 10, 0
		local a = newArea("SS_Test_Along", { l })
		a.spline = {
			pts = splineAlong({ 30, 55, 80, 105, 130, 155, 180, 205 }, function(x)
				return math.sin(x / 18) * 25
			end),
			closed = false,
			width = 0,
			snap = true,
			branches = {},
		}
		local total = run(a)
		local float, where = 0, {}
		for _, m in placed(a.folder) do
			local c = clearance(m)
			if c > 0.3 then
				float += 1
				local p = m:GetPivot().Position
				if #where < 5 then
					table.insert(where, string.format("(%.0f,%.0f) %.1f", p.X - O.X, p.Z - O.Z, c))
				end
			end
		end
		check("along a spline: places", total > 20, total .. " placed")
		check("along a spline: nothing floats", float == 0, float .. " floating " .. table.concat(where, " "))
	end

	-- 4. roads: straight over the hill, winding over it, and a T-junction on flat ground
	for _, case in
		{
			{
				"straight road over hill",
				{ 30, 90, 150, 210 },
				function()
					return 20
				end,
				nil,
			},
			{
				"winding road over hill",
				{ 30, 50, 70, 90, 110, 130, 150, 170, 190, 210 },
				function(x)
					return 20 + math.sin(x / 18) * 25
				end,
				nil,
			},
			{
				"T-junction road",
				{ -40, 0, 40 },
				function()
					return -120
				end,
				true,
			},
		}
	do
		local a = newArea("SS_Test_Road", {})
		local pts = splineAlong(case[2], case[3])
		a.spline = { pts = pts, closed = false, width = 16, snap = true, branches = {}, surface = { on = true, style = "Asphalt", thick = 1 } }
		if case[4] then -- a branch from the middle point going sideways
			local root = pts[2]
			local h = ground(root.p + Vector3.new(0, 0, 50))
			table.insert(a.spline.branches, { pts = { { p = root.p, n = root.n }, { p = h.Position, n = h.Normal } }, closed = false })
		end
		local t0 = os.clock()
		local f, n = E.buildSurface(a, rpG)
		local ms = (os.clock() - t0) * 1000
		f.Parent = world
		local inc = RaycastParams.new()
		inc.FilterType = Enum.RaycastFilterType.Include
		inc.FilterDescendantsInstances = { f }
		local exc = E.rayParams(templates)
		local ex = exc.FilterDescendantsInstances
		table.insert(ex, f)
		exc.FilterDescendantsInstances = ex
		local ds, holes, overlaps, where = {}, 0, 0, {}
		for _, cv in E.splineCurves(a.spline) do
			local P = E.splineCurve(cv, 1)
			for k = 3, #P - 2 do
				local tt = P[k + 2] - P[k - 2]
				tt = Vector3.new(tt.X, 0, tt.Z).Unit
				local r = tt:Cross(Vector3.yAxis)
				for _, o in { -6.5, -3, 0, 3, 6.5 } do
					local q = P[k] + r * o + Vector3.new(0.013, 0, 0.007)
					local top = workspace:Raycast(Vector3.new(q.X, q.Y + 400, q.Z), Vector3.new(0, -800, 0), inc)
					local g = workspace:Raycast(Vector3.new(q.X, q.Y + 400, q.Z), Vector3.new(0, -800, 0), exc)
					if not top then
						holes += 1
					elseif g and g.Normal.Y >= 0.6 then
						local d = top.Position.Y - g.Position.Y
						table.insert(ds, d)
						if math.abs(d) > 0.5 and #where < 5 then
							table.insert(where, string.format("(%.0f,%.0f)%+.1f", q.X - O.X, q.Z - O.Z, d))
						end
					end
					-- two road surfaces stacked at one spot (a junction drawn twice) would flicker
					if top then
						local inc2 = RaycastParams.new()
						inc2.FilterType = Enum.RaycastFilterType.Include
						inc2.FilterDescendantsInstances = { f }
						local under = workspace:Raycast(top.Position - Vector3.new(0, 0.01, 0), Vector3.new(0, -0.3, 0), inc2)
						if
							under
							and math.abs(under.Position.Y - top.Position.Y) < 0.2
							and under.Instance ~= top.Instance
							and under.Normal.Y > 0.9
						then
							overlaps += 1
						end
					end
				end
			end
		end
		table.sort(ds)
		local off = 0
		for _, d in ds do
			if math.abs(d) > 0.5 then
				off += 1
			end
		end
		local share = #ds > 0 and off / #ds or 1
		check(case[1] .. ": no holes", holes <= 2, holes .. " holes, " .. n .. " parts, " .. string.format("%.0f ms", ms))
		check(
			case[1] .. ": sits on the ground",
			share < 0.08,
			string.format("%.1f%% off by >0.5 (median %.2f) %s", share * 100, ds[math.max(1, #ds // 2)] or 0, table.concat(where, " "))
		)
		if case[4] then
			check(case[1] .. ": no stacked surfaces", overlaps == 0, overlaps .. " spots with two surfaces")
		end
		f:Destroy()
		table.insert(made, a)
	end

	-- 5. fitting maths: even pieces on straights, a joint on every corner and junction
	do
		local function poly(P)
			local acc = { 0 }
			for k = 2, #P do
				acc[k] = acc[k - 1] + (P[k] - P[k - 1]).Magnitude
			end
			return acc[#P],
				function(d)
					d = math.clamp(d, 0, acc[#P])
					local k = 2
					while k < #P and acc[k] < d do
						k += 1
					end
					return P[k - 1]:Lerp(P[k], (d - acc[k - 1]) / math.max(acc[k] - acc[k - 1], 1e-6))
				end
		end
		local P = {}
		for k = 0, 200 do
			table.insert(P, Vector3.new(k * 0.5, 0, 0))
		end
		for k = 1, 200 do
			table.insert(P, Vector3.new(100, 0, k * 0.5))
		end
		local total, at = poly(P)
		local pcs = E.fitPieces(total, at, 19, { 50 })
		local onCorner, onJoint = false, false
		for _, pc in pcs do
			if math.abs(pc[1] - 100) < 0.3 then
				onCorner = true
			end
			if math.abs(pc[1] - 50) < 0.01 then
				onJoint = true
			end
		end
		check("fit: joint on the corner", onCorner, #pcs .. " pieces")
		check("fit: joint on a junction", onJoint, "junction at 50")
	end

	-- 6. a layer whose model moves or disappears: found again, or kept (with its settings) until relinked
	do
		local lonely = model("TestLonelyBush", { { Name = "Leaf", Size = Vector3.new(2, 2, 2), CFrame = CFrame.new(0, 1, 0) } })
		local l = E.makeLayer(lonely, "Bush")
		l.s.density = 1.7 -- a setting that must survive
		local a = newArea("SS_Test_Lost", { l })
		table.insert(made, a)
		E.saveArea(a)
		local elsewhere = Instance.new("Folder")
		elsewhere.Name = "MovedAssets"
		elsewhere.Parent = world
		lonely.Parent = elsewhere -- moved
		local b = E.loadArea(a.folder)
		check("moved model is found again", #b.layers == 1 and b.relinked == 1, #b.layers .. " layers, " .. tostring(b.relinked) .. " relinked")
		lonely:Destroy() -- gone
		local c = E.loadArea(a.folder)
		E.saveArea(c)
		local d = E.loadArea(a.folder)
		check("missing model keeps its layer", #d.layers == 0 and #d.lost == 1, #d.layers .. " layers, " .. #d.lost .. " kept aside")
		local replacement = model("TestOtherBush", { { Name = "Leaf", Size = Vector3.new(3, 3, 3), CFrame = CFrame.new(0, 1.5, 0) } })
		local okRelink = E.relinkLost(d, 1, replacement)
		check(
			"relinking brings it back with its settings",
			okRelink and #d.layers == 1 and d.layers[1].s.density == 1.7,
			tostring(okRelink) .. ", density " .. tostring(d.layers[1] and d.layers[1].s.density)
		)
	end

	-- 7. spline editing: close a loop, weld two points, make a T-junction, thin a freehand stroke
	do
		local function pt(x, z)
			local h = ground(O + Vector3.new(x, 0, z))
			return { p = h.Position, n = h.Normal }
		end
		-- closing: the last point dropped on the first
		local sp = { pts = { pt(-60, 150), pt(-20, 150), pt(-20, 190), pt(-60, 190), pt(-60, 151) }, closed = false, branches = {} }
		local r = E.joinToPoint(sp, { cv = sp, i = 5 }, { cv = sp, i = 1 })
		check("dropping the end on the start closes the loop", r == "closed" and sp.closed and #sp.pts == 4, r .. ", " .. #sp.pts .. " points")
		-- welding: a branch end dropped on a point of the main curve
		local main = { pts = { pt(0, 150), pt(40, 150), pt(80, 150) }, closed = false, branches = {} }
		local br = { pts = { pt(40, 190), pt(38, 152) }, closed = false }
		table.insert(main.branches, br)
		E.joinToPoint(main, { cv = br, i = 2 }, { cv = main, i = 2 })
		check("dropping a point on a point welds them", (br.pts[2].p - main.pts[2].p).Magnitude < 1e-6, "shared position")
		-- T-junction: a branch end dropped on the middle of a segment adds a shared point there
		local main2 = { pts = { pt(0, 230), pt(80, 230) }, closed = false, branches = {} }
		local br2 = { pts = { pt(40, 270), pt(40, 232) }, closed = false }
		table.insert(main2.branches, br2)
		local jp = pt(40, 230)
		E.joinToCurve({ cv = br2, i = 2 }, main2, 1, jp.p, jp.n)
		check(
			"dropping an end on a curve makes a T-junction",
			#main2.pts == 3 and (main2.pts[2].p - br2.pts[2].p).Magnitude < 1e-6,
			#main2.pts .. " points on the main curve"
		)
		-- that junction becomes a fence joint on the main curve
		local l = E.makeLayer(fence)
		l.s.follow = "Spline"
		local a = newArea("SS_Test_Edit", { l })
		a.spline = main2
		main2.width, main2.snap = 0, true
		run(a)
		local J, nearJ = main2.pts[2].p, math.huge
		for _, m in placed(a.folder) do
			local b = m:FindFirstChild("Base")
			if b then
				nearJ = math.min(nearJ, (Vector3.new(b.Position.X, 0, b.Position.Z) - Vector3.new(J.X, 0, J.Z)).Magnitude)
			end
		end
		check("the fence has a joint at the junction", nearJ < 1, string.format("nearest post %.2f studs from it", nearJ))
		-- a shaky straight stroke thins to a couple of points; an L keeps its corner
		local stroke = {}
		for k = 0, 30 do
			table.insert(stroke, { p = O + Vector3.new(k * 3, 0, (k % 2 == 0 and 0.4 or -0.4)) })
		end
		local drop = E.thinStroke(stroke, 3)
		local kept = 0
		for _, q in stroke do
			if not drop[q] then
				kept += 1
			end
		end
		check("a shaky straight stroke thins down", kept <= 3, kept .. " of 31 points kept")
		local L = {}
		for k = 0, 15 do
			table.insert(L, { p = O + Vector3.new(k * 3, 0, 0) })
		end
		for k = 1, 15 do
			table.insert(L, { p = O + Vector3.new(45, 0, k * 3) })
		end
		local dropL = E.thinStroke(L, 3)
		local corner = false
		for _, q in L do
			if not dropL[q] and (q.p - (O + Vector3.new(45, 0, 0))).Magnitude < 4 then
				corner = true
			end
		end
		check("a drawn corner keeps its corner point", corner, "corner kept: " .. tostring(corner))
		-- a closed loop as a road: no holes all the way round
		local loop = {
			pts = { pt(-150, 150), pt(-100, 150), pt(-100, 200), pt(-150, 200) },
			closed = true,
			branches = {},
			width = 12,
			snap = true,
			surface = { on = true, style = "Asphalt", thick = 1 },
		}
		local ra = newArea("SS_Test_Edit", {})
		ra.spline = loop
		table.insert(made, ra)
		local f = E.buildSurface(ra, rpG)
		f.Parent = world
		local inc = RaycastParams.new()
		inc.FilterType = Enum.RaycastFilterType.Include
		inc.FilterDescendantsInstances = { f }
		local holes, probes = 0, 0
		local P = E.splineCurve(loop, 1)
		for k = 1, #P - 1 do
			probes += 1
			local q = P[k] + Vector3.new(0.013, 0, 0.007)
			if not workspace:Raycast(Vector3.new(q.X, q.Y + 50, q.Z), Vector3.new(0, -100, 0), inc) then
				holes += 1
			end
		end
		f:Destroy()
		check("a closed-loop road has no holes", holes == 0, holes .. " of " .. probes .. " centre probes missed")
	end

	-- 8. lines of pieces: flat tiles resize to meet, the chosen axis runs down the line, a lantern's front faces the curve
	do
		local slab = model("TestSlab", {
			{ Name = "Tile", Size = Vector3.new(18, 0.4, 15.3), CFrame = CFrame.new(0, 0.2, 0), Material = Enum.Material.Concrete },
		})
		local lantern = model("TestLantern", {
			{ Name = "Body", Size = Vector3.new(1, 1.6, 1), CFrame = CFrame.new(0, 0.8, 0) },
			{ Name = "Glass", Size = Vector3.new(0.2, 0.8, 0.6), CFrame = CFrame.new(0.6, 0.8, 0), Material = Enum.Material.Neon },
		})
		table.insert(templates, slab)
		table.insert(templates, lantern)
		local ls = E.makeLayer(slab)
		check("a flat slab is not taken for a building", ls.type ~= "Building", "type " .. ls.type)
		local seg = E.looksLikeSegment(ls) and E.looksLikeSegment(E.makeLayer(fence))
		local notSeg = not E.looksLikeSegment(E.makeLayer(lantern)) and not E.looksLikeSegment(E.makeLayer(tree))
		check("tiles and panels join up, lanterns and trees keep a gap", seg and notSeg, tostring(seg) .. ", " .. tostring(notSeg))
		E.smartLine(ls, true)
		check("a tile on a spline lines up end to end by itself", ls.s.fit and ls.s.follow == "Spline" and ls.s.place == "Along", tostring(ls.s.fit))
		-- tiles along a straight line with the 15.3 side (Z) down the line: every joint closes
		local function line(z)
			return splineAlong({ -100, -60, -20, 20, 60 }, function()
				return z
			end)
		end
		ls.s.front = "+Z"
		ls.s.scaleMin, ls.s.scaleMax = 1, 1
		local a = newArea("SS_Test_Axis", { ls })
		a.spline = { pts = line(-220), closed = false, width = 0, snap = true, branches = {} }
		run(a)
		local spans, badAxis = {}, 0
		local topLo, topHi = math.huge, -math.huge
		for _, m in placed(a.folder) do
			local t = m:FindFirstChild("Tile")
			if t then
				local top = t.Position.Y + t.Size.Y / 2
				topLo, topHi = math.min(topLo, top), math.max(topHi, top)
				if math.abs(t.CFrame.LookVector.X) < 0.99 then
					badAxis += 1
				end
				table.insert(spans, { t.Position.X - t.Size.Z / 2, t.Position.X + t.Size.Z / 2 })
			end
		end
		table.sort(spans, function(p, q)
			return p[1] < q[1]
		end)
		local worstGap, worstLap = 0, 0
		for k = 2, #spans do
			worstGap = math.max(worstGap, spans[k][1] - spans[k - 1][2])
			worstLap = math.max(worstLap, spans[k - 1][2] - spans[k][1])
		end
		local cover = #spans > 0 and (spans[#spans][2] - spans[1][1]) or 0
		check(
			"tiles run on the chosen axis and butt exactly",
			#spans >= 9 and badAxis == 0 and worstGap < 0.05 and worstLap < 0.03 and cover > 158,
			string.format("%d tiles, %d off-axis, worst gap %.2f, worst overlap %.2f, cover %.1f of 160", #spans, badAxis, worstGap, worstLap, cover)
		)
		check("tiles on a straight sit flush", topHi - topLo < 0.005, string.format("top faces differ by %.3f", topHi - topLo))
		-- the same tiles (Auto: the 18 side runs along) round an S-bend: both edges covered, no wedge gaps
		local lc = E.makeLayer(slab)
		E.smartLine(lc, true)
		lc.s.scaleMin, lc.s.scaleMax = 1, 1
		local c = newArea("SS_Test_Axis", { lc })
		c.spline = {
			pts = splineAlong({ -260, -230, -200, -170, -140 }, function(x)
				return -210 + math.sin((x + 260) / 30) * 28 -- bends of ~32 studs radius, twice the tile's width
			end),
			closed = false,
			width = 0,
			snap = true,
			branches = {},
		}
		run(c)
		local inc = RaycastParams.new()
		inc.FilterType = Enum.RaycastFilterType.Include
		inc.FilterDescendantsInstances = { c.folder }
		local P = E.splineCurve(c.spline, 1)
		local miss, probes, where, stacked = 0, 0, {}, 0
		local hw = 15.3 / 2 - 0.6 -- just inside each edge
		for k = 4, #P - 3 do
			local t = P[k + 1] - P[k - 1]
			local lat = Vector3.new(-t.Z, 0, t.X).Unit
			for _, o in { -hw, -hw / 2, 0, hw / 2 } do -- two faces in one spot flicker: none anywhere across the path
				local q = P[k] + lat * o
				local top = workspace:Raycast(Vector3.new(q.X, q.Y + 30, q.Z), Vector3.new(0, -60, 0), inc)
				if top then
					local under = workspace:Raycast(top.Position - Vector3.new(0, 0.005, 0), Vector3.new(0, -0.1, 0), inc)
					if under and under.Instance ~= top.Instance and under.Normal.Y > 0.9 then
						stacked += 1
					end
				end
			end
			for sgn = -1, 1, 2 do
				local q = P[k] + lat * hw * sgn
				probes += 1
				if not workspace:Raycast(Vector3.new(q.X, q.Y + 30, q.Z), Vector3.new(0, -60, 0), inc) then
					miss += 1
					if #where < 4 then
						table.insert(where, string.format("(%.0f,%.0f)", q.X - O.X, q.Z - O.Z))
					end
				end
			end
		end
		check(
			"tiles round a bend leave no gaps at the edges",
			miss == 0,
			miss .. " of " .. probes .. " edge probes fell through " .. table.concat(where, " ")
		)
		check("tiles round a bend never overlap (no flicker)", stacked == 0, stacked .. " spots with two tile surfaces")
		-- lanterns beside the curve with their glass (+X) turned toward it
		local ll = E.makeLayer(lantern)
		ll.s.place, ll.s.follow, ll.s.side, ll.s.offset = "Along", "Spline", "Both", 5
		ll.s.facing, ll.s.front, ll.s.interval, ll.s.tilt, ll.s.jitter = "Face it", "+X", 20, 0, 0
		local b = newArea("SS_Test_Axis", { ll })
		b.spline = { pts = line(-260), closed = false, width = 0, snap = true, branches = {} }
		run(b)
		local n, wrong = 0, 0
		for _, m in placed(b.folder) do
			local g = m:FindFirstChild("Glass")
			if g then
				n += 1
				local toCurve = Vector3.new(0, 0, (O.Z - 260) - g.Position.Z)
				if toCurve.Magnitude < 1e-3 or m:GetPivot().RightVector:Dot(toCurve.Unit) < 0.95 then
					wrong += 1
				end
			end
		end
		check("a lantern's chosen front faces the curve", n >= 10 and wrong == 0, string.format("%d lanterns, %d facing away", n, wrong))
	end

	-- 9. street lamps on a sidewalk spline that curves round a building corner, road on the outside: every lamp stands
	--    on the curve with its arm over the road (the lamp's arm is its +X side; nothing is set by hand)
	do
		part({
			Name = "RoadA",
			Size = Vector3.new(95, 0.4, 10),
			CFrame = CFrame.new(O + Vector3.new(197.5, 0.2, 210)),
			Material = Enum.Material.Asphalt,
		})
		part({
			Name = "RoadB",
			Size = Vector3.new(10, 0.4, 85),
			CFrame = CFrame.new(O + Vector3.new(240, 0.2, 247.5)),
			Material = Enum.Material.Asphalt,
		})
		part({ Name = "Block", Size = Vector3.new(20, 14, 20), CFrame = CFrame.new(O + Vector3.new(170, 7, 280)), Material = Enum.Material.Concrete })
		local lamp = model("TestStreetLamp", {
			{ Name = "Pole", Size = Vector3.new(0.6, 10, 0.6), CFrame = CFrame.new(0, 5, 0) },
			{ Name = "Arm", Size = Vector3.new(4, 0.4, 0.4), CFrame = CFrame.new(2, 9.8, 0) },
			{ Name = "Head", Size = Vector3.new(1, 0.4, 1), CFrame = CFrame.new(3.8, 9.5, 0), Material = Enum.Material.Neon },
		})
		table.insert(templates, lamp)
		local C = O + Vector3.new(180, 0, 270)
		local pts = {}
		for k = 0, 6 do
			local ang = math.rad(-90 + k * 15) -- a quarter circle, radius 50, from (180,220) round to (230,270)
			local h = ground(C + Vector3.new(math.cos(ang) * 50, 0, math.sin(ang) * 50))
			table.insert(pts, { p = h.Position, n = h.Normal })
		end
		local l = E.makeLayer(lamp)
		check("a street lamp is not taken for a fence piece", not E.looksLikeSegment(l), "segment: " .. tostring(E.looksLikeSegment(l)))
		E.smartLine(l, true)
		l.s.interval, l.s.jitter = 12, 0
		local a = newArea("SS_Test_Lamps", { l })
		a.spline = { pts = pts, closed = false, width = 0, snap = true, branches = {} }
		run(a)
		local n, wrong, offCurve, where = 0, 0, 0, {}
		for _, m in placed(a.folder) do
			local pole, head = m:FindFirstChild("Pole"), m:FindFirstChild("Head")
			if pole and head then
				n += 1
				local base = Vector3.new(pole.Position.X, 0, pole.Position.Z)
				local out = (base - Vector3.new(C.X, 0, C.Z))
				if math.abs(out.Magnitude - 50) > 1 then
					offCurve += 1
				end
				local arm = Vector3.new(head.Position.X, 0, head.Position.Z) - base
				if arm:Dot(out.Unit) < arm.Magnitude * 0.7 then -- the arm must reach out toward the road
					wrong += 1
					if #where < 4 then
						table.insert(where, string.format("(%.0f,%.0f)", base.X - O.X, base.Z - O.Z))
					end
				end
			end
		end
		check("street lamps stand on the curve", n >= 5 and offCurve == 0, string.format("%d lamps, %d off the curve", n, offCurve))
		check(
			"street lamps reach over the road",
			n >= 5 and wrong == 0,
			string.format("%d of %d arms point away from the road %s", wrong, n, table.concat(where, " "))
		)
	end
	-- 12. piles: a pointed model (a pine) set to Prop, with groups and stacking on, must never be stacked on another's
	-- tip (they floated); a flat-topped crate may still stack
	do
		isolate()
		local pine = model("TestPine", {
			{ Name = "Trunk", Size = Vector3.new(1, 3, 1), CFrame = CFrame.new(0, 1.5, 0) },
			{ Name = "Low", Size = Vector3.new(7, 3, 7), CFrame = CFrame.new(0, 4.5, 0) },
			{ Name = "Mid", Size = Vector3.new(4.5, 3, 4.5), CFrame = CFrame.new(0, 7.5, 0) },
			{ Name = "Tip", Size = Vector3.new(1.5, 3, 1.5), CFrame = CFrame.new(0, 10.5, 0) },
		})
		local crate = model("TestCrate", { { Name = "Box", Size = Vector3.new(4, 4, 4), CFrame = CFrame.new(0, 2, 0) } })
		table.insert(templates, pine)
		table.insert(templates, crate)
		local lp, lc = E.makeLayer(pine, "Tree"), E.makeLayer(crate, "Prop")
		E.setType(lp, "Prop")
		lp.s.stack, lc.s.stack, lp.s.density, lc.s.density = 0.6, 0.6, 8, 8 -- enough copies to make piles
		local a = newArea("SS_Test_Piles", { lp, lc })
		paintRect(a, -70, -80, -5, -20)
		run(a)
		local function bottom(m)
			local low = math.huge
			for _, p in m:GetDescendants() do
				if p:IsA("BasePart") then
					low = math.min(low, p.Position.Y - p.Size.Y / 2)
				end
			end
			return low - O.Y
		end
		local pines, floating, crates, stacked = 0, 0, 0, 0
		for _, m in placed(a.folder) do
			if m.Name == pine.Name then
				pines += 1
				if bottom(m) > 0.5 then
					floating += 1
				end
			elseif m.Name == crate.Name then
				crates += 1
				if bottom(m) > 2 then
					stacked += 1
				end
			end
		end
		check("pointed models in piles never float", pines > 0 and floating == 0, string.format("%d of %d pines off the ground", floating, pines))
		check("flat-topped models still stack", crates > 0 and stacked > 0, string.format("%d of %d crates stacked", stacked, crates))
	end
	-- 14. keep-clear zones, locked objects, swapped models, filling from parts, biomes
	do
		-- a zone over the middle of a patch: nothing lands in it
		local zone = E.createArea("SS_Test_Zone", nil)
		zone.folder:SetAttribute("SS_Kind", "Clear")
		table.insert(made, zone)
		paintRect(zone, -30, 20, -10, 40)
		E.saveArea(zone)
		local a = newArea("SS_Test_Zoned", { E.makeLayer(rock, "Rock") })
		a.layers[1].s.density = 4
		paintRect(a, -45, 5, 5, 55)
		run(a)
		local inZone, n = 0, 0
		for _, m in placed(a.folder) do
			n += 1
			local x, z = m:GetAttribute("SS_X") - O.X, m:GetAttribute("SS_Z") - O.Z
			if x >= -30 and x < -10 and z >= 20 and z < 40 then
				inZone += 1
			end
		end
		check("keep-clear zones stay empty", n > 0 and inZone == 0, string.format("%d of %d copies inside the zone", inZone, n))

		-- a locked object keeps its copies through a reroll; swapping its model keeps the spots
		local function spots(folder)
			local t = {}
			for _, m in placed(folder) do
				table.insert(t, string.format("%.2f,%.2f", m:GetAttribute("SS_X"), m:GetAttribute("SS_Z")))
			end
			table.sort(t)
			return table.concat(t, ";")
		end
		local before = spots(a.folder)
		a.layers[1].s.locked = true
		a.seed += 1
		run(a)
		check("a locked object keeps its copies", spots(a.folder) == before, "reroll with the object locked")
		a.layers[1].s.locked = false
		a.seed -= 1
		local rock2 =
			model("TestRock2", { { Name = "Stone", Size = Vector3.new(5, 3, 6), CFrame = CFrame.new(0, 1.5, 0), Material = Enum.Material.Basalt } })
		table.insert(templates, rock2)
		E.swapVariant(a.layers[1], 1, rock2)
		run(a)
		local names = {}
		for _, m in placed(a.folder) do
			names[m.Name] = true
		end
		check(
			"a swapped model lands on the same spots",
			spots(a.folder) == before and names.TestRock2 and not names.TestRock,
			"same spots, new model"
		)

		-- the top of a raised platform, filled from the part itself, takes copies (it would read as a roof otherwise)
		local deck = part({
			Name = "Deck",
			Size = Vector3.new(24, 1, 24),
			CFrame = CFrame.new(O + Vector3.new(40, 12, -110)),
			Material = Enum.Material.WoodPlanks,
		})
		local b = newArea("SS_Test_Deck", { E.makeLayer(rock, "Rock") })
		b.layers[1].s.density = 3
		E.fillFromParts(b, { deck })
		E.saveArea(b)
		local reload = E.loadArea(b.folder)
		run(b)
		local onDeck = 0
		for _, m in placed(b.folder) do
			if m:GetPivot().Position.Y > O.Y + 11 then
				onDeck += 1
			end
		end
		check(
			"Fill selected parts places on the part's top",
			onDeck > 0 and #reload.on == 1,
			string.format("%d on the deck, part remembered: %s", onDeck, tostring(#reload.on == 1))
		)

		-- a biome from the sample models
		local samples, madeSamples = E.makeSamples()
		local forest, missing = E.biomeLayers(E.BIOMES[1])
		local kinds = {}
		for _, l in forest do
			kinds[l.type] = #l.variants
		end
		check(
			"a biome is made from the models in the place",
			(kinds.Tree or 0) >= 2 and kinds.Bush and kinds.Rock and kinds.Flower and #missing == 0,
			string.format("trees %s, missing %d", tostring(kinds.Tree), #missing)
		)
		if madeSamples then
			samples:Destroy()
		end
	end
	-- 15. several objects on one path never land inside each other (they all start at the same spot)
	do
		local a = E.createArea("SS_Test_PathMix", nil)
		table.insert(made, a)
		local pts = {}
		for i = 0, 6 do
			local h = ground(O + Vector3.new(-150 + i * 50, 0, -40 + math.sin(i) * 20))
			table.insert(pts, { p = h.Position, n = h.Normal })
		end
		a.spline = { pts = pts, closed = false, width = 0, snap = true, branches = {} }
		a.layers = {}
		for _, m in { tree, rock } do
			local l = E.makeLayer(m)
			E.smartLine(l, true)
			l.s.interval, l.s.jitter = 14, 0
			table.insert(a.layers, l)
		end
		E.generate(a, nil, 1, templates, {})
		local items, inside = {}, 0
		for _, m in placed(a.folder) do
			table.insert(items, { x = m:GetAttribute("SS_X"), z = m:GetAttribute("SS_Z"), r = m:GetAttribute("SS_R"), n = m.Name })
		end
		for i = 1, #items do
			for j = i + 1, #items do
				local p, q = items[i], items[j]
				if p.n ~= q.n and math.sqrt((p.x - q.x) ^ 2 + (p.z - q.z) ^ 2) < (p.r + q.r) * 0.7 then
					inside += 1
				end
			end
		end
		check("objects sharing a path stay apart", #items > 0 and inside == 0, string.format("%d placed, %d inside each other", #items, inside))
	end
	-- 16. Variation: colours differ per copy on parts, SurfaceAppearance tints and decals; details can be left out
	do
		local m = model("TestShrub", {
			{ Name = "Body", Size = Vector3.new(3, 3, 3), CFrame = CFrame.new(0, 1.5, 0), Color = Color3.fromRGB(90, 150, 80) },
			{ Name = "Apple", Size = Vector3.new(0.6, 0.6, 0.6), CFrame = CFrame.new(1, 3, 0), Color = Color3.fromRGB(200, 40, 40) },
		})
		local skin = Instance.new("MeshPart") -- SurfaceAppearance only goes on a MeshPart
		skin.Name, skin.Size, skin.Anchored = "Skin", Vector3.new(2, 2, 2), true
		skin.CFrame = m.Body.CFrame
		skin.Parent = m
		local sa = Instance.new("SurfaceAppearance")
		sa.Parent = skin
		local decal = Instance.new("Decal")
		decal.Parent = m.Body
		table.insert(templates, m)
		local l = E.makeLayer(m, "Bush")
		l.s.vary, l.s.valVar, l.s.dropDetails, l.s.density = true, 0.4, 1, 2
		local a = newArea("SS_Test_Vary", { l })
		paintRect(a, 40, 60, 80, 100)
		run(a)
		local colours, tints, apples, n = {}, {}, 0, 0
		for _, c in placed(a.folder) do
			n += 1
			local body = c:FindFirstChild("Body")
			if body then
				colours[body.Color:ToHex()] = true
			end
			local skinned = c:FindFirstChild("Skin")
			if skinned then
				local s2 = skinned:FindFirstChildOfClass("SurfaceAppearance")
				if s2 then
					local ok, col = pcall(function()
						return s2.Color:ToHex()
					end)
					if ok then
						tints[col] = true
					end
				end
			end
			if c:FindFirstChild("Apple") then
				apples += 1
			end
		end
		local function count(t)
			local k = 0
			for _ in t do
				k += 1
			end
			return k
		end
		check(
			"Variation recolours parts and SurfaceAppearance, and drops details",
			n > 3 and count(colours) > 3 and count(tints) > 3 and apples == 0,
			string.format("%d copies, %d part colours, %d SurfaceAppearance tints, %d with details", n, count(colours), count(tints), apples)
		)
	end
	-- 13. names are read word by word
	do
		local function kind(name)
			local m = model(name, { { Name = "P", Size = Vector3.new(2, 2, 2), CFrame = CFrame.new(0, 1, 0) } })
			local l = E.makeLayer(m)
			m:Destroy()
			return l.s.place
		end
		local okNames = kind("Palisade_Wall") == "Along"
			and kind("StreetLamp") == "Along"
			and kind("OakFences") == "Along"
			and kind("Campfire") == "Scatter"
			and kind("Trailhead") == "Scatter"
			and kind("Sign Post") == "Along"
		check("names are matched as words", okNames, "palisade/streetlamp/fences are lines; campfire/trailhead are not")
	end
	-- 13b. real footprints: long models keep their true outline, so they pack closer than their circle but never
	-- overlap
	do
		isolate()
		local log = model("TestLog", { { Name = "Trunk", Size = Vector3.new(10, 1.5, 2), CFrame = CFrame.new(0, 0.75, 0) } })
		table.insert(templates, log)
		local l = E.makeLayer(log, "Rock")
		l.s.density, l.s.spacing, l.s.cluster, l.s.tilt, l.s.align = 40, 1, 0, 0, 0 -- crowded, so they must pack
		l.s.scaleMin, l.s.scaleMax = 1, 1
		local a = newArea("SS_Test_Logs", { l })
		paintRect(a, -60, 60, 0, 120)
		run(a)
		local logs = {}
		for _, m in placed(a.folder) do
			local cf = m:GetPivot()
			table.insert(logs, { p = Vector2.new(cf.X, cf.Z), ax = Vector2.new(cf.RightVector.X, cf.RightVector.Z).Unit, m = m })
		end
		-- two rectangles overlap unless one of their four axes separates them
		local function halfOn(g, axis) -- half the log (10 x 2) measured along an axis
			local side = Vector2.new(-g.ax.Y, g.ax.X)
			return 5 * math.abs(g.ax:Dot(axis)) + 1 * math.abs(side:Dot(axis))
		end
		local overlaps, closest = 0, math.huge
		for i = 1, #logs do
			for j = i + 1, #logs do
				local A, B = logs[i], logs[j]
				local d = B.p - A.p
				closest = math.min(closest, d.Magnitude)
				local apart = false
				for _, axis in { A.ax, Vector2.new(-A.ax.Y, A.ax.X), B.ax, Vector2.new(-B.ax.Y, B.ax.X) } do
					if math.abs(d:Dot(axis)) > halfOn(A, axis) + halfOn(B, axis) - 0.05 then
						apart = true
						break
					end
				end
				if not apart then
					overlaps += 1
				end
			end
		end
		check(
			"long models use their real outline: closer than their circle, never overlapping",
			#logs >= 5 and overlaps == 0 and closest < 9, -- as circles, two logs would stay 10 studs apart
			string.format("%d logs, %d overlapping, closest %.1f studs apart (a circle would keep 10+)", #logs, overlaps, closest)
		)
	end
	-- 13c. the object brush: a pin puts a copy on its exact spot every time, and removing that copy takes the pin
	do
		isolate()
		local l = E.makeLayer(rock, "Rock")
		l.s.density = 0.3
		local a = newArea("SS_Test_Pins", { l })
		paintRect(a, 100, -100, 160, -40)
		l.pins = { { O.X + 130, O.Z - 70, 12345 } }
		run(a)
		local pinned
		for _, m in placed(a.folder) do
			if m:GetAttribute("SS_Pin") then
				pinned = m
			end
		end
		local onSpot = pinned
			and math.abs(pinned:GetAttribute("SS_X") - (O.X + 130)) < 0.01
			and math.abs(pinned:GetAttribute("SS_Z") - (O.Z - 70)) < 0.01
		if pinned then
			E.removeCopy(a, pinned)
		end
		check(
			"a pinned copy lands on its spot, and removing it takes the pin",
			onSpot and l.pins == nil,
			tostring(onSpot) .. ", pins left: " .. tostring(l.pins and #l.pins)
		)
	end
	-- 13d. colour zones tint copies by the area's pattern: different spots, different colours; off, all alike
	do
		isolate()
		local l = E.makeLayer(rock, "Rock")
		l.s.tint, l.s.vary, l.s.density = 0, false, 2
		local a = newArea("SS_Test_Zones", { l })
		paintRect(a, 100, -100, 200, 0)
		a.zones, a.zoneMood, a.pattern, a.patchSize = 1, "Autumn", "Groves", 30
		run(a)
		local tints = {}
		for _, m in placed(a.folder) do
			tints[m:FindFirstChildWhichIsA("BasePart", true).Color:ToHex()] = true
		end
		local n = 0
		for _ in tints do
			n += 1
		end
		a.zones = 0
		run(a)
		local plain = {}
		for _, m in placed(a.folder) do
			plain[m:FindFirstChildWhichIsA("BasePart", true).Color:ToHex()] = true
		end
		local k = 0
		for _ in plain do
			k += 1
		end
		check("colour zones tint copies by the pattern", n > 3 and k == 1, string.format("%d colours with zones, %d without", n, k))
	end
	-- 14. removed copies stay gone, and a patch rebuild leaves everything outside the patch alone
	do
		local a = newArea("SS_Test_Patch", { E.makeLayer(rock, "Rock") })
		paintRect(a, -60, -60, 60, 60)
		local total, _, _, an = run(a)
		local rows, sum = E.report(a)
		check(
			"the performance report counts what's placed",
			#rows == 1 and rows[1].copies == total and sum.parts >= total and rows[1].parts == sum.parts,
			string.format("%d rows, %d copies of %d, %d parts", #rows, rows[1] and rows[1].copies or 0, total, sum.parts)
		)
		local before = {}
		for _, m in placed(a.folder) do
			before[m] = true
		end
		local victim = placed(a.folder)[1]
		local vx, vz = victim and victim:GetAttribute("SS_X"), victim and victim:GetAttribute("SS_Z")
		if victim then
			E.removeCopy(a, E.copyAt(a, victim:FindFirstChildWhichIsA("BasePart", true)))
		end
		local _, again = E.generate(a, an, 1, templates, {})
		local back = 0
		for _, m in placed(a.folder) do
			if math.abs(m:GetAttribute("SS_X") - vx) < 0.3 and math.abs(m:GetAttribute("SS_Z") - vz) < 0.3 then
				back += 1
			end
		end
		check(
			"a removed copy stays removed after generating again",
			victim ~= nil and back == 0 and again == total - 1 and E.removedCount(a) == 1,
			string.format("%d placed, %d after, %d back at the spot", total, again or -1, back)
		)
		local kept = {}
		for _, m in placed(a.folder) do
			kept[m] = true
		end
		local box = { O.X - 10, O.Z - 10, O.X + 10, O.Z + 10 }
		E.generate(a, an, 1, templates, { region = box })
		local moved, stayed = 0, 0
		for m in kept do
			if m.Parent then
				stayed += 1
			elseif math.abs(m:GetAttribute("SS_X") - O.X) > 30 or math.abs(m:GetAttribute("SS_Z") - O.Z) > 30 then
				moved += 1 -- far outside the patch (and its padding), yet rebuilt
			end
		end
		check(
			"a patch rebuild keeps copies outside the patch",
			stayed > 0 and moved == 0,
			string.format("%d kept, %d far copies rebuilt", stayed, moved)
		)
	end

	-- map scan: copies grouped by shape (renamed, turned and scaled still match), nested copies left inside theirs,
	-- and the snapshot putting a changed copy back
	do
		local map = Instance.new("Folder")
		map.Name = "ScanMap"
		map.Parent = world
		local function hut(name, at, turn, scale)
			local m = Instance.new("Model")
			m.Name = name
			local base = part({ Name = "Walls", Size = Vector3.new(10, 8, 12), CFrame = CFrame.new(0, 4, 0) })
			base.Parent = m
			local roof = part({ Name = "Roof", Size = Vector3.new(11, 2, 13), CFrame = CFrame.new(0, 9, 0), Color = Color3.new(0.6, 0.2, 0.1) })
			roof.Parent = m
			m.PrimaryPart = base
			m.Parent = map
			m:PivotTo(CFrame.new(O + at) * CFrame.Angles(0, math.rad(turn), 0))
			if scale then
				m:ScaleTo(scale)
			end
			return m
		end
		local a1 = hut("Hut", Vector3.new(-200, 0, 200), 0)
		hut("Hut", Vector3.new(-170, 0, 200), 90)
		local renamed = hut("Cabin (1)", Vector3.new(-140, 0, 200), 33)
		local scaled = hut("Hut", Vector3.new(-110, 0, 200), 0, 1.5)
		local lone = model("Lonely", { { Name = "Box", Size = Vector3.new(3, 3, 3), CFrame = CFrame.new(0, 1.5, 0) } })
		lone.Parent = map
		-- a village: one model holding two huts; the village is the copy, its huts stay inside it
		local village = Instance.new("Model")
		village.Name = "Village"
		for i = 1, 2 do
			local h = hut("Hut", Vector3.new(-200 + i * 30, 0, 250), 0)
			h.Parent = village
		end
		village.Parent = map
		local village2 = village:Clone()
		village2.Name = "Village B"
		village2:PivotTo(village:GetPivot() * CFrame.new(0, 0, 60))
		village2.Parent = map
		local kinds = E.scanKinds({ roots = { map } })
		local huts, villages
		for _, k in kinds do
			for _, c in k.copies do
				if c.inst == a1 then
					huts = k
				elseif c.inst == village then
					villages = k
				end
			end
		end
		local hasRenamed, scaleOf = false, nil
		for _, c in huts and huts.copies or {} do
			hasRenamed = hasRenamed or c.inst == renamed
			if c.inst == scaled then
				scaleOf = c.scale
			end
		end
		check(
			"the map scan groups copies by shape: renamed, turned and scaled",
			huts ~= nil and huts.count == 4 and hasRenamed and scaleOf ~= nil and math.abs(scaleOf - 1.5) < 0.01 and huts.name == "Hut",
			string.format("%s huts, scaled %.2f, %d kinds", huts and huts.count or "no", scaleOf or -1, #kinds)
		)
		check(
			"copies inside a copy stay part of it; a model with no twin isn't a kind",
			villages ~= nil and villages.count == 2 and #kinds == 2,
			string.format("%s villages, %d kinds", villages and villages.count or "no", #kinds)
		)
		E.clearSnapshot()
		local saved = E.snapshot({ a1, scaled })
		local again = E.snapshot({ a1 })
		a1.Roof.Color = Color3.new(1, 1, 1) -- a season tool recolours it in place
		E.snapshotChanged(a1)
		local swapIn = lone:Clone() -- a swap tool replaces the scaled one
		swapIn.Parent = map
		E.snapshotChanged(scaled, swapIn)
		scaled:Destroy()
		local info = E.snapshotInfo()
		local back = E.restoreSnapshot()
		local roofs, lonely = 0, 0
		for _, m in map:GetChildren() do
			if m.Name == "Hut" and m:FindFirstChild("Roof") and m.Roof.Color == Color3.new(0.6, 0.2, 0.1) then
				roofs += 1
			elseif m.Name == "Lonely" then
				lonely += 1
			end
		end
		check(
			"the snapshot keeps originals once and puts changed copies back",
			saved == 2 and again == 0 and info.saved == 2 and info.changed == 2 and back == 2 and roofs == 3 and lonely == 1,
			string.format("saved %d then %d, %d changed, %d back, %d red roofs, %d swapped left", saved, again, info.changed, back, roofs, lonely)
		)
		check("a restore leaves nothing marked changed", E.snapshotInfo().changed == 0, "")
		E.clearSnapshot()
		map:Destroy()
	end

	-- swapping a kind: each new copy stands where the old one did, turned the same way, at its scale, base on the
	-- ground; tags, attributes and scripts come along; the originals can be put back
	do
		local map = Instance.new("Folder")
		map.Name = "SwapMap"
		map.Parent = world
		local function hut(at, turn, scale)
			local m = Instance.new("Model")
			m.Name = "Hut"
			local base = part({ Name = "Walls", Size = Vector3.new(10, 8, 12), CFrame = CFrame.new(0, 4, 0) })
			base.Parent = m
			part({ Name = "Roof", Size = Vector3.new(11, 2, 13), CFrame = CFrame.new(0, 9, 0) }).Parent = m
			m.PrimaryPart = base
			m.Parent = map
			m:PivotTo(CFrame.new(O + at) * CFrame.Angles(0, math.rad(turn), 0))
			if scale then
				m:ScaleTo(scale)
			end
			return m
		end
		local huts = { hut(Vector3.new(-200, 0, -200), 0), hut(Vector3.new(-170, 0, -200), 90), hut(Vector3.new(-140, 0, -200), 0, 1.5) }
		huts[1]:SetAttribute("Owner", "Ghulo")
		game:GetService("CollectionService"):AddTag(huts[1], "Destructible")
		local script = Instance.new("Script")
		script.Disabled = true
		script.Parent = huts[1]
		-- the new model: a flat slab 4 wide, 16 tall, 2 deep; and the same slab built lying down (its up is its X)
		local tower = part({ Name = "Tower", Size = Vector3.new(4, 16, 2), CFrame = CFrame.new(O + Vector3.new(0, 300, 40)) })
		local lying = part({
			Name = "Lying",
			Size = Vector3.new(16, 4, 2),
			CFrame = CFrame.new(O + Vector3.new(0, 300, 60)) * CFrame.Angles(0, 0, math.rad(90)),
		})
		local kinds = E.scanKinds({ roots = { map } })
		local kind = kinds[1]
		local before = {}
		for _, c in kind.copies do
			local cf, size = c.inst:GetBoundingBox()
			before[c.inst] = { at = cf.Position, bottom = cf.Position.Y - size.Y / 2, look = c.inst:GetPivot().LookVector, scale = c.scale }
		end
		E.clearSnapshot()
		local pairs1 = E.swapCopies(kind.copies, { { inst = tower, w = 1 } }, { scripts = true, tags = true, attributes = true })
		local worst, turned, tall = 0, 0, 0
		local carried = false
		for _, pr in pairs1 do
			local b = before[pr.old]
			local cf, size = pr.new.CFrame, pr.new.Size
			local bottom = cf.Position.Y - size.Y / 2
			worst = math.max(
				worst,
				math.abs(bottom - b.bottom),
				(Vector3.new(cf.Position.X, 0, cf.Position.Z) - Vector3.new(b.at.X, 0, b.at.Z)).Magnitude
			)
			turned = math.max(turned, (pr.new.CFrame.LookVector - b.look).Magnitude)
			tall = math.max(tall, math.abs(size.Y - 16 * b.scale))
			if pr.old == huts[1] then
				carried = pr.new:GetAttribute("Owner") == "Ghulo"
					and game:GetService("CollectionService"):HasTag(pr.new, "Destructible")
					and pr.new:FindFirstChildOfClass("Script") ~= nil
			end
		end
		check(
			"a swapped copy stands where the old one did, turned the same way, its base where the old one's was",
			#pairs1 == 3 and worst < 0.05 and turned < 0.01,
			string.format("%d swapped, off by %.3f, turned off by %.3f", #pairs1, worst, turned)
		)
		check("a swapped copy keeps its scale against the rest", tall < 0.05, string.format("height off by %.3f", tall))
		check("tags, attributes and scripts come along when asked", carried, tostring(carried))
		local back = E.restoreSnapshot()
		local hutsBack = 0
		for _, m in map:GetChildren() do
			hutsBack += m.Name == "Hut" and 1 or 0
		end
		check("the swapped copies can be put back", back == 3 and hutsBack == 3, string.format("%d back, %d huts", back, hutsBack))
		-- a model built lying down still stands up; "same size" makes it as big as the old copies
		kinds = E.scanKinds({ roots = { map } })
		local extentOf = {}
		for _, c in kinds[1].copies do
			local _, size = c.inst:GetBoundingBox()
			extentOf[c.inst] = math.max(size.X, size.Y, size.Z)
		end
		local pairs2 = E.swapCopies(kinds[1].copies, { { inst = lying, w = 1 } }, { match = true })
		local upright, off = true, 0
		for _, pr in pairs2 do
			upright = upright and math.abs(pr.new.CFrame.RightVector.Y) > 0.99 -- its long X side points up
			off = math.max(off, math.abs(pr.new.Size.X - extentOf[pr.old]))
		end
		check(
			"a model built lying down stands up, and same size matches each old copy",
			#pairs2 == 3 and upright and off < 0.1,
			string.format("%d swapped, upright %s, size off by %.2f", #pairs2, tostring(upright), off)
		)
		E.restoreSnapshot()
		E.clearSnapshot()
		map:Destroy()
	end

	-- seasons: leaves, roofs and walls each change their own way, one season replaces another from the original
	-- colours, and taking it off puts every colour and the terrain back exactly
	do
		local map = Instance.new("Folder")
		map.Name = "SeasonMap"
		map.Parent = world
		local at = O + Vector3.new(120, 36, 0) -- over the terrain mound's top
		local green, brown, wallC = Color3.fromRGB(70, 140, 60), Color3.fromRGB(110, 80, 50), Color3.fromRGB(150, 120, 100)
		local leaves = part({ Name = "Leaves", Size = Vector3.new(8, 8, 8), CFrame = CFrame.new(at), Color = green, Parent = map })
		local trunk =
			part({ Name = "Trunk", Size = Vector3.new(1, 6, 1), CFrame = CFrame.new(at - Vector3.new(0, 7, 0)), Color = brown, Parent = map })
		local roof =
			part({ Name = "Slab", Size = Vector3.new(12, 1, 12), CFrame = CFrame.new(at + Vector3.new(20, 0, 0)), Color = wallC, Parent = map })
		local wall =
			part({ Name = "Wall", Size = Vector3.new(12, 10, 1), CFrame = CFrame.new(at + Vector3.new(20, -6, 6)), Color = wallC, Parent = map })
		local sa = Instance.new("SurfaceAppearance")
		sa.Parent = leaves
		local decal = Instance.new("Decal")
		decal.Color3 = wallC
		decal.Parent = wall
		local saBefore = select(
			2,
			pcall(function()
				return sa.Color
			end)
		)
		local function val(c)
			return select(3, c:ToHSV())
		end
		local function sat(c)
			return select(2, c:ToHSV())
		end
		local grassBefore = workspace.Terrain:GetMaterialColor(Enum.Material.Grass)
		local function count(material)
			local r = Region3.new(O + Vector3.new(104, 12, -16), O + Vector3.new(136, 36, 16)):ExpandToGrid(4)
			local mats = workspace.Terrain:ReadVoxels(r, 4)
			local n = 0
			for x = 1, #mats do
				for y = 1, #mats[x] do
					for z = 1, #mats[x][y] do
						n += mats[x][y][z] == material and 1 or 0
					end
				end
			end
			return n
		end
		local grassCells = count(Enum.Material.Grass)
		local n, terrainOk = E.applySeason({ season = "Snow", strength = 1, roots = { map }, terrainColors = true, terrainMaterials = true })
		check(
			"snow: leaves go white, a flat top whiter than a wall, the wall paler",
			n == 4 and val(leaves.Color) > 0.85 and sat(leaves.Color) < 0.2 and val(roof.Color) > val(wall.Color) and sat(wall.Color) < sat(wallC),
			string.format(
				"%d parts, leaves v%.2f s%.2f, top v%.2f, wall v%.2f s%.2f",
				n,
				val(leaves.Color),
				sat(leaves.Color),
				val(roof.Color),
				val(wall.Color),
				sat(wall.Color)
			)
		)
		local snowCells = count(Enum.Material.Snow)
		check(
			"snow turns the terrain's grass to snow, and tints its grass colour",
			terrainOk and grassCells > 0 and snowCells >= grassCells and workspace.Terrain:GetMaterialColor(Enum.Material.Grass) ~= grassBefore,
			string.format("%d grass cells before, %d snow after, terrain ok %s", grassCells, snowCells, tostring(terrainOk))
		)
		E.applySeason({ season = "Autumn", strength = 1, roots = { map }, terrainColors = true })
		local h = leaves.Color:ToHSV()
		check(
			"autumn replaces snow from the original colours",
			(h < 0.17 or h > 0.95) and sat(leaves.Color) > 0.3 and count(Enum.Material.Grass) == grassCells,
			string.format("leaves hue %.2f s%.2f, %d grass cells", h, sat(leaves.Color), count(Enum.Material.Grass))
		)
		local info = E.seasonInfo()
		local back = E.clearSeason({ roots = { map } })
		local saAfter = select(
			2,
			pcall(function()
				return sa.Color
			end)
		)
		check(
			"taking the season off puts every colour back exactly",
			info
				and info.season == "Autumn"
				and back == 4
				and leaves.Color == green
				and trunk.Color == brown
				and roof.Color == wallC
				and wall.Color == wallC
				and decal.Color3 == wallC
				and saAfter == saBefore
				and leaves:GetAttribute("SS_SeasonOrig") == nil
				and workspace.Terrain:GetMaterialColor(Enum.Material.Grass) == grassBefore
				and E.seasonInfo() == nil,
			string.format("%d back, info %s", back, info and info.season or "none")
		)
		map:Destroy()
	end
end)
if not ok then
	check("suite ran without errors", false, tostring(err))
end

-- ── clean up everything ──────────────────────────────────────────────────────
for _, a in made do
	if a.folder and a.folder.Parent then
		E.clearOutputs(a) -- its copies, and its road surface outside the area
		a.folder:Destroy()
	end
end
-- anything a test area left behind, even from a run that stopped halfway (its roads go with it)
for _, f in E.getOut():GetChildren() do
	if string.sub(f.Name, 1, 8) == "SS_Test_" then
		E.clearOutputs(E.loadArea(f))
		f:Destroy()
	end
end
workspace.Terrain:FillBlock(CFrame.new(O + Vector3.new(140, -60, 0)), Vector3.new(300, 290, 260), Enum.Material.Air)
world:Destroy()
table.insert(
	results,
	string.format(
		"%s  (%d checks, %d failed, engine %s)",
		fails == 0 and "ALL PASS" or "FAILURES",
		#results,
		fails,
		tostring(SRC:GetAttribute("Version"))
	)
)
return table.concat(results, "\n")
