--[[
	Smart Scatter — Grid: a floor grid round the brush while painting, like Blender's viewport grid, but lying on the
	ground (hills and all) and drawn on the area's own cells, so it shows exactly what a stroke fills. It fades out
	toward its edge and every 4th line is stronger. Heights come from the overlay's ground probe (cached per cell),
	lines over flat ground are one line, not a line per cell, and it's redrawn only when the brush reaches another
	cell. Settings › Viewport can turn it off.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local G, P, new = App.G, App.P, App.new
	local MAJOR = 4 -- every 4th line is a major one
	local LIFT = 0.07 -- over the ground, so it isn't lost in it

	local last -- the cell and size the grid was last drawn for
	local function pool()
		local gz = App.gz
		gz.grid = gz.grid or { lines = {}, used = 0 }
		return gz.grid
	end
	local function line(a, b, transparency, major)
		local g = pool()
		g.used += 1
		local l = g.lines[g.used]
		if not l then
			l = new("LineHandleAdornment", {
				Adornee = workspace.Terrain,
				AlwaysOnTop = false, -- (hills in front hide it, as ground does)
				ZIndex = 0,
				Parent = App.gizmoFolder(),
			})
			g.lines[g.used] = l
		end
		l.CFrame = CFrame.lookAt(a, b)
		l.Length = (b - a).Magnitude
		l.Thickness = major and 2 or 1
		l.Color3 = major and Color3.new(1, 1, 1):Lerp(P.accent, 0.25) or Color3.fromRGB(225, 225, 225)
		l.Transparency = transparency
		l.Visible = true
	end

	App.clearGrid = function()
		local g = App.gz and App.gz.grid
		if g then
			for _, l in g.lines do
				l.Visible = false
			end
			g.used = 0
		end
		last = nil
	end

	-- draws the grid round world point p (nil: hides it)
	App.drawGrid = function(p)
		if not (App.gz and App.gz.grid) then -- (the viewport's helpers were taken down since: draw afresh)
			last = nil
		end
		local a = App.area
		if not (p and a and G.grid ~= false) then
			App.clearGrid()
			return
		end
		local c = a.cell
		local R = math.clamp(G.radius * 2.2, 32, 96)
		local hx, hz = math.floor(p.X / c), math.floor(p.Z / c)
		local key = hx .. "," .. hz .. "," .. R
		if key == last then
			return
		end
		last = key
		local g = pool()
		for i = 1, g.used do
			g.lines[i].Visible = false
		end
		g.used = 0
		local n = math.ceil(R / c)
		-- the ground's height at a grid corner: its cell's probed height (cached by the overlay)
		local heights = {}
		local function y(ix, iz)
			local k = ix * 100003 + iz
			local v = heights[k]
			if not v then
				v = App.probe(ix, iz, p.Y).y + LIFT
				heights[k] = v
			end
			return v
		end
		local function fade(x, z) -- 0 at the brush, 1 at the grid's edge
			return math.sqrt((x - p.X) ^ 2 + (z - p.Z) ^ 2) / R
		end
		-- one direction at a time: lines of constant z (along x), then of constant x (along z). A run of cells at
		-- about the same height is drawn as one line.
		for pass = 1, 2 do
			for k = -n, n + 1 do
				local fixed = (pass == 1 and hz or hx) + k
				local major = fixed % MAJOR == 0
				local runStart, runY, runT
				local function flush(i)
					if runStart then
						local x0, x1 = runStart * c, i * c
						local fx = fixed * c
						local A = pass == 1 and Vector3.new(x0, runY, fx) or Vector3.new(fx, runY, x0)
						local B = pass == 1 and Vector3.new(x1, runY, fx) or Vector3.new(fx, runY, x1)
						line(A, B, runT, major)
						runStart = nil
					end
				end
				for i = (pass == 1 and hx or hz) - n, (pass == 1 and hx or hz) + n do
					local ix, iz = pass == 1 and i or fixed, pass == 1 and fixed or i
					local mx, mz = (pass == 1 and (i + 0.5) * c or fixed * c), (pass == 1 and fixed * c or (i + 0.5) * c)
					local d = fade(mx, mz)
					if d > 1 then
						flush(i)
					else
						local h = y(ix, iz)
						-- fades out toward the edge; major lines stay a little stronger
						local t = math.clamp((major and 0.35 or 0.6) + (major and 0.65 or 0.4) * d ^ 1.6, 0, 1)
						local tq = math.floor(t * 5 + 0.5) / 5 -- (a run keeps one of five fade steps: few lines, smooth enough)
						if runStart and (math.abs(h - runY) > 0.35 or tq ~= runT) then
							flush(i)
						end
						if not runStart then
							runStart, runY, runT = i, h, tq
						end
					end
				end
				flush((pass == 1 and hx or hz) + n + 1)
			end
		end
	end
end
