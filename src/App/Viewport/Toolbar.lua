--[[
	Smart Scatter — Toolbar: the viewport's tools, like Blender's; the one place tools live. Down the left edge, a strip
	of small square tool buttons in groups (the tools the features registered: Core/Registry), the one in use lit.
	Along the top, while a tool is on, a bar with what it acts on and its settings (the brush's size and shape, the
	stamp's turn, size and model, the path's shapes), so the eyes can stay on the viewport.
	Both follow the state they show (looked at ten times a second, rebuilt only when it changes), so no other module
	has to tell them. Where Studio won't show them (no CoreGui), the panel shows the same tools as a row
	(App.buildToolRow).
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local G, saveG, P, Engine = App.G, App.saveG, App.P, App.Engine
	local new, box, label, corner, stroke, pad = App.new, App.box, App.label, App.corner, App.stroke, App.pad
	local SANS, SANS_B = App.SANS, App.SANS_B
	local BTN, SEE = 30, 0.12 -- a tool button's size; how see-through the strip and bar are

	local gui, strip, bar, tip
	local stripKey, barKey -- what each was last built for
	local looks = {} -- the strip's buttons: fn() that colours each for the tool in use

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
		for gi, g in App.toolGroups() do
			local group = g.tools
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
					showTip(b, (string.match(t.name, "^([^:]+)") or t.name) .. (t.key and ("   " .. App.keyText(t.key)) or ""))
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
			title = (m == "Erase" and "Erase" or "Paint") .. " · " .. G.tool .. (App.area and (" · " .. App.area.folder.Name) or "")
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
		elseif m == "Array" then
			title = "Array"
			table.insert(items, { text = "Press and drag along where the copies go" })
		elseif m == "Select" then
			title = "Select"
			table.insert(items, { text = "Click a zone's ground, a path or a placed copy" })
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
		local l = App.brushTarget()
		local sel = App.selected
		local s = string.format(
			"%s|%s|%s|%d|%s",
			a and a.folder.Name or "",
			a and App.kindOf(a) or "",
			l and l.inst.Name or "",
			a and #a.layers or 0,
			sel and sel.kind or ""
		)
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
		local want = App.widget.Enabled and not App.ctx.preview -- (the panel preview draws nothing in the viewport)
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

	-- A small menu in the viewport, at the mouse: items { { text, run, color? } } or "-" for a line, a title first if
	-- given (the panel's App.popupMenu, in the 3D view). A click on an item runs it; any click closes the menu. Where
	-- Studio won't show the strip (no CoreGui), the panel's menu opens instead.
	local menu
	App.closeViewMenu = function()
		if menu then
			menu:Destroy()
			menu = nil
		end
	end
	App.viewMenu = function(items, title)
		App.closeViewMenu()
		if not App.toolbarAvailable() then
			App.popupMenu(App.ui.outliner or App.root, items, title)
			return
		end
		local at = Vector2.new(App.rawMouse.X, App.rawMouse.Y) -- (where it was opened: the mouse moves on)
		local catcher = new("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 20, Parent = gui })
		menu = catcher
		catcher.MouseButton1Click:Connect(App.closeViewMenu)
		catcher.MouseButton2Click:Connect(App.closeViewMenu)
		local W = 210
		local list = box({
			BackgroundTransparency = SEE,
			BackgroundColor3 = P.card,
			Position = UDim2.fromOffset(at.X + 4, at.Y + 4),
			Size = UDim2.fromOffset(W, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			ZIndex = 21,
			Parent = catcher,
		}, { corner(8), stroke(P.line), pad(4, 4, 4, 4), App.vlist(1) })
		if title then
			local head = label(title, 11, P.faint, SANS_B, { Size = UDim2.new(1, 0, 0, 22), ZIndex = 22, Parent = list })
			pad(8, 8, 0, 0).Parent = head
		end
		for _, it in items do
			if it == "-" then
				box({ BackgroundTransparency = 0, BackgroundColor3 = P.line, Size = UDim2.new(1, 0, 0, 1), ZIndex = 22, Parent = list })
				continue
			end
			local b = new("TextButton", {
				Text = it[1],
				Font = SANS,
				TextSize = 13,
				TextColor3 = it[3] or P.text,
				TextXAlignment = Enum.TextXAlignment.Left,
				BackgroundColor3 = P.hover,
				BackgroundTransparency = 1,
				AutoButtonColor = false,
				Size = UDim2.new(1, 0, 0, 26),
				ZIndex = 22,
				Parent = list,
			}, { corner(5), pad(8, 8, 0, 0) })
			b.MouseEnter:Connect(function()
				b.BackgroundTransparency = 0
			end)
			b.MouseLeave:Connect(function()
				b.BackgroundTransparency = 1
			end)
			b.MouseButton1Click:Connect(function()
				App.closeViewMenu()
				it[2]()
			end)
		end
		-- kept on the screen: a menu opened near the right or the bottom edge moves in (once it knows its height)
		local function keepOn()
			local screen = gui.AbsoluteSize
			list.Position = UDim2.fromOffset(
				math.max(4, math.min(at.X + 4, screen.X - W - 8)),
				math.max(4, math.min(at.Y + 4, screen.Y - list.AbsoluteSize.Y - 8))
			)
		end
		list:GetPropertyChangedSignal("AbsoluteSize"):Connect(keepOn)
		keepOn()
	end

	-- false when Studio won't show the strip (no CoreGui here): the panel then shows App.buildToolRow
	App.toolbarAvailable = function()
		if App.ctx.preview then
			return false
		end
		if not (gui and gui.Parent) then
			refresh()
		end
		return gui ~= nil
	end
	-- the same tools as a row of square buttons in the panel, for where the strip can't show; lit as they're in use
	App.buildToolRow = function(parent)
		local row = App.col({ Parent = parent }, {
			new("UIGridLayout", {
				CellSize = UDim2.fromOffset(BTN, BTN),
				CellPadding = UDim2.fromOffset(3, 3),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		local n = 0
		for _, g in App.toolGroups() do
			for _, t in g.tools do
				n += 1
				local b = App.iconButton(t.icon, (string.match(t.name, "^([^:]+)") or t.name), function()
					t.click()
					App.rebuildAll()
				end, t.on(), BTN)
				b.LayoutOrder = n
				b.Parent = row
			end
		end
		return row
	end

	-- gone for good (the plugin unloads or updates)
	App.clearToolbar = function()
		if gui then
			gui:Destroy()
			gui = nil
		end
	end
	pcall(function() -- (one left by an earlier load of the plugin; not the preview's business)
		if App.ctx.preview then
			return
		end
		local old = game:GetService("CoreGui"):FindFirstChild("SmartScatterToolbar")
		if old then
			old:Destroy()
		end
	end)
end
