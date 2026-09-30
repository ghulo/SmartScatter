--[[
	Smart Scatter — Engine/Pins: copies put down by hand with the object brush. Each is a pin on its object
	(l.pins = { { x, z, seed }, … }, saved with the area like the object's painting): generating places the pins
	first, on their exact spots, under the object's rules (surfaces, slope, spacing), then fills in the rest as usual.
	A pin's seed picks its model, size and turn, so it looks the same every time.
	A stamp (from 9.70 to 9.77, when stamps belonged to an area) is a pin that also says its turn, size and model
	({ x, z, seed, yaw, size, model }): it's put exactly so, no rule moves or refuses it; only the ground sets its height.
	A seventh number, 1, marks a stamp standing in for a copy the rules placed (one changed by hand, below): those go
	down after the rules' own copies, so the layout round them is what it was.
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
					pin[7] = tonumber(p[7]) == 1 and 1 or nil
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
	--------------------------------------------------------------------------------
	-- One placed copy, changed by hand. A copy the rules placed has nothing of its own to change, so the first change
	-- makes it a stamp's pin standing as it stood (its spot is remembered as removed, so the rules don't put theirs
	-- back beside it), and changes after that are changes to the pin. Generating puts it back exactly so.
	--------------------------------------------------------------------------------
	local function near(p, x, z)
		return math.abs(p[1] - x) < 0.05 and math.abs(p[2] - z) < 0.05
	end
	-- the object a placed copy is of (by its output folder), or nil
	local function layerOfCopy(a, copy)
		local cur = copy.Parent
		while cur and cur ~= a.folder do
			local key = cur:GetAttribute("SS_Key")
			if key then
				for _, l in a.layers do
					if E.layerKey(l) == key then
						return l
					end
				end
				return nil
			end
			cur = cur.Parent
		end
		return nil
	end
	-- How a placed copy stands, as a stamp's pin would say it: { l = its object, vi = which of its models, x, z,
	-- yaw (radians), k (size, 1 = the model's own), pin = its pin when it's a stamp already }. nil for a copy that
	-- can't be one (a piece of a line, one stacked on another, a preview box).
	function E.copyPose(a, copy)
		local l = layerOfCopy(a, copy)
		local x, z = copy:GetAttribute("SS_X"), copy:GetAttribute("SS_Z")
		if not (l and x and z) or E.isLine(l) or copy:GetAttribute("SS_Stacked") or copy:GetAttribute("SS_Ghost") then
			return nil
		end
		if copy:GetAttribute("SS_Stamp") then
			for _, p in l.pins or {} do
				if p[4] and near(p, x, z) then
					return { l = l, vi = l.variants[p[6]] and p[6] or 1, x = p[1], z = p[2], yaw = p[4], k = p[5], pin = p }
				end
			end
		end
		local vi = 1
		for i, v in l.variants do
			if v.inst.Name == copy.Name then
				vi = i
				break
			end
		end
		local v = l.variants[vi]
		local from = v.src or v.inst
		local sc
		if copy:IsA("Model") and from:IsA("Model") then
			sc = copy:GetScale() / from:GetScale()
		elseif copy:IsA("BasePart") and from:IsA("BasePart") then
			sc = copy.Size.X / math.max(from.Size.X, 1e-3)
		else
			return nil
		end
		local _, yaw = (copy:GetPivot() * v.m.rel:Inverse()):ToOrientation()
		return { l = l, vi = vi, x = x, z = z, yaw = yaw % (math.pi * 2), k = math.clamp(sc / v.size, 0.05, 20) }
	end
	-- a stamp's pin changed in place: change = { x, z, yaw, k, vi }, each optional
	function E.changePin(l, pin, change)
		local vi = l.variants[change.vi or 0] and change.vi or pin[6]
		local new = E.stampPin(change.x or pin[1], change.z or pin[2], change.yaw or pin[4], change.k or pin[5], vi, pin[3])
		pin[1], pin[2], pin[4], pin[5], pin[6] = new[1], new[2], new[4], new[5], new[6]
		return pin
	end
	-- Changes one placed copy: change = { x, z, yaw, k, vi }, each optional (what's left out stays as it stands). The
	-- copy itself is taken out (the caller rebuilds the spot, which puts the pin's copy there); returns the pin and
	-- the pose it had, or nil for a copy that can't be changed.
	function E.pinCopy(a, copy, change)
		local was = E.copyPose(a, copy)
		if not was then
			return nil
		end
		local l = was.l
		local pin = was.pin
		if pin then
			E.changePin(l, pin, change)
			E.dropOutput(copy)
		else
			local vi = l.variants[change.vi or 0] and change.vi or was.vi
			local new = E.stampPin(change.x or was.x, change.z or was.z, change.yaw or was.yaw, change.k or was.k, vi, 0)
			-- (its seed: its colour variation, from where it stood, so the same copy changed twice looks the same)
			new[3] = math.floor(math.abs(was.x * 7919 + was.z * 104729)) % 2 ^ 30 + 1
			if not copy:GetAttribute("SS_Pin") then
				new[7] = 1 -- (it stands in for a rules' copy)
			end
			E.removeCopy(a, copy) -- a rules' copy: its spot stays empty · one sprayed by hand: its plain pin goes
			l.pins = l.pins or {}
			table.insert(l.pins, new)
			pin = new
		end
		return pin, was
	end
	-- A changed copy given back to the rules: its pin goes, and the spot it was first taken from is free again (the
	-- rules' own copy comes back there on the next rebuild). false for one that was never the rules' (or was moved).
	function E.canUnpinCopy(a, copy)
		local pose = E.copyPose(a, copy)
		return pose ~= nil and pose.pin ~= nil and E.removedAt(a, copy:GetAttribute("SS_L") or 0, pose.x, pose.z)
	end
	function E.unpinCopy(a, copy)
		if not E.canUnpinCopy(a, copy) then
			return false
		end
		local pose = E.copyPose(a, copy)
		local h = copy:GetAttribute("SS_L")
		local keep = {}
		for _, p in a.removed[h] do
			if not (math.abs(p[1] - pose.x) < 0.3 and math.abs(p[2] - pose.z) < 0.3) then
				table.insert(keep, p)
			end
		end
		a.removed[h] = #keep > 0 and keep or nil
		E.unpin(pose.l, pose.x, pose.z)
		E.dropOutput(copy)
		return true
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
	-- late: false for the pins put down by hand (before the rules' copies, which keep their distance from them), true
	-- for the ones standing in for a rules' copy (after them). stampsOnly: the plain pins are left out (their copies
	-- were kept). Returns how many were placed.
	function I.placePins(ctx, l, wanted, late, stampsOnly)
		local n = 0
		for _, p in l.pins or {} do
			if (p[7] == 1) == late and (p[4] or not stampsOnly) and (not wanted or wanted(p[1], p[2])) then
				if placeAt(ctx, l, nil, p[1], p[2], Random.new(p[3]), pinG(l, p)) then
					n += 1
				end
			end
		end
		return n
	end
end
