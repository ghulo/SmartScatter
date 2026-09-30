--[[
	Panel checks (a dev tool): runs the panel from src/ (panel.lua) on a zone of its own, far from the map, and checks
	what needs the whole plugin together: picking placed copies (one, several, a box of them) and changing them, the
	viewport header's contents, the quick menu's fallback, the outliner's eye, padlock and filter, adjusting the last
	edit helper, and the compact panel. What needs a real mouse (the drag itself, the menus drawn in the viewport)
	isn't covered. Run with HttpService on for the call; returns a report. It leaves "Smart Scatter" steps in the
	undo history, and nothing else: everything it makes is removed.
]]
local HS = game:GetService("HttpService")
local SS = game:GetService("ServerStorage")
local Selection = game:GetService("Selection")
local URL = "http://127.0.0.1:8766/"

local report, failed, made = {}, 0, {}
local function check(name, ok, detail)
	if not ok then
		failed += 1
	end
	table.insert(report, (ok and "ok    " or "FAIL  ") .. name .. ((detail ~= nil and not ok) and ("  |  " .. tostring(detail)) or ""))
end
local keepSel = Selection:Get()
local cam = workspace.CurrentCamera
local camWas, focusWas = cam.CFrame, cam.Focus

local okAll, err = pcall(function()
	assert(loadstring(HS:GetAsync(URL .. "panel.lua", true)))()
	local App = _G.SS_Preview.app
	local E = App.Engine
	local O = Vector3.new(30000, 300, 30000)

	-- a patch of ground, a model to scatter, a zone painted over the ground and generated
	local ground = Instance.new("Part")
	ground.Name = "SS_ChecksGround"
	ground.Anchored = true
	ground.Size = Vector3.new(160, 4, 160)
	ground.Position = O
	ground.Material = Enum.Material.Grass
	ground.Parent = workspace
	table.insert(made, ground)
	local rock = Instance.new("Model")
	rock.Name = "SS_ChecksRock"
	local part = Instance.new("Part")
	part.Anchored = true
	part.Size = Vector3.new(3, 2, 3)
	part.Parent = rock
	rock.PrimaryPart = part
	rock.Parent = SS
	table.insert(made, rock)
	App.newArea({ keepMode = true })
	local zone = App.area.folder
	table.insert(made, zone)
	local cell = App.area.cell
	for cx = math.floor((O.X - 40) / cell), math.floor((O.X + 40) / cell) do
		for cz = math.floor((O.Z - 40) / cell), math.floor((O.Z + 40) / cell) do
			E.setCell(App.area, cx, cz, true)
		end
	end
	Selection:Set({ rock })
	App.addSelected()
	App.saveArea()
	task.wait(0.3)
	local function copies()
		local t = {}
		for _, d in zone:GetDescendants() do
			if d:GetAttribute("SS_Type") then
				table.insert(t, d)
			end
		end
		return t
	end
	local function spots(but)
		local t = {}
		for _, d in copies() do
			if not (but and table.find(but, d)) then
				table.insert(t, string.format("%.2f,%.2f", d:GetAttribute("SS_X"), d:GetAttribute("SS_Z")))
			end
		end
		table.sort(t)
		return table.concat(t, " ")
	end
	App.analysisDirty = true
	App.runGenerate(true)
	local t0 = os.clock()
	while (#copies() == 0 or App.busy()) and os.clock() - t0 < 15 do
		task.wait(0.1)
	end
	local n0 = #copies()
	check("the zone placed copies", n0 > 6, n0)
	local function settle(want)
		local t = os.clock()
		while os.clock() - t < 5 do
			task.wait(0.1)
			if not App.busy() and (want == nil or want()) then
				return true
			end
		end
		return false
	end
	local function allThere(n)
		return function()
			return #App.pickedCopies() == n
		end
	end
	-- the mouse: aimed straight down at a copy, or at a spot; Shift as wanted
	local shift = false
	App.shiftHeld = function()
		return shift
	end
	local function aim(at)
		App.rawMouse.UnitRay = Ray.new(Vector3.new(at.X, O.Y + 80, at.Z), Vector3.new(0, -1, 0))
	end
	local function click(at, withShift)
		shift = withShift == true
		aim(at)
		App.selectMove()
		App.selectDown()
		App.selectUp()
		shift = false
	end

	-- ── one copy ─────────────────────────────────────────────────────────────────
	App.setMode("Select")
	local list = copies()
	local c1 = list[1]
	local x, z, h0 = c1:GetAttribute("SS_X"), c1:GetAttribute("SS_Z"), c1:GetExtentsSize().Y
	local others = spots({ c1 })
	click(c1:GetPivot().Position)
	check(
		"a click on a copy picks it: its zone selected, its object active",
		App.pickedCopy() == c1 and App.active ~= nil and App.selected.folder == zone
	)
	local title, items = App.copyHeader()
	local steps, buttons = {}, {}
	for _, it in items do
		table.insert(it.step and steps or buttons, it.step or it.button or "text")
	end
	check(
		"the header names it and has Turn, Size, Move and Remove",
		title == c1.Name and table.concat(steps, ",") == "Turn,Size" and table.find(buttons, "Move") and table.find(buttons, "Remove"),
		tostring(title) .. " | " .. table.concat(steps, ",") .. " | " .. table.concat(buttons, ",")
	)
	task.wait(0.4)
	click(c1:GetPivot().Position)
	check("a second click on it leaves it picked and opens nothing", App.pickedCopy() == c1 and (App.ui.popup == nil or App.ui.popup.Parent == nil))
	App.openQuick()
	task.wait(0.1)
	local texts = {}
	for _, d in App.ui.popup and App.ui.popup:GetDescendants() or {} do
		if d:IsA("TextButton") and d.Text ~= "" then
			table.insert(texts, d.Text)
		end
	end
	texts = table.concat(texts, " | ")
	check(
		"the quick menu has its actions (here, where the viewport can't draw it, as a menu in the panel)",
		string.find(texts, "Turn 15°", 1, true) ~= nil
			and string.find(texts, "Move it", 1, true) ~= nil
			and string.find(texts, "Remove", 1, true) ~= nil,
		texts
	)
	App.closePopup()
	items[2].inc() -- the header's Size +
	settle(allThere(1))
	local c2 = App.pickedCopy()
	check(
		"the header's Size + makes it a stamp, 10% bigger, on its spot",
		c2 ~= nil and c2 ~= c1 and c2:GetAttribute("SS_Stamp") == true and math.abs(c2:GetExtentsSize().Y / h0 - 1.1) < 0.02,
		c2 and c2:GetExtentsSize().Y / h0
	)
	check("every other copy is where it was", #copies() == n0 and spots({ c2 }) == others, #copies())
	App.copyEdit.size(1)
	local second = App.copyEdit.turn(1)
	settle(allThere(1))
	task.wait(0.4)
	local c3 = App.pickedCopy()
	check(
		"two quick changes both take",
		second == true and c3 ~= nil and math.abs(c3:GetExtentsSize().Y / h0 - 1.21) < 0.04,
		c3 and c3:GetExtentsSize().Y / h0
	)
	check("a move off the painted ground is refused", App.copyEdit.move(O + Vector3.new(70, 0, 70)) == false)
	check("a move onto it starts", App.copyEdit.move(Vector3.new(x + 4, 0, z)) == true)
	settle(allThere(1))
	local c4 = App.pickedCopy()
	check(
		"it stands at the new spot, the others untouched",
		c4 ~= nil and math.abs(c4:GetAttribute("SS_X") - (x + 4)) < 0.02 and spots({ c4 }) == others
	)
	check(
		"the stamp's grow key sizes it, Delete removes it",
		App.selectKey("grow") == true and settle(allThere(1)) and App.selectKey("delete") == true
	)
	task.wait(0.3)
	check(
		"one copy fewer, no pin left, the others untouched",
		#copies() == n0 - 1 and App.area.layers[1].pins == nil and spots() == others,
		#copies()
	)
	check("with nothing picked the keys are not taken", App.selectKey("turn") == false)

	-- ── several copies ───────────────────────────────────────────────────────────
	list = copies()
	local a1, a2, a3 = list[1], list[2], list[3]
	click(a1:GetPivot().Position)
	click(a2:GetPivot().Position, true)
	click(a3:GetPivot().Position, true)
	check("Shift + click adds copies", #App.pickedCopies() == 3, #App.pickedCopies())
	click(a2:GetPivot().Position, true)
	check("Shift + click on a picked one takes it back out", #App.pickedCopies() == 2 and not table.find(App.pickedCopies(), a2))
	local title2, items2 = App.copyHeader()
	check("the header says how many", title2 == "2 copies" and items2[#items2].button == "Remove 2" and items2[#items2].danger == true, title2)
	local rest = spots({ a1, a3 })
	check("turning them starts", App.copyEdit.turn(1) == true)
	settle(allThere(2))
	local both = App.pickedCopies()
	local stamps = 0
	for _, c in both do
		stamps += c:GetAttribute("SS_Stamp") and 1 or 0
	end
	check(
		"both are stamps now, both still picked, the rest untouched",
		#both == 2 and stamps == 2 and #App.area.layers[1].pins == 2 and spots(both) == rest,
		stamps
	)
	check("they can both go back to their rules", App.copyEdit.back() == true)
	settle(allThere(2))
	task.wait(0.4)
	check(
		"and the rules' copies are back, the layout as it was",
		App.area.layers[1].pins == nil and #copies() == n0 - 1 and spots() == others,
		#copies()
	)
	check("removing takes both", App.copyEdit.remove() == true and #App.pickedCopies() == 0)
	task.wait(0.3)
	check("two fewer", #copies() == n0 - 3, #copies())
	-- a box over everything: the camera backed away from the zone along the way it looks (Studio keeps its own
	-- turn, so it's moved, not turned), the box the whole screen
	-- (no wait after moving it: someone working in Studio meanwhile moves the camera themselves)
	cam.CFrame = CFrame.new(O - cam.CFrame.LookVector * 250) * cam.CFrame.Rotation
	local n = App.boxPick(Vector2.new(-1e5, -1e5), Vector2.new(1e5, 1e5), false)
	check(
		"a box over the zone picks every copy in it",
		n == #copies() and #App.pickedCopies() == n,
		string.format(
			"%d of %d, camera %s, picked from %s",
			n,
			#copies(),
			tostring(cam.CFrame.Position),
			tostring(App.selected and App.selected.folder)
		)
	)
	aim(O + Vector3.new(70, 0, 70))
	App.selectDown()
	App.selectUp()
	check("a click on nothing lets them go", #App.pickedCopies() == 0)
	local t3 = App.copyHeader()
	check("with none picked the header is Select's own", t3 == "Select")
	-- the quick menu: where the viewport can't show it, the search menu opens
	local palettes = 0
	local realPalette = App.openPalette
	App.openPalette = function()
		palettes += 1
	end
	App.openQuick()
	App.openPalette = realPalette
	check("with nothing picked the quick menu is the tools': here, the search menu", palettes == 1)
	App.setMode("Off")

	-- ── the stamp's header comes from its own module ─────────────────────────────
	Selection:Set({ rock })
	App.startStamp()
	task.wait(0.1)
	local st, sitems, skey = App.modeHandlers.Stamp.header()
	sitems[1].inc()
	local _, _, skey2 = App.modeHandlers.Stamp.header()
	check(
		"the stamp's header: its model, Turn and Size, and a key that follows the turn",
		string.find(st, "Stamp · ", 1, true) == 1 and sitems[1].step == "Turn" and skey ~= skey2,
		st
	)
	App.setMode("Off")

	-- ── the outliner's eye and padlock ───────────────────────────────────────────
	App.select(App.thingOf(zone))
	local function shown()
		local seen, all = 0, 0
		for _, d in zone:GetDescendants() do
			if d:IsA("BasePart") then
				all += 1
				seen += d.LocalTransparencyModifier == 0 and 1 or 0
			end
		end
		return seen, all
	end
	App.setHidden(zone, true)
	local seen, all = shown()
	check("hiding a zone hides every part it placed", all > 0 and seen == 0 and App.isHidden(zone), seen .. " of " .. all)
	App.applyNow(nil, nil)
	settle()
	task.wait(0.3)
	seen, all = shown()
	check("copies placed while it's hidden are hidden too", all > 0 and seen == 0, seen .. " of " .. all)
	App.setMode("Select")
	aim(copies()[1]:GetPivot().Position)
	local _, _, hit = App.pickAt()
	check("a hidden zone's copies can't be clicked", hit == nil)
	App.setMode("Off")
	App.setHidden(zone, false)
	seen, all = shown()
	check("showing it again shows them all", seen == all and not App.isHidden(zone), seen .. " of " .. all)
	local spec = App.kindSpec("Zone")
	check("a zone's row has an eye and a padlock", spec.hide == true and spec.lock ~= nil and spec.lock.get(App.selected) == false)
	spec.lock.toggle(App.selected)
	task.wait(0.2)
	check("the padlock locks the zone", zone:GetAttribute("SS_Locked") == true and App.area.locked == true)
	spec.lock.toggle(App.selected)
	task.wait(0.2)
	check("and unlocks it", zone:GetAttribute("SS_Locked") ~= true)

	-- ── the outliner's filter (with many things) ─────────────────────────────────
	local have = #E.listAreas()
	for _ = 1, math.max(0, 8 - have) do
		App.newArea({ kind = "Clear", keepMode = true })
		table.insert(made, App.area.folder)
	end
	App.select(App.thingOf(zone))
	task.wait(0.4)
	local tb = App.ui.outlinerFilter
	check("with many things the outliner has a filter box", tb ~= nil)
	if tb then
		local function rowsShown()
			local nRows = 0
			for _, d in App.ui.outliner:GetDescendants() do
				if d:IsA("TextButton") and d.AbsoluteSize.Y == 28 and d.Visible and d.Parent.Visible then
					nRows += 1
				end
			end
			return nRows
		end
		local headY, firstRowY = nil, math.huge
		for _, d in App.ui.outliner:GetDescendants() do
			if d:IsA("TextLabel") and string.find(d.Text, "^Outliner") then
				headY = d.AbsolutePosition.Y
			elseif d:IsA("TextButton") and d.AbsoluteSize.Y == 28 then
				firstRowY = math.min(firstRowY, d.AbsolutePosition.Y)
			end
		end
		check(
			"it sits between the outliner's head and its rows",
			headY ~= nil and tb.AbsolutePosition.Y > headY and tb.AbsolutePosition.Y < firstRowY,
			string.format("head %s, box %d, first row %s", tostring(headY), tb.AbsolutePosition.Y, tostring(firstRowY))
		)
		local before = rowsShown()
		tb.Text = string.lower(zone.Name)
		task.wait(0.1)
		local after = rowsShown()
		check("typing a name leaves only its row", before >= 8 and after >= 1 and after < before, before .. " -> " .. after)
		tb.Text = ""
		task.wait(0.1)
		check("clearing it brings them all back", rowsShown() == before)
	end

	-- ── the compact panel ────────────────────────────────────────────────────────
	App.G.compact = true
	App.rebuildAll()
	task.wait(0.3)
	check("compact: no search box over the outliner", App.ui.search == nil and App.ui.outliner ~= nil)
	App.G.compact = false
	App.rebuildAll()
	task.wait(0.3)
	check("and it's back with compact off", App.ui.search ~= nil)

	-- ── adjusting the last edit helper ───────────────────────────────────────────
	local blocks = {}
	for i = 1, 3 do
		local b = Instance.new("Part")
		b.Name = "SS_ChecksBlock" .. i
		b.Anchored = true
		b.Size = Vector3.new(2, 2 + i, 2)
		b.Position = O + Vector3.new(-60 + i * 7, 20 + i, 60 + i * 3)
		b.Parent = workspace
		table.insert(made, b)
		blocks[i] = b
	end
	local was = {}
	for i, b in blocks do
		was[i] = b.Position
	end
	local function edges(axis, side)
		local t = {}
		for _, b in blocks do
			table.insert(t, string.format("%.2f", b.Position[axis] + (side == "Max" and 1 or -1) * b.Size[axis] / 2))
		end
		return t
	end
	local function same(t)
		return t[1] == t[2] and t[2] == t[3]
	end
	Selection:Set(blocks)
	check("with nothing done yet there's nothing to adjust", App.lastEdit() == nil)
	App.alignSelection("X", "Min")
	local last = App.lastEdit()
	check("aligned on X's lowest, and kept as the last helper", same(edges("X", "Min")) and last ~= nil and last.kind == "align" and #last.list == 3)
	local lowest = edges("X", "Min")[1]
	Selection:Set({}) -- (adjusting works on what the helper was done to, not on what's selected now)
	check(
		"adjusting it to the highest moves them all to the other end",
		App.adjustLastEdit({ where = "Max" }) == true and same(edges("X", "Max")) and edges("X", "Min")[1] ~= lowest,
		table.concat(edges("X", "Max"), " ")
	)
	App.adjustLastEdit({ axis = "Z" })
	local backX = true
	for i, b in blocks do
		backX = backX and math.abs(b.Position.X - was[i].X) < 0.01
	end
	check("adjusting the axis puts X back as it stood and lines up Z", backX and same(edges("Z", "Max")))
	Selection:Set(blocks)
	App.G.editTurn, App.G.editSize = 90, 0.5
	App.randomizeSelection()
	local moved = false
	for i, b in blocks do
		moved = moved or math.abs(b.Size.Y - (2 + i)) > 0.01
	end
	App.adjustLastEdit({ turn = 0, size = 0 })
	local sizesBack = true
	for i, b in blocks do
		sizesBack = sizesBack and math.abs(b.Size.Y - (2 + i)) < 0.01
	end
	check("randomize, then adjusted down to nothing: every size as it was before it", moved and sizesBack and App.lastEdit().kind == "random")
	blocks[1]:Destroy()
	check("once one of them is gone there's nothing to adjust", App.lastEdit() == nil)

	-- ── the layout: the tab column, the line over the page, the grid of objects ───
	-- the way in ("Start") is a tab of its own, only while the place has nothing of Smart Scatter's; with nothing
	-- selected the other tabs show their own pages
	local start = App.tabById("start")
	local nAreas = #E.listAreas()
	check(
		"the Start tab is there only with nothing made and nothing selected",
		start ~= nil and start.when(nil) == (nAreas == 0) and start.when(App.thingOf(zone)) == false,
		nAreas .. " areas"
	)
	App.select(nil)
	task.wait(0.3)
	local openNow, tabsNow = App.currentTab()
	local ids = {}
	for _, t in tabsNow do
		table.insert(ids, t.id)
	end
	check(
		"with nothing selected the open tab is the map's own (World), and Edit is its own page too",
		openNow.id == "world" and table.find(ids, "edit") ~= nil and not table.find(ids, "start"),
		table.concat(ids, ",")
	)
	App.openTab("edit")
	task.wait(0.3)
	local welcome = false
	for _, d in App.scroll:GetDescendants() do
		if d:IsA("TextLabel") and string.find(d.Text, "Fill your map by rules", 1, true) then
			welcome = true
		end
	end
	check("the Edit tab shows its helpers, not the introduction", App.currentTab().id == "edit" and not welcome)
	local more = {}
	for i, n in { "SS_ChecksPine", "SS_ChecksBush", "SS_ChecksCrate", "SS_ChecksAVeryLongModelNameIndeed" } do
		local m = Instance.new("Model")
		m.Name = n
		local mp = Instance.new("Part")
		mp.Anchored = true
		mp.Size = Vector3.new(2 + i, 3 + i, 2)
		mp.Color = Color3.fromHSV(i / 5, 0.5, 0.8)
		mp.Parent = m
		m.PrimaryPart = mp
		m.Parent = SS
		table.insert(made, m)
		more[i] = m
	end
	App.select(App.thingOf(zone))
	Selection:Set(more)
	App.addSelected()
	App.selectObject(nil)
	App.openTab("objects")
	task.wait(0.4)
	local column = App.ui.tabRow
	local nTabs = 0
	for _ in App.ui.tabs do
		nTabs += 1
	end
	check(
		"the tabs are a column beside the page, the page starting where it ends",
		column ~= nil
			and column.AbsoluteSize.X == App.TAB_COL
			and nTabs >= 3
			and App.ui.tabs.objects ~= nil
			and math.abs(App.scroll.AbsolutePosition.X - (column.AbsolutePosition.X + App.TAB_COL)) < 1
			and math.abs(column.AbsolutePosition.Y - App.scroll.AbsolutePosition.Y) < 1,
		column and (column.AbsoluteSize.X .. " wide, " .. nTabs .. " tabs")
	)
	local function crumbText()
		local t = {}
		for _, d in App.ui.crumb:GetDescendants() do
			if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" then
				table.insert(t, d.Text)
			end
		end
		return table.concat(t, " | ")
	end
	local crumb = crumbText()
	check(
		"the line over the page names the zone and the open tab",
		string.find(crumb, zone.Name, 1, true) ~= nil and string.find(crumb, "Objects", 1, true) ~= nil,
		crumb
	)
	App.selectObject(App.area.layers[2])
	task.wait(0.4)
	crumb = crumbText()
	check(
		"with an object open it names both, and the tab is the object's",
		string.find(crumb, zone.Name, 1, true) ~= nil
			and string.find(crumb, App.area.layers[2].inst.Name, 1, true) ~= nil
			and string.find(crumb, "Object", 1, true) ~= nil,
		crumb
	)
	App.selectObject(nil)
	App.openTab("objects")
	App.G.objGrid = true
	App.rebuildAll()
	task.wait(0.4)
	local cells, pictures = 0, 0
	for _, d in App.scroll:GetDescendants() do
		if d:IsA("TextButton") and d.Parent:FindFirstChildOfClass("UIGridLayout") and d.AbsoluteSize.Y == 102 then
			cells += 1
			pictures += d:FindFirstChildOfClass("ViewportFrame") and 1 or 0
		end
	end
	check(
		"the grid view has a cell and a picture for every object",
		cells == #App.area.layers and pictures == cells and cells == 5,
		cells .. " cells, " .. pictures .. " pictures"
	)
	if _G.SS_ChecksDump then -- (for a look at it: python tools/preview/render.py <that name>)
		_G.SS_DumpName = _G.SS_ChecksDump
		table.insert(report, "      dump: " .. tostring(assert(loadstring(HS:GetAsync(URL .. "dump.lua", true)))()))
	end
	App.G.objGrid = false
	App.refreshObjects()
	task.wait(0.2)
	local rowsBack = 0
	for _, d in App.scroll:GetDescendants() do
		if d:IsA("TextButton") and d.AbsoluteSize.Y == 60 then
			rowsBack += 1
		end
	end
	check("and the list view has its rows again", rowsBack == #App.area.layers, rowsBack)
end)
check("no errors", okAll, err)

if _G.SS_Preview then
	pcall(_G.SS_Preview.cleanup)
end
for _, inst in made do
	pcall(function()
		inst:Destroy()
	end)
end
Selection:Set(keepSel)
cam.CFrame, cam.Focus = camWas, focusWas
return string.format("panel checks: %d failed, %d checks\n", failed, #report) .. table.concat(report, "\n")
