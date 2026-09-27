--[[
	Smart Scatter — Engine/Paths: splines (smooth curves through clicked points) and the road surfaces laid along them.
	Adds to E (the engine API); shares internals with the other engine modules through I.
]]

return function(E, I)
	--------------------------------------------------------------------------------
	-- Splines: a smooth 3D curve through clicked points (centripetal Catmull-Rom: no loops or overshoot).
	-- a.spline = { pts = { { p = Vector3, n = Vector3, sharp = bool?, raised = bool? (Shift-lifted: kept off the ground), w = width x?, s = scale x?, h = handle Vector3? }, ... }, closed = bool, width = studs (0 = path only), snap = bool,
	--   walls = bool (clicks may land on walls),
	--   branches = { { pts = { ... } }, ... } }  -- extra open curves that sprout from a point of the network
	--------------------------------------------------------------------------------
	local function knot(t, a, b)
		return t + math.max((b - a).Magnitude, 1e-4) ^ 0.5
	end
	local function catmull(p0, p1, p2, p3, t)
		local t1 = knot(0, p0, p1)
		local t2 = knot(t1, p1, p2)
		local t3 = knot(t2, p2, p3)
		local u = t1 + (t2 - t1) * t
		local a1 = p0:Lerp(p1, u / t1)
		local a2 = p1:Lerp(p2, (u - t1) / (t2 - t1))
		local a3 = p2:Lerp(p3, (u - t2) / (t3 - t2))
		local b1 = a1:Lerp(a2, u / t2)
		local b2 = a2:Lerp(a3, (u - t1) / (t3 - t1))
		return b1:Lerp(b2, (u - t1) / (t2 - t1))
	end

	-- The automatic handle of point i: the Bezier offset (out direction) the curve would use without a custom handle.
	-- Custom handles (q.h) are that offset set by hand; the "in" handle mirrors it.
	function E.autoHandle(sp, i)
		local pts, n = sp.pts, #sp.pts
		if n < 2 then
			return Vector3.zero
		end
		local closed = sp.closed and n >= 3
		local function at(k)
			if closed then
				return pts[(k - 1) % n + 1].p
			end
			return pts[math.clamp(k, 1, n)].p
		end
		return (at(i + 1) - at(i - 1)) / 6
	end

	local function bezier(a, c1, c2, b, t)
		local u = 1 - t
		return a * (u * u * u) + c1 * (3 * u * u * t) + c2 * (3 * u * t * t) + b * (t * t * t)
	end

	-- dense polyline of the curve: P (positions), U (interpolated up/normal), S (control segment of each sample),
	-- W and Z (per-point width and scale multipliers, eased between points), R (how raised, 0-1, eased between points)
	function E.splineCurve(sp, step)
		local pts = sp.pts
		local n = #pts
		local P, U, S, W, Z, R = {}, {}, {}, {}, {}, {}
		if n == 0 then
			return P, U, S, W, Z, R
		end
		local function raised(q)
			return q.raised and 1 or 0
		end
		if n == 1 then
			return { pts[1].p }, { pts[1].n }, { 1 }, { pts[1].w or 1 }, { pts[1].s or 1 }, { raised(pts[1]) }
		end
		local closed = sp.closed and n >= 3
		local function cp(i)
			if closed then
				return pts[(i - 1) % n + 1].p
			end
			if i < 1 then
				return pts[1].p * 2 - pts[2].p
			end
			if i > n then
				return pts[n].p * 2 - pts[n - 1].p
			end
			return pts[i].p
		end
		local segs = closed and n or n - 1
		for i = 1, segs do
			local j = i % n + 1
			local a, b = pts[i], pts[j]
			local steps = math.max(1, math.ceil((b.p - a.p).Magnitude / step))
			-- a hand-set handle on either end makes this a Bezier segment (the other end keeps its automatic handle)
			local c1, c2
			if a.h or b.h then
				c1 = a.p + (a.h or (a.sharp and Vector3.zero or E.autoHandle(sp, i)))
				c2 = b.p - (b.h or (b.sharp and Vector3.zero or E.autoHandle(sp, j)))
			end
			local wa, wb, za, zb, ra, rb = a.w or 1, b.w or 1, a.s or 1, b.s or 1, raised(a), raised(b)
			for k = 0, steps - 1 do
				local t = k / steps
				if c1 then
					table.insert(P, bezier(a.p, c1, c2, b.p, t))
				else
					-- a sharp point pins its neighbour tangent: the curve runs straight into and out of the corner
					table.insert(P, catmull(a.sharp and a.p * 2 - b.p or cp(i - 1), cp(i), cp(i + 1), b.sharp and b.p * 2 - a.p or cp(i + 2), t))
				end
				local nn = a.n:Lerp(b.n, t)
				table.insert(U, nn.Magnitude > 1e-4 and nn.Unit or Vector3.yAxis)
				table.insert(S, i)
				local e = t * t * (3 - 2 * t)
				table.insert(W, wa + (wb - wa) * e)
				table.insert(Z, za + (zb - za) * e)
				table.insert(R, ra + (rb - ra) * e)
			end
		end
		local last = closed and pts[1] or pts[n]
		table.insert(P, last.p)
		table.insert(U, last.n)
		table.insert(S, segs)
		table.insert(W, last.w or 1)
		table.insert(Z, last.s or 1)
		table.insert(R, raised(last))
		return P, U, S, W, Z, R
	end

	-- true when p is inside solid terrain or inside a solid part (a ray started there can't see the surface around it)
	local function insideSolid(p, rp)
		local T = workspace.Terrain
		local ok, mats, occ = pcall(function()
			local lo = Vector3.new(math.floor(p.X / 4), math.floor(p.Y / 4), math.floor(p.Z / 4)) * 4 -- the voxel p is in
			return T:ReadVoxels(Region3.new(lo, lo + Vector3.new(4, 4, 4)), 4)
		end)
		if ok and mats.Size.X > 0 then
			local m, o = mats[1][1][1], occ[1][1][1]
			if m ~= Enum.Material.Air and m ~= Enum.Material.Water and o > 0.5 then
				return true
			end
		end
		local op = OverlapParams.new()
		op.FilterType = rp.FilterType
		op.FilterDescendantsInstances = rp.FilterDescendantsInstances
		op.RespectCanCollide = true
		for _, part in workspace:GetPartBoundsInRadius(p, 0.05, op) do
			if part ~= T and part.CanCollide then
				return true
			end
		end
		return false
	end

	local function project(pos, up, rp)
		-- a short probe first (a spline on a wall or under a ledge should find its own surface, not the floor below),
		-- then a tall one: on a steep hillside the ground beside the curve can be far above or below it
		local hit = E.cast(pos + up * 4, -up * 12, rp) or E.cast(pos + up * 60, -up * 120, rp)
		-- where the curve passes through solid ground (a smooth curve over a cliff or a steep hill), the short probe
		-- starts inside it and finds the floor underneath; the surface we want is the one on top
		if hit and (pos - hit.Position):Dot(up) > 1.5 and insideSolid(pos + up * 0.5, rp) then
			local top = E.cast(pos + up * 60, -up * 120, rp)
			if top and (top.Position - pos):Dot(up) > -1.5 then
				hit = top
			end
		end
		if hit then
			return hit.Position, hit.Normal
		end
		return pos, up
	end
	-- curve samples for placement: optionally snapped onto the surface under each sample (ground, walls, ceilings)
	function E.splineSamples(sp, rp)
		local P, U, _, W, Z, R = E.splineCurve(sp, 0.75)
		if sp.snap then
			-- straight down onto the ground (along the slope's normal would slide the curve sideways on a hillside);
			-- a spline allowed on walls snaps along its own normals instead. Between Shift-raised points the curve
			-- keeps its own height (a bridge), easing back onto the ground toward points that aren't raised.
			for k = 1, #P do
				local up = sp.walls and U[k] or Vector3.yAxis
				local g, gn = project(P[k], up, rp)
				local lift = math.max((P[k] - g):Dot(up), 0) * R[k]
				P[k], U[k] = g + up * lift, lift > 0.05 and gn:Lerp(up, R[k]).Unit or gn
			end
		end
		return { P = P, U = U, W = W, Z = Z, R = R, snap = sp.snap, rp = rp }
	end

	-- ── spline editing: plain data operations, used by the editor and checked by the test suite ──
	-- point ref = { cv = curve, i = index }. Dropping a point on another point joins them: they share a position from
	-- then on (and move together). The main curve's end dropped on its own start closes the loop instead.
	-- Returns "closed" or "joined".
	function E.joinToPoint(sp, ref, target)
		if ref.cv == sp and target.cv == sp and #sp.pts >= 4 and ((ref.i == #sp.pts and target.i == 1) or (ref.i == 1 and target.i == #sp.pts)) then
			table.remove(sp.pts, ref.i)
			sp.closed = true
			return "closed"
		end
		local q, o = ref.cv.pts[ref.i], target.cv.pts[target.i]
		if not (q and o) then
			return nil
		end -- a stale reference: nothing to join
		q.p, q.n = o.p, o.n
		return "joined"
	end
	-- dropping an end on the middle of a curve: a real point is added to that curve there (a T-junction) and the end
	-- sits on it, so both curves share it
	function E.joinToCurve(ref, cv, seg, p, n)
		local q = ref.cv.pts[ref.i] -- before the insert: it may shift indices on the same curve
		-- the new point carries the curve's width and scale there, so a junction doesn't pinch the road
		local a, b = cv.pts[seg], cv.pts[seg + 1] or cv.pts[1]
		local t = 0.5
		if a and b and (b.p - a.p).Magnitude > 1e-3 then
			t = math.clamp((p - a.p):Dot(b.p - a.p) / (b.p - a.p).Magnitude ^ 2, 0, 1)
		end
		local function mix(k)
			local va, vb = a and a[k] or 1, b and b[k] or 1
			local v = va + (vb - va) * t
			return math.abs(v - 1) > 1e-3 and v or nil
		end
		table.insert(cv.pts, seg + 1, { p = p, n = n, w = mix("w"), s = mix("s") })
		q.p, q.n = p, n
	end
	-- a freehand stroke (its point tables in drawing order): smooths out hand jitter (the ends stay put), then keeps only
	-- the points that shape it (Ramer-Douglas-Peucker, tolerance ~a third of the drop spacing). Returns the set of point
	-- tables to remove.
	function E.thinStroke(s, spacing)
		local drop = {}
		if #s <= 2 then
			return drop
		end
		for _ = 1, 3 do
			local p = table.create(#s)
			for k, q in s do
				p[k] = q.p
			end
			for k = 2, #s - 1 do
				s[k].p = p[k] * 0.5 + (p[k - 1] + p[k + 1]) * 0.25
			end
		end
		local keep = { [1] = true, [#s] = true }
		local tol = spacing * 0.3
		local function rdp(a, b)
			local A, B = s[a].p, s[b].p
			local ab = Vector3.new(B.X - A.X, 0, B.Z - A.Z)
			local len = ab.Magnitude
			local worst, wi = 0, nil
			for k = a + 1, b - 1 do
				local v = Vector3.new(s[k].p.X - A.X, 0, s[k].p.Z - A.Z)
				local dist = len > 1e-4 and math.abs(v.X * ab.Z - v.Z * ab.X) / len or v.Magnitude
				dist = math.max(dist, math.abs(s[k].p.Y - (A.Y + (B.Y - A.Y) * (k - a) / (b - a))) * 0.5)
				if dist > worst then
					worst, wi = dist, k
				end
			end
			if wi and worst > tol then
				keep[wi] = true
				rdp(a, wi)
				rdp(wi, b)
			end
		end
		rdp(1, #s)
		for k, q in s do
			if not keep[k] then
				drop[q] = true
			end
		end
		return drop
	end

	-- every drawable curve of a spline network: the main curve, then its branches (each shares the network's settings)
	function E.splineCurves(sp)
		local list = {}
		if not sp then
			return list
		end
		if #sp.pts >= 2 then
			table.insert(list, sp)
		end
		for _, b in sp.branches or {} do
			if #b.pts >= 2 then
				table.insert(list, { pts = b.pts, closed = false, snap = sp.snap, width = sp.width, walls = sp.walls })
			end
		end
		return list
	end

	-- Road and path surfaces: the spline's strip laid as a solid, seamless surface. Each stretch between stations is two
	-- triangles (two wedges each), so any curve, slope or width change closes without gaps; stations sit close together
	-- in bends and far apart on straights, so a straight road stays a handful of parts.
	E.ROAD_STYLES = {
		{ name = "Asphalt", mat = Enum.Material.Asphalt, color = Color3.fromRGB(64, 64, 70) },
		{ name = "Concrete", mat = Enum.Material.Concrete, color = Color3.fromRGB(150, 150, 150) },
		{ name = "Cobble", mat = Enum.Material.Cobblestone, color = Color3.fromRGB(128, 122, 116) },
		{ name = "Brick", mat = Enum.Material.Brick, color = Color3.fromRGB(143, 76, 58) },
		{ name = "Dirt", mat = Enum.Material.Ground, color = Color3.fromRGB(107, 84, 58) },
		{ name = "Sand", mat = Enum.Material.Sand, color = Color3.fromRGB(216, 199, 149) },
		{ name = "Planks", mat = Enum.Material.WoodPlanks, color = Color3.fromRGB(139, 106, 74) },
	}
	local function surfaceStyle(name)
		for _, st in E.ROAD_STYLES do
			if st.name == name then
				return st
			end
		end
		return E.ROAD_STYLES[1]
	end
	local function wedge(parent, style, size, cf)
		local w = Instance.new("WedgePart")
		w.Anchored = true
		w.TopSurface, w.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		w.Material, w.Color = style.mat, style.color
		w.CastShadow = false
		w.Size, w.CFrame = size, cf
		w.Parent = parent
	end
	-- a solid triangle: top face on a, b, c; `thick` studs deep below it
	local function triangle(parent, style, a, b, c, thick)
		local ab, ac, bc = b - a, c - a, c - b
		local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
		if abd > acd and abd > bcd then
			c, a = a, c
		elseif acd > bcd and acd > abd then
			a, b = b, a
		end
		ab, ac, bc = b - a, c - a, c - b
		local nrm = ac:Cross(ab)
		if nrm.Magnitude < 1e-4 or bc.Magnitude < 1e-3 then
			return 0
		end
		local right = nrm.Unit
		local up = bc:Cross(right).Unit
		local back = bc.Unit
		local height = math.abs(ab:Dot(up))
		if height < 1e-3 then
			return 0
		end
		local sink = (right.Y >= 0 and -right or right) * (thick / 2) -- the top face sits on the triangle, depth goes down
		local n = 0
		local d0, d1 = math.abs(ab:Dot(back)), math.abs(ac:Dot(back))
		if d0 > 1e-3 then
			wedge(parent, style, Vector3.new(thick, height, d0), CFrame.fromMatrix((a + b) / 2 + sink, right, up, back))
			n += 1
		end
		if d1 > 1e-3 then
			wedge(parent, style, Vector3.new(thick, height, d1), CFrame.fromMatrix((a + c) / 2 + sink, -right, up, -back))
			n += 1
		end
		return n
	end
	-- the road's width in studs (0 = no road). It has its own width inside the strip, so the strip around it can still
	-- be filled; roads from before that had one are as wide as the strip.
	function E.roadWidth(sp)
		local sf = sp and sp.surface
		if not (sf and sf.on) then
			return 0
		end
		return math.max(tonumber(sf.width) or sp.width or 0, 0)
	end

	-- builds a.spline's surface into a new folder (not parented); returns it and the part count, or nil when there's none
	function E.buildSurface(a, rp)
		local sp = a.spline
		local sf = sp and sp.surface
		local width = E.roadWidth(sp)
		if width <= 0 then
			return nil, 0
		end
		local style = surfaceStyle(sf.style)
		local thick = math.clamp(tonumber(sf.thick) or 1, 0.2, 20)
		local R0 = width / 2
		local folder = Instance.new("Folder")
		folder.Name = "Surface"
		folder:SetAttribute("SS_Surface", (style.name == "Dirt" or style.name == "Sand") and "Path" or "Road") -- also how scans read it
		local parts = 0
		-- every curve's samples first: a branch needs to know where the road it joins lies
		local all = {}
		for ci, cv in E.splineCurves(sp) do
			all[ci] = { smp = E.splineSamples(cv, rp) }
		end
		-- flat distance from q to curve j's centre line, that road's half width there, and whether the closest spot is
		-- one of its ends (an end-to-end join, not a junction into the middle of it)
		local function nearest(j, q)
			local Pj, Wj = all[j].smp.P, all[j].smp.W
			local best, bw, atEnd = math.huge, 1, false
			for k = 1, #Pj - 1 do
				local a, b = Pj[k], Pj[k + 1]
				local ab = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
				local aq = Vector3.new(q.X - a.X, 0, q.Z - a.Z)
				local L2 = ab:Dot(ab)
				local t = L2 > 1e-9 and math.clamp(aq:Dot(ab) / L2, 0, 1) or 0
				local d = (aq - ab * t).Magnitude
				if d < best then
					best, bw = d, Wj[k] + (Wj[k + 1] - Wj[k]) * t
					atEnd = (k == 1 and t < 1e-3) or (k == #Pj - 1 and t > 1 - 1e-3)
				end
			end
			return best, R0 * bw, atEnd
		end
		for ci, rec in all do
			local smp = rec.smp
			local P, W = smp.P, smp.W
			local n = #P
			if n >= 2 then
				local loop = (P[1] - P[n]).Magnitude < 0.05
				-- stations: every sample where the curve has turned ~5 degrees, the width changed, or 48 studs went by
				local st, lastDir, run, lastW = { 1 }, nil, 0, W[1]
				for k = 2, n - 1 do
					local d = P[k + 1] - P[k]
					run += (P[k] - P[k - 1]).Magnitude
					-- a vertical step (kerb, edge of another road) has no direction of its own: keep the last one
					local dir = Vector3.new(d.X, 0, d.Z).Magnitude > 0.05 and d.Unit or lastDir
					local ref = P[k] - P[st[#st]]
					ref = ref.Magnitude > 1e-5 and ref.Unit or dir
					if dir and ref and (dir:Dot(ref) < 0.9965 or run >= 48 or math.abs(W[k] - lastW) > 0.04) then
						table.insert(st, k)
						run, lastW = 0, W[k]
					end
					lastDir = dir
				end
				table.insert(st, n)
				-- edges at sample k: square to the curve, mitred through bends so both sides stay parallel, dropped onto
				-- the ground (a tall probe, so a steep cross-slope still finds it)
				local lift = 0.04 + (ci - 1) * 0.03 -- branches sit a hair higher where they overlap the main road
				local function flat(v)
					if not v then
						return nil
					end
					v = Vector3.new(v.X, 0, v.Z)
					return v.Magnitude > 0.05 and v.Unit or nil
				end
				local function ground(q)
					local hit = E.cast(q + Vector3.new(0, 60, 0), Vector3.new(0, -120, 0), rp)
					return hit and hit.Position or q
				end
				local cache = {}
				local function edgeAt(k)
					local hitC = cache[k]
					if hitC then
						return hitC[1], hitC[2], hitC[3]
					end
					-- direction from ~4.5 studs of curve either side (not a neighbouring station, which can be far away or
					-- a sub-stud step at a kerb); at a sharp corner the two sides differ and the edges mitre
					local m = 6
					local prev = k > 1 and math.max(k - m, 1) or (loop and n - m) or nil
					local nxt = k < n and math.min(k + m, n) or (loop and 1 + m) or nil
					local t0 = flat(prev and (P[k] - P[prev]) or nil)
					local t1 = flat(nxt and (P[nxt] - P[k]) or nil)
					local t = (t0 and t1) and (t0 + t1) or t0 or t1 or Vector3.zAxis
					t = t.Magnitude > 1e-5 and t.Unit or (t1 or t0 or Vector3.zAxis)
					local right = t:Cross(Vector3.yAxis)
					local miter = (t0 and t1) and 1 / math.max(math.cos(math.acos(math.clamp(t0:Dot(t1), -1, 1)) / 2), 0.5) or 1
					local half = R0 * (W[k] or 1) * miter
					local l, r, c = P[k] + right * half, P[k] - right * half, P[k]
					if smp.snap then
						-- raised stretches (Shift-lifted points) stay level across at the curve's height: a bridge
						local up = smp.R and smp.R[k] or 0
						local y = P[k].Y
						l, r, c = ground(l), ground(r), ground(c)
						if up > 0 then
							l = l:Lerp(Vector3.new(l.X, math.max(y, l.Y), l.Z), up)
							r = r:Lerp(Vector3.new(r.X, math.max(y, r.Y), r.Z), up)
							c = c:Lerp(Vector3.new(c.X, math.max(y, c.Y), c.Z), up)
						end
					end
					l, r, c = l + Vector3.yAxis * lift, r + Vector3.yAxis * lift, c + Vector3.yAxis * lift
					cache[k] = { l, r, c }
					return l, r, c
				end
				-- follow the ground's height too: wherever the edges or the centre between two stations stray more than
				-- 0.3 studs from a straight line, that stretch gets another station (over crests, through dips, across
				-- a sideways slope), until every stretch lies on the ground
				if smp.snap then
					local j, guard = 1, 0
					while j < #st and guard < 4000 do
						guard += 1
						local k0, k1 = st[j], st[j + 1]
						local split
						if k1 - k0 >= 2 then
							local l0, r0, c0 = edgeAt(k0)
							local l1, r1, c1 = edgeAt(k1)
							local stepK = math.max(1, math.floor((k1 - k0) / math.max(math.ceil((k1 - k0) * 0.75 / 6), 1)))
							local worst = 0.3
							for k = k0 + stepK, k1 - 1, stepK do
								local f = (k - k0) / (k1 - k0)
								local lk, rk, ck = edgeAt(k)
								local d = math.max(
									math.abs(lk.Y - (l0.Y + (l1.Y - l0.Y) * f)),
									math.abs(rk.Y - (r0.Y + (r1.Y - r0.Y) * f)),
									math.abs(ck.Y - (c0.Y + (c1.Y - c0.Y) * f))
								)
								if d > worst then
									worst, split = d, k
								end
							end
						end
						if split then
							table.insert(st, j + 1, split)
						else
							j += 1
						end
					end
				end
				local L, Rr, C = {}, {}, {}
				for j, k in st do
					L[j], Rr[j], C[j] = edgeAt(k)
				end
				-- junctions: an end of this road that sits inside an earlier road (a branch off the main road) is cut back
				-- to that road's edge, each side where it crosses, so the two surfaces meet in a clean seam instead of
				-- lying on top of each other (which flickers). Roads that just continue end to end are left alone.
				local function trim(fromStart)
					local kEnd = fromStart and 1 or n
					for j = 1, ci - 1 do
						local d, hw, atEnd = nearest(j, P[kEnd])
						if d < hw - 0.05 and not atEnd then
							local function inside(q)
								local dd, hh = nearest(j, q)
								return dd < hh
							end
							-- walk inward until each edge is out of the other road, then pin the exact crossing
							local function cross(side)
								local prevK = kEnd
								local step = fromStart and 1 or -1
								local k = kEnd
								while k >= 1 and k <= n do
									local l, r = edgeAt(k)
									local q = side == 1 and l or r
									if not inside(q) then
										if k == kEnd then
											return q, k
										end
										local lp, rp2 = edgeAt(prevK)
										local a0 = side == 1 and lp or rp2
										local lo, hi = 0, 1
										for _ = 1, 10 do
											local mid = (lo + hi) / 2
											if inside(a0:Lerp(q, mid)) then
												lo = mid
											else
												hi = mid
											end
										end
										return a0:Lerp(q, hi), k
									end
									prevK = k
									k += step
								end
								return nil
							end
							local lx, kl = cross(1)
							local rx, kr = cross(-1)
							if not lx or not rx then
								return "gone"
							end -- the whole road lies inside the other one
							return { l = lx, r = rx, k = fromStart and math.max(kl, kr) or math.min(kl, kr) }
						end
					end
					return nil
				end
				if not loop then
					local cut0, cut1 = trim(true), trim(false)
					if cut0 == "gone" or cut1 == "gone" then
						continue
					end
					if cut0 or cut1 then
						-- the stations between the cuts, with each crossing as the new end edge
						local nL, nR, nC = {}, {}, {}
						local function push(l, r, c)
							table.insert(nL, l)
							table.insert(nR, r)
							table.insert(nC, c or (l + r) / 2)
						end
						if cut0 then
							push(cut0.l, cut0.r)
						end
						for idx, k in st do
							if (not cut0 or k >= cut0.k) and (not cut1 or k <= cut1.k) then
								push(L[idx], Rr[idx], C[idx])
							end
						end
						if cut1 then
							push(cut1.l, cut1.r)
						end
						if #nL < 2 then
							continue
						end
						L, Rr, C = nL, nR, nC
					end
				end
				-- the surface is two strips (edge to centre line, centre line to edge), so a crowned or domed ground
				-- is followed across the road as well as along it; a flat, straight stretch collapses to one part
				for j = 1, #L - 1 do
					local across, along = L[j] - Rr[j], L[j + 1] - L[j]
					local mid = (L[j] + Rr[j]) / 2
					local flatAcross = math.abs(C[j].Y - mid.Y) < 0.05 and math.abs(C[j + 1].Y - (L[j + 1].Y + Rr[j + 1].Y) / 2) < 0.05
					if not flatAcross then
						for _, side in { { L, C }, { C, Rr } } do
							local A, B = side[1], side[2]
							parts += triangle(folder, style, A[j], B[j], B[j + 1], thick)
							parts += triangle(folder, style, A[j], B[j + 1], A[j + 1], thick)
						end
					elseif ((Rr[j + 1] - Rr[j]) - along).Magnitude < 0.02 and math.abs(across.Unit:Dot(along.Unit)) < 0.01 then
						-- a straight, even stretch is a plain rectangle: one part instead of four wedges
						local nrm = along:Cross(across).Unit
						if nrm.Y < 0 then
							nrm = -nrm
						end
						local b = Instance.new("Part")
						b.Anchored = true
						b.TopSurface, b.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
						b.Material, b.Color, b.CastShadow = style.mat, style.color, false
						b.Size = Vector3.new(across.Magnitude, thick, along.Magnitude)
						b.CFrame = CFrame.fromMatrix((L[j] + Rr[j + 1]) / 2 - nrm * (thick / 2), across.Unit, nrm)
						b.Parent = folder
						parts += 1
					else
						parts += triangle(folder, style, L[j], Rr[j], Rr[j + 1], thick)
						parts += triangle(folder, style, L[j], Rr[j + 1], L[j + 1], thick)
					end
				end
			end
		end
		if parts == 0 then -- no curve long enough for a road yet
			folder:Destroy()
			return nil, 0
		end
		return folder, parts
	end

	-- a test for "is (x, z) on the road of area a": the strip stamped on a 2-stud grid (used to clear other areas'
	-- copies off a road that was just built)
	function E.roadTest(a, rp)
		local sp, cells, g = a.spline, {}, 2
		for _, cv in E.splineCurves(sp) do
			local smp = E.splineSamples(cv, rp)
			for k, p in smp.P do
				local R = E.roadWidth(sp) / 2 * smp.W[k]
				for cx = math.floor((p.X - R) / g), math.floor((p.X + R) / g) do
					for cz = math.floor((p.Z - R) / g), math.floor((p.Z + R) / g) do
						local dx, dz = (cx + 0.5) * g - p.X, (cz + 0.5) * g - p.Z
						if dx * dx + dz * dz <= R * R then
							cells[cx * 1000003 + cz] = true
						end
					end
				end
			end
		end
		return function(x, z)
			return cells[math.floor(x / g) * 1000003 + math.floor(z / g)] == true
		end
	end

	-- the strip around the curves becomes the area (so the usual scatter fills it)
	function E.maskFromSpline(a, rp)
		local sp = a.spline
		a.rows, a.count = {}, 0
		if not sp or (sp.width or 0) <= 0 then
			return
		end
		local c, R0, road = a.cell, sp.width / 2, E.roadWidth(sp) / 2 -- the road down the middle stays empty
		local top = -math.huge
		for _, cv in E.splineCurves(sp) do
			local smp = E.splineSamples(cv, rp)
			local lastX, lastZ
			for k, p in smp.P do
				top = math.max(top, p.Y)
				local R = R0 * smp.W[k] -- the strip widens and narrows with each point's width
				if not lastX or (p.X - lastX) ^ 2 + (p.Z - lastZ) ^ 2 >= (c * 0.5) ^ 2 or k == #smp.P then
					lastX, lastZ = p.X, p.Z
					if road <= 0 then
						E.setCell(a, math.floor(p.X / c), math.floor(p.Z / c), true) -- a strip narrower than a cell still counts
					end
					for cx = math.floor((p.X - R) / c), math.floor((p.X + R) / c) do
						for cz = math.floor((p.Z - R) / c), math.floor((p.Z + R) / c) do
							local dx, dz = (cx + 0.5) * c - p.X, (cz + 0.5) * c - p.Z
							local d2, rr = dx * dx + dz * dz, road * smp.W[k] + c * 0.5
							if d2 <= R * R and d2 > rr * rr then
								E.setCell(a, cx, cz, true)
							end
						end
					end
				end
			end
		end
		if top > -math.huge then
			a.topY = top
		end
	end

	-- shared with the modules after this one
	I.triangle = triangle
	I.project = project
end
