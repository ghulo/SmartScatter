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
	local function hex(h)
		return Color3.fromHex(h)
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
				selected = hex("2C3A2F"),
				rowSel = hex("2C3A2F"),
				line = hex("33312D"), -- borders and hairlines
				text = hex("F2EFEA"),
				dim = hex("A6A199"),
				faint = hex("7C766C"),
				accent = hex("8FBA97"),
				onAccent = hex("16221A"),
				accentSoft = hex("2E3A30"),
				accentLine = hex("4F6A55"),
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
				selected = hex("E1ECE2"),
				rowSel = hex("E1ECE2"),
				line = hex("DDD8CF"),
				text = hex("23211D"),
				dim = hex("5E5950"),
				faint = hex("8A8479"),
				accent = hex("4C8558"),
				onAccent = hex("FFFFFF"),
				accentSoft = hex("E1ECE2"),
				accentLine = hex("A9C8AE"),
				knob = hex("FFFFFF"),
				track = hex("CFCAC1"),
				danger = hex("B5533F"),
				tip = hex("FFFFFF"),
			}
		end
		for k, v in pal do
			P[k] = v
		end
		-- one accent everywhere: the old per-step colours all read as the accent
		P.green, P.orange, P.violet = P.accent, P.accent, P.accent
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
	App.SANS = SANS
	App.SANS_M = SANS_M
	App.SANS_B = SANS_B
end
