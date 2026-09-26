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
	local hit = workspace:Raycast(pos + up * 4, -up * 12, rp) or workspace:Raycast(pos + up * 60, -up * 120, rp)
	-- where the curve passes through solid ground (a smooth curve over a cliff or a steep hill), the short probe
	-- starts inside it and finds the floor underneath; the surface we want is the one on top
	if hit and (pos - hit.Position):Dot(up) > 1.5 and insideSolid(pos + up * 0.5, rp) then
		local top = workspace:Raycast(pos + up * 60, -up * 120, rp)
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
	return { P = P, U = U, W = W, Z = Z, snap = sp.snap, rp = rp }
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
