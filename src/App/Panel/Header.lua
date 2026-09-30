--[[
	Smart Scatter — Header: what's done to areas (lock, clear, bake, delete, copy settings), the three area kinds as the
	outliner lists them (Zone, Path, Keep-clear zone) with their menus, the + New menu, a small popup menu, marking
	surfaces, dialogs, and helpers the panel shares.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local Selection, beginRec, endRec = App.Selection, App.beginRec, App.endRec
	local Engine, G, num, P, SANS, SANS_M = App.Engine, App.G, App.num, App.P, App.SANS, App.SANS_M
	local SANS_B, new, corner, stroke, pad, vlist, box = App.SANS_B, App.new, App.corner, App.stroke, App.pad, App.vlist, App.box
	local label, hoverable, flushRows, saveArea = App.label, App.hoverable, App.flushRows, App.saveArea
	local canGenerate, runGenerate, newArea = App.canGenerate, App.runGenerate, App.newArea
	local deleteArea = App.deleteArea

	local function closePopup()
		if App.ui.popup then
			App.ui.popup:Destroy()
			App.ui.popup = nil
		end
	end

	-- the area menu's actions (the search menu runs them too)
	App.toggleLock = function()
		local a = App.area
		if not a then
			return
		end
		local rec = beginRec(a.locked and "Smart Scatter: Unlock area" or "Smart Scatter: Lock area")
		a.locked = not a.locked or nil
		saveArea()
		endRec(rec)
		if a.locked and App.mode ~= "Off" then
			App.setMode("Off")
		end
		App.rebuildAll()
		App.status(a.locked and "Locked: nothing regenerates or repaints here until you unlock it." or "Unlocked.")
	end
	App.clearPlaced = function()
		if not App.area then
			return
		end
		local rec = beginRec("Smart Scatter: Clear")
		Engine.clearOutputs(App.area)
		endRec(rec)
		App.lastCounts, App.lastTotal = {}, 0
		App.markPending()
		App.refreshCounts()
		App.status("Cleared. The area and objects are kept; Generate brings it all back.")
	end
	App.bakeArea = function()
		if not App.area then
			return
		end
		local a = App.area
		local n = Engine.roadOf(a) and 1 or 0
		for _, f in a.folder:GetChildren() do
			n += #f:GetChildren()
		end
		if n == 0 then
			App.status("Nothing to bake yet. Generate first.")
			return
		end
		if Engine.isPreview(a) then -- boxes would be baked, not the models
			App.status("Some objects are still a preview (boxes). Press Generate first, then bake.", "error")
			return
		end
		App.cancelJob()
		local rec = beginRec("Smart Scatter: Bake")
		local out, count = Engine.bake(a)
		a.locked = true -- so the area doesn't fill itself again on the next edit
		saveArea()
		endRec(rec)
		Selection:Set({ out })
		App.lastCounts, App.lastTotal, App.lastParts = {}, 0, 0
		App.rebuildAll()
		App.status(string.format("Baked %s objects into Workspace › %s. The area is locked; unlock it to keep editing.", num(count), out.Name))
	end

	-- A small menu over the panel, under `anchor` (a GuiObject) or at the mouse: items { { text, run, color?, tag? } }
	-- (color: P.danger for one that takes something away; tag: a quiet word on the right); a title line first if
	-- given. A click on an item runs it; any click closes the menu.
	App.popupMenu = function(anchor, items, title)
		closePopup()
		local root = App.root
		local catcher = new("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 50, Parent = root })
		catcher.MouseButton1Click:Connect(closePopup)
		catcher.MouseButton2Click:Connect(closePopup)
		App.ui.popup = catcher
		local x, y
		if anchor then
			x = anchor.AbsolutePosition.X - root.AbsolutePosition.X
			y = anchor.AbsolutePosition.Y - root.AbsolutePosition.Y + anchor.AbsoluteSize.Y + 4
		else
			local m = App.widget:GetRelativeMousePosition()
			x, y = m.X, m.Y
		end
		local w = math.min(250, root.AbsoluteSize.X - 24)
		local menu = new("Frame", {
			BackgroundColor3 = P.card,
			Position = UDim2.fromOffset(math.clamp(x, 12, math.max(12, root.AbsoluteSize.X - w - 12)), y),
			Size = UDim2.fromOffset(w, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			ZIndex = 51,
			Parent = catcher,
		}, { corner(10), stroke(P.line), pad(5), vlist(2) })
		if title then
			local head = box({ Size = UDim2.new(1, 0, 0, 24), ZIndex = 52, Parent = menu }, { pad(10, 10, 0, 0) })
			label(title, 11, P.faint, SANS_B, { Size = UDim2.fromScale(1, 1), ZIndex = 52, Parent = head })
		end
		for _, it in items do
			if it == "-" then -- a line between groups of items
				box({ BackgroundTransparency = 0, BackgroundColor3 = P.line, Size = UDim2.new(1, 0, 0, 1), ZIndex = 52, Parent = menu })
				continue
			end
			local b = new("TextButton", {
				Text = it[1],
				Font = SANS,
				TextSize = 13,
				TextColor3 = it[3] or P.text,
				TextXAlignment = Enum.TextXAlignment.Left,
				BackgroundColor3 = P.card,
				BackgroundTransparency = 1,
				AutoButtonColor = false,
				Size = UDim2.new(1, 0, 0, 30),
				ZIndex = 52,
				Parent = menu,
			}, { corner(6), pad(10, 10, 0, 0) })
			hoverable(b, P.card, P.hover)
			if it[4] then
				label(it[4], 12, P.accent, SANS_M, {
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, 0, 0, 0),
					Size = UDim2.fromOffset(70, 30),
					TextXAlignment = Enum.TextXAlignment.Right,
					ZIndex = 53,
					Parent = b,
				})
			end
			b.MouseButton1Click:Connect(function()
				closePopup()
				it[2]()
			end)
		end
		-- a menu that would run off the bottom of the panel moves up to fit (once it knows its height)
		local function keepOn()
			local over = y + menu.AbsoluteSize.Y + 8 - root.AbsoluteSize.Y
			if over > 0 then
				menu.Position = UDim2.fromOffset(menu.Position.X.Offset, math.max(8, y - over))
			end
		end
		menu:GetPropertyChangedSignal("AbsoluteSize"):Connect(keepOn)
		keepOn()
	end

	--------------------------------------------------------------------------------
	-- The area kinds, as the outliner lists them. Each thing's menu acts on it (selecting it first: the actions work
	-- on the area being worked on).
	--------------------------------------------------------------------------------
	local function areasOf(kind)
		return function()
			local out = {}
			for _, f in Engine.listAreas() do
				local t = App.thingOf(f)
				if t.kind == kind then
					table.insert(out, t)
				end
			end
			return out
		end
	end
	local function on(thing, fn)
		return function()
			if not App.sameThing(App.selected, thing) then
				App.select(thing)
			end
			fn()
		end
	end
	local function areaMenu(thing)
		local items = {
			{
				"Rename",
				function()
					if App.startRename then
						App.startRename(thing)
					end
				end,
			},
			{ thing.folder:GetAttribute("SS_Locked") and "Unlock" or "Lock", on(thing, App.toggleLock), P.dim },
		}
		if thing.kind ~= "Clear" and #Engine.listAreas() > 1 then
			table.insert(items, {
				"Copy settings from…",
				on(thing, function()
					local others = {}
					for _, f in Engine.listAreas() do
						if f ~= thing.folder and f:GetAttribute("SS_Kind") ~= "Clear" then
							table.insert(others, {
								f.Name,
								function()
									-- the look replaces this area's; objects are added (ones it has stay as they are). One
									-- undo step: adding the objects saves the area with the new look.
									local src = Engine.loadArea(f)
									Engine.copyLook(src, App.area)
									App.addLayers(Engine.layersFromJSON(Engine.layersToJSON(src.layers, false)), f.Name)
								end,
							})
						end
					end
					task.defer(App.popupMenu, nil, others, "COPY PATTERN, EDGES, COLOURS AND OBJECTS FROM")
				end),
				P.dim,
			})
		end
		table.insert(items, "-")
		if thing.kind ~= "Clear" then
			table.insert(items, { "Clear placed objects", on(thing, App.clearPlaced), P.dim })
		end
		table.insert(items, { "Bake to plain models", on(thing, App.bakeArea), P.dim })
		table.insert(items, { "Delete", on(thing, deleteArea), P.danger })
		return items
	end
	-- an area's rename (from the outliner): the folder's name is the area's name
	App.renameThing = function(thing, name)
		name = string.gsub(name or "", "^%s*(.-)%s*$", "%1")
		if name ~= "" and thing.folder and thing.folder.Name ~= name then
			thing.folder.Name = name
		end
	end
	local function placed(thing) -- (known for the area being worked on; the others would each need loading)
		return App.area and App.area.folder == thing.folder and App.lastTotal or nil
	end
	App.registerKind({
		kind = "Zone",
		icon = "area",
		title = "Zone",
		order = 10,
		list = areasOf("Zone"),
		count = placed,
		menu = areaMenu,
		reorder = true,
	})
	App.registerKind({
		kind = "Path",
		icon = "spline",
		title = "Path",
		order = 20,
		list = areasOf("Path"),
		count = placed,
		menu = areaMenu,
		reorder = true,
	})
	App.registerKind({
		kind = "Clear",
		icon = "clear",
		title = "Keep-clear zone",
		order = 30,
		list = areasOf("Clear"),
		menu = areaMenu,
		reorder = true,
	})

	App.markSelected = function(cls)
		local sel = Selection:Get()
		if #sel == 0 then
			App.status("Select the road, path or building parts first.")
			return
		end
		local rec = beginRec("Smart Scatter: Mark surface")
		local n, meshes = 0, 0
		for _, inst in sel do
			if inst:IsA("BasePart") or inst:IsA("Model") or inst:IsA("Folder") then
				inst:SetAttribute("SS_Surface", cls)
				n += 1
				local parts = inst:IsA("BasePart") and { inst } or inst:GetDescendants()
				for _, p in parts do
					if p:IsA("MeshPart") and p.MeshId ~= "" then
						Engine.teachMesh(p.MeshId, cls)
						meshes += 1
					end
				end
				-- a marked surface is never also a scatter layer
				if cls and App.area then
					for i = #App.area.layers, 1, -1 do
						if App.area.layers[i].inst == inst then
							table.remove(App.area.layers, i)
						end
					end
				end
			end
		end
		endRec(rec)
		if n == 0 then
			App.status("Select parts, models or folders to mark.")
			return
		end
		App.status(
			cls and string.format("Marked %d as %s%s.", n, string.lower(cls), meshes > 0 and " (meshes remembered for every copy)" or "")
				or string.format("Cleared the mark on %d.", n)
		)
		Engine.freshSurfaces() -- the overlay and the next scan read the new mark right away
		App.analysisDirty = true
		saveArea()
		App.refreshObjects()
		if G.live and canGenerate() then
			runGenerate(true)
		else
			App.markPending()
		end
	end

	-- small group title inside a page
	local function heading(parent, text, gapTop)
		box({ Size = UDim2.new(1, 0, 0, gapTop or 8), Parent = parent })
		label(text, 12, P.dim, SANS_B, { Size = UDim2.new(1, 0, 0, 20), Parent = parent })
	end

	-- + New: a zone, a path or a keep-clear zone
	local function openNewMenu(anchor)
		closePopup()
		local catcher = new("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 50, Parent = App.root })
		catcher.MouseButton1Click:Connect(closePopup)
		App.ui.popup = catcher
		local menu = new("Frame", {
			BackgroundColor3 = P.card,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromOffset(
				anchor.AbsolutePosition.X - App.root.AbsolutePosition.X + anchor.AbsoluteSize.X,
				anchor.AbsolutePosition.Y - App.root.AbsolutePosition.Y + anchor.AbsoluteSize.Y + 4
			),
			Size = UDim2.fromOffset(250, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			ZIndex = 51,
			Parent = catcher,
		}, { corner(10), stroke(P.line), pad(5), vlist(2) })
		local function item(iconName, title, sub, onClick, color)
			local b = new("TextButton", {
				Text = "",
				BackgroundColor3 = P.card,
				AutoButtonColor = false,
				Size = UDim2.new(1, 0, 0, 48),
				ZIndex = 52,
				Parent = menu,
			}, { corner(7) })
			hoverable(b, P.card, P.hover)
			local badge = box({
				BackgroundTransparency = 0,
				BackgroundColor3 = color:Lerp(P.card, 0.82),
				Size = UDim2.fromOffset(32, 32),
				Position = UDim2.fromOffset(8, 8),
				ZIndex = 53,
				Parent = b,
			}, { corner(8) })
			local ic = App.icon(iconName, 16, color)
			ic.AnchorPoint = Vector2.new(0.5, 0.5)
			ic.Position = UDim2.fromScale(0.5, 0.5)
			ic.ZIndex = 54
			ic.Parent = badge
			label(title, 13, P.text, SANS_B, { Position = UDim2.fromOffset(50, 7), Size = UDim2.new(1, -58, 0, 18), ZIndex = 53, Parent = b })
			label(sub, 12, P.faint, SANS, { Position = UDim2.fromOffset(50, 25), Size = UDim2.new(1, -58, 0, 16), ZIndex = 53, Parent = b })
			b.MouseButton1Click:Connect(function()
				closePopup()
				onClick()
			end)
		end
		item("area", "Zone", "Paint ground, fill it with objects", newArea, P.accent)
		item("layers", "Zone from selected models", "The models picked in the Explorer, ready to paint", function()
			App.newZoneFromSelection()
		end, P.accent)
		item("grid", "Array from selected model", "A row, grid or circle of it, or along a path", function()
			App.newArrayFromSelection()
		end, P.accent)
		item("spline", "Path", "Draw a curve: roads, fences, lamps", function()
			App.newSplineFn()
		end, P.accent)
		item("clear", "Keep-clear zone", "Paint where nothing may go: spawns, doors", function()
			newArea({ kind = "Clear" })
		end, P.danger)
	end

	local NICE = { Dirt = "Path", Generic = "Other" }
	local TOOLS = { "Brush", "Lasso", "Box", "Polygon", "Fill" }
	local TOOL_HINT = {
		Brush = "Paint with a round or square brush. Hold Shift to erase, [ and ] resize.",
		Lasso = "Draw an outline freehand; the inside fills when you let go.",
		Box = "Drag a rectangle to fill it.",
		Polygon = "Click corner points, then click the first point, double-click, right-click or press Enter to close.",
		Fill = "Click a surface to fill everything connected to it: a field between roads, a lawn, a clearing.",
	}
	local FILTER_SURFACES = { "Grass", "Dirt", "Road", "Rock", "Sand", "Snow", "Generic" }

	-- runs a cleanup op on the whole mask as one undoable step
	local function maskOp(op, name)
		if not App.area or App.area.count == 0 then
			App.status("Paint an area first.")
			return
		end
		local rec = beginRec("Smart Scatter: " .. name)
		local changed = Engine.maskMorph(App.area, op)
		for _, cc in changed do
			App.dirtyRows[cc[2]] = true
		end
		if #changed > 0 then
			saveArea()
		end
		endRec(rec, #changed == 0) -- the undo step holds the ground; the objects are rebuilt after it
		if #changed > 0 then
			flushRows()
			App.analysisDirty = true
			if G.live and canGenerate() then
				runGenerate(false)
			else -- (Shrink, Smooth: the copies on the ground taken away go now)
				local gone = {}
				for _, cc in changed do
					if not Engine.hasCell(App.area, cc[1], cc[2]) then
						gone[App.cellKey(cc[1], cc[2])] = true
					end
				end
				App.dropErased(gone, {})
				App.markPending()
			end
		end
		if #changed == 0 then
			App.status(name .. ": nothing to change.")
			return
		end
		if not (G.live and canGenerate()) then
			App.refreshScan()
			App.refreshCounts()
		end
		App.status(string.format("%s: %s cells changed.", name, num(#changed)))
	end

	-- filled accent button for the one main action of a section
	local function primaryButton(text, onClick)
		local b = new("TextButton", {
			Text = text,
			Font = SANS_B,
			TextSize = 14,
			TextColor3 = P.onAccent,
			BackgroundColor3 = P.accent,
			AutoButtonColor = false,
			Size = UDim2.new(1, 0, 0, 42),
		}, { corner(10) })
		App.shade(b, 0.12) -- lit from the top, like the design's glossy button
		App.topLight(b, 0.35, 8)
		App.pressable(b, 0.98) -- (no glow: it runs the card's full width, and the gap to the card's edge stays clean)
		local function rest()
			return b:GetAttribute("secondary") and P.raised or P.accent
		end
		b.MouseEnter:Connect(function()
			b.BackgroundColor3 = rest():Lerp(Color3.new(1, 1, 1), 0.1)
		end)
		b.MouseLeave:Connect(function()
			b.BackgroundColor3 = rest()
		end)
		b.MouseButton1Click:Connect(onClick)
		return b
	end

	-- used by later modules
	-- a message that needs an answer, over the panel: title, text and buttons { { text, kind, onClick }, ... }
	-- (kind as for App.button; the first is the main one). Any button, or a click outside, closes it.
	-- tone: "accent" for good news (an update), otherwise a warning
	App.dialog = function(title, text, actions, iconName, tone)
		local tint = tone == "accent" and P.accent or P.danger
		closePopup()
		local shade = new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.45,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 50,
			Parent = App.root,
		})
		shade.MouseButton1Click:Connect(closePopup)
		App.ui.popup = shade
		local card = new("TextButton", { -- a button, so clicks on the card don't fall through and close it
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = P.card,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.45),
			Size = UDim2.new(1, -32, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			ZIndex = 51,
			Parent = shade,
		}, { corner(14), stroke(P.line), pad(16, 16, 16, 16), vlist(10) })
		local head = box({ Size = UDim2.new(1, 0, 0, 32), ZIndex = 52, Parent = card })
		local badge = box({
			BackgroundTransparency = 0,
			BackgroundColor3 = tint:Lerp(P.card, 0.84),
			Size = UDim2.fromOffset(32, 32),
			ZIndex = 52,
			Parent = head,
		}, { corner(8) })
		local ic = App.icon(iconName or "info", 16, tint)
		ic.AnchorPoint, ic.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
		ic.Parent = badge
		for _, d in ic:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex = 53
			end
		end
		label(title, 14, P.text, SANS_B, { Position = UDim2.fromOffset(44, 0), Size = UDim2.new(1, -44, 1, 0), ZIndex = 52, Parent = head })
		local body = App.para(text, { ZIndex = 52, Parent = card })
		body.TextColor3 = P.dim
		local row = App.buttonRow(card)
		row.ZIndex = 52
		for i, a in actions do
			local b = App.button(a[1], a[2], function()
				closePopup()
				a[3]()
			end, { LayoutOrder = i, ZIndex = 53, Parent = row })
			for _, d in b:GetDescendants() do
				if d:IsA("GuiObject") then
					d.ZIndex = 54
				end
			end
		end
	end
	App.closePopup = closePopup
	App.heading = heading
	App.openNewMenu = openNewMenu
	App.NICE = NICE
	App.TOOLS = TOOLS
	App.TOOL_HINT = TOOL_HINT
	App.FILTER_SURFACES = FILTER_SURFACES
	App.maskOp = maskOp
	App.primaryButton = primaryButton
end
