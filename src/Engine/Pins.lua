--[[
	Smart Scatter — Engine/Pins: copies put down by hand with the object brush. Each is a pin on its object
	(l.pins = { { x, z, seed }, … }, saved with the area like the object's painting): generating places the pins
	first, on their exact spots, under the object's rules (surfaces, slope, spacing), then fills in the rest as usual.
	A pin's seed picks its model, size and turn, so it looks the same every time.
	A stamp (from 9.70 to 9.77, when stamps belonged to an area) is a pin that also says its turn, size and model
	({ x, z, seed, yaw, size, model }): it's put exactly so, no rule moves or refuses it; only the ground sets its height.
	Saved ones keep coming back; the stamp tool now makes plain models of its own (App's Viewport/Stamp).
	Adds to E (the engine API); shares internals with the other engine modules through I.
]]

return function(E, I)
	local placeAt = I.placeAt
	local scaleRange = I.scaleRange

	-- how far apart two pins of an object stay: its usual spacing, at its average size
	local function pinSpacing(l)
		local lo, hi = scaleRange(l)
		return math.max(l.m.radius * (lo + hi) / 2 * l.s.spacing * 2, 1)
	end
	E.pinSpacing = pinSpacing

	local function roomFor(l, x, z, gap)
		for _, p in l.pins or {} do
			local dx, dz = p[1] - x, p[2] - z
			if dx * dx + dz * dz < gap * gap then
				return false
			end
		end
		return true
	end

	-- One dab of the brush at (x, z), radius R: drops pins on the area's painted ground, as many as the brush has
	-- room for at the object's spacing, never closer than that to another pin. rng: where in the brush they land.
	-- Returns the pins added.
	function E.brushPins(a, l, x, z, R, rng)
		l._size = a.size or 1 -- ("Size of everything", as generating sets it)
		local gap = pinSpacing(l)
		local want = math.clamp(math.floor(R * R / (gap * gap) * 0.9), 1, 40)
		local added = {}
		for _ = 1, want * 4 do
			if #added >= want then
				break
			end
			local ang, d = rng:NextNumber() * math.pi * 2, math.sqrt(rng:NextNumber()) * R
			local px, pz = x + math.cos(ang) * d, z + math.sin(ang) * d
			if E.hasCell(a, math.floor(px / a.cell), math.floor(pz / a.cell)) and roomFor(l, px, pz, gap) then
				local pin = { math.floor(px * 100 + 0.5) / 100, math.floor(pz * 100 + 0.5) / 100, rng:NextInteger(1, 2 ^ 30) }
				l.pins = l.pins or {}
				table.insert(l.pins, pin)
				table.insert(added, pin)
			end
		end
		return added
	end

	-- removes the object's pins within R of (x, z); returns how many
	function E.erasePins(l, x, z, R)
		local n, keep = 0, {}
		for _, p in l.pins or {} do
			local dx, dz = p[1] - x, p[2] - z
			if dx * dx + dz * dz <= R * R then
				n += 1
			else
				table.insert(keep, p)
			end
		end
		l.pins = #keep > 0 and keep or nil
		return n
	end

	-- the pin a placed copy came from, taken off its object (a pinned copy removed by hand stays gone)
	function E.unpin(l, x, z)
		for k, p in l.pins or {} do
			if math.abs(p[1] - x) < 0.05 and math.abs(p[2] - z) < 0.05 then
				table.remove(l.pins, k)
				if #l.pins == 0 then
					l.pins = nil
				end
				return true
			end
		end
		return false
	end

	-- pins as saved: plain lists of three numbers, or six for a stamp (anything else is dropped)
	function E.readPins(list)
		local out = {}
		for _, p in type(list) == "table" and list or {} do
			if type(p) == "table" and tonumber(p[1]) and tonumber(p[2]) and tonumber(p[3]) then
				local pin = { tonumber(p[1]), tonumber(p[2]), tonumber(p[3]) }
				if tonumber(p[4]) and tonumber(p[5]) and tonumber(p[6]) then
					pin[4], pin[5], pin[6] = tonumber(p[4]), tonumber(p[5]), tonumber(p[6])
				end
				table.insert(out, pin)
			end
		end
		return #out > 0 and out or nil
	end

	-- a stamp's pin: at (x, z), turned yaw (radians), size k (1 = the model's own size, times its size in the mix),
	-- model index vi of the object's models; seed: its colour variation
	function E.stampPin(x, z, yaw, k, vi, seed)
		local r = function(n, q)
			return math.floor(n * q + 0.5) / q
		end
		return { r(x, 100), r(z, 100), seed, r(yaw % (math.pi * 2), 1000), r(math.clamp(k, 0.05, 20), 1000), vi }
	end
	-- how placing treats a pin: a stamp exactly as given
	local function pinG(l, p)
		if not p[4] then
			return { pin = true }
		end
		local v = l.variants[p[6]] or l.variants[1]
		return { pin = true, exact = true, yaw = p[4], v = v, sc = p[5] * v.size }
	end

	-- Places the object's pins (those `wanted(x, z)` accepts: all of them, or the ones in a rebuilt patch). Each
	-- uses its own random numbers, so the object's other copies draw theirs exactly as they would without pins.
	-- Returns how many were placed.
	function I.placePins(ctx, l, wanted)
		local n = 0
		for _, p in l.pins or {} do
			if not wanted or wanted(p[1], p[2]) then
				if placeAt(ctx, l, nil, p[1], p[2], Random.new(p[3]), pinG(l, p)) then
					n += 1
				end
			end
		end
		return n
	end
end
