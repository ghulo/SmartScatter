--[[
	Engine tests that run without Studio (tools/offline.py, part of tools/check.sh): the pure logic — patterns,
	spacing and footprints, the painted mask, curves. What needs the real world (raycasts, models, placing copies)
	is in tests/suite.lua, run inside Studio.
	E and I are the engine's API and internals, loaded by the runner.
]]

local passed, failed = 0, {}
local function check(name, ok, detail)
	if ok then
		passed += 1
	else
		table.insert(failed, name .. (detail and ("  |  " .. detail) or ""))
	end
end
local function near(a, b, eps)
	return math.abs(a - b) <= (eps or 1e-6)
end

-- ── patterns ────────────────────────────────────────────────────────────────────
do
	for _, name in E.PATTERNS do
		local a = { patches = 1, pattern = name, patchSize = 40, seed = 4242, windDir = 30 }
		local lo, hi, bad = math.huge, -math.huge, 0
		for x = 0, 400, 7 do
			for z = 0, 400, 7 do
				local v = E.patchAt(a, x, z)
				lo, hi = math.min(lo, v), math.max(hi, v)
				if v < 0 or v > 1 or v ~= v then
					bad += 1
				end
			end
		end
		check("pattern " .. name .. " stays in 0-1 and varies", bad == 0 and hi - lo >= 0.6, string.format("%.2f-%.2f, %d bad", lo, hi, bad))
		check("pattern " .. name .. " has a hint", type(E.PATTERN_HINT[name]) == "string")
	end
	check("no pattern strength means no effect", E.patchAt({ patches = 0, pattern = "Islands", seed = 1 }, 12, 34) == 1)
	local full = E.patchAt({ patches = 1, pattern = "Groves", patchSize = 40, seed = 7 }, 12, 34)
	local half = E.patchAt({ patches = 0.5, pattern = "Groves", patchSize = 40, seed = 7 }, 12, 34)
	check("strength blends the pattern in", near(half, 0.5 + 0.5 * full), string.format("full %.3f half %.3f", full, half))
	check("an unknown pattern falls back to Groves", E.patchAt({ patches = 1, pattern = "Nope", patchSize = 40, seed = 7 }, 12, 34) == full)
	local a1 = E.patchAt({ patches = 1, pattern = "Natural", patchSize = 40, seed = 7 }, 50, 50)
	local a2 = E.patchAt({ patches = 1, pattern = "Natural", patchSize = 40, seed = 8 }, 50, 50)
	check("two areas' seeds give different patterns", a1 ~= a2)
end

-- ── colour zones ────────────────────────────────────────────────────────────────────
do
	local a = { zones = 0, zoneMood = "Autumn", pattern = "Groves", patchSize = 40, seed = 3 }
	check("no colour zones, no tint", E.zoneShift(a, 5, 5) == nil)
	a.zones = 1
	local open, thick
	for x = 0, 400, 5 do -- find an open spot and a thick one
		local v = E.patternAt(a, x, 0)
		if v < 0.1 and not open then
			open = x
		elseif v > 0.9 and not thick then
			thick = x
		end
	end
	local oh, os, ov = E.zoneShift(a, open or 0, 0)
	local th = E.zoneShift(a, thick or 0, 0)
	check(
		"open ground takes the mood, thick ground keeps its colour",
		open and thick and oh < -0.07 and math.abs(th) < 0.01,
		string.format("open %.3f thick %.3f", oh or 0, th or 0)
	)
	a.zones = 0.5
	local hh = E.zoneShift(a, open or 0, 0)
	check("zone strength scales the tint", near(hh, oh / 2))
	for _, mood in E.ZONE_MOODS do
		a.zoneMood = mood
		check("mood " .. mood .. " tints and has a hint", E.zoneShift(a, open or 0, 0) ~= nil and type(E.ZONE_HINT[mood]) == "string")
	end
	check("the mood shifts saturation and brightness too", os ~= 0 and ov ~= 0)
end

