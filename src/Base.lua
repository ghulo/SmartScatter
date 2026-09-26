--[[
	Smart Scatter — Base: services, undo helpers, settings, shared state, palette and fonts.
	Part of Main; loaded in order by the bundle. Shared state and cross-module functions live on App.
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
		live = true,
		overlay = true,
		groups = {},
		walk = true,
		shadows = true,
		query = true,
		chunks = false,
		accent = "Sage", -- the accent theme (ACCENTS below)
		ghost = false, -- preview as boxes: one see-through box per copy, for quick tuning of big areas
		tool = "Brush",
		shape = "Circle",
		fillReach = 120,
		paintOn = {},
		page = "Main", -- Main (the area's steps) · Objects (its objects, or one object's settings) · Settings
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
	G.page = "Main" -- every session opens on the area's page
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
	App.analysisDirty = true
	App.lastCounts, App.lastTotal, App.lastParts = {}, 0, 0
	App.mode = "Off" -- "Paint" | "Erase" (area) · "More" | "Less" | "Clear" (paint one layer) · "Off"
	local LAYER_MODES = { More = true, Less = true, Clear = true }
	-- App.paintLayer: the layer being painted with More / Less / Clear

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
	App.VIEW = VIEW
	App.ACCENTS = ACCENTS
	App.SANS = SANS
	App.SANS_M = SANS_M
	App.SANS_B = SANS_B
end
