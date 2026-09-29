--[[
	Smart Scatter — Stamp: one model, put down exactly where and how you want it, anywhere on the ground. No area,
	painting or object needed: it's its own tool. What it stamps: the models selected in the Explorer when it starts (a
	folder counts as the models in it), or an object's models (its Stamp button), or the last ones again.
	The model floats under the mouse, see-through, standing just as it will; a click puts it down, a drag from where
	you pressed turns it to face the mouse (15° steps; Shift turns freely). Keys turn it, size it, pick the model or
	roll a random one; the Stamp card and the viewport's bar have the same. Stamped copies are plain models in
	Workspace › Stamps: Generate, Erase and the areas never touch them; Ctrl+Z takes one back, Delete removes one.
	Paint hands the viewport's mouse and keys to it while the mode is "Stamp".
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local Engine, G, beginRec, endRec, rawMouse = App.Engine, App.G, App.beginRec, App.endRec, App.rawMouse
	local STEP = math.rad(15) -- the turn's steps (keys, and dragging without Shift)
	local DRAG_PX = 6 -- a press that moves further than this turns the stamp instead of just placing it
	local FOLDER = "Stamps" -- where stamped copies go, in Workspace
	local BARE = { s = {} } -- (placing asks the layer only whether it's a line: a stamp never is)

	-- the stamp being aimed: its models, which one, its turn (radians) and size (1 = the model's own size); from: the
	-- object they came from, if they did
	local stamp = { models = {}, vi = 1, yaw = 0, k = 1, from = nil }
	App.stamp = stamp
	local measured = setmetatable({}, { __mode = "k" }) -- each model measured once: { m = size, bottom, footprint… }
	local function variantOf(inst)
		local v = measured[inst]
		if v == nil then
			v = Engine.makeVariant(inst, 1, 1) or false
			measured[inst] = v
		end
		return v or nil
	end
	local function current()
		local inst = stamp.models[stamp.vi] or stamp.models[1]
		return inst, inst and variantOf(inst)
	end

	--------------------------------------------------------------------------------
	-- what to stamp
	--------------------------------------------------------------------------------
	-- the models in the Explorer's selection (a folder counts as its models); none that the plugin placed itself
	local function selectedModels()
		local out = {}
		local placedByUs = { workspace:FindFirstChild(Engine.OUT), workspace:FindFirstChild(Engine.ROADS) } -- (areas, roads)
		local function ours(inst)
			if inst:GetAttribute("SS_Type") ~= nil then -- a copy an area placed (it carries the area's tags and marks)
				return true
			end
			for _, f in placedByUs do
				if f and inst:IsDescendantOf(f) then
					return true
				end
			end
			return false
		end
		local function take(inst)
			if (inst:IsA("Model") or inst:IsA("BasePart")) and not ours(inst) and variantOf(inst) then
				table.insert(out, inst)
			end
		end
		for _, s in App.Selection:Get() do
			if s:IsA("Folder") then
				for _, c in s:GetChildren() do
					take(c)
				end
			else
				take(s)
			end
		end
		return out
	end

	-- starts stamping: `from` (an object) stamps its models; nil takes the selection, else keeps the last models, else
	-- the object in hand. Returns false (and says why) when there's nothing to stamp.
	App.startStamp = function(from)
		local models
		if from then
			models = {}
			for _, v in from.variants do
				table.insert(models, v.inst)
			end
		else
			models = selectedModels()
			if #models == 0 then
				models = #stamp.models > 0 and stamp.models or nil
				from = stamp.from
			end
			if not models and App.handLayer then
				from = App.handLayer
				models = {}
				for _, v in from.variants do
					table.insert(models, v.inst)
				end
			end
		end
		if not models or #models == 0 then
			App.status("Select a model in the Explorer (or a folder of them), then press Stamp.")
			return false
		end
		if models ~= stamp.models then
			stamp.models, stamp.vi, stamp.from = models, 1, from
			local s = from and from.s
			stamp.k = s and (s.scaleMin + s.scaleMax) / 2 or 1
			stamp.base = stamp.k -- (a random one sizes round these models' size, not the last ones')
		end
		if App.mode ~= "Stamp" then
			App.setMode("Stamp")
		end
		if App.refreshStamp then
			App.refreshStamp()
		end
		local inst = current()
		App.status(
			string.format(
				"Stamping %s%s. Click to put it down, drag to turn it.",
				inst.Name,
				#models > 1 and string.format(" (and %d more)", #models - 1) or ""
			)
		)
		return true
	end

	--------------------------------------------------------------------------------
	-- the model under the mouse
	--------------------------------------------------------------------------------
	local ghost -- { clone, v, sc, offset (pivot relative to its stand) }
	local press -- a press in progress: { pos, up, at = screen position, turning }

	local function clearGhost()
		if ghost then
			ghost.clone:Destroy()
			ghost = nil
		end
	end
	-- the model, see-through and out of the way of clicks, rays and physics (made again when the model or size changes)
	local function ghostFor(inst, v, sc)
		if ghost and ghost.v == v and math.abs(ghost.sc - sc) < 1e-4 and ghost.clone.Parent then
			return ghost
		end
		clearGhost()
		local c = (v.src or inst):Clone()
		c.Archivable = false
		local all = c:GetDescendants()
		table.insert(all, c)
		for _, d in all do
			if d:IsA("BasePart") then
				d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch, d.CastShadow, d.Locked = true, false, false, false, false, true
				d.Transparency = 1 - (1 - d.Transparency) * 0.5
			elseif d:IsA("Decal") then
				d.Transparency = 1 - (1 - d.Transparency) * 0.5
			elseif d:IsA("Script") or d:IsA("LocalScript") then
				d:Destroy()
			end
		end
		ghost = { clone = c, v = v, sc = sc }
		return ghost
	end

	-- where the stamp stands at a point of the ground: turned, sized, upright (or along the surface), and settled on
	-- the lowest ground under its footprint so no side floats
	local function stand(v, pos, up)
		local m, sc = v.m, stamp.k * v.size
		local upV = (G.stampAlign and up and up.Y > 0.2) and up or Vector3.yAxis
		local y = pos.Y
		if upV == Vector3.yAxis then
			local r = math.max(m.radius * sc * 0.6, 0.4)
			for k = 0, 3 do
				local a = k * math.pi / 2 + stamp.yaw
				local h = Engine.cast(
					Vector3.new(pos.X + math.cos(a) * r, pos.Y + r + 4, pos.Z + math.sin(a) * r),
					Vector3.new(0, -(r * 3 + 8), 0),
					App.probeParams
				)
				if h and h.Position.Y < y then
					y = math.max(h.Position.Y, y - r * 1.5)
				end
			end
		end
		local cf = CFrame.new(pos.X, y, pos.Z) * Engine.rotateUp(upV) * CFrame.Angles(0, stamp.yaw, 0)
		return cf, sc
	end

	local function describe(inst, extra)
		return string.format(
			"Stamp · %s · %d° · %.2f×%s",
			inst.Name,
			math.floor(math.deg(stamp.yaw) + 0.5) % 360,
			stamp.k,
			extra and ("  ·  " .. extra) or ""
		)
	end
	local function label(at, text)
		App.gizmoFolder()
		App.gz.anchor.CFrame = CFrame.new(at)
		App.setLabel(text)
	end

	local function show(pos, up)
		local inst, v = current()
		if not v then
			clearGhost()
			return
		end
		local cf, sc = stand(v, pos, up)
		local gh = ghostFor(inst, v, sc)
		if not gh.offset then -- posed once (that scales it); after that only moved
			Engine.poseCopy(gh.clone, BARE, v, sc, cf, 0)
			gh.offset = cf:Inverse() * gh.clone:GetPivot()
			gh.clone.Parent = App.gizmoFolder()
		else
			gh.clone:PivotTo(cf * gh.offset)
		end
		label(cf.Position, describe(inst, press and press.turning and "release to put it down" or "click to put it down, drag to turn"))
	end

	-- where the mouse points on the flat plane at height y (steady while turning, whatever is under the mouse)
	local function onPlane(y)
		local ray = rawMouse.UnitRay
		if math.abs(ray.Direction.Y) > 1e-3 then
			local t = (y - ray.Origin.Y) / ray.Direction.Y
			if t > 0 then
				return ray.Origin + ray.Direction * t
			end
		end
		return nil
	end

	App.stampMove = function()
		if press then
			local m = Vector2.new(rawMouse.X, rawMouse.Y)
			press.turning = press.turning or (m - press.at).Magnitude > DRAG_PX
			if press.turning then -- the front (the model's -Z) turns toward the mouse
				local to = onPlane(press.pos.Y)
				local d = to and Vector3.new(to.X - press.pos.X, 0, to.Z - press.pos.Z)
				if d and d.Magnitude > 0.5 then
					local yaw = math.atan2(-d.X, -d.Z)
					stamp.yaw = App.shiftHeld() and yaw or math.floor(yaw / STEP + 0.5) * STEP
				end
			end
			show(press.pos, press.up)
			return
		end
		local hit = App.mouseHit()
		if not hit then
			clearGhost()
			App.setLabel("")
			return
		end
		show(hit.Position, hit.Normal)
	end

	-- a random turn, size (±20% round the size set) and model
	local function roll()
		stamp.yaw = math.random() * math.pi * 2
		stamp.base = stamp.base or stamp.k
		stamp.k = stamp.base * (0.8 + math.random() * 0.4)
		stamp.vi = math.random(1, math.max(#stamp.models, 1))
	end

	local function refresh()
		if App.refreshStamp then
			App.refreshStamp()
		end
		App.stampMove()
	end

	-- puts it down: a plain copy of the model, in Workspace › Stamps, one undo step
	local function put(pos, up)
		local inst, v = current()
		if not v then
			return
		end
		local cf, sc = stand(v, pos, up)
		local rec = beginRec("Smart Scatter: Stamp " .. inst.Name)
		local folder = workspace:FindFirstChild(FOLDER)
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = FOLDER
			folder.Parent = workspace
		end
		local copy = (v.src or inst):Clone()
		Engine.poseCopy(copy, BARE, v, sc, cf, 0)
		for _, d in copy:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
			end
		end
		if copy:IsA("BasePart") then
			copy.Anchored = true
		end
		copy.Parent = folder
		endRec(rec)
		App.status(describe(inst, "put down in Workspace › Stamps. Ctrl+Z takes it back."))
		if G.stampRandom then
			roll()
			if App.refreshStamp then
				App.refreshStamp()
			end
		end
	end

	App.stampDown = function()
		local hit = App.mouseHit()
		if hit and current() then
			press = { pos = hit.Position, up = hit.Normal, at = Vector2.new(rawMouse.X, rawMouse.Y) }
		end
	end
	App.stampUp = function()
		local pr = press
		press = nil
		if pr then
			put(pr.pos, pr.up)
			if pr.turning and App.refreshStamp then
				App.refreshStamp()
			end
			App.stampMove()
		end
	end

	-- the stamp's keys; true when the key was one of them
	App.stampKey = function(name)
		if name == "turn" then
			stamp.yaw = (math.floor(stamp.yaw / STEP + 0.5) + (App.shiftHeld() and -1 or 1)) * STEP % (math.pi * 2)
		elseif name == "grow" or name == "shrink" then
			stamp.k = math.clamp(stamp.k * (name == "grow" and 1.1 or 1 / 1.1), 0.05, 20)
			stamp.base = stamp.k
		elseif name == "model" then
			stamp.vi = stamp.vi % math.max(#stamp.models, 1) + 1
		elseif name == "shuffle" then
			roll()
		elseif name == "size" then -- (there's no brush to size)
			return true
		elseif name == "cancel" and press then -- a press being dragged is dropped; the next Esc stops stamping
			press = nil
		else
			return false
		end
		refresh()
		return true
	end

	-- the panel's and the bar's controls change the stamp through these
	App.setStamp = function(yaw, k, vi)
		stamp.yaw = yaw and math.rad(yaw) % (math.pi * 2) or stamp.yaw
		if k then
			stamp.k, stamp.base = k, k
		end
		stamp.vi = vi or stamp.vi
		if App.mode == "Stamp" then
			App.stampMove()
		end
	end
	App.rollStamp = function()
		roll()
		refresh()
	end

	-- leaving the stamp (another mode, Esc, the plugin closing): the model under the mouse goes
	App.clearStamp = function()
		press = nil
		clearGhost()
	end
end