-- ── spacing and real footprints ───────────────────────────────────────────────────
do
	local function item(x, z, extra)
		local it = { x = x, z = z, r = 1, type = "Rock", sp = 1, cs = 1 }
		for k, v in extra or {} do
			it[k] = v
		end
		return it
	end
	local function log(x, z, yaw)
		return item(x, z, { r = 5, hx = 5, hz = 1, yaw = yaw })
	end
	local function clash(a, b)
		local h = I.Hash.new()
		h:add(a)
		return h:conflicts(b)
	end
	-- circles keep the plain rule: radius x spacing on both sides
	check("circles: too close", clash(item(0, 0), item(1.9, 0)))
	check("circles: far enough", not clash(item(0, 0), item(2.1, 0)))
	-- logs lying along X
	check("logs side by side fit closer than their circle", not clash(log(0, 0, 0), log(0, 2.2, 0)))
	check("logs side by side still can't overlap", clash(log(0, 0, 0), log(0, 1.8, 0)))
	check("logs end to end keep their length", clash(log(0, 0, 0), log(9.5, 0, 0)) and not clash(log(0, 0, 0), log(10.5, 0, 0)))
	check("a crossing log is caught", clash(log(0, 0, 0), log(0, 3, math.pi / 2)))
	check("a diagonal corner overlap is caught", clash(log(0, 0, 0), log(8, 1.8, -0.2)))
	check("a turned log clear of the first is fine", not clash(log(0, 0, 0), log(0, 7, math.pi / 2)))
	-- two turned logs, side by side but shifted along their length: only their own sides can tell them apart
	do
		local q = math.pi / 4
		local sideX, sideZ = math.sin(q), math.cos(q) -- the logs' short axis
		local lenX, lenZ = math.cos(q), -math.sin(q) -- their long axis
		local bx, bz = sideX * 2.2 + lenX * 6, sideZ * 2.2 + lenZ * 6
		check("turned logs side by side, shifted along, fit", not clash(log(0, 0, q), log(bx, bz, q)))
		check("the same, a little closer, don't", clash(log(0, 0, q), log(sideX * 1.8 + lenX * 6, sideZ * 1.8 + lenZ * 6, q)))
	end
	-- while a spot is tried the turn isn't known yet: only the narrow side counts
	check("an unturned log is tried by its narrow side", not clash(log(0, 0, 0), item(0, 2.5, { r = 5, hx = 5, hz = 1 })))
	-- a circle next to a log
	check("a bush beside a log", not clash(log(0, 0, 0), item(0, 2.2)) and clash(log(0, 0, 0), item(0, 1.5)))
	-- the same pile may touch
	check("pieces of one pile may touch", not clash(item(0, 0, { g = 7 }), item(1.85, 0, { g = 7 })))
end

