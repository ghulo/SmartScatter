--[[
	Smart Scatter — Header: area menu, surface marking, header with page tabs, shared page helpers.
	Part of Main; loaded in order by the bundle. Shared state and cross-module functions live on App.
]]

return function(App)
	local Selection, beginRec, endRec = App.Selection, App.beginRec, App.endRec
	local Engine, G, saveG, num, P, SANS, SANS_M = App.Engine, App.G, App.saveG, App.num, App.P, App.SANS, App.SANS_M
	local SANS_B, new, corner, stroke, pad, vlist, box = App.SANS_B, App.new, App.corner, App.stroke, App.pad, App.vlist, App.box
	local label, hoverable, hintOn, flushRows, saveArea = App.label, App.hoverable, App.hintOn, App.flushRows, App.saveArea
	local canGenerate, runGenerate, switchArea, newArea = App.canGenerate, App.runGenerate, App.switchArea, App.newArea
	local deleteArea = App.deleteArea

	--------------------------------------------------------------------------------
	-- Build
	--------------------------------------------------------------------------------

	local function closePopup()
		if App.ui.popup then
			App.ui.popup:Destroy()
			App.ui.popup = nil
		end
	end

	local function openAreaMenu()
		closePopup()
		local catcher = new("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 50, Parent = App.root })
		catcher.MouseButton1Click:Connect(closePopup)
		App.ui.popup = catcher
		local menu = new("Frame", {
			BackgroundColor3 = P.card,
			Position = UDim2.fromOffset(
				12,
				App.ui.areaPick and (App.ui.areaPick.AbsolutePosition.Y - App.root.AbsolutePosition.Y + App.ui.areaPick.AbsoluteSize.Y + 4) or 76
			),
			Size = UDim2.new(1, -24, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			ZIndex = 51,
			Parent = catcher,
		}, { corner(10), stroke(P.line), pad(5), vlist(2) })
		local function item(t, onClick, color)
			local b = new("TextButton", {
				Text = t,
				Font = SANS,
				TextSize = 13,
				TextColor3 = color or P.text,
				TextXAlignment = Enum.TextXAlignment.Left,
				BackgroundColor3 = P.card,
				BackgroundTransparency = 1,
				AutoButtonColor = false,
				Size = UDim2.new(1, 0, 0, 32),
				ZIndex = 52,
				Parent = menu,
			}, { corner(6), pad(10, 10, 0, 0) })
			hoverable(b, P.card, P.hover)
			b.MouseButton1Click:Connect(function()
				closePopup()
				onClick()
			end)
			return b
		end
		for _, f in Engine.listAreas() do
			local b = item(f.Name, function()
				switchArea(f)
			end)
			if App.area and f == App.area.folder then
				b.Font = SANS_B
				b.TextColor3 = P.accent
			end
			local k = f:GetAttribute("SS_Kind")
			if k then
				label(k == "Clear" and "Keep clear" or k, 12, k == "Clear" and P.danger or P.accent, SANS_M, {
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, 0, 0, 0),
					Size = UDim2.fromOffset(60, 32),
					TextXAlignment = Enum.TextXAlignment.Right,
					ZIndex = 53,
					Parent = b,
				})
			end
		end
		if App.area then
			box({ BackgroundTransparency = 0, BackgroundColor3 = P.line, Size = UDim2.new(1, 0, 0, 1), ZIndex = 52, Parent = menu })
			local rename = new("TextBox", {
				Text = App.area.folder.Name,
				PlaceholderText = "Rename",
				Font = SANS,
				TextSize = 14,
				TextColor3 = P.text,
				PlaceholderColor3 = P.faint,
				BackgroundTransparency = 1,
				ClearTextOnFocus = false,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, 0, 0, 30),
				ZIndex = 52,
				Parent = menu,
			}, { pad(10, 10, 0, 0) })
			rename.FocusLost:Connect(function()
				local n = string.gsub(rename.Text, "^%s*(.-)%s*$", "%1")
				if n ~= "" and App.area and n ~= App.area.folder.Name then
					App.area.folder.Name = n
					if App.ui.areaName then
						App.ui.areaName.Text = n
					end
				end
			end)
		end
		if App.area then
			box({ BackgroundTransparency = 0, BackgroundColor3 = P.line, Size = UDim2.new(1, 0, 0, 1), ZIndex = 52, Parent = menu })
			item(App.area.locked and "Unlock area" or "Lock area", function()
				local a = App.area
				local rec = beginRec(a.locked and "Smart Scatter: Unlock area" or "Smart Scatter: Lock area")
				a.locked = not a.locked or nil
				saveArea()
				endRec(rec)
				if a.locked and App.mode ~= "Off" then
					App.setMode("Off")
				end
				App.rebuildAll()
				App.status(a.locked and "Locked: nothing regenerates or repaints here until you unlock it." or "Unlocked.")
			end, P.dim)
			item("Bake to plain models", function()
				local a = App.area
				local n = 0
				for _, f in a.folder:GetChildren() do
					n += #f:GetChildren()
				end
				if n == 0 then
					App.status("Nothing to bake yet. Generate first.")
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
				App.status(
					string.format("Baked %s objects into Workspace › %s. The area is locked; unlock it to keep editing.", num(count), out.Name)
				)
			end, P.dim)
			item("Delete area", deleteArea, P.danger)
		end
	end

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
		end
	end

	-- switch page; area tools (paint, erase, spline) stop when you leave the Area page
	App.goPage = function(name)
		if G.page == name then
			return
		end
		G.page = name
		saveG()
		if name ~= "Main" and (App.mode == "Paint" or App.mode == "Erase" or App.mode == "Spline") then
			App.setMode("Off")
		end
		App.rebuildAll()
	end
	-- small group title inside a page
	local function heading(parent, text, gapTop)
		box({ Size = UDim2.new(1, 0, 0, gapTop or 8), Parent = parent })
		label(string.upper(text), 11, P.faint, SANS_B, { Size = UDim2.new(1, 0, 0, 20), Parent = parent })
	end

	-- what an area is for: "Scatter" (painted ground to fill), "Path" (a curve things follow) or "Clear" (a keep-clear
	-- zone no area places anything on). Chosen when it's made; older areas are read from what they have.
	local KIND = {
		Scatter = { icon = "area", title = "SCATTER AREA" },
		Path = { icon = "spline", title = "PATH" },
		Clear = { icon = "clear", title = "KEEP-CLEAR ZONE" },
	}
	App.kindOf = function(a)
		if not a then
			return nil
		end
		local k = a.folder and a.folder:GetAttribute("SS_Kind")
		if KIND[k] then
			return k
		end
		if a.spline and #a.spline.pts > 0 and (a.count or 0) == 0 then
			return "Path"
		end
		return "Scatter"
	end

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
		item("area", "Scatter area", "Paint ground, fill it with objects", newArea, P.green)
		item("spline", "Path", "Draw a curve: roads, fences, lamps", function()
			App.newSplineFn()
		end, P.orange)
		item("clear", "Keep-clear zone", "Paint where nothing may go: spawns, doors", function()
			newArea({ kind = "Clear" })
		end, P.danger)
	end

	local iconButton = App.iconButton

	local function buildHeader(parent)
		local kind = App.kindOf(App.area)
		-- what's being worked on: "PATH", "SCATTER AREA"
		label(kind and KIND[kind].title or "SMART SCATTER", 11, P.faint, SANS_B, {
			Size = UDim2.new(1, 0, 0, 20),
			Parent = parent,
		})
		box({ Size = UDim2.new(1, 0, 0, 4), Parent = parent })
		local row = box({ Size = UDim2.new(1, 0, 0, 36), Parent = parent })
		-- area select: which area you're working on
		local pick = new("TextButton", {
			Text = "",
			BackgroundColor3 = P.raised,
			AutoButtonColor = false,
			Size = UDim2.new(1, -88, 1, 0),
			Parent = row,
		}, { corner(9) })
		App.ui.areaPick = pick
		local pickStroke = stroke(P.line)
		pickStroke.Parent = pick
		local kic = App.icon(kind and KIND[kind].icon or "area", 14, App.area and P.accent or P.faint)
		kic.AnchorPoint = Vector2.new(0, 0.5)
		kic.Position = UDim2.new(0, 12, 0.5, 0)
		kic.Parent = pick
		App.ui.areaName = label(App.area and App.area.folder.Name or "No area yet", 13, App.area and P.text or P.faint, SANS_B, {
			Position = UDim2.fromOffset(34, 0),
			Size = UDim2.new(1, -60, 1, 0),
			Parent = pick,
		})
		local down = App.icon("down", 12, P.faint)
		down.AnchorPoint = Vector2.new(1, 0.5)
		down.Position = UDim2.new(1, -12, 0.5, 0)
		down.Parent = pick
		pick.MouseEnter:Connect(function()
			pick.BackgroundColor3 = P.hover
		end)
		pick.MouseLeave:Connect(function()
			pick.BackgroundColor3 = P.raised
		end)
		pick.MouseButton1Click:Connect(openAreaMenu)
		hintOn(pick, "Your areas and paths: switch, rename, lock, bake or delete.")
		local plus = iconButton("plus", "New scatter area or path", function(b)
			openNewMenu(b)
		end, false, 36)
		plus.Position = UDim2.new(1, -80, 0, 0)
		plus.Parent = row
		App.ui.plusBtn = plus
		local gear = iconButton("settings", G.page == "Settings" and "Back to the area" or "Settings", function()
			App.goPage(G.page == "Settings" and "Main" or "Settings")
		end, G.page == "Settings", 36)
		gear.Position = UDim2.new(1, -36, 0, 0)
		gear.Parent = row
		App.ui.gearBtn = gear
		box({ Size = UDim2.new(1, 0, 0, 4), Parent = parent })
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
	App.buildHeader = buildHeader
	App.NICE = NICE
	App.TOOLS = TOOLS
	App.TOOL_HINT = TOOL_HINT
	App.FILTER_SURFACES = FILTER_SURFACES
	App.maskOp = maskOp
	App.primaryButton = primaryButton
end
