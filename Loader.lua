--[[
	Smart Scatter — loader (plugin root). Installed once; the code it runs updates live.

	Code sources, newest build wins:
	  1. bundled: the Engine / Main modules inside this plugin file
	  2. saved:   the last update, kept in plugin settings (so every place gets it)
	  3. online:  the release published at UPDATE_URL (manifest.json + the code files). Checked when Studio starts
	              (a newer build goes straight in) and every five minutes (the plugin asks first, then swaps it in
	              live, no restart). Everyone who has the plugin gets updates without reinstalling. Studio asks once
	              before the plugin may reach that site.
	  4. live:    ServerStorage.SmartScatterSource in the open place (for development). Never saved with the place.
	              Editing its modules and bumping its Build attribute hot-swaps the plugin instantly.
]]

local RunService = game:GetService("RunService")
if not RunService:IsEdit() then return end

local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")

local BUNDLED_BUILD = __BUILD__
local BUNDLED_VERSION = "__VERSION__"
local UPDATE_URL = "__UPDATE_URL__" -- where releases are published ("" turns online updates off)
local ICON = "rbxassetid://117898410132206" -- the Smart Scatter mark
local MIRROR = "SmartScatterSource"
local SAVED_KEY = "SmartScatter_code"
local TESTS_KEY = "SmartScatter_tests" -- the regression suite (a dev tool) lives in the mirror; kept across reloads

local toolbar = plugin:CreateToolbar("Smart Scatter")
local button = toolbar:CreateButton("SmartScatter", "Paint an area and it fills itself", ICON, "Smart Scatter")
button.ClickableWhenViewportHidden = true

local widget = plugin:CreateDockWidgetPluginGui("SmartScatterV3",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 340, 680, 300, 420))
widget.Title = "Smart Scatter"
widget.Name = "SmartScatter"
widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
-- Studio reloads the plugin when its file changes (updates); keep the panel open across reloads if it was open
if plugin:GetSetting("SmartScatter_open") == true then widget.Enabled = true end
widget:GetPropertyChangedSignal("Enabled"):Connect(function() plugin:SetSetting("SmartScatter_open", widget.Enabled) end)

-- a per-install token, so the plugin only runs live code it created itself
local token = plugin:GetSetting("SmartScatter_token")
if type(token) ~= "string" then
	token = HttpService:GenerateGUID(false)
	plugin:SetSetting("SmartScatter_token", token)
end

local function valid(c)
	return type(c) == "table" and type(c.build) == "number" and type(c.Engine) == "string" and type(c.Main) == "string"
		and (c.Parts == nil or type(c.Parts) == "table")
end

-- Main may come in parts (Main_2, Main_3…): Studio won't take a script Source of 200k+ characters from code
local function partsOf(folder)
	local parts = {}
	for _, c in folder:GetChildren() do
		if c:IsA("ModuleScript") and string.match(c.Name, "^Main_%d+$") then
			parts[c.Name] = c.Source
		end
	end
	return parts
end

local bundled = {
	build = BUNDLED_BUILD, version = BUNDLED_VERSION, Engine = script.Engine.Source, Main = script.Main.Source,
	Parts = partsOf(script),
}
local saved = plugin:GetSetting(SAVED_KEY)
local current = (valid(saved) and saved.build > bundled.build) and saved or bundled

-- run a version of the code, cleaning up the previous one first
local cleanup, holder, running -- running: the ctx of the code that's running (it may offer to update)
local function start(code, reloaded)
	if cleanup then pcall(cleanup); cleanup = nil end
	if holder then holder:Destroy() end
	holder = Instance.new("Folder")
	holder.Name = "Live"
	local e = Instance.new("ModuleScript"); e.Name = "Engine"; e.Source = code.Engine; e.Parent = holder
	local m = Instance.new("ModuleScript"); m.Name = "Main"; m.Source = code.Main; m.Parent = holder
	for name, src in code.Parts or {} do
		local p = Instance.new("ModuleScript"); p.Name = name; p.Source = src; p.Parent = holder
	end
	holder.Parent = script
	local ctx = { plugin = plugin, button = button, widget = widget, version = code.version, reloaded = reloaded }
	running = ctx
	local ok, err = pcall(function()
		ctx.Engine = require(e)
		cleanup = require(m)(ctx)
	end)
	if not ok then
		warn("[SmartScatter] v" .. tostring(code.version) .. " failed to start: " .. tostring(err))
		if ctx.abort then pcall(ctx.abort) end -- undo what started before the failure (input hooks, the panel)
		return false
	end
	return true
end

-- the live copy in the open place
local function readMirror(f)
	if not f or f:GetAttribute("Token") ~= token then return nil end
	local e, m = f:FindFirstChild("Engine"), f:FindFirstChild("Main")
	if not (e and m and e:IsA("ModuleScript") and m:IsA("ModuleScript")) then return nil end
	return {
		build = f:GetAttribute("Build") or 0, version = f:GetAttribute("Version") or "?", Engine = e.Source, Main = m.Source,
		Parts = partsOf(f),
	}
end