-- ── pins (the object brush) ─────────────────────────────────────────────────────────────
do
	local a = { rows = {}, count = 0, cell = 4, size = 1 }
	for cx = 0, 9 do
		for cz = 0, 9 do
			E.setCell(a, cx, cz, true) -- painted: 0-40 studs square
		end
	end
	local l = { m = { radius = 2 }, s = { spacing = 1, scaleMin = 1, scaleMax = 1 } }
	local rng = Random.new(5)
	local added = E.brushPins(a, l, 20, 20, 10, rng)
	check("a brush dab drops pins", #added >= 2 and #l.pins == #added, #added .. " added")
	local gap, tight = E.pinSpacing(l), math.huge
	for i = 1, #l.pins do
		for j = i + 1, #l.pins do
			tight = math.min(tight, math.sqrt((l.pins[i][1] - l.pins[j][1]) ^ 2 + (l.pins[i][2] - l.pins[j][2]) ^ 2))
		end
	end
	check("pins keep the object's spacing", tight >= gap - 0.02, string.format("closest %.2f, spacing %.2f", tight, gap))
	local before = #l.pins
	for _ = 1, 20 do
		E.brushPins(a, l, 20, 20, 10, rng)
	end
	local inside = true
	for _, p in l.pins do
		inside = inside and p[1] >= 0 and p[1] < 40 and p[2] >= 0 and p[2] < 40
	end
	check("dabbing again fills up but never crowds", #l.pins >= before and inside)
	local off = E.brushPins(a, l, 200, 200, 10, rng)
	check("no pins off the painted ground", #off == 0)
	local p1 = l.pins[1]
	check("a removed copy's pin comes off", E.unpin(l, p1[1], p1[2]) and not table.find(l.pins or {}, p1))
	local n = #l.pins
	local erased = E.erasePins(l, 20, 20, 100)
	check("the brush's eraser clears pins", erased == n and l.pins == nil)
	check(
		"saved pins are read back, junk dropped",
		#E.readPins({ { 1, 2, 3 }, { "x" }, 5, { 4, 5, 6 } }) == 2 and E.readPins({}) == nil and E.readPins(nil) == nil
	)
end

-- ── copying an area's look ───────────────────────────────────────────────────────────────
do
	local from = { edge = 20, size = 1.3, patches = 0.7, pattern = "Veins", patchSize = 90, zones = 0.4, zoneMood = "Frost", windDir = 45 }
	local to = { edge = 12, rows = { [1] = { [2] = true } }, layers = { "keep" } }
	E.copyLook(from, to)
	local same = true
	for _, k in E.AREA_LOOK do
		same = same and to[k] == from[k]
	end
	check("copying an area's look takes every look setting", same)
	check("copying an area's look leaves its ground and objects", to.rows[1][2] and to.layers[1] == "keep")
end

-- ── the painted mask ──────────────────────────────────────────────────────────────
do
	local a = { rows = {}, count = 0 }
	check("painting a cell counts it", E.setCell(a, 3, 4, true) and a.count == 1 and E.hasCell(a, 3, 4))
	check("painting it again changes nothing", not E.setCell(a, 3, 4, true) and a.count == 1)
	E.setCell(a, -2, 4, true)
	check("negative cells work", E.hasCell(a, -2, 4) and a.count == 2)
	check("erasing a cell", E.setCell(a, 3, 4, false) and not E.hasCell(a, 3, 4) and a.count == 1)
	E.setCell(a, -2, 4, false)
	check("an emptied row is dropped", a.rows[4] == nil and a.count == 0)
end

-- ── curves ─────────────────────────────────────────────────────────────────────────
do
	local up = Vector3.yAxis
	local function pt(x, z)
		return { p = Vector3.new(x, 0, z), n = up }
	end
	local open = { pts = { pt(0, 0), pt(10, 0), pt(20, 5), pt(30, 0) } }
	local P, _, _, W = E.splineCurve(open, 1)
	check("an open curve starts and ends on its points", P[1] == open.pts[1].p and P[#P] == open.pts[4].p)
	local gap = 0
	for k = 2, #P do
		gap = math.max(gap, (P[k] - P[k - 1]).Magnitude)
	end
	check("curve samples are close together", gap < 1.6, string.format("widest step %.2f", gap))
	check("widths default to 1", W[1] == 1 and W[#W] == 1)
	local loop = { pts = { pt(0, 0), pt(10, 0), pt(10, 10), pt(0, 10) }, closed = true }
	local L = E.splineCurve(loop, 1)
	check("a closed curve comes back to its start", (L[#L] - L[1]).Magnitude < 1e-6)
	check(
		"a straight curve's automatic handle points along it",
		(E.autoHandle({ pts = { pt(0, 0), pt(6, 0), pt(12, 0) } }, 2) - Vector3.new(2, 0, 0)).Magnitude < 1e-6
	)
	-- a raised point is carried into the samples, eased toward its neighbours
	local r = { pts = { pt(0, 0), pt(10, 0), pt(20, 0) } }
	r.pts[2].raised = true
	local _, _, _, _, _, R = E.splineCurve(r, 1)
	local top = 0
	for _, v in R do
		top = math.max(top, v)
	end
	check("a raised point lifts the curve around it", top == 1 and R[1] == 0 and R[#R] == 0)
	check("a road has its own width inside the strip", E.roadWidth({ width = 30, surface = { on = true, width = 12 } }) == 12)
	check("older roads are as wide as the strip", E.roadWidth({ width = 30, surface = { on = true } }) == 30)
	check("no road, no width", E.roadWidth({ width = 30, surface = { on = false, width = 12 } }) == 0)
end

-- ── kinds: shapes matched by shape, not name ──────────────────────────────────────────
do
	local V = Vector3.new
	local tree = {
		{ kind = "Part:Block", size = V(1.2, 8, 1.2) },
		{ kind = "MeshPart:rbxassetid://7", size = V(8, 6, 8) },
	}
	local key, unit = E.shapeKey(tree)
	check("a shape has a key and a size", type(key) == "string" and unit == 8)
	local turned = { -- the same parts, turned on their sides
		{ kind = "MeshPart:rbxassetid://7", size = V(6, 8, 8) },
		{ kind = "Part:Block", size = V(8, 1.2, 1.2) },
	}
	check("a turned copy matches", E.shapeKey(turned) == key)
	local big = {
		{ kind = "Part:Block", size = V(1.8, 12, 1.8) },
		{ kind = "MeshPart:rbxassetid://7", size = V(12, 9, 12) },
	}
	local bkey, bunit = E.shapeKey(big)
	check("a scaled copy matches, and its size says how much bigger", bkey == key and near(bunit / unit, 1.5))
	local tiny = { -- float error from scaling back and forth doesn't split a kind
		{ kind = "Part:Block", size = V(1.2000004, 7.9999996, 1.2) },
		{ kind = "MeshPart:rbxassetid://7", size = V(8, 6.0000003, 8) },
	}
	check("tiny float differences still match", E.shapeKey(tiny) == key)
	local other = {
		{ kind = "Part:Block", size = V(1.2, 8, 1.2) },
		{ kind = "MeshPart:rbxassetid://8", size = V(8, 6, 8) },
	}
	check("another mesh is another kind", E.shapeKey(other) ~= key)
	local stretched = {
		{ kind = "Part:Block", size = V(1.2, 12, 1.2) },
		{ kind = "MeshPart:rbxassetid://7", size = V(8, 6, 8) },
	}
	check("different proportions are another kind", E.shapeKey(stretched) ~= key)
	local extra = table.clone(tree)
	table.insert(extra, { kind = "Part:Ball", size = V(1, 1, 1) })
	check("an extra part is another kind", E.shapeKey(extra) ~= key)
	check("no parts, no key", E.shapeKey({}) == nil)
end

-- ── seasons: colours ─────────────────────────────────────────────────────────────────
do
	local green = Color3.fromRGB(70, 140, 60)
	local wall = Color3.fromRGB(150, 120, 100)
	local function hueOf(c)
		local h = c:ToHSV()
		return h
	end
	local function satOf(c)
		local _, s = c:ToHSV()
		return s
	end
	local function valOf(c)
		local _, _, v = c:ToHSV()
		return v
	end
	check("the HSV stand-in round-trips", (Color3.fromHSV(green:ToHSV()).G - green.G) < 1e-9)
	for _, season in E.SEASONS do
		check(season .. ": no amount, no change", E.seasonColor(green, season, 0, { foliage = true }) == green)
		check(season .. " has a hint", type(E.SEASON_HINT[season]) == "string")
	end
	local snowLeaf = E.seasonColor(green, "Snow", 1, { foliage = true })
	check(
		"snow turns leaves nearly white",
		valOf(snowLeaf) > 0.85 and satOf(snowLeaf) < 0.2,
		string.format("v %.2f s %.2f", valOf(snowLeaf), satOf(snowLeaf))
	)
	local roof = E.seasonColor(wall, "Snow", 1, { top = true })
	local side = E.seasonColor(wall, "Snow", 1, {})
	check("snow settles on tops more than on walls", valOf(roof) > valOf(side) and satOf(side) < satOf(wall))
	local picks = {}
	for i = 0, 4 do
		local c = E.seasonColor(green, "Autumn", 1, { foliage = true, pick = i / 5 + 0.01 })
		local h = hueOf(c)
		check("autumn leaves are warm (" .. i .. ")", h < 0.17 or h > 0.95, string.format("hue %.2f", h))
		picks[string.format("%.3f", h)] = true
	end
	local n = 0
	for _ in picks do
		n += 1
	end
	check("autumn gives trees different colours", n >= 4, tostring(n))
	local dry = E.seasonColor(green, "Dry", 1, { foliage = true, pick = 0.2 })
	check("dry grass is straw, not green", hueOf(dry) < 0.17, string.format("hue %.2f", hueOf(dry)))
	local half = E.seasonColor(green, "Snow", 0.5, { foliage = true })
	check("half strength is in between", valOf(half) > valOf(green) and valOf(half) < valOf(snowLeaf))
	local darkLeaf = Color3.fromRGB(20, 50, 20)
	check(
		"dark leaves stay darker than light ones in autumn",
		valOf(E.seasonColor(darkLeaf, "Autumn", 1, { foliage = true, pick = 0.1 }))
			< valOf(E.seasonColor(green, "Autumn", 1, { foliage = true, pick = 0.1 }))
	)
end

-- ── improving a layout ─────────────────────────────────────────────────────────────
do
	-- a 10 x 10 grid of trees 10 studs apart, with a hole of 3 x 3 missing in it
	local function grid(opts)
		local pts = {}
		for gx = 0, 9 do
			for gz = 0, 9 do
				local hole = opts.hole and gx >= 4 and gx <= 6 and gz >= 4 and gz <= 6
				if not hole then
					local jx = opts.jitter and math.noise(gx * 0.7, gz * 0.7, 1) * opts.jitter or 0
					local jz = opts.jitter and math.noise(gx * 0.7, gz * 0.7, 9) * opts.jitter or 0
					table.insert(pts, { x = gx * 10 + jx, z = gz * 10 + jz, r = 2 })
				end
			end
		end
		return pts
	end
	local function spotsOver(step)
		local sp = {}
		for x = -5, 95, step do
			for z = -5, 95, step do
				table.insert(sp, { x = x, z = z })
			end
		end
		return sp
	end
	local function inHole(x, z)
		return x > 30 and x < 70 and z > 30 and z < 70
	end
	check("typical spacing of a grid is its step", near(E.typicalSpacing(grid({})), 10))
	local even = E.evenness(grid({}))
	local clumped = grid({})
	for i = 1, 20 do
		clumped[i].x += 7
	end
	check(
		"evenness: a grid is even, a clumped one less so",
		even > 0.95 and E.evenness(clumped) < even,
		string.format("%.2f vs %.2f", even, E.evenness(clumped))
	)

	local pts = grid({ hole = true })
	local n0 = #pts
	table.insert(pts, { x = 21, z = 20, r = 2 }) -- crowding the tree at 20, 20
	table.insert(pts, { x = 80, z = 81, r = 2, fixed = true }) -- crowding too, but placed by hand
	table.insert(pts, { x = 90, z = 5, r = 2, bad = true }) -- on a road, say
	local spots = spotsOver(2)
	local opts = { spacing = 10, crowd = 0.5, gap = 1.7, step = 2, seed = 3 }
	local plan = E.relayout(pts, spots, opts)
	local movedIn, fixedTouched = 0, false
	for _, mv in plan.moves do
		movedIn += inHole(mv.x, mv.z) and 1 or 0
		fixedTouched = fixedTouched or pts[mv.i].fixed == true
	end
	check(
		"a hole is found; the crowded and the rule-breaking copies move into it",
		plan.holes == 1 and plan.crowded >= 1 and plan.bad == 1 and #plan.moves == 3 and movedIn == 3,
		string.format("%d holes, %d crowded, %d bad, %d moves (%d into the hole)", plan.holes, plan.crowded, plan.bad, #plan.moves, movedIn)
	)
	local who = {}
	for _, mv in plan.moves do
		who[mv.i] = true
	end
	check(
		"the copy with the most room keeps its place; the hand-placed one never moves",
		who[n0 + 1] and not fixedTouched and not who[n0 + 2] and who[n0 + 3]
	)
	check("moving only: nothing added or taken out", #plan.adds == 0 and #plan.removes == 0)
	local again = E.relayout(pts, spots, opts)
	local same = #again.moves == #plan.moves
	for k, mv in plan.moves do
		same = same and again.moves[k].i == mv.i and again.moves[k].x == mv.x and again.moves[k].z == mv.z
	end
	check("the same plan every time", same)

	opts.fill = true
	local filled = E.relayout(pts, spots, opts)
	local total, farApart = #filled.moves + #filled.adds, true
	local placed = {}
	for _, mv in filled.moves do
		table.insert(placed, mv)
	end
	for _, ad in filled.adds do
		table.insert(placed, ad)
		farApart = farApart and inHole(ad.x, ad.z)
	end
	for a = 1, #placed do
		for b = a + 1, #placed do
			farApart = farApart and math.sqrt((placed[a].x - placed[b].x) ^ 2 + (placed[a].z - placed[b].z) ^ 2) >= 7.7
		end
	end
	check(
		"filling: the hole gets about as many copies as it lost, well apart",
		total >= 6 and total <= 12 and farApart,
		string.format("%d moved or added", total)
	)
	-- the result is more even than before
	local after = {}
	local gone = {}
	for _, mv in filled.moves do
		gone[mv.i] = true
		table.insert(after, { x = mv.x, z = mv.z })
	end
	for i, p in pts do
		if not gone[i] then
			table.insert(after, p)
		end
	end
	for _, ad in filled.adds do
		table.insert(after, ad)
	end
	check(
		"the layout is more even afterwards",
		E.evenness(after) > E.evenness(pts),
		string.format("%.2f -> %.2f", E.evenness(pts), E.evenness(after))
	)

	-- no hole: crowded copies have nowhere to go; they stay, or go when asked
	local full = grid({})
	table.insert(full, { x = 51, z = 50, r = 2 })
	local stay = E.relayout(full, spots, { spacing = 10, step = 2, seed = 3 })
	local go = E.relayout(full, spots, { spacing = 10, step = 2, seed = 3, remove = true })
	check("no hole: extras stay unless asked to go", #stay.moves == 0 and #stay.removes == 0 and #go.removes == 1)
	-- a natural, uneven forest has no holes: nothing to add
	local natural = E.relayout(grid({ jitter = 6 }), spots, { spacing = E.typicalSpacing(grid({ jitter = 6 })), step = 2, fill = true, seed = 3 })
	check(
		"an uneven but full forest is left alone",
		#natural.adds == 0 and #natural.moves == 0,
		string.format("%d adds, %d moves", #natural.adds, #natural.moves)
	)
	-- no spots (the rules allow nowhere): nothing moves anywhere
	local nowhere = E.relayout(pts, {}, { spacing = 10, step = 2, fill = true })
	check("where the rules allow nothing, nothing moves", #nowhere.moves == 0 and #nowhere.adds == 0)
end

-- ── path shapes and subdivide ───────────────────────────────────────────────────────────
do
	local c = Vector3.new(10, 5, 20)
	-- a hexagon from its centre: six corners, all as far out as the mouse, one right under it
	local hex, smooth = E.shapePoints("Hexagon", c, Vector3.new(30, 5, 20))
	local round = #hex == 6 and not smooth
	for _, p in hex do
		round = round and near((p - c).Magnitude, 20, 1e-6) and p.Y == 5
	end
	check("a hexagon: six sharp corners round its centre", round and near(hex[1].X, 30, 1e-6) and near(hex[1].Z, 20, 1e-6))
	-- the turn snaps to 15° steps, unless free
	local sq = E.shapePoints("Square", c, c + Vector3.new(math.cos(math.rad(47)), 0, math.sin(math.rad(47))) * 10)
	local turn = math.deg(math.atan2(sq[1].Z - c.Z, sq[1].X - c.X))
	local free = E.shapePoints("Square", c, c + Vector3.new(math.cos(math.rad(47)), 0, math.sin(math.rad(47))) * 10, true)
	local freeTurn = math.deg(math.atan2(free[1].Z - c.Z, free[1].X - c.X))
	check(
		"a shape turns in 15° steps, or freely",
		#sq == 4 and near(turn, 45, 1e-6) and near(freeTurn, 47, 1e-6),
		string.format("%.2f / %.2f", turn, freeTurn)
	)
	-- the rectangle goes corner to corner; the circle is smooth
	local rect = E.shapePoints("Rectangle", Vector3.new(0, 0, 0), Vector3.new(40, 3, 10))
	check("a rectangle: corner to corner", #rect == 4 and rect[3].X == 40 and rect[3].Z == 10 and rect[2].Z == 0 and rect[3].Y == 0)
	local _, circle = E.shapePoints("Circle", c, c + Vector3.xAxis * 8)
	check("a circle is smooth", circle == true)

	-- subdivide: a point halfway along each side, the shape unchanged
	local function curve(list, closed, sharp)
		local pts = {}
		for _, p in list do
			table.insert(pts, { p = p, n = Vector3.yAxis, sharp = sharp or nil })
		end
		return { pts = pts, closed = closed }
	end
	local square = curve(E.shapePoints("Rectangle", Vector3.new(0, 0, 0), Vector3.new(20, 0, 20)), true, true)
	local added = E.subdivide(square)
	local mid = square.pts[2]
	check(
		"subdividing a closed square adds one point per side, on the side",
		added == 4 and #square.pts == 8 and near(mid.p.X, 10, 1e-6) and near(mid.p.Z, 0, 1e-6) and mid.sharp == true,
		string.format("%d added, mid at %.2f, %.2f", added, mid.p.X, mid.p.Z)
	)
	local open = curve({ Vector3.new(0, 0, 0), Vector3.new(10, 0, 0), Vector3.new(20, 0, 10) }, false)
	local before = E.splineCurve(open, 0.25)
	E.subdivide(open)
	local worst = 0
	for _, p in E.splineCurve(open, 0.25) do -- every point of the new curve lies on the old one
		local best = math.huge
		for _, q in before do
			best = math.min(best, (p - q).Magnitude)
		end
		worst = math.max(worst, best)
	end
	check("subdividing an open curve adds a point per stretch and keeps its shape", #open.pts == 5 and worst < 0.6, string.format("%.3f off", worst))
	-- a bent (Bezier) stretch splits exactly
	local bent = curve({ Vector3.new(0, 0, 0), Vector3.new(20, 0, 0) }, false)
	bent.pts[1].h = Vector3.new(4, 0, 8)
	local want = E.splineCurve(bent, 1)
	E.subdivide(bent)
	local P = E.splineCurve(bent, 0.5)
	local off = 0
	for _, q in want do
		local best = math.huge
		for _, p in P do
			best = math.min(best, (p - q).Magnitude)
		end
		off = math.max(off, best)
	end
	check("subdividing a bent stretch keeps the bend", #bent.pts == 3 and off < 0.35, string.format("%.3f off", off))

	-- a loop of its own in a path network: drawn closed
	local net = { pts = { { p = Vector3.new(0, 0, 0), n = Vector3.yAxis }, { p = Vector3.new(10, 0, 0), n = Vector3.yAxis } }, closed = false }
	net.branches = { curve(E.shapePoints("Triangle", Vector3.new(50, 0, 50), Vector3.new(60, 0, 50)), true, true) }
	local cvs = E.splineCurves(net)
	check("a shape added to a path is its own closed loop", #cvs == 2 and cvs[2].closed == true and cvs[1].closed == false)
	-- a branch's end dropped on its own start closes it too
	local br = curve({ Vector3.new(0, 0, 0), Vector3.new(10, 0, 0), Vector3.new(10, 0, 10), Vector3.new(0, 0, 10), Vector3.new(0, 0, 0.01) }, false)
	local how = E.joinToPoint(net, { cv = br, i = 5 }, { cv = br, i = 1 })
	check("a branch closes into a loop like the main curve", how == "closed" and br.closed == true and #br.pts == 4)
end

-- ── stamps: pins that keep their turn, size and model ──────────────────────────────────────
do
	local p = E.stampPin(10.123, -4.567, -math.pi / 2, 1.23456, 2, 77)
	check(
		"a stamp's pin keeps its spot, turn (0 to a full turn), size and model",
		p[1] == 10.12 and p[2] == -4.57 and p[3] == 77 and near(p[4], 3 * math.pi / 2, 1e-3) and p[5] == 1.235 and p[6] == 2
	)
	local back = E.readPins({ p, { 1, 2, 3 }, { 1, 2 }, { 4, 5, 6, 0.5 } })
	check(
		"saved pins read back: stamps whole, plain pins as three numbers, broken ones dropped",
		#back == 3 and back[1][6] == 2 and back[1][5] == 1.235 and back[2][4] == nil and back[3][4] == nil,
		#back .. " pins"
	)
	check("a stamp's size stays sensible", E.stampPin(0, 0, 0, 0, 1, 1)[5] == 0.05 and E.stampPin(0, 0, 0, 99, 1, 1)[5] == 20)
end

-- ── report ──────────────────────────────────────────────────────────────────────────
if #failed > 0 then
	print(table.concat(failed, "\n"))
	error(string.format("offline engine tests: %d failed, %d passed", #failed, passed), 0)
end
print(string.format("offline engine tests: %d passed", passed))
