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

	-- Undo steps: a recording when Studio grants one, otherwise classic waypoints, so every action is always undoable.
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
		if not cancel and App.historyPush then -- on the history timeline (Core/History)
			App.historyPush(h.name)
		end
	end

	local plugin = ctx.plugin
	local Engine = ctx.Engine
	local conns = {} -- long-lived connections, dropped on hot-reload
	local function track(c)
		table.insert(conns, c)
		return c
	end
	-- if a later module fails while starting, the loader calls this so nothing half-started keeps running
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

	--------------------------------------------------------------------------------
	-- Settings / state
	--------------------------------------------------------------------------------
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
		scanSelection = false, -- the map scan looks only inside the selection
		history = true, -- the history timeline over the bottom bar
		focus = true, -- the world steps back while a tool is on (Viewport/Focus)
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
	-- the logo: the mark (a sage tile of scattered dots on a curve) and the card with the name under it
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

	-- App.area: current area (Engine.loadArea / createArea)
	-- App.expanded: layer whose rules are open
	-- App.lastAnalysis: cached scan
	--------------------------------------------------------------------------------
	-- Shortcuts: every action a key can do, its default key, and the one the user picked (G.keys). Painting reads
	-- keys through this, Settings edits it, and the hints under the tools show what's bound. Shift (erase / height)
	-- and Ctrl+Z are Studio's modifiers and stay fixed.
	--------------------------------------------------------------------------------
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
	-- how a key is written on a chip
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
	-- keys that can't be bound: modifiers, and the mouse's own
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
	-- bind an action to a key; an action already on that key takes this one's old key (a swap). Returns the
	-- action that moved, if any.
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
	App.mode = "Off" -- "Paint" | "Erase" (area) · "Place" | "More" | "Less" | "None" | "Clear" (one layer) · "Off"
	-- the modes that work on one layer: "paint" changes how much of it grows where, "pins" puts copies down by hand
	local LAYER_MODES = { More = "paint", Less = "paint", None = "paint", Clear = "paint", Place = "pins" }
	-- how the one-layer brush shows them, in order; and what Shift turns each into (the opposite, as on the ground)
	App.LAYER_ORDER = { "Place", "More", "Less", "None", "Clear" }
	App.LAYER_LABEL = { Place = "Place", More = "More", Less = "Less", None = "Erase", Clear = "Reset" }
	App.LAYER_OPPOSITE = { Place = "None", More = "Less", Less = "More", None = "Clear", Clear = "None" }
	-- App.paintLayer: the layer being painted or placed

	local function num(n)
		local str = tostring(math.floor(n + 0.5))
		return (str:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
	end

	App.ui = {}

	--------------------------------------------------------------------------------
	-- Palette (the redesign): warm dark neutrals, soft raised surfaces with faint borders and ONE sage accent,
	-- dark text on the accent. A light variant follows Studio's light theme.
	--------------------------------------------------------------------------------
	local P = {} -- filled in place by makePalette, so every module can keep this one table
	-- the viewport's colours (painted ground, brush, paths): fixed per accent, the viewport isn't themed. Also
	-- filled in place, so the overlay and the path editor keep one table.
	local VIEW = {}
	local function hex(h)
		return Color3.fromHex(h)
	end
	-- accent themes: the one colour everything active wears. dark / light: the accent on each Studio theme;
	-- glow: its lighter tint (outlines in the viewport, neon edges)
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
		-- the accent theme: the accent itself, its soft fills and lines, text on it
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

	-- used by later modules
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
