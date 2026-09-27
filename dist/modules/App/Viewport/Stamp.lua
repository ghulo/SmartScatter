--[[
	Smart Scatter — Stamp: puts one copy of an object down exactly where and how you want it. The real model floats
	under the mouse, see-through, standing just as it will (it's posed by the same placement code, on the same ground);
	a click puts it down, a drag from where you pressed turns it to face the mouse (15° steps; Shift turns freely).
	Keys turn it, size it, pick the model or roll a random one; the panel has the same as sliders. Each stamp is a pin
	that keeps its turn, size and model (Engine/Pins), so it comes back exactly so every time the area is generated,
	and no rule moves or refuses it. One undo step each.
	Paint hands the viewport's mouse and keys to it while the mode is "Stamp".
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local Engine, G, beginRec, endRec, rawMouse = App.Engine, App.G, App.beginRec, App.endRec, App.rawMouse
	local STEP = math.rad(15) -- the turn's steps (keys, and dragging without Shift)
	local DRAG_PX = 6 -- a press that moves further than this turns the stamp instead of just placing it

	-- the stamp being aimed: its turn (radians), size (1 = the model's own size in the mix) and model (index)
	local stamp = { yaw = 0, k = 1, vi = 1 }
	App.stamp = stamp
	local ghost -- the see-through model under the mouse: { clone, v, sc, offset (pivot relative to its stand) }
	local press -- a press in progress: { x, z, y, at = screen position, turning }

	local function layer()
		local l = App.mode == "Stamp" and App.paintLayer or nil
		if l and stamp.layer ~= l then -- a new object: its first model, at the size its copies grow on average
			stamp.layer, stamp.vi = l, 1
			stamp.k = (l.s.scaleMin + l.s.scaleMax) / 2 * (App.area and App.area.size or 1)
		end
		return l
	end

	local function clearGhost()
		if ghost then
			ghost.clone:Destroy()
			ghost = nil
		end
	end
	-- the model, see-through and out of the way of clicks, rays and physics (made again when the model or size changes)
	local function ghostFor(v, sc)
		if ghost and ghost.v == v and math.abs(ghost.sc - sc) < 1e-4 and ghost.clone.Parent then
			return ghost
		end
		clearGhost()
		local c = (v.src or v.inst):Clone()
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

	-- the stamp as a pin at (x, z), and where it would stand there (nil: it can't go there, and why)
	local function aim(l, x, z, seed)
		if not App.area or (App.area.count or 0) == 0 then
			return nil, nil, "paint the area first: stamps go on its ground"
		end
		App.readGround(App.area) -- (only when the ground is out of date)
		local an = App.lastAnalysis
		if not an then
			return nil, nil, "the ground couldn't be read"
		end
		stamp.vi = math.clamp(stamp.vi, 1, #l.variants)
		local p = Engine.stampPin(x, z, stamp.yaw, stamp.k, stamp.vi, seed or 1)
		local pose = Engine.stampPose(App.area, an, l, p)
		return p, pose, not pose and "outside the area, or no ground here" or nil
	end

	local function describe(l, extra)
		local v = l.variants[stamp.vi] or l.variants[1]
		return string.format(
			"Stamp · %s · %d° · %.2f×%s",
			v.inst.Name,
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

	-- shows the stamp at (x, z): the model where it will stand, and what it is
	local function show(l, x, z, y)
		local _, pose, why = aim(l, x, z)
		if not pose then
			clearGhost()
			label(Vector3.new(x, y, z), describe(l, "can't go here: " .. why))
			return
		end
		local gh = ghostFor(pose.v, pose.sc)
		if not gh.offset then -- posed once (that scales it); after that only moved
			Engine.poseCopy(gh.clone, l, pose.v, pose.sc, pose.cf, pose.sink)
			gh.offset = pose.cf:Inverse() * gh.clone:GetPivot()
			gh.clone.Parent = App.gizmoFolder()
		else
			gh.clone:PivotTo(pose.cf * gh.offset)
		end
		label(pose.cf.Position, describe(l, press and press.turning and "release to put it down" or "click to put it down, drag to turn"))
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
		local l = layer()
		if not l then
			return
		end
		if press then
			local m = Vector2.new(rawMouse.X, rawMouse.Y)
			press.turning = press.turning or (m - press.at).Magnitude > DRAG_PX
			if press.turning then -- the front (the model's -Z) turns toward the mouse
				local to = onPlane(press.y)
				if to and (Vector3.new(to.X - press.x, 0, to.Z - press.z)).Magnitude > 0.5 then
					local yaw = math.atan2(-(to.X - press.x), -(to.Z - press.z))
					stamp.yaw = App.shiftHeld() and yaw or math.floor(yaw / STEP + 0.5) * STEP
				end
			end
			show(l, press.x, press.z, press.y)
			return
		end
		local hit = App.mouseHit()
		if not hit then
			clearGhost()
			App.setLabel("")
			return
		end
		show(l, hit.Position.X, hit.Position.Z, hit.Position.Y)
	end

	-- a random turn, size (within the object's size range) and model (by its share of the mix)
	local function roll(l)
		local s = l.s
		stamp.yaw = s.yawMode == "Fixed" and math.rad(s.yaw) or s.yawMode == "Snap" and math.random(0, 3) * math.pi / 2 or math.random() * math.pi * 2
		local size = App.area and App.area.size or 1
		stamp.k = (s.scaleMin + (s.scaleMax - s.scaleMin) * math.random()) * size
		local sum = 0
		for _, v in l.variants do
			sum += math.max(v.w, 0)
		end
		local r = math.random() * sum
		for i, v in l.variants do
			r -= math.max(v.w, 0)
			if r <= 0 and v.w > 0 then
				stamp.vi = i
				break
			end
		end
	end

	local function refresh()
		if App.ui.refreshStamp then
			App.ui.refreshStamp()
		end
		App.stampMove()
	end

	-- puts the stamp down at (x, z): the copy now (the real model, Live or not), and its pin so it stays
	local function put(l, x, z)
		local p, pose, why = aim(l, x, z, math.random(1, 2 ^ 30))
		if not pose then
			App.status("Can't stamp there: " .. why .. ".", "error")
			return
		end
		local rec = beginRec("Smart Scatter: Stamp " .. l.inst.Name)
		local made = Engine.placeStamp(
			App.area,
			App.lastAnalysis,
			l,
			p,
			{ walk = G.walk, shadows = G.shadows, query = G.query, chunks = false, ghost = false }
		)
		if not made then
			endRec(rec, true)
			App.status("Can't stamp there: it's a keep-clear zone.", "error")
			return
		end
		l.pins = l.pins or {}
		table.insert(l.pins, p)
		App.saveArea()
		endRec(rec)
		App.lastCounts[l] = (App.lastCounts[l] or 0) + 1
		App.lastTotal = (App.lastTotal or 0) + 1
		App.refreshCounts()
		App.status(describe(l, "put down. Ctrl+Z takes it back."))
		if G.stampRandom then
			roll(l)
			if App.ui.refreshStamp then
				App.ui.refreshStamp()
			end
		end
	end

	App.stampDown = function()
		local hit = App.mouseHit()
		if not (layer() and hit) then
			return
		end
		press = { x = hit.Position.X, z = hit.Position.Z, y = hit.Position.Y, at = Vector2.new(rawMouse.X, rawMouse.Y) }
	end
	App.stampUp = function()
		local l, pr = layer(), press
		press = nil
		if l and pr then
			put(l, pr.x, pr.z)
			if pr.turning and App.ui.refreshStamp then
				App.ui.refreshStamp()
			end
			App.stampMove()
		end
	end

	-- the stamp's keys; true when the key was one of them
	App.stampKey = function(name)
		local l = layer()
		if not l then
			return false
		end
		if name == "turn" then
			stamp.yaw = (math.floor(stamp.yaw / STEP + 0.5) + (App.shiftHeld() and -1 or 1)) * STEP % (math.pi * 2)
		elseif name == "grow" or name == "shrink" then
			stamp.k = math.clamp(stamp.k * (name == "grow" and 1.1 or 1 / 1.1), 0.05, 20)
		elseif name == "model" then
			stamp.vi = stamp.vi % #l.variants + 1
		elseif name == "shuffle" then
			roll(l)
		elseif name == "size" then -- (there's no brush to size)
			return true
		elseif name == "cancel" and press then -- a press being dragged is dropped; the next Esc stops stamping
			press = nil
		elseif name == "cancel" then
			return false
		else
			return false
		end
		refresh()
		return true
	end

	-- the panel's controls change the stamp through these
	App.setStamp = function(yaw, k, vi)
		stamp.yaw = yaw and math.rad(yaw) % (math.pi * 2) or stamp.yaw
		stamp.k = k or stamp.k
		stamp.vi = vi or stamp.vi
		if App.mode == "Stamp" then
			App.stampMove()
		end
	end
	App.rollStamp = function()
		local l = layer() or App.paintLayer
		if l then
			roll(l)
			refresh()
		end
	end

	-- leaving the stamp (another mode, Esc, the plugin closing): the model under the mouse goes
	App.clearStamp = function()
		press = nil
		clearGhost()
	end
end
