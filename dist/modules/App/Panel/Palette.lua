--[[
	Smart Scatter — Palette: the search menu, like Blender's F3 (Space here, or whatever Settings › Shortcuts says).
	Pressed anywhere in the viewport while the panel is open, it opens at the mouse: type a few letters of anything the
	plugin can do, pick it with the arrow keys and Enter (or a click), and it's done. Actions that take things away
	for good ask first. With nothing typed it lists the last few used, then everything, by group. What can't be done
	right now isn't listed at all. A last line searches the panel's settings for what was typed.
	The actions are listed here, in one place, each calling what the module that owns it put on App.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local G, saveG, P, Engine = App.G, App.saveG, App.P, App.Engine
	local new, box, label, corner, stroke, pad = App.new, App.box, App.label, App.corner, App.stroke, App.pad
	local SANS, SANS_M, SANS_B = App.SANS, App.SANS_M, App.SANS_B
	local UIS = game:GetService("UserInputService")
	local ROW, HEAD, SHOWN, WIDTH = 30, 22, 10, 500 -- row heights, rows in view, the menu's width
	-- while it's open the world steps back, like a focus mode: a soft blur and a little less colour and light (on the
	-- camera, never saved with the place; the menu itself stays sharp)
	local BLUR, DIM = 6, { Saturation = -0.25, Brightness = -0.04 }
	local SEE = 0.08 -- how see-through the menu is
	local RECENT = 5

	--------------------------------------------------------------------------------
	-- The actions: { id, name, group, icon?, words? (more to match on), key? (a keymap id: its key is shown),
	-- run, danger? (asks first: what it says) }. Built fresh each time the menu opens, for what's possible now.
	--------------------------------------------------------------------------------
	local GROUP_ICON = {
		Generate = "logo",
		Edit = "undo",
		["Paint the ground"] = "brush",
		Objects = "layers",
		["By hand"] = "stamp",
		Path = "spline",
		Areas = "area",
		World = "search",
		Tools = "cursor",
		View = "settings",
		["Go to"] = "right",
	}
	local TOOL_ICON = { Brush = "brush", Lasso = "lasso", Box = "box", Polygon = "polygon", Fill = "fill" }
	local HAND = { -- the one-object tools, as actions per object
		{ "Place", "Spray", "spray", "place pins copies brush" },
		{ "More", "More", "plus", "thicker paint" },
		{ "Less", "Less", "minus", "thinner paint" },
		{ "None", "Erase", "trash", "none remove paint" },
	}
	-- features that live in a card: the action opens it { name, property tab (or "settings"), card id, fold (More
	-- options), words }. One not there for what's selected says so.
	local CARDS = {
		{ "Map scan", "world", "mapscan", nil, "find kinds repeated models duplicates" },
		{ "Swap models", "world", "swap", nil, "replace kind" },
		{ "Improve layout", "world", "layout", nil, "respace even gaps crowded" },
		{ "Seasons", "world", "seasons", nil, "snow snowy autumn winter dry fall" },
		{ "Snapshot and restore", "world", "snapshot", nil, "backup originals put back" },
		{ "Fix what the scan sees", "world", "scanfix", "world", "mark road building water" },
		{ "Curve of the path", "curve", "curve", nil, "strip width snap walls loop closed" },
		{ "Road", "road", "road", nil, "asphalt surface style" },
		{ "Objects", "objects", "objects", nil, "models list amount size" },
		{ "Start from a biome", "objects", "biomes", "objects", "forest meadow desert town" },
		{ "Presets", "objects", "presets", "objects", "save load share code" },
		{ "Performance", "objects", "performance", "objects", "report parts heavy" },
		{ "Ground", "zone", "ground", nil, "painted overlay colours fill selected parts erase all" },
		{ "Pattern", "zone", "pattern", nil, "groves islands veins spots bands" },
		{ "Colour zones", "zone", "zones", "zone", "color mood autumn lush frost" },
		{ "Edges and wind", "zone", "edges", "zone", "soft edge lean" },
		{ "Paint only on", "zone", "paintfilter", "zone", "surfaces filter" },
		{ "Tidy the edge", "zone", "tidy", "zone", "holes smooth grow shrink" },
		{ "Look: accent and text size", "settings", "look", nil, "theme colour font" },
		{ "Viewport settings", "settings", "viewport", nil, "overlay focus grid history" },
		{ "Game-ready output", "settings", "output", nil, "collision shadows streaming chunks boxes" },
		{ "Shortcuts", "settings", "shortcuts", "settings", "keys keybind hotkey" },
	}

	local function actions()
		local list = {}
		local function add(a)
			a.icon = a.icon or GROUP_ICON[a.group]
			table.insert(list, a)
		end
		local a = App.area
		local kind = a and App.kindOf(a)
		local open = a and not a.locked

		-- Generate
		if a then
			add({
				id = "generate",
				name = App.busy() and "Stop generating" or "Generate",
				group = "Generate",
				words = "place build run",
				run = App.generateNow,
			})
			if open then
				add({
					id = "shuffle",
					name = "Shuffle the layout",
					group = "Generate",
					icon = "refresh",
					key = "shuffle",
					words = "random new seed",
					run = App.shuffle,
				})
			end
		end
		add({
			id = "live",
			name = G.live and "Turn Live off" or "Turn Live on",
			group = "Generate",
			words = "live preview boxes automatic",
			run = App.toggleLive,
		})
		-- Edit
		add({
			id = "undo",
			name = "Undo",
			group = "Edit",
			words = "back ctrl z",
			run = function()
				App.undoStep()
			end,
		})
		add({
			id = "redo",
			name = "Redo",
			group = "Edit",
			words = "forward ctrl y",
			run = function()
				App.undoStep(true)
			end,
		})
		-- Paint the ground
		if open and kind ~= "Path" then
			for i, t in App.TOOLS do
				add({
					id = "tool" .. t,
					name = "Paint with the " .. string.lower(t),
					group = "Paint the ground",
					icon = TOOL_ICON[t],
					key = "tool" .. i,
					run = function()
						App.setTool(t)
					end,
				})
			end
			add({
				id = "erase",
				name = "Erase ground",
				group = "Paint the ground",
				icon = "trash",
				key = "erase",
				words = "remove unpaint",
				run = function()
					App.setMode("Erase")
				end,
			})
			add({
				id = "fillsel",
				name = "Fill selected parts",
				group = "Paint the ground",
				words = "island roof platform tops",
				run = App.fillSelection,
			})
			if (a.count or 0) > 0 then
				for _, m in
					{ { "holes", "Fill holes" }, { "smooth", "Smooth the edge" }, { "grow", "Grow the area" }, { "shrink", "Shrink the area" } }
				do
					add({
						id = "tidy" .. m[1],
						name = m[2],
						group = "Paint the ground",
						words = "tidy edge",
						run = function()
							App.maskOp(m[1], m[2])
						end,
					})
				end
				add({
					id = "eraseall",
					name = "Erase all paint",
					group = "Paint the ground",
					icon = "trash",
					words = "clear delete everything",
					danger = "Removes all painted ground in this area and what was placed on it. Your objects and settings stay.",
					run = App.eraseAllPaint,
				})
			end
		end
		-- Objects, and each one by hand
		if a and kind ~= "Clear" then
			if open then
				add({
					id = "addsel",
					name = "Add selected models",
					group = "Objects",
					icon = "plus",
					words = "new object add model",
					run = App.addSelected,
				})
			end
			for _, l in a.layers do
				local name = l.inst.Name
				add({
					id = "open:" .. name,
					name = name .. " settings",
					group = "Objects",
					words = "open rules object " .. l.type,
					run = function()
						App.showObject(l)
					end,
				})
				add({ -- (the stamp is no area's: any of its models, anywhere)
					id = "stamp:" .. name,
					name = "Stamp " .. name,
					group = "By hand",
					icon = "stamp",
					words = "one copy single place rotate turn model",
					run = function()
						App.startStamp(l)
					end,
				})
				if open and kind ~= "Path" and not (Engine.isLine(l) and l.s.follow == "Spline") then
					for _, h in HAND do
						add({
							id = h[1] .. ":" .. name,
							name = h[2] .. " " .. name,
							group = "By hand",
							icon = h[3],
							words = h[4],
							run = function()
								App.setMode(h[1], l)
							end,
						})
					end
				end
			end
			if open then
				add({
					id = "remove",
					name = "Remove single copies",
					group = "By hand",
					icon = "close",
					words = "delete copy click",
					run = function()
						App.setMode("Remove")
					end,
				})
			end
		end
		add({
			id = "stampsel",
			name = App.mode == "Stamp" and "Stop stamping" or "Stamp the selected models",
			group = "By hand",
			icon = "stamp",
			words = "one copy single place model anywhere",
			run = function()
				if App.mode == "Stamp" then
					App.setMode("Off")
				else
					App.startStamp()
				end
			end,
		})
		-- Path
		if open and kind ~= "Clear" then
			add({
				id = "drawpath",
				name = App.hasPath() and "Keep drawing the path" or "Draw a path",
				group = "Path",
				words = "spline curve road fence points",
				run = function()
					App.ensureSplineFn()
					App.setMode("Spline")
				end,
			})
			for _, d in Engine.SHAPES do
				add({
					id = "shape" .. d.name,
					name = "Path shape: " .. d.name,
					group = "Path",
					words = "preset loop fence ring",
					run = function()
						App.pickShape(d.name)
					end,
				})
			end
			if App.hasPath() then
				add({ id = "subdivide", name = "Subdivide the path", group = "Path", words = "add points vertices", run = App.subdivideSpline })
				add({
					id = "clearpath",
					name = "Clear the path",
					group = "Path",
					icon = "trash",
					danger = "Removes every point, branch and shape of this path.",
					run = function()
						App.clearSplineFn(App.beginRec("Smart Scatter: Clear spline"))
						App.rebuildAll()
					end,
				})
			end
		end
		-- every other tool the features registered (Core/Registry): a new tool is found here with no change to this list.
		-- (The ground, object, stamp, path and remove tools have their richer entries above; the search is this menu.)
		local COVERED = { search = true, remove = true, stamp = true, path = true }
		for _, g in App.toolGroups() do
			for _, t in g.tools do
				if not (COVERED[t.id] or string.match(t.id, "^ground:") or string.match(t.id, "^object:")) then
					add({
						id = "tool:" .. t.id,
						name = string.match(t.name, "^([^:]+)") or t.name,
						group = "Tools",
						icon = t.icon,
						key = t.key,
						words = t.name,
						run = t.click,
					})
				end
			end
		end
		-- Areas
		add({
			id = "newarea",
			name = "New zone",
			group = "Areas",
			words = "create add scatter area",
			run = function()
				App.newArea()
			end,
		})
		add({
			id = "newzonefrom",
			name = "New zone from the selected models",
			group = "Areas",
			words = "create add scatter area selection explorer",
			run = App.newZoneFromSelection,
		})
		add({
			id = "newpath",
			name = "New path",
			group = "Areas",
			icon = "spline",
			words = "create add road fence",
			run = function()
				App.newSplineFn()
			end,
		})
		add({
			id = "newclear",
			name = "New keep-clear zone",
			group = "Areas",
			icon = "clear",
			words = "create spawn door",
			run = function()
				App.newArea({ kind = "Clear" })
			end,
		})
		for _, f in Engine.listAreas() do
			if not (a and f == a.folder) then
				add({
					id = "switch:" .. f.Name,
					name = "Switch to " .. f.Name,
					group = "Areas",
					words = "area open go",
					run = function()
						App.switchArea(f)
						App.rebuildAll()
					end,
				})
			end
		end
		if a then
			add({ id = "lock", name = a.locked and "Unlock this area" or "Lock this area", group = "Areas", run = App.toggleLock })
			if kind ~= "Clear" then
				add({ id = "clearplaced", name = "Clear placed objects", group = "Areas", words = "empty remove", run = App.clearPlaced })
			end
			add({ id = "bake", name = "Bake to plain models", group = "Areas", words = "finish final export", run = App.bakeArea })
			add({
				id = "deletearea",
				name = "Delete this area",
				group = "Areas",
				icon = "trash",
				danger = "Deletes " .. a.folder.Name .. " and everything it placed.",
				run = App.deleteArea,
			})
		end
		-- the features that live in cards, and the tabs
		for _, c in CARDS do
			add({
				id = "card:" .. c[3],
				name = c[1],
				group = c[2] == "world" and "World" or "Go to",
				words = c[5],
				run = function()
					if not App.openCard(c[2], c[3], c[4]) then
						App.status(c[1] .. " isn't there for this area.")
					end
				end,
			})
		end
		for _, t in App.tabsFor(App.selected, App.active) do -- the selection's tabs, and Settings
			add({
				id = "tab:" .. t.id,
				name = t.title .. " tab",
				group = "Go to",
				words = "page open properties",
				run = function()
					App.openTab(t.id)
				end,
			})
		end
		add({
			id = "tab:settings",
			name = "Settings",
			group = "Go to",
			words = "page open preferences options",
			run = function()
				App.openSettings(true)
			end,
		})
		-- View
		add({
			id = "overlay",
			name = App.overlayHidden and "Show the overlay" or "Hide the overlay",
			group = "View",
			key = "overlay",
			run = function()
				App.overlayHidden = not App.overlayHidden
				App.rebuildOverlay()
				App.drawSpline()
			end,
		})
		for _, s in
			{
				{
					"focus",
					"Focus while a tool is on",
					function()
						App.refreshFocus()
					end,
				},
				{
					"toolbar",
					"Tools in the viewport",
					function()
						App.refreshToolbar()
					end,
				},
				{
					"grid",
					"Brush grid",
					function()
						App.clearGrid()
					end,
				},
				{
					"history",
					"History timeline",
					function()
						App.rebuildAll()
					end,
				},
			}
		do
			add({
				id = "view:" .. s[1],
				name = s[2] .. (G[s[1]] ~= false and ": turn off" or ": turn on"),
				group = "View",
				run = function()
					G[s[1]] = G[s[1]] == false
					saveG()
					s[3]()
				end,
			})
		end
		add({
			id = "tour",
			name = "Replay the tour",
			group = "View",
			icon = "info",
			words = "help learn guide",
			run = function()
				App.startTour()
			end,
		})
		return list
	end

	--------------------------------------------------------------------------------
	-- Matching: every typed word must be found. In the name is best, at its start or a word's start better still;
	-- then in the group or the extra words; last, its letters in order in the name ("gnr" finds Generate).
	-- Returns the score (higher is better) and the name's matched character spans, or nil.
	--------------------------------------------------------------------------------
	local function score(words, a)
		local name = string.lower(a.name)
		local extra = string.lower(a.group .. " " .. (a.words or ""))
		local total, spans = 0, {}
		for _, w in words do
			local i = string.find(name, w, 1, true)
			if i then
				local atWord = i == 1 or string.sub(name, i - 1, i - 1) == " "
				total += (i == 1 and 6 or atWord and 4 or 2) + #w * 0.1
				table.insert(spans, { i, i + #w - 1 })
			elseif string.find(extra, w, 1, true) then
				total += 1
			elseif #w >= 2 then
				local pos, hits = 1, {}
				for ch in string.gmatch(w, ".") do
					local j = string.find(name, ch, pos, true)
					if not j then
						return nil
					end
					table.insert(hits, { j, j })
					pos = j + 1
				end
				total += 0.5
				for _, h in hits do
					table.insert(spans, h)
				end
			else
				return nil
			end
		end
		return total, spans
	end
	App.paletteScore = score

	-- the name with its matched letters in the accent (rich text)
	local function marked(name, spans)
		local on = {}
		for _, s in spans or {} do
			for k = s[1], s[2] do
				on[k] = true
			end
		end
		local hex = P.accent:ToHex()
		local out = {}
		for k = 1, #name do
			local ch = string.sub(name, k, k)
			ch = ch == "&" and "&amp;" or ch == "<" and "&lt;" or ch == ">" and "&gt;" or ch
			table.insert(out, on[k] and string.format('<font color="#%s">%s</font>', hex, ch) or ch)
		end
		return table.concat(out)
	end

	-- what the menu lists for what's typed: { a = action, spans } rows, or { head = group } between groups
	local function results(text, all)
		local words = {}
		for w in string.gmatch(string.lower(text), "%S+") do
			table.insert(words, w)
		end
		local byId = {}
		for _, a in all do
			byId[a.id] = a
		end
		local out = {}
		if #words == 0 then
			local seen = {}
			local recent = {}
			for _, id in G.recent do
				if byId[id] and not seen[id] then
					seen[id] = true
					table.insert(recent, { a = byId[id] })
				end
			end
			if #recent > 0 then
				table.insert(out, { head = "Recent" })
				for _, r in recent do
					table.insert(out, r)
				end
			end
			local group
			for _, a in all do
				if a.group ~= group then
					group = a.group
					table.insert(out, { head = group })
				end
				table.insert(out, { a = a })
			end
			return out
		end
		local rank = {}
		for i, id in G.recent do
			rank[id] = RECENT - i + 1
		end
		for i, a in all do
			local s, spans = score(words, a)
			if s then
				table.insert(out, { a = a, spans = spans, s = s + (rank[a.id] or 0) * 0.5, i = i })
			end
		end
		table.sort(out, function(x, y)
			if x.s ~= y.s then
				return x.s > y.s
			end
			return x.i < y.i
		end)
		-- last: the panel's own search, over every setting
		table.insert(out, {
			a = {
				id = "",
				name = string.format('Search the settings for "%s"', text),
				group = "Settings",
				icon = "search",
				run = function()
					App.widget.Enabled = true
					if App.ui.search then
						App.ui.search.Text = text
					end
				end,
			},
		})
		return out
	end
	App.paletteResults = function(text)
		return results(text, actions())
	end

	--------------------------------------------------------------------------------
	-- The menu
	--------------------------------------------------------------------------------
	local gui, conns, closing = nil, {}, false
	local blur, dim -- the camera's effects while it's open

	local function stepBack(on)
		local cam = workspace.CurrentCamera
		if on and cam then
			blur = new("BlurEffect", { Name = "SmartScatterPaletteBlur", Archivable = false, Size = 0, Parent = cam })
			dim = new("ColorCorrectionEffect", { Name = "SmartScatterPaletteDim", Archivable = false, Parent = cam })
			App.tween(blur, App.FAST, { Size = BLUR })
			App.tween(dim, App.FAST, DIM)
			return
		end
		for _, e in { blur, dim } do
			App.tween(e, App.FAST, e:IsA("BlurEffect") and { Size = 0 } or { Saturation = 0, Brightness = 0 })
			task.delay(0.25, function()
				e:Destroy()
			end)
		end
		blur, dim = nil, nil
	end

	local function close()
		for _, c in conns do
			c:Disconnect()
		end
		table.clear(conns)
		if gui then
			gui:Destroy()
			gui = nil
			stepBack(false)
		end
	end
	App.closePalette = close

	local function run(a)
		close()
		if a.id ~= "" then -- remembered for next time, newest first
			local keep = { a.id }
			for _, id in G.recent do
				if id ~= a.id and #keep < RECENT then
					table.insert(keep, id)
				end
			end
			G.recent = keep
			saveG()
		end
		local function go()
			local ok, err = pcall(a.run)
			if not ok then
				warn("[Smart Scatter] " .. a.name .. " failed: " .. tostring(err))
				App.status("Couldn't do that: " .. tostring(err), "error")
			end
		end
		if a.danger then
			App.widget.Enabled = true
			App.dialog(a.name .. "?", a.danger .. " Ctrl+Z brings it back.", { { a.name, "danger", go }, { "Cancel", nil, function() end } }, "trash")
		else
			task.defer(go)
		end
	end

	App.openPalette = function()
		if gui then
			return
		end
		local all = actions()
		stepBack(true)
		gui = new("ScreenGui", {
			Name = "SmartScatterPalette",
			Archivable = false,
			IgnoreGuiInset = true,
			DisplayOrder = 60,
			ResetOnSpawn = false,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		})
		if not pcall(function()
			gui.Parent = game:GetService("CoreGui")
		end) then
			gui.Parent = App.widget -- (no CoreGui: it opens over the panel instead)
		end
		-- a click anywhere else closes it
		local back = new("TextButton", { Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = gui })
		table.insert(conns, back.MouseButton1Click:Connect(close))
		-- the menu, with its search field under the mouse (as Blender's)
		local view = gui.AbsoluteSize.X > 0 and gui.AbsoluteSize or workspace.CurrentCamera.ViewportSize
		local height = 40 + 1 + SHOWN * ROW + 8 + 24
		local mx, my = App.rawMouse.X, App.rawMouse.Y
		local win = box({
			BackgroundTransparency = SEE,
			BackgroundColor3 = P.card,
			Position = UDim2.fromOffset(
				math.clamp(mx - 60, 8, math.max(view.X - WIDTH - 8, 8)),
				math.clamp(my - 20, 8, math.max(view.Y - height - 8, 8))
			),
			Size = UDim2.fromOffset(WIDTH, height),
			ZIndex = 2,
			Parent = gui,
		}, { corner(10), stroke(P.line) })
		App.shadow(win, 10)
		local field = box({ Size = UDim2.new(1, 0, 0, 40), ZIndex = 2, Parent = win })
		local ic = App.icon("search", 14, P.faint)
		ic.Position = UDim2.fromOffset(14, 13)
		ic.Parent = field
		local tb = new("TextBox", {
			Text = "",
			PlaceholderText = "Search every action…",
			PlaceholderColor3 = P.faint,
			TextColor3 = P.text,
			Font = SANS_M,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			ClearTextOnFocus = false,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(38, 0),
			Size = UDim2.new(1, -90, 1, 0),
			ZIndex = 2,
			Parent = field,
		})
		label(App.keyText("cancel"), 11, P.faint, SANS, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -14, 0, 0),
			Size = UDim2.fromOffset(40, 40),
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 2,
			Parent = field,
		})
		box({
			BackgroundTransparency = 0,
			BackgroundColor3 = P.line,
			Position = UDim2.fromOffset(0, 40),
			Size = UDim2.new(1, 0, 0, 1),
			ZIndex = 2,
			Parent = win,
		})
		local list = new("ScrollingFrame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, 45),
			Size = UDim2.new(1, 0, 0, SHOWN * ROW),
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 3,
			ScrollBarImageColor3 = P.line,
			ZIndex = 2,
			Parent = win,
		}, { new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }), pad(6, 6, 0, 0) })
		local foot = label("↑ ↓  move     Enter  run     " .. App.keyText("cancel") .. "  close", 11, P.faint, SANS, {
			Position = UDim2.new(0, 14, 1, -26),
			Size = UDim2.new(1, -28, 0, 22),
			ZIndex = 2,
			Parent = win,
		})

		local shown, rows, sel = {}, {}, 0
		local function look()
			for k, r in rows do
				local on = k == sel
				r.b.BackgroundTransparency = on and 0 or 1
				r.bar.Visible = on
			end
			local r = rows[sel]
			if r then -- keep it in view
				local top, y = list.CanvasPosition.Y, r.b.AbsolutePosition.Y - list.AbsolutePosition.Y + list.CanvasPosition.Y
				if y < top then
					list.CanvasPosition = Vector2.new(0, y - HEAD)
				elseif y + ROW > top + SHOWN * ROW then
					list.CanvasPosition = Vector2.new(0, y + ROW - SHOWN * ROW)
				end
			end
		end
		local function fill()
			for _, c in list:GetChildren() do
				if c:IsA("GuiObject") then
					c:Destroy()
				end
			end
			shown = results(tb.Text, all)
			rows = {}
			for k, item in shown do
				if item.head then
					label(string.upper(item.head), 10, P.faint, SANS_B, {
						Size = UDim2.new(1, 0, 0, HEAD),
						LayoutOrder = k,
						ZIndex = 3,
						Parent = list,
					}).TextYAlignment =
						Enum.TextYAlignment.Bottom
				else
					local a = item.a
					local b = new("TextButton", {
						Text = "",
						AutoButtonColor = false,
						BackgroundColor3 = P.accentSoft,
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, ROW),
						LayoutOrder = k,
						ZIndex = 3,
						Parent = list,
					}, { corner(6) })
					local bar = box({
						BackgroundTransparency = 0,
						BackgroundColor3 = P.accent,
						Position = UDim2.fromOffset(0, 7),
						Size = UDim2.fromOffset(2, ROW - 14),
						Visible = false,
						ZIndex = 4,
						Parent = b,
					})
					local tint = a.danger and P.danger or P.dim
					local i = App.icon(a.icon or "right", 13, tint)
					i.Position = UDim2.fromOffset(10, (ROW - 13) / 2)
					i.ZIndex = 4
					i.Parent = b
					local right = a.key and App.keyText(a.key) or (tb.Text ~= "" and a.group or nil)
					local t = label(marked(a.name, item.spans), 13, a.danger and P.danger or P.text, SANS_M, {
						Position = UDim2.fromOffset(32, 0),
						Size = UDim2.new(1, right and -140 or -40, 1, 0),
						TextTruncate = Enum.TextTruncate.AtEnd,
						ZIndex = 4,
						Parent = b,
					})
					t.RichText = true
					if right then
						label(right, 11, P.faint, a.key and SANS_B or SANS, {
							AnchorPoint = Vector2.new(1, 0),
							Position = UDim2.new(1, -10, 0, 0),
							Size = UDim2.new(0, 100, 1, 0),
							TextXAlignment = Enum.TextXAlignment.Right,
							ZIndex = 4,
							Parent = b,
						})
					end
					local idx = #rows + 1
					rows[idx] = { b = b, bar = bar, a = a }
					b.MouseEnter:Connect(function()
						sel = idx
						look()
					end)
					b.MouseButton1Down:Connect(function() -- (on the press: the field losing focus mustn't close it first)
						closing = false
						run(a)
					end)
				end
			end
			list.CanvasPosition = Vector2.zero
			sel = #rows > 0 and 1 or 0
			foot.Text = string.format("%d  ·  ↑ ↓  move     Enter  run     %s  close", #rows, App.keyText("cancel"))
			look()
		end
		fill()
		table.insert(conns, tb:GetPropertyChangedSignal("Text"):Connect(fill))
		table.insert(
			conns,
			UIS.InputBegan:Connect(function(input)
				local k = input.KeyCode
				if k == Enum.KeyCode.Down or k == Enum.KeyCode.Up then
					if #rows > 0 then
						sel = (sel - 1 + (k == Enum.KeyCode.Down and 1 or -1)) % #rows + 1
						look()
					end
				end
			end)
		)
		table.insert(
			conns,
			tb.FocusLost:Connect(function(enter)
				if enter then
					local r = rows[sel]
					if r then
						run(r.a)
					else
						close()
					end
					return
				end
				-- Esc, or a click elsewhere (a click on a row runs it first)
				closing = true
				task.delay(0.15, function()
					if closing then
						closing = false
						close()
					end
				end)
			end)
		)
		task.defer(function() -- (after this key press, so the key that opened it isn't typed into it)
			if gui and tb.Parent then
				tb.Text = ""
				tb:CaptureFocus()
			end
		end)
	end
	-- (what an earlier load of the plugin left: the menu, or the world's blur)
	local cam = workspace.CurrentCamera
	for _, name in { "SmartScatterPaletteBlur", "SmartScatterPaletteDim" } do
		local e = cam and cam:FindFirstChild(name)
		if e then
			e:Destroy()
		end
	end
	pcall(function()
		if App.ctx.preview then -- (the panel preview leaves the real plugin's alone)
			return
		end
		local g = game:GetService("CoreGui"):FindFirstChild("SmartScatterPalette")
		if g then
			g:Destroy()
		end
	end)

	-- the search menu in the viewport's strip
	App.registerTool({
		id = "search",
		group = "Search",
		icon = "search",
		name = "Search every action",
		key = "palette",
		on = function()
			return false
		end,
		click = function()
			App.openPalette()
		end,
	})
end
