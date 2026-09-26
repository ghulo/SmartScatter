--[[
	Smart Scatter — Engine/Areas: saving and loading (attributes on the area folder), the painted mask, removed copies, outputs.
	Adds to E (the engine API); shares internals with the other engine modules through I.
]]

return function(E, I)
	local CollectionService = game:GetService("CollectionService")
	local HttpService = game:GetService("HttpService")
	local decodePaint = I.decodePaint
	local encodePaint = I.encodePaint

	--------------------------------------------------------------------------------
	-- Persistence (stored as attributes on the area folder)
	--------------------------------------------------------------------------------
	-- A model's path from the DataModel: its name at each level. When several siblings share a name, the name carries
	-- which one it is (NAME .. "\31" .. n), so three models all called "Tree" stay three different models. Paths saved
	-- before this read the same.
	local SEP = "\31"
	local function nameAt(inst)
		local parent = inst.Parent
		if not parent then
			return inst.Name
		end
		local n, k = 0, 0
		for _, c in parent:GetChildren() do
			if c.Name == inst.Name then
				n += 1
				if c == inst then
					k = n
				end
			end
		end
		return n > 1 and (inst.Name .. SEP .. k) or inst.Name
	end
	local function pathOf(inst)
		local p, cur = {}, inst
		while cur and cur ~= game do
			table.insert(p, 1, nameAt(cur))
			cur = cur.Parent
		end
		return p
	end
	local function childAt(parent, entry)
		local name, k = string.match(entry, "^(.*)" .. SEP .. "(%d+)$")
		if not name then
			return parent:FindFirstChild(entry)
		end
		k = tonumber(k)
		for _, c in parent:GetChildren() do
			if c.Name == name then
				k -= 1
				if k == 0 then
					return c
				end
			end
		end
		return nil
	end
	local function resolve(path)
		local cur = game
		for _, n in path do
			if type(n) ~= "string" then
				return nil
			end
			cur = cur and childAt(cur, n)
		end
		return cur
	end
	-- a layer's identity (its model's full name; same-named siblings told apart as in pathOf)
	function E.layerKey(l)
		return table.concat(pathOf(l.inst), ".")
	end

	-- the name part of a saved path entry
	local function plainName(entry)
		return type(entry) == "string" and (string.match(entry, "^(.*)" .. SEP .. "%d+$") or entry) or nil
	end

	-- A layer's model by its saved path; if it moved or its folder was renamed, the one model in the place with the same
	-- name (outside our output) is taken instead, so moving a template folder doesn't break every layer that uses it.
	-- `index` (shared across one load) holds every candidate by name, so the place is walked at most once per load.
	local function findModel(path, index)
		local hit = resolve(path)
		if hit then
			return hit, false
		end
		local name = plainName(path[#path])
		if not name then
			return nil
		end
		if not index.built then
			index.built = true
			local out = workspace:FindFirstChild(E.OUT)
			for _, root in { game:GetService("ServerStorage"), game:GetService("ReplicatedStorage"), workspace } do
				for _, c in root:GetDescendants() do
					-- not one of our copies, and not a part inside some bigger model
					if
						(c:IsA("Model") or c:IsA("BasePart"))
						and not (out and c:IsDescendantOf(out))
						and not (c:IsA("BasePart") and c:FindFirstAncestorWhichIsA("Model"))
					then
						local seen = index[c.Name]
						index[c.Name] = seen == nil and c or false -- false: two candidates, don't guess
					end
				end
			end
		end
		local found = index[name]
		return found or nil, found ~= nil and found ~= false
	end

	local function encodeMask(rows)
		local out = {}
		for cz, row in rows do
			local xs = {}
			for cx in row do
				table.insert(xs, cx)
			end
			if #xs > 0 then
				table.sort(xs)
				local segs, s, p = {}, xs[1], xs[1]
				for i = 2, #xs do
					if xs[i] == p + 1 then
						p = xs[i]
					else
						table.insert(segs, s .. "~" .. p)
						s, p = xs[i], xs[i]
					end
				end
				table.insert(segs, s .. "~" .. p)
				table.insert(out, cz .. ":" .. table.concat(segs, ","))
			end
		end
		return table.concat(out, "|")
	end

	function E.getOut()
		local out = workspace:FindFirstChild(E.OUT)
		if not out then
			out = Instance.new("Folder")
			out.Name = E.OUT
			out.Parent = workspace
		end
		return out
	end

	function E.listAreas()
		local t = {}
		local out = workspace:FindFirstChild(E.OUT)
		if out then
			for _, c in out:GetChildren() do
				if c:IsA("Folder") and c:GetAttribute("SS_Area") then
					table.insert(t, c)
				end
			end
		end
		table.sort(t, function(a, b)
			return a.Name < b.Name
		end)
		return t
	end

	function E.setCell(a, cx, cz, on)
		local row = a.rows[cz]
		if on then
			if not row then
				row = {}
				a.rows[cz] = row
			end
			if not row[cx] then
				row[cx] = true
				a.count += 1
				return true
			end
		elseif row and row[cx] then
			row[cx] = nil
			a.count -= 1
			if next(row) == nil then
				a.rows[cz] = nil
			end
			return true
		end
		return false
	end
	function E.hasCell(a, cx, cz)
		local r = a.rows[cz]
		return r ~= nil and r[cx] == true
	end

	-- layers as JSON (models by path, settings, variants, posts, per-layer paint); shared by areas and presets.
	-- lost: layers whose model couldn't be found, kept as they were saved so nothing is thrown away
	function E.layersToJSON(layers, withPaint, lost)
		local data = {}
		for _, l in layers do
			local v = {}
			for _, x in l.variants do
				table.insert(v, { p = pathOf(x.inst), w = x.w, z = x.size })
			end
			for _, x in l.missing or {} do
				table.insert(v, x)
			end -- models not found this time: kept for when they're back
			table.insert(data, {
				p = pathOf(l.inst),
				t = l.type,
				s = l.s,
				v = v,
				pm = withPaint ~= false and encodePaint(l.paint) or nil,
				post = l.post and pathOf(l.post.inst) or l.missingPost,
			})
		end
		for _, d in lost or {} do
			table.insert(data, d)
		end
		return HttpService:JSONEncode(data)
	end
	-- returns the layers, the saved entries whose model can't be found (lost), and how many were found again elsewhere
	function E.layersFromJSON(json)
		local layers, lost, relinked = {}, {}, 0
		local index = {} -- models by name, built on the first path that doesn't resolve
		local ok, data = pcall(HttpService.JSONDecode, HttpService, json or "[]")
		if ok and type(data) == "table" then
			for _, d in data do
				if type(d) ~= "table" then
					continue
				end
				local vlist, missing = {}, {}
				for _, v in (type(d.v) == "table" and d.v or { { p = d.p, w = 1, z = 1 } }) do
					local inst, moved = nil, false
					if type(v) == "table" and type(v.p) == "table" then
						inst, moved = findModel(v.p, index)
					end
					if inst then
						table.insert(vlist, { inst = inst, w = v.w, size = v.z })
						if moved then
							relinked += 1
						end
					elseif type(v) == "table" then
						table.insert(missing, v)
					end
				end
				local l = vlist[1] and E.makeLayer(vlist[1].inst, d.t, d.s, vlist)
				if l then
					l.paint = decodePaint(d.pm)
					l.missing = #missing > 0 and missing or nil
					local post = type(d.post) == "table" and findModel(d.post, index)
					if post then
						E.setPost(l, post)
					elseif type(d.post) == "table" then
						l.missingPost = d.post
					end
					table.insert(layers, l)
				elseif type(d.p) == "table" then
					table.insert(lost, d)
				end
			end
		end
		return layers, lost, relinked
	end
	-- a lost layer, pointed at a model the user picked: it comes back with all its settings
	function E.relinkLost(a, i, inst)
		local d = a.lost and a.lost[i]
		if not d or not inst then
			return false
		end
		-- work on a copy: if the picked model can't be used, the saved entry stays exactly as it was
		local copy = HttpService:JSONDecode(HttpService:JSONEncode(d))
		local p = pathOf(inst)
		copy.p = p
		-- the picked model takes the first model's place; any other missing ones stay listed until they turn up
		local vs = type(copy.v) == "table" and copy.v or {}
		vs[1] = type(vs[1]) == "table" and vs[1] or { w = 1, z = 1 }
		vs[1].p = p
		copy.v = vs
		local layers = E.layersFromJSON(HttpService:JSONEncode({ copy }))
		if not layers[1] or layers[1].inst ~= inst then
			return false
		end
		table.remove(a.lost, i)
		table.insert(a.layers, layers[1])
		return true
	end

	-- presets: named layer stacks kept with the place (ServerStorage), reusable in any area
	local PRESETS = "SmartScatterPresets"
	function E.listPresets()
		local t = {}
		local f = game:GetService("ServerStorage"):FindFirstChild(PRESETS)
		for _, c in f and f:GetChildren() or {} do
			if c:IsA("StringValue") then
				table.insert(t, c)
			end
		end
		table.sort(t, function(a, b)
			return a.Name < b.Name
		end)
		return t
	end
	function E.savePreset(name, layers)
		local ss = game:GetService("ServerStorage")
		local f = ss:FindFirstChild(PRESETS)
		if not f then
			f = Instance.new("Folder")
			f.Name = PRESETS
			f.Parent = ss
		end
		local v = f:FindFirstChild(name)
		if not (v and v:IsA("StringValue")) then
			v = Instance.new("StringValue")
		end
		v.Name = name
		v.Value = E.layersToJSON(layers, false) -- painting belongs to an area, not to a preset
		v.Parent = f
		return v
	end

	-- bake: the area's output becomes plain models (no tags or attributes), and the area lets go of them
	function E.bake(a, name)
		local out = Instance.new("Folder")
		out.Name = name or (a.folder.Name .. " (baked)")
		local n = 0
		for _, layerFolder in a.folder:GetChildren() do
			local dst = Instance.new("Folder")
			dst.Name = layerFolder.Name
			for _, inst in layerFolder:GetDescendants() do
				if CollectionService:HasTag(inst, E.TAG) then
					CollectionService:RemoveTag(inst, E.TAG)
					for k in inst:GetAttributes() do
						if string.sub(k, 1, 3) == "SS_" then
							inst:SetAttribute(k, nil)
						end
					end
					n += 1
				end
			end
			for _, c in layerFolder:GetChildren() do
				c.Parent = dst
			end -- models (or streaming chunks) keep their grouping
			dst.Parent = out
			layerFolder.Parent = nil
		end
		out.Parent = workspace
		return out, n
	end

	function E.loadArea(folder)
		local a = {
			folder = folder,
			rows = {},
			count = 0,
			cell = folder:GetAttribute("SS_Cell") or E.MASK_CELL,
			topY = folder:GetAttribute("SS_TopY") or 0,
			seed = folder:GetAttribute("SS_Seed") or 1,
			edge = folder:GetAttribute("SS_Edge") or 12,
			size = folder:GetAttribute("SS_Size") or 1, -- "Size of everything": multiplies every object's size range
			patches = folder:GetAttribute("SS_Patches") or 0, -- groves and clearings shared by all objects (0 = off)
			patchSize = folder:GetAttribute("SS_PatchSize") or 60,
			pattern = folder:GetAttribute("SS_Pattern") or "Groves", -- which noise the patches follow (E.PATTERNS)
			windDir = folder:GetAttribute("SS_Wind") or 0, -- the way leaning objects lean (degrees, 0 = +Z)
			layers = {},
		}
		for cz, rest in string.gmatch(folder:GetAttribute("SS_Mask") or "", "(-?%d+):([^|]*)") do
			for s, e in string.gmatch(rest, "(-?%d+)~(-?%d+)") do
				for cx = tonumber(s), tonumber(e) do
					E.setCell(a, cx, tonumber(cz), true)
				end
			end
		end
		a.layers, a.lost, a.relinked = E.layersFromJSON(folder:GetAttribute("SS_Layers"))
		a.locked = folder:GetAttribute("SS_Locked") == true
		-- copies the user removed one by one: { [object's number] = { {x, z}, … } }; rebuilds leave those spots empty
		a.removed = {}
		local okR, rem = pcall(HttpService.JSONDecode, HttpService, folder:GetAttribute("SS_Removed") or "[]")
		for _, e in (okR and type(rem) == "table") and rem or {} do
			if type(e) == "table" and tonumber(e[1]) and tonumber(e[2]) and tonumber(e[3]) then
				a.removed[e[1]] = a.removed[e[1]] or {}
				table.insert(a.removed[e[1]], { e[2], e[3] })
			end
		end
		-- parts the area was filled from ("Fill selected parts"): scans take their tops as ground, whatever they're made of
		a.on = {}
		local okO, on = pcall(HttpService.JSONDecode, HttpService, folder:GetAttribute("SS_On") or "[]")
		for _, p in (okO and type(on) == "table") and on or {} do
			local inst = type(p) == "table" and resolve(p)
			if inst and inst:IsA("BasePart") then
				table.insert(a.on, inst)
			end
		end
		local okS, sd = pcall(HttpService.JSONDecode, HttpService, folder:GetAttribute("SS_Spline") or "null")
		if okS and type(sd) == "table" and type(sd.pts) == "table" then
			local function readPts(list)
				local pts = {}
				for _, q in list do
					if type(q) == "table" and #q >= 6 then
						local n = Vector3.new(q[4], q[5], q[6])
						local pt = {
							p = Vector3.new(q[1], q[2], q[3]),
							n = n.Magnitude > 1e-4 and n.Unit or Vector3.yAxis,
							sharp = (q[7] or 0) % 2 == 1 or nil,
							raised = (q[7] or 0) >= 2 or nil,
						}
						if tonumber(q[8]) and q[8] ~= 1 then
							pt.w = q[8]
						end
						if tonumber(q[9]) and q[9] ~= 1 then
							pt.s = q[9]
						end
						if #q >= 12 then
							pt.h = Vector3.new(q[10], q[11], q[12])
						end
						table.insert(pts, pt)
					end
				end
				return pts
			end
			local sp = {
				pts = readPts(sd.pts),
				closed = sd.closed == true,
				width = tonumber(sd.width) or 0,
				snap = sd.snap ~= false,
				walls = sd.walls == true,
				branches = {},
			}
			if type(sd.surface) == "table" then
				sp.surface = {
					on = sd.surface.on == true,
					style = tostring(sd.surface.style or "Asphalt"),
					thick = tonumber(sd.surface.thick) or 1,
					width = tonumber(sd.surface.width),
				}
			end
			for _, b in (type(sd.branches) == "table" and sd.branches or {}) do
				local pts = type(b) == "table" and readPts(b) or {}
				if #pts >= 2 then
					table.insert(sp.branches, { pts = pts, closed = false })
				end
			end
			a.spline = sp
		end
		-- upgrade coarse areas to the finer grid (smoother edges); per-layer paint follows
		if a.cell > E.MASK_CELL and a.cell % E.MASK_CELL == 0 then
			local k = a.cell // E.MASK_CELL
			local old = a.rows
			a.rows, a.count = {}, 0
			for cz, row in old do
				for cx in row do
					for i = 0, k - 1 do
						for j = 0, k - 1 do
							E.setCell(a, cx * k + i, cz * k + j, true)
						end
					end
				end
			end
			for _, l in a.layers do
				if l.paint then
					local np = {}
					for cz, r in l.paint do
						for cx, v in r do
							for j = 0, k - 1 do
								local row = np[cz * k + j] or {}
								np[cz * k + j] = row
								for i = 0, k - 1 do
									row[cx * k + i] = v
								end
							end
						end
					end
					l.paint = np
				end
			end
			a.cell = E.MASK_CELL
		end
		return a
	end

	--------------------------------------------------------------------------------
	-- Mask editing: shapes and cleanup (each returns the list of changed cells { {cx, cz}, ... })
	--------------------------------------------------------------------------------
	-- fill a polygon (list of {x, z}) using scanlines; allow(cx, cz) may veto cells
	function E.fillPolygon(a, poly, on, allow)
		local changed, c, n = {}, a.cell, #poly
		if n < 3 then
			return changed
		end
		local minZ, maxZ = math.huge, -math.huge
		for _, p in poly do
			minZ = math.min(minZ, p[2])
			maxZ = math.max(maxZ, p[2])
		end
		for cz = math.floor(minZ / c), math.floor(maxZ / c) do
			local z = (cz + 0.5) * c
			local xs = {}
			for i = 1, n do
				local p, q = poly[i], poly[i % n + 1]
				if (p[2] <= z and q[2] > z) or (q[2] <= z and p[2] > z) then
					table.insert(xs, p[1] + (z - p[2]) / (q[2] - p[2]) * (q[1] - p[1]))
				end
			end
			table.sort(xs)
			for k = 1, #xs - 1, 2 do
				for cx = math.ceil(xs[k] / c - 0.5), math.floor(xs[k + 1] / c - 0.5) do
					if E.hasCell(a, cx, cz) ~= on and (not allow or allow(cx, cz)) then
						E.setCell(a, cx, cz, on)
						table.insert(changed, { cx, cz })
					end
				end
			end
		end
		return changed
	end

	local N8 = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }
	-- op: "grow" | "shrink" | "smooth" | "holes"
	function E.maskMorph(a, op)
		local minCX, maxCX, minCZ, maxCZ = math.huge, -math.huge, math.huge, -math.huge
		for cz, row in a.rows do
			minCZ = math.min(minCZ, cz)
			maxCZ = math.max(maxCZ, cz)
			for cx in row do
				minCX = math.min(minCX, cx)
				maxCX = math.max(maxCX, cx)
			end
		end
		if minCX == math.huge then
			return {}
		end
		local has = E.hasCell
		local set, unset = {}, {}
		if op == "holes" then
			-- flood the outside from the bounding box border; any empty cell it can't reach is a hole
			local x0, x1, z0, z1 = minCX - 1, maxCX + 1, minCZ - 1, maxCZ + 1
			local W = x1 - x0 + 1
			local seen, queue, qi = {}, {}, 1
			local function push(cx, cz)
				local k = (cz - z0) * W + (cx - x0)
				if not seen[k] and not has(a, cx, cz) then
					seen[k] = true
					table.insert(queue, cx)
					table.insert(queue, cz)
				end
			end
			for cx = x0, x1 do
				push(cx, z0)
				push(cx, z1)
			end
			for cz = z0, z1 do
				push(x0, cz)
				push(x1, cz)
			end
			while qi < #queue do
				local cx, cz = queue[qi], queue[qi + 1]
				qi += 2
				for d = 1, 4 do
					local nx, nz = cx + N8[d][1], cz + N8[d][2]
					if nx >= x0 and nx <= x1 and nz >= z0 and nz <= z1 then
						push(nx, nz)
					end
				end
			end
			for cz = minCZ, maxCZ do
				for cx = minCX, maxCX do
					if not has(a, cx, cz) and not seen[(cz - z0) * W + (cx - x0)] then
						table.insert(set, { cx, cz })
					end
				end
			end
		else
			for cz = minCZ - 1, maxCZ + 1 do
				for cx = minCX - 1, maxCX + 1 do
					local on = has(a, cx, cz)
					local nOn = 0
					for d = 1, 8 do
						if has(a, cx + N8[d][1], cz + N8[d][2]) then
							nOn += 1
						end
					end
					if op == "grow" then
						if not on and nOn > 0 then
							table.insert(set, { cx, cz })
						end
					elseif op == "shrink" then
						if on and nOn < 8 then
							table.insert(unset, { cx, cz })
						end
					elseif op == "smooth" then -- by neighbours in the 3x3 block (3 or fewer: off, 6 or more: on): rounds corners, fills notches, drops specks
						local total = nOn + (on and 1 or 0)
						if on and total <= 3 then
							table.insert(unset, { cx, cz })
						elseif not on and total >= 6 then
							table.insert(set, { cx, cz })
						end
					end
				end
			end
		end
		for _, c in set do
			E.setCell(a, c[1], c[2], true)
		end
		for _, c in unset do
			E.setCell(a, c[1], c[2], false)
		end
		table.move(unset, 1, #unset, #set + 1, set)
		return set
	end

	-- the area's folder can be deleted out from under the panel (e.g. clearing Workspace): put it back
	function E.ensureFolder(a)
		local f = a.folder
		if f and f:IsDescendantOf(workspace) then
			return
		end
		local ok = f ~= nil and pcall(function()
			f.Parent = E.getOut()
		end)
		if not ok then
			local n = Instance.new("Folder")
			n.Name = f and f.Name or "Area"
			n.Parent = E.getOut()
			a.folder = n
		end
	end

	function E.saveArea(a)
		E.ensureFolder(a)
		local f = a.folder
		f:SetAttribute("SS_Area", true)
		f:SetAttribute("SS_Cell", a.cell)
		f:SetAttribute("SS_TopY", a.topY)
		f:SetAttribute("SS_Seed", a.seed)
		f:SetAttribute("SS_Edge", a.edge or 12)
		f:SetAttribute("SS_Size", (a.size and a.size ~= 1) and a.size or nil)
		f:SetAttribute("SS_Patches", (a.patches or 0) > 0 and a.patches or nil)
		f:SetAttribute("SS_PatchSize", (a.patchSize and a.patchSize ~= 60) and a.patchSize or nil)
		f:SetAttribute("SS_Pattern", (a.pattern and a.pattern ~= "Groves") and a.pattern or nil)
		f:SetAttribute("SS_Wind", (a.windDir or 0) ~= 0 and a.windDir or nil)
		f:SetAttribute("SS_Mask", encodeMask(a.rows))
		local sp = a.spline
		if sp and #sp.pts > 0 then
			local function pack(list)
				local pts = {}
				for _, q in list do
					table.insert(pts, {
						math.floor(q.p.X * 100 + 0.5) / 100,
						math.floor(q.p.Y * 100 + 0.5) / 100,
						math.floor(q.p.Z * 100 + 0.5) / 100,
						math.floor(q.n.X * 1000 + 0.5) / 1000,
						math.floor(q.n.Y * 1000 + 0.5) / 1000,
						math.floor(q.n.Z * 1000 + 0.5) / 1000,
						(q.sharp and 1 or 0) + (q.raised and 2 or 0), -- flags: 1 sharp, 2 raised
						math.floor((q.w or 1) * 100 + 0.5) / 100,
						math.floor((q.s or 1) * 100 + 0.5) / 100,
					})
					if q.h then
						local e = pts[#pts]
						table.insert(e, math.floor(q.h.X * 100 + 0.5) / 100)
						table.insert(e, math.floor(q.h.Y * 100 + 0.5) / 100)
						table.insert(e, math.floor(q.h.Z * 100 + 0.5) / 100)
					end
				end
				return pts
			end
			local br = {}
			for _, b in sp.branches or {} do
				if #b.pts >= 2 then
					table.insert(br, pack(b.pts))
				end
			end
			f:SetAttribute(
				"SS_Spline",
				HttpService:JSONEncode({
					pts = pack(sp.pts),
					closed = sp.closed,
					width = sp.width,
					snap = sp.snap,
					walls = sp.walls,
					branches = #br > 0 and br or nil,
					surface = sp.surface,
				})
			)
		else
			f:SetAttribute("SS_Spline", nil)
		end
		f:SetAttribute("SS_Layers", E.layersToJSON(a.layers, nil, a.lost))
		f:SetAttribute("SS_Locked", a.locked or nil)
		local on = {}
		for _, p in a.on or {} do
			if p.Parent then
				table.insert(on, pathOf(p))
			end
		end
		f:SetAttribute("SS_On", #on > 0 and HttpService:JSONEncode(on) or nil)
		local rem = {}
		for h, list in a.removed or {} do
			for _, p in list do
				table.insert(rem, { h, p[1], p[2] })
			end
		end
		f:SetAttribute("SS_Removed", #rem > 0 and HttpService:JSONEncode(rem) or nil)
	end

	-- Removing single copies: the copy goes, and its spot is remembered so rebuilds leave it empty (a Shuffle moves
	-- everything, so its spots stop matching). inst: a placed copy, or any part inside one. Returns the copy's object
	-- number, or nil when inst isn't one of this area's copies.
	function E.copyAt(a, inst)
		local cur = inst
		while cur and cur ~= a.folder do
			if cur:GetAttribute("SS_Type") and cur:IsDescendantOf(a.folder) then
				return cur
			end
			cur = cur.Parent
		end
		return nil
	end
	function E.removeCopy(a, copy)
		local h = copy:GetAttribute("SS_L")
		if not h then
			return nil
		end
		a.removed = a.removed or {}
		a.removed[h] = a.removed[h] or {}
		table.insert(a.removed[h], { copy:GetAttribute("SS_X") or 0, copy:GetAttribute("SS_Z") or 0 })
		E.dropOutput(copy)
		return h
	end
	function E.removedCount(a)
		local n = 0
		for _, list in a.removed or {} do
			n += #list
		end
		return n
	end
	local function removedAt(a, h, x, z)
		for _, p in (a.removed and a.removed[h]) or {} do
			if math.abs(p[1] - x) < 0.3 and math.abs(p[2] - z) < 0.3 then
				return true
			end
		end
		return false
	end
	E.removedAt = removedAt

	-- Keep-clear zones: areas of kind "Clear". Nothing from any other area is placed on their cells.
	function E.clearZones(except)
		local t = {}
		for _, f in E.listAreas() do
			if f ~= except and f:GetAttribute("SS_Kind") == "Clear" then
				local z = E.loadArea(f)
				if z.count > 0 then
					table.insert(t, z)
				end
			end
		end
		return t
	end
	function E.isCleared(zones, x, z)
		for _, zn in zones or {} do
			if E.hasCell(zn, math.floor(x / zn.cell), math.floor(z / zn.cell)) then
				return true
			end
		end
		return false
	end

	-- Fill the area with the tops of some parts (a floating island, a roof, a platform): every cell whose centre looks
	-- down onto one of them. The parts are remembered, so scans treat them as ground. Returns the changed cells.
	function E.fillFromParts(a, parts)
		local changed, c = {}, a.cell
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Include
		rp.FilterDescendantsInstances = parts
		for _, p in parts do
			if not table.find(a.on, p) then
				table.insert(a.on, p)
			end
			local cf, h = p.CFrame, p.Size / 2
			local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
			for sx = -1, 1, 2 do
				for sy = -1, 1, 2 do
					for sz = -1, 1, 2 do
						local w = cf:PointToWorldSpace(Vector3.new(h.X * sx, h.Y * sy, h.Z * sz))
						lo, hi = lo:Min(w), hi:Max(w)
					end
				end
			end
			if (hi.X - lo.X) * (hi.Z - lo.Z) / (c * c) > 250000 then
				continue
			end -- a baseplate: paint that by hand
			for cz = math.floor(lo.Z / c), math.floor(hi.Z / c) do
				for cx = math.floor(lo.X / c), math.floor(hi.X / c) do
					local o = Vector3.new((cx + 0.5) * c, hi.Y + 1, (cz + 0.5) * c)
					if workspace:Raycast(o, Vector3.new(0, lo.Y - hi.Y - 2, 0), rp) and E.setCell(a, cx, cz, true) then
						table.insert(changed, { cx, cz })
					end
				end
			end
			a.topY = math.max(a.topY or 0, hi.Y)
		end
		return changed
	end

	function E.createArea(name, layersFrom)
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = E.getOut()
		local a = {
			folder = f,
			rows = {},
			count = 0,
			cell = E.MASK_CELL,
			topY = 0,
			seed = math.random(1, 999999),
			edge = 12,
			layers = {},
			on = {},
			removed = {},
		}
		for _, l in layersFrom or {} do
			local c = E.makeLayer(l.inst, l.type, l.s, E.variantList(l))
			if c then
				if l.post then
					E.setPost(c, l.post.inst)
				end
				table.insert(a.layers, c)
			end
		end
		E.saveArea(a)
		return a
	end

	-- the road surface folder built for area `a` (linked by an ObjectValue, so renaming the area keeps it)
	function E.roadOf(a)
		local roads = workspace:FindFirstChild(E.ROADS)
		for _, f in roads and roads:GetChildren() or {} do
			local link = f:FindFirstChild("Area")
			if link and link:IsA("ObjectValue") and link.Value == a.folder then
				return f
			end
		end
		return nil
	end
	function E.clearOutputs(a)
		for _, c in a.folder:GetChildren() do
			E.dropOutput(c)
		end -- not kept for undo: undo rebuilds from the area
		local surface = E.roadOf(a)
		if surface then
			E.dropOutput(surface)
		end
	end
end
