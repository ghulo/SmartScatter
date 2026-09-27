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

-- ── report ──────────────────────────────────────────────────────────────────────────
if #failed > 0 then
	print(table.concat(failed, "\n"))
	error(string.format("offline engine tests: %d failed, %d passed", #failed, passed), 0)
end
print(string.format("offline engine tests: %d passed", passed))
