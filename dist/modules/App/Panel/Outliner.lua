--[[
	Smart Scatter — Outliner: everything Smart Scatter made in this place, a row per thing, by kind (the kinds the
	features registered: zones, paths, keep-clear zones, stamps). Click one to select it; the selected zone or path
	opens to its objects, and a click on one makes it the active object. Double-click a name to rename it; the … at
	the end of a row has what can be done to it. The whole list folds away, and scrolls past a few rows.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local G, saveG, P, SANS, SANS_M, SANS_B = App.G, App.saveG, App.P, App.SANS, App.SANS_M, App.SANS_B
	local new, box, col, label, vlist, corner, pad = App.new, App.box, App.col, App.label, App.vlist, App.corner, App.pad
	local ROW, CHILD, MAX_H = 28, 24, 190 -- row heights, and how tall the list gets before it scrolls

	local renaming -- the thing whose name is being edited, if any
	App.startRename = function(thing)
		renaming = thing
		App.rebuildAll()
	end

	-- one row: icon, name (or a box to rename it), count, lock, … menu
	local function thingRow(list, spec, thing, order)
		local sel = App.sameThing(thing, App.selected)
		local b = new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = sel and P.accentSoft or P.card,
			BackgroundTransparency = sel and 0 or 1,
			Size = UDim2.new(1, 0, 0, ROW),
			LayoutOrder = order,
			Parent = list,
		}, { corner(6) })
		local ic = App.icon(spec.icon, 13, sel and P.accent or P.dim)
		ic.AnchorPoint, ic.Position = Vector2.new(0, 0.5), UDim2.new(0, 8, 0.5, 0)
		ic.Parent = b
		local name = thing.folder and thing.folder.Name or spec.title
		if renaming and App.sameThing(renaming, thing) then
			local tb = new("TextBox", {
				Text = name,
				Font = SANS_B,
				TextSize = 13,
				TextColor3 = P.text,
				BackgroundColor3 = P.field,
				ClearTextOnFocus = false,
				TextXAlignment = Enum.TextXAlignment.Left,
				Position = UDim2.fromOffset(28, 3),
				Size = UDim2.new(1, -66, 1, -6),
				Parent = b,
			}, { corner(5), pad(6, 6, 0, 0) })
			tb.FocusLost:Connect(function(enter)
				if enter or tb.Text ~= name then
					App.renameThing(thing, tb.Text)
				end
				renaming = nil
				task.defer(App.rebuildAll)
			end)
			task.defer(function()
				tb:CaptureFocus()
				tb.SelectionStart, tb.CursorPosition = 1, #tb.Text + 1
			end)
		else
			label(name, 13, sel and P.text or P.dim, sel and SANS_B or SANS_M, {
				Position = UDim2.fromOffset(28, 0),
				Size = UDim2.new(1, -110, 1, 0),
				Parent = b,
			})
		end
		-- on the right: how many it placed, locked, the menu
		local right = box({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -4, 0.5, 0),
			Size = UDim2.fromOffset(0, 22),
			AutomaticSize = Enum.AutomaticSize.X,
			Parent = b,
		}, { App.hlist(4) })
		local n = spec.count and spec.count(thing)
		local count = label(n and n > 0 and App.num(n) or "", 11, P.faint, SANS, {
			Size = UDim2.fromOffset(0, 22),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = 1,
			Parent = right,
		})
		if sel then
			App.ui.outlinerCount = count -- (refreshCounts keeps it current)
		end
		if thing.folder and thing.folder:GetAttribute("SS_Locked") then
			local lock = label("locked", 11, P.faint, SANS, {
				Size = UDim2.fromOffset(0, 22),
				AutomaticSize = Enum.AutomaticSize.X,
				LayoutOrder = 2,
				Parent = right,
			})
			lock.TextXAlignment = Enum.TextXAlignment.Right
		end
		if spec.menu then
			local more = App.iconButton("down", "Rename, lock, bake, delete…", nil, false, 22)
			more.LayoutOrder = 3
			more.BackgroundTransparency = 1
			more.Parent = right
			more.MouseButton1Click:Connect(function()
				App.popupMenu(more, spec.menu(thing))
			end)
		end
		if not sel then
			b.MouseEnter:Connect(function()
				b.BackgroundTransparency = 0
				b.BackgroundColor3 = P.hover
			end)
			b.MouseLeave:Connect(function()
				b.BackgroundTransparency = 1
			end)
		end
		local lastClick = 0
		b.MouseButton1Click:Connect(function()
			local now = os.clock()
			if sel and spec.menu and now - lastClick < 0.35 and App.isArea(thing) then -- double-click: rename
				App.startRename(thing)
				return
			end
			lastClick = now
			if not sel then
				App.select(thing)
			elseif App.active then -- the thing itself again: no object active
				App.selectObject(nil)
			end
		end)
		return b
	end

	-- the selected zone's or path's objects, under its row
	local function objectRows(list, order)
		for i, l in App.area.layers do
			local on = l == App.active
			local b = new("TextButton", {
				Text = "",
				AutoButtonColor = false,
				BackgroundColor3 = on and P.accentSoft or P.card,
				BackgroundTransparency = on and 0 or 1,
				Size = UDim2.new(1, 0, 0, CHILD),
				LayoutOrder = order + i,
				Parent = list,
			}, { corner(6) })
			box({ -- the thread from its zone
				BackgroundTransparency = 0,
				BackgroundColor3 = P.line,
				Position = UDim2.fromOffset(14, 0),
				Size = UDim2.new(0, 1, 1, i == #App.area.layers and -CHILD / 2 or 0),
				Parent = b,
			})
			box({
				BackgroundTransparency = 0,
				BackgroundColor3 = P.line,
				Position = UDim2.new(0, 14, 0.5, 0),
				Size = UDim2.fromOffset(10, 1),
				Parent = b,
			})
			label(
				l.inst.Name .. (#l.variants > 1 and ("  +" .. (#l.variants - 1)) or ""),
				12,
				on and P.accent or (l.s.enabled and P.text or P.faint),
				on and SANS_B or SANS,
				{
					Position = UDim2.fromOffset(30, 0),
					Size = UDim2.new(1, -80, 1, 0),
					Parent = b,
				}
			)
			local what = App.Engine.isLine(l) and "along" or string.lower(l.type)
			local tag = label(l.s.enabled and what or "off", 11, P.faint, SANS, {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -8, 0, 0),
				Size = UDim2.fromOffset(60, CHILD),
				Parent = b,
			})
			tag.TextXAlignment = Enum.TextXAlignment.Right
			if not on then
				b.MouseEnter:Connect(function()
					b.BackgroundTransparency = 0
					b.BackgroundColor3 = P.hover
				end)
				b.MouseLeave:Connect(function()
					b.BackgroundTransparency = 1
				end)
			end
			b.MouseButton1Click:Connect(function()
				App.selectObject(l)
			end)
		end
	end

	App.buildOutliner = function(parent)
		local wrap = col({ Parent = parent }, { vlist(4) })
		-- its head: the name, and the fold
		local head =
			new("TextButton", { Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), Parent = wrap })
		local chev = App.icon("right", 10, P.faint)
		chev.AnchorPoint, chev.Position = Vector2.new(0, 0.5), UDim2.new(0, 2, 0.5, 0)
		chev.Rotation = G.outliner and 90 or 0
		chev.Parent = head
		local title = label("OUTLINER", 11, P.faint, SANS_B, { Position = UDim2.fromOffset(18, 0), Size = UDim2.new(1, -18, 1, 0), Parent = head })
		head.MouseEnter:Connect(function()
			title.TextColor3 = P.text
		end)
		head.MouseLeave:Connect(function()
			title.TextColor3 = P.faint
		end)
		head.MouseButton1Click:Connect(function()
			G.outliner = not G.outliner
			saveG()
			App.rebuildAll()
		end)
		App.hintOn(head, "Everything Smart Scatter made in this place. Click one to work on it.")
		App.ui.outliner = wrap
		if not G.outliner then
			local sel = App.selected
			local spec = sel and App.kindSpec(sel.kind)
			title.Text = sel and ("OUTLINER  ·  " .. string.upper(sel.folder and sel.folder.Name or (spec and spec.title or ""))) or "OUTLINER"
			return wrap
		end
		local scroll = new("ScrollingFrame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 3,
			ScrollBarImageColor3 = P.faint,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
			Parent = wrap,
		})
		local list = col({ Parent = scroll }, { vlist(1) })
		local order, any, selRow = 0, false, nil
		for _, spec in App.thingKinds() do
			for _, thing in spec.list() do
				order += 100
				any = true
				local row = thingRow(list, spec, thing, order)
				if App.sameThing(thing, App.selected) then
					selRow = row
					if App.area and (thing.kind == "Zone" or thing.kind == "Path") and #App.area.layers > 0 then
						objectRows(list, order)
					end
				end
			end
		end
		if not any then
			local t = App.para("Nothing yet. + makes a zone, a path or a keep-clear zone.", { Parent = list })
			t.TextColor3 = P.faint
		end
		-- as tall as its rows, up to MAX_H; then it scrolls, with the selected row in view
		local function fit()
			local h = list.AbsoluteSize.Y
			scroll.Size = UDim2.new(1, 0, 0, math.min(h, MAX_H))
		end
		list:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
		fit()
		if selRow then
			task.defer(function()
				if selRow.Parent then
					local top = selRow.AbsolutePosition.Y - list.AbsolutePosition.Y
					if top + ROW > MAX_H then
						scroll.CanvasPosition = Vector2.new(0, top - MAX_H / 2)
					end
				end
			end)
		end
		return wrap
	end
end
