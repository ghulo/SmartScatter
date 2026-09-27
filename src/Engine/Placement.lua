--[[
	Smart Scatter — Engine/Placement: putting one copy down (spacing, footing, orientation, variation).
	Adds to E (the engine API); shares internals with the other engine modules through I.
]]

return function(E, I)
	local CollectionService = game:GetService("CollectionService")
	local CORE = I.CORE
	local hasKeyword = I.hasKeyword
	local isLine = I.isLine
	local partsOf = I.partsOf
	local scaleRange = I.scaleRange
	local score = I.score
	local triangle = I.triangle

	--------------------------------------------------------------------------------
	-- Placement
	--------------------------------------------------------------------------------
	-- Spatial hash of everything placed so far, for the spacing rules. An item's "reach" is the furthest any rule can
	-- keep another item from it; a query looks as far as its own reach plus the largest reach stored. The few very
	-- large items (buildings) are kept in a plain list so they don't widen every query.
	local CELL = 8
	local BIG = 32 -- reach above this goes in the list
	local Hash = {}
	Hash.__index = Hash
	local function ckey(cx, cz)
		return cx * 73856093 + cz
	end
	local function reach(it)
		return it.r * math.max(it.sp or 1, it.cs or 1, 1)
	end
	function Hash.new()
		return setmetatable({ cells = {}, big = {}, maxReach = 0 }, Hash)
	end
	function Hash:add(it)
		local rch = reach(it)
		if rch > BIG then
			table.insert(self.big, it)
			return
		end
		local k = ckey(math.floor(it.x / CELL), math.floor(it.z / CELL))
		local c = self.cells[k]
		if not c then
			c = {}
			self.cells[k] = c
		end
		table.insert(c, it)
		if rch > self.maxReach then
			self.maxReach = rch
		end
	end
	-- Real footprints: a long or wide model (a log, a bench, a house) keeps its true outline instead of the circle
	-- round it, so it can sit as close as its shape allows. it.hx / it.hz: half its size across and along; it.yaw:
	-- how it's turned (unknown while its spot is still being tried: then only its narrow side counts, and the spot
	-- is checked again once it's turned). Round things (and older copies) are circles of radius it.r.
	local LONG = 1.3 -- one side this much longer than the other counts as long
	local function footprint(item, m, sc)
		local hx, hz = m.size.X * sc / 2, m.size.Z * sc / 2
		if math.max(hx, hz) >= math.min(hx, hz) * LONG then
			item.hx, item.hz = hx, hz
		end
	end
	-- how far the item reaches from its centre along the unit axis (ux, uz), either way
	local function extent(it, ux, uz)
		if not it.hx then
			return it.r
		end
		if not it.yaw then
			return math.min(it.hx, it.hz)
		end
		local c, s = math.cos(it.yaw), math.sin(it.yaw)
		return it.hx * math.abs(ux * c - uz * s) + it.hz * math.abs(ux * s + uz * c)
	end
	-- the least distance the rules allow between two items, ro / ri: how far each reaches toward the other
	local function minDist(o, it, ro, ri)
		if o.type == it.type then
			if it.g and o.g == it.g then -- same pile: allowed to touch; pieces of one fence are already laid end to end
				return it.fit and 0 or (ro + ri) * 0.9
			end
			return ro * o.sp + ri * it.sp
		elseif o.type == "Building" or it.type == "Building" then -- keep canopies off roofs
			return o.type == "Building" and (ro + ri * 0.6 * it.cs) or (ri + ro * 0.6 * o.cs)
		elseif o.line and it.line then -- two objects lined up along a path: side by side, never inside each other
			return (ro + ri) * 0.85
		end
		return ro * CORE[o.type] * o.cs + ri * CORE[it.type] * it.cs
	end
	-- Too close when no axis separates the two shapes, each grown by what its rule asks (separating axes: the sides
	-- of any turned outline, and the line between the centres). For two circles that's plain distance.
	local function tooClose(o, it)
		local dx, dz = it.x - o.x, it.z - o.z
		local d = math.sqrt(dx * dx + dz * dz)
		local ko, ki = minDist(o, it, 1, 0), minDist(o, it, 0, 1) -- the rules are linear in each reach
		if d > 1e-6 and d >= (ko * extent(o, dx / d, dz / d) + ki * extent(it, dx / d, dz / d)) then
			return false
		end
		for _, t in { o, it } do
			if t.hx and t.yaw then
				local c, s = math.cos(t.yaw), math.sin(t.yaw)
				for _, a in { { c, -s }, { s, c } } do
					if math.abs(dx * a[1] + dz * a[2]) >= ko * extent(o, a[1], a[2]) + ki * extent(it, a[1], a[2]) then
						return false
					end
				end
			end
		end
		return true
	end
	function Hash:conflicts(it)
		for _, o in self.big do
			if tooClose(o, it) then
				return true
			end
		end
		local range = reach(it) + self.maxReach
		for cx = math.floor((it.x - range) / CELL), math.floor((it.x + range) / CELL) do
			for cz = math.floor((it.z - range) / CELL), math.floor((it.z + range) / CELL) do
				local c = self.cells[ckey(cx, cz)]
				if c then
					for _, o in c do
						if tooClose(o, it) then
							return true
						end
					end
				end
			end
		end
		return false
	end

	-- distance from (x,z) to the canopy edge of the nearest item of type t (a type name, or a layer's number: the
	-- copies of that one object), nil if none in range
	function Hash:nearest(x, z, range, t)
		local best
		for _, o in self.big do
			if o.type == t or o.lk == t then
				local d = math.sqrt((o.x - x) ^ 2 + (o.z - z) ^ 2) - o.r * 0.5
				if d <= range and (not best or d < best) then
					best = d
				end
			end
		end
		for cx = math.floor((x - range) / CELL), math.floor((x + range) / CELL) do
			for cz = math.floor((z - range) / CELL), math.floor((z + range) / CELL) do
				local c = self.cells[ckey(cx, cz)]
				if c then
					for _, o in c do
						if o.type == t or o.lk == t then
							local d = math.sqrt((o.x - x) ^ 2 + (o.z - z) ^ 2) - o.r * 0.5
							if not best or d < best then
								best = d
							end
						end
					end
				end
			end
		end
		return best and math.max(best, 0)
	end

	local function rotateUp(up)
		local d = Vector3.yAxis:Dot(up)
		if d > 0.9999 then
			return CFrame.identity
		end
		if d < -0.9999 then
			return CFrame.Angles(math.pi, 0, 0)
		end -- straight down: any axis will do
		return CFrame.fromAxisAngle(Vector3.yAxis:Cross(up).Unit, math.acos(math.clamp(d, -1, 1)))
	end
	E.rotateUp = rotateUp

	-- Which way a model sits on a line. s.front names the side of the model that leads: with "Along" it points down the
	-- line (and that axis sets the piece length), otherwise it's the side that faces what the layer faces (a lantern's
	-- glass toward the road). "Auto" keeps the smart guess: the longer of X/Z runs along the line, -Z is the front.
	E.FRONTS = { "Auto", "-Z", "+Z", "-X", "+X" }
	local FRONT_YAW = { ["-Z"] = 0, ["+Z"] = math.pi, ["-X"] = -math.pi / 2, ["+X"] = math.pi / 2 }
	local function frontOf(s)
		local f = s and s.front
		return FRONT_YAW[f] and f or nil
	end
	local function alongXOf(s, m) -- true when the model's X axis runs along the line
		local f = frontOf(s)
		if f then
			return f == "+X" or f == "-X"
		end
		return m.size.X >= m.size.Z
	end
	local function lengthOf(s, m)
		return alongXOf(s, m) and m.size.X or m.size.Z
	end

	-- A model with an overhang (a street lamp's arm, a sign on a bracket, a basketball hoop) has an obvious front: the
	-- side its top reaches out to. Found from the parts: where the upper parts sit compared with the parts it stands on.
	-- Returns the extra turn that makes that side the front (the side a line's "Face it" turns toward the edge), or nil.
	local function overhangYaw(v)
		if v._over ~= nil then
			return v._over or nil
		end
		local m = v.m
		local H = m.size.Y
		local ref = v.inst:GetPivot().Position
		local base, top, wb, wt = Vector3.zero, Vector3.zero, 0, 0
		for _, p in m.parts do
			local cf, sz = p.CFrame, p.Size
			local vol = math.max(sz.X * sz.Y * sz.Z, 1e-3)
			local lowY = math.huge
			for sx = -1, 1, 2 do
				for sy = -1, 1, 2 do
					for sz2 = -1, 1, 2 do
						lowY = math.min(lowY, (cf * Vector3.new(sz.X / 2 * sx, sz.Y / 2 * sy, sz.Z / 2 * sz2)).Y - ref.Y)
					end
				end
			end
			local rel = cf.Position - ref
			if lowY - m.bottom < H * 0.1 then
				base += rel * vol
				wb += vol
			end -- stands on the ground
			if rel.Y - m.bottom > H * 0.65 then
				top += rel * vol
				wt += vol
			end -- up top
		end
		v._over = false
		if wb > 0 and wt > 0 and H > math.max(m.size.X, m.size.Z) then -- taller than wide: a lamp, a sign post
			local d = top / wt - base / wb
			d = Vector3.new(d.X, 0, d.Z)
			if d.Magnitude > math.max(0.5, math.max(m.size.X, m.size.Z) * 0.2) then
				v._over = math.atan2(d.X, -d.Z)
				local b = base / wb
				v._foot = Vector2.new(b.X, b.Z) -- what it stands on: that goes on the line, not the middle of its arm
			end
		end
		return v._over or nil
	end

	-- the id shared by the pieces of one pile or one line (n: the pile's number, or 99998/99999 for a layer's lines)
	local function groupId(l, n)
		return (l._h % 100000) * 100000 + n
	end

	local function pickVariant(l, rng)
		local r = rng:NextNumber() * l._wsum
		for _, v in l.variants do
			if v.w > 0 then
				r -= v.w
				if r <= 0 then
					return v
				end
			end
		end
		return l.variants[#l.variants]
	end

	-- A piece with a post (or cap, pillar) at one end only: which parts form that post and how far from the centre
	-- they sit along the length (signed, model units). nil when the posts are at both ends or there are none.
	local function capInfo(v, s)
		local alongX = alongXOf(s, v.m)
		if v._cap ~= nil and v._capX == alongX then
			return v._cap or nil
		end
		v._capX = alongX
		local m = v.m
		local A = alongX and Vector3.xAxis or Vector3.zAxis
		local L = alongX and m.size.X or m.size.Z
		local origin = v.inst:GetPivot().Position
		local c = alongX and m.cx or m.cz
		local only, sum, cnt, neg, pos = {}, 0, 0, false, false
		for i, p in partsOf(v.inst) do
			local cf, sz = p.CFrame, p.Size
			local ext = math.abs(cf.RightVector:Dot(A)) * sz.X + math.abs(cf.UpVector:Dot(A)) * sz.Y + math.abs(cf.LookVector:Dot(A)) * sz.Z
			local off = (cf.Position - origin):Dot(A) - c
			if ext < L * 0.4 and math.abs(off) > L * 0.25 then
				only[i] = true
				sum += off
				cnt += 1
				if off < 0 then
					neg = true
				else
					pos = true
				end
			end
		end
		v._cap = (cnt > 0 and neg ~= pos) and { only = only, off = sum / cnt, alongX = alongX } or false
		return v._cap or nil
	end

	-- Shortens a straight piece (fence panel, wall, rail) along its length so it fits a shorter chord of a bend.
	-- Long parts (rails, planks, beams) shrink; short ones (posts, caps, nails) keep their size and just move in,
	-- so a squeezed fence still looks like the same fence. Works in the template's world-aligned frame (see measure).
	local function squeeze(clone, m, sc, f, alongX)
		local A = alongX and Vector3.xAxis or Vector3.zAxis
		local pivot = clone:GetPivot()
		local origin = pivot.Position
		local c = (alongX and m.cx or m.cz) * sc
		local L = (alongX and m.size.X or m.size.Z) * sc
		for _, p in partsOf(clone) do
			local cf = p.CFrame
			local along = (cf.Position - origin):Dot(A)
			local dx, dy, dz = math.abs(cf.RightVector:Dot(A)), math.abs(cf.UpVector:Dot(A)), math.abs(cf.LookVector:Dot(A))
			local sz = p.Size
			if dx * sz.X + dy * sz.Y + dz * sz.Z > L * 0.4 then
				local k = Vector3.new(1 + (f - 1) * dx * dx, 1 + (f - 1) * dy * dy, 1 + (f - 1) * dz * dz)
				p.Size = sz * k
				local mesh = p:FindFirstChildWhichIsA("SpecialMesh")
				if mesh and mesh.MeshType == Enum.MeshType.FileMesh then
					mesh.Scale *= k
				end -- file meshes ignore part size
			end
			p.CFrame = cf + A * ((c - along) * (1 - f))
		end
		-- a model's pivot rides on its PrimaryPart (often an end post that just moved in): pin it back where it was,
		-- or the piece would land off-centre by however far that post moved
		local pp = clone:IsA("Model") and clone.PrimaryPart
		if pp then
			pp.PivotOffset = pp.CFrame:ToObjectSpace(pivot)
		end
	end

	local tag, recolor, dropDetails -- (below)

	-- ── Variation: every copy a little different ──
	-- a colour shifted by (dh hue, ds saturation, dv brightness as a share)
	local function shifted(c, dh, ds, dv)
		local h, s, v = c:ToHSV()
		return Color3.fromHSV((h + dh) % 1, math.clamp(s + ds, 0, 1), math.clamp(v * (1 + dv), 0, 1))
	end
	-- Recolours a copy's parts. Variation on: its own hue / saturation / brightness ranges, one shift for the copy or
	-- one per part. Off: the simple colour shift (tint: brightness and a little hue). zone (optional): the area's
	-- colour zone at the copy's spot { dh, ds, dv }, added on top (it draws no random numbers). Reaches what gives a
	-- part its look: its colour, a MeshPart's SurfaceAppearance (through its Color tint) and any decals or textures.
	recolor = function(parts, s, rng, zone)
		local function roll()
			if s.vary then
				return rng:NextNumber(-s.hueVar, s.hueVar), rng:NextNumber(-s.satVar, s.satVar), rng:NextNumber(-s.valVar, s.valVar)
			elseif s.tint > 0 then -- (brightness drawn first, as always: existing layouts keep their colours)
				local dv = rng:NextNumber(-s.tint, s.tint)
				return rng:NextNumber(-s.tint, s.tint) * 0.15, 0, dv
			end
			return nil
		end
		local dh, ds, dv = roll()
		if not dh and not zone then
			return
		end
		local zh, zs, zv = 0, 0, 0
		if zone then
			zh, zs, zv = zone[1], zone[2], zone[3]
		end
		local each = s.vary and s.perPart
		for _, p in parts do
			if each then -- (the copy's own roll above stays drawn, as always: existing layouts keep their colours)
				dh, ds, dv = roll()
			end
			local h, sa, v = (dh or 0) + zh, (ds or 0) + zs, (dv or 0) + zv
			p.Color = shifted(p.Color, h, sa, v)
			for _, d in p:GetChildren() do
				if d:IsA("SurfaceAppearance") then
					pcall(function()
						d.Color = shifted(d.Color, h, sa, v)
					end) -- (older Studio builds have no SurfaceAppearance.Color)
				elseif d:IsA("Decal") then -- (Texture is a Decal too)
					d.Color3 = shifted(d.Color3, h, sa, v)
				end
			end
		end
	end
	-- the parts a copy can do without: named as details ("Apple", "Leaf_Detail", "ExtraBranch") or marked with the
	-- attribute SS_Optional. Each is left out with the given chance; the copy keeps its main part.
	local DETAIL_WORDS = { "detail", "optional", "extra", "deco", "decoration", "apple", "fruit", "berry", "mushroom", "moss" }
	dropDetails = function(clone, chance, rng)
		local main = clone:IsA("Model") and clone.PrimaryPart or clone
		for _, p in partsOf(clone) do
			if p ~= main and p ~= clone and (p:GetAttribute("SS_Optional") or hasKeyword(p.Name, DETAIL_WORDS)) and rng:NextNumber() < chance then
				p:Destroy()
			end
		end
	end

	-- a quick stand-in for a copy when previewing: one see-through box the size of the model, standing where it would
	local function ghostOf(v, sc, cf, sink)
		local m = v.m
		local p = Instance.new("Part")
		p.Name = v.inst.Name
		p.Size = m.size * sc
		p.CFrame = cf * CFrame.new(0, m.size.Y * sc / 2 - sink, 0)
		p.Transparency, p.CastShadow, p.CanCollide, p.CanTouch, p.CanQuery = 0.55, false, false, false, false
		p.Material, p.Color = Enum.Material.SmoothPlastic, Color3.fromRGB(143, 186, 151)
		return p
	end

	-- a copy made from its model: scaled by sc and stood at cf (its footprint's middle, or a lamp's pole, on the spot;
	-- sunk by sink). Shared by emit and the stamp's preview, so the preview stands exactly where the copy will.
	local function poseCopy(clone, l, v, sc, cf, sink, stretch)
		local m = v.m
		if clone:IsA("Model") then
			if math.abs(sc - 1) > 1e-3 then
				clone:ScaleTo(clone:GetScale() * sc)
			end
		else
			clone.Size *= sc
		end
		if stretch and math.abs(stretch - 1) > 0.005 then
			squeeze(clone, m, sc, math.min(stretch, 1.15), alongXOf(l.s, m))
		end
		-- a line stands a lamp by its pole (the footprint's middle would be out along its arm)
		local cx, cz = m.cx, m.cz
		if isLine(l) then -- a lamp stands on the line by its pole, whichever way it faces
			overhangYaw(v)
			if v._foot then
				cx, cz = v._foot.X, v._foot.Y
			end
		end
		clone:PivotTo(cf * CFrame.new(-cx * sc, -m.bottom * sc - sink, -cz * sc) * m.rel)
	end
	E.poseCopy = poseCopy

	-- makes one copy: clone, scale, place, tint, game-ready flags, tags; registers it for spacing. Nothing is made in a
	-- keep-clear zone (returns nil). stretch (optional, < 1): squeeze the piece along its length to fit a bend
	local function emit(ctx, l, v, sc, cf, rng, x, z, item, sink, gid, stacked, stretch, only, uprightPosts)
		if E.isCleared(ctx.clear, x, z) then
			return nil
		end
		local s, m = l.s, v.m
		local out = ctx.output
		if out.ghost then
			local box = ghostOf(v, sc, cf, sink)
			ctx.parts += 1
			return tag(ctx, l, box, x, z, item, gid, stacked)
		end
		local clone = (v.src or v.inst):Clone() -- src: a procedural model, frozen
		if only then -- keep just these parts (by index in partsOf order): an end post taken from the model itself
			for i, p in partsOf(clone) do
				if not only[i] and p ~= clone then
					p:Destroy()
				end
			end
		end
		poseCopy(clone, l, v, sc, cf, sink, stretch)
		if uprightPosts and math.abs(cf.RightVector.Y) + math.abs(cf.LookVector.Y) > 0.02 then
			-- a piece tilted to follow a slope: its posts stand straight again (rails slope, posts don't lean)
			local A = alongXOf(s, m) and cf.RightVector or cf.LookVector
			local L = lengthOf(s, m) * sc
			for _, p in partsOf(clone) do
				local pcf, sz = p.CFrame, p.Size
				local ext = math.abs(pcf.RightVector:Dot(A)) * sz.X + math.abs(pcf.UpVector:Dot(A)) * sz.Y + math.abs(pcf.LookVector:Dot(A)) * sz.Z
				-- its long axis (a post is tall and thin, so that's the one that stood up in the template)
				local axes = { { pcf.RightVector, sz.X }, { pcf.UpVector, sz.Y }, { pcf.LookVector, sz.Z } }
				table.sort(axes, function(a, b)
					return a[2] > b[2]
				end)
				local ax, len = axes[1][1], axes[1][2]
				if ext < L * 0.4 and len >= math.max(axes[2][2], axes[3][2]) * 1.5 then -- tall and thin across the run: a post
					if ax.Y < 0 then
						ax = -ax
					end
					local rot = ax:Cross(Vector3.yAxis)
					local ang = math.acos(math.clamp(ax.Y, -1, 1))
					if rot.Magnitude > 1e-4 and ang > 1e-3 then
						local bottom = pcf.Position - ax * (len / 2) -- keep its foot where it was
						local upright = CFrame.fromAxisAngle(rot.Unit, ang) * pcf.Rotation
						p.CFrame = CFrame.new(bottom + Vector3.yAxis * (len / 2)) * upright
					end
				end
			end
		end
		if s.vary and s.dropDetails > 0 then
			dropDetails(clone, s.dropDetails, rng)
		end
		local zh, zs, zv = E.zoneShift(ctx.area, x, z)
		recolor(partsOf(clone), s, rng, zh and { zh, zs, zv } or nil)
		local small = l.type == "Flower" or l.type == "Bush"
		local parts = partsOf(clone)
		ctx.parts += #parts
		for _, p in parts do
			p.Anchored = true
			if out.walk and small then
				p.CanCollide = false
				p.CanTouch = false
			end
			if out.shadows and (l.type == "Flower" or p.Size.Magnitude < 2.5) then
				p.CastShadow = false
			end
			if out.query and l.type == "Flower" then
				p.CanQuery = false
			end
		end
		return tag(ctx, l, clone, x, z, item, gid, stacked)
	end

	-- tags a finished copy (what spacing, counting, Erase and Bake look for), puts it in its folder and registers it
	function tag(ctx, l, clone, x, z, item, gid, stacked)
		local s = l.s
		CollectionService:AddTag(clone, E.TAG)
		clone:SetAttribute("SS_Type", l.type)
		clone:SetAttribute("SS_L", l._h) -- which object it is (kept copies still count for "grows near")
		clone:SetAttribute("SS_X", x)
		clone:SetAttribute("SS_Z", z)
		clone:SetAttribute("SS_R", item.r)
		if item.pin then -- put down by hand (Engine/Pins): removing it takes the pin away
			clone:SetAttribute("SS_Pin", true)
		end
		if item.hx and item.yaw then -- its outline, for the next runs that keep it
			clone:SetAttribute("SS_Fp", Vector3.new(item.hx, item.yaw, item.hz))
		end
		clone:SetAttribute("SS_Sp", s.spacing)
		clone:SetAttribute("SS_Cs", s.clearance)
		if gid then
			clone:SetAttribute("SS_G", gid)
		end
		if stacked then
			clone:SetAttribute("SS_Stacked", true)
		end
		clone.Parent = ctx.parentFor(l, x, z)
		if not stacked then
			ctx.hash:add(item)
		end
		return clone
	end

	-- Mitre joint: the long parts of a piece (rails, planks, wall slabs, path tiles) are extended or trimmed at one end
	-- so they meet the plane that halves the angle to the neighbouring piece, like a carpenter's mitre. A: the piece's
	-- direction; J: the joint point; nB: the bisector plane's normal (pointing along the run); atEnd: true for the far end.
	-- A box can't be cut on a slant, so a WIDE part (a tile, a thick wall) is trimmed until its INNER corner meets that
	-- plane: the two pieces then touch without overlapping (overlapping faces flicker), and the small wedge left open on
	-- the outside of the bend is filled afterwards by fillJoint. Returns those wide parts for it.
	local function mitre(clone, A, J, nB, atEnd, pieceLen)
		local wide = {}
		for _, p in partsOf(clone) do
			local pcf, sz = p.CFrame, p.Size
			local axes = { { pcf.RightVector, sz.X, "X" }, { pcf.UpVector, sz.Y, "Y" }, { pcf.LookVector, sz.Z, "Z" } }
			local best, bd = nil, 0
			for _, ax in axes do
				local d = math.abs(ax[1]:Dot(A))
				if d > bd then
					best, bd = ax, d
				end
			end
			if best and bd > 0.9 and best[2] > pieceLen * 0.4 then -- a long part running with the piece
				local axis = best[1]:Dot(A) > 0 and best[1] or -best[1]
				local half = best[2] / 2
				local e = pcf.Position + axis * (atEnd and half or -half) -- the end face's centre
				local denom = axis:Dot(nB)
				if math.abs(denom) > 0.2 then
					local shift = (J - e):Dot(nB) / denom -- how far that end must move along the part to reach the plane
					-- its width: the other axis that lies most level (a tile's width, a wall's thickness)
					local lat, ld = nil, math.huge
					for _, ax in axes do
						if ax ~= best then
							local up = math.abs(ax[1].Y)
							if up < ld then
								lat, ld = ax, up
							end
						end
					end
					local isWide = lat and lat[2] > 0.5
					if isWide then -- the inner side corner: whichever needs the end pulled back the most
						for sgn = -1, 1, 2 do
							local sc = (J - (e + lat[1] * (lat[2] / 2 * sgn))):Dot(nB) / denom
							if (atEnd and sc < shift) or (not atEnd and sc > shift) then
								shift = sc
							end
						end
					end
					-- never trim more than most of the part away: on a bend tighter than the piece is wide, trim what's
					-- possible and let the fill close the rest (skipping the joint would leave a gap)
					if isWide then
						shift = math.clamp(shift, -best[2] * 0.45, best[2] * 0.45)
					end
					if math.abs(shift) < best[2] * 0.5 then
						local grow = atEnd and shift or -shift
						local size = sz
						if best[3] == "X" then
							size = Vector3.new(sz.X + grow, sz.Y, sz.Z)
						elseif best[3] == "Y" then
							size = Vector3.new(sz.X, sz.Y + grow, sz.Z)
						else
							size = Vector3.new(sz.X, sz.Y, sz.Z + grow)
						end
						p.Size = size
						p.CFrame = pcf + axis * (shift / 2)
						if isWide then
							local upAx
							for _, ax in axes do
								if ax ~= best and ax ~= lat then
									upAx = ax
								end
							end
							table.insert(wide, { p = p, along = best[3], across = lat[3], up = upAx[3], sign = axis:Dot(best[1]) > 0 and 1 or -1 })
						end
					end
				end
			end
		end
		return wide
	end

	-- Fills the wedge a bend leaves open on the outside between two wide parts that were mitred to their inner corners:
	-- a solid kite (two triangles) from the shared inner corner to both outer corners and the point where the outer edges
	-- would meet, as thick as the part and made of the same material. ea: the part ending at the joint, eb: the one
	-- starting there (from mitre). The fill becomes part of the first piece, so it's cleared and counted with it.
	local AXIS = { X = "RightVector", Y = "UpVector", Z = "LookVector" }
	local function fillJoint(ea, eb, nB)
		local function frame(e, atEnd)
			local p = e.p
			local cf, sz = p.CFrame, p.Size
			local along = cf[AXIS[e.along]] * e.sign
			local across, up = cf[AXIS[e.across]], cf[AXIS[e.up]]
			if up.Y < 0 then
				up = -up
			end
			local L, W, H = sz[e.along], sz[e.across], sz[e.up]
			local c = p.Position + along * (L / 2) * (atEnd and 1 or -1) + up * (H / 2) -- top of the end face
			return c + across * (W / 2), c - across * (W / 2), along, H
		end
		local a1, a2, dirA, H = frame(ea, true)
		local b1, b2 = frame(eb, false)
		if (a1 - b2).Magnitude + (a2 - b1).Magnitude < (a1 - b1).Magnitude + (a2 - b2).Magnitude then
			b1, b2 = b2, b1
		end
		local ai, bi, ao, bo = a1, b1, a2, b2 -- inner corners (touching) and outer ones (apart)
		if (a1 - b1).Magnitude > (a2 - b2).Magnitude then
			ai, bi, ao, bo = a2, b2, a1, b1
		end
		if (ao - bo).Magnitude < 0.02 then
			return 0
		end
		local I = (ai + bi) / 2
		local denom = dirA:Dot(nB)
		if math.abs(denom) < 0.2 then
			return 0
		end
		local s = (I - ao):Dot(nB) / denom -- along A's outer edge to the bisector: where the two outer edges meet
		if s < 0 or s > (ao - ai).Magnitude * 2 then
			return 0
		end
		local O = ao + dirA * s
		local tmp = Instance.new("Folder")
		local style = { mat = ea.p.Material, color = ea.p.Color }
		local n = triangle(tmp, style, I, ao, O, H) + triangle(tmp, style, I, O, bo, H)
		for _, w in tmp:GetChildren() do
			w.MaterialVariant, w.Transparency, w.Reflectance = ea.p.MaterialVariant, ea.p.Transparency, ea.p.Reflectance
			w.CastShadow, w.CanCollide, w.CanQuery, w.CanTouch = ea.p.CastShadow, ea.p.CanCollide, ea.p.CanQuery, ea.p.CanTouch
			w.Name = "JointFill"
			w.Parent = ea.p.Parent
		end
		tmp:Destroy()
		return n
	end

	-- true when the scanned ground within `r` of a grid cell sits at the same height (no need for extra settle rays)
	local function flatAround(an, ix, iz, y, r)
		local k = math.clamp(math.ceil(r / an.G), 1, 3)
		for jz = math.max(iz - k, 0), math.min(iz + k, an.nz - 1) do
			for jx = math.max(ix - k, 0), math.min(ix + k, an.nx - 1) do
				local j = jz * an.nx + jx + 1
				if an.cls[j] ~= "None" and math.abs(an.y[j] - y) > 0.25 then
					return false
				end
			end
		end
		return true
	end

	-- The keep-away rules at the exact spot. The distance fields are measured between 4-stud cell centres, but a spot is
	-- jittered anywhere inside its cell, so near an edge the field alone lets a tree creep up to the shoreline. Near an
	-- edge this checks every cell of that kind around the spot, treating each as a solid square (the conservative side).
	local KEEP_CLASS = { Buildings = "Building", Roads = "Road", Water = "Water" }
	local function clearAt(an, i, x, z, field, k)
		if k <= 0 or an.dist[field][i] >= k + an.G * 1.5 then
			return true
		end -- well away: the field is exact enough
		local want, G = KEEP_CLASS[field], an.G
		local r = math.ceil(k / G) + 1
		local ix, iz = (i - 1) % an.nx, (i - 1) // an.nx
		for jz = math.max(iz - r, 0), math.min(iz + r, an.nz - 1) do
			for jx = math.max(ix - r, 0), math.min(ix + r, an.nx - 1) do
				if an.cls[jz * an.nx + jx + 1] == want then
					local cx0, cz0 = an.x0 + jx * G, an.z0 + jz * G
					local dx = math.max(cx0 - x, 0, x - (cx0 + G))
					local dz = math.max(cz0 - z, 0, z - (cz0 + G))
					if dx * dx + dz * dz < k * k then
						return false
					end
				end
			end
		end
		return true
	end

	-- g (optional): { v = variant, sc = scale, member = true, gid = group id, stackOn = info of the piece below,
	--   pin = true for a copy put down by hand (its spot is given: no clumping or other chance rules),
	--   exact = true for a stamp (Engine/Pins: its spot, turn, size and model are given, and no rule moves or refuses
	--   it; only the ground sets its height), dry = true to only work out where it would stand (the stamp's preview) }
	local function placeAt(ctx, l, i, x, z, rng, g)
		g = g or {}
		local v = g.v or pickVariant(l, rng)
		local an, s, m = ctx.an, l.s, v.m
		local exact = g.exact
		i = i or E.indexAt(an, x, z)
		if not i or (not an.inM[i] and not g.line and not exact) then
			return nil
		end -- lines come from the area's own edge
		if g.line and E.isCleared(ctx.clear, x, z) then
			return nil
		end -- (the area's own cells already leave zones out)
		local ix, iz = (i - 1) % an.nx, (i - 1) // an.nx
		if (g.member or g.pin) and not g.stackOn and not exact then
			-- a group member (or a copy pinned by hand) must still obey the layer's rules at its own spot
			if score(l, an, i) <= 0 then
				return nil
			end
			if l.paint and E.paintValue(l, math.floor(x / an.cell), math.floor(z / an.cell)) <= 0 then
				return nil
			end
		end

		local keep = 0.5
		if g.member or g.line or g.pin then
			-- followers go wherever the leader decided, pins where they were put
		else
			if s.cluster > 0 then -- natural clumps
				local f = (m.radius * 8 + 10) * math.max(s.clumpSize, 0.1)
				keep = math.clamp(0.5 + math.noise(x / f, z / f, (ctx.seed % 997) + (l._h % 1000) * 0.173) * 2.2, 0, 1)
				if rng:NextNumber() > 1 - s.cluster * (1 - keep) then
					return nil
				end
			end
			if s.hug == "Trees" then -- undergrowth: gather around trees already placed
				local d = ctx.hash:nearest(x, z, s.hugRange + 16, "Tree")
				local near = d and math.clamp(1 - d / math.max(s.hugRange, 1), 0, 1) or 0
				if rng:NextNumber() > (1 - s.hugStrength) + s.hugStrength * near then
					return nil
				end
			end
			if l._nearH then -- grows close to another object's copies (placed before it)
				local d = ctx.hash:nearest(x, z, s.nearRange + 16, l._nearH)
				local near = d and math.clamp(1 - d / math.max(s.nearRange, 1), 0, 1) or 0
				if rng:NextNumber() > (1 - s.nearStrength) + s.nearStrength * near then
					return nil
				end
			end
		end

		-- bigger specimens toward the middle of clumps, smaller at the fringes
		local lo, hi = scaleRange(l)
		local t = s.cluster > 0 and math.clamp(rng:NextNumber() * 0.7 + keep * 0.3, 0, 1) or rng:NextNumber()
		local sc = g.sc or (lo + (hi - lo) * t) * v.size
		if s.edgeYoung > 0 and not g.line and not g.sc then -- the young fringe: smaller toward the edge and clearings
			local reach = 12 + m.radius * sc * 4
			local open = math.clamp(an.dist.Edge[i] / reach, 0, 1) * math.clamp(E.patchAt(ctx.area, x, z) * 1.25, 0, 1)
			sc *= 1 - s.edgeYoung * 0.6 * (1 - open)
		end
		local item = {
			x = x,
			z = z,
			r = math.max(m.radius * sc, 0.25),
			type = l.type,
			sp = s.spacing,
			cs = s.clearance,
			g = g.gid,
			fit = g.stretch ~= nil,
			lk = l._h,
			pin = g.pin,
		}
		if not g.line and not g.stackOn then
			footprint(item, m, sc)
		end

		local base = g.stackOn
		local hit, y
		if base then
			-- stacking: sits on top of the piece below, no ground checks
			y = base.top
		else
			if not g.post and not exact and ctx.hash:conflicts(item) then
				return nil
			end -- posts sit on the joints of their own panels
			if not g.line and not exact then
				local cr = l._core or 0
				if not clearAt(an, i, x, z, "Water", s.keepWater + cr) then
					return nil
				end
				if not clearAt(an, i, x, z, "Buildings", s.keepBuilding + cr) then
					return nil
				end
				if not s.surfaces.Road and not clearAt(an, i, x, z, "Roads", s.keepRoad + cr) then
					return nil
				end
			end
			hit = E.cast(Vector3.new(x, an.top, z), Vector3.new(0, -an.len, 0), an.rp)
			if not hit or hit.Material == Enum.Material.Water then
				return nil
			end
			-- (parts the area was filled from take anything, whatever they're made of: see the scan)
			if not exact and not s.surfaces[(E.surfaceOf(hit.Instance, hit.Material))] and not (an and i and an.on[i]) then
				return nil
			end
			if not exact and math.deg(math.acos(math.clamp(hit.Normal.Y, -1, 1))) > s.maxSlope then
				return nil
			end
			y = hit.Position.Y
		end
		local yaw
		local function pickYaw()
			if s.yawMode == "Fixed" then
				return math.rad(s.yaw)
			end
			if s.yawMode == "Snap" then
				return rng:NextInteger(0, 3) * math.pi / 2
			end
			return rng:NextNumber(0, math.pi * 2)
		end

		if l.type == "Building" and not base and not exact then -- (a stamped house settles like anything else, below)
			if g.yaw then
				yaw = g.yaw
			elseif s.faceRoad and an.dist.Roads[i] < 90 then -- turn the front (-Z / LookVector) toward the nearest road
				local f = an.dist.Roads
				local function at(a, b)
					a = math.clamp(a, 0, an.nx - 1)
					b = math.clamp(b, 0, an.nz - 1)
					return f[b * an.nx + a + 1]
				end
				local gx, gz = at(ix + 2, iz) - at(ix - 2, iz), at(ix, iz + 2) - at(ix, iz - 2)
				if gx * gx + gz * gz > 1e-6 then
					yaw = math.atan2(gx, gz)
				end
			end
			yaw = yaw or pickYaw()
			-- whole footprint must be valid, level ground
			local hx, hz = m.size.X * sc / 2, m.size.Z * sc / 2
			local rot = CFrame.Angles(0, yaw, 0)
			local nxs, nzs = math.clamp(math.ceil(hx * 2 / an.G), 2, 8), math.clamp(math.ceil(hz * 2 / an.G), 2, 8)
			local mnY, mxY = y, y
			for a = 0, nxs do
				for b = 0, nzs do
					local o = rot:VectorToWorldSpace(Vector3.new(-hx + 2 * hx * a / nxs, 0, -hz + 2 * hz * b / nzs))
					local j = E.indexAt(an, x + o.X, z + o.Z)
					if not j then
						return nil
					end
					if not an.inM[j] then
						return nil
					end -- the whole house stays inside the painted area
					local c = an.cls[j]
					if not s.surfaces[c] and not an.on[j] then
						return nil
					end
					if an.dist.Buildings[j] < s.keepBuilding then
						return nil
					end
					if not s.surfaces.Road and an.dist.Roads[j] < s.keepRoad then
						return nil
					end
					if an.dist.Water[j] < s.keepWater then
						return nil
					end
					mnY = math.min(mnY, an.y[j])
					mxY = math.max(mxY, an.y[j])
				end
			end
			if mxY - mnY > math.max(1.5, math.max(hx, hz) * 0.08) then
				return nil
			end
			y = mnY
		else
			yaw = g.yaw or pickYaw()
			-- settle upright things on slopes: use the lowest ground under the base so the downhill side never floats
			local rr = math.max(item.r * CORE[l.type] * 0.6, 0.4)
			if s.align < 1 and not base and not flatAround(an, ix, iz, y, rr) then
				for k = 0, 3 do
					local a = k * math.pi / 2 + yaw
					local h2 = E.cast(Vector3.new(x + math.cos(a) * rr, an.top, z + math.sin(a) * rr), Vector3.new(0, -an.len, 0), an.rp)
					if h2 and h2.Position.Y < y then
						y = math.max(h2.Position.Y, y - rr * 1.5)
					end
				end
			end
		end

		if item.hx then -- now it's turned: its real outline must fit where only its narrow side was tried
			item.yaw = yaw
			if not base and not g.post and not exact and ctx.hash:conflicts(item) then
				return nil
			end
		end

		local up = (s.align > 0 and hit) and Vector3.yAxis:Lerp(hit.Normal, s.align).Unit or Vector3.yAxis
		local cf = CFrame.new(x, y, z) * rotateUp(up) * CFrame.Angles(0, yaw, 0)
		if s.tilt > 0 and not base and not exact and not (g.line and s.fit) then
			cf *= CFrame.Angles(math.rad(rng:NextNumber(-s.tilt, s.tilt)), 0, math.rad(rng:NextNumber(-s.tilt, s.tilt)))
		end
		if s.lean > 0 and not base and not exact and not (g.line and s.fit) then -- all the same way, like a windswept stand of trees
			local wd = math.rad(ctx.area.windDir or 0)
			local axis = Vector3.yAxis:Cross(Vector3.new(math.sin(wd), 0, math.cos(wd))) -- turns "up" toward the wind
			cf = CFrame.new(cf.Position) * CFrame.fromAxisAngle(axis, math.rad(s.lean) * rng:NextNumber(0.7, 1.3)) * cf.Rotation
		end

		if l.type ~= "Flower" and not base and not exact then -- don't clip into the user's own geometry
			local h = math.max(m.size.Y * sc - 1, 1)
			local real = l.type == "Building" or g.line
			local w = real and m.size.X * sc or math.max(1, item.r * CORE[l.type] * 2)
			local d = real and m.size.Z * sc or w
			if g.stretch then -- as long as the piece really gets (squeeze stretches at most 15%)
				local st = math.min(g.stretch, 1.15)
				if alongXOf(s, m) then
					w *= st
				else
					d *= st
				end
			end
			for _, p in workspace:GetPartBoundsInBox(cf * CFrame.new(0, 1 + h / 2, 0), Vector3.new(w * 0.95, h, d * 0.95), ctx.op) do
				if p ~= hit.Instance then
					return nil
				end
			end
		end

		local sink = base and 0 or s.sink * m.size.Y * sc
		if g.dry then
			return { cf = cf, sc = sc, sink = sink, v = v }
		end
		local made = emit(ctx, l, v, sc, cf, rng, x, z, item, sink, g.gid, base ~= nil, g.stretch)
		if not made then
			return nil -- not made after all (a keep-clear zone): it mustn't count as placed
		end
		return { x = x, z = z, r = item.r, sc = sc, v = v, top = y - sink + m.size.Y * sc, stacked = base ~= nil, clone = made }
	end

	local function place(ctx, l, i, rng, gid)
		local an = ctx.an
		local ix, iz = (i - 1) % an.nx, (i - 1) // an.nx
		local x = an.x0 + (ix + rng:NextNumber()) * an.G
		local z = an.z0 + (iz + rng:NextNumber()) * an.G
		return placeAt(ctx, l, i, x, z, rng, gid and { gid = gid } or nil)
	end

	-- a pile around a leader: members touch (tightness), may stack, share the leader's model if asked
	local function growGroup(ctx, l, lead, gid, want, rng)
		local s = l.s
		local members, got, tries = { lead }, 0, 0
		while got < want and tries < want * 10 + 6 do
			tries += 1
			local basePiece = members[rng:NextInteger(1, #members)]
			local v = s.sameModel and lead.v or pickVariant(l, rng)
			local sc = lead.sc / lead.v.size * v.size * rng:NextNumber(0.92, 1.08)
			local info
			-- stack only on a flat top the new piece fits on (crates on crates); a tree or a rock has nothing to sit on
			local fits = basePiece.v.m.flatTop >= 0.45 and v.m.radius * math.min(sc, basePiece.sc) <= basePiece.r * 1.1
			if s.stack > 0 and fits and not basePiece.stacked and rng:NextNumber() < s.stack then
				local jitter = basePiece.r * 0.08
				info = placeAt(
					ctx,
					l,
					nil,
					basePiece.x + rng:NextNumber(-jitter, jitter),
					basePiece.z + rng:NextNumber(-jitter, jitter),
					rng,
					{ v = v, sc = math.min(sc, basePiece.sc), member = true, gid = gid, stackOn = basePiece }
				)
			else
				local ang = rng:NextNumber(0, math.pi * 2)
				local d = (basePiece.r + v.m.radius * sc) * math.max(s.tight, 0.9)
				info = placeAt(
					ctx,
					l,
					nil,
					basePiece.x + math.cos(ang) * d,
					basePiece.z + math.sin(ang) * d,
					rng,
					{ v = v, sc = sc, member = true, gid = gid }
				)
			end
			if info then
				table.insert(members, info)
				got += 1
			end
		end
		return got
	end

	-- shared with the modules after this one
	I.Hash = Hash
	I.FRONT_YAW = FRONT_YAW
	I.frontOf = frontOf
	I.alongXOf = alongXOf
	I.lengthOf = lengthOf
	I.overhangYaw = overhangYaw
	I.groupId = groupId
	I.pickVariant = pickVariant
	I.capInfo = capInfo
	I.emit = emit
	I.mitre = mitre
	I.fillJoint = fillJoint
	I.placeAt = placeAt
	I.place = place
	I.growGroup = growGroup
end
