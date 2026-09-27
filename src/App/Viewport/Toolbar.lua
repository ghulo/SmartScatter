--[[
	Smart Scatter — Toolbar: the viewport's own tools, like Blender's. Down the left edge, a strip of small square
	tool buttons in groups (painting the ground; stamping and spraying the object in hand; the path and removing
	copies; the search menu), the one in use lit. Along the top, while a tool is on, a bar with just that tool's
	settings (the brush's size and shape, the stamp's turn, size and model, the path's shapes), so the eyes can stay
	on the viewport. The panel stays the full menu; these only reach what's needed while working.
	Both follow the state they show (looked at ten times a second, rebuilt only when it changes), so no other module
	has to tell them. Settings › Viewport turns them off.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local G, saveG, P, Engine = App.G, App.saveG, App.P, App.Engine
	local new, box, label, corner, stroke, pad = App.new, App.box, App.label, App.corner, App.stroke, App.pad
	local SANS, SANS_B = App.SANS, App.SANS_B
	local BTN, SEE = 30, 0.12 -- a tool button's size; how see-through the strip and bar are
	local TOOL_ICON = { Brush = "brush", Lasso = "lasso", Box = "box", Polygon = "polygon", Fill = "fill" }

	local gui, strip, bar, tip
	local stripKey, barKey -- what each was last built for
	local looks = {} -- the strip's buttons: fn() that colours each for the tool in use

	-- the object the strip's Stamp and Spray work on: the one in hand, else the Brush tab's pick, else the first
	local function handLayer()
		local a = App.area
		if not a then
			return nil
		end
		local function ok(l)
			return l ~= nil and table.find(a.layers, l) ~= nil and not (Engine.isLine(l) and l.s.follow == "Spline")
		end
		if ok(App.paintLayer) then
			return App.paintLayer
		elseif ok(App.handLayer) then
			return App.handLayer
		end
		for _, l in a.layers do
			if ok(l) then
				return l
			end
		end
		return nil
	end

	-- the strip's tools, in groups: { icon, name, key? (a keymap id), on(), click(), danger? }
	local function tools()
		local a = App.area
		local kind = a and App.kindOf(a)
		local groups = {}
		if kind ~= "Path" then
			local g = {}
			for i, t in App.TOOLS do
				table.insert(g, {
					icon = TOOL_ICON[t],
					name = t,
					key = "tool" .. i,
					on = function()
						return App.mode == "Paint" and G.tool == t
					end,
					click = function()
						if App.mode == "Paint" and G.tool == t then
							App.setMode("Off")
						else
							App.setTool(t)
						end
					end,
				})
			end
			table.insert(g, {
				icon = "trash",
				name = "Erase ground",
				key = "erase",
				danger = true,
				on = function()
					return App.mode == "Erase"
				end,
				click = function()
					App.setMode(App.mode == "Erase" and "Off" or "Erase")
				end,
			})
			table.insert(groups, g)
		end
		-- by hand: the stamp (any model, anywhere) and, with an object in hand, spraying it
		local hand = {
			{
				icon = "stamp",
				name = "Stamp (the selected models, or the last ones)",
				on = function()
					return App.mode == "Stamp"
				end,
				click = function()
					if App.mode == "Stamp" then
						App.setMode("Off")
					else
						App.startStamp()
					end
				end,
			},
		}
		local l = kind ~= "Path" and kind ~= "Clear" and handLayer() or nil
		if l then
			table.insert(hand, {
				icon = "spray",
				name = "Spray " .. l.inst.Name,
				on = function()
					return App.mode == "Place" and App.paintLayer == l
				end,
				click = function()
					App.setMode("Place", l)
				end,
			})
		end
		table.insert(groups, hand)
		local g = {}
		if kind ~= "Clear" then
			table.insert(g, {
				icon = "spline",
				name = "Draw the path",
				on = function()
					return App.mode == "Spline"
				end,
				click = function()
					if App.mode ~= "Spline" then
						App.ensureSplineFn()
					end
					App.setMode("Spline")
				end,
			})
		end
		if a and kind ~= "Clear" then
			table.insert(g, {
				icon = "close",
				name = "Remove single copies",
				danger = true,
				on = function()
					return App.mode == "Remove"
				end,
				click = function()
					App.setMode("Remove")
				end,
			})
		end
		if #g > 0 then
			table.insert(groups, g)
		end
		table.insert(groups, {
			{
				icon = "search",
				name = "Search every action",
				key = "palette",
				on = function()
					return false
				end,
				click = function()
					App.openPalette()
				end,
			},
		})
		return groups
	end

	-- the name of what's under the mouse, beside the strip
	local function showTip(b, text)
		tip.Visible = text ~= nil
		if text then
			tip.Text = text
			tip.Position = UDim2.fromOffset(strip.AbsolutePosition.X + strip.AbsoluteSize.X + 6, b.AbsolutePosition.Y + (BTN - 24) / 2)
		end
	end

	local function buildStrip()
		for _, c in strip:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		table.clear(looks)
		for gi, group in tools() do
			if gi > 1 then -- a thin line between groups
				box({ Size = UDim2.fromOffset(BTN, 7), Parent = strip }, {
					new("Frame", {
						BackgroundColor3 = P.line,
						BorderSizePixel = 0,
						Position = UDim2.fromOffset(5, 3),
						Size = UDim2.new(1, -10, 0, 1),
					}),
				})
			end
			for _, t in group do
				local b = new("TextButton", {
					Text = "",
					AutoButtonColor = false,
					BackgroundColor3 = P.accent,
					BackgroundTransparency = 1,
					Size = UDim2.fromOffset(BTN, BTN),
					Parent = strip,
				}, { corner(6) })
				local ic = App.icon(t.icon, 16, P.dim)
				ic.AnchorPoint, ic.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
				ic.Parent = b
				local hot = false
				local function look()
					local on = t.on()
					local tint = t.danger and P.danger or P.accent
					b.BackgroundColor3 = on and tint or P.hover
					b.BackgroundTransparency = on and 0 or hot and 0.2 or 1
					App.setIconColor(
						ic,
						on and (t.danger and Color3.new(1, 1, 1) or P.onAccent) or hot and P.text or (t.danger and tint:Lerp(P.dim, 0.3) or P.dim)
					)
				end
				look()
				table.insert(looks, look)
				b.MouseEnter:Connect(function()
					hot = true
					look()
					showTip(b, t.name .. (t.key and ("   " .. App.keyText(t.key)) or ""))
				end)
				b.MouseLeave:Connect(function()
					hot = false
					look()
					showTip(b, nil)
				end)
				b.MouseButton1Click:Connect(function()
					t.click()
					for _, f in looks do
						f()
					end
				end)
			end
		end
	end

	--------------------------------------------------------------------------------
	-- the top bar: the tool in use, and its settings
	--------------------------------------------------------------------------------
	local function stepRadius(up)
		G.radius = math.clamp(math.floor(G.radius * (up and 1.2 or 1 / 1.2) + 0.5), 4, 200)
		saveG()
		App.refreshSliders()
	end
	local function stampChanged()
		if App.refreshStamp then
			App.refreshStamp()
		end
	end

	-- what the bar shows for the tool in use: a title, then items
	-- { text } · { step = label, value, dec, inc } · { button = text, click, on? }
	local function options()
		local m = App.mode
		if m == "Off" then
			return nil
		end
		local items = {}
		local title
		local brushSize = {
			step = "Size",
			value = string.format("%d", G.radius),
			dec = function()
				stepRadius(false)
			end,
			inc = function()
				stepRadius(true)
			end,
		}
		if m == "Paint" or m == "Erase" then
			title = (m == "Erase" and "Erase" or "Paint") .. " · " .. G.tool
			if G.tool == "Brush" then
				table.insert(items, brushSize)
				for _, s in { "Circle", "Square" } do
					table.insert(items, {
						button = s,
						on = G.shape == s,
						click = function()
							G.shape = s
							saveG()
						end,
					})
				end
			elseif G.tool == "Fill" then
				table.insert(items, {
					step = "Reach",
					value = string.format("%d", G.fillReach),
					dec = function()
						G.fillReach = math.clamp(G.fillReach - 16, 16, 400)
						saveG()
						App.refreshSliders()
					end,
					inc = function()
						G.fillReach = math.clamp(G.fillReach + 16, 16, 400)
						saveG()
						App.refreshSliders()
					end,
				})
			else
				table.insert(items, { text = App.TOOL_HINT and App.TOOL_HINT[G.tool] or "" })
			end
		elseif m == "Stamp" then
			local st = App.stamp
			local models = st.models
			local cur = models[st.vi] or models[1]
			title = "Stamp · " .. (cur and cur.Name or "")
			table.insert(items, {
				step = "Turn",
				value = string.format("%d°", math.floor(math.deg(st.yaw) + 0.5) % 360),
				dec = function()
					App.setStamp(math.deg(st.yaw) - 15)
					stampChanged()
				end,
				inc = function()
					App.setStamp(math.deg(st.yaw) + 15)
					stampChanged()
				end,
			})
			table.insert(items, {
				step = "Size",
				value = string.format("%.2f×", st.k),
				dec = function()
					App.setStamp(nil, math.max(st.k / 1.1, 0.05))
					stampChanged()
				end,
				inc = function()
					App.setStamp(nil, math.min(st.k * 1.1, 20))
					stampChanged()
				end,
			})
			if #models > 1 then
				table.insert(items, {
					step = "Model",
					value = cur.Name,
					dec = function()
						App.setStamp(nil, nil, (st.vi - 2) % #models + 1)
						stampChanged()
					end,
					inc = function()
						App.setStamp(nil, nil, st.vi % #models + 1)
						stampChanged()
					end,
				})
			end
			table.insert(items, { button = "Random", click = App.rollStamp })
		elseif App.LAYER_MODES[m] and App.paintLayer then
			title = App.LAYER_LABEL[m] .. " · " .. App.paintLayer.inst.Name
			table.insert(items, brushSize)
		elseif m == "Spline" then
			title = App.shapeTool and ("Path · " .. App.shapeTool) or "Path"
			for _, d in Engine.SHAPES do
				table.insert(items, {
					button = d.name,
					on = App.shapeTool == d.name,
					click = function()
						App.pickShape(d.name)
					end,
				})
			end
			if App.hasPath() then
				table.insert(items, { button = "Subdivide", click = App.subdivideSpline })
			end
		elseif m == "Remove" then
			title = "Remove copies"
			table.insert(items, { text = "Click a copy to take it out" })
		else
			return nil
		end
		return title, items
	end

	local function buildBar()
		for _, c in bar:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		local title, items = options()
		bar.Visible = title ~= nil
		if not title then
			return
		end
		label(title, 12, P.text, SANS_B, { Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, Parent = bar })
		local function small(text, click, on)
			local b = new("TextButton", {
				Text = text,
				Font = SANS,
				TextSize = 12,
				TextColor3 = on and P.onAccent or P.text,
				AutoButtonColor = false,
				BackgroundColor3 = on and P.accent or P.raised,
				Size = UDim2.fromOffset(0, 24),
				AutomaticSize = Enum.AutomaticSize.X,
				Parent = bar,
			}, { corner(5), pad(8, 8, 0, 0) })
			b.MouseEnter:Connect(function()
				if not on then
					b.BackgroundColor3 = P.hover
				end
			end)
			b.MouseLeave:Connect(function()
				b.BackgroundColor3 = on and P.accent or P.raised
			end)
			b.MouseButton1Click:Connect(click)
			return b
		end
		for _, it in items do
			box({ BackgroundTransparency = 0, BackgroundColor3 = P.line, Size = UDim2.fromOffset(1, 16), Parent = bar })
			if it.text then
				label(it.text, 12, P.dim, SANS, { Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, Parent = bar })
			elseif it.step then
				label(it.step, 12, P.dim, SANS, { Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, Parent = bar })
				small("−", it.dec).Size = UDim2.fromOffset(22, 24)
				label(it.value, 12, P.text, SANS_B, {
					Size = UDim2.fromOffset(0, 24),
					AutomaticSize = Enum.AutomaticSize.X,
					TextXAlignment = Enum.TextXAlignment.Center,
					Parent = bar,
				})
				small("+", it.inc).Size = UDim2.fromOffset(22, 24)
			else
				small(it.button, it.click, it.on)
			end
		end
	end

	local function build()
		gui = new("ScreenGui", {
			Name = "SmartScatterToolbar",
			Archivable = false,
			IgnoreGuiInset = true,
			DisplayOrder = 55,
			ResetOnSpawn = false,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		})
		local function panel(props, layout)
			local f = box(props, { corner(8), stroke(P.line), layout })
			f.BackgroundTransparency, f.BackgroundColor3 = SEE, P.card
			return f
		end
		strip = panel(
			{ AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), AutomaticSize = Enum.AutomaticSize.XY, Parent = gui },
			new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) })
		)
		pad(3, 3, 3, 3).Parent = strip
		bar = panel(
			{
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 10),
				AutomaticSize = Enum.AutomaticSize.XY,
				Visible = false,
				Parent = gui,
			},
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 6),
			})
		)
		pad(10, 5, 4, 4).Parent = bar
		tip = label("", 12, P.text, SANS, {
			BackgroundTransparency = 0,
			BackgroundColor3 = P.raised,
			Size = UDim2.fromOffset(0, 24),
			AutomaticSize = Enum.AutomaticSize.X,
			Visible = false,
			Parent = gui,
		})
		corner(5).Parent = tip
		pad(8, 8, 0, 0).Parent = tip
		stripKey, barKey = nil, nil
		if not pcall(function()
			gui.Parent = game:GetService("CoreGui")
		end) then
			gui:Destroy() -- (no CoreGui here: the panel has every tool anyway)
			gui = nil
		end
	end

	-- what the strip and the bar were built for: when this changes they're built again
	local function keys()
		local a = App.area
		local l = handLayer()
		local s = string.format("%s|%s|%s|%d", a and a.folder.Name or "", a and App.kindOf(a) or "", l and l.inst.Name or "", a and #a.layers or 0)
		local st = App.stamp or {}
		local b = table.concat({
			App.mode,
			G.tool,
			G.radius,
			G.shape,
			G.fillReach,
			tostring(App.paintLayer and App.paintLayer.inst.Name),
			tostring(App.shapeTool),
			tostring(App.hasPath and App.hasPath()),
			string.format("%.3f|%.3f|%s|%d", st.yaw or 0, st.k or 0, tostring(st.vi), st.models and #st.models or 0),
		}, "|")
		return s, b
	end

	-- shows, hides or rebuilds the strip and the bar for what's going on now
	local function refresh()
		local want = App.widget.Enabled and G.toolbar ~= false
		if not want then
			if gui then
				gui.Enabled = false
			end
			return
		end
		if not (gui and gui.Parent) then
			build()
			if not gui then
				return
			end
		end
		gui.Enabled = true
		local s, b = keys()
		if s ~= stripKey then
			stripKey = s
			buildStrip()
		else
			for _, f in looks do
				f()
			end
		end
		if b ~= barKey then
			barKey = b
			buildBar()
		end
	end
	App.refreshToolbar = refresh
	local last = 0
	App.track(App.RunService.Heartbeat:Connect(function()
		if os.clock() - last >= 0.1 then
			last = os.clock()
			refresh()
		end
	end))

	-- true while the mouse is over the strip or the bar (a click there mustn't paint the ground behind them)
	App.overViewportUI = function()
		if not (gui and gui.Enabled) then
			return false
		end
		local m = Vector2.new(App.rawMouse.X, App.rawMouse.Y)
		for _, f in { strip, bar } do
			if f.Visible then
				local p, sz = f.AbsolutePosition, f.AbsoluteSize
				if m.X >= p.X and m.X <= p.X + sz.X and m.Y >= p.Y and m.Y <= p.Y + sz.Y then
					return true
				end
			end
		end
		return false
	end

	-- gone for good (the plugin unloads or updates)
	App.clearToolbar = function()
		if gui then
			gui:Destroy()
			gui = nil
		end
	end
	pcall(function() -- (one left by an earlier load of the plugin)
		local old = game:GetService("CoreGui"):FindFirstChild("SmartScatterToolbar")
		if old then
			old:Destroy()
		end
	end)
end
