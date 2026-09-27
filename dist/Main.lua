-- GENERATED from src/App by tools/tree.py (a flattened copy for older loaders): edit the modules, not this.
local MODULES = {}

-- #module Core/State
MODULES["Core/State"] = (function()
--[[
	Smart Scatter — State: services, undo helpers, settings, shared state, palette and fonts.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local ctx = App.ctx

	local RunService = game:GetService("RunService")
	local ChangeHistoryService = game:GetService("ChangeHistoryService")
	local Selection = game:GetService("Selection")
	local TweenService = game:GetService("TweenService")
	local FAST = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local MED = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	local function tween(o, info, props)
		local t = TweenService:Create(o, info, props)
		t:Play()
		return t
	end

	local function beginRec(name)
		local ok, id = pcall(ChangeHistoryService.TryBeginRecording, ChangeHistoryService, name)
		if ok and id then
			return { id = id, name = name }
		end
		return { name = name } -- fallback: the waypoint set when the step ends groups the changes since the last one
	end
	local function endRec(h, cancel)
		if not h then
			return
		end
		if h.id then
			pcall(
				ChangeHistoryService.FinishRecording,
				ChangeHistoryService,
				h.id,
				cancel and Enum.FinishRecordingOperation.Cancel or Enum.FinishRecordingOperation.Commit
			)
		elseif not cancel then
			pcall(ChangeHistoryService.SetWaypoint, ChangeHistoryService, h.name)
		end
	end

	local plugin = ctx.plugin
	local Engine = ctx.Engine
	local conns = {} -- long-lived connections, dropped on hot-reload
	local function track(c)
		table.insert(conns, c)
		return c
	end
	ctx.abort = function()
		for _, c in conns do
			c:Disconnect()
		end
		if App.root then
			App.root:Destroy()
		end
		pcall(function()
			plugin:Deactivate()
		end)
	end

	local KEY = "SmartScatter_v3"
	local G = {
		radius = 24,
		density = 1,
		textScale = 1.2, -- text size: 1 small, 1.2 normal, 1.4 large (App.TEXT_SIZES)
		live = true,
		overlay = true,
		groups = {},
		walk = true,
		shadows = true,
		query = true,
		chunks = false,
		accent = "Sage", -- the accent theme (ACCENTS below)
		keys = {}, -- shortcuts changed from their defaults: [action id] = KeyCode name (KEYMAP below)
		ghost = false, -- preview as boxes: one see-through box per copy, for quick tuning of big areas
		tool = "Brush",
		shape = "Circle",
		fillReach = 120,
		paintOn = {},
		page = "", -- the open tab: Scatter · Brush · Map · Settings ("" opens the area's home tab)
	}
	do
		local saved = plugin:GetSetting(KEY)
		if type(saved) == "table" then
			for k, v in saved do
				if G[k] ~= nil and type(v) == type(G[k]) then
					G[k] = v
				end
			end
		end
	end
	G.page = "" -- every session opens on the area's home tab
	App.LOGO = { mark = "rbxassetid://117898410132206", card = "rbxassetid://125838588548368" }
	local function saveG()
		plugin:SetSetting(KEY, G)
	end
	App.paintFilterOn = false -- is any "Paint only on" surface picked (cached; checked per cell while painting)
	local function refreshFilter()
		App.paintFilterOn = false
		for _, on in G.paintOn do
			if on then
				App.paintFilterOn = true
				break
			end
		end
	end
	refreshFilter()

	local KEYMAP = {
		{ id = "tool1", group = "Painting", label = "Brush", key = "One" },
		{ id = "tool2", group = "Painting", label = "Lasso", key = "Two" },
		{ id = "tool3", group = "Painting", label = "Box", key = "Three" },
		{ id = "tool4", group = "Painting", label = "Polygon", key = "Four" },
		{ id = "tool5", group = "Painting", label = "Fill", key = "Five" },
		{ id = "erase", group = "Painting", label = "Erase on / off", key = "E" },
		{ id = "size", group = "Painting", label = "Resize brush with the mouse", key = "F" },
		{ id = "shrink", group = "Painting", label = "Smaller brush", key = "LeftBracket" },
		{ id = "grow", group = "Painting", label = "Bigger brush", key = "RightBracket" },
		{ id = "close", group = "Shapes and paths", label = "Close polygon / finish", key = "Return" },
		{ id = "back", group = "Shapes and paths", label = "Remove last point", key = "Backspace" },
		{ id = "cancel", group = "Shapes and paths", label = "Stop", key = "Escape" },
		{ id = "corner", group = "Shapes and paths", label = "Sharp corner", key = "C" },
		{ id = "delete", group = "Shapes and paths", label = "Delete point", key = "X" },
		{ id = "shuffle", group = "Anywhere while working", label = "Shuffle the layout", key = "R" },
		{ id = "overlay", group = "Anywhere while working", label = "Hide / show the overlay", key = "H" },
	}
	local KEY_TEXT = {
		One = "1",
		Two = "2",
		Three = "3",
		Four = "4",
		Five = "5",
		Six = "6",
		Seven = "7",
		Eight = "8",
		Nine = "9",
		Zero = "0",
		LeftBracket = "[",
		RightBracket = "]",
		Return = "Enter",
		Backspace = "Backspace",
		Escape = "Esc",
		Space = "Space",
		Minus = "-",
		Equals = "=",
		Semicolon = ";",
		Quote = "'",
		Comma = ",",
		Period = ".",
		Slash = "/",
		BackSlash = "\\",
		Tab = "Tab",
		Delete = "Del",
		Insert = "Ins",
		Home = "Home",
		End = "End",
		PageUp = "PgUp",
		PageDown = "PgDn",
	}
	local UNBINDABLE = {
		LeftShift = true,
		RightShift = true,
		LeftControl = true,
		RightControl = true,
		LeftAlt = true,
		RightAlt = true,
		LeftSuper = true,
		RightSuper = true,
		Unknown = true,
	}
	local function keyOf(id) -- the KeyCode name bound to an action
		if type(G.keys[id]) == "string" and not UNBINDABLE[G.keys[id]] then
			return G.keys[id]
		end
		for _, a in KEYMAP do
			if a.id == id then
				return a.key
			end
		end
		return nil
	end
	local function keyText(id)
		local k = keyOf(id)
		return k and (KEY_TEXT[k] or k) or "?"
	end
	local function bindKey(id, key)
		local old, moved = keyOf(id), nil
		for _, a in KEYMAP do
			if a.id ~= id and keyOf(a.id) == key then
				moved = a
				G.keys[a.id] = old
			end
		end
		G.keys[id] = key
		saveG()
		return moved
	end
	local function resetKeys()
		table.clear(G.keys)
		saveG()
	end

	App.analysisDirty = true
	App.lastCounts, App.lastTotal, App.lastParts = {}, 0, 0
	App.mode = "Off" -- "Paint" | "Erase" (area) · "More" | "Less" | "Clear" | "Place" (one layer) · "Off"
	local LAYER_MODES = { More = "paint", Less = "paint", Clear = "paint", Place = "pins" }

	local function num(n)
		local str = tostring(math.floor(n + 0.5))
		return (str:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
	end

	App.ui = {}

	local P = {} -- filled in place by makePalette, so every module can keep this one table
	local VIEW = {}
	local function hex(h)
		return Color3.fromHex(h)
	end
	local ACCENTS = {
		{ name = "Sage", dark = "8FBA97", light = "4C8558", glow = "C9E2CD" },
		{ name = "Aqua", dark = "7CC7C4", light = "2E7D7A", glow = "C4EAE8" },
		{ name = "Amber", dark = "E3B26A", light = "98661C", glow = "F3DDB6" },
		{ name = "Violet", dark = "A99BE8", light = "6453C0", glow = "DAD3F7" },
		{ name = "Rose", dark = "E59AAA", light = "B0485F", glow = "F5D2DA" },
	}
	local function accentOf(name)
		for _, a in ACCENTS do
			if a.name == name then
				return a
			end
		end
		return ACCENTS[1]
	end
	local function makePalette()
		local pal
		if settings().Studio.Theme.Name ~= "Light" then
			pal = {
				bg = hex("1A1917"), -- the panel
				card = hex("262420"), -- step card, rows that open something
				raised = hex("32302B"), -- buttons, pickers, value pills
				header = hex("201F1C"), -- footer strip
				field = hex("1F1E1B"), -- inputs
				hover = hex("3B3934"),
				line = hex("33312D"), -- borders and hairlines
				text = hex("F2EFEA"),
				dim = hex("A6A199"),
				faint = hex("7C766C"),
				knob = hex("FFFFFF"),
				track = hex("45423D"), -- switch / slider track when off
				danger = hex("D08A78"),
				tip = hex("2A2825"),
			}
		else
			pal = {
				bg = hex("F4F2EE"),
				card = hex("FFFFFF"),
				raised = hex("ECE9E3"),
				header = hex("EFECE7"),
				field = hex("FFFFFF"),
				hover = hex("E3DFD8"),
				line = hex("DDD8CF"),
				text = hex("23211D"),
				dim = hex("5E5950"),
				faint = hex("8A8479"),
				knob = hex("FFFFFF"),
				track = hex("CFCAC1"),
				danger = hex("B5533F"),
				tip = hex("FFFFFF"),
			}
		end
		local a, dark = accentOf(G.accent), settings().Studio.Theme.Name ~= "Light"
		local acc = hex(dark and a.dark or a.light)
		pal.accent = acc
		pal.onAccent = dark and acc:Lerp(Color3.new(0, 0, 0), 0.82) or Color3.new(1, 1, 1)
		pal.accentSoft = acc:Lerp(pal.card, dark and 0.8 or 0.86)
		pal.accentLine = acc:Lerp(pal.card, dark and 0.55 or 0.5)
		pal.glow = hex(a.glow)
		for k, v in pal do
			P[k] = v
		end
		local viewAccent = hex(a.dark) -- the viewport always gets the bright version
		for k, v in
			{
				accent = viewAccent, -- painted ground, the brush, curves
				edge = hex(a.glow), -- the painted area's outline
				muted = hex("A6A199"), -- roads and paths inside the area (only some objects go there)
				blocked = hex("D08A78"), -- roofs and water: nothing is placed there; keep-clear zones
				ink = hex("1A1917"), -- outlines of handles
				paper = hex("F2EFEA"), -- handle fill
				corner = hex("E3B26A"), -- sharp path points
				less = hex("3B3934"), -- painted "less" of an object
			}
		do
			VIEW[k] = v
		end
	end
	makePalette()

	local SANS, SANS_M, SANS_B = Enum.Font.BuilderSans, Enum.Font.BuilderSansMedium, Enum.Font.BuilderSansBold

	App.RunService = RunService
	App.ChangeHistoryService = ChangeHistoryService
	App.Selection = Selection
	App.FAST = FAST
	App.MED = MED
	App.tween = tween
	App.beginRec = beginRec
	App.endRec = endRec
	App.plugin = plugin
	App.Engine = Engine
	App.conns = conns
	App.track = track
	App.G = G
	App.saveG = saveG
	App.refreshFilter = refreshFilter
	App.LAYER_MODES = LAYER_MODES
	App.num = num
	App.P = P
	App.makePalette = makePalette
	App.KEYMAP = KEYMAP
	App.UNBINDABLE = UNBINDABLE
	App.keyOf = keyOf
	App.keyText = keyText
	App.bindKey = bindKey
	App.resetKeys = resetKeys
	App.VIEW = VIEW
	App.ACCENTS = ACCENTS
	App.SANS = SANS
	App.SANS_M = SANS_M
	App.SANS_B = SANS_B
end
end)()
-- #module Core/Kit
MODULES["Core/Kit"] = (function()
--[[
	Smart Scatter — Kit: UI kit: layout helpers, labels, links, sliders, switches, segmented controls, chips, icons.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local RunService, FAST, tween, P, SANS = App.RunService, App.FAST, App.tween, App.P, App.SANS
	local SANS_M, SANS_B = App.SANS_M, App.SANS_B
	local TweenService = game:GetService("TweenService")

	local seqN = 0
	local function seq()
		seqN += 1
		return seqN
	end

	local TEXT_SIZES = { [1] = "Small", [1.2] = "Normal", [1.4] = "Large" }
	local function textSize(n)
		return math.round(n * (App.G.textScale or 1.2))
	end
	local function new(cls, props, kids)
		local o = Instance.new(cls)
		if o:IsA("GuiObject") then
			o.LayoutOrder = seq()
			o.BorderSizePixel = 0
		end
		local parent
		for k, v in props or {} do
			if k == "Parent" then
				parent = v
			elseif k == "TextSize" then
				o.TextSize = textSize(v)
			else
				o[k] = v
			end
		end
		for _, c in kids or {} do
			c.Parent = o
		end
		if parent then
			o.Parent = parent
		end
		return o
	end
	local function corner(r)
		return new("UICorner", { CornerRadius = UDim.new(0, r or 6) })
	end
	local function stroke(c)
		return new("UIStroke", { Color = c, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
	end
	local function pad(l, r, t, b)
		return new("UIPadding", {
			PaddingLeft = UDim.new(0, l),
			PaddingRight = UDim.new(0, r or l),
			PaddingTop = UDim.new(0, t or l),
			PaddingBottom = UDim.new(0, b or t or l),
		})
	end
	local function vlist(gap)
		return new("UIListLayout", { Padding = UDim.new(0, gap or 0), SortOrder = Enum.SortOrder.LayoutOrder })
	end
	local function hlist(gap)
		return new("UIListLayout", {
			Padding = UDim.new(0, gap or 0),
			SortOrder = Enum.SortOrder.LayoutOrder,
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		})
	end
	local function box(props, kids)
		props.BackgroundTransparency = props.BackgroundTransparency or 1
		return new("Frame", props, kids)
	end
	local function col(props, kids) -- auto-height column
		props.Size = props.Size or UDim2.new(1, 0, 0, 0)
		props.AutomaticSize = Enum.AutomaticSize.Y
		return box(props, kids)
	end
	local function label(t, size, color, font, props)
		local o = new("TextLabel", {
			BackgroundTransparency = 1,
			Text = t,
			TextSize = size or 13,
			TextColor3 = color or P.text,
			Font = font or SANS,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
			Size = UDim2.new(1, 0, 0, textSize(size or 13) + 8),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		for k, v in props or {} do
			o[k] = v
		end
		return o
	end
	local function para(t, props)
		local o = label(t, 12, P.faint, SANS, props)
		o.TextWrapped = true
		o.TextTruncate = Enum.TextTruncate.None
		o.AutomaticSize = Enum.AutomaticSize.Y
		o.Size = UDim2.new(1, 0, 0, 0)
		o.LineHeight = 1.2
		return o
	end
	local grain -- Content of a 4×4 tile with one white dot (false: not available here)
	local function grainContent()
		if grain == nil then
			local ok, c = pcall(function()
				local img = game:GetService("AssetService"):CreateEditableImage({ Size = Vector2.new(4, 4) })
				local buf = buffer.create(4 * 4 * 4) -- RGBA, all clear
				local i = (1 * 4 + 1) * 4 -- the dot at (1, 1)
				buffer.writeu8(buf, i, 255)
				buffer.writeu8(buf, i + 1, 255)
				buffer.writeu8(buf, i + 2, 255)
				buffer.writeu8(buf, i + 3, 255)
				img:WritePixelsBuffer(Vector2.zero, Vector2.new(4, 4), buf)
				return Content.fromObject(img)
			end)
			grain = ok and c or false
		end
		return grain or nil
	end
	local function halftone(parent, strength, spacing, z)
		local c = grainContent()
		if not c then
			return nil
		end
		local l = new("ImageLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ScaleType = Enum.ScaleType.Tile,
			TileSize = UDim2.fromOffset(spacing or 4, spacing or 4),
			ResampleMode = Enum.ResamplerMode.Pixelated,
			ImageTransparency = 1 - (strength or 0.04),
			ImageColor3 = settings().Studio.Theme.Name == "Light" and Color3.new(0, 0, 0) or Color3.new(1, 1, 1),
			Active = false,
			ZIndex = z or 1,
			Parent = parent,
		})
		if not pcall(function()
			l.ImageContent = c
		end) then
			l:Destroy()
			return nil
		end
		return l
	end
	local function sheen(parent, strength, height, z)
		local f = new("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0,
			Size = UDim2.new(1, 0, 0, height or 120),
			Active = false,
			ZIndex = z or 1,
			Parent = parent,
		})
		new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new(1 - (strength or 0.04), 1),
			Parent = f,
		})
		return f
	end
	local function fadeLine(parent, edge, strength)
		local f = new("Frame", {
			BackgroundColor3 = P.text,
			BackgroundTransparency = 0,
			Size = UDim2.new(1, 0, 0, 1),
			Parent = parent,
		})
		local a = 1 - (strength or 0.16)
		new("UIGradient", {
			Transparency = edge == "left" and NumberSequence.new({
				NumberSequenceKeypoint.new(0, a),
				NumberSequenceKeypoint.new(0.7, 1),
				NumberSequenceKeypoint.new(1, 1),
			}) or NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.4, a),
				NumberSequenceKeypoint.new(0.6, a),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = f,
		})
		return f
	end
	local function shade(obj, amount)
		local d = 1 - (amount or 0.08)
		return new("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(d, d, d)),
			Parent = obj,
		})
	end
	local function topLight(obj, strength, inset)
		local f = fadeLine(obj, nil, strength or 0.07)
		f.Position = UDim2.fromOffset(inset or 10, 0)
		f.Size = UDim2.new(1, -(inset or 10) * 2, 0, 1)
		f.ZIndex = obj.ZIndex + 1
		return f
	end

	local function ring(obj, radius, out, thickness, color, dy)
		local p = obj:FindFirstChildOfClass("UIPadding")
		local l, r = p and p.PaddingLeft.Offset or 0, p and p.PaddingRight.Offset or 0
		local t, bt = p and p.PaddingTop.Offset or 0, p and p.PaddingBottom.Offset or 0
		local f = new("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(-out - l, -out - t + (dy or 0)),
			Size = UDim2.new(1, out * 2 + l + r, 1, out * 2 + t + bt),
			Active = false,
			ZIndex = obj.ZIndex,
			Parent = obj,
		}, { corner(radius + out) })
		local st = stroke(color)
		st.Thickness = thickness
		st.Transparency = 1
		st.Parent = f
		return st
	end
	local GLOW = { { 1, 1.5, 0.62 }, { 3, 4, 0.93 } } -- { out, thickness, transparency when fully lit }
	local function glow(obj, radius, strength, color)
		strength = strength or 1
		local rings, lit, pulses = {}, false, {}
		for i, g in GLOW do
			rings[i] = { st = ring(obj, radius or 8, g[1], g[2], color or P.accent), rest = 1 - (1 - g[3]) * strength }
		end
		local c = {}
		function c:set(on, instant)
			lit = on
			for _, r in rings do
				local t = on and r.rest or 1
				if instant then
					r.st.Transparency = t
				else
					tween(r.st, FAST, { Transparency = t })
				end
			end
		end
		function c:pulse(on)
			for _, p in pulses do
				p:Cancel()
			end
			table.clear(pulses)
			if not on then
				self:set(lit, false)
				return
			end
			for _, r in rings do
				r.st.Transparency = r.rest
				local p = TweenService:Create(
					r.st,
					TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
					{ Transparency = (r.rest + 1) / 2 }
				)
				p:Play()
				table.insert(pulses, p)
			end
		end
		return c
	end
	local function shadow(obj, radius)
		local st = ring(obj, radius or 12, 1, 3, Color3.new(0, 0, 0), 2)
		st.Transparency = settings().Studio.Theme.Name == "Light" and 0.93 or 0.75
		return st
	end
	local function pressable(b, amount)
		local sc = new("UIScale", { Parent = b })
		b.MouseButton1Down:Connect(function()
			tween(sc, FAST, { Scale = amount or 0.97 })
		end)
		for _, ev in { b.MouseButton1Up, b.MouseLeave } do
			ev:Connect(function()
				tween(sc, App.MED, { Scale = 1 })
			end)
		end
		return sc
	end
	local function sweep(obj, strength)
		local f = new("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0,
			Size = UDim2.fromScale(1, 1),
			Visible = false,
			Active = false,
			ZIndex = obj.ZIndex + 1,
			Parent = obj,
		}, { corner(8) })
		local a = 1 - (strength or 0.35)
		local g = new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.4, 1),
				NumberSequenceKeypoint.new(0.5, a),
				NumberSequenceKeypoint.new(0.6, 1),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Offset = Vector2.new(-1, 0),
			Parent = f,
		})
		local run
		local c = {}
		function c:play(on)
			if run then
				run:Cancel()
				run = nil
			end
			f.Visible = on
			if on then
				g.Offset = Vector2.new(-1, 0)
				run = TweenService:Create(g, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1), {
					Offset = Vector2.new(1, 0),
				})
				run:Play()
			end
		end
		return c
	end

	local function hoverable(b, rest, over)
		b.MouseEnter:Connect(function()
			if b:GetAttribute("active") ~= true then
				tween(b, FAST, { BackgroundColor3 = over, BackgroundTransparency = 0 })
			end
		end)
		b.MouseLeave:Connect(function()
			if b:GetAttribute("active") ~= true then
				tween(b, FAST, { BackgroundColor3 = rest, BackgroundTransparency = rest == P.bg and 1 or 0 })
			end
		end)
	end

	local function button(t, kind, onClick, props)
		local filled = kind == "accent"
		local flat = kind == "danger" or kind == "ghost"
		local rest = filled and P.accent or P.raised
		local b = new("TextButton", {
			Text = t,
			Font = filled and SANS_B or SANS_B,
			TextSize = 13,
			TextColor3 = filled and P.onAccent or (kind == "danger" and P.danger or kind == "ghost" and P.dim or P.text),
			BackgroundColor3 = rest,
			BackgroundTransparency = flat and 1 or 0,
			AutoButtonColor = false,
			Size = UDim2.fromOffset(0, 30),
			AutomaticSize = Enum.AutomaticSize.X,
		}, { corner(8), pad(kind == "danger" and 4 or 13, kind == "danger" and 4 or 13, 0, 0) })
		if kind ~= "danger" and not filled then
			stroke(P.line).Parent = b
		end
		if not flat then
			shade(b, filled and 0.1 or 0.06)
			topLight(b, filled and 0.3 or 0.06, 6)
		end
		if filled then
			glow(b, 8, 0.55):set(true, true)
		end
		pressable(b)
		b.MouseEnter:Connect(function()
			if filled then
				b.BackgroundColor3 = P.accent:Lerp(Color3.new(1, 1, 1), 0.1)
			elseif kind == "danger" then
				b.TextColor3 = P.danger:Lerp(Color3.new(1, 1, 1), 0.2)
			else
				b.BackgroundTransparency = 0
				b.BackgroundColor3 = P.hover
			end
		end)
		b.MouseLeave:Connect(function()
			b.BackgroundColor3 = rest
			b.BackgroundTransparency = flat and 1 or 0
			if kind == "danger" then
				b.TextColor3 = P.danger
			end
		end)
		if onClick then
			b.MouseButton1Click:Connect(onClick)
		end
		for k, v in props or {} do
			b[k] = v
		end
		return b
	end
	local function buttonRow(parent, gap)
		local row = new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = parent,
		}, {
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Wraps = true,
				Padding = UDim.new(0, gap or 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Center,
			}),
		})
		return row
	end

	local tip, tipText, tipToken = nil, nil, 0
	local function hideTip()
		tipToken += 1
		if tip then
			tip.Visible = false
		end
	end
	local function showTip(obj, text)
		tipToken += 1
		local my = tipToken
		task.delay(0.4, function()
			local root = App.root
			if my ~= tipToken or not root or not obj:IsDescendantOf(root) or App.tour then -- no tips under the tour
				return
			end
			if not tip or not tip:IsDescendantOf(root) then
				tip = new("Frame", {
					BackgroundColor3 = P.tip,
					AutomaticSize = Enum.AutomaticSize.Y,
					ZIndex = 200,
					Visible = false,
					Parent = root,
				}, { corner(6), stroke(P.line), pad(10, 10, 7, 8) })
				tipText = new("TextLabel", {
					BackgroundTransparency = 1,
					Font = SANS,
					TextSize = 12,
					TextColor3 = P.text,
					TextWrapped = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					LineHeight = 1.15,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					ZIndex = 201,
					Parent = tip,
				})
			end
			local rw, rh = root.AbsoluteSize.X, root.AbsoluteSize.Y
			local w = math.min(rw - 24, 270)
			tipText.Text = text
			tip.Size = UDim2.fromOffset(w, 0)
			local ox, oy = obj.AbsolutePosition.X - root.AbsolutePosition.X, obj.AbsolutePosition.Y - root.AbsolutePosition.Y
			local x = math.clamp(ox, 12, math.max(rw - w - 12, 12))
			tip.Position = UDim2.fromOffset(x, oy + obj.AbsoluteSize.Y + 6)
			tip.Visible = true
			task.defer(function() -- flip above the control if it would run off the bottom
				if my == tipToken and tip.Parent and oy + obj.AbsoluteSize.Y + 6 + tip.AbsoluteSize.Y > rh - 8 then
					tip.Position = UDim2.fromOffset(x, math.max(oy - tip.AbsoluteSize.Y - 6, 8))
				end
			end)
		end)
	end
	local function hintOn(obj, hint)
		if not hint then
			return
		end
		obj.MouseEnter:Connect(function()
			showTip(obj, hint)
		end)
		obj.MouseLeave:Connect(hideTip)
		obj.AncestryChanged:Connect(hideTip)
	end

	local function explain(parent, text)
		local last
		for _, c in parent:GetChildren() do
			if c:IsA("GuiObject") and c.Visible and (not last or c.LayoutOrder > last.LayoutOrder) then
				last = c
			end
		end
		if last then
			local prev = last:GetAttribute("hint")
			last:SetAttribute("hint", prev and (prev .. "\n\n" .. text) or text)
			if not prev then
				last.MouseEnter:Connect(function()
					showTip(last, last:GetAttribute("hint"))
				end)
				last.MouseLeave:Connect(hideTip)
				last.AncestryChanged:Connect(hideTip)
			end
		end
	end

	local sliderViews = {}
	local function refreshSliders()
		for f, show in sliderViews do
			if f.Parent then
				show()
			else
				sliderViews[f] = nil
			end
		end
	end
	local function slider(text, min, max, get, set, fmt, step, onLive, onCommit, hint, def)
		local f = box({ Size = UDim2.new(1, 0, 0, 50) })
		hintOn(f, hint and (def ~= nil and (hint .. "\nRight-click to reset.") or hint))
		local name = label(text, 13, P.text, SANS, { Size = UDim2.new(1, -78, 0, 26), Parent = f })
		local value = new("TextBox", {
			BackgroundTransparency = 0,
			BackgroundColor3 = P.raised,
			Text = "",
			Font = SANS_B,
			TextSize = 12,
			TextColor3 = P.dim,
			TextXAlignment = Enum.TextXAlignment.Center,
			ClearTextOnFocus = false,
			Size = UDim2.new(0, 70, 0, 22),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 2),
			Parent = f,
		}, { corner(6), pad(4, 4, 0, 0) })
		local valueStroke = stroke(P.raised)
		valueStroke.Parent = value
		local track = box({
			BackgroundTransparency = 0,
			BackgroundColor3 = P.track,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 7, 0, 38),
			Size = UDim2.new(1, -14, 0, 4),
			Parent = f,
		}, { corner(2) })
		local fill = box({ BackgroundTransparency = 0, BackgroundColor3 = P.accent, Size = UDim2.fromScale(0, 1), Parent = track }, { corner(2) })
		local knob = box({
			BackgroundTransparency = 0,
			BackgroundColor3 = P.knob,
			Size = UDim2.fromOffset(14, 14),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			ZIndex = 3,
			Parent = track,
		}, { corner(7) })
		local knobStroke = stroke(P.track)
		knobStroke.Transparency = 1
		knobStroke.Parent = knob
		local hit = new("TextButton", {
			Text = "",
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 0, 0, 26),
			Size = UDim2.new(1, 0, 0, 24),
			ZIndex = 4,
			Parent = f,
		})

		local pct = string.find(fmt, "%%%%") ~= nil -- "%" formats show 0–1 values as 0–100%
		local function show(v, animate)
			local a = math.clamp((v - min) / (max - min), 0, 1)
			if animate then
				tween(fill, FAST, { Size = UDim2.fromScale(a, 1) })
				tween(knob, FAST, { Position = UDim2.fromScale(a, 0.5) })
			else
				fill.Size = UDim2.fromScale(a, 1)
				knob.Position = UDim2.fromScale(a, 0.5)
			end
			value.Text = string.format(fmt, pct and v * 100 or v)
		end
		local function apply(v, animate)
			v = math.clamp(tonumber(v) or get(), min, max)
			if step then
				v = math.floor(v / step + 0.5) * step
			end
			if v ~= get() then
				set(v)
				show(v, animate)
				if onLive then
					onLive()
				end
			end
		end
		local function fromX(px)
			apply(min + (max - min) * math.clamp((px - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1))
		end
		local hovering, dragging = false, false
		local function look()
			local hot = hovering or dragging
			knobStroke.Transparency = hot and 0 or 1
			knobStroke.Color = P.accent
			knob.Size = UDim2.fromOffset(hot and 16 or 14, hot and 16 or 14)
			name.TextColor3 = P.text
		end
		f.MouseEnter:Connect(function()
			hovering = true
			look()
		end)
		f.MouseLeave:Connect(function()
			hovering = false
			look()
		end)
		local function stop()
			if not dragging then
				return
			end
			dragging = false
			look()
			if onCommit then
				onCommit()
			end
		end
		hit.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
				return
			end
			dragging = true
			look()
			fromX(input.Position.X)
			local conn
			conn = RunService.Heartbeat:Connect(function()
				if not dragging then
					conn:Disconnect()
					return
				end
				fromX(App.widget:GetRelativeMousePosition().X)
			end)
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					stop()
				end
			end)
		end)
		hit.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				stop()
			end
		end)
		if def ~= nil then
			hit.MouseButton2Click:Connect(function()
				if get() == def then
					return
				end
				set(def)
				show(def, true)
				if onLive then
					onLive()
				end
				if onCommit then
					onCommit()
				end
			end)
		end
		value.Focused:Connect(function()
			valueStroke.Color = P.accent
		end)
		value.FocusLost:Connect(function()
			valueStroke.Color = P.raised
			local n = tonumber(string.match(value.Text, "%-?[%d%.]+"))
			if n and pct then
				n /= 100
			end
			apply(n, true)
			show(get(), true)
			if onCommit then
				onCommit()
			end
		end)
		show(get())
		sliderViews[f] = function()
			if f.Parent then
				show(get(), true)
			end
		end
		return f
	end

	local function switch(get, set, onChange)
		local b = new(
			"TextButton",
			{ Text = "", Size = UDim2.fromOffset(38, 22), BackgroundColor3 = P.track, AutoButtonColor = false },
			{ corner(11) }
		)
		local dot = box({ BackgroundTransparency = 0, BackgroundColor3 = P.knob, Size = UDim2.fromOffset(18, 18), Parent = b }, { corner(9) })
		local lit = glow(b, 11, 0.7)
		local function refresh(animate)
			local on = get()
			lit:set(on, not animate)
			local props = { Position = on and UDim2.fromOffset(18, 2) or UDim2.fromOffset(2, 2) }
			if animate then
				tween(dot, FAST, props)
				tween(b, FAST, { BackgroundColor3 = on and P.accent or P.track })
			else
				dot.Position = props.Position
				b.BackgroundColor3 = on and P.accent or P.track
			end
		end
		b.MouseButton1Click:Connect(function()
			set(not get())
			refresh(true)
			if onChange then
				onChange()
			end
		end)
		refresh(false)
		return b, lit
	end

	local function switchRow(text, get, set, onChange, hint)
		local f = box({ Size = UDim2.new(1, 0, 0, 38) })
		hintOn(f, hint)
		label(text, 13, P.text, SANS, { Size = UDim2.new(1, -48, 1, 0), Parent = f })
		local s = switch(get, set, onChange)
		s.Position = UDim2.new(1, -38, 0.5, -11)
		s.Parent = f
		return f
	end

	local ICON_FILL = 0.72 -- transparency of the soft fill inside outlines
	local function icon(name, size, color)
		local f = box({ Size = UDim2.fromOffset(size, size) })
		local th = math.max(1.6, size / 7.5)
		local function ring(cx, cy, r, filled)
			local o = box({
				BackgroundTransparency = filled and 0 or ICON_FILL,
				BackgroundColor3 = color,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(cx * size, cy * size),
				Size = UDim2.fromOffset(r * 2 * size, r * 2 * size),
				Parent = f,
			}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
			if not filled then
				local st = stroke(color)
				st.Thickness = th
				st.Parent = o
			end
			return o
		end
		local function rect(cx, cy, w, h, filled, rad)
			local o = box({
				BackgroundTransparency = filled and 0 or ICON_FILL,
				BackgroundColor3 = color,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(cx * size, cy * size),
				Size = UDim2.fromOffset(w * size, h * size),
				Parent = f,
			}, { corner(math.max(rad or 1, size * 0.14)) })
			if not filled then
				local st = stroke(color)
				st.Thickness = th
				st.Parent = o
			end
			return o
		end
		local function bar(x1, y1, x2, y2)
			local dx, dy = (x2 - x1) * size, (y2 - y1) * size
			box({
				BackgroundTransparency = 0,
				BackgroundColor3 = color,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset((x1 + x2) / 2 * size, (y1 + y2) / 2 * size),
				Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy) + th, th),
				Rotation = math.deg(math.atan2(dy, dx)),
				Parent = f,
			}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) }) -- round ends
		end
		if name == "brush" then
			ring(0.5, 0.5, 0.36)
			ring(0.5, 0.5, 0.09, true)
		elseif name == "search" then
			ring(0.42, 0.42, 0.27)
			bar(0.63, 0.63, 0.84, 0.84)
		elseif name == "erase" then
			ring(0.5, 0.5, 0.36)
			bar(0.24, 0.76, 0.76, 0.24)
		elseif name == "lasso" then
			ring(0.52, 0.4, 0.32)
			bar(0.36, 0.7, 0.24, 0.94)
		elseif name == "box" then
			rect(0.5, 0.5, 0.7, 0.7, false, 2)
		elseif name == "polygon" then
			bar(0.5, 0.14, 0.88, 0.82)
			bar(0.88, 0.82, 0.12, 0.82)
			bar(0.12, 0.82, 0.5, 0.14)
		elseif name == "fill" then
			rect(0.44, 0.5, 0.5, 0.5, false, 2).Rotation = 45
			ring(0.86, 0.8, 0.09, true)
		elseif name == "spline" then
			bar(0.14, 0.78, 0.5, 0.3)
			bar(0.5, 0.3, 0.86, 0.64)
			ring(0.14, 0.78, 0.1, true)
			ring(0.5, 0.3, 0.1, true)
			ring(0.86, 0.64, 0.1, true)
		elseif name == "area" then
			rect(0.5, 0.5, 0.78, 0.78, false, 3)
			ring(0.36, 0.38, 0.08, true)
			ring(0.64, 0.56, 0.08, true)
			ring(0.4, 0.68, 0.07, true)
		elseif name == "clear" then -- a keep-clear zone: a crossed-out patch
			rect(0.5, 0.5, 0.78, 0.78, false, 3)
			bar(0.26, 0.74, 0.74, 0.26)
		elseif name == "layers" then
			rect(0.5, 0.26, 0.8, 0.14, true, 2)
			rect(0.5, 0.5, 0.8, 0.14, true, 2)
			rect(0.5, 0.74, 0.8, 0.14, true, 2)
		elseif name == "settings" then
			bar(0.12, 0.3, 0.88, 0.3)
			bar(0.12, 0.7, 0.88, 0.7)
			ring(0.34, 0.3, 0.11, true)
			ring(0.66, 0.7, 0.11, true)
		elseif name == "plus" then
			bar(0.5, 0.16, 0.5, 0.84)
			bar(0.16, 0.5, 0.84, 0.5)
		elseif name == "close" then
			bar(0.22, 0.22, 0.78, 0.78)
			bar(0.22, 0.78, 0.78, 0.22)
		elseif name == "info" then
			ring(0.5, 0.5, 0.38)
			bar(0.5, 0.46, 0.5, 0.7)
			ring(0.5, 0.31, 0.05, true)
		elseif name == "right" then
			bar(0.38, 0.2, 0.66, 0.5)
			bar(0.66, 0.5, 0.38, 0.8)
		elseif name == "left" then
			bar(0.62, 0.2, 0.34, 0.5)
			bar(0.34, 0.5, 0.62, 0.8)
		elseif name == "down" then
			bar(0.2, 0.38, 0.5, 0.66)
			bar(0.5, 0.66, 0.8, 0.38)
		elseif name == "trash" then
			bar(0.16, 0.28, 0.84, 0.28)
			bar(0.38, 0.14, 0.62, 0.14)
			rect(0.5, 0.6, 0.52, 0.56, false, 2)
		elseif name == "logo" then
			ring(0.5, 0.2, 0.08, true)
			ring(0.24, 0.72, 0.08, true)
			ring(0.76, 0.72, 0.08, true)
			bar(0.5, 0.3, 0.5, 0.42)
			bar(0.36, 0.62, 0.44, 0.48)
			bar(0.64, 0.62, 0.56, 0.48)
		elseif name == "refresh" then
			ring(0.5, 0.52, 0.32)
			bar(0.62, 0.14, 0.84, 0.2)
			bar(0.84, 0.2, 0.8, 0.42)
		end
		return f
	end
	local function setIconColor(ic, color)
		for _, d in ic:GetDescendants() do
			if d:IsA("UIStroke") then
				d.Color = color
			elseif d:IsA("Frame") and d.BackgroundTransparency < 1 then
				d.BackgroundColor3 = color
			end
		end
	end

	local SHOWN = { Spline = "Path" }

	local function segmented(options, get, set, onChange, height, toggleable, icons, hints)
		local n = #options
		height = math.max(height or 30, 30)
		local f = new("Frame", { BackgroundColor3 = P.field, Size = UDim2.new(1, 0, 0, height) }, { corner(9), stroke(P.line) })
		local inner = box({ Position = UDim2.fromOffset(2, 2), Size = UDim2.new(1, -4, 1, -4), Parent = f })
		local pill = box({
			BackgroundTransparency = 1,
			BackgroundColor3 = P.accentSoft,
			Size = UDim2.new(1 / n, 0, 1, 0),
			Position = UDim2.new(0, 0, 0, 0),
			Parent = inner,
		}, { corner(7) })
		local pillStroke = stroke(P.accentLine)
		pillStroke.Transparency = 1
		pillStroke.Parent = pill

		local row = box({ Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = inner }, { hlist(0) })
		local btns = {}
		local shown, init = false, false
		local function refresh()
			local cur = get()
			local idx = table.find(options, cur)
			if idx then
				local target = UDim2.new((idx - 1) / n, 0, 0, 0)
				if shown then
					tween(pill, FAST, { Position = target })
				else
					pill.Position = target
				end
				if init then
					tween(pill, FAST, { BackgroundTransparency = 0 })
					tween(pillStroke, FAST, { Transparency = 0 })
				else
					pill.BackgroundTransparency, pillStroke.Transparency = 0, 0
				end
			elseif init then
				tween(pill, FAST, { BackgroundTransparency = 1 })
				tween(pillStroke, FAST, { Transparency = 1 })
			end
			shown, init = idx ~= nil, true
			for o, b in btns do
				local on = cur == o
				local lbl = b:FindFirstChild("Label", true) or b
				lbl.Font = on and SANS_M or SANS
				lbl.TextColor3 = on and P.accent or P.dim
				local ic = b:FindFirstChild("Icon", true)
				if ic then
					setIconColor(ic, on and P.accent or P.dim)
				end
			end
		end
		pillStroke.Color = P.accentLine
		for _, o in options do
			local b = new("TextButton", {
				Text = SHOWN[o] or o,
				Font = SANS_M,
				TextSize = 13,
				TextColor3 = P.dim,
				AutoButtonColor = false,
				BackgroundTransparency = 1,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Size = UDim2.new(1 / n, 0, 1, 0),
				ZIndex = 2,
				Parent = row,
			})
			if icons and icons[o] then
				b.Text = ""
				local tall = height >= 44
				local content = box({ Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = b }, {
					new("UIListLayout", {
						FillDirection = tall and Enum.FillDirection.Vertical or Enum.FillDirection.Horizontal,
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0, tall and 3 or 5),
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
				})
				local ic = icon(icons[o], tall and 16 or 13, P.dim)
				ic.Name = "Icon"
				ic.Parent = content
				label(SHOWN[o] or o, 12, P.dim, SANS_M, {
					Name = "Label",
					Size = UDim2.fromOffset(0, tall and 13 or 16),
					AutomaticSize = Enum.AutomaticSize.X,
					TextXAlignment = Enum.TextXAlignment.Center,
					ZIndex = 2,
					Parent = content,
				})
			end
			local function labelOf()
				local c = b:FindFirstChild("Label", true)
				return c or b
			end
			b.MouseEnter:Connect(function()
				if get() ~= o then
					labelOf().TextColor3 = P.text
				end
			end)
			b.MouseLeave:Connect(function()
				if get() ~= o then
					labelOf().TextColor3 = P.dim
				end
			end)
			b.MouseButton1Click:Connect(function()
				if get() == o and not toggleable then
					return
				end
				set(o)
				refresh()
				if onChange then
					onChange()
				end
			end)
			if hints and hints[o] then
				hintOn(b, hints[o])
			end
			btns[o] = b
		end
		refresh()
		return f, refresh
	end

	local function stepLabel(parent, n, text, done)
		local row = box({ Size = UDim2.new(1, 0, 0, 22), Parent = parent }, { hlist(8) })
		if n then
			local dot = label(tostring(n), 10, done and P.onAccent or P.faint, SANS_B, {
				Size = UDim2.fromOffset(16, 16),
				TextXAlignment = Enum.TextXAlignment.Center,
				BackgroundTransparency = done and 0 or 1,
				BackgroundColor3 = P.accent,
				Parent = row,
			})
			corner(8).Parent = dot
			local st = stroke(done and P.accent or P.faint)
			st.Thickness = 1.5
			st.Parent = dot
		end
		label(string.upper(text), 11, P.faint, SANS_B, { Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, Parent = row })
		return row
	end

	local function hintBox(parent, text)
		local f = col({
			BackgroundTransparency = 0,
			BackgroundColor3 = P.accent:Lerp(P.bg, 0.9),
			Parent = parent,
		}, { corner(10), stroke(P.accent:Lerp(P.bg, 0.72)), pad(12, 12, 10, 10) })
		local ic = icon("info", 15, P.accent)
		ic.Position = UDim2.fromOffset(0, 1)
		ic.Parent = f
		local t = para(text, { Position = UDim2.fromOffset(24, 0), Size = UDim2.new(1, -24, 0, 0), Parent = f })
		t.TextColor3 = P.dim
		return f, t
	end

	local function keyChips(parent, list)
		local row = buttonRow(parent, 6)
		for _, k in list do
			local chip = new("Frame", {
				BackgroundColor3 = P.raised,
				Size = UDim2.fromOffset(0, 24),
				AutomaticSize = Enum.AutomaticSize.X,
				Parent = row,
			}, { corner(6), pad(5, 8, 0, 0), hlist(5) })
			local key = label(k[1], 10, P.text, SANS_B, {
				Size = UDim2.fromOffset(0, 16),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundTransparency = 0,
				BackgroundColor3 = P.raised:Lerp(Color3.new(1, 1, 1), 0.08),
				Parent = chip,
			})
			corner(4).Parent = key
			pad(5, 5, 0, 0).Parent = key
			label(k[2], 11, P.dim, SANS, { Size = UDim2.fromOffset(0, 16), AutomaticSize = Enum.AutomaticSize.X, Parent = chip })
		end
		return row
	end

	local function iconButton(iconName, hint, onClick, on, size)
		size = size or 32
		local b = new("TextButton", {
			Text = "",
			BackgroundColor3 = on and P.accentSoft or P.raised,
			AutoButtonColor = false,
			Size = UDim2.fromOffset(size, size),
		}, { corner(9), stroke(on and P.accentLine or P.line) })
		pressable(b, 0.94)
		local ic = icon(iconName, math.floor(size * 0.44), on and P.accent or P.dim)
		ic.AnchorPoint = Vector2.new(0.5, 0.5)
		ic.Position = UDim2.fromScale(0.5, 0.5)
		ic.Parent = b
		b.MouseEnter:Connect(function()
			if not on then
				b.BackgroundColor3 = P.hover
				setIconColor(ic, P.text)
			end
		end)
		b.MouseLeave:Connect(function()
			if not on then
				b.BackgroundColor3 = P.raised
				setIconColor(ic, P.dim)
			end
		end)
		hintOn(b, hint)
		if onClick then
			b.MouseButton1Click:Connect(function()
				onClick(b)
			end)
		end
		return b, ic
	end

	local TYPED = {
		["["] = "LeftBracket",
		["]"] = "RightBracket",
		["-"] = "Minus",
		["="] = "Equals",
		[";"] = "Semicolon",
		[","] = "Comma",
		["."] = "Period",
		["/"] = "Slash",
		[" "] = "Space",
		["'"] = "Quote",
	}
	for d, n in
		{
			["1"] = "One",
			["2"] = "Two",
			["3"] = "Three",
			["4"] = "Four",
			["5"] = "Five",
			["6"] = "Six",
			["7"] = "Seven",
			["8"] = "Eight",
			["9"] = "Nine",
			["0"] = "Zero",
		}
	do
		TYPED[d] = n
	end
	local function captureKey(over, done)
		local UIS = game:GetService("UserInputService")
		local tb = new("TextBox", {
			Text = "",
			TextTransparency = 1,
			BackgroundTransparency = 1,
			ClearTextOnFocus = true,
			Size = UDim2.fromScale(1, 1),
			ZIndex = over.ZIndex + 2,
			Parent = over,
		})
		local conns, finished = {}, false
		local function finish(key)
			if finished then
				return
			end
			finished = true
			for _, c in conns do
				c:Disconnect()
			end
			tb:Destroy()
			done(key ~= "Escape" and key or nil)
		end
		local function fromInput(input)
			if input.UserInputType == Enum.UserInputType.Keyboard and not App.UNBINDABLE[input.KeyCode.Name] then
				finish(input.KeyCode.Name)
			end
		end
		table.insert(conns, tb.InputBegan:Connect(fromInput))
		table.insert(conns, UIS.InputBegan:Connect(fromInput))
		table.insert(
			conns,
			tb:GetPropertyChangedSignal("Text"):Connect(function()
				local ch = string.sub(tb.Text, -1)
				if ch ~= "" then
					finish(TYPED[ch] or (string.match(ch, "%a") and string.upper(ch)) or nil)
				end
			end)
		)
		table.insert(
			conns,
			tb.FocusLost:Connect(function(enter)
				task.defer(finish, enter and "Return" or nil) -- after any key event of the same press
			end)
		)
		tb:CaptureFocus()
		return function()
			finish(nil)
		end
	end

	local function emptyState(parent, title, text, actionText, onAction)
		local f = col({ Parent = parent }, {
			pad(8, 8, 18, 18),
			new("UIListLayout", {
				Padding = UDim.new(0, 8),
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		new("ImageLabel", { Image = App.LOGO.mark, BackgroundTransparency = 1, Size = UDim2.fromOffset(40, 40), Parent = f })
		label(title, 14, P.text, SANS_B, { Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center, Parent = f })
		local t = para(text, { Parent = f })
		t.TextColor3, t.TextXAlignment = P.dim, Enum.TextXAlignment.Center
		if actionText then
			box({ Size = UDim2.new(1, 0, 0, 2), Parent = f })
			button(actionText, "accent", onAction, { Parent = f })
		end
		return f
	end

	local function chip(parent, text, isOn, onClick, swatch)
		local b = new(
			"TextButton",
			{ Text = (swatch and "     " or "") .. text, TextSize = 12, AutoButtonColor = false, Parent = parent },
			{ corner(8) }
		)
		local st = stroke(P.line)
		st.Parent = b
		if swatch then -- a colour dot before the name
			box({
				BackgroundTransparency = 0,
				BackgroundColor3 = swatch,
				Size = UDim2.fromOffset(8, 8),
				Position = UDim2.new(0, 9, 0.5, -4),
				ZIndex = b.ZIndex + 1,
				Parent = b,
			}, { corner(4) })
		end
		pressable(b)
		local function look()
			local on = isOn ~= nil and isOn() == true
			b.Font = on and SANS_B or SANS_M
			b.BackgroundColor3 = on and P.accentSoft or P.raised
			b.TextColor3 = on and P.accent or (isOn and P.dim or P.text)
			st.Color = on and P.accentLine or P.line
		end
		look()
		b.MouseButton1Click:Connect(function()
			onClick()
			look()
		end)
		return b, look
	end
	local function chipGrid(parent, cols, h)
		return col({ Parent = parent }, {
			new("UIGridLayout", {
				CellSize = UDim2.new(1 / cols, -6, 0, h or 30),
				CellPadding = UDim2.fromOffset(6, 6),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
	end

	local function pageHead(parent, backText, title, onBack)
		local row = box({ Size = UDim2.new(1, 0, 0, 30), Parent = parent })
		local back = new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(0, 30),
			AutomaticSize = Enum.AutomaticSize.X,
			Parent = row,
		}, { hlist(4) })
		local ic = icon("left", 13, P.dim)
		ic.Parent = back
		local t = label(backText, 13, P.dim, SANS_M, { Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, Parent = back })
		back.MouseEnter:Connect(function()
			t.TextColor3 = P.text
			setIconColor(ic, P.text)
		end)
		back.MouseLeave:Connect(function()
			t.TextColor3 = P.dim
			setIconColor(ic, P.dim)
		end)
		back.MouseButton1Click:Connect(onBack)
		if title then
			box({ Size = UDim2.new(1, 0, 0, 4), Parent = parent })
			label(title, 17, P.text, SANS_B, { Size = UDim2.new(1, 0, 0, 24), Parent = parent })
		end
		return row
	end

	App.new = new
	App.textSize = textSize
	App.TEXT_SIZES = TEXT_SIZES
	App.corner = corner
	App.stroke = stroke
	App.pad = pad
	App.vlist = vlist
	App.hlist = hlist
	App.box = box
	App.col = col
	App.label = label
	App.para = para
	App.explain = explain
	App.hoverable = hoverable
	App.halftone = halftone
	App.sheen = sheen
	App.fadeLine = fadeLine
	App.shade = shade
	App.glow = glow
	App.shadow = shadow
	App.pressable = pressable
	App.sweep = sweep
	App.topLight = topLight
	App.hideTip = hideTip
	App.button = button
	App.buttonRow = buttonRow
	App.hintOn = hintOn
	App.refreshSliders = refreshSliders
	App.slider = slider
	App.switch = switch
	App.switchRow = switchRow
	App.segmented = segmented
	App.icon = icon
	App.setIconColor = setIconColor
	App.stepLabel = stepLabel
	App.hintBox = hintBox
	App.keyChips = keyChips
	App.pageHead = pageHead
	App.chip = chip
	App.emptyState = emptyState
	App.captureKey = captureKey
	App.chipGrid = chipGrid
	App.iconButton = iconButton
end
end)()
-- #module Core/Cards
MODULES["Core/Cards"] = (function()
--[[
	Smart Scatter — Cards: how every tab lays out its features, and the search box that finds them.
	A tab is a column of cards, one per feature: the basics first, then the extras folded under "More options".
	While searching, only the cards whose words match are built, and the extras show without the fold.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local G, saveG, P, SANS_B = App.G, App.saveG, App.P, App.SANS_B
	local new, corner, stroke, pad, vlist, hlist = App.new, App.corner, App.stroke, App.pad, App.vlist, App.hlist
	local box, col, label, icon = App.box, App.col, App.label, App.icon

	local SUB = {
		scanfix = "Tell it what's a road, building or water",
		line = "What it follows and which way it faces",
		variants = "Mix several models in one object",
		layerpaint = "Brush more or less of it by hand",
		size = "Random sizes, smallest to largest",
		spread = "Spacing, clumping and a limit",
		groups = "Small piles, like rocks or crates",
		surfaces = "Grass, sand, rock… and a height band",
		avoid = "Distance from buildings, roads, water",
		attract = "Grow close to walls, water or roads",
		terrain = "Steepest ground and leaning",
		look = "Rotation, tilt, colour, variation and sinking",
		presets = "Save this set of objects, reuse it anywhere",
		output = "Collision, shadows, streaming",
	}

	App.searchWords = {}
	App.searching = function()
		return #App.searchWords > 0
	end
	App.setSearch = function(text)
		local words = {}
		for w in string.gmatch(string.lower(text or ""), "%S+") do
			table.insert(words, w)
		end
		App.searchWords = words
	end
	local function matches(spec)
		local hay = string.lower(spec.title .. " " .. (spec.sub or SUB[spec.id] or "") .. " " .. (spec.keys or ""))
		for _, w in App.searchWords do
			if not string.find(hay, w, 1, true) then
				return false
			end
		end
		return true
	end

	App.cardCount = 0 -- cards built since the panel was last built (the search tells empty tabs from ones with hits)

	local function card(parent, spec, order)
		App.cardCount += 1
		local c = col({ BackgroundTransparency = 0, BackgroundColor3 = P.card, LayoutOrder = order, Parent = parent }, {
			corner(12),
			stroke(P.line),
			pad(14, 14, 12, 14),
			vlist(8),
		})
		App.shade(c, 0.05)
		App.topLight(c, 0.06, 12)
		local head = col({ Parent = c })
		local x = 0
		if spec.icon then
			local badge = box({
				BackgroundTransparency = 0,
				BackgroundColor3 = P.accent:Lerp(P.card, 0.86),
				Size = UDim2.fromOffset(28, 28),
				Parent = head,
			}, { corner(7) })
			local ic = icon(spec.icon, 14, P.accent)
			ic.AnchorPoint, ic.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
			ic.Parent = badge
			x = 38
		end
		local txt = col({ Position = UDim2.fromOffset(x, 0), Size = UDim2.new(1, -x, 0, 0), Parent = head }, { vlist(1) })
		local titleRow = box({ Size = UDim2.new(1, 0, 0, 18), Parent = txt }, { hlist(8) })
		label(spec.title, 14, P.text, SANS_B, { Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, Parent = titleRow })
		if spec.tag then -- a small pill after the title ("Optional")
			local tag = label(spec.tag, 10, P.dim, SANS_B, {
				Size = UDim2.fromOffset(0, 18),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundTransparency = 0,
				BackgroundColor3 = P.raised,
				Parent = titleRow,
			})
			corner(9).Parent = tag
			pad(7, 7, 0, 0).Parent = tag
		end
		local sub = spec.sub or SUB[spec.id]
		if sub and sub ~= "" then
			local s = App.para(sub, { Parent = txt })
			s.TextColor3 = P.dim
		end
		local body = col({ Parent = c }, { vlist(6) })
		spec.build(body, c)
		return c
	end

	App.cards = function(parent, id)
		local cs = {}
		local order = 0
		local fold, foldBody, foldCount
		local function moreBody()
			if App.searching() then -- search results show flat
				return parent
			end
			if foldBody then
				return foldBody
			end
			local key = "more:" .. id
			local open = G.groups[key] == true
			fold = col({ LayoutOrder = 100000, Parent = parent }, { vlist(10) })
			local head = new("TextButton", {
				Text = "",
				AutoButtonColor = false,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 30),
				Parent = fold,
			})
			local line = box({
				BackgroundTransparency = 0,
				BackgroundColor3 = P.line,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromScale(0, 0.5),
				Size = UDim2.new(1, 0, 0, 1),
				Parent = head,
			})
			local chip = box({
				BackgroundTransparency = 0,
				BackgroundColor3 = P.bg,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(0, 26),
				AutomaticSize = Enum.AutomaticSize.X,
				Parent = head,
			}, { pad(10, 10, 0, 0), hlist(6) })
			local chev = icon("right", 11, P.dim)
			chev.Parent = chip
			foldCount = label("", 12, P.dim, SANS_B, { Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, Parent = chip })
			foldBody = col({ Parent = fold }, { vlist(10) })
			local function look()
				foldBody.Visible = open
				chev.Rotation = open and 90 or 0
			end
			look()
			head.MouseEnter:Connect(function()
				foldCount.TextColor3 = P.text
				line.BackgroundColor3 = P.accentLine
			end)
			head.MouseLeave:Connect(function()
				foldCount.TextColor3 = P.dim
				line.BackgroundColor3 = P.line
			end)
			head.MouseButton1Click:Connect(function()
				open = not open
				G.groups[key] = open or nil
				saveG()
				look()
			end)
			return foldBody
		end
		local nMore = 0
		function cs.add(spec)
			if App.searching() and not matches(spec) then
				return nil
			end
			if spec.more then
				local into = moreBody()
				nMore += 1
				if foldCount then
					foldCount.Text = string.format("More options  ·  %d", nMore)
				end
				order += 1
				return card(into, spec, order)
			end
			order += 1
			return card(parent, spec, order)
		end
		return cs
	end

	App.goNote = function(parent, text, buttonText, tab)
		local wrap = col({ Parent = parent }, { vlist(8) })
		App.hintBox(wrap, text)
		if buttonText then
			App.button(buttonText, "accent", function()
				App.goPage(tab)
			end, { Parent = App.buttonRow(wrap) })
		end
		return wrap
	end
end
end)()
-- #module Viewport/Overlay
MODULES["Viewport/Overlay"] = (function()
--[[
	Smart Scatter — Overlay: the widget and the painted-area overlay in the viewport.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local RunService, ctx, Engine, track, G, LAYER_MODES = App.RunService, App.ctx, App.Engine, App.track, App.G, App.LAYER_MODES
	local new = App.new

	local toggleBtn = ctx.button
	App.widget = ctx.widget

	local overlayFolder
	local rowParts = {} -- [cz] = { parts }
	App.dirtyRows = {} -- [cz] = true
	local cellInfo = {} -- [cz][cx] = { y =, cls = } quick ground probe cache
	local MAX_OVERLAY = 80000
	local VIEW = App.VIEW -- the viewport's colours (Base; they follow the accent theme)

	local function templates()
		local t = {}
		if App.area then
			for _, l in App.area.layers do
				for _, v in l.variants do
					table.insert(t, v.inst)
				end
			end
		end
		return t
	end
	local function refreshParams()
		App.probeParams = Engine.rayParams(templates())
	end

	local function probe(cx, cz, yHint)
		local r = cellInfo[cz]
		local info = r and r[cx]
		if info then
			return info
		end
		if not App.probeParams then
			refreshParams()
		end
		local c = App.area.cell
		local top = math.max(App.area.topY or 0, yHint or -math.huge) + 250
		local hit = workspace:Raycast(Vector3.new((cx + 0.5) * c, top, (cz + 0.5) * c), Vector3.new(0, -1500, 0), App.probeParams)
		info = { y = hit and hit.Position.Y or (yHint or App.area.topY or 0), cls = hit and (Engine.surfaceOf(hit.Instance, hit.Material)) or "None" }
		if not r then
			r = {}
			cellInfo[cz] = r
		end
		r[cx] = info
		return info
	end

	local function overlayVisible()
		return App.area ~= nil
			and App.widget.Enabled
			and not App.overlayHidden -- the hide key (for this session)
			and (G.overlay or App.mode ~= "Off" or App.heatLayer ~= nil)
			and App.area.count <= MAX_OVERLAY
	end
	local function clearOverlay()
		if overlayFolder then
			overlayFolder:Destroy()
			overlayFolder = nil
		end
		rowParts, App.dirtyRows = {}, {}
	end
	local QUIET = { Road = true, Dirt = true } -- only some objects go there
	local BLOCKED = { Building = true, Water = true }
	local function cellColor(cx, cz, zone)
		local an = App.lastAnalysis
		if App.heatLayer and an and not App.analysisDirty then
			App.heatFn = App.heatFn or Engine.heat(App.heatLayer, an, App.area)
			local j = Engine.indexAt(an, (cx + 0.5) * App.area.cell, (cz + 0.5) * App.area.cell)
			local v = j and App.heatFn(j) or 0
			return v <= 0 and VIEW.less or VIEW.muted:Lerp(VIEW.accent, math.clamp(0.25 + v * 0.75, 0, 1))
		end
		if App.paintLayer and LAYER_MODES[App.mode] == "paint" then
			local v = Engine.paintValue(App.paintLayer, cx, cz)
			if v > 1.001 then
				return VIEW.muted:Lerp(VIEW.accent, math.clamp(0.35 + (v - 1) * 0.35, 0, 1))
			end
			if v < 0.999 then
				return VIEW.muted:Lerp(VIEW.less, math.clamp(0.4 + (1 - v) * 0.6, 0, 1))
			end
			return VIEW.muted
		end
		if zone then -- a keep-clear zone: one colour
			return VIEW.blocked
		end
		local cls
		if App.lastAnalysis and not App.analysisDirty then
			local j = Engine.indexAt(App.lastAnalysis, (cx + 0.5) * App.area.cell, (cz + 0.5) * App.area.cell)
			cls = j and App.lastAnalysis.cls[j]
		end
		cls = cls or probe(cx, cz).cls
		return BLOCKED[cls] and VIEW.blocked or QUIET[cls] and VIEW.muted or VIEW.accent
	end
	local function onEdge(cx, cz)
		local a = App.area
		return not (
			Engine.hasCell(a, cx + 1, cz)
			and Engine.hasCell(a, cx - 1, cz)
			and Engine.hasCell(a, cx, cz + 1)
			and Engine.hasCell(a, cx, cz - 1)
		)
	end
	local edgeStrips = setmetatable({}, { __mode = "k" }) -- the outline's strips (they breathe while you paint)
	local EDGE_REST = 0.25
	local function buildRow(cz)
		local old = rowParts[cz]
		if old then
			for _, p in old do
				p:Destroy()
			end
			rowParts[cz] = nil
		end
		local row = App.area and App.area.rows[cz]
		if not row then
			return
		end
		if not overlayFolder or not overlayFolder.Parent then
			overlayFolder = new("Folder", { Name = "SmartScatterOverlay", Archivable = false, Parent = workspace.CurrentCamera })
		end
		local xs = {}
		for cx in row do
			table.insert(xs, cx)
		end
		table.sort(xs)
		local c, parts, i = App.area.cell, {}, 1
		local zone = App.kindOf(App.area) == "Clear"
		local painting = App.paintLayer and LAYER_MODES[App.mode] == "paint" -- per-object paint: no outline, just the amounts
		local function style(cx)
			local col = cellColor(cx, cz, zone)
			if not painting and onEdge(cx, cz) then
				return col == VIEW.accent and VIEW.edge or col, true
			end
			return col, false
		end
		while i <= #xs do
			local sx = xs[i]
			local y0 = probe(sx, cz).y
			local col, edge = style(sx)
			local ymax, j = y0, i
			while j < #xs and xs[j + 1] == xs[j] + 1 and j - i < 31 do
				local ny = probe(xs[j + 1], cz).y
				local col2, edge2 = style(xs[j + 1])
				if math.abs(ny - y0) > 0.6 or col2 ~= col or edge2 ~= edge then
					break
				end
				ymax = math.max(ymax, ny)
				j += 1
			end
			local n = j - i + 1
			local strip = new("Part", {
				Anchored = true,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
				CastShadow = false,
				Locked = true,
				Archivable = false,
				Material = Enum.Material.SmoothPlastic,
				Transparency = edge and EDGE_REST or 0.62,
				Color = col,
				Size = Vector3.new(n * c - 0.3, edge and 0.16 or 0.1, c - 0.3),
				CFrame = CFrame.new(sx * c + n * c / 2, ymax + 0.2, (cz + 0.5) * c),
				Parent = overlayFolder,
			})
			table.insert(parts, strip)
			if edge then
				edgeStrips[strip] = true
			end
			i = j + 1
		end
		rowParts[cz] = parts
	end
	local function flushRows(budget)
		if not overlayVisible() then
			App.dirtyRows = {}
			return
		end
		local fresh = {}
		for cz, v in App.dirtyRows do
			if v == true then
				table.insert(fresh, cz)
			end
		end
		for _, cz in fresh do -- (keys are added after the loop: a table can't grow while it's being walked)
			App.dirtyRows[cz] = "near"
			App.dirtyRows[cz - 1] = App.dirtyRows[cz - 1] or "near"
			App.dirtyRows[cz + 1] = App.dirtyRows[cz + 1] or "near"
		end
		local t0 = os.clock()
		for cz in App.dirtyRows do
			App.dirtyRows[cz] = nil
			buildRow(cz)
			if budget and os.clock() - t0 > budget then
				break
			end
		end
	end
	local breath, breathing = 0, false
	track(RunService.Heartbeat:Connect(function(dt)
		if next(App.dirtyRows) then
			flushRows(0.004) -- a few ms a frame, so a big redraw never stalls Studio
		end
		local paint = (App.mode == "Paint" or App.mode == "Erase") and overlayFolder ~= nil
		if paint or breathing then
			breath += dt
			if breath >= 0.08 or not paint then
				local t = paint and EDGE_REST - 0.06 + 0.06 * math.sin(os.clock() * 2.4) or EDGE_REST
				breath, breathing = 0, paint
				for strip in edgeStrips do
					strip.Transparency = t
				end
			end
		end
	end))

	local function rebuildOverlay(fresh)
		clearOverlay()
		if fresh then
			cellInfo = {}
		end
		refreshParams()
		if not overlayVisible() then
			return
		end
		for cz in App.area.rows do
			App.dirtyRows[cz] = true
		end
		flushRows(0.03) -- the first part now, the rest over the next frames
	end
	local function recolorOverlay()
		App.heatFn = nil -- rules may have changed: the heatmap is worked out again
		for cz in rowParts do
			App.dirtyRows[cz] = true
		end
	end

	App.toggleBtn = toggleBtn
	App.templates = templates
	App.refreshParams = refreshParams
	App.probe = probe
	App.clearOverlay = clearOverlay
	App.flushRows = flushRows
	App.rebuildOverlay = rebuildOverlay
	App.recolorOverlay = recolorOverlay
end
end)()
-- #module Core/Generation
MODULES["Core/Generation"] = (function()
--[[
	Smart Scatter — Generation: generation (cached scan, live throttle), areas and model thumbnails.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local beginRec, endRec, Engine, G, num, P, new = App.beginRec, App.endRec, App.Engine, App.G, App.num, App.P, App.new
	local corner, stroke, templates, rebuildOverlay = App.corner, App.stroke, App.templates, App.rebuildOverlay
	local recolorOverlay = App.recolorOverlay


	local CHS = App.ChangeHistoryService
	local lastPrint, worldEdited = nil, true
	local function edited()
		worldEdited = true
	end
	App.track(CHS.OnUndo:Connect(edited))
	App.track(CHS.OnRedo:Connect(edited))
	pcall(function()
		App.track(CHS.OnRecordingFinished:Connect(function(name)
			if not (type(name) == "string" and string.find(name, "Smart Scatter", 1, true)) then
				worldEdited = true
			end
		end))
	end)
	local function worldPrint()
		local an = App.lastAnalysis
		if not an then
			return nil
		end
		local w, d = an.nx * an.G, an.nz * an.G
		local centre = Vector3.new(an.x0 + w / 2, an.top - an.len / 2, an.z0 + d / 2)
		local op = OverlapParams.new()
		op.FilterType = Enum.RaycastFilterType.Exclude
		local skip = { workspace.CurrentCamera, workspace.Terrain }
		for _, name in { Engine.OUT, Engine.ROADS } do
			local f = workspace:FindFirstChild(name)
			if f then
				table.insert(skip, f)
			end
		end
		for _, t in templates() do
			table.insert(skip, t)
		end
		op.FilterDescendantsInstances = skip
		local sum, count = 0, 0
		for _, p in workspace:GetPartBoundsInBox(CFrame.new(centre), Vector3.new(w, an.len, d), op) do
			local pos, sz = p.Position, p.Size
			sum += pos.X * 1.31 + pos.Y * 2.17 + pos.Z * 3.73 + sz.X * 5.39 + sz.Y * 7.13 + sz.Z * 11.97 + p.Material.Value * 0.013 + (p.CanCollide and 0.7 or 0) + p.Orientation.Y * 0.0071
			count += 1
		end
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Include
		rp.FilterDescendantsInstances = { workspace.Terrain }
		local down = Vector3.new(0, -an.len, 0)
		for i = 0, 15 do
			for j = 0, 15 do
				local hit = workspace:Raycast(Vector3.new(an.x0 + (i + 0.5) * w / 16, an.top, an.z0 + (j + 0.5) * d / 16), down, rp)
				if hit then
					sum += hit.Position.Y * (i * 16 + j + 1) * 0.001 + hit.Material.Value * 0.0003
				end
			end
		end
		return string.format("%d:%.3f", count, sum)
	end
	App.worldChanged = function()
		if worldEdited or not App.lastAnalysis or not lastPrint then
			return true
		end
		return worldPrint() ~= lastPrint
	end

	local function saveArea()
		if App.area then
			Engine.saveArea(App.area)
		end
	end

	local function canGenerate()
		if not App.area then
			return false, "Paint an area to get started."
		end
		if App.area.locked then
			return false, "Area locked · unlock it in the area menu"
		end
		if App.area.count == 0 and not (App.area.spline and #App.area.spline.pts >= 2) then
			return false, "Paint an area or draw a spline first."
		end
		local sp = App.area.spline
		local road = sp and Engine.roadWidth(sp) > 0 and #sp.pts >= 2
		if #App.area.layers == 0 and not road then
			return false, "Add a layer to fill the area."
		end
		return true
	end

	local function explainError(err)
		local msg = tostring(err)
		local where, line, rest = string.match(msg, "([%w_]+):(%d+): (.*)$")
		if rest then
			local part = string.find(where, "Engine", 1, true) and "engine" or "plugin"
			msg = rest .. " (" .. part .. " line " .. line .. ")"
		end
		msg = string.gsub(msg, "%s+", " ")
		if #msg > 90 then
			msg = string.sub(msg, 1, 87) .. "..."
		end
		return msg .. "."
	end

	local ALL = {} -- `from` meaning "rebuild every layer"
	local function mergeFrom(a, b)
		b = b or ALL
		if a == nil or a == b then
			return b
		end
		return ALL
	end
	local FIRST_SLICE, SLICE = 0.08, 0.03
	local HEAVY_PARTS = 25000 -- more than this is a slowdown on most machines: Live update stops and asks
	local heavyAsked = setmetatable({}, { __mode = "k" }) -- [area folder] = true once the pop-up was shown
	local job -- the running job: { live = bool, from = layer?, cancel = bool }
	local liveFrom, liveLoop = nil, false

	local lostPatch
	local function joinBoxes(a, b)
		if not (a and b) then
			return a or b
		end
		return { math.min(a[1], b[1]), math.min(a[2], b[2]), math.max(a[3], b[3]), math.max(a[4], b[4]) }
	end
	local function runGenerate(recorded, from, region)
		if not canGenerate() then -- the Generate button shows why
			return
		end
		local me = { live = not recorded, from = from }
		while job do -- wait for the running job; a newer request of any kind retires a live preview
			if job.live and job ~= me then
				job.cancel = true
			end
			task.wait()
		end
		if not canGenerate() then -- the area was deleted, emptied or locked while this waited
			return
		end
		job = me
		if lostPatch then
			from = nil
			region = lostPatch ~= true and region and joinBoxes(region, lostPatch) or nil
		end
		me.from, me.region = from, not recorded and region or nil
		App.heavyWarning = nil
		local area = App.area
		local t0, slice = os.clock(), os.clock()
		local budget = FIRST_SLICE
		local phase = "Scanning"
		local function tick(progress)
			if me.cancel or App.area ~= area then
				return false
			end
			if os.clock() - slice > budget then
				budget = SLICE
				if App.showProgress then
					App.showProgress(phase, progress)
				end
				task.wait()
				slice = os.clock()
				if me.cancel or App.area ~= area then
					return false
				end
			end
			return true
		end
		local trace
		local success, err = xpcall(function()
			if App.analysisDirty or not App.lastAnalysis then
				local an, aborted = Engine.analyze(area, templates(), tick)
				if aborted then
					return
				end
				App.lastAnalysis = an
				App.analysisDirty = false
				lastPrint, worldEdited = worldPrint(), false
				from = nil
				App.refreshScan()
				recolorOverlay()
			end
			if from and not table.find(area.layers, from) then
				from = nil
			end
			if me.live then
				local copies, parts = Engine.estimate(area, App.lastAnalysis, G.density)
				if parts > HEAVY_PARTS then
					App.heavyWarning = { copies = copies, parts = parts, area = area }
					return
				end
			end
			App.heavyWarning = nil
			phase = "Placing"
			local counts, total, parts = Engine.generate(area, App.lastAnalysis, G.density, templates(), {
				from = from,
				region = me.region,
				output = { walk = G.walk, shadows = G.shadows, query = G.query, chunks = G.chunks, ghost = G.ghost },
				tick = tick,
			})
			if counts then
				App.lastCounts, App.lastTotal, App.lastParts = counts, total, parts
				me.done = true
				lostPatch = nil
			end
		end, function(e)
			trace = debug.traceback(tostring(e), 2)
			return e
		end)
		job = nil
		if not me.done and App.area == area then
			lostPatch = (me.region and lostPatch ~= true) and joinBoxes(lostPatch, me.region) or true
		end
		if App.showProgress then
			App.showProgress(nil)
		end
		if success and not me.done then -- cancelled, or paused as too heavy: nothing changed
			local w = App.heavyWarning
			if w then
				App.status(string.format("Live update paused: about %s objects (%s parts) is too heavy.", num(w.copies), num(w.parts)), "error")
				if not heavyAsked[w.area.folder] then -- asked once per area; after that the status line says it
					heavyAsked[w.area.folder] = true
					App.dialog(
						"This would slow Studio down",
						string.format(
							"The area would get about %s objects (%s parts). Live update paused so Studio stays smooth.\n\n"
								.. "Place it anyway, or lower the amount or Size of everything first.",
							num(w.copies),
							num(w.parts)
						),
						{
							{
								"Place anyway",
								"accent",
								function()
									runGenerate(true)
								end,
							},
							{ "Keep it off", nil, function() end },
						}
					)
				end
			end
			return
		end
		local seconds = os.clock() - t0
		App.failure = not success and explainError(err) or nil
		if area and area.folder and area.folder.Parent then
			if area.folder:GetAttribute("SS_Failed") ~= App.failure then
				area.folder:SetAttribute("SS_Failed", App.failure)
			end
		end
		if success then
			local ms = seconds * 1000
			local note, heavy = App.perfNote()
			App.status(
				string.format(
					"%s objects · %s parts · %s%s",
					num(App.lastTotal),
					num(App.lastParts),
					ms < 1000 and string.format("%d ms", math.floor(ms + 0.5)) or string.format("%.1f s", ms / 1000),
					note ~= "" and ("  " .. note) or ""
				),
				heavy and "error" or nil
			)
		else
			warn("[Smart Scatter] Generate failed. Please send this to the plugin author:\n" .. tostring(trace or err))
			App.status("Generate failed: " .. App.failure .. " What you see is the last result that worked.", "error")
		end
		App.refreshCounts()
		if success and recorded and App.flashDone then
			App.flashDone(string.format("Done  ·  %s placed", num(App.lastTotal)))
		end
	end

	local function cancelJob()
		if job then
			job.cancel = true
		end
	end
	local function busy()
		return job ~= nil
	end

	local function requestLive(from)
		if not G.live or not canGenerate() then
			return
		end
		liveFrom = mergeFrom(liveFrom, from)
		if job and job.live then
			liveFrom = mergeFrom(liveFrom, job.from)
			job.cancel = true
		end
		if liveLoop then
			return
		end
		liveLoop = true
		task.spawn(function()
			while liveFrom ~= nil do
				local f = liveFrom
				liveFrom = nil
				runGenerate(false, f ~= ALL and f or nil)
			end
			liveLoop = false
		end)
	end

	local function commit(from)
		local rec = beginRec("Smart Scatter: Change settings")
		saveArea()
		endRec(rec)
		if not G.live then
			return
		end
		local f = mergeFrom(liveFrom, from)
		if job and job.live then
			f = mergeFrom(f, job.from)
		end
		liveFrom = nil
		task.spawn(function()
			runGenerate(true, f ~= ALL and f or nil)
		end)
	end

	local function switchArea(folder)
		cancelJob()
		App.area = folder and Engine.loadArea(folder) or nil
		App.failure = App.area and App.area.folder:GetAttribute("SS_Failed") or nil -- its last Generate failed
		App.expanded = nil
		App.lastAnalysis, App.analysisDirty, App.lastCounts, App.lastTotal, App.lastParts = nil, true, {}, 0, 0
		App.paintLayer = nil
		if App.area then -- what's already placed, counted per layer from its output folder
			for _, f in App.area.folder:GetChildren() do
				local key = f:GetAttribute("SS_Key")
				for _, l in App.area.layers do
					if key == Engine.layerKey(l) or (not key and f.Name == l.inst.Name) then
						local n = 0
						for _, d in f:GetDescendants() do
							if d:GetAttribute("SS_Type") then
								n += 1
							end
							if d:IsA("BasePart") then
								App.lastParts += 1
							end
						end
						App.lastCounts[l] = n
						App.lastTotal += n
						break
					end
				end
			end
		end
		if App.setMode and App.mode ~= "Off" and (not App.area or App.area.locked) then
			App.setMode("Off") -- nothing to paint on, or not allowed to
		end
		rebuildOverlay(true)
		if App.drawSpline then
			App.drawSpline()
		end
		if App.rebuildAll then
			App.rebuildAll()
		end
		if App.refreshCounts then
			App.refreshCounts()
		end
	end

	local function newArea(opts)
		local clear = opts and opts.kind == "Clear"
		local n = #Engine.listAreas() + 1
		while Engine.getOut():FindFirstChild("Area " .. n) do
			n += 1
		end
		local rec = beginRec(clear and "Smart Scatter: New Keep-clear Zone" or "Smart Scatter: New Area")
		local a = Engine.createArea((clear and "Keep clear " or "Area ") .. n, nil)
		a.folder:SetAttribute("SS_Kind", clear and "Clear" or "Scatter")
		endRec(rec)
		G.page = "" -- its home tab: where its first step is
		switchArea(a.folder)
		if not (opts and opts.keepMode) then
			App.setMode("Paint")
		end
		App.status(clear and "Paint where nothing should go." or "Paint the ground where things should go.")
	end

	local function deleteArea()
		if not App.area then
			return
		end
		local rec = beginRec("Smart Scatter: Delete Area")
		local surface = Engine.roadOf(App.area)
		if surface then
			surface.Parent = nil -- its road goes with it
		end
		App.area.folder.Parent = nil
		endRec(rec)
		switchArea(Engine.listAreas()[1])
		App.status("Area deleted. Ctrl+Z brings it back.")
	end

	local thumbCache = {} -- [inst] = { [px] = ViewportFrame }
	local function eachThumb(fn)
		for _, bySize in thumbCache do
			for _, vp in bySize do
				fn(vp)
			end
		end
	end
	local function thumbnail(inst, px)
		px = px or 36
		thumbCache[inst] = thumbCache[inst] or {}
		local vp = thumbCache[inst][px]
		if vp then
			return vp
		end
		vp = new("ViewportFrame", {
			Size = UDim2.fromOffset(px, px),
			BackgroundColor3 = P.raised,
			Ambient = Color3.fromRGB(170, 168, 160),
			LightColor = Color3.new(1, 1, 1),
			LightDirection = Vector3.new(-1, -2, -0.6),
		}, { corner(8), stroke(P.line) })
		pcall(function()
			local c = Engine.copyOf(inst)
			if c:IsA("BasePart") then
				local m = Instance.new("Model")
				c.Parent = m
				c = m
			end
			for _, d in c:GetDescendants() do
				if d:IsA("LuaSourceContainer") then
					d:Destroy()
				end
			end
			c.Parent = vp
			local cf, size = c:GetBoundingBox()
			local cam = new("Camera", { FieldOfView = 35, Parent = vp })
			vp.CurrentCamera = cam
			local dist = (size.Magnitude / 2) / math.tan(math.rad(17.5)) * 1.02
			cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(1, 0.6, 1).Unit * dist, cf.Position)
		end)
		thumbCache[inst][px] = vp
		return vp
	end

	App.saveArea = saveArea
	App.canGenerate = canGenerate
	App.runGenerate = runGenerate
	App.cancelJob = cancelJob
	App.busy = busy
	App.requestLive = requestLive
	App.commit = commit
	App.switchArea = switchArea
	App.newArea = newArea
	App.deleteArea = deleteArea
	App.thumbCache = thumbCache
	App.eachThumb = eachThumb
	App.thumbnail = thumbnail
end
end)()
-- #module Panel/Header
MODULES["Panel/Header"] = (function()
--[[
	Smart Scatter — Header: the area picker and its menu, the "new" menu, surface marking, dialogs, shared helpers.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local Selection, beginRec, endRec = App.Selection, App.beginRec, App.endRec
	local Engine, G, num, P, SANS, SANS_M = App.Engine, App.G, App.num, App.P, App.SANS, App.SANS_M
	local SANS_B, new, corner, stroke, pad, vlist, box = App.SANS_B, App.new, App.corner, App.stroke, App.pad, App.vlist, App.box
	local label, hoverable, hintOn, flushRows, saveArea = App.label, App.hoverable, App.hintOn, App.flushRows, App.saveArea
	local canGenerate, runGenerate, switchArea, newArea = App.canGenerate, App.runGenerate, App.switchArea, App.newArea
	local deleteArea = App.deleteArea


	local function closePopup()
		if App.ui.popup then
			App.ui.popup:Destroy()
			App.ui.popup = nil
		end
	end

	local function openAreaMenu(pick)
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
		if pick then
			local head = box({ Size = UDim2.new(1, 0, 0, 24), ZIndex = 52, Parent = menu }, { pad(10, 10, 0, 0) })
			label(pick.title, 11, P.faint, SANS_B, { Size = UDim2.fromScale(1, 1), ZIndex = 52, Parent = head })
			for _, f in Engine.listAreas() do
				if f ~= (App.area and App.area.folder) and f:GetAttribute("SS_Kind") ~= "Clear" then
					item(f.Name, function()
						pick.onPick(f)
					end)
				end
			end
			item("Cancel", function() end, P.dim)
			return
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
			if App.kindOf(App.area) ~= "Clear" and #Engine.listAreas() > 1 then
				item("Copy settings from…", function()
					task.defer(openAreaMenu, {
						title = "COPY PATTERN, EDGES, COLOURS AND OBJECTS FROM",
						onPick = function(f)
							local src = Engine.loadArea(f)
							Engine.copyLook(src, App.area)
							App.addLayers(Engine.layersFromJSON(Engine.layersToJSON(src.layers, false)), f.Name)
							App.rebuildAll()
						end,
					})
				end, P.dim)
			end
			if App.kindOf(App.area) ~= "Clear" then
				item("Clear placed objects", function()
					local rec = beginRec("Smart Scatter: Clear")
					Engine.clearOutputs(App.area)
					endRec(rec)
					App.lastCounts, App.lastTotal = {}, 0
					App.refreshCounts()
					App.status("Cleared. The area and objects are kept; Generate brings it all back.")
				end, P.dim)
			end
			item("Bake to plain models", function()
				local a = App.area
				local n = Engine.roadOf(a) and 1 or 0
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

	local function heading(parent, text, gapTop)
		box({ Size = UDim2.new(1, 0, 0, gapTop or 8), Parent = parent })
		label(string.upper(text), 11, P.faint, SANS_B, { Size = UDim2.new(1, 0, 0, 20), Parent = parent })
	end

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
		item("area", "Scatter area", "Paint ground, fill it with objects", newArea, P.accent)
		item("spline", "Path", "Draw a curve: roads, fences, lamps", function()
			App.newSplineFn()
		end, P.accent)
		item("clear", "Keep-clear zone", "Paint where nothing may go: spawns, doors", function()
			newArea({ kind = "Clear" })
		end, P.danger)
	end

	local iconButton = App.iconButton

	local function buildHeader(parent)
		local kind = App.kindOf(App.area)
		label(kind and KIND[kind].title or "SMART SCATTER", 11, P.faint, SANS_B, {
			Size = UDim2.new(1, 0, 0, 20),
			Parent = parent,
		})
		box({ Size = UDim2.new(1, 0, 0, 4), Parent = parent })
		local row = box({ Size = UDim2.new(1, 0, 0, 36), Parent = parent })
		local pick = new("TextButton", {
			Text = "",
			BackgroundColor3 = P.raised,
			AutoButtonColor = false,
			Size = UDim2.new(1, -44, 1, 0),
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
		pick.MouseButton1Click:Connect(function()
			openAreaMenu()
		end)
		hintOn(pick, "Your areas and paths: switch, rename, lock, bake or delete.")
		local plus = iconButton("plus", "New scatter area or path", function(b)
			openNewMenu(b)
		end, false, 36)
		plus.Position = UDim2.new(1, -36, 0, 0)
		plus.Parent = row
		App.ui.plusBtn = plus
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
end)()
-- #module Panel/AreaTools
MODULES["Panel/AreaTools"] = (function()
--[[
	Smart Scatter — AreaTools: what an area is made of, as the controls the tabs put in their cards: the ground's
	paint tools and clean-up, its pattern, colour zones and wind, the path with its curve and road, fixing the scan,
	and the welcome shown before there are any areas. Each builder fills the body it's given.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local beginRec, endRec, Engine, G, saveG, refreshFilter = App.beginRec, App.endRec, App.Engine, App.G, App.saveG, App.refreshFilter
	local P, SANS, SANS_M, new, corner, stroke, vlist = App.P, App.SANS, App.SANS_M, App.new, App.corner, App.stroke, App.vlist
	local box, col, label, para = App.box, App.col, App.label, App.para
	local pad, SANS_B, icon = App.pad, App.SANS_B, App.icon
	local button, buttonRow = App.button, App.buttonRow
	local hintOn, slider, switchRow, segmented = App.hintOn, App.slider, App.switchRow, App.segmented
	local rebuildOverlay, saveArea, runGenerate, requestLive = App.rebuildOverlay, App.saveArea, App.runGenerate, App.requestLive
	local commit, heading, NICE, TOOLS, TOOL_HINT = App.commit, App.heading, App.NICE, App.TOOLS, App.TOOL_HINT
	local FILTER_SURFACES, maskOp, primaryButton = App.FILTER_SURFACES, App.maskOp, App.primaryButton
	local setIconColor, keyChips = App.setIconColor, App.keyChips
	local chip, chipGrid = App.chip, App.chipGrid

	local function gap(parent, h)
		box({ Size = UDim2.new(1, 0, 0, h), Parent = parent })
	end

	local function buildPaintTools(parent)
		local grid = chipGrid(parent, 3, 36)
		local ICON = { Brush = "brush", Lasso = "lasso", Box = "box", Polygon = "polygon", Fill = "fill" }
		local cells = {}
		local function cell(iconName, text, color, hint, onClick)
			local b = new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = P.raised, Parent = grid }, { corner(8) })
			local st = stroke(P.line)
			st.Parent = b
			local row = box({ Size = UDim2.fromScale(1, 1), Parent = b }, {
				new("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 6),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
			})
			local ic = icon(iconName, 14, P.dim)
			ic.Parent = row
			local t = label(text, 12, P.dim, SANS_B, { Size = UDim2.fromOffset(0, 16), AutomaticSize = Enum.AutomaticSize.X, Parent = row })
			hintOn(b, hint)
			b.MouseButton1Click:Connect(onClick)
			App.pressable(b, 0.96)
			local lit = App.glow(b, 8, 0.6)
			local c = { hot = false }
			c.paint = function(on)
				lit:set(on)
				b.BackgroundColor3 = on and color:Lerp(P.card, 0.85) or (c.hot and P.hover or P.raised)
				st.Color = on and color:Lerp(P.card, 0.5) or P.line
				local fg = on and color or (c.hot and P.text or P.dim)
				setIconColor(ic, fg)
				t.TextColor3 = fg
			end
			b.MouseEnter:Connect(function()
				c.hot = true
				c.look()
			end)
			b.MouseLeave:Connect(function()
				c.hot = false
				c.look()
			end)
			table.insert(cells, c)
			return c
		end
		for _, t in TOOLS do
			local c = cell(ICON[t], t, P.accent, t .. ": " .. (TOOL_HINT[t] or ""), function()
				if (App.mode == "Paint" or App.mode == "Erase") and G.tool == t then
					App.setMode("Off")
				else
					App.setTool(t)
				end
			end)
			c.look = function()
				c.paint(G.tool == t and App.mode == "Paint")
			end
		end
		local er = cell("erase", "Erase", P.danger, "Erase: take ground out of the area (Shift does it while painting).", function()
			App.setMode(App.mode == "Erase" and "Paint" or "Erase")
		end)
		er.look = function()
			er.paint(App.mode == "Erase")
		end
		local function refresh()
			for _, c in cells do
				c.look()
			end
		end
		refresh()
		App.ui.refreshMode = refresh
		keyChips(parent, {
			{ "Shift", "erase" },
			{ App.keyText("size"), "size" },
			{ App.keyText("shrink") .. " " .. App.keyText("grow"), "step" },
			{ App.keyText("cancel"), "stop" },
		})
		hintOn(
			button("Fill selected parts", nil, function()
				App.fillSelection()
			end, { Parent = buttonRow(parent) }),
			"Select parts or models in the Explorer (an island, a roof, a platform), then click: their tops join the area and count as ground."
		)
		local brushOpts = col({ Parent = parent }, { vlist(6) })
		slider(
			"Brush size",
			4,
			200,
			function()
				return G.radius
			end,
			function(v)
				G.radius = v
			end,
			"%.0f studs",
			1,
			nil,
			saveG,
			"Radius of the brush. While painting, press F and move the mouse to set it (click to keep), or step it with [ and ].",
			24
		).Parent =
			brushOpts
		segmented({ "Circle", "Square" }, function()
			return G.shape
		end, function(v)
			G.shape = v
		end, function()
			saveG()
		end).Parent =
			brushOpts
		local fillOpts = col({ Parent = parent }, { vlist(6) })
		slider("Reach", 16, 400, function()
			return G.fillReach
		end, function(v)
			G.fillReach = v
		end, "%.0f studs", 4, nil, saveG, "How far a fill can spread from where you click.", 120).Parent =
			fillOpts
		local function showTool()
			brushOpts.Visible = G.tool == "Brush"
			fillOpts.Visible = G.tool == "Fill"
		end
		showTool()
		App.ui.refreshTool = function()
			refresh()
			showTool()
		end
	end

	local function areaSlider(parent, key, text, min, max, fmt, step, hint, def)
		slider(
			text,
			min,
			max,
			function()
				return App.area and App.area[key] or def
			end,
			function(v)
				if App.area then
					App.area[key] = v
				end
			end,
			fmt,
			step,
			function()
				requestLive()
			end,
			function()
				commit()
			end,
			hint,
			def
		).Parent =
			parent
	end
	local function areaChoice(parent, key, title, options, hints, def, onPick)
		label(title, 13, P.text, SANS, { Parent = parent })
		local grid = chipGrid(parent, #options > 4 and 3 or 4, 30)
		for i, name in options do
			local c = chip(grid, name, function()
				return (App.area and App.area[key] or def) == name
			end, function()
				if App.area and App.area[key] ~= name then
					App.area[key] = name
					if onPick then
						onPick(App.area)
					end
					commit()
					App.rebuildAll()
				end
			end)
			c.LayoutOrder = i
			hintOn(c, hints[name])
		end
	end
	local function showing(strengthKey, amount)
		return function(a)
			if (a[strengthKey] or 0) <= 0 then
				a[strengthKey] = amount
			end
		end
	end

	local function buildEdges(parent)
		areaSlider(
			parent,
			"edge",
			"Soft edges",
			0,
			48,
			"%.0f studs",
			1,
			"Thins things out toward the border so the area fades into its surroundings.",
			12
		)
	end

	local function buildPattern(parent)
		areaChoice(parent, "pattern", "Pattern", Engine.PATTERNS, Engine.PATTERN_HINT, "Groves", showing("patches", 0.6))
		areaSlider(
			parent,
			"patches",
			"Pattern strength",
			0,
			1,
			"%.0f%%",
			0.05,
			"How much the pattern shapes the area: every object thickens and thins in the same places. 0% is off.",
			0
		)
		areaSlider(parent, "patchSize", "Pattern size", 16, 240, "%.0f studs", 4, "How big the pattern's patches, spots or rows are.", 60)
	end

	local function buildZones(parent)
		areaChoice(parent, "zoneMood", "Mood", Engine.ZONE_MOODS, Engine.ZONE_HINT, "Autumn", showing("zones", 0.5))
		areaSlider(
			parent,
			"zones",
			"Strength",
			0,
			1,
			"%.0f%%",
			0.05,
			"Tints every object by the pattern: the open, thin parts take on this mood, the thick parts keep their colours. 0% is off.",
			0
		)
	end

	local function buildWind(parent)
		areaSlider(
			parent,
			"windDir",
			"Wind direction",
			0,
			359,
			"%.0f°",
			5,
			'The way objects with "Lean with the wind" lean (0° leans toward +Z).',
			0
		)
	end

	local function buildPaintFilter(parent)
		local fHead = box({ Size = UDim2.new(1, 0, 0, 30), Parent = parent })
		local fLabel = label("", 13, P.text, SANS, { Size = UDim2.new(1, -110, 1, 0), Parent = fHead })
		hintOn(fHead, "Only paint or erase over these surfaces, e.g. just the grass between roads. None picked means any surface.")
		local chips = chipGrid(parent, 4, 30)
		local refreshers = {}
		local function refreshHead()
			fLabel.Text = App.paintFilterOn and "Paint only on" or "Paint only on · any"
		end
		for _, cls in FILTER_SURFACES do
			local _, look = chip(chips, NICE[cls] or cls, function()
				return G.paintOn[cls] == true
			end, function()
				G.paintOn[cls] = not G.paintOn[cls] or nil
				refreshFilter()
				saveG()
				refreshHead()
			end)
			table.insert(refreshers, look)
		end
		button("Any surface", "ghost", function()
			table.clear(G.paintOn)
			refreshFilter()
			saveG()
			for _, f in refreshers do
				f()
			end
			refreshHead()
		end, { Size = UDim2.fromOffset(0, 26), Position = UDim2.new(1, 0, 0, 2), AnchorPoint = Vector2.new(1, 0), Parent = fHead })
		refreshHead()
	end

	local function buildTidy(parent)
		local tools = buttonRow(parent, 6)
		for _, t in
			{
				{ "Fill holes", "holes", "Fills gaps enclosed by the area." },
				{ "Smooth", "smooth", "Rounds jagged edges and removes specks." },
				{ "Grow", "grow", "Expands the area by one cell all around." },
				{ "Shrink", "shrink", "Pulls the edge in by one cell." },
			}
		do
			local b = button(t[1], nil, function()
				maskOp(t[2], t[1])
			end, { Parent = tools })
			hintOn(b, t[3])
		end
		if App.area and App.area.count > 0 then
			local armed = 0
			local clr
			clr = button("Erase all paint", "danger", function()
				if not App.area or App.area.count == 0 then
					return
				end
				if os.clock() - armed > 3 then
					armed = os.clock()
					clr.Text = "Click again to erase"
					task.delay(3, function()
						if os.clock() - armed >= 2.9 then
							clr.Text = "Erase all paint"
						end
					end)
					return
				end
				armed = 0
				local rec = beginRec("Smart Scatter: Erase area")
				App.area.rows, App.area.count = {}, 0
				Engine.clearOutputs(App.area)
				saveArea()
				endRec(rec)
				App.analysisDirty = true
				App.lastCounts, App.lastTotal = {}, 0
				rebuildOverlay()
				App.rebuildAll()
				App.status("Area erased. Objects and settings are kept, paint a new one.")
			end, { Parent = buttonRow(parent) })
			hintOn(clr, "Removes all painted ground in this area and what was placed on it. Your objects stay. Ctrl+Z brings it back.")
		end
	end

	local function hasPath()
		return App.area ~= nil and App.area.spline ~= nil and #App.area.spline.pts > 0
	end

	local function buildDrawTools(parent)
		local drawBtn = primaryButton("Draw path", function()
			if App.mode == "Spline" then
				App.setMode("Off")
			else
				App.ensureSplineFn()
				App.setMode("Spline")
			end
		end)
		drawBtn.Parent = parent
		hintOn(
			drawBtn,
			"Click to add points or hold and drag to draw. Drag a point to move it. Select a point and click the ground to branch off. Drop an end on a point or curve to join them; on the first point to close a loop."
		)
		App.ui.refreshSplineBtn = function()
			local editing = App.mode == "Spline"
			drawBtn.Text = editing and "Done" or (hasPath() and "+  Keep drawing" or "+  Draw path")
			drawBtn:SetAttribute("secondary", editing)
			drawBtn.BackgroundColor3 = editing and P.raised or P.accent
			drawBtn.TextColor3 = editing and P.text or P.onAccent
		end
		App.ui.refreshSplineBtn()
		keyChips(parent, { { "Shift", "height" }, { App.keyText("corner"), "corner" }, { App.keyText("delete"), "delete" } })
		App.ui.splineInfo = para("", { Parent = parent })
		App.refreshSplineInfo()
		if hasPath() then
			local clearBtn = button("Clear path", "danger", function()
				if not hasPath() then
					return
				end
				App.clearSplineFn(beginRec("Smart Scatter: Clear spline"))
				App.rebuildAll()
			end, { Parent = buttonRow(parent) })
			hintOn(clearBtn, "Removes every point and branch. Ctrl+Z brings them back.")
		end

		local pointBox = col({ Parent = parent }, { vlist(4) })
		App.ui.refreshPoint = function()
			for _, c in pointBox:GetChildren() do
				if c:IsA("GuiObject") then
					c:Destroy()
				end
			end
			local q = App.selectedPoint and App.selectedPoint()
			if not q then
				return
			end
			local card = col(
				{ BackgroundTransparency = 0, BackgroundColor3 = P.raised, Parent = pointBox },
				{ corner(10), stroke(P.line), pad(12, 12, 10, 10), vlist(2) }
			)
			label("SELECTED POINT", 11, P.faint, SANS_B, { Parent = card })
			local function pointSlider(key, text, hint)
				return slider(
					text,
					0.2,
					3,
					function()
						return q[key] or 1
					end,
					function(v)
						q[key] = math.abs(v - 1) > 1e-3 and v or nil
					end,
					"%.2f×",
					0.05,
					function()
						App.drawSpline()
					end,
					function()
						App.commitSplineFn(beginRec("Smart Scatter: Spline point"))
					end,
					hint,
					1
				)
			end
			local sp = App.area and App.area.spline
			if sp and (sp.width or 0) > 0 then
				pointSlider("w", "Width here", "Widens or narrows the strip at this point; it eases into the next point.").Parent = card
			end
			pointSlider(
				"s",
				"Scale here",
				"Makes things near this point bigger or smaller (spaced copies and posts; end-to-end pieces keep their length)."
			).Parent =
				card
			switchRow("Sharp corner  (C)", function()
				return q.sharp == true
			end, function() end, function()
				App.pointAction("sharp")
			end, "Straight lines into and out of this point, like a fence corner. Smooth points get handles to bend the curve.").Parent =
				card
			local acts = buttonRow(card)
			if q.h then
				hintOn(
					button("Reset handles", nil, function()
						App.pointAction("resetHandle")
					end, { Parent = acts }),
					"Forgets how you bent the curve here; it goes back to the automatic smooth shape."
				)
			end
			button("Delete point", "danger", function()
				App.pointAction("delete")
			end, { Parent = acts })
		end
		App.ui.refreshPoint()
	end

	local function spGet(k, d)
		return function()
			local sp = App.area and App.area.spline
			if sp then
				return sp[k]
			end
			return d
		end
	end
	local function spSet(k)
		return function(v)
			App.ensureSplineFn()[k] = v
		end
	end

	local function buildCurve(parent)
		slider(
			"Strip width",
			0,
			200,
			spGet("width", 0),
			spSet("width"),
			"%.0f studs",
			2,
			function()
				App.drawSpline()
			end,
			function()
				if App.area and App.area.spline then
					App.commitSplineFn(beginRec("Smart Scatter: Spline width"))
				end
			end,
			"0 keeps it a line for fences and rows. Wider makes a strip: your scatter objects fill it, or it becomes the road when Build a road is on.",
			0
		).Parent =
			parent
		gap(parent, 4)
		local function toggle(text, key, def, rec, hint)
			switchRow(text, spGet(key, def), spSet(key), function()
				if App.area and App.area.spline then
					App.commitSplineFn(beginRec("Smart Scatter: " .. rec))
				end
			end, hint).Parent =
				parent
		end
		toggle(
			"Snap to surfaces",
			"snap",
			true,
			"Spline snap",
			"On: things hug the ground, walls or ceilings under the curve. Off: they sit exactly on the curve, e.g. lanterns on a cable in the air."
		)
		toggle(
			"Points on walls",
			"walls",
			false,
			"Spline walls",
			"Off: a click on a wall drops the point onto the ground below. On: points can sit on walls and ceilings (vines, cables)."
		)
		toggle("Closed loop", "closed", false, "Spline loop", "Joins the last point back to the first, e.g. a fence around a field.")
	end

	local function buildScanFix(parent)
		local markHead = box({ Size = UDim2.new(1, 0, 0, 30), Parent = parent })
		hintOn(
			markHead,
			"The scan guesses what each part is from its material and name, to keep things off roads, out of water and off roofs. If it guesses wrong, select the part and mark it."
		)
		label("MARK SELECTED AS", 11, P.faint, SANS_B, { Size = UDim2.new(1, -120, 1, 0), Parent = markHead })
		hintOn(
			button("Remove mark", "ghost", function()
				App.markSelected(nil)
			end, { Size = UDim2.fromOffset(0, 26), Position = UDim2.new(1, 0, 0, 2), AnchorPoint = Vector2.new(1, 0), Parent = markHead }),
			"Lets the scan guess again for the selected parts."
		)
		local marks = chipGrid(parent, 4, 30)
		for _, cls in { "Road", "Path", "Building", "Water" } do
			local c = chip(marks, cls, nil, function()
				App.markSelected(cls)
			end)
			hintOn(c, "Select parts, models or meshes in the Explorer or viewport, then click to mark them as " .. string.lower(cls) .. ".")
		end
		gap(parent, 4)
		App.ui.scanText = para("", { Parent = parent })
		hintOn(
			button("Rescan", nil, function()
				App.analysisDirty = true
				rebuildOverlay(true)
				runGenerate(true)
			end, { Parent = buttonRow(parent) }),
			"Reads the ground again, e.g. after you moved a house or added a road, then regenerates."
		)
	end

	local function buildRoad(parent)
		local function surf()
			local sp = App.ensureSplineFn()
			sp.surface = sp.surface or { on = false, style = "Asphalt", thick = 1 }
			return sp.surface
		end
		local function roadOn()
			local sp = App.area and App.area.spline
			return sp ~= nil and sp.surface ~= nil and sp.surface.on == true
		end
		local function roadCommit(name)
			if App.area and App.area.spline then
				App.commitSplineFn(beginRec("Smart Scatter: " .. name))
			end
		end
		switchRow(
			"Build a road",
			roadOn,
			function(v)
				local sf = surf()
				sf.on = v
				sf.width = sf.width or 12 -- its own width: the strip around it stays as it is
				if not v then -- the road goes now, even when nothing else is left to generate
					local road = Engine.roadOf(App.area)
					if road then
						Engine.dropOutput(road)
					end
				end
			end,
			function()
				roadCommit("Road")
				App.rebuildAll()
			end,
			"Lays a solid road or path down the middle of the curve; the strip beside it still gets filled. Bends, slopes, junctions and per-point widths stay seamless, and scattered objects keep off it."
		).Parent =
			parent
		if roadOn() then
			local grid = chipGrid(parent, 4, 32)
			for i, st in Engine.ROAD_STYLES do
				chip(grid, st.name, function()
					return (App.area.spline.surface.style or "Asphalt") == st.name
				end, function()
					surf().style = st.name
					roadCommit("Road style")
					App.rebuildAll()
				end, st.color).LayoutOrder =
					i
			end
			slider(
				"Road width",
				2,
				80,
				function()
					return Engine.roadWidth(App.area.spline)
				end,
				function(v)
					surf().width = v
				end,
				"%d studs",
				1,
				function() end,
				function()
					roadCommit("Road width")
				end,
				"How wide the road is. Widen the strip past it to fill the ground on either side.",
				12
			).Parent =
				parent
			slider(
				"Thickness",
				0.2,
				4,
				function()
					return surf().thick or 1
				end,
				function(v)
					surf().thick = v
				end,
				"%.1f studs",
				0.1,
				function() end,
				function()
					roadCommit("Road thickness")
				end,
				"How deep the road is. Thicker hides uneven ground at the edges.",
				1
			).Parent =
				parent
		end
	end

	local function buildWelcome(parent)
		new("ImageLabel", { Image = App.LOGO.mark, BackgroundTransparency = 1, Size = UDim2.fromOffset(48, 48), Parent = parent })
		gap(parent, 6)
		local title = label("Fill your map by rules, not by hand.", 18, P.text, SANS_B, { Parent = parent })
		title.TextWrapped = true
		title.TextTruncate = Enum.TextTruncate.None
		title.AutomaticSize = Enum.AutomaticSize.Y
		title.Size = UDim2.new(1, 0, 0, 0)
		gap(parent, 2)
		para("Pick what you want to make. You can have as many of each as you like.", { Parent = parent }).TextColor3 = P.dim
		gap(parent, 12)
		local function choice(iconName, title, text, examples, onClick)
			local b = new("TextButton", {
				Text = "",
				AutoButtonColor = false,
				BackgroundColor3 = P.card,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Parent = parent,
			}, { corner(14), pad(14, 14, 14, 14) })
			local st = stroke(P.line)
			st.Parent = b
			local badge = box({
				BackgroundTransparency = 0,
				BackgroundColor3 = P.accent:Lerp(P.card, 0.86),
				Size = UDim2.fromOffset(36, 36),
				Parent = b,
			}, { corner(9), stroke(P.accent:Lerp(P.card, 0.8)) })
			local ic = icon(iconName, 18, P.accent)
			ic.AnchorPoint = Vector2.new(0.5, 0.5)
			ic.Position = UDim2.fromScale(0.5, 0.5)
			ic.Parent = badge
			local txt = col({ Position = UDim2.fromOffset(48, 0), Size = UDim2.new(1, -48, 0, 0), Parent = b }, { vlist(4) })
			label(title, 14, P.text, SANS_B, { Size = UDim2.new(1, 0, 0, 18), Parent = txt })
			para(text, { Parent = txt }).TextColor3 = P.dim
			local tags = buttonRow(txt, 5)
			for _, e in examples do
				local tag = label(e, 11, P.dim, SANS_M, {
					Size = UDim2.fromOffset(0, 22),
					AutomaticSize = Enum.AutomaticSize.X,
					BackgroundTransparency = 0,
					BackgroundColor3 = P.raised,
					Parent = tags,
				})
				corner(6).Parent = tag
				pad(8, 8, 0, 0).Parent = tag
			end
			App.shadow(b, 14)
			App.pressable(b, 0.985)
			local lit = App.glow(b, 14, 0.5) -- lights up under the mouse
			b.MouseEnter:Connect(function()
				st.Color = P.accentLine
				b.BackgroundColor3 = P.card:Lerp(P.hover, 0.4)
				lit:set(true)
			end)
			b.MouseLeave:Connect(function()
				st.Color = P.line
				b.BackgroundColor3 = P.card
				lit:set(false)
			end)
			b.MouseButton1Click:Connect(onClick)
			return b
		end
		App.ui.welcomeChoice = choice(
			"area",
			"Scatter area",
			"Paint a patch of ground and fill it. Things keep off roads, water and roofs by themselves.",
			{ "Forests", "Flower fields", "Rocks", "Rubble" },
			App.newArea
		)
		gap(parent, 10)
		choice("spline", "Path", "Draw a curve and line it. It follows hills and bends round corners without gaps.", {
			"Fences",
			"Street lamps",
			"Tiled paths",
			"Roads",
		}, function()
			App.newSplineFn()
		end)
		gap(parent, 20)
		heading(parent, "How it works", 0)
		for i, s in
			{
				{ "Shape", "Paint the ground, or draw a path." },
				{ "Objects", "Pick models from the Explorer." },
				{ "Generate", "Everything is placed, and updates as you tweak." },
			}
		do
			local row = box({ Size = UDim2.new(1, 0, 0, 30), Parent = parent })
			local n = label(tostring(i), 10, P.faint, SANS_B, {
				Size = UDim2.fromOffset(16, 16),
				Position = UDim2.fromOffset(0, 7),
				TextXAlignment = Enum.TextXAlignment.Center,
				Parent = row,
			})
			corner(8).Parent = n
			local st = stroke(P.faint)
			st.Thickness = 1.5
			st.Parent = n
			label(s[1], 13, P.text, SANS_B, { Position = UDim2.fromOffset(26, 0), Size = UDim2.new(0, 70, 1, 0), Parent = row })
			label(s[2], 12, P.dim, SANS, { Position = UDim2.fromOffset(96, 0), Size = UDim2.new(1, -96, 1, 0), Parent = row })
		end
	end

	local function shapeKey()
		local a = App.area
		if not a then
			return "none"
		end
		return tostring((a.count or 0) > 0) .. tostring(a.spline ~= nil and #a.spline.pts >= 2) .. tostring(#a.layers > 0)
	end
	local pending = false
	local function stale()
		return G.page ~= "Settings" and App.ui.builtShape ~= nil and App.ui.builtShape ~= shapeKey()
	end
	App.checkShape = function()
		if pending or not stale() then
			return
		end
		pending = true
		task.defer(function()
			pending = false
			if stale() then
				App.rebuildAll()
			end
		end)
	end
	App.shapeKey = shapeKey

	App.refreshScan = function()
		if not App.ui.scanText then
			return
		end
		local an = App.lastAnalysis
		if not an or App.analysisDirty or an.maskCells == 0 then
			App.ui.scanText.Text = (App.area and App.area.count > 0) and "Not scanned yet." or "Paint over the ground to mark an area."
			return
		end
		local list = {}
		for cls, n in an.stats do
			if cls ~= "None" then
				table.insert(list, { cls, n / an.maskCells })
			end
		end
		table.sort(list, function(a, b)
			return a[2] > b[2]
		end)
		local parts = {}
		for i = 1, math.min(4, #list) do
			if list[i][2] >= 0.01 then
				table.insert(parts, string.format("%s %d%%", NICE[list[i][1]] or list[i][1], math.floor(list[i][2] * 100 + 0.5)))
			end
		end
		App.ui.scanText.Text = table.concat(parts, "  ·  ")
	end

	App.hasPath = hasPath
	App.buildPaintTools = buildPaintTools
	App.buildTidy = buildTidy
	App.buildPaintFilter = buildPaintFilter
	App.buildEdges = buildEdges
	App.buildPattern = buildPattern
	App.buildZones = buildZones
	App.buildWind = buildWind
	App.buildDrawTools = buildDrawTools
	App.buildCurve = buildCurve
	App.buildRoad = buildRoad
	App.buildScanFix = buildScanFix
	App.buildWelcome = buildWelcome
end
end)()
-- #module Panel/ObjectTools
MODULES["Panel/ObjectTools"] = (function()
--[[
	Smart Scatter — ObjectTools: the area's objects (each one model or a mix of models, with its rules) as the
	controls the tabs put in their cards: the list with adding and objects whose model went missing, one object's
	settings (a card per rule), biomes, presets, the performance report and removing single copies.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local Selection, FAST, tween, Engine, G, saveG, num = App.Selection, App.FAST, App.tween, App.Engine, App.G, App.saveG, App.num
	local P, SANS, SANS_M, SANS_B, new, corner, stroke = App.P, App.SANS, App.SANS_M, App.SANS_B, App.new, App.corner, App.stroke
	local pad, vlist, hlist, box, col, label, para = App.pad, App.vlist, App.hlist, App.box, App.col, App.label, App.para
	local hintOn, slider, switch, switchRow, segmented = App.hintOn, App.slider, App.switch, App.switchRow, App.segmented
	local recolorOverlay, rebuildOverlay, canGenerate, requestLive, commit =
		App.recolorOverlay, App.rebuildOverlay, App.canGenerate, App.requestLive, App.commit
	local newArea, eachThumb, thumbnail = App.newArea, App.eachThumb, App.thumbnail
	local beginRec, endRec, button, buttonRow, explain = App.beginRec, App.endRec, App.button, App.buttonRow, App.explain
	local chip, chipGrid, stepLabel, NICE = App.chip, App.chipGrid, App.stepLabel, App.NICE

	local rowRefs = {} -- [layer] = { name, kind (list row), sub (settings page) }: labels refreshCounts keeps current

	local function gap(parent, h)
		box({ Size = UDim2.new(1, 0, 0, h), Parent = parent })
	end
	local function showObject(l)
		if App.LAYER_MODES[App.mode] then
			App.setMode("Off")
		end
		App.expanded = l
		if App.heatLayer and App.heatLayer ~= l then -- the heatmap belongs to the object whose page it was
			App.heatLayer = nil
			rebuildOverlay()
		end
		App.rebuildAll()
	end
	local function modelRow(parent, inst, text, actions)
		local row = box({ Size = UDim2.new(1, 0, 0, 32), Parent = parent })
		local th = thumbnail(inst, 28)
		th.Position = UDim2.fromOffset(0, 2)
		th.Parent = row
		label(text, 13, P.text, SANS_M, { Position = UDim2.fromOffset(36, 0), Size = UDim2.new(1, -170, 1, 0), Parent = row })
		local right = box({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 1),
			Size = UDim2.fromOffset(0, 30),
			AutomaticSize = Enum.AutomaticSize.X,
			Parent = row,
		}, {
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 6),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		for i, a in actions or {} do
			button(a[1], a[2], a[3], { LayoutOrder = i, Parent = right })
		end
		return row
	end

	local function controls(l)
		local s, D = l.s, Engine.defaults(l.type)
		local c = {}
		local function reheat() -- the heatmap follows the rules as they change
			if App.heatLayer == l then
				recolorOverlay()
			end
		end
		function c.live()
			requestLive(l)
			reheat()
		end
		function c.done()
			commit(l)
			reheat()
		end
		function c.changed(rebuild) -- a change the page must be redrawn for (other controls appear or go)
			c.live()
			c.done()
			if rebuild then
				App.refreshObjects()
			end
		end
		function c.S(parent, key, text, min, max, fmt, step, hint) -- a slider for s[key], right-click resets it
			slider(text, min, max, function()
				return s[key]
			end, function(v)
				s[key] = v
			end, fmt, step, c.live, c.done, hint, D[key]).Parent =
				parent
		end
		function c.SW(parent, key, text, hint, rebuild) -- an on/off switch for s[key]
			switchRow(text, function()
				return s[key]
			end, function(v)
				s[key] = v
			end, function()
				c.changed(rebuild)
			end, hint).Parent =
				parent
		end
		function c.PICK(parent, title, key, options, hint, rebuild) -- a labelled choice for s[key]
			stepLabel(parent, nil, title)
			segmented(options, function()
				return s[key]
			end, function(v)
				s[key] = v
			end, function()
				c.changed(rebuild)
			end).Parent =
				parent
			if hint then
				explain(parent, hint)
			end
		end
		return c
	end

	local function buildBasics(l, cs, c)
		cs.add({
			id = "placement",
			title = "Placement",
			sub = "Spread out or along a line, how much, and what it is",
			build = function(parent)
				local s = l.s
				local line = Engine.isLine(l)
				segmented(Engine.PLACES, function()
					return s.place
				end, function(v)
					if v == "Along" and s.place ~= "Along" then
						local sp = App.area and App.area.spline
						Engine.smartLine(l, sp ~= nil and #sp.pts >= 2)
					else
						s.place = v
					end
				end, function()
					commit()
					App.refreshObjects()
				end).Parent =
					parent
				explain(
					parent,
					line and "Along: copies follow a line (a road edge, the area's border or a path), like lamps or a fence."
						or "Scatter: copies spread over the painted area, following the rules below."
				)
				gap(parent, 6)
				if not line then
					c.S(parent, "density", "Amount", 0, 4, "%.2f×", 0.05, "How much of this object to place. 1× is the smart default for its type.")
					gap(parent, 4)
				end
				stepLabel(parent, nil, "Type")
				segmented(Engine.TYPES, function()
					return l.type
				end, function(t)
					Engine.setType(l, t)
				end, function()
					commit()
					App.refreshObjects()
				end).Parent =
					parent
				explain(parent, "What it is. Sets sensible defaults for spacing, slopes and what it keeps away from.")
				gap(parent, 6)
				c.SW(
					parent,
					"locked",
					"Lock placement",
					"Keeps every copy of this object exactly where it is when the area regenerates. Changes still save; unlock to see them."
				)
			end,
		})
	end

	local function buildLine(l, parent, c)
		local s = l.s
		parent.add({
			id = "line",
			title = "Line",
			keys = "follow side orientation roll fit end to end post gap stagger facing axis",
			more = false,
			build = function(b)
				local follows = table.clone(Engine.FOLLOWS)
				if (App.area and App.area.spline and #App.area.spline.pts > 0) or s.follow == "Spline" then
					table.insert(follows, "Spline")
				end
				c.PICK(
					b,
					"Follow",
					"follow",
					follows,
					s.follow == "Spline" and "Follows this area's path."
						or s.follow == "Border" and "Runs around the edge of the painted area, e.g. a fence around a field."
						or ("Runs along " .. string.lower(s.follow) .. " inside the painted area (found by the scan)."),
					true
				)
				local onSpline = s.follow == "Spline"
				if onSpline then
					gap(b, 4)
					c.PICK(
						b,
						"Side",
						"side",
						Engine.SIDES,
						"Center puts copies on the curve itself, turned toward the nearest road; the others set them beside it, e.g. lamps along both sides of a road.",
						true
					)
					gap(b, 4)
					c.PICK(
						b,
						"Orientation",
						"orient",
						Engine.ORIENTS,
						"Upright stands straight (lamps, posts). Surface sticks to what's under it (moss on walls, lights on a ceiling). Follow bends with the curve up and down (bridge planks, rails, pipes)."
					)
					c.S(b, "roll", "Roll", 0, 360, "%.0f°", 5, "Turns each copy around the direction of the curve.")
				end
				gap(b, 4)
				if not onSpline then
					c.S(b, "offset", "Distance from it", 0, 40, "%.0f studs", 0.5, "Gap between the edge you follow and the side of each copy.")
				elseif s.side ~= "Center" then
					c.S(b, "offset", "Distance from the curve", 0, 60, "%.0f studs", 0.5, "How far to the side of the path each copy sits.")
				end
				c.SW(
					b,
					"fit",
					"Line up end to end",
					"Resizes each piece so they meet with no gaps or overlaps, even on bends: fences, walls, path tiles, rails.",
					true
				)
				if not s.fit and Engine.looksLikeSegment(l) then
					local row = col({ Parent = b }, { vlist(4) })
					label("Pieces don't meet. Resize them to fit?", 12, P.dim, SANS, { Parent = row })
					button("Resize pieces to fit", "accent", function()
						s.fit = true
						c.changed(true)
					end, { Parent = buttonRow(row) })
				end
				if s.fit then -- an optional post model at every joint and both ends
					if l.post then
						modelRow(b, l.post.inst, "Post: " .. l.post.inst.Name, {
							{
								"Remove",
								"danger",
								function()
									Engine.setPost(l, nil)
									c.changed(true)
								end,
							},
						})
					else
						hintOn(
							button("Add selected as post", nil, function()
								local sel = Selection:Get()[1]
								if not sel or sel == l.inst or not Engine.setPost(l, sel) then
									App.status("Select a post or pillar model in the Explorer first.")
									return
								end
								App.status("Posts go at every joint and both ends.")
								c.changed(true)
							end, { Parent = buttonRow(b) }),
							"Optional: a separate post model placed at every joint and at both ends. Without one, a fence whose model has a post on one end only gets matching end posts automatically."
						)
					end
				else
					c.S(b, "interval", "Gap between", 2, 150, "%.0f studs", 1, "Distance from one copy to the next along the line.")
					c.S(b, "jitter", "Unevenness", 0, 1, "%.0f%%", 0.05, "0% is perfectly even. Higher shifts copies back and forth along the line.")
					if not onSpline or s.side == "Both" then
						c.SW(b, "stagger", "Stagger the two sides", "Copies on opposite sides sit between each other instead of facing pairs.")
					end
				end
				c.S(
					b,
					"skip",
					"Leave gaps",
					0,
					0.9,
					"%.0f%%",
					0.05,
					"How much is left out, in real openings: stretches of fence with gaps between them, never a lone piece. Posts only stand where there's fence."
				)
				if not s.fit then -- end-to-end pieces always run along the line
					gap(b, 4)
					c.PICK(
						b,
						"Facing",
						"facing",
						Engine.FACINGS,
						"Face it turns the front (−Z side) toward the edge, like a lamp over a road. Along lines the long side up with it.",
						true -- the axis picker below reads differently for "Along"
					)
				end
				gap(b, 4)
				local alongAxis = s.fit or s.facing == "Along"
				c.PICK(
					b,
					alongAxis and "Axis along the line" or "Model's front",
					"front",
					Engine.FRONTS,
					alongAxis and "Which of the model's axes runs down the line, and so sets the piece length. Auto uses the longer side."
						or "Which side of the model is its front, the side that faces the edge (a lantern's glass, a sign's face). Auto uses the side the model reaches out to (a lamp's arm), otherwise -Z, Roblox's front."
				)
				c.S(b, "maxCount", "Limit", 0, 2000, "%.0f", 10, "Maximum number of copies. 0 means no limit.")
			end,
		})
	end

	local function buildModels(l, parent, c)
		parent.add({
			id = "variants",
			title = "Models",
			keys = "swap mix share",
			more = false,
			build = function(b)
				for _, v in l.variants do
					local actions = {
						{
							"Swap",
							nil,
							function()
								local pick = Selection:Get()[1]
								local old = v.inst.Name
								if not (pick and Engine.swapVariant(l, table.find(l.variants, v), pick)) then
									App.status("Select the model to swap in, in the Explorer, then click Swap.")
									return
								end
								App.status(string.format("Swapped %s for %s. Copies stay on the same spots where they fit.", old, pick.Name))
								commit(l)
								App.refreshObjects()
							end,
						},
					}
					if #l.variants > 1 then
						table.insert(actions, {
							"Remove",
							"danger",
							function()
								Engine.removeVariant(l, table.find(l.variants, v))
								commit()
								App.refreshObjects()
							end,
						})
					end
					modelRow(b, v.inst, v.inst.Name, actions)
					if #l.variants > 1 then
						slider("Share", 0, 10, function()
							return v.w
						end, function(x)
							v.w = x
						end, "%.1f", 0.5, c.live, c.done, "How often this model is picked compared to the others in this object.", 1).Parent =
							b
					end
					slider("Size", 0.3, 3, function()
						return v.size
					end, function(x)
						v.size = x
					end, "%.2f×", 0.05, c.live, c.done, "Size of this model on top of the object's size range.", 1).Parent =
						b
				end
				if l.missing then
					para(
						string.format(
							"%d more model%s not found in this place. %s kept, and come%s back when found again.",
							#l.missing,
							#l.missing == 1 and "" or "s",
							#l.missing == 1 and "It's" or "They're",
							#l.missing == 1 and "s" or ""
						),
						{ Parent = b }
					)
				end
				gap(b, 4)
				hintOn(
					button("Add selected as models", nil, function()
						local added = 0
						for _, sel in Selection:Get() do
							for _, inst in sel:IsA("Folder") and sel:GetChildren() or { sel } do
								if Engine.addVariant(l, inst) then
									added += 1
								end
							end
						end
						if added == 0 then
							App.status("Select more models in the Explorer to mix them into this object.")
							return
						end
						App.status(string.format("Added %d model%s to %s.", added, added == 1 and "" or "s", l.inst.Name))
						commit(l)
						App.refreshObjects()
					end, { Parent = buttonRow(b) }),
					"Select models (or a folder of them) in the Explorer, then click: they mix into this object, e.g. pine, oak and birch in one forest."
				)
			end,
		})
	end

	local function buildLayerPaint(l, parent, more)
		parent.add({
			id = "layerpaint",
			title = "Paint or place this object",
			keys = "brush more less clear place pins",
			more = more,
			build = function(b)
				local seg, refresh = segmented({ "More", "Less", "Clear", "Place" }, function()
					return App.paintLayer == l and App.mode or nil
				end, function(m)
					App.setMode(m, l)
				end, nil, nil, true)
				seg.Parent = b
				explain(
					b,
					"Brush over the area: More adds, Less thins out (twice removes), Clear undoes your painting. Place puts copies down right where you brush; Shift takes them away."
				)
				App.ui.refreshLayerBrush = refresh
				if l.pins then
					gap(b, 4)
					button(string.format("Remove %d placed by hand", #l.pins), "ghost", function()
						l.pins = nil
						commit(l)
						App.refreshObjects()
					end, { Parent = buttonRow(b) })
				end
				if l.paint then
					gap(b, 4)
					button("Reset painting", nil, function()
						l.paint = nil
						if App.paintLayer == l then
							recolorOverlay()
						end
						commit(l)
						App.refreshObjects()
					end, { Parent = buttonRow(b) })
				end
			end,
		})
	end

	local function buildSize(l, parent, c)
		local s = l.s
		parent.add({
			id = "size",
			title = "Size",
			keys = "smallest largest young edges scale",
			more = false,
			build = function(b)
				if Engine.isLine(l) and s.fit then -- pieces that join up all share one size
					slider("Size", 0.2, 4, function()
						return (s.scaleMin + s.scaleMax) / 2
					end, function(v)
						s.scaleMin, s.scaleMax = v, v
					end, "%.2f×", 0.05, c.live, c.done, "Size of every piece. Pieces that join end to end all share one size.", 1).Parent =
						b
				else
					c.S(b, "scaleMin", "Smallest", 0.2, 4, "%.2f×", 0.05, "Smallest random size a copy can be.")
					c.S(b, "scaleMax", "Largest", 0.2, 4, "%.2f×", 0.05, "Largest random size. Bigger copies land in the middle of clumps.")
					c.S(
						b,
						"edgeYoung",
						"Young at the edges",
						0,
						1,
						"%.0f%%",
						0.05,
						"Smaller copies toward the area's edge and its clearings, like the young fringe of a real forest."
					)
				end
			end,
		})
	end

	local function buildSpread(parent, c)
		parent.add({
			id = "spread",
			title = "Spread",
			keys = "spacing clumping clump room limit",
			more = false,
			build = function(b)
				c.S(b, "spacing", "Spacing", 0.3, 3, "%.2f×", 0.05, "Gap between copies of this object, relative to their size.")
				c.S(b, "clearance", "Room for others", 0, 2, "%.2f×", 0.05, "Lower lets other objects tuck in close, e.g. bushes under trees.")
				c.S(b, "cluster", "Clumping", 0, 1, "%.0f%%", 0.05, "0% spreads evenly. 100% groups copies into patches.")
				c.S(b, "clumpSize", "Clump size", 0.3, 4, "%.2f×", 0.05, "How big the patches are when clumping.")
				c.S(b, "maxCount", "Limit", 0, 2000, "%.0f", 10, "Maximum number of copies. 0 means no limit.")
			end,
		})
	end

	local function buildGroups(l, parent, c)
		local s = l.s
		parent.add({
			id = "groups",
			title = "Groups",
			keys = "piles stack tightness",
			more = true,
			build = function(b)
				c.SW(
					b,
					"groups",
					"Place in small groups",
					"Copies gather in little piles (barrels, crates, rocks, bushes) with space between piles, instead of spreading one by one.",
					true
				)
				if not s.groups then
					return
				end
				c.S(b, "groupMin", "Smallest group", 1, 12, "%.0f", 1, "Fewest pieces in one pile.")
				c.S(b, "groupMax", "Largest group", 1, 12, "%.0f", 1, "Most pieces in one pile.")
				c.S(b, "tight", "Tightness", 0.9, 2.5, "%.2f×", 0.05, "1× means pieces touch. Higher leaves a small gap between them.")
				local flat = false
				for _, v in l.variants do
					flat = flat or v.m.flatTop >= 0.45
				end
				if flat then
					c.S(
						b,
						"stack",
						"Stack on top",
						0,
						0.6,
						"%.0f%%",
						0.05,
						"Chance a piece sits on top of another, like crates on crates. Only on flat tops."
					)
				end
				c.SW(b, "sameModel", "Same model per group", "On: a pile is all barrels or all crates. Off: models mix inside a pile.")
			end,
		})
	end

	local function buildGrowsOn(l, parent, c)
		local s = l.s
		parent.add({
			id = "surfaces",
			title = "Grows on",
			keys = "grass sand rock snow height band",
			more = true,
			build = function(b)
				local grid = chipGrid(b, 4, 30)
				for _, cls in Engine.SURFACES do
					chip(grid, NICE[cls] or cls, function()
						return s.surfaces[cls]
					end, function()
						s.surfaces[cls] = not s.surfaces[cls]
						c.changed()
					end)
				end
				if not Engine.isLine(l) then -- the height band is a scatter rule: lines follow their edge wherever it goes
					gap(b, 6)
					c.SW(b, "useAlt", "Only within a height band", "Keeps this object to part of the area's height, e.g. rocks only up high.", true)
					if s.useAlt then
						c.S(b, "altMin", "From", 0, 1, "%.0f%%", 0.05, "Bottom of the band. 0% is the lowest ground in the area.")
						c.S(b, "altMax", "To", 0, 1, "%.0f%%", 0.05, "Top of the band. 100% is the highest ground in the area.")
					end
				end
			end,
		})
	end

	local function buildNeighbours(l, parent, c)
		local s = l.s
		parent.add({
			id = "avoid",
			title = "Keep away from",
			keys = "buildings roads water distance",
			more = true,
			build = function(b)
				c.S(b, "keepBuilding", "Buildings", 0, 60, "%.0f studs", 1, "Minimum distance from buildings and other structures.")
				c.S(b, "keepRoad", "Roads", 0, 60, "%.0f studs", 1, "Minimum distance from roads and pavement.")
				c.S(b, "keepWater", "Water", 0, 60, "%.0f studs", 1, "Minimum distance from water.")
			end,
		})
		parent.add({
			id = "attract",
			title = "Prefer near",
			keys = "hug near walls water roads face road",
			more = true,
			build = function(b)
				segmented(Engine.HUGS, function()
					return s.hug
				end, function(v)
					s.hug = v
				end, function()
					c.changed(true)
				end).Parent =
					b
				explain(b, "Pull this object toward something: bushes near trees, crates near houses.")
				if s.hug ~= "None" then
					gap(b, 4)
					c.S(b, "hugRange", "Within", 2, 80, "%.0f studs", 1, "How far the pull reaches.")
					c.S(b, "hugStrength", "Strength", 0, 1, "%.0f%%", 0.05, "100% means only near it. 0% ignores it.")
				end
				if l.type == "Building" then
					c.SW(b, "faceRoad", "Face the nearest road", "Turns the front (−Z side) of each building toward the closest road.")
				end
				local others = {}
				for _, o in App.area.layers do
					if o ~= l then
						table.insert(others, o)
					end
				end
				if #others > 0 then
					gap(b, 6)
					stepLabel(b, nil, "Near another object")
					local grid = chipGrid(b, 3, 30)
					chip(grid, "None", function()
						return s.near == ""
					end, function()
						s.near = ""
						c.changed(true)
					end)
					for _, o in others do
						local key = Engine.layerKey(o)
						chip(grid, o.inst.Name, function()
							return s.near == key
						end, function()
							s.near = key
							c.changed(true)
						end)
					end
					if s.near ~= "" then
						c.S(b, "nearRange", "Within", 2, 60, "%.0f studs", 1, "How far from that object's copies this one grows.")
						c.S(b, "nearStrength", "Strength", 0, 1, "%.0f%%", 0.05, "100% means only near it. 0% ignores it.")
					end
				end
			end,
		})
	end

	local function buildSlope(parent, c)
		parent.add({
			id = "terrain",
			title = "Slope",
			keys = "steep flat lean slope",
			more = true,
			build = function(b)
				c.S(b, "maxSlope", "Steepest", 0, 89, "%.0f°", 1, "Steepest ground this object can stand on.")
				c.S(
					b,
					"slopePref",
					"Prefers",
					-1,
					1,
					"%+.0f%%",
					0.05,
					"Below 0: mostly on flat ground (trees in the valleys). Above 0: mostly on slopes (rocks and shrubs on hillsides). 0: anywhere."
				)
				c.S(b, "align", "Lean with the ground", 0, 1, "%.0f%%", 0.05, "0% stands straight up. 100% tilts with the slope.")
			end,
		})
	end

	local function buildLook(l, parent, c)
		local s = l.s
		local line = Engine.isLine(l)
		parent.add({
			id = "look",
			title = "Look",
			keys = "rotation tilt wind colour color hue saturation brightness variation details sink lift",
			more = true,
			build = function(b)
				if not line then
					c.PICK(b, "Rotation", "yawMode", Engine.YAW_MODES, nil, true)
					if s.yawMode == "Fixed" then
						gap(b, 4)
						c.S(b, "yaw", "Fixed angle", 0, 359, "%.0f°", 5, "The direction every copy faces.")
					end
				end
				if not (line and s.fit) then -- joined pieces stay true so their joints meet
					c.S(b, "tilt", "Random tilt", 0, 45, "%.0f°", 1, "Random lean for a less uniform look.")
					c.S(
						b,
						"lean",
						"Lean with the wind",
						0,
						30,
						"%.0f°",
						1,
						"Every copy leans the same way, like windswept trees. The direction is the area's Wind setting."
					)
				end
				gap(b, 4)
				c.SW(
					b,
					"vary",
					"Variation",
					"Every copy a little different: its own hue, saturation and brightness, on part colours, SurfaceAppearance meshes and decals alike; optionally with some details left out.",
					true
				)
				if s.vary then
					c.S(b, "hueVar", "Hue", 0, 0.15, "±%.0f%%", 0.005, "How far colours may drift round the colour wheel.")
					c.S(b, "satVar", "Saturation", 0, 0.5, "±%.0f%%", 0.01, "Richer or more washed-out colours.")
					c.S(b, "valVar", "Brightness", 0, 0.5, "±%.0f%%", 0.01, "Lighter or darker copies.")
					c.SW(
						b,
						"perPart",
						"Each part separately",
						"Off: one shift for the whole copy. On: every part gets its own, e.g. leaves in slightly different greens."
					)
					c.S(
						b,
						"dropDetails",
						"Leave out details",
						0,
						1,
						"%.0f%%",
						0.05,
						"Chance each detail part is left out, so copies differ in shape too. Details: parts named like Apple, Fruit, Berry, Mushroom, Moss, Detail, Extra or Optional, or marked with the attribute SS_Optional."
					)
				else
					c.S(b, "tint", "Colour shift", 0, 0.4, "%.0f%%", 0.01, "Random brightness and hue change per copy.")
				end
				c.S(
					b,
					"sink",
					"Sink or lift",
					-0.3,
					0.6,
					"%.0f%%",
					0.01,
					"Pushes copies into the ground (+) or lifts them (−), as a share of their height."
				)
			end,
		})
	end

	local function buildActions(l, parent, c)
		local actions = buttonRow(parent)
		hintOn(
			button("New look", "accent", function()
				l.s.seed = (tonumber(l.s.seed) or 0) + 1
				c.done()
			end, { Parent = actions }),
			"Rerolls just this object: new positions, same settings. The other objects stay where they are."
		)
		hintOn(
			button("Reset settings", nil, function()
				Engine.resetLayer(l)
				commit(l)
				App.refreshObjects()
			end, { Parent = actions }),
			"Puts this object's rules back to the smart defaults for its type. A line stays a line."
		)
		hintOn(
			button("Select model", nil, function()
				Selection:Set({ l.inst })
			end, { Parent = actions }),
			"Selects the source model in the Explorer."
		)
		button("Remove object", "danger", function()
			table.remove(App.area.layers, table.find(App.area.layers, l))
			commit()
			showObject(nil)
		end, { Parent = actions })
	end

	local function layerRules(l, parent, c)
		local s = l.s
		local spl = App.area and App.area.spline
		if Engine.isLine(l) and spl and #spl.pts >= 2 and (App.area.count or 0) == 0 and s.follow ~= "Spline" then
			s.follow = "Spline"
			App.saveArea()
		end
		local line = Engine.isLine(l)
		local onSpline = line and s.follow == "Spline" -- stands on the curve: ground filters and slope don't apply
		local cs = App.cards(parent, "object")
		buildBasics(l, cs, c)
		buildModels(l, cs, c)
		if line then
			buildLine(l, cs, c)
		end
		buildSize(l, cs, c)
		if not line then
			buildSpread(cs, c)
		end
		if not onSpline then
			buildLayerPaint(l, cs, true)
		end
		if not line then
			buildGroups(l, cs, c)
		end
		if not onSpline then
			buildGrowsOn(l, cs, c)
		end
		if not line then
			buildNeighbours(l, cs, c)
		end
		if not onSpline then -- on a path, Orientation decides how copies stand
			buildSlope(cs, c)
		end
		buildLook(l, cs, c)
	end

	local function layerRow(l, parent) -- an object in the list: thumbnail, name, what it is, its share, on/off
		local r = new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = P.card,
			Size = UDim2.new(1, 0, 0, 60),
			Parent = parent,
		}, { corner(12), stroke(P.line) })
		App.shade(r, 0.05)
		App.topLight(r, 0.06, 12)
		App.shadow(r, 12)
		App.pressable(r, 0.985)
		r.MouseEnter:Connect(function()
			r.BackgroundColor3 = P.card:Lerp(P.hover, 0.45)
		end)
		r.MouseLeave:Connect(function()
			r.BackgroundColor3 = P.card
		end)
		local th = thumbnail(l.inst, 44)
		th.Position = UDim2.fromOffset(8, 8)
		th.Parent = r
		local name = label(l.inst.Name .. (#l.variants > 1 and ("  +" .. (#l.variants - 1)) or ""), 13, l.s.enabled and P.text or P.faint, SANS_B, {
			Position = UDim2.fromOffset(62, 9),
			Size = UDim2.new(1, -112, 0, 18),
			Parent = r,
		})
		local kind = label("", 12, P.dim, SANS, { Position = UDim2.fromOffset(62, 27), Size = UDim2.new(1, -112, 0, 16), Parent = r })
		local barTrack = box({
			BackgroundTransparency = 0,
			BackgroundColor3 = P.raised,
			Position = UDim2.fromOffset(62, 47),
			Size = UDim2.new(1, -112, 0, 3),
			Parent = r,
		}, { corner(2) })
		local bar = box({ BackgroundTransparency = 0, BackgroundColor3 = P.accent, Size = UDim2.fromScale(0, 1), Parent = barTrack }, { corner(2) })
		rowRefs[l] = { kind = kind, name = name, bar = bar }
		local sw = switch(function()
			return l.s.enabled
		end, function(v)
			l.s.enabled = v
		end, function()
			commit(l)
			App.refreshObjects()
		end)
		sw.Position = UDim2.new(1, -48, 0.5, -11)
		sw.ZIndex = 3
		sw.Parent = r
		hintOn(sw, "On or off, keeping its settings.")
		r.MouseButton1Click:Connect(function()
			showObject(l)
		end)
	end

	local function objectPage(l, parent)
		local head = box({ Size = UDim2.new(1, 0, 0, 44), Parent = parent })
		local th = thumbnail(l.inst, 40)
		th.Position = UDim2.fromOffset(0, 2)
		th.Parent = head
		label(l.inst.Name, 16, P.text, SANS_B, { Position = UDim2.fromOffset(52, 2), Size = UDim2.new(1, -52, 0, 22), Parent = head })
		local sub = label("", 12, P.dim, SANS, { Position = UDim2.fromOffset(52, 24), Size = UDim2.new(1, -52, 0, 16), Parent = head })
		rowRefs[l] = { sub = sub }
		local c = controls(l)
		buildActions(l, parent, c)
		if not Engine.isLine(l) then
			switchRow(
				"Show where it grows",
				function()
					return App.heatLayer == l
				end,
				function(v)
					App.heatLayer = v and l or nil
				end,
				function()
					rebuildOverlay()
				end,
				"Colours the painted area by how likely this object is to grow there with its current rules: dark is never, the accent is thickest. It follows your changes as you make them."
			).Parent =
				parent
		end
		gap(parent, 4)
		layerRules(l, parent, c)
	end

	local function addSelected()
		if not App.area then
			newArea()
		end
		local added, skipped, last = 0, nil, nil
		local function tryAdd(inst)
			for _, l in App.area.layers do
				if l.inst == inst then
					return
				end
			end
			if Engine.isGround(inst) then
				skipped = inst.Name
				return
			end
			local l = Engine.makeLayer(inst)
			if l then
				local sp = App.area.spline
				if sp and #sp.pts >= 2 then
					if App.area.count == 0 then -- a path-only area: everything follows the curve
						Engine.smartLine(l, true)
					elseif l.s.place == "Along" then -- lamps, fences in a strip: along both edges of the curve
						l.s.follow, l.s.side, l.s.offset = "Spline", "Both", math.max(l.s.offset, (sp.width or 0) / 2)
					end
				end
				table.insert(App.area.layers, l)
				added += 1
				last = l
			end
		end
		for _, sel in Selection:Get() do
			for _, inst in sel:IsA("Folder") and sel:GetChildren() or { sel } do
				tryAdd(inst)
			end
		end
		if added == 0 then
			App.status(
				skipped and ('"' .. skipped .. '" looks like ground. To make it a road, use Mark selected as.')
					or "Select models, or a folder of them, in the Explorer first."
			)
			return
		end
		App.status(added == 1 and "Added 1 object." or string.format("Added %d objects.", added))
		G.page = "Scatter"
		saveG()
		commit()
		showObject(added == 1 and last or nil) -- one new object: open it; several: show the list
	end

	local function addLayers(layers, from, note)
		if not App.area then
			newArea()
		end
		local added = 0
		for _, l in layers do
			local dup = false
			for _, o in App.area.layers do
				dup = dup or o.inst == l.inst
			end
			if not dup then
				table.insert(App.area.layers, l)
				added += 1
			end
		end
		local sp, needPath = App.area.spline, false
		for _, l in layers do
			needPath = needPath or (l.s.follow == "Spline" and Engine.isLine(l) and not (sp and #sp.pts >= 2))
		end
		App.status(
			(
				added == 0 and string.format("%s: this area already has all its objects.", from)
				or string.format("Added %d object%s from %s.", added, added == 1 and "" or "s", from)
			)
				.. (note and (" " .. note) or "")
				.. (needPath and " Some follow a path: draw one first." or "")
		)
		App.refreshObjects()
		commit()
	end
	App.addLayers = addLayers -- (the area menu's "Copy settings from…" adds objects the same way)

	local function buildBiomes(b)
		local grid = chipGrid(b, 4, 30)
		for _, biome in Engine.BIOMES do
			hintOn(
				chip(grid, biome.name, nil, function()
					local layers, missing = Engine.biomeLayers(biome)
					if #layers == 0 then
						App.status('No models with fitting names found (like "Oak Tree" or "Rock"). Try Get sample models.')
						return
					end
					local none = #missing > 0 and ("No " .. string.lower(table.concat(missing, ", ")) .. " models found.") or nil
					addLayers(layers, biome.name, none)
				end),
				"Adds a "
					.. string.lower(biome.name)
					.. " mix made from your models, found by name in ServerStorage, ReplicatedStorage and asset folders."
			)
		end
		gap(b, 4)
		hintOn(
			button("Get sample models", nil, function()
				local rec = beginRec("Smart Scatter: Sample models")
				local folder, made = Engine.makeSamples()
				endRec(rec, not made)
				Selection:Set({ folder })
				App.status(
					made and "Sample models are in ServerStorage > SmartScatter Samples, and selected. Pick a biome, or Add selected."
						or "Sample models are already in ServerStorage; selected them."
				)
			end, { Parent = buttonRow(b) }),
			"Puts a few simple trees, a bush, a flower, a rock and a crate in ServerStorage to try things with."
		)
	end

	local function buildReport(b)
		explain(b, "See which objects cost the most parts, so you know what to simplify first.")
		local out = col({ Parent = b }, { vlist(2) })
		local function show()
			out:ClearAllChildren()
			vlist(2).Parent = out
			local rows, total = Engine.report(App.area)
			if total.parts == 0 then
				para("Nothing placed yet.", { Parent = out })
				return
			end
			for _, r in rows do
				local row = box({ Size = UDim2.new(1, 0, 0, 22), Parent = out })
				label(r.name, 12, P.text, SANS_M, { Size = UDim2.new(0.45, 0, 1, 0), Parent = row })
				label(
					r.copies > 0
							and string.format(
								"%s parts · %s per copy%s",
								num(r.parts),
								num(math.ceil(r.parts / r.copies)),
								r.unique > 0 and (" · " .. r.unique .. " meshes") or ""
							)
						or (num(r.parts) .. " parts"),
					12,
					P.dim,
					SANS,
					{
						Size = UDim2.new(0.55, 0, 1, 0),
						Position = UDim2.fromScale(0.45, 0),
						TextXAlignment = Enum.TextXAlignment.Right,
						Parent = row,
					}
				)
			end
			local top = rows[1]
			local share = top.parts / total.parts
			para(
				string.format("%s parts in all.", num(total.parts))
					.. (
						#rows > 1
							and share >= 0.4
							and string.format(
								" %s is %d%% of them: a simpler model or a lower amount there helps most.",
								top.name,
								math.floor(share * 100 + 0.5)
							)
						or ""
					),
				{ Parent = out }
			)
		end
		button("Check this area", nil, show, { Parent = buttonRow(b) })
	end

	local codeBox
	local function shareCode(code)
		if not codeBox then
			return
		end
		codeBox.Text = code
		codeBox:CaptureFocus()
		codeBox.SelectionStart, codeBox.CursorPosition = 1, #code + 1
		App.status("The code is selected in the box: press Ctrl+C to copy it.")
	end
	local function buildPresets(b)
		local list = Engine.listPresets()
		if #list == 0 then
			App.emptyState(b, "No presets yet", "Save this area's objects below to reuse them in any area.")
		end
		for _, v in list do
			local row = box({ Size = UDim2.new(1, 0, 0, 36), Parent = b })
			label(v.Name, 13, P.text, SANS_M, { Size = UDim2.new(1, -220, 1, 0), Parent = row })
			local acts = box({
				Size = UDim2.new(0, 0, 1, 0),
				AutomaticSize = Enum.AutomaticSize.X,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromScale(1, 0),
				Parent = row,
			}, { hlist(6) })
			hintOn(
				button("Use", "accent", function()
					local layers, lost = Engine.layersFromJSON(v.Value)
					addLayers(layers, v.Name, #lost > 0 and string.format("%d model%s not found in this place.", #lost, #lost == 1 and "" or "s"))
				end, { Parent = acts }),
				"Adds this preset's objects to the area (ones it already has are skipped)."
			)
			hintOn(
				button("Share", nil, function()
					shareCode(Engine.presetCode(v))
				end, { Parent = acts }),
				"Puts this preset's code in the box below: copy it and paste it into another place, or send it to a teammate."
			)
			button("Delete", "danger", function()
				local rec = beginRec("Smart Scatter: Delete preset")
				v.Parent = nil
				endRec(rec)
				App.refreshObjects()
			end, { Parent = acts })
		end
		gap(b, 6)
		local saveRow = box({ Size = UDim2.new(1, 0, 0, 30), Parent = b })
		local nameBox = new("TextBox", {
			Text = "",
			PlaceholderText = "Preset name",
			Font = SANS,
			TextSize = 13,
			TextColor3 = P.text,
			PlaceholderColor3 = P.faint,
			BackgroundColor3 = P.field,
			ClearTextOnFocus = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -76, 1, 0),
			Parent = saveRow,
		}, { corner(8), stroke(P.line), pad(8, 8, 0, 0) })
		hintOn(
			button("Save", "accent", function()
				local name = string.gsub(nameBox.Text, "^%s*(.-)%s*$", "%1")
				if name == "" then
					name = App.area.folder.Name
				end
				if #App.area.layers == 0 then
					App.status("Add some objects first, then save them as a preset.")
					return
				end
				local rec = beginRec("Smart Scatter: Save preset")
				Engine.savePreset(name, App.area.layers)
				endRec(rec)
				App.status(string.format("Saved %d objects as %s.", #App.area.layers, name))
				App.refreshObjects()
			end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Parent = saveRow }),
			"Saves this area's objects and all their settings under that name. Saving an existing name replaces it."
		)
		gap(b, 8)
		label("Share code", 13, P.text, SANS, { Parent = b })
		local codeRow = box({ Size = UDim2.new(1, 0, 0, 30), Parent = b })
		codeBox = new("TextBox", {
			Text = "",
			PlaceholderText = "Paste a code here, or press Share on a preset",
			Font = SANS,
			TextSize = 12,
			TextColor3 = P.text,
			PlaceholderColor3 = P.faint,
			BackgroundColor3 = P.field,
			ClearTextOnFocus = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -76, 1, 0),
			Parent = codeRow,
		}, { corner(8), stroke(P.line), pad(8, 8, 0, 0) })
		hintOn(
			button("Import", "accent", function()
				local preset, err = Engine.importPresetCode(codeBox.Text)
				if not preset then
					App.status(err, "error")
					return
				end
				codeBox.Text = ""
				App.status(string.format("Imported %s. Press Use to add its objects to this area.", preset.Name))
				App.refreshObjects()
			end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Parent = codeRow }),
			"Saves a pasted code as a preset. Models it needs are found in this place by where they sit or their name."
		)
	end

	local function buildLost(list)
		local lost = App.area and App.area.lost
		if not (lost and #lost > 0) then
			return
		end
		local card = col(
			{ BackgroundTransparency = 0, BackgroundColor3 = P.card, Parent = list },
			{ corner(10), stroke(P.danger:Lerp(P.line, 0.5)), pad(12, 12, 10, 12), vlist(4) }
		)
		label(#lost == 1 and "1 object lost its model" or (#lost .. " objects lost their model"), 13, P.danger, SANS_B, { Parent = card })
		explain(
			card,
			"The model was moved, renamed or deleted, so nothing is placed. The settings are kept: select the model in the Explorer and press Use selected."
		)
		for i, d in lost do
			local row = col({ Parent = card }, { vlist(4) })
			label(tostring(d.p[#d.p]), 13, P.text, SANS_M, { Parent = row })
			label("was at " .. table.concat(d.p, " › "), 11, P.faint, SANS, { Parent = row })
			local acts = buttonRow(row)
			button("Use selected", "accent", function()
				local sel = Selection:Get()[1]
				if not sel or not (sel:IsA("Model") or sel:IsA("BasePart")) then
					App.status("Select the model this object should use in the Explorer first.")
					return
				end
				if Engine.relinkLost(App.area, i, sel) then
					App.status(tostring(d.p[#d.p]) .. " now uses " .. sel.Name .. ", with all its old settings.")
					commit()
				else
					App.status("That model can't be used for an object (it needs parts).")
				end
				App.refreshObjects()
			end, { Parent = acts })
			button("Remove", "danger", function()
				table.remove(App.area.lost, i)
				commit()
				App.refreshObjects()
			end, { Parent = acts })
		end
		gap(list, 8)
	end

	local function buildEverything(list)
		slider(
			"Amount of everything",
			0.1,
			3,
			function()
				return G.density
			end,
			function(v)
				G.density = v
			end,
			"%.2f×",
			0.05,
			function()
				requestLive()
			end,
			function()
				saveG()
				commit()
			end,
			"Scales how many of every object get placed, on top of each one's own amount.",
			1
		).Parent =
			list
		slider(
			"Size of everything",
			0.3,
			3,
			function()
				return App.area.size or 1
			end,
			function(v)
				App.area.size = v
			end,
			"%.2f×",
			0.05,
			function()
				requestLive()
			end,
			function()
				commit()
			end,
			"Scales every object in this area at once, on top of each one's own size. Spacing grows with it.",
			1
		).Parent =
			list
	end

	local function fillList(list)
		buildLost(list)
		if #App.area.layers == 0 then
			App.emptyState(
				list,
				"No objects yet",
				"Select models (or a folder of them) in the Explorer, then add them. Keep the originals outside the area, e.g. in ServerStorage.",
				"Add selected models",
				addSelected
			)
			return
		end
		buildEverything(list)
		gap(list, 2)
		for _, l in App.area.layers do
			layerRow(l, list)
		end
		gap(list, 2)
		hintOn(
			button("+  Add selected models", nil, addSelected, { Parent = buttonRow(list) }),
			"Select models, or a folder of them, in the Explorer. Each becomes an object you can tune."
		)
	end

	local function fillRemoveCopies(b)
		local fix = buttonRow(b)
		local pick = button("", nil, function()
			App.setMode("Remove")
		end, { Parent = fix })
		hintOn(pick, "Click placed copies in the viewport to take them out. Generating again keeps them out.")
		local function refresh()
			pick.Text = App.mode == "Remove" and "Done removing" or "Remove single copies"
		end
		refresh()
		App.ui.refreshRemoveBtn = refresh
		local n = App.area and Engine.removedCount(App.area) or 0
		if n > 0 then
			button(string.format("Bring back %d removed", n), "ghost", function()
				App.area.removed = {}
				commit()
				App.refreshObjects()
				if not G.live then
					App.status("Press Generate to bring them back.")
				end
			end, { Parent = fix })
		end
	end

	local function liveBox(parent, fill)
		local holder = col({ Parent = parent }, { vlist(8) })
		App.ui.live = App.ui.live or {}
		table.insert(App.ui.live, { holder = holder, fill = fill })
		return holder
	end

	App.refreshObjects = function()
		if App.expanded and not (App.area and table.find(App.area.layers, App.expanded)) then
			App.expanded = nil
			if App.ui.inspector then -- the open object is gone (removed, undone): back to the list
				App.rebuildAll()
				return
			end
		end
		if App.area and (App.area.relinked or 0) > 0 then
			App.status(
				string.format(
					"Found %d model%s in a new place and reconnected %s.",
					App.area.relinked,
					App.area.relinked == 1 and "" or "s",
					App.area.relinked == 1 and "it" or "them"
				)
			)
			App.area.relinked = 0
			App.saveArea()
		end
		local boxes = App.ui.live or {}
		if #boxes > 0 then
			eachThumb(function(vp) -- thumbnails are reused: take them out before the rows they sit in go
				vp.Parent = nil
			end)
			table.clear(rowRefs)
			for _, lb in boxes do
				for _, ch in lb.holder:GetChildren() do
					if ch:IsA("GuiObject") then
						ch:Destroy()
					end
				end
				if App.area then
					lb.fill(lb.holder)
				end
			end
		end
		App.refreshCounts()
	end

	App.refreshCounts = function()
		App.refreshPerf()
		App.checkShape()
		local most = 1 -- the bars are relative to the object placed most
		for l in rowRefs do
			most = math.max(most, (l.s.enabled and App.lastCounts[l]) or 0)
		end
		for l, r in rowRefs do
			if r.bar then
				local share = l.s.enabled and (App.lastCounts[l] or 0) / most or 0
				tween(r.bar, App.MED, { Size = UDim2.fromScale(share, 1) })
			end
			local n = App.lastCounts[l]
			local what = Engine.isLine(l) and ("Along " .. (l.s.follow == "Spline" and "path" or string.lower(l.s.follow))) or l.type
			local placed = (n and l.s.enabled) and ("  ·  " .. num(n) .. " placed") or ""
			if r.sub then
				r.sub.Text = (l.s.enabled and what or (what .. "  ·  off")) .. placed
			end
			if r.kind then
				r.kind.Text = l.s.enabled and (what .. placed .. (l.s.locked and " · locked" or "")) or "Off"
			end
		end
		if App.ui.genBtn and not App.busy() then -- while busy the button shows progress
			local ok, why = canGenerate()
			local failed = ok and App.failure ~= nil
			App.ui.genBtn.Text = failed and "Generate failed  ·  click to try again" or ok and "Generate" or (why or "Generate")
			tween(App.ui.genBtn, FAST, {
				BackgroundColor3 = failed and P.danger or ok and P.accent or P.raised,
				TextColor3 = ok and P.onAccent or P.faint,
			})
		end
	end

	App.showObject = showObject
	App.addSelected = addSelected
	App.liveBox = liveBox
	App.buildBiomes = buildBiomes
	App.buildReport = buildReport
	App.buildLayerPaint = buildLayerPaint
	App.objectRules = function(l, parent) -- one object's rule cards alone (search results)
		layerRules(l, parent, controls(l))
	end
	App.objectList = function(parent)
		return liveBox(parent, fillList)
	end
	App.objectInspector = function(parent)
		App.ui.inspector = liveBox(parent, function(h)
			if App.expanded then
				objectPage(App.expanded, h)
			end
		end)
		return App.ui.inspector
	end
	App.presetsBox = function(parent)
		return liveBox(parent, buildPresets)
	end
	App.removeCopiesBox = function(parent)
		return liveBox(parent, fillRemoveCopies)
	end
end
end)()
-- #module Panel/Tabs/Scatter
MODULES["Panel/Tabs/Scatter"] = (function()
--[[
	Smart Scatter — Scatter tab: what fills the area. The objects and how much of everything, or one object's rules
	when it's open; then the look of the whole area (pattern, colour zones, edges, wind), biomes, presets and the
	performance report under More options.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local vlist, col = App.vlist, App.col

	local function buildObject(page)
		App.pageHead(page, "All objects", nil, function()
			App.showObject(nil)
		end)
		App.objectInspector(col({ Parent = page }, { vlist(10) }))
	end

	App.buildScatterTab = function(page)
		local a = App.area
		if a and App.expanded and not App.searching() then
			buildObject(page)
			return
		end
		local cs = App.cards(page, "scatter")
		local kind = a and App.kindOf(a)
		if kind == "Clear" then
			cs.add({
				id = "clearzone",
				title = "Keep-clear zone",
				icon = "clear",
				sub = "Nothing from any area goes here: spawns, doorways, a quest NPC's spot",
				build = function(b)
					App.goNote(b, "This zone holds no objects. Paint where to keep clear on the Brush tab.", "Paint the zone", "Brush")
				end,
			})
			return
		end
		local shaped = a and ((a.count or 0) > 0 or App.hasPath())
		cs.add({
			id = "objects",
			title = "Objects",
			icon = "layers",
			sub = "The models that fill this area, and how much of everything",
			keys = "add models amount size everything list lost",
			build = function(b)
				if a and not shaped then
					if kind == "Path" then
						App.goNote(b, "Draw the path first, on the Map tab. Then add what lines it.", "Draw the path", "Map")
					else
						App.goNote(b, "Paint the ground first, on the Brush tab. Then add what fills it.", "Paint the area", "Brush")
					end
				end
				if a then
					App.objectList(b)
				else
					App.emptyState(b, "No area yet", "Make a scatter area or a path first: the + next to the area picker.")
				end
				App.ui.step2Card = b.Parent
			end,
		})
		if not a then
			return
		end
		local empty = #a.layers == 0
		cs.add({
			id = "biomes",
			title = "Start from a biome",
			sub = "A ready mix of objects made from your models",
			keys = "forest meadow desert town sample models",
			more = not empty,
			build = App.buildBiomes,
		})
		cs.add({
			id = "pattern",
			title = "Pattern",
			sub = "Where everything thickens and thins together",
			keys = "groves natural islands veins spots bands strength noise patches",
			more = true,
			build = App.buildPattern,
		})
		cs.add({
			id = "zones",
			title = "Colour zones",
			sub = "Tint objects by the pattern: autumn, dry, lush, frost",
			keys = "color mood autumn dry lush frost tint season",
			more = true,
			build = App.buildZones,
		})
		cs.add({
			id = "edges",
			title = "Edges and wind",
			sub = "Fade into the surroundings, and which way things lean",
			keys = "soft edges border fade wind direction lean",
			more = true,
			build = function(b)
				App.buildEdges(b)
				App.buildWind(b)
			end,
		})
		cs.add({
			id = "presets",
			title = "Presets",
			keys = "save share code import reuse",
			more = true,
			build = App.presetsBox,
		})
		cs.add({
			id = "performance",
			title = "Performance",
			sub = "Which objects cost the most parts",
			keys = "report parts meshes heavy lag simplify",
			more = true,
			build = App.buildReport,
		})
		if App.searching() then -- every object's rules too, under its name
			for i, l in a.layers do
				local holder = col({ LayoutOrder = 200000 + i, Parent = page }, { vlist(10) })
				App.label(l.inst.Name, 13, App.P.text, App.SANS_B, { Parent = holder })
				local before = App.cardCount
				App.objectRules(l, holder)
				if App.cardCount == before then
					holder:Destroy()
				end
			end
		end
	end
end
end)()
-- #module Panel/Tabs/Brush
MODULES["Panel/Tabs/Brush"] = (function()
--[[
	Smart Scatter — Brush tab: working by hand in the viewport. Paint the area's ground, brush one object more or
	less (or place copies exactly), take single copies out; then which surfaces painting sticks to and cleaning up
	the painted edge under More options.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local Engine, P, SANS = App.Engine, App.P, App.SANS
	local label, chip, chipGrid, hintOn = App.label, App.chip, App.chipGrid, App.hintOn

	local picked
	local function paintable(l)
		return not (Engine.isLine(l) and l.s.follow == "Spline")
	end
	local function buildObjectBrush(b)
		local list = {}
		for _, l in App.area.layers do
			if paintable(l) then
				table.insert(list, l)
			end
		end
		if #list == 0 then
			App.goNote(
				b,
				#App.area.layers == 0 and "Add objects on the Scatter tab first." or "Objects along a path can't be brushed.",
				#App.area.layers == 0 and "Add objects" or nil,
				"Scatter"
			)
			return
		end
		if not table.find(list, picked) then
			picked = App.paintLayer and table.find(list, App.paintLayer) and App.paintLayer or list[1]
		end
		label("Object", 13, P.text, SANS, { Parent = b })
		local grid = chipGrid(b, 3, 30)
		for i, l in list do
			local c = chip(grid, l.inst.Name, function()
				return picked == l
			end, function()
				if picked ~= l then
					if App.LAYER_MODES[App.mode] then -- the brush moves over to the new pick
						App.setMode(App.mode, l)
					end
					picked = l
					App.rebuildAll()
				end
			end)
			c.LayoutOrder = i
			hintOn(c, "Brush " .. l.inst.Name .. ".")
		end
		App.buildLayerPaint(picked, { -- its controls straight into this card
			add = function(spec)
				spec.build(b)
			end,
		})
	end

	App.buildBrushTab = function(page)
		local a = App.area
		local cs = App.cards(page, "brush")
		local kind = a and App.kindOf(a)
		if kind == "Path" then
			cs.add({
				id = "pathbrush",
				title = "Draw the path",
				icon = "spline",
				sub = "Paths are drawn, not painted",
				keys = "draw path spline points",
				build = function(b)
					App.goNote(b, "Draw and shape the path on the Map tab.", "Go to Map", "Map")
				end,
			})
		else
			local painted = a and (a.count or 0) > 0
			local card = cs.add({
				id = "paint",
				title = kind == "Clear" and "Paint the zone" or "Paint the area",
				icon = kind == "Clear" and "clear" or "brush",
				sub = kind == "Clear" and "Where nothing from any area may go"
					or painted and string.format("%s studs² painted. Keep painting, or tune what fills it.", App.num(a.count * a.cell * a.cell))
					or "Pick a tool, then paint the ground in the viewport",
				keys = "paint ground brush lasso box polygon fill erase size shape reach selected parts",
				build = App.buildPaintTools,
			})
			App.ui.step1Card = card
		end
		if a and kind ~= "Clear" then
			if kind ~= "Path" then
				cs.add({
					id = "objectbrush",
					title = "Paint one object",
					sub = "More, less or none of it where you brush; or place copies exactly",
					keys = "more less clear place pins object brush by hand",
					build = buildObjectBrush,
				})
			end
			cs.add({
				id = "removecopies",
				title = "Remove single copies",
				sub = "Click a copy that looks wrong to take it out; it stays out",
				keys = "remove delete copy copies bring back",
				build = App.removeCopiesBox,
			})
		end
		if kind ~= "Path" then
			cs.add({
				id = "paintfilter",
				title = "Paint only on",
				sub = "Painting and erasing stick to these surfaces",
				keys = "filter surfaces grass road rock sand snow",
				more = true,
				build = App.buildPaintFilter,
			})
			if a then
				cs.add({
					id = "tidy",
					title = "Tidy the edge",
					sub = "Fill holes, smooth, grow or shrink what's painted",
					keys = "fill holes smooth grow shrink erase all paint cleanup",
					more = true,
					build = App.buildTidy,
				})
			end
		end
	end
end
end)()
-- #module Panel/Tabs/Map
MODULES["Panel/Tabs/Map"] = (function()
--[[
	Smart Scatter — Map tab: the shapes on the map. The path (drawing it, its curve and its road), and telling the
	scan what the parts of the map are.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	App.buildMapTab = function(page)
		local a = App.area
		local cs = App.cards(page, "map")
		local kind = a and App.kindOf(a)
		local drawn = App.hasPath()
		if kind ~= "Clear" then
			local isPath = kind == "Path"
			local card = cs.add({
				id = "path",
				title = isPath and "Draw the path" or "Path through this area",
				icon = "spline",
				tag = not isPath and "Optional" or nil,
				sub = drawn and (isPath and "Click to add more points, or drag one to move it" or "Objects set to follow it line it")
					or (isPath and "Click in the viewport to place points" or "A road, fence or row of lamps along a curve you draw"),
				keys = "draw path spline points corner branch loop clear",
				build = App.buildDrawTools,
			})
			if isPath then
				App.ui.step1Card = card
			end
			if drawn then
				cs.add({
					id = "curve",
					title = "Curve",
					sub = "The strip beside it, and what it sticks to",
					keys = "strip width snap surfaces walls closed loop",
					build = App.buildCurve,
				})
				cs.add({
					id = "road",
					title = "Road",
					sub = "A solid road or path down the middle",
					keys = "road asphalt dirt style width thickness",
					build = App.buildRoad,
				})
			end
		end
		cs.add({
			id = "scanfix",
			title = "Fix what the scan sees",
			keys = "mark road path building water rescan",
			more = kind ~= "Clear",
			build = App.buildScanFix,
		})
	end
end
end)()
-- #module Panel/Tabs/Settings
MODULES["Panel/Tabs/Settings"] = (function()
--[[
	Smart Scatter — Settings tab: the plugin's own settings, the same in every area. Look and text size, the
	viewport overlay, game-ready output and the tour; shortcuts under More options.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local G, saveG, P, SANS, SANS_B = App.G, App.saveG, App.P, App.SANS, App.SANS_B
	local box, label, para, hlist = App.box, App.label, App.para, App.hlist
	local hintOn, switchRow, button, buttonRow, commit = App.hintOn, App.switchRow, App.button, App.buttonRow, App.commit

	local function buildLook(b)
		local swatches = App.chipGrid(b, 5, 32)
		for _, a in App.ACCENTS do
			App.chip(swatches, a.name, function()
				return G.accent == a.name
			end, function()
				if G.accent ~= a.name then
					G.accent = a.name
					saveG()
					task.defer(App.applyTheme) -- after this click finishes (the tab it's on is rebuilt)
				end
			end, Color3.fromHex(a.dark))
		end
		App.explain(b, "The accent the whole plugin wears: buttons, glow, the brush, painted ground and paths.")
		label("Text size", 13, P.text, SANS, { Parent = b })
		App.segmented({ "Small", "Normal", "Large" }, function()
			return App.TEXT_SIZES[G.textScale] or "Normal"
		end, function(v)
			for scale, name in App.TEXT_SIZES do
				if name == v then
					G.textScale = scale
				end
			end
			saveG()
			task.defer(App.rebuildAll) -- after this click finishes (the tab it's on is rebuilt)
		end).Parent =
			b
	end

	local function buildViewport(b)
		switchRow("Show overlay", function()
			return G.overlay
		end, function(v)
			G.overlay = v
		end, function()
			saveG()
			App.rebuildOverlay()
			App.drawSpline()
		end, "Shows the painted area coloured by the surface under it, and the path.").Parent =
			b
	end

	local function buildOutput(b)
		local function outSwitch(text, key, hint)
			switchRow(text, function()
				return G[key]
			end, function(v)
				G[key] = v
			end, function()
				saveG()
				commit()
			end, hint).Parent =
				b
		end
		outSwitch("Walk through plants", "walk", "Flowers and bushes get no collision, so players never snag on them.")
		outSwitch("No shadows on small stuff", "shadows", "Flowers and tiny parts skip shadows. Big win on lower-end devices.")
		outSwitch("Flowers ignore clicks", "query", "Flowers won't block raycasts, clicks, tools or weapons.")
		outSwitch(
			"Streaming chunks",
			"chunks",
			"Groups output into 128-stud models that stream in and out together, with low-detail stand-ins far away."
		)
		outSwitch(
			"Preview as boxes",
			"ghost",
			"Places a see-through box per copy instead of the model. Much faster on big areas while you tune; turn it off for the real thing."
		)
		box({ Size = UDim2.new(1, 0, 0, 4), Parent = b })
		App.ui.perf = para("", { Parent = b })
		App.refreshPerf()
	end

	local function buildShortcuts(b)
		App.explain(b, "Click a key to change it, then press the new one (Esc keeps the old). A key already in use swaps over.")
		local group
		for _, a in App.KEYMAP do
			if a.group ~= group then
				group = a.group
				label(group, 12, P.dim, SANS_B, { Size = UDim2.new(1, 0, 0, 24), Parent = b })
			end
			local row = box({ Size = UDim2.new(1, 0, 0, 32), Parent = b })
			label(a.label, 13, P.text, SANS, { Size = UDim2.new(1, -96, 1, 0), Parent = row })
			local key = button(App.keyText(a.id), nil, nil, {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, 0, 0.5, 0),
				AutomaticSize = Enum.AutomaticSize.None,
				Size = UDim2.fromOffset(84, 26),
				Font = SANS_B,
				Parent = row,
			})
			local lit = App.glow(key, 8, 0.8)
			key.MouseButton1Click:Connect(function()
				if App.capturingKey then
					return
				end
				App.capturingKey = true
				key.Text = "Press a key"
				lit:pulse(true)
				App.captureKey(key, function(k)
					App.capturingKey = false
					if not k then
						key.Text = App.keyText(a.id)
						lit:pulse(false)
						return
					end
					local moved = App.bindKey(a.id, k)
					App.status(
						moved and string.format("%s is now %s. %s moved to %s.", a.label, App.keyText(a.id), moved.label, App.keyText(moved.id))
							or string.format("%s is now %s.", a.label, App.keyText(a.id))
					)
					App.rebuildAll() -- every hint that names a key shows the new one
				end)
			end)
		end
		local fixed = label(
			"Fixed: Shift erases while painting and raises a path point while dragging; Ctrl+Z undoes; a quick right-click closes a polygon or deletes a path point.",
			12,
			P.faint,
			SANS,
			{ Parent = b }
		)
		fixed.TextWrapped, fixed.AutomaticSize, fixed.Size = true, Enum.AutomaticSize.Y, UDim2.new(1, 0, 0, 0)
		box({ Size = UDim2.new(1, 0, 0, 4), Parent = b })
		button("Reset all shortcuts", "ghost", function()
			App.resetKeys()
			App.status("Shortcuts are back to their defaults.")
			App.rebuildAll()
		end, { Parent = buttonRow(b) })
	end

	local function buildAbout(b)
		hintOn(
			button("Replay the tour", nil, function()
				App.startTour()
			end, { Parent = buttonRow(b) }),
			"A three-minute walk through everything: what it's for, areas, paths, objects and their rules, placing and finishing."
		)
		local about = box({ Size = UDim2.new(1, 0, 0, 40), Parent = b }, { hlist(10) })
		App.new("ImageLabel", { Image = App.LOGO.mark, BackgroundTransparency = 1, Size = UDim2.fromOffset(32, 32), Parent = about })
		label("Smart Scatter  v" .. tostring(App.ctx.version or "dev") .. "  ·  made by Ghulo", 12, P.faint, SANS, {
			Size = UDim2.new(1, -42, 1, 0),
			Parent = about,
		})
	end

	App.buildSettingsTab = function(page)
		local cs = App.cards(page, "settings")
		cs.add({
			id = "look",
			title = "Look",
			sub = "Accent colour and text size",
			keys = "theme accent colour color text size font",
			build = buildLook,
		})
		cs.add({ id = "viewport", title = "Viewport", sub = "What's drawn over the 3D view", keys = "overlay", build = buildViewport })
		cs.add({
			id = "output",
			title = "Game-ready output",
			keys = "collision walk shadows clicks raycast streaming chunks preview boxes ghost performance parts",
			build = buildOutput,
		})
		cs.add({
			id = "about",
			title = "Tour and about",
			sub = "A walk through everything, and the version",
			keys = "tour help version",
			build = buildAbout,
		})
		cs.add({
			id = "shortcuts",
			title = "Shortcuts",
			sub = "Every key, and changing them",
			keys = "keys keyboard keybind hotkey",
			more = true,
			build = buildShortcuts,
		})
	end
end
end)()

-- the rest of the modules are in sibling parts; an older loader that only copies Main finds them in the
-- live mirror instead
for k = 2, 16 do
	local p = script.Parent and script.Parent:FindFirstChild("Main_" .. k)
	if not p then
		local m = game:GetService("ServerStorage"):FindFirstChild("SmartScatterSource")
		p = m and m:FindFirstChild("Main_" .. k)
	end
	if not p then
		break
	end
	for k2, f in require(p) do
		MODULES[k2] = f
	end
end

--[[
	Smart Scatter — App: the plugin's panel and viewport tools, built on the Engine.

	Each module below is `return function(App) … end` and runs once, in ORDER, against one shared App table: a module
	puts its state and functions on App, and later modules read them from there. A module that returns a function
	hands back its cleanup (the last one returned runs when the plugin unloads or updates).
	  Core/        state, UI kit, cards and search, generation jobs, and the undo/cleanup wiring that runs last
	  Viewport/    what happens in the 3D view: the painted overlay, painting, the spline editor
	  Panel/       the header, the controls for areas and objects, the shell (tabs, search, bottom bar), the tour
	  Panel/Tabs/  one module per tab: Scatter, Brush, Map, Settings
	To add a module: create it in the folder it belongs to and add its path to ORDER after what it uses.
]]

local ORDER = {
	"Core/State",
	"Core/Kit",
	"Core/Cards",
	"Viewport/Overlay",
	"Core/Generation",
	"Panel/Header",
	"Panel/AreaTools",
	"Panel/ObjectTools",
	"Panel/Tabs/Scatter",
	"Panel/Tabs/Brush",
	"Panel/Tabs/Map",
	"Panel/Tabs/Settings",
	"Panel/Shell",
	"Viewport/Paint",
	"Viewport/Spline",
	"Panel/Tour",
	"Core/Lifecycle",
}

local function module(path)
	return MODULES[path]
end

-- ctx: what the loader passes in (plugin, button, widget, Engine, version…)
return function(ctx)
	local App = { ctx = ctx }
	local cleanup
	for _, path in ORDER do
		local r = module(path)(App)
		if r ~= nil then
			cleanup = r
		end
	end
	return cleanup
end
