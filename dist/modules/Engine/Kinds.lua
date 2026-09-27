--[[
	Smart Scatter — Engine/Kinds: reading a finished map. Every repeated model is found and grouped into kinds by its
	shape, not its name, so renamed, turned and scaled copies still match; and the snapshot that keeps the originals
	of what later tools change (swapping models, seasons), so they can be put back.
	Adds to E (the engine API); shares internals with the other engine modules through I.
]]

return function(E, I)
	local STEP = 40 -- a side is known to 1/40 of the copy's longest side: tells shapes apart, forgives float error
	local SNAPSHOT = "SmartScatter Snapshot"

	--------------------------------------------------------------------------------
	-- Shape keys
	--------------------------------------------------------------------------------
	-- The key of a shape given as its parts { { kind = "MeshPart:rbxassetid://1", size = Vector3 }, ... }: every
	-- part's sides, longest first (so turning doesn't matter), as fractions of the longest side of any part (so
	-- scale doesn't matter), sorted. Returns the key and that longest side (a copy's size, to compare copies by).
	function E.shapeKey(parts)
		local unit = 0
		for _, p in parts do
			unit = math.max(unit, p.size.X, p.size.Y, p.size.Z)
		end
		if #parts == 0 or unit <= 0 then
			return nil, 0
		end
		local keys = table.create(#parts)
		for i, p in parts do
			local d = { p.size.X, p.size.Y, p.size.Z }
			table.sort(d, function(a, b)
				return a > b
			end)
			local q = function(v)
				return math.floor(v / unit * STEP + 0.5)
			end
			keys[i] = string.format("%s/%d,%d,%d", p.kind, q(d[1]), q(d[2]), q(d[3]))
		end
		table.sort(keys)
		return #parts .. "|" .. table.concat(keys, "|"), unit
	end

	-- what a part is, apart from its size: its class, and its mesh or its shape
	local function partKind(p)
		if p:IsA("MeshPart") then
			return "MeshPart:" .. p.MeshId
		elseif p:IsA("Part") then
			local sm = p:FindFirstChildOfClass("SpecialMesh")
			if sm then
				return "Mesh:" .. sm.MeshType.Name .. ":" .. sm.MeshId
			end
			return "Part:" .. p.Shape.Name
		end
		return p.ClassName
	end
	local function describe(inst)
		local parts = {}
		local list = inst:IsA("BasePart") and { inst } or inst:GetDescendants()
		for _, p in list do
			if p:IsA("BasePart") then
				table.insert(parts, { kind = partKind(p), size = p.Size })
			end
		end
		return parts
	end
	-- a model's key (nil when it has no parts)
	function E.keyOf(inst)
		return E.shapeKey(describe(inst))
	end

	--------------------------------------------------------------------------------
	-- Scanning a map for kinds
	--------------------------------------------------------------------------------
	-- a single part counts as a copy only when it has a shape of its own (a mesh or a union), not a plain block:
	-- floors and walls built from blocks aren't copies of a model
	local function shapedPart(p)
		return p:IsA("MeshPart") or p:IsA("UnionOperation") or (p:IsA("Part") and p:FindFirstChildOfClass("SpecialMesh") ~= nil)
	end
	local function skipped(inst)
		if inst:IsA("Terrain") or inst:IsA("Camera") then
			return true
		end
		if inst.Name == E.OUT or inst.Name == E.ROADS then -- what the plugin placed: its areas own it
			return inst.Parent == workspace
		end
		return inst:IsA("Model") and inst:FindFirstChildOfClass("Humanoid") ~= nil -- players and NPCs
	end

	-- Finds the kinds in a map: every model or shaped part that has at least one other copy of the same shape.
	-- A copy inside another copy (a window in a house) stays part of it, unless opts.nested. opts.roots: where to
	-- look (default the whole Workspace); opts.pause: called now and then on a big map (e.g. task.wait, to keep
	-- Studio responsive).
	-- Returns the kinds, most copies first: { key, name, count, copies = { { inst, scale } }, parts }. A copy's
	-- scale is its size against the kind's first copy.
	function E.scanKinds(opts)
		opts = opts or {}
		local roots = opts.roots or { workspace }
		-- every candidate's key, and how many share it
		local keyOf, sizeOf, count, seen = {}, {}, {}, 0
		local function visit(inst)
			if skipped(inst) then
				return
			end
			if inst:IsA("Model") or (inst:IsA("BasePart") and shapedPart(inst)) then
				local key, size = E.keyOf(inst)
				if key then
					keyOf[inst], sizeOf[inst] = key, size
					count[key] = (count[key] or 0) + 1
				end
			end
			seen += 1
			if opts.pause and seen % 3000 == 0 then
				opts.pause()
			end
			for _, c in inst:GetChildren() do
				visit(c)
			end
		end
		for _, r in roots do
			visit(r)
		end
		-- then from the top down: the first repeated shape on each branch is a copy, and what's inside it is its own
		local byKey, list = {}, {}
		local function pick(inst)
			if skipped(inst) then
				return
			end
			local key = keyOf[inst]
			if key and count[key] >= 2 then
				local k = byKey[key]
				if not k then
					k = { key = key, copies = {}, names = {}, parts = #describe(inst) }
					byKey[key] = k
					table.insert(list, k)
				end
				table.insert(k.copies, { inst = inst, size = sizeOf[inst] })
				k.names[inst.Name] = (k.names[inst.Name] or 0) + 1
				if not opts.nested then
					return
				end
			end
			for _, c in inst:GetChildren() do
				pick(c)
			end
		end
		for _, r in roots do
			pick(r)
		end
		local kinds = {}
		for _, k in list do
			if #k.copies >= 2 then -- (a shape repeated only inside other copies has one left here)
				local name, most = "?", 0
				for n, c in k.names do
					if c > most or (c == most and n < name) then
						name, most = n, c
					end
				end
				local ref = k.copies[1].size
				for _, c in k.copies do
					c.scale = ref > 0 and c.size / ref or 1
					c.size = nil
				end
				table.insert(kinds, { key = k.key, name = name, count = #k.copies, copies = k.copies, parts = k.parts })
			end
		end
		table.sort(kinds, function(a, b)
			if a.count ~= b.count then
				return a.count > b.count
			end
			return a.name < b.name
		end)
		return kinds
	end

	--------------------------------------------------------------------------------
	-- The snapshot: originals kept before anything changes them
	--------------------------------------------------------------------------------
	-- ServerStorage › SmartScatter Snapshot holds one entry per saved copy: the original (a clone, as it was), where
	-- it lived, and the copy in the map now. A copy is saved once, so the snapshot always holds the true original,
	-- however many times it's changed afterwards. Tools that change a copy say so (E.snapshotChanged); Restore puts
	-- back the changed ones.
	local function folder(make)
		local ss = game:GetService("ServerStorage")
		local f = ss:FindFirstChild(SNAPSHOT)
		if not f and make then
			f = Instance.new("Folder")
			f.Name = SNAPSHOT
			f:SetAttribute("SS_Saved", os.time())
			f.Parent = ss
		end
		return f
	end
	local function entries()
		local f = folder(false)
		return f and f:GetChildren() or {}
	end
	-- [copy in the map] = its entry, rebuilt whenever it doesn't match the folder (after an undo, say)
	local index = {}
	local function entryOf(inst)
		local e = index[inst]
		local ok = e and e.Parent == folder(false) and e:FindFirstChild("Now") and e.Now.Value == inst
		if not ok then
			index = {}
			for _, x in entries() do
				local now = x:FindFirstChild("Now")
				if now and now.Value then
					index[now.Value] = x
				end
			end
			e = index[inst]
		end
		return e
	end

	-- keeps the originals of these copies (ones already kept are skipped). Returns how many were added.
	function E.snapshot(list)
		local have = {}
		for _, e in entries() do
			local now = e:FindFirstChild("Now")
			if now and now.Value then
				have[now.Value] = true
			end
		end
		local f, added = nil, 0
		for _, inst in list do
			if not have[inst] and inst.Parent then
				local old = inst.Archivable
				inst.Archivable = true -- (a clone of a non-archivable instance is nil)
				local copy = inst:Clone()
				inst.Archivable = old
				if copy then
					f = f or folder(true)
					local e = Instance.new("Folder")
					e.Name = inst.Name
					local where = Instance.new("ObjectValue")
					where.Name = "Where"
					where.Value = inst.Parent
					where.Parent = e
					local now = Instance.new("ObjectValue")
					now.Name = "Now"
					now.Value = inst
					now.Parent = e
					copy.Name = "Original"
					copy.Parent = e
					e.Parent = f
					index[inst] = e
					have[inst] = true
					added += 1
				end
			end
		end
		return added
	end

	-- a tool changed a kept copy: swapped it for `now`, moved or recoloured it in place (now nil: the same copy),
	-- or took it out (now false). Returns whether the copy was in the snapshot.
	function E.snapshotChanged(inst, now)
		local e = entryOf(inst)
		if not e then
			return false
		end
		if now == false then
			e.Now.Value = nil
		else
			e.Now.Value = now or inst
			index[now or inst] = e
		end
		if now ~= nil then
			index[inst] = nil
		end
		e:SetAttribute("SS_Changed", true)
		return true
	end

	-- a tool added a copy that wasn't in the map: Restore takes it out again
	function E.snapshotAdded(inst)
		local f = folder(true)
		local e = Instance.new("Folder")
		e.Name = inst.Name
		local now = Instance.new("ObjectValue")
		now.Name = "Now"
		now.Value = inst
		now.Parent = e
		e:SetAttribute("SS_Added", true)
		e:SetAttribute("SS_Changed", true)
		e.Parent = f
		index[inst] = e
	end

	-- { saved = copies kept, changed = copies changed (or added) since, time = when it was started } or nil
	function E.snapshotInfo()
		local f = folder(false)
		if not f then
			return nil
		end
		local saved, changed = 0, 0
		for _, e in f:GetChildren() do
			saved += e:GetAttribute("SS_Added") and 0 or 1
			changed += e:GetAttribute("SS_Changed") and 1 or 0
		end
		return { saved = saved, changed = changed, time = f:GetAttribute("SS_Saved") }
	end

	-- puts every changed copy back as it was, where it was (the originals stay kept, so it can be done again).
	-- only (optional): a set of copies now in the map, { [inst] = true }: just those go back. Returns how many were
	-- put back, and [copy that was in the map] = the original now back in its place.
	function E.restoreSnapshot(only)
		local back, map = 0, {}
		for _, e in entries() do
			local orig, now, where = e:FindFirstChild("Original"), e:FindFirstChild("Now"), e:FindFirstChild("Where")
			if e:GetAttribute("SS_Added") and now and (not only or only[now.Value]) then -- added since: out again
				if now.Value and now.Value.Parent then
					now.Value:Destroy()
				end
				e:Destroy()
				back += 1
			elseif orig and now and e:GetAttribute("SS_Changed") and (not only or only[now.Value]) then
				local was = now.Value
				if was and was.Parent then
					was:Destroy()
				end
				local copy = orig:Clone()
				copy.Name = e.Name
				copy.Parent = (where and where.Value and where.Value:IsDescendantOf(game)) and where.Value or workspace
				now.Value = copy
				index[copy] = e
				e:SetAttribute("SS_Changed", nil)
				back += 1
				if was then
					map[was] = copy
				end
			end
		end
		return back, map
	end

	-- forgets the snapshot (the map stays as it is now)
	function E.clearSnapshot()
		local f = folder(false)
		if f then
			f:Destroy()
		end
		index = {}
	end

	--------------------------------------------------------------------------------
	-- Swapping copies for another model
	--------------------------------------------------------------------------------
	local CollectionService = game:GetService("CollectionService")
	local AXES = { Vector3.xAxis, -Vector3.xAxis, Vector3.yAxis, -Vector3.yAxis, Vector3.zAxis, -Vector3.zAxis }
	-- the model axis nearest to v
	local function snapAxis(v)
		local best, bd = Vector3.yAxis, -math.huge
		for _, a in AXES do
			local d = a:Dot(v)
			if d > bd then
				best, bd = a, d
			end
		end
		return best
	end
	-- the turn that takes axis a onto axis b (both model axes)
	local function turnBetween(a, b)
		local d = a:Dot(b)
		if d > 0.5 then
			return CFrame.identity
		elseif d < -0.5 then
			local side = math.abs(a.X) > 0.5 and Vector3.zAxis or Vector3.xAxis
			return CFrame.fromAxisAngle(side, math.pi)
		end
		return CFrame.fromAxisAngle(a:Cross(b).Unit, math.pi / 2)
	end
	local function boxOf(inst)
		if inst:IsA("BasePart") then
			return inst.CFrame, inst.Size
		end
		return inst:GetBoundingBox()
	end
	-- the middle of a copy's underside, "under" meaning along -up
	local function baseOf(inst, up)
		local cf, size = boxOf(inst)
		local reach = math.abs(cf.RightVector:Dot(up)) * size.X + math.abs(cf.UpVector:Dot(up)) * size.Y + math.abs(cf.LookVector:Dot(up)) * size.Z
		return cf.Position - up * (reach / 2)
	end
	local function extent(inst)
		local _, size = boxOf(inst)
		return math.max(size.X, size.Y, size.Z)
	end
	local function scaleBy(inst, f)
		if math.abs(f - 1) < 1e-4 then
			return
		end
		if inst:IsA("Model") then
			inst:ScaleTo(inst:GetScale() * f)
		else
			inst.Size *= f
		end
	end
	-- which way is up for a kind, in its copies' own axes (most stand the way they were built)
	local function upOfCopies(copies)
		local sum = Vector3.zero
		for _, c in copies do
			if c.inst.Parent then
				sum += c.inst:GetPivot():VectorToObjectSpace(Vector3.yAxis)
			end
		end
		return snapAxis(sum)
	end
	local function median(list)
		if #list == 0 then
			return 1
		end
		table.sort(list)
		return list[math.ceil(#list / 2)]
	end

	-- what a whole kind is like, for swapping part of it the same way as the rest: its usual scale, its size at
	-- that scale, and which way is up in its copies' axes
	function E.kindRef(copies)
		local scales, sizes = {}, {}
		for _, c in copies do
			if c.inst.Parent then
				table.insert(scales, c.scale or 1)
				table.insert(sizes, extent(c.inst) / (c.scale or 1))
			end
		end
		return { scale = median(scales), size = median(sizes), up = upOfCopies(copies) }
	end

	-- Swaps copies for other models, each copy for one of `with` = { { inst, w } } (picked by weight).
	-- Each new copy stands where the old one stood, turned the same way (its up matched to the old one's up), at
	-- the old one's scale against the rest of its kind, with its underside where the old one's was.
	-- opts: ref (E.kindRef of the whole kind; default: of these copies), size (× on top), match (make the new
	-- model as big as the old ones), turn (extra degrees about its up), scripts / tags / attributes (carry them
	-- over from the old copy), seed, pause (called now and then). Every old copy is kept in the snapshot first.
	-- Returns { { old, new } }.
	function E.swapCopies(copies, with, opts)
		opts = opts or {}
		local ref = opts.ref or E.kindRef(copies)
		local total = 0
		for _, w in with do
			total += math.max(w.w or 1, 0)
		end
		if total <= 0 then
			return {}
		end
		local list = {}
		for _, c in copies do
			if c.inst.Parent then
				table.insert(list, c.inst)
			end
		end
		E.snapshot(list)
		local rng = Random.new(tonumber(opts.seed) or 1)
		local out = {}
		for n, c in copies do
			local old = c.inst
			if old.Parent then
				local r, pick = rng:NextNumber() * total, with[#with]
				for _, w in with do
					r -= math.max(w.w or 1, 0)
					if r <= 0 then
						pick = w
						break
					end
				end
				local new = E.copyOf(pick.inst)
				if new then
					local tUp = snapAxis(pick.inst:GetPivot():VectorToObjectSpace(Vector3.yAxis))
					-- the kind's usual copy keeps the new model's size (or, matching, the old one's), others scale with it
					local f = opts.match and (c.scale or 1) * ref.size / math.max(extent(pick.inst), 1e-3) or (c.scale or 1) / ref.scale
					f *= opts.size or 1
					scaleBy(new, f)
					local pivot = old:GetPivot()
					local turn = CFrame.fromAxisAngle(tUp, math.rad(opts.turn or 0))
					new:PivotTo(CFrame.new(pivot.Position) * pivot.Rotation * turnBetween(tUp, ref.up) * turn)
					local up = pivot:VectorToWorldSpace(ref.up)
					new:PivotTo(new:GetPivot() + (baseOf(old, up) - baseOf(new, up)))
					if opts.scripts then
						for _, d in old:GetDescendants() do
							if d:IsA("LuaSourceContainer") then
								d:Clone().Parent = new
							end
						end
					end
					if opts.tags then
						for _, t in CollectionService:GetTags(old) do
							CollectionService:AddTag(new, t)
						end
					end
					if opts.attributes then
						for k, v in old:GetAttributes() do
							if new:GetAttribute(k) == nil then
								new:SetAttribute(k, v)
							end
						end
					end
					new.Parent = old.Parent
					E.snapshotChanged(old, new)
					old:Destroy()
					table.insert(out, { old = old, new = new })
				end
			end
			if opts.pause and n % 200 == 0 then
				opts.pause()
			end
		end
		return out
	end
end
