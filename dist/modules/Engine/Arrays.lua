--[[
	Smart Scatter — Engine/Arrays: one model repeated in a pattern, like Blender's Array modifier (and its Curve one).
	Plain maths: from an array's settings, where each copy stands (a position and a heading, relative to the array's
	origin, or in the world along a path) and how big it is. The plugin makes the copies (App's Panel/ArrayTools); nothing here touches
	the world, so it's checked by the offline tests.
	Settings (s): shape "Line" | "Grid" | "Circle" | "Path"
	  Line   count, spacing                      copies in a row down the origin's front (-Z)
	  Grid   rows, cols, spacingX, spacingZ      rows down the front, columns to the right
	  Circle count, radius, face "Out"|"In"|"Keep" round the origin
	  Path   count, spacing, pathMode "Count"|"Spacing"   along a path's curve (samples given), facing along it
	  every shape: yawStep (degrees added per copy), yawJitter (± degrees), scaleJitter (± share), posJitter (± studs),
	  seed, scale
	Adds to E (the engine API); shares internals with the other engine modules through I.
]]

return function(E)
	E.ARRAY_SHAPES = { "Line", "Grid", "Circle", "Path" }
	E.ARRAY_FACES = { "Out", "In", "Keep" }
	local MAX = 1000 -- copies in one array at most (a slider can't make Studio stall)

	-- the settings an array starts with, and what's missing from saved ones filled in
	function E.arrayDefaults(s)
		local d = {
			shape = "Line",
			count = 6,
			spacing = 8,
			rows = 3,
			cols = 3,
			spacingX = 8,
			spacingZ = 8,
			radius = 20,
			face = "Out",
			pathMode = "Count",
			yawStep = 0,
			yawJitter = 0,
			scaleJitter = 0,
			posJitter = 0,
			seed = 1,
			scale = 1,
			ground = true,
			lift = 0,
		}
		for k, v in s or {} do
			if d[k] ~= nil and type(v) == type(d[k]) then
				d[k] = v
			end
		end
		d.count = math.clamp(math.floor(d.count), 1, MAX)
		d.rows = math.clamp(math.floor(d.rows), 1, 100)
		d.cols = math.clamp(math.floor(d.cols), 1, 100)
		while d.rows * d.cols > MAX do
			d.rows -= 1
		end
		return d
	end

	-- points along a sampled curve (a list of Vector3, in order) at the given distances from its start: position and
	-- the flat direction it runs there. The curve's length comes back too.
	local function along(P, dists)
		local cum = { 0 }
		for k = 2, #P do
			cum[k] = cum[k - 1] + (P[k] - P[k - 1]).Magnitude
		end
		local out, seg = {}, 2
		for _, d in dists do
			while seg < #P and cum[seg] < d do
				seg += 1
			end
			local a, b = P[seg - 1] or P[1], P[seg] or P[1]
			local len = cum[seg] - (cum[seg - 1] or 0)
			local t = len > 1e-6 and math.clamp((d - (cum[seg - 1] or 0)) / len, 0, 1) or 0
			local dir = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
			table.insert(out, { p = a:Lerp(b, t), dir = dir.Magnitude > 1e-4 and dir.Unit or Vector3.new(0, 0, -1) })
		end
		return out, cum[#P] or 0
	end
	E.arrayAlong = along

	-- the heading (radians about the vertical, 0 = facing -Z, Roblox's front) of a flat direction
	local function heading(dir)
		return math.atan2(-dir.X, -dir.Z)
	end

	-- Where each copy stands: { { pos = Vector3, yaw = radians, scale = number } }. In the array's own space (its
	-- origin at 0, facing -Z) for Line, Grid and Circle; in the world for Path (P: the path's curve, sampled; closed: a
	-- loop). yaw is its heading with its own turn (yawStep, jitter) added. The same settings give the same copies.
	function E.arrayCopies(s, P, closed)
		s = E.arrayDefaults(s)
		local rng = Random.new(math.floor(s.seed) * 7919 + 17)
		local spots = {} -- { pos, yaw } before each copy's own turn
		if s.shape == "Line" then
			for i = 0, s.count - 1 do
				table.insert(spots, { Vector3.new(0, 0, -i * s.spacing), 0 })
			end
		elseif s.shape == "Grid" then
			for r = 0, s.rows - 1 do
				for c = 0, s.cols - 1 do
					table.insert(spots, { Vector3.new(c * s.spacingX, 0, -r * s.spacingZ), 0 })
				end
			end
		elseif s.shape == "Circle" then
			for i = 0, s.count - 1 do
				local a = i / s.count * math.pi * 2
				local p = Vector3.new(math.sin(a) * s.radius, 0, -math.cos(a) * s.radius)
				local yaw = 0
				if s.face == "Out" then -- its front away from the centre
					yaw = heading(p)
				elseif s.face == "In" then
					yaw = heading(Vector3.zero - p)
				end
				table.insert(spots, { p, yaw })
			end
		elseif s.shape == "Path" and P and #P >= 2 then
			local _, len = along(P, {})
			local dists = {}
			if s.pathMode == "Spacing" then
				local n = math.min(math.floor(len / math.max(s.spacing, 0.1)) + 1, MAX)
				for i = 0, n - 1 do
					table.insert(dists, i * s.spacing)
				end
			else
				local n = s.count
				for i = 0, n - 1 do -- (a loop spaces them all round; an open path puts one at each end)
					table.insert(dists, n == 1 and 0 or len * i / (closed and n or (n - 1)))
				end
			end
			for _, pt in along(P, dists) do
				table.insert(spots, { pt.p, heading(pt.dir) })
			end
		end
		local out = {}
		for i, spot in spots do
			local yaw = spot[2] + math.rad(s.yawStep * (i - 1) + (s.yawJitter > 0 and rng:NextNumber(-s.yawJitter, s.yawJitter) or 0))
			local scale = s.scale * (1 + (s.scaleJitter > 0 and rng:NextNumber(-s.scaleJitter, s.scaleJitter) or 0))
			local nudge = s.posJitter > 0 and Vector3.new(rng:NextNumber(-s.posJitter, s.posJitter), 0, rng:NextNumber(-s.posJitter, s.posJitter))
				or Vector3.zero
			table.insert(out, { pos = spot[1] + nudge, yaw = yaw, scale = math.max(scale, 0.05) })
		end
		return out
	end
end
