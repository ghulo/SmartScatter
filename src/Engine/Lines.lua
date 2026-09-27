--[[
	Smart Scatter — Engine/Lines: copies following an edge or a path (roads, water, houses, fences end to end).
	Adds to E (the engine API); shares internals with the other engine modules through I.
]]

return function(E, I)
	local FOLLOW_FIELD = I.FOLLOW_FIELD
	local FRONT_YAW = I.FRONT_YAW
	local Hash = I.Hash
	local alongXOf = I.alongXOf
	local capInfo = I.capInfo
	local emit = I.emit
	local fillJoint = I.fillJoint
	local frontOf = I.frontOf
	local groupId = I.groupId
	local lengthOf = I.lengthOf
	local mitre = I.mitre
	local overhangYaw = I.overhangYaw
	local pickVariant = I.pickVariant
	local placeAt = I.placeAt
	local project = I.project
	local scaleRange = I.scaleRange

	--------------------------------------------------------------------------------
	-- Lines: copies following an edge (roads, paths, water, houses, the area border)
	--------------------------------------------------------------------------------
	-- Contour of the distance field at `target` (marching squares on the scan grid), linked into polylines,
	-- then resampled and smoothed so blocky paint edges and grid steps become clean curves.
	-- Returns { { pts = { {x,z}, ... }, closed = bool }, ... }
	local function traceLines(an, f, target, anyMask)
		local nx, nz, G, x0, z0 = an.nx, an.nz, an.G, an.x0, an.z0
		local function v(ix, iz)
			return f[iz * nx + ix + 1] - target
		end
		local function inside(ix, iz)
			return an.inM[iz * nx + ix + 1]
		end
		local function px(ix)
			return x0 + (ix + 0.5) * G
		end
		local function pz(iz)
			return z0 + (iz + 0.5) * G
		end
		-- edge ids: horizontal edge from (ix,iz)->(ix+1,iz) = 2*node, vertical (ix,iz)->(ix,iz+1) = 2*node+1
		local pos, links = {}, {}
		local function edgePoint(ix, iz, vertical)
			local id = (iz * nx + ix) * 2 + (vertical and 1 or 0)
			if not pos[id] then
				local a = v(ix, iz)
				local jx, jz = vertical and ix or ix + 1, vertical and iz + 1 or iz
				local b = v(jx, jz)
				local t = math.clamp(a / (a - b), 0, 1)
				pos[id] = { px(ix) + (px(jx) - px(ix)) * t, pz(iz) + (pz(jz) - pz(iz)) * t }
			end
			return id
		end
		-- corners on the open side of the line must be in the area (the near side may be outside it for Border)
		local function ok(val, jx, jz)
			return inside(jx, jz) or (anyMask and val < 0)
		end
		local function link(a, b)
			links[a] = links[a] or {}
			table.insert(links[a], b)
			links[b] = links[b] or {}
			table.insert(links[b], a)
		end
		for iz = 0, nz - 2 do
			for ix = 0, nx - 2 do
				local a, b, c, d = v(ix, iz), v(ix + 1, iz), v(ix + 1, iz + 1), v(ix, iz + 1)
				if ok(a, ix, iz) and ok(b, ix + 1, iz) and ok(c, ix + 1, iz + 1) and ok(d, ix, iz + 1) then
					if math.max(a, b, c, d) < 1e8 then
						local code = (a < 0 and 1 or 0) + (b < 0 and 2 or 0) + (c < 0 and 4 or 0) + (d < 0 and 8 or 0)
						if code ~= 0 and code ~= 15 then
							local S = function()
								return edgePoint(ix, iz, false)
							end -- bottom edge a-b
							local E_ = function()
								return edgePoint(ix + 1, iz, true)
							end -- right edge b-c
							local N = function()
								return edgePoint(ix, iz + 1, false)
							end -- top edge d-c
							local W = function()
								return edgePoint(ix, iz, true)
							end -- left edge a-d
							if code == 1 or code == 14 then
								link(S(), W())
							elseif code == 2 or code == 13 then
								link(S(), E_())
							elseif code == 3 or code == 12 then
								link(W(), E_())
							elseif code == 4 or code == 11 then
								link(E_(), N())
							elseif code == 6 or code == 9 then
								link(S(), N())
							elseif code == 7 or code == 8 then
								link(W(), N())
							elseif code == 5 or code == 10 then -- saddle: decide by the centre
								local mid = (a + b + c + d) / 4
								if (mid < 0) == (code == 5) then
									link(S(), E_())
									link(W(), N())
								else
									link(S(), W())
									link(E_(), N())
								end
							end
						end
					end
				end
			end
		end
		-- walk the links into polylines (open ends first)
		local used, lines = {}, {}
		local function other(id, from)
			for _, n in links[id] do
				if n ~= from and not used[id .. ":" .. n] then
					return n
				end
			end
			return nil
		end
		local function walk(start)
			local pts, prev, cur = { pos[start] }, nil, start
			while true do
				local nxt = other(cur, prev)
				if not nxt then
					break
				end
				used[cur .. ":" .. nxt] = true
				used[nxt .. ":" .. cur] = true
				if nxt == start then
					return pts, true
				end
				table.insert(pts, pos[nxt])
				prev, cur = cur, nxt
			end
			return pts, false
		end
		local ids = {}
		for id in links do
			table.insert(ids, id)
		end
		table.sort(ids) -- deterministic
		local seen = {}
		local function mark(pts)
			for _, p in pts do
				seen[p] = true
			end
		end
		for _, id in ids do
			if #links[id] == 1 and not seen[pos[id]] then
				local pts, closed = walk(id)
				mark(pts)
				table.insert(lines, { pts = pts, closed = closed })
			end
		end
		for _, id in ids do
			if not seen[pos[id]] then
				local pts, closed = walk(id)
				mark(pts)
				table.insert(lines, { pts = pts, closed = closed })
			end
		end
		-- resample every ~G/2 and smooth (grid stairs and 8-stud paint steps become curves)
		local out = {}
		for _, ln in lines do
			local P = ln.pts
			if ln.closed then
				table.insert(P, P[1])
			end
			local len = 0
			for k = 2, #P do
				len += math.sqrt((P[k][1] - P[k - 1][1]) ^ 2 + (P[k][2] - P[k - 1][2]) ^ 2)
			end
			if len >= G * 1.5 then
				local step = G * 0.5
				local R, k, acc = { { P[1][1], P[1][2] } }, 2, 0
				local want = step
				local cx, cz = P[1][1], P[1][2]
				while k <= #P do
					local dx, dz = P[k][1] - cx, P[k][2] - cz
					local seg = math.sqrt(dx * dx + dz * dz)
					if acc + seg >= want and seg > 1e-6 then
						local t = (want - acc) / seg
						cx, cz = cx + dx * t, cz + dz * t
						table.insert(R, { cx, cz })
						acc, want = 0, step
					else
						acc += seg
						cx, cz = P[k][1], P[k][2]
						k += 1
					end
				end
				if not ln.closed then
					table.insert(R, { P[#P][1], P[#P][2] })
				elseif #R > 2 then
					table.remove(R)
				end
				local n = #R
				for _ = 1, 8 do -- Laplacian smoothing, ends pinned on open lines
					local S2 = table.create(n)
					for i = 1, n do
						local a, b
						if ln.closed then
							a, b = R[(i - 2) % n + 1], R[i % n + 1]
						elseif i == 1 or i == n then
							S2[i] = R[i]
							continue
						else
							a, b = R[i - 1], R[i + 1]
						end
						S2[i] = { R[i][1] * 0.5 + (a[1] + b[1]) * 0.25, R[i][2] * 0.5 + (a[2] + b[2]) * 0.25 }
					end
					R = S2
				end
				if ln.closed then
					table.insert(R, { R[1][1], R[1][2] })
				end
				table.insert(out, { pts = R, closed = ln.closed })
			end
		end
		return out
	end

	-- lines never run across a road, path, water or a building: that's where they open up (gates, crossings)
	local BLOCKS_LINE = { Road = true, Dirt = true, Water = true, Building = true }

	-- "Leave gaps": stretches of kept copies with openings between them (a broken fence, gaps in a hedge), not a
	-- coin toss per copy. skip = the share left out. gapMask gives a keep flag per piece for end-to-end runs and never
	-- leaves a lone piece standing; gapper streams flags for spaced copies.
	local function gapper(skip, rng)
		if skip <= 0 then
			return function()
				return true
			end
		end
		skip = math.min(skip, 0.95)
		local runMean, gapMean = 4, 4 * skip / (1 - skip)
		if gapMean < 1 then
			gapMean, runMean = 1, (1 - skip) / skip
		end
		local keeping, left = true, rng:NextInteger(1, math.max(math.floor(runMean * 1.4 + 0.5), 1))
		return function()
			while left <= 0 do
				keeping = not keeping
				left = keeping and math.max(math.floor(runMean * rng:NextNumber(0.6, 1.4) + 0.5), 1)
					or math.max(math.floor(gapMean * rng:NextNumber(0.5, 1.5) + 0.5), 1)
			end
			left -= 1
			return keeping
		end
	end
	local function gapMask(n, skip, rng)
		local mask, nextKeep = table.create(n), gapper(skip, rng)
		for k = 1, n do
			mask[k] = nextKeep()
		end
		if skip > 0 and n > 2 then
			for k = 1, n do -- a single piece between two openings looks like a mistake: drop it
				if mask[k] and not mask[k - 1] and not mask[k + 1] then
					mask[k] = false
				end
			end
		end
		return mask
	end

	-- Breaks a curve into end-to-end pieces for straight models (fences, walls, rails). Each piece is a chord of the
	-- curve. Piece length flows smoothly with the curve: full length on straights, gradually shorter into a bend (only as
	-- short as that bend needs), and every run between corners is split evenly so it starts and ends on a joint.
	-- at(d) -> Vector3 on the curve at arc length d. Returns { { d0, d1 }, ... }.
	-- halfW (optional): half the piece's width across the line. A wide piece (a path tile) is a chord of the curve, and
	-- its outer edge bows out further than its centre line does (by halfW / radius), so wide pieces are judged at the edge.
	local function fitPieces(total, at3, pieceL, joints, halfW)
		if total < 0.05 then
			return {}
		end
		halfW = halfW or 0
		-- bends are judged on the ground plane: a kerb or a step in the ground is not a bend
		local function at(d)
			local p = at3(d)
			return Vector3.new(p.X, 0, p.Z)
		end
		local tol = math.clamp(pieceL * 0.05, 0.15, 1.2) -- how far a piece may stray from the curve
		if halfW > 0.5 then
			tol = math.min(tol, 0.35)
		end -- a wide piece's edge is in plain view: keep it tight
		local minL = math.min(pieceL * 0.3, total) -- never squeeze below this
		local n = math.max(math.ceil(total / math.max(pieceL / 8, 0.1)), 2)
		local h = total / n
		-- corners are found in 3D, so the foot and the top of a wall or cliff get a joint too (a kerb is too small to count)
		local G = table.create(n + 1)
		for i = 0, n do
			G[i + 1] = at3(i * h)
		end
		local function turn(u, v)
			if u.Magnitude < 1e-6 or v.Magnitude < 1e-6 then
				return 0
			end
			return math.acos(math.clamp(u.Unit:Dot(v.Unit), -1, 1))
		end
		-- corners: a sharp turn inside one grid step. They split the curve into runs, and a joint sits exactly on each.
		local CORNER = math.rad(28)
		local breaks = { 0 }
		local i = 2
		while i <= n do
			if turn(G[i] - G[i - 1], G[i + 1] - G[i]) > CORNER then
				local lo, hi = math.max((i - 2) * h, 0), math.min(i * h, total)
				local best, bestD, e = -1, (i - 1) * h, h / 16
				for k = 0, 32 do -- refine: the point of sharpest turn in this window
					local d = lo + (hi - lo) * k / 32
					local t = turn(at3(d) - at3(d - e), at3(d + e) - at3(d))
					if t > best then
						best, bestD = t, d
					end
				end
				if bestD - breaks[#breaks] > 0.05 and total - bestD > 0.05 then
					table.insert(breaks, bestD)
				end
				i += 2
			else
				i += 1
			end
		end
		-- junctions and sharp points of the spline: a joint lands exactly there, so each section gets its own even pieces
		for _, jd in joints or {} do
			if jd > 0.05 and jd < total - 0.05 then
				table.insert(breaks, jd)
			end
		end
		table.sort(breaks)
		for k = #breaks, 2, -1 do
			if breaks[k] - breaks[k - 1] < math.max(minL * 0.5, 0.3) then
				table.remove(breaks, k)
			end
		end
		-- the same for the last run: a break a hair before the end would leave a sliver of a piece
		if #breaks > 1 and total - breaks[#breaks] < math.max(minL * 0.5, 0.3) then
			table.remove(breaks)
		end
		table.insert(breaks, total)
		-- how far the curve bows away from a chord (its sagitta): sideways, and up/down over crests and dips
		-- (height changes under half a stud don't count, so a kerb or a road edge doesn't chop the pieces)
		local function bow(d0, d1)
			local a, b = at(d0), at(d1)
			local a3, b3 = at3(d0), at3(d1)
			local ab = b - a
			local L2 = ab:Dot(ab)
			local worst = 0
			for k = 1, 7 do
				local dk = d0 + (d1 - d0) * k / 8
				local p = at(dk)
				local t = L2 > 1e-9 and math.clamp((p - a):Dot(ab) / L2, 0, 1) or k / 8
				local vy = math.abs(at3(dk).Y - (a3.Y + (b3.Y - a3.Y) * t))
				worst = math.max(worst, (p - (a + ab * t)).Magnitude, vy - 0.5)
			end
			-- the outer edge of a wide piece: bow x (1 + halfW / radius), radius ~ L^2 / (8 bow)
			local L = (at(d1) - at(d0)).Magnitude
			if halfW > 0.5 and L > 1e-3 then
				worst += halfW * 8 * worst * worst / (L * L)
			end
			return worst
		end
		-- the longest piece each spot allows: a full-length chord centred there, shortened until its bow <= tol
		-- (bow grows with length squared), measured inside its own run so corners don't shorten their neighbours
		local lmax = table.create(n + 1, pieceL)
		local r = 1
		for k = 1, n + 1 do
			local d = (k - 1) * h
			while r < #breaks - 1 and d > breaks[r + 1] do
				r += 1
			end
			local d0, d1 = math.max(d - pieceL / 2, breaks[r]), math.min(d + pieceL / 2, breaks[r + 1])
			if d1 - d0 > minL * 0.5 then
				local s = bow(d0, d1)
				if s > tol then
					lmax[k] = math.clamp((d1 - d0) * math.sqrt(tol / s), minL, pieceL)
				end
			end
		end
		local w = math.max(math.ceil(pieceL * 0.5 / h), 1) -- ease: lengths start shrinking half a piece before a bend
		local rho = table.create(n + 1)
		for k = 1, n + 1 do
			local m = pieceL
			for j = math.max(k - w, 1), math.min(k + w, n + 1) do
				m = math.min(m, lmax[j])
			end
			rho[k] = 1 / m -- pieces per stud
		end
		local function rhoAt(d)
			local x = math.clamp(d / h, 0, n)
			local k = math.min(math.floor(x), n - 1)
			return rho[k + 1] + (rho[k + 2] - rho[k + 1]) * (x - k)
		end
		local out = {}
		local function add(d0, d1, depth) -- split a piece that still cuts across the curve
			if depth < 4 and d1 - d0 > minL * 1.2 and bow(d0, d1) > tol * 1.5 then
				local mid = (d0 + d1) / 2
				add(d0, mid, depth + 1)
				add(mid, d1, depth + 1)
			else
				table.insert(out, { d0, d1 })
			end
		end
		for rr = 1, #breaks - 1 do
			local b0, b1 = breaks[rr], breaks[rr + 1]
			local steps = math.max(math.ceil((b1 - b0) / (h * 0.5)), 1)
			local ds = (b1 - b0) / steps
			local F = table.create(steps + 1)
			F[1] = 0
			for k = 1, steps do
				local d = b0 + (k - 1) * ds
				F[k + 1] = F[k] + (rhoAt(d) + rhoAt(d + ds)) * 0.5 * ds
			end
			local count = math.max(math.ceil(F[steps + 1] - 0.15), 1)
			local prev, k = b0, 1
			for j = 1, count do
				local target = F[steps + 1] * j / count
				local d = b1
				if j < count then
					while k < steps and F[k + 1] < target do
						k += 1
					end
					local f0, f1 = F[k], F[k + 1]
					d = b0 + (k - 1 + (f1 > f0 and (target - f0) / (f1 - f0) or 0)) * ds
				end
				if d - prev > 0.05 then
					add(prev, d, 0)
					prev = d
				end
			end
			if b1 - prev > 0.05 then
				add(prev, b1, 0)
			end
		end
		return out
	end
	E.fitPieces = fitPieces

	-- where a copy on a line may move to (in intervals) when its spot is taken
	local NUDGE = { 0, 0.25, -0.25, 0.45, -0.45 }

	-- Copies along the spline in full 3D: centre, one side or both; upright, stuck to the surface, or bent with the curve.
	local function placeSpline(ctx, l, rng)
		if not ctx.splines or #ctx.splines == 0 then
			return 0
		end
		local s, m = l.s, l.m
		local facing = s.fit and "Along" or s.facing -- end-to-end pieces always run along the line
		local lo, hi = scaleRange(l)
		local avg = (lo + hi) / 2
		local long = lengthOf(s, m)
		local alongX = alongXOf(s, m)
		local front = frontOf(s) -- nil: the smart guess
		local pieceL = long * avg * l.variants[1].size * 0.98
		-- wide pieces (tiles, thick walls) butt exactly; thin rails keep a hair of overlap so no daylight shows
		local wideSeg = (alongX and m.size.Z or m.size.X) > 0.6
		local interval = s.fit and pieceL or math.max(s.interval, 1)
		local gid = groupId(l, 99998)
		local got, cap = 0, s.maxCount > 0 and s.maxCount or 5000
		local off = math.max(s.offset, 0)
		local side = s.side
		-- a built road keeps copies off it: the offset counts from its edge (plus the copy's own reach), and copies
		-- meant for the curve itself line both edges instead. Pieces fitted end to end (a path of tiles) stay on it.
		local sp = ctx.area and ctx.area.spline
		if E.roadWidth(sp) > 0 and not s.fit then
			off += E.roadWidth(sp) / 2 + (l._r or 0)
			if side ~= "Left" and side ~= "Right" then
				side = "Both"
			end
		end
		local sides = (side == "Both" and off > 0) and { -off, off } or (side == "Left" and { -off }) or (side == "Right" and { off }) or { 0 }
		local roll = math.rad(s.roll or 0)

		local function tangent(Q, k)
			local a, b = Q[math.max(k - 1, 1)], Q[math.min(k + 1, #Q)]
			local t = b - a
			return t.Magnitude > 1e-5 and t.Unit or Vector3.zAxis
		end
		-- A copy on the curve itself has no edge to face, so "Face it" looks for one: the side where the ground is road
		-- (and away from buildings), probed a few steps out on each side. Where neither side says anything (open
		-- ground), the whole curve's majority decides, so a row of lamps never flips from one to the next.
		local curRp, curveSide = nil, 0
		local PROBES = { 3, 6, 10, 15, 22, 30 }
		local function edgeSide(pos, right)
			if not curRp then
				return 0
			end
			local score = 0
			for _, d in PROBES do
				for sgn = -1, 1, 2 do
					local q = pos + right * (d * sgn)
					local h = workspace:Raycast(q + Vector3.new(0, 40, 0), Vector3.new(0, -80, 0), curRp)
					if h then
						-- something standing well above the path is a building, whatever it's made of (a concrete roof
						-- isn't a road); otherwise the surface decides
						local c = h.Position.Y - pos.Y > 3 and "Building" or E.surfaceOf(h.Instance, h.Material)
						if c == "Road" then
							score += sgn
						elseif c == "Building" then
							score -= sgn
						end
					end
				end
			end
			return score > 0 and 1 or (score < 0 and -1 or 0)
		end
		-- orientation for one copy: `side` > 0 means right of the curve; v (optional): the variant, for its overhang
		local function frame(pos, t, n, side, pitch, v)
			local up, fwd
			if s.orient == "Upright" and pitch then -- an end-to-end piece: follows the slope of its chord, no roll
				fwd = t
				up = Vector3.yAxis - t * t.Y
			elseif s.orient == "Upright" then
				up, fwd = Vector3.yAxis, Vector3.new(t.X, 0, t.Z)
			elseif s.orient == "Surface" then
				up = n
				fwd = t - n * t:Dot(n)
			else -- Follow: pitch with the curve, up stays as close to the surface normal as the tangent allows
				fwd = t
				up = n - t * n:Dot(t)
			end
			if up.Magnitude < 1e-4 then
				up = Vector3.yAxis
			end
			up = up.Unit
			if fwd.Magnitude < 1e-4 then
				fwd = up:Cross(Vector3.xAxis)
				if fwd.Magnitude < 1e-4 then
					fwd = up:Cross(Vector3.zAxis)
				end
			end
			fwd = (fwd - up * fwd:Dot(up)).Unit
			local right = fwd:Cross(up)
			local cf
			local look = fwd
			if (facing == "Face it" or facing == "Away") and side == 0 then
				local sg = edgeSide(pos, right)
				if sg == 0 then
					sg = curveSide
				end
				if sg ~= 0 then
					look = ((sg > 0) == (facing == "Face it")) and right or -right
				elseif facing == "Away" then
					look = -fwd
				end
			elseif facing == "Face it" then
				look = side > 0 and -right or right
			elseif facing == "Away" then
				look = side > 0 and right or -right
			elseif facing == "Random" then
				look = CFrame.fromAxisAngle(up, rng:NextNumber(0, math.pi * 2)):VectorToWorldSpace(fwd)
			end
			if front then
				-- the chosen side of the model leads: down the line ("Along") or toward what it faces
				cf = CFrame.fromMatrix(pos, look:Cross(up), up) * CFrame.Angles(0, FRONT_YAW[front], 0)
				if roll ~= 0 then
					cf *= CFrame.fromAxisAngle(alongX and Vector3.xAxis or Vector3.zAxis, roll)
				end
			else
				if facing == "Along" then
					cf = alongX and CFrame.fromMatrix(pos, fwd, up) or CFrame.fromMatrix(pos, right, up)
				else
					cf = CFrame.fromMatrix(pos, look:Cross(up), up)
					-- a lamp's arm, a sign's bracket: the side the model reaches out to is its front
					local oy = v and facing ~= "Random" and overhangYaw(v)
					if oy then
						cf *= CFrame.Angles(0, oy, 0)
					end
				end
				if roll ~= 0 then
					cf *= (facing == "Along" and alongX) and CFrame.Angles(roll, 0, 0) or CFrame.Angles(0, 0, roll)
				end
			end
			if s.tilt > 0 and not s.fit then -- end-to-end pieces stay true so their joints meet
				cf *= CFrame.Angles(math.rad(rng:NextNumber(-s.tilt, s.tilt)), 0, math.rad(rng:NextNumber(-s.tilt, s.tilt)))
			end
			return cf
		end
		-- one duplicate check per side, so "Both" on a narrow strip keeps its copies on each side
		local mines, minD = {}, interval * 0.5
		local function put(pos, t, n, side, sc, v, stretch)
			if got >= cap or E.isCleared(ctx.clear, pos.X, pos.Z) then
				return
			end
			local mine = mines[side]
			if not mine then
				mine = Hash.new()
				mines[side] = mine
			end
			local probe = { x = pos.X, z = pos.Z, r = minD * 0.5, type = "L", sp = 1, cs = 1 }
			if not s.fit and mine:conflicts(probe) then
				return
			end
			local r = math.max(v.m.radius * sc, 0.25)
			local item = { x = pos.X, z = pos.Z, r = r, type = l.type, sp = s.spacing, cs = s.clearance, g = gid, line = true }
			-- the same spacing rules as everything else: another object already there (a rock, a bush on the same path)
			-- keeps this one off; end-to-end pieces are meant to touch and skip this
			if not s.fit and ctx.hash:conflicts(item) then
				return nil
			end
			local clone = emit(
				ctx,
				l,
				v,
				sc,
				frame(pos, t, n, side, s.fit, v),
				rng,
				pos.X,
				pos.Z,
				item,
				s.sink * v.m.size.Y * sc,
				gid,
				false,
				stretch,
				nil,
				s.fit and s.orient == "Upright"
			)
			if clone then -- (none is made in a keep-clear zone)
				got += 1
			end
			if not s.fit then
				mine:add(probe)
			end
			return clone
		end

		for _, smp in ctx.splines do
			curRp, curveSide = smp.rp, 0
			if (facing == "Face it" or facing == "Away") and table.find(sides, 0) and #smp.P >= 2 then
				local votes = 0
				for k = 1, #smp.P, math.max(#smp.P // 16, 1) do
					local t = tangent(smp.P, k)
					local r = Vector3.new(t.X, 0, t.Z):Cross(Vector3.yAxis)
					if r.Magnitude > 1e-4 then
						votes += edgeSide(smp.P[k], r.Unit)
					end
				end
				curveSide = votes > 0 and 1 or (votes < 0 and -1 or 0)
			end
			for si, side in sides do
				-- the curve shifted sideways (re-snapped onto the surface when snapping is on)
				local Q, W = smp.P, smp.U
				if side ~= 0 then
					Q, W = table.create(#smp.P), table.create(#smp.P)
					for k = 1, #smp.P do
						local t, n = tangent(smp.P, k), smp.U[k]
						local up = s.orient == "Upright" and Vector3.yAxis or n
						local right = t:Cross(up)
						if right.Magnitude < 1e-4 then
							right = t:Cross(Vector3.yAxis)
						end
						local q = smp.P[k] + right.Unit * side * (smp.W and smp.W[k] or 1) -- edges follow the strip's width
						if smp.snap then
							Q[k], W[k] = project(q, n, smp.rp)
						else
							Q[k], W[k] = q, n
						end
					end
				end
				local acc = { 0 }
				for k = 2, #Q do
					acc[k] = acc[k - 1] + (Q[k] - Q[k - 1]).Magnitude
				end
				local total = acc[#Q]
				local function at(d)
					d = math.clamp(d, 0, total)
					local lo2, hi2 = 1, #Q
					while hi2 - lo2 > 1 do
						local mid = (lo2 + hi2) // 2
						if acc[mid] <= d then
							lo2 = mid
						else
							hi2 = mid
						end
					end
					local t = (d - acc[lo2]) / math.max(acc[hi2] - acc[lo2], 1e-6)
					local zs = smp.Z and (smp.Z[lo2] + (smp.Z[hi2] - smp.Z[lo2]) * t) or 1
					return Q[lo2]:Lerp(Q[hi2], t), W[lo2]:Lerp(W[hi2], t), lo2, zs
				end
				if s.fit then
					local joints = {}
					for _, k in smp.joints or {} do
						table.insert(joints, acc[k])
					end
					local halfW = (alongX and m.size.Z or m.size.X) * avg * l.variants[1].size / 2
					local pieces = fitPieces(total, function(d)
						return (at(d))
					end, pieceL, joints, halfW)
					local keep = gapMask(#pieces, s.skip, rng)
					if l.post and #pieces > 0 then -- posts at every joint and both ends of the fence that's there
						local loop = (Q[1] - Q[#Q]).Magnitude < 0.05
						local marks = {}
						for k, pc in pieces do
							if keep[k] or keep[k - 1] or (loop and k == 1 and keep[#pieces]) then
								table.insert(marks, { pc[1], k })
							end
						end
						if not loop and keep[#pieces] then
							table.insert(marks, { total, #pieces + 1 })
						end
						local pv = l.post
						for _, mk in marks do
							if got >= cap then
								break
							end
							local pos, n, _, zs = at(mk[1])
							local prev, nxt = pieces[mk[2] - 1] or (loop and pieces[#pieces]), pieces[mk[2]]
							local t = Vector3.zero
							if prev then
								t += at(prev[2]) - at(prev[1])
							end
							if nxt then
								t += at(nxt[2]) - at(nxt[1])
							end
							t = t.Magnitude > 1e-4 and t.Unit or Vector3.zAxis
							local sc = avg * pv.size * zs
							local item = {
								x = pos.X,
								z = pos.Z,
								r = math.max(pv.m.radius * sc, 0.25),
								type = l.type,
								sp = s.spacing,
								cs = s.clearance,
								g = gid,
							}
							if
								emit(
									ctx,
									l,
									pv,
									sc,
									frame(pos, t, n.Magnitude > 1e-4 and n.Unit or Vector3.yAxis, side),
									rng,
									pos.X,
									pos.Z,
									item,
									s.sink * pv.m.size.Y * sc,
									gid,
									false
								)
							then
								got += 1
							end
						end
					end
					local placed = {}
					for k, pc in pieces do
						if got >= cap or not ctx.alive() then
							break
						end
						local a, na = at(pc[1])
						local dir = at(pc[2]) - a
						local len = dir.Magnitude
						-- a piece that would climb a cliff (steeper than 60 degrees) is left out: an opening, closed by end posts
						local cliff = s.orient == "Upright" and len > 0.05 and math.abs(dir.Y / len) > 0.866
						if len > 0.05 and keep[k] and not cliff then
							local v = pickVariant(l, rng)
							local sc = avg * v.size
							local _, n = at((pc[1] + pc[2]) / 2)
							n = n.Magnitude > 1e-4 and n.Unit or na
							local f = len * (wideSeg and 1.0005 or 1.02) / (lengthOf(s, v.m) * sc)
							local clone = put(a + dir / 2, dir.Unit, n, side, sc, v, f)
							if clone then
								placed[k] =
									{ v = v, sc = sc, f = math.min(f, 1.15), a = a, b = a + dir, t = dir.Unit, n = n, clone = clone, len = len }
							end
						end
					end
					-- mitre every joint between two placed pieces (both sides of it), so rails meet cleanly on bends and slopes
					local loopRun = (Q[1] - Q[#Q]).Magnitude < 0.05
					for k, pk in placed do
						local nxt = placed[k + 1] or (loopRun and k == #pieces and placed[1]) or nil
						if nxt then
							local nB = pk.t + nxt.t
							if nB.Magnitude > 1e-3 and pk.t:Dot(nxt.t) < 0.9998 then
								nB = nB.Unit
								local wa = mitre(pk.clone, pk.t, pk.b, nB, true, pk.len)
								local wb = mitre(nxt.clone, nxt.t, nxt.a, nB, false, nxt.len)
								for i = 1, math.min(#wa, #wb) do
									ctx.parts += fillJoint(wa[i], wb[i], nB)
								end
							end
						end
					end
					-- close open ends: a model with a post on one end only leaves bare rails where a stretch stops on the
					-- other side, so that end gets the model's own post (unless a separate post model is set)
					if not l.post and facing == "Along" and roll == 0 then
						local k = 1
						while k <= #pieces do
							if placed[k] then
								local j = k
								while placed[j + 1] do
									j += 1
								end
								local loop = (Q[1] - Q[#Q]).Magnitude < 0.05 and k == 1 and j == #pieces
								local ci = not loop and capInfo(placed[k].v, s)
								if ci and got < cap then
									-- which way the post points along the fence, from how the piece is actually turned (front and all)
									local cf0 = frame(placed[k].a:Lerp(placed[k].b, 0.5), placed[k].t, placed[k].n, side, true)
									local offDir = cf0:VectorToWorldSpace(ci.alongX and Vector3.xAxis or Vector3.zAxis):Dot(placed[k].t)
									local pk = placed[(offDir * ci.off < 0) and j or k] -- posts at piece starts: cap the stretch's end
									local e = offDir * ci.off * pk.sc -- post offset from the centre along the fence (unsqueezed)
									local halfL = lengthOf(s, pk.v.m) * pk.sc * pk.f / 2
									local inset = halfL - math.abs(e) * pk.f
									local post = e < 0 and pk.b - pk.t * inset or pk.a + pk.t * inset
									local pos = post - pk.t * e
									local item = { x = post.X, z = post.Z, r = 0.5, type = l.type, sp = s.spacing, cs = s.clearance, g = gid }
									emit(
										ctx,
										l,
										pk.v,
										pk.sc,
										frame(pos, pk.t, pk.n, side, true),
										rng,
										post.X,
										post.Z,
										item,
										s.sink * pk.v.m.size.Y * pk.sc,
										gid,
										false,
										nil,
										ci.only,
										s.orient == "Upright"
									)
									got += 1
								end
								k = j + 1
							else
								k += 1
							end
						end
					end
				else
					local d = math.min(interval * 0.5, total * 0.5)
					if s.stagger and si == 2 then
						d += interval * 0.5
					end
					local nextKeep = gapper(s.skip, rng)
					while d <= total and got < cap and ctx.alive() do
						local dd = math.clamp(d + (rng:NextNumber() - 0.5) * s.jitter * interval, 0, total)
						if nextKeep() then
							local v = pickVariant(l, rng)
							local scale = (lo + hi) / 2 + (hi - lo) * (rng:NextNumber() - 0.5)
							-- a spot another object already took: try a little further along, then a little back
							for _, shift in NUDGE do
								local pos, n, k, zs = at(math.clamp(dd + shift * interval, 0, total))
								if put(pos, tangent(Q, k), n.Magnitude > 1e-4 and n.Unit or Vector3.yAxis, side, scale * v.size * zs, v) then
									break
								end
								if got >= cap then
									break
								end
							end
						end
						d += interval
					end
				end
			end
		end
		return got
	end

	local function placeLine(ctx, l, rng)
		if l.s.follow == "Spline" or not ctx.an then
			return placeSpline(ctx, l, rng)
		end
		local an, s = ctx.an, l.s
		local facing = s.fit and "Along" or s.facing -- end-to-end pieces always run along the line
		local fieldName = FOLLOW_FIELD[s.follow] or "Roads"
		local f = an.dist[fieldName]
		if not f then
			return 0
		end
		local lo, hi = scaleRange(l)
		local m = l.m
		local long = lengthOf(s, m)
		local short = alongXOf(s, m) and m.size.Z or m.size.X
		local front = frontOf(s)
		local avg = (lo + hi) / 2
		-- the edge of a feature sits half a scan cell past its last cell centre
		local depth = facing == "Along" and short
			or (facing == "Random" and math.max(m.size.X, m.size.Z))
			or ((front == "-X" or front == "+X") and m.size.X or m.size.Z)
		local target = s.offset + depth * avg / 2 + an.G * 0.5
		local pieceL = long * avg * l.variants[1].size * 0.98 -- a hair of overlap so joints never show daylight
		local interval = s.fit and pieceL or math.max(s.interval, 1)
		local gid = groupId(l, 99999)
		-- `mine` stops two traced lines (a contour found twice) from doubling up. It must not stop the two sides of a
		-- narrow path from both getting copies, nor the short pieces a bend needs.
		local mine = Hash.new()
		local minD = s.fit and pieceL * 0.2 or math.min(interval * 0.5, target * 1.2)
		local got, cap = 0, s.maxCount > 0 and s.maxCount or 5000

		local function blocked(x, z)
			local j = E.indexAt(an, x, z)
			if not j then
				return true
			end
			local c = an.cls[j]
			return BLOCKS_LINE[c] == true
		end
		local function normalToward(x, z, tx, tz)
			local ja, jb = E.indexAt(an, x - tz * an.G, z + tx * an.G), E.indexAt(an, x + tz * an.G, z - tx * an.G)
			local fa, fb = ja and f[ja] or 1e9, jb and f[jb] or 1e9
			if fb < fa then
				return tz, -tx
			end
			return -tz, tx
		end
		local function yawFor(x, z, tx, tz, v)
			if front and facing ~= "Random" then
				-- -Z along the line or toward the feature, then turned so the chosen side leads
				local dx, dz = tx, tz
				if facing ~= "Along" then
					local nx_, nz_ = normalToward(x, z, tx, tz)
					if facing == "Away" then
						dx, dz = -nx_, -nz_
					else
						dx, dz = nx_, nz_
					end
				end
				return math.atan2(-dx, -dz) + FRONT_YAW[front]
			end
			if facing == "Along" then
				if m.size.X >= m.size.Z then
					return math.atan2(-tz, tx)
				end
				return math.atan2(tx, tz)
			elseif facing == "Random" then
				return rng:NextNumber(0, math.pi * 2)
			end
			local nx_, nz_ = normalToward(x, z, tx, tz)
			local oy = v and overhangYaw(v) or 0 -- a lamp's arm is its front
			if facing == "Away" then
				return math.atan2(nx_, nz_) + oy
			end
			return math.atan2(-nx_, -nz_) + oy -- LookVector (-Z) toward the feature
		end
		local function put(x, z, tx, tz, sc, v, stretch)
			if got >= cap then
				return
			end
			local i = E.indexAt(an, x, z)
			if not i then
				return
			end
			if l.paint then
				local p = E.paintValue(l, math.floor(x / an.cell), math.floor(z / an.cell))
				if p <= 0 or (p < 1 and rng:NextNumber() >= p) then
					return
				end
			end
			local probe = { x = x, z = z, r = minD * 0.5, type = "L", sp = 1, cs = 1 }
			if mine:conflicts(probe) then
				return
			end
			local info = placeAt(ctx, l, i, x, z, rng, { v = v, sc = sc, yaw = yawFor(x, z, tx, tz, v), line = true, gid = gid, stretch = stretch })
			if info then
				got += 1
				mine:add(probe)
			end
		end

		for ci, ln in traceLines(an, f, target, fieldName == "Edge") do
			local P = ln.pts
			local acc = { 0 }
			for k = 2, #P do
				acc[k] = acc[k - 1] + math.sqrt((P[k][1] - P[k - 1][1]) ^ 2 + (P[k][2] - P[k - 1][2]) ^ 2)
			end
			local total = acc[#P]
			local function at(d) -- binary search: callers probe back and forth along the line
				d = math.clamp(d, 0, total)
				local lo, hi = 1, #P
				while hi - lo > 1 do
					local mid = (lo + hi) // 2
					if acc[mid] <= d then
						lo = mid
					else
						hi = mid
					end
				end
				local k = hi
				local a, b = P[k - 1], P[k]
				local t = (d - acc[k - 1]) / math.max(acc[k] - acc[k - 1], 1e-6)
				return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t
			end

			if s.fit then
				-- end to end: each piece is a chord of the curve, squeezed on bends so it hugs the line and corners stay joined
				local pieces = fitPieces(total, function(d)
					local x, z = at(d)
					return Vector3.new(x, 0, z)
				end, pieceL, nil, short * avg * l.variants[1].size / 2)
				local keep = gapMask(#pieces, s.skip, rng)
				for k, pc in pieces do
					if got >= cap or not ctx.alive() then
						break
					end
					local ax, az = at(pc[1])
					local bx, bz = at(pc[2])
					local tx, tz = bx - ax, bz - az
					local tl = math.sqrt(tx * tx + tz * tz)
					if tl > 0.05 then
						tx, tz = tx / tl, tz / tl
						local cx, cz = (ax + bx) / 2, (az + bz) / 2
						if keep[k] and not blocked(ax, az) and not blocked(cx, cz) and not blocked(bx, bz) then
							local v = pickVariant(l, rng)
							local sc = avg * v.size
							put(cx, cz, tx, tz, sc, v, tl * (short > 0.6 and 1.0005 or 1.02) / (lengthOf(s, v.m) * sc))
						end
					end
				end
				if l.post and #pieces > 0 then -- posts at every joint and both ends of the fence that's there
					local marks = {}
					for k, pc in pieces do
						if keep[k] or keep[k - 1] or (ln.closed and k == 1 and keep[#pieces]) then
							table.insert(marks, pc[1])
						end
					end
					if not ln.closed and keep[#pieces] then
						table.insert(marks, total)
					end
					for _, d in marks do
						if got >= cap then
							break
						end
						local x, z = at(d)
						local x1, z1 = at(d - 1)
						local x2, z2 = at(d + 1)
						local tx, tz = x2 - x1, z2 - z1
						local tl = math.sqrt(tx * tx + tz * tz)
						local i = E.indexAt(an, x, z)
						if i and tl > 1e-3 and not blocked(x, z) then
							local info = placeAt(
								ctx,
								l,
								i,
								x,
								z,
								rng,
								{ v = l.post, sc = avg * l.post.size, yaw = yawFor(x, z, tx / tl, tz / tl), line = true, gid = gid, post = true }
							)
							if info then
								got += 1
							end
						end
					end
				end
			else
				local d = math.min(interval * 0.5, total * 0.5)
				if s.stagger and ci % 2 == 0 then
					d += interval * 0.5
				end -- every other traced edge starts half a gap later
				local nextKeep = gapper(s.skip, rng)
				while d <= total and got < cap and ctx.alive() do
					local dd = math.clamp(d + (rng:NextNumber() - 0.5) * s.jitter * interval, 0, total)
					local x, z = at(dd)
					local h = math.max(an.G, 2)
					local x1, z1 = at(dd - h)
					local x2, z2 = at(dd + h)
					local tx, tz = x2 - x1, z2 - z1
					local tl = math.sqrt(tx * tx + tz * tz)
					if tl > 1e-3 and nextKeep() and not blocked(x, z) then
						local v = pickVariant(l, rng)
						put(x, z, tx / tl, tz / tl, (lo + (hi - lo) * rng:NextNumber()) * v.size, v)
					end
					d += interval
				end
			end
		end
		return got
	end

	-- shared with the modules after this one
	I.placeLine = placeLine
end
