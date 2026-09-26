--[[
	Smart Scatter — Tour: a short guided tour shown once to each new user (and on demand from Settings).
	Dims the panel except the part being explained, with a card next to it. Seen-state is a plugin setting, so every
	person who installs the plugin gets it once on their own machine.
	Part of Main; loaded in order by the bundle. Shared state and cross-module functions live on App.
]]

return function(App)
	local plugin, P, G, RunService = App.plugin, App.P, App.G, App.RunService
	local SANS, SANS_M, SANS_B = App.SANS, App.SANS_M, App.SANS_B
	local new, corner, stroke, pad, vlist, hlist, box, col, label, para =
		App.new, App.corner, App.stroke, App.pad, App.vlist, App.hlist, App.box, App.col, App.label, App.para

	local TOUR_KEY = "SmartScatter_tour"
	local TOUR_V = 1 -- raise when the tour changes enough that everyone should see it again

	local function ui(name)
		local o = App.ui[name]
		return o and o.Parent and o or nil
	end
	local function inArea()
		return App.area ~= nil
	end

	-- each step: a title, text, and the part of the panel it points at (nil: a card in the middle)
	local STEPS = {
		{
			title = "Welcome to Smart Scatter",
			text = "It fills your map by rules: forests, flower fields, rocks, fences, street lamps and roads that keep off buildings, roads and water by themselves.\n\nThis tour takes about a minute.",
		},
		{
			title = "Your areas and paths",
			text = "Everything you make lives in an area. Click here to switch between them, rename one, lock it, bake it into plain models or delete it.",
			target = function()
				return ui("areaPick")
			end,
		},
		{
			title = "Make something new",
			text = "Scatter area: paint a patch of ground and fill it.\nPath: draw a curve for fences, lamps, tiled paths or roads.",
			target = function()
				return ui("plusBtn")
			end,
		},
		{
			title = "Step 1 · Shape",
			text = function()
				if not inArea() then
					return "Start here. Pick Scatter area or Path, and your first one is ready to shape."
				end
				return App.kindOf(App.area) == "Path"
						and "Press Draw path, then click in the viewport to place points. Drag a point to move it; Shift changes its height, C makes a sharp corner, right-click deletes it."
					or "Pick a tool and paint the ground in the viewport. Shift erases, [ and ] change the brush size, Esc stops. Fill paints a whole field in one click."
			end,
			target = function()
				return ui("step1Card") or ui("welcomeChoice")
			end,
		},
		{
			title = "Add objects",
			text = "Once the ground is marked, open this. Select models in the Explorer (keep the originals outside the area, e.g. in ServerStorage) and press Add selected models.\n\nClick an object for its settings: size, spacing, clumping, what it grows on and what it keeps away from.",
			target = function()
				return ui("step2Card")
			end,
		},
		{
			title = "Placing it all",
			text = "With Live update on, everything is placed as you go and every change rebuilds by itself. Turn it off to get a Generate button instead.\n\nShuffle gives a new random layout, Clear removes what was placed. Ctrl+Z undoes any of it.",
			target = function()
				return ui("foot")
			end,
		},
		{
			title = "Settings",
			text = "Overall density, the coloured overlay in the viewport, and game-ready output: no collision on plants, fewer shadows, streaming for big maps.",
			target = function()
				return ui("gearBtn")
			end,
		},
		{
			title = "That's it",
			text = "Not sure what something does? Hover over it for a tip. Right-click a slider to reset it.\n\nYou can replay this tour any time from Settings.",
		},
	}

	local layer -- the tour's overlay frame (rebuilt with the panel)

	local function finish()
		App.tour = nil
		pcall(function()
			plugin:SetSetting(TOUR_KEY, TOUR_V)
		end)
		if layer then
			layer:Destroy()
			layer = nil
		end
	end

	-- keep the highlighted part in view when it sits in the scrolling page
	local function scrollTo(target)
		local sc = App.scroll
		if not (sc and target:IsDescendantOf(sc)) then
			return
		end
		local top = target.AbsolutePosition.Y - sc.AbsolutePosition.Y + sc.CanvasPosition.Y
		sc.CanvasPosition = Vector2.new(0, math.max(top - 12, 0))
	end

	local render
	local function go(i)
		if not App.tour then
			return
		end
		App.tour.i = math.clamp(i, 1, #STEPS)
		render()
	end

	render = function()
		if layer then
			layer:Destroy()
			layer = nil
		end
		local root = App.root
		App.hideTip()
		if not App.tour or not root then
			return
		end
		local i = App.tour.i
		local step = STEPS[i]
		local target = step.target and step.target()
		if target then
			scrollTo(target)
		end
		if App.tour.root ~= root then -- follow the panel being resized
			App.tour.root = root
			root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
				if App.tour and App.root == root then
					App.renderTour()
				end
			end)
		end
		layer = box({ Size = UDim2.fromScale(1, 1), ZIndex = 300, Parent = root })
		local my = layer
		RunService.Heartbeat:Wait() -- let the scroll and layout settle before measuring
		if layer ~= my or not root.Parent then
			return
		end
		local rw, rh = root.AbsoluteSize.X, root.AbsoluteSize.Y
		local ox, oy = root.AbsolutePosition.X, root.AbsolutePosition.Y

		-- the dimmed panel, with a hole over the target
		local function shade(x, y, w, h)
			if w <= 0 or h <= 0 then
				return
			end
			new("TextButton", {
				Text = "",
				AutoButtonColor = false,
				BackgroundColor3 = Color3.new(0, 0, 0),
				BackgroundTransparency = 0.45,
				Position = UDim2.fromOffset(x, y),
				Size = UDim2.fromOffset(w, h),
				ZIndex = 301,
				Parent = layer,
			})
		end
		local hx, hy, hw, hh
		if target then
			local m = 4
			hx = math.clamp(target.AbsolutePosition.X - ox - m, 0, rw)
			hy = math.clamp(target.AbsolutePosition.Y - oy - m, 0, rh)
			hw = math.clamp(target.AbsoluteSize.X + m * 2, 0, rw - hx)
			hh = math.clamp(target.AbsoluteSize.Y + m * 2, 0, rh - hy)
			shade(0, 0, rw, hy)
			shade(0, hy + hh, rw, rh - hy - hh)
			shade(0, hy, hx, hh)
			shade(hx + hw, hy, rw - hx - hw, hh)
			local ring = box({
				Position = UDim2.fromOffset(hx, hy),
				Size = UDim2.fromOffset(hw, hh),
				ZIndex = 302,
				Parent = layer,
			}, { corner(10) })
			local st = stroke(P.accent)
			st.Thickness = 2
			st.Parent = ring
		else
			shade(0, 0, rw, rh)
		end

		-- the card
		local w = math.min(rw - 24, 300)
		local card = col({
			BackgroundTransparency = 0,
			BackgroundColor3 = P.card,
			Size = UDim2.fromOffset(w, 0),
			ZIndex = 303,
			Parent = layer,
		}, { corner(12), stroke(P.line), pad(16, 16, 14, 14), vlist(8) })
		local function z(o)
			o.ZIndex = 304
			for _, d in o:GetDescendants() do
				if d:IsA("GuiObject") then
					d.ZIndex = 304
				end
			end
			return o
		end
		-- progress: one dot per step
		local dots = z(box({ Size = UDim2.new(1, 0, 0, 8), Parent = card }, { hlist(5) }))
		for k = 1, #STEPS do
			z(box({
				BackgroundTransparency = 0,
				BackgroundColor3 = k == i and P.accent or P.line,
				Size = UDim2.fromOffset(k == i and 18 or 8, 6),
				Parent = dots,
			}, { corner(3) }))
		end
		local t = z(label(step.title, 17, P.text, SANS_B, { Parent = card }))
		t.TextWrapped = true
		t.TextTruncate = Enum.TextTruncate.None
		t.AutomaticSize = Enum.AutomaticSize.Y
		t.Size = UDim2.new(1, 0, 0, 0)
		local body = z(para(type(step.text) == "function" and step.text() or step.text, { Parent = card }))
		body.TextSize = 13
		body.TextColor3 = P.dim
		box({ Size = UDim2.new(1, 0, 0, 4), Parent = card })
		local row = z(box({ Size = UDim2.new(1, 0, 0, 32), Parent = card }))
		local function btn(text, primary, onClick)
			local b = new("TextButton", {
				Text = text,
				Font = primary and SANS_B or SANS_M,
				TextSize = 13,
				TextColor3 = primary and P.onAccent or P.text,
				BackgroundColor3 = primary and P.accent or P.raised,
				AutoButtonColor = false,
				Size = UDim2.fromOffset(0, 32),
				AutomaticSize = Enum.AutomaticSize.X,
				ZIndex = 304,
			}, { corner(8), pad(14, 14, 0, 0) })
			local rest = b.BackgroundColor3
			b.MouseEnter:Connect(function()
				b.BackgroundColor3 = rest:Lerp(Color3.new(1, 1, 1), 0.1)
			end)
			b.MouseLeave:Connect(function()
				b.BackgroundColor3 = rest
			end)
			b.MouseButton1Click:Connect(onClick)
			return b
		end
		local last = i == #STEPS
		if not last then
			local skip = new("TextButton", {
				Text = "Skip tour",
				Font = SANS,
				TextSize = 13,
				TextColor3 = P.faint,
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(70, 32),
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 304,
				Parent = row,
			})
			skip.MouseEnter:Connect(function()
				skip.TextColor3 = P.text
			end)
			skip.MouseLeave:Connect(function()
				skip.TextColor3 = P.faint
			end)
			skip.MouseButton1Click:Connect(finish)
		end
		local right = box({
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			ZIndex = 304,
			Parent = row,
		}, { hlist(6) })
		if i > 1 then
			btn("Back", false, function()
				go(i - 1)
			end).Parent = right
		end
		btn(last and "Got it" or (i == 1 and "Show me" or "Next"), true, function()
			if last then
				finish()
			else
				go(i + 1)
			end
		end).Parent =
			right

		-- place the card under the highlighted part, or above it if there's no room, or in the middle
		local x = math.floor((rw - w) / 2)
		card.Position = UDim2.fromOffset(x, 0)
		RunService.Heartbeat:Wait()
		if layer ~= my then
			return
		end
		local ch = card.AbsoluteSize.Y
		local y
		if not target then
			y = (rh - ch) / 2
		elseif hy + hh + 10 + ch <= rh - 8 then
			y = hy + hh + 10
		elseif hy - 10 - ch >= 8 then
			y = hy - 10 - ch
		else
			y = rh - ch - 12
		end
		card.Position = UDim2.fromOffset(x, math.floor(math.max(y, 8)))
	end
	App.renderTour = function()
		task.spawn(render)
	end

	App.startTour = function()
		if App.mode ~= "Off" then
			App.setMode("Off")
		end
		App.tour = { i = 1 }
		if G.page ~= "Main" then
			App.goPage("Main") -- rebuilds the panel, which shows the tour
		else
			App.renderTour()
		end
	end

	-- first time this person opens the panel: show the tour once
	App.maybeStartTour = function()
		local ok, seen = pcall(function()
			return plugin:GetSetting(TOUR_KEY)
		end)
		if ok and type(seen) == "number" and seen >= TOUR_V then
			return
		end
		if not App.widget.Enabled then
			return
		end
		task.delay(0.5, function()
			if App.root and not App.tour then
				App.startTour()
			end
		end)
	end
end
