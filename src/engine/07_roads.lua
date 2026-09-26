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
-- builds a.spline's surface into a new folder (not parented); returns it and the part count, or nil when there's none
function E.buildSurface(a, rp)
	local sp = a.spline
	local sf = sp and sp.surface
	if not sf or not sf.on or (sp.width or 0) <= 0 then
		return nil, 0
	end
	local style = surfaceStyle(sf.style)
	local thick = math.clamp(tonumber(sf.thick) or 1, 0.2, 20)
	local R0 = sp.width / 2
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
				local hit = workspace:Raycast(q + Vector3.new(0, 60, 0), Vector3.new(0, -120, 0), rp)
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
					l, r, c = ground(l), ground(r), ground(c)
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

-- the strip around the curves becomes the area (so the usual scatter fills it)
function E.maskFromSpline(a, rp)
	local sp = a.spline
	a.rows, a.count = {}, 0
	if not sp or (sp.width or 0) <= 0 then
		return
	end
	if sp.surface and sp.surface.on then
		return
	end -- the strip is a road: nothing gets scattered onto it
	local c, R0 = a.cell, sp.width / 2
	local top = -math.huge
	for _, cv in E.splineCurves(sp) do
		local smp = E.splineSamples(cv, rp)
		local lastX, lastZ
		for k, p in smp.P do
			top = math.max(top, p.Y)
			local R = R0 * smp.W[k] -- the strip widens and narrows with each point's width
			if not lastX or (p.X - lastX) ^ 2 + (p.Z - lastZ) ^ 2 >= (c * 0.5) ^ 2 or k == #smp.P then
				lastX, lastZ = p.X, p.Z
				E.setCell(a, math.floor(p.X / c), math.floor(p.Z / c), true) -- a strip narrower than a cell still counts
				for cx = math.floor((p.X - R) / c), math.floor((p.X + R) / c) do
					for cz = math.floor((p.Z - R) / c), math.floor((p.Z + R) / c) do
						local dx, dz = (cx + 0.5) * c - p.X, (cz + 0.5) * c - p.Z
						if dx * dx + dz * dz <= R * R then
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