local function writeMirror(code)
	local f = ServerStorage:FindFirstChild(MIRROR)
	if f and f:GetAttribute("Token") ~= token then f = nil end
	if not f then
		f = Instance.new("Folder")
		f.Name = MIRROR
		f.Archivable = false -- never saved into the place, never reaches players
		f:SetAttribute("Token", token)
		local e = Instance.new("ModuleScript"); e.Name = "Engine"; e.Archivable = false; e.Parent = f
		local m = Instance.new("ModuleScript"); m.Name = "Main"; m.Archivable = false; m.Parent = f
		local suite = plugin:GetSetting(TESTS_KEY)
		if type(suite) == "string" and suite ~= "" then
			local t = Instance.new("ModuleScript"); t.Name = "Tests"; t.Archivable = false; t.Source = suite; t.Parent = f
		end
	end
	f.Engine.Source = code.Engine
	f.Main.Source = code.Main
	for _, c in f:GetChildren() do -- parts: add or update the current ones, drop any a smaller build doesn't have
		if string.match(c.Name, "^Main_%d+$") and not (code.Parts and code.Parts[c.Name]) then c:Destroy() end
	end
	for name, src in code.Parts or {} do
		local p = f:FindFirstChild(name)
		if not p then
			p = Instance.new("ModuleScript"); p.Name = name; p.Archivable = false; p.Parent = f
		end
		p.Source = src
	end
	f:SetAttribute("Version", code.version)
	f:SetAttribute("Build", code.build)
	f.Parent = ServerStorage
	return f
end

-- the suite, if one was put in the mirror, outlives the mirror (it's removed whenever the plugin reloads)
local function keepTests(f)
	local t = f and f:FindFirstChild("Tests")
	if t and t:IsA("ModuleScript") and t.Source ~= "" then pcall(plugin.SetSetting, plugin, TESTS_KEY, t.Source) end
end

local watchConn
local function watch(f)
	if watchConn then watchConn:Disconnect() end
	watchConn = f:GetAttributeChangedSignal("Build"):Connect(function()
		task.wait(0.2) -- let a multi-part edit finish
		keepTests(f)
		local code = readMirror(f)
		if not code or code.build == current.build then return end
		if start(code, true) then
			current = code
			plugin:SetSetting(SAVED_KEY, code)
		elseif current then
			start(current, false) -- bad update: fall back to the last good version
		end
	end)
end

-- online updates: the manifest names the build and each file with a checksum, so a cut-off download is never run
local function checksum(str)
	local h = 0
	for i = 1, #str do
		h = (h * 31 + string.byte(str, i)) % 1000000007
	end
	return h
end
local function fetchRelease()
	if UPDATE_URL == "" or string.sub(UPDATE_URL, 1, 2) == "__" then return nil end
	local function get(file)
		local ok, body = pcall(HttpService.GetAsync, HttpService, UPDATE_URL .. "/" .. file, true)
		return ok and body or nil
	end
	local raw = get("manifest.json")
	local ok, m = pcall(HttpService.JSONDecode, HttpService, raw or "")
	if not (ok and type(m) == "table" and type(m.build) == "number" and type(m.files) == "table") then return nil end
	if m.build <= current.build then return nil end
	local code = { build = m.build, version = tostring(m.version or m.build), Parts = {} }
	for name, entry in m.files do
		local src = type(entry) == "table" and type(entry.path) == "string" and get(entry.path)
		if not src or checksum(src) ~= entry.sum then return nil end
		if name == "Engine" or name == "Main" then code[name] = src
		elseif string.match(name, "^Main_%d+$") then code.Parts[name] = src
		else return nil end
	end
	return valid(code) and code or nil
end
local unloading = false
local offered = {} -- [build] = true once the running plugin has asked about it
local function apply(code)
	if unloading or code.build <= current.build then return end
	if start(code, true) then
		current = code
		plugin:SetSetting(SAVED_KEY, code)
		plugin:SetSetting("SmartScatter_lastBuild", code.build)
		watch(writeMirror(current))
	else
		start(current, false) -- a release that won't start: keep the version that works
	end
end
-- at boot a new release goes straight in; while working, the plugin asks first (a swap mid-stroke would lose it)
local function checkForUpdate(boot)
	local code = fetchRelease()
	if not code or unloading then return end
	local ask = not boot and running and running.offerUpdate
	if not ask then
		apply(code)
	elseif not offered[code.build] then
		offered[code.build] = true
		pcall(ask, code.version, function()
			apply(code)
		end)
	end
end

-- boot: newest of bundled / saved / live copy
local existing = readMirror(ServerStorage:FindFirstChild(MIRROR))
if existing and existing.build > current.build then current = existing end
local lastBuild = plugin:GetSetting("SmartScatter_lastBuild")
if not start(current, lastBuild ~= nil and current.build ~= lastBuild) then -- "Updated" only after a real update
	-- a version that won't start: fall back to the other good copy (bundled, or the last saved update)
	local other = current ~= bundled and bundled or (valid(saved) and saved or nil)
	if other and start(other, false) then
		current = other
	end
end
plugin:SetSetting("SmartScatter_lastBuild", current.build)
if current ~= bundled then plugin:SetSetting(SAVED_KEY, current) end
watch(writeMirror(current))

-- then look for a newer release now and every five minutes, without holding up the start
task.spawn(function()
	local boot = true
	while not unloading do
		checkForUpdate(boot)
		boot = false
		task.wait(300)
	end
end)

-- if the live copy is deleted, put it back so updates keep working
local removedConn = ServerStorage.ChildRemoved:Connect(function(c)
	if c.Name == MIRROR and not unloading and not ServerStorage:FindFirstChild(MIRROR) then
		task.defer(function()
			if not unloading then watch(writeMirror(current)) end
		end)
	end
end)

plugin.Unloading:Connect(function()
	unloading = true
	removedConn:Disconnect()
	if cleanup then pcall(cleanup) end
	if watchConn then watchConn:Disconnect() end
	local f = ServerStorage:FindFirstChild(MIRROR)
	if f and f:GetAttribute("Token") == token then
		keepTests(f)
		f:Destroy()
	end
end)
