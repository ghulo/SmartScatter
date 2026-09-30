--[[
	Smart Scatter — Outliner: everything Smart Scatter made in this place, a row per thing, by kind (the kinds the
	features registered: zones, paths, keep-clear zones, stamps). Click one to select it; the selected zone or path
	opens to its objects (each with its picture), and a click on one makes it the active object. Double-click a name
	to rename it; the … at the end of a row, or a right-click on the row, has what can be done to it. Rows drag up and
	down: zones, paths and arrays into any order, a zone's objects into the order they're placed in (the first takes
	its room first). The eye on a row hides what it placed (for you, this session); the padlock locks it. With many
	things a filter box narrows the list as you type. The whole list folds away, and scrolls past a few rows.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local G, saveG, P, SANS, SANS_M, SANS_B = App.G, App.saveG, App.P, App.SANS, App.SANS_M, App.SANS_B
	local new, box, col, label, vlist, corner, pad = App.new, App.box, App.col, App.label, App.vlist, App.corner, App.pad
	local ROW, CHILD, MAX_H = 28, 24, 190 -- row heights, and how tall the list gets before it scrolls
	local THUMB = 18 -- a row's picture of its model
	local FILTER_FROM = 8 -- how many things before the filter box shows
	local filter = "" -- what's typed in it (kept while the panel is rebuilt)

	local renaming -- the thing whose name is being edited, if any
	App.startRename = function(thing)
		renaming = thing
		App.rebuildAll()
	end

	-- a kind's things in the order its rows show: as listed, or (a kind whose rows reorder) by the place each was
	-- dragged to, the ones never moved after them
	local function thingsOf(spec)
		local things = spec.list()
		if spec.reorder then
			local at = {}
			for i, t in things do
				at[t] = i
			end
			table.sort(things, function(a, b)
				local oa, ob = a.folder:GetAttribute("SS_Order") or math.huge, b.folder:GetAttribute("SS_Order") or math.huge
				if oa ~= ob then
					return oa < ob
				end
				return at[a] < at[b]
			end)
		end
		return things
	end
	-- puts a thing in another place among its kind (one undo step)
	App.moveThing = function(thing, to)
		local spec = App.kindSpec(thing.kind)
		if not (spec and spec.reorder) then
			return
		end
		local things = thingsOf(spec)
		local from
		for i, t in things do
			if App.sameThing(t, thing) then
				from = i
			end
		end
		to = math.clamp(to, 1, #things)
		if not from or from == to then
			return
		end
		table.insert(things, to, table.remove(things, from))
		local rec = App.beginRec("Smart Scatter: Reorder")
		for i, t in things do
			t.folder:SetAttribute("SS_Order", i)
		end
		App.endRec(rec)
		App.rebuildAll()
	end
	-- what can be done to a thing: its kind's menu, with moving it up or down where its rows reorder
	local function menuOf(spec, thing, index, n)
		local items = spec.menu and spec.menu(thing) or {}
		if spec.reorder and n > 1 then
			local at = table.find(items, "-") or #items + 1
			if index < n then
				table.insert(items, at, {
					"Move down",
					function()
						App.moveThing(thing, index + 1)
					end,
					P.dim,
				})
			end
			if index > 1 then
				table.insert(items, at, {
					"Move up",
					function()
						App.moveThing(thing, index - 1)
					end,
					P.dim,
				})
			end
		end
		return items
	end

	-- one row: icon (or its model's picture), name (or a box to rename it), count, lock, … menu
	local function thingRow(list, spec, thing, order, index, n, drag)
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
		local pictured = spec.thumb and spec.thumb(thing)
		if pictured then
			local th = App.thumbnail(pictured, THUMB)
			th.AnchorPoint, th.Position = Vector2.new(0, 0.5), UDim2.new(0, 5, 0.5, 0)
			th.Parent = b
		else
			local ic = App.icon(spec.icon, 13, sel and P.accent or P.dim)
			ic.AnchorPoint, ic.Position = Vector2.new(0, 0.5), UDim2.new(0, 8, 0.5, 0)
			ic.Parent = b
		end
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
		-- a small icon that is a switch: quiet when off (and only shown under the mouse or on the selected row), lit when on
		local quiet = {}
		local function toggle(iconName, on, hint, order, click)
			local t = new("TextButton", {
				Text = "",
				AutoButtonColor = false,
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(20, 22),
				LayoutOrder = order,
				Visible = on or sel,
				Parent = right,
			})
			local ic = App.icon(iconName, 12, on and P.accent or P.faint)
			ic.AnchorPoint, ic.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
			ic.Parent = t
			t.MouseEnter:Connect(function()
				App.setIconColor(ic, P.text)
			end)
			t.MouseLeave:Connect(function()
				App.setIconColor(ic, on and P.accent or P.faint)
			end)
			t.MouseButton1Click:Connect(click)
			App.hintOn(t, hint)
			if not on and not sel then
				table.insert(quiet, t)
			end
			return t
		end
		if spec.hide and thing.folder then
			local off = App.isHidden(thing.folder)
			toggle(
				off and "eyeOff" or "eye",
				off,
				off and "Hidden: what it placed isn't drawn (for you, until Studio closes). Click to show it." or "Hide what it placed.",
				2,
				function()
					App.setHidden(thing.folder, not off)
					App.rebuildAll()
					App.status(
						off and (name .. " is shown again.")
							or (name .. " is hidden: its copies aren't drawn. Only for you and this session; nothing in the place changed.")
					)
				end
			)
		end
		if spec.lock then
			local locked = spec.lock.get(thing)
			toggle(
				locked and "lock" or "unlock",
				locked,
				locked and "Locked: nothing here regenerates or repaints. Click to unlock." or "Lock it: nothing here changes until it's unlocked.",
				2,
				function()
					spec.lock.toggle(thing)
				end
			)
		end
		if spec.menu then
			local more = App.iconButton("down", "Rename, lock, bake, delete… (or right-click the row)", nil, false, 22)
			more.LayoutOrder = 3
			more.BackgroundTransparency = 1
			more.Parent = right
			more.MouseButton1Click:Connect(function()
				App.popupMenu(more, menuOf(spec, thing, index, n))
			end)
			b.MouseButton2Click:Connect(function()
				App.popupMenu(nil, menuOf(spec, thing, index, n))
			end)
		end
		if drag then
			drag.add(b, index)
		end
		if not sel then
			b.MouseEnter:Connect(function()
				b.BackgroundTransparency = 0
				b.BackgroundColor3 = P.hover
				for _, t in quiet do
					t.Visible = true
				end
			end)
			b.MouseLeave:Connect(function()
				b.BackgroundTransparency = 1
				for _, t in quiet do
					t.Visible = false
				end
			end)
		end
		local lastClick = 0
		b.MouseButton1Click:Connect(function()
			if drag and drag.dragged() then
				return
			end
			local now = os.clock()
			if sel and spec.menu and now - lastClick < 0.35 and thing.folder then -- double-click: rename
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

	-- the selected zone's or path's objects, under its row: each with its picture, in the order they're placed in
	local function objectRows(list, order)
		local drag = App.reorderList(function(from, to)
			App.moveObject(App.area.layers[from], to)
		end)
		local made = {}
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
					Position = UDim2.fromOffset(34 + THUMB, 0),
					Size = UDim2.new(1, -(84 + THUMB), 1, 0),
					Parent = b,
				}
			)
			local th = App.thumbnail(l.inst, THUMB)
			th.AnchorPoint, th.Position = Vector2.new(0, 0.5), UDim2.new(0, 28, 0.5, 0)
			th.Parent = b
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
				if not drag.dragged() then
					App.selectObject(l)
				end
			end)
			b.MouseButton2Click:Connect(function()
				App.popupMenu(nil, App.objectMenu(l))
			end)
			drag.add(b, i)
			table.insert(made, b)
		end
		return made
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
		local maxH = G.compact and math.floor(MAX_H * 0.6) or MAX_H -- (the compact panel gives the page more room)
		local order, any, selRow = 0, false, nil
		local rows = {} -- { row, name (lower case), kids = its object rows }: what the filter shows and hides
		local total = 0
		for _, spec in App.thingKinds() do
			total += #spec.list()
		end
		if total < FILTER_FROM then
			filter = ""
		end
		for _, spec in App.thingKinds() do
			local things = thingsOf(spec)
			local drag = spec.reorder and App.reorderList(function(from, to)
				App.moveThing(things[from], to)
			end) or nil
			for index, thing in things do
				order += 100
				any = true
				local row = thingRow(list, spec, thing, order, index, #things, drag)
				local entry = { row = row, name = string.lower(thing.folder and thing.folder.Name or spec.title), kids = {} }
				table.insert(rows, entry)
				if App.sameThing(thing, App.selected) then
					selRow = row
					if App.area and (thing.kind == "Zone" or thing.kind == "Path") and #App.area.layers > 0 then
						entry.kids = objectRows(list, order)
					end
				end
			end
		end
		if not any then
			local t = App.para("Nothing yet. + makes a zone, a path or a keep-clear zone.", { Parent = list })
			t.TextColor3 = P.faint
		end
		-- the filter: rows whose name has what's typed stay (shown and hidden in place: the box keeps its focus)
		local function applyFilter()
			local want = string.lower(filter)
			for _, e in rows do
				local show = want == "" or string.find(e.name, want, 1, true) ~= nil
				e.row.Visible = show
				for _, k in e.kids do
					k.Visible = show
				end
			end
		end
		if total >= FILTER_FROM then
			local tb = new("TextBox", {
				Text = filter,
				PlaceholderText = "Filter by name",
				PlaceholderColor3 = P.faint,
				Font = SANS,
				TextSize = 12,
				TextColor3 = P.text,
				BackgroundColor3 = P.field,
				ClearTextOnFocus = false,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, 0, 0, 24),
				LayoutOrder = -1,
				Parent = wrap,
			}, { corner(6), pad(8, 8, 0, 0) })
			scroll.LayoutOrder = 1
			tb:GetPropertyChangedSignal("Text"):Connect(function()
				filter = tb.Text
				applyFilter()
			end)
			App.ui.outlinerFilter = tb
			applyFilter()
		end
		-- as tall as its rows, up to MAX_H; then it scrolls, with the selected row in view
		local function fit()
			local h = list.AbsoluteSize.Y
			scroll.Size = UDim2.new(1, 0, 0, math.min(h, maxH))
		end
		list:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
		fit()
		if selRow then
			task.defer(function()
				if selRow.Parent then
					local top = selRow.AbsolutePosition.Y - list.AbsolutePosition.Y
					if top + ROW > maxH then
						scroll.CanvasPosition = Vector2.new(0, top - maxH / 2)
					end
				end
			end)
		end
		return wrap
	end
end
