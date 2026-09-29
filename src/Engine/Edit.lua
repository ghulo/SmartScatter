--[[
	Smart Scatter — Engine/Edit: the maths of the editing helpers (App's Panel/EditTools): lining things up, spacing
	them evenly, and random turns and sizes. Plain numbers in, plain moves out; nothing here touches the world, so the
	offline tests check it.
	A box is { min = Vector3, max = Vector3 } (something's extent in the world); an axis is "X", "Y" or "Z".
	Adds to E (the engine API); shares internals with the other engine modules through I.
]]

return function(E)
	local function comp(v, axis)
		return axis == "X" and v.X or axis == "Y" and v.Y or v.Z
	end
	local function along(axis, d)
		return axis == "X" and Vector3.new(d, 0, 0) or axis == "Y" and Vector3.new(0, d, 0) or Vector3.new(0, 0, d)
	end

	-- Aligns boxes on an axis to the selection's own extent there: "Min" (all start where the lowest starts), "Center"
	-- (all centred on its middle) or "Max". Returns the move for each box.
	function E.alignMoves(boxes, axis, where)
		local lo, hi = math.huge, -math.huge
		for _, b in boxes do
			lo, hi = math.min(lo, comp(b.min, axis)), math.max(hi, comp(b.max, axis))
		end
		local out = {}
		for i, b in boxes do
			local a, z = comp(b.min, axis), comp(b.max, axis)
			local d = where == "Min" and lo - a or where == "Max" and hi - z or (lo + hi) / 2 - (a + z) / 2
			out[i] = along(axis, d)
		end
		return out
	end

	-- Spreads boxes evenly on an axis between the two outermost (which stay put): "Centers" (the same distance centre
	-- to centre) or "Gaps" (the same empty space between neighbours). Returns the move for each box.
	function E.distributeMoves(boxes, axis, mode)
		local out, order = {}, {}
		for i in boxes do
			out[i] = Vector3.zero
			table.insert(order, i)
		end
		if #order < 3 then
			return out
		end
		local function mid(i)
			return (comp(boxes[i].min, axis) + comp(boxes[i].max, axis)) / 2
		end
		table.sort(order, function(a, b)
			return mid(a) < mid(b)
		end)
		local n = #order
		if mode == "Gaps" then
			local total, span = 0, comp(boxes[order[n]].max, axis) - comp(boxes[order[1]].min, axis)
			for _, i in order do
				total += comp(boxes[i].max, axis) - comp(boxes[i].min, axis)
			end
			local gap = (span - total) / (n - 1)
			local at = comp(boxes[order[1]].max, axis) + gap
			for k = 2, n - 1 do
				local i = order[k]
				out[i] = along(axis, at - comp(boxes[i].min, axis))
				at += comp(boxes[i].max, axis) - comp(boxes[i].min, axis) + gap
			end
		else
			local first, last = mid(order[1]), mid(order[n])
			for k = 2, n - 1 do
				local i = order[k]
				out[i] = along(axis, first + (last - first) * (k - 1) / (n - 1) - mid(i))
			end
		end
		return out
	end

	-- A random turn (radians, up to ± turn degrees) and size (× 1 ± size) for each of n things; the same seed gives
	-- the same ones
	function E.randomTurns(n, turn, size, seed)
		local rng = Random.new(math.floor(seed or 1) * 104729 + 3)
		local out = {}
		for i = 1, n do
			out[i] = {
				yaw = turn > 0 and math.rad(rng:NextNumber(-turn, turn)) or 0,
				scale = size > 0 and math.max(1 + rng:NextNumber(-size, size), 0.05) or 1,
			}
		end
		return out
	end
end
