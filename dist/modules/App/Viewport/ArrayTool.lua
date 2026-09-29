--[[
	Smart Scatter — ArrayTool: the strip's Array tool. With a model selected in the Explorer (or an array selected: its
	model), press on the ground and drag: a line runs from the press to the mouse, and on letting go an array of the
	model lines up along it, as many as fit at the model's own spacing. A plain click makes a row of six running the
	way the camera looks. The array is then selected, its tab open to tune it (Panel/ArrayTools).
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local rawMouse = App.rawMouse
	local DRAG_PX = 6 -- a press that moves further than this is a drag

	local press -- { at = the ground where it was pressed, px = screen position, src, spacing }
	local line -- the preview line from the press to the mouse

	-- what the tool arrays: the Explorer's selected model, else the selected array's model
	local function source()
		local src = App.arraySource()
		if not src and App.selected and App.selected.kind == "Array" then
			local v = App.selected.folder:FindFirstChild("Source")
			src = v and v.Value
		end
		return src
	end

	local function onGround(y)
		local ray = rawMouse.UnitRay
		if math.abs(ray.Direction.Y) > 1e-3 then
			local t = (y - ray.Origin.Y) / ray.Direction.Y
			if t > 0 then
				return ray.Origin + ray.Direction * t
			end
		end
		return nil
	end
	local function clearLine()
		if line then
			line:Destroy()
			line = nil
		end
	end

	local function move()
		App.gizmoFolder()
		local hit = App.mouseHit()
		if not press then
			if hit then
				App.gz.anchor.CFrame = CFrame.new(hit.Position)
				local src = source()
				App.setLabel(src and ("Array of " .. src.Name .. " · press and drag along where they go") or "Select a model in the Explorer first")
			end
			return
		end
		local to = onGround(press.at.Y)
		if not to then
			return
		end
		local d = Vector3.new(to.X - press.at.X, 0, to.Z - press.at.Z)
		if not line then
			line = App.new("LineHandleAdornment", {
				Adornee = workspace.Terrain,
				AlwaysOnTop = true,
				Thickness = 4,
				ZIndex = 5,
				Color3 = App.VIEW.accent,
				Parent = App.gizmoFolder(),
			})
		end
		line.Visible = d.Magnitude > 0.05
		if d.Magnitude > 0.05 then
			local from = press.at + Vector3.new(0, 0.3, 0)
			line.CFrame, line.Length = CFrame.lookAt(from, from + d), d.Magnitude
		end
		local n = math.max(math.floor(d.Magnitude / press.spacing) + 1, 2)
		App.gz.anchor.CFrame = CFrame.new(to)
		App.setLabel(string.format("%d × %s · let go to make it", n, press.src.Name))
	end

	local function down()
		local src = source()
		local hit = App.mouseHit()
		if not src then
			App.status("Select a model in the Explorer first: the array repeats it.")
			return
		end
		if hit then
			press = { at = hit.Position, px = Vector2.new(rawMouse.X, rawMouse.Y), src = src, spacing = App.arraySpacing(src) }
		end
	end

	local function up()
		local pr = press
		press = nil
		clearLine()
		if not pr then
			return
		end
		local to = onGround(pr.at.Y)
		local dragged = (Vector2.new(rawMouse.X, rawMouse.Y) - pr.px).Magnitude > DRAG_PX and to ~= nil
		local dir, count
		if dragged then
			local d = Vector3.new(to.X - pr.at.X, 0, to.Z - pr.at.Z)
			dir = d.Magnitude > 1e-3 and d.Unit or Vector3.new(0, 0, -1)
			count = math.max(math.floor(d.Magnitude / pr.spacing) + 1, 2)
		else -- a click: six in a row, the way the camera looks
			local look = workspace.CurrentCamera.CFrame.LookVector
			local flat = Vector3.new(look.X, 0, look.Z)
			dir = flat.Magnitude > 1e-3 and flat.Unit or Vector3.new(0, 0, -1)
			count = 6
		end
		App.setMode("Off")
		App.newArray(pr.src, CFrame.lookAt(pr.at, pr.at + dir), { shape = "Line", count = count, spacing = pr.spacing })
		App.status(string.format("Array of %d %s made. Tune it on its Array tab.", count, pr.src.Name))
	end

	-- leaving the tool halfway through a drag drops it
	local function stop()
		press = nil
		clearLine()
	end
	App.registerMode("Array", { move = move, down = down, up = up, stop = stop, noArea = true })
	App.registerTool({
		id = "array",
		group = "Stamp",
		order = 2,
		icon = "grid",
		name = "Array: drag along the ground to line up copies of the selected model",
		on = function()
			return App.mode == "Array"
		end,
		click = function()
			if App.mode == "Array" then
				App.setMode("Off")
			elseif source() then
				App.setMode("Array")
			else
				App.status("Select a model in the Explorer first: the array repeats it.")
			end
		end,
	})
end
