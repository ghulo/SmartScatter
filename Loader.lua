--[[
	Smart Scatter — loader (the plugin's Script). Installed once; the code it runs updates live.

	The code is two module trees, App (the panel and tools) and Engine (placement), carried as
	code = { build, version, modules = { ["App"] = source, ["App/Core/State"] = source, …, ["Engine"] = source, … } }.
	Older releases were flattened into Engine / Main / Main_2…; those still load (see normalize).

	Code sources, newest build wins:
	  1. bundled: the App and Engine trees inside this plugin file
	  2. saved:   the last update, kept in plugin settings (so every place gets it)
	  3. online:  the release published at UPDATE_URL (release.json + the modules). Checked when Studio starts and
	              every five minutes; only the modules that changed are downloaded. With the panel closed a newer build
	              goes straight in; with it open the plugin asks first, then swaps it in live, no restart. Everyone who
	              has the plugin gets updates without reinstalling. Studio asks once before the plugin may reach that
	              site. The running code reads how that went from ctx.updates (its settings show it).
	  4. live:    ServerStorage.SmartScatterSource in the open place (for development). Never saved with the place.
	              Editing its modules and bumping its Build attribute hot-swaps the plugin instantly.
]]

local RunService = game:GetService("RunService")
if not RunService:IsEdit() then
	return
end

local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")

local BUNDLED_BUILD = __BUILD__
local BUNDLED_VERSION = "__VERSION__"
local UPDATE_URL = "__UPDATE_URL__" -- where releases are published ("" turns online updates off)
local ICON = "rbxassetid://117898410132206" -- the Smart Scatter mark
local MIRROR = "SmartScatterSource"
local SAVED_KEY = "SmartScatter_code"
local TESTS_KEY = "SmartScatter_tests" -- the regression suite (a dev tool) lives in the mirror; kept across reloads
local ENTRIES = { App = true, Engine = true, Main = true } -- Main: the App entry of a flattened (older) release

local toolbar = plugin:CreateToolbar("Smart Scatter")
local button = toolbar:CreateButton("SmartScatter", "Paint an area and it fills itself", ICON, "Smart Scatter")
button.ClickableWhenViewportHidden = true

local widget =
	plugin:CreateDockWidgetPluginGui("SmartScatterV3", DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 340, 680, 300, 420))
widget.Title = "Smart Scatter"
widget.Name = "SmartScatter"
widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
-- Studio reloads the plugin when its file changes (updates); keep the panel open across reloads if it was open
if plugin:GetSetting("SmartScatter_open") == true then
	widget.Enabled = true
end
widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	plugin:SetSetting("SmartScatter_open", widget.Enabled)
end)

-- a per-install token, so the plugin only runs live code it created itself
local token = plugin:GetSetting("SmartScatter_token")
if type(token) ~= "string" then
	token = HttpService:GenerateGUID(false)
	plugin:SetSetting("SmartScatter_token", token)
end

--------------------------------------------------------------------------------
-- Code: a map of module paths to sources, and the ModuleScript trees made from it
--------------------------------------------------------------------------------

-- any form of code -> { build, version, modules, app = the App entry's path }, or nil when it's not usable.
-- A flattened (older) release names its files Engine, Main, Main_2…: each is a root module.
local function normalize(c)
	if type(c) ~= "table" or type(c.build) ~= "number" then
		return nil
	end
	local modules = c.modules
	if modules == nil and type(c.Engine) == "string" and type(c.Main) == "string" then
		modules = { Engine = c.Engine, Main = c.Main }
		for name, src in (type(c.Parts) == "table" and c.Parts or {}) do
			modules[name] = src
		end
	end
	if type(modules) ~= "table" or type(modules.Engine) ~= "string" then
		return nil
	end
	for path, src in modules do
		if type(path) ~= "string" or type(src) ~= "string" then
			return nil
		end
	end
	local app = type(modules.App) == "string" and "App" or (type(modules.Main) == "string" and "Main") or nil
	if not app then
		return nil
	end
	return { build = c.build, version = tostring(c.version or c.build), modules = modules, app = app }
end

-- builds the ModuleScripts for code.modules under parent: a path with a source is a ModuleScript, a path that only
-- has children is a Folder
local function buildTree(modules, parent, archivable)
	local made = {}
	local function at(path)
		if made[path] then
			return made[path]
		end
		local up, name = string.match(path, "^(.*)/([^/]+)$")
		local inst = Instance.new(modules[path] and "ModuleScript" or "Folder")
		inst.Name = name or path
		inst.Archivable = archivable
		if modules[path] then
			inst.Source = modules[path]
		end
		inst.Parent = up and at(up) or parent
		made[path] = inst
		return inst
	end
	for path in modules do
		at(path)
	end
	return made
end

-- reads a tree back into { [path] = source } (the live mirror, after someone edited it)
local function readTree(root)
	local modules = {}
	for _, d in root:GetDescendants() do
		if d:IsA("ModuleScript") then
			local path, cur = d.Name, d.Parent
			while cur and cur ~= root do
				path = cur.Name .. "/" .. path
				cur = cur.Parent
			end
			local top = string.match(path, "^[^/]+")
			if ENTRIES[top] or string.match(top, "^Main_%d+$") then
				modules[path] = d.Source
			end
		end
	end
	return modules
end

local bundled = {
	build = BUNDLED_BUILD,
	version = BUNDLED_VERSION,
	modules = readTree(script),
}
local saved = normalize(plugin:GetSetting(SAVED_KEY))
bundled = normalize(bundled)
local current = (saved and saved.build > bundled.build) and saved or bundled

-- Online updates, as the running code sees them (ctx.updates). status: "off" (no update site), "checking",
-- "downloading" (version, done, of), "current", "ready" (version: downloaded, waiting for a yes) or "failed" (detail:
-- "reach" the site, "download" a module, or "start" the new version).
local ONLINE = UPDATE_URL ~= "" and string.sub(UPDATE_URL, 1, 2) ~= "__"
local update = { status = ONLINE and "checking" or "off" }
local checkForUpdate, applyReady -- (defined with the update code below)

-- run a version of the code, cleaning up the previous one first
local cleanup, holder, running -- running: the ctx of the code that's running (it may offer to update)
local function setUpdate(status, fields)
	update = fields or {}
	update.status = status
	local changed = running and running.updates and running.updates.changed -- (set by the code that shows it)
	if changed then
		task.spawn(pcall, changed)
	end
end
local function start(code, reloaded)
	if cleanup then
		pcall(cleanup)
		cleanup = nil
	end
	if holder then
		holder:Destroy()
	end
	holder = Instance.new("Folder")
	holder.Name = "Live"
	local made = buildTree(code.modules, holder, true)
	holder.Parent = script
	local ctx = { plugin = plugin, button = button, widget = widget, version = code.version, reloaded = reloaded }
	ctx.updates = {
		host = string.match(UPDATE_URL, "^%a+://([^/]+)"),
		state = function()
			return table.clone(update)
		end,
		check = function() -- look now (the answer arrives through changed)
			task.spawn(checkForUpdate, true)
		end,
		apply = function() -- swap in the release that's ready
			task.spawn(applyReady)
		end,
	}
	running = ctx
	local ok, err = pcall(function()
		ctx.Engine = require(made.Engine)
		cleanup = require(made[code.app])(ctx)
	end)
	if not ok then
		warn("[SmartScatter] v" .. tostring(code.version) .. " failed to start: " .. tostring(err))
		if ctx.abort then
			pcall(ctx.abort) -- undo what started before the failure (input hooks, the panel)
		end
		return false
	end
	return true
end

-- a plain table for plugin settings (what normalize reads back)
local function storable(code)
	return { build = code.build, version = code.version, modules = code.modules }
end

--------------------------------------------------------------------------------
-- The live copy in the open place (development)
--------------------------------------------------------------------------------
local function readMirror(f)
	if not f or f:GetAttribute("Token") ~= token then
		return nil
	end
	return normalize({ build = f:GetAttribute("Build") or 0, version = f:GetAttribute("Version"), modules = readTree(f) })
end

local function writeMirror(code)
	local f = ServerStorage:FindFirstChild(MIRROR)
	if f and f:GetAttribute("Token") ~= token then
		f = nil
	end
	if not f then
		f = Instance.new("Folder")
		f.Name = MIRROR
		f.Archivable = false -- never saved into the place, never reaches players
		f:SetAttribute("Token", token)
		local suite = plugin:GetSetting(TESTS_KEY)
		if type(suite) == "string" and suite ~= "" then
			local t = Instance.new("ModuleScript")
			t.Name = "Tests"
			t.Archivable = false
			t.Source = suite
			t.Parent = f
		end
	end
	for _, c in f:GetChildren() do -- the code is rebuilt; the suite stays
		if c.Name ~= "Tests" then
			c:Destroy()
		end
	end
	buildTree(code.modules, f, false)
	f:SetAttribute("Version", code.version)
	f:SetAttribute("Build", code.build)
	f.Parent = ServerStorage
	return f
end

-- the suite, if one was put in the mirror, outlives the mirror (it's removed whenever the plugin reloads)
local function keepTests(f)
	local t = f and f:FindFirstChild("Tests")
	if t and t:IsA("ModuleScript") and t.Source ~= "" then
		pcall(plugin.SetSetting, plugin, TESTS_KEY, t.Source)
	end
end

local watchConn
local function watch(f)
	if watchConn then
		watchConn:Disconnect()
	end
	watchConn = f:GetAttributeChangedSignal("Build"):Connect(function()
		task.wait(0.2) -- let a multi-module edit finish
		keepTests(f)
		local code = readMirror(f)
		if not code or code.build == current.build then
			return
		end
		if start(code, true) then
			current = code
			plugin:SetSetting(SAVED_KEY, storable(code))
		elseif current then
			start(current, false) -- bad update: fall back to the last good version
		end
	end)
end

--------------------------------------------------------------------------------
-- Online updates: the release lists every module with a checksum, so a cut-off download is never run
--------------------------------------------------------------------------------
local function checksum(str)
	local h = 0
	for i = 1, #str do
		h = (h * 31 + string.byte(str, i)) % 1000000007
	end
	return h
end

-- The sources of release m ({ build, version, modules = { [path] = { path = file, sum } } }): a module this install
-- already has (have[path], same checksum) is kept, one an earlier, unfinished try downloaded (kept[path]) is reused,
-- and only the rest come from get(file), told to progress(nth, of) as they go. Returns the code, or nil and the
-- module that couldn't be had.
local function gatherRelease(m, have, kept, get, progress)
	local modules, need = {}, {}
	for path, entry in m.modules do
		if type(path) ~= "string" or type(entry) ~= "table" or type(entry.path) ~= "string" or type(entry.sum) ~= "number" then
			return nil, tostring(path)
		end
		local mine, old = have[path], kept[path]
		if mine and checksum(mine) == entry.sum then
			modules[path] = mine
		elseif old and old.sum == entry.sum then
			modules[path] = old.src
		else
			table.insert(need, path)
		end
	end
	table.sort(need)
	for i, path in need do
		progress(i, #need)
		local entry = m.modules[path]
		local src = get(entry.path)
		if type(src) ~= "string" or checksum(src) ~= entry.sum then
			return nil, path
		end
		kept[path] = { sum = entry.sum, src = src }
		modules[path] = src
	end
	return { build = m.build, version = m.version, modules = modules }
end

-- a file of the release, tried again (after 1s, 2s…) when the request fails; nil and the error when it can't be had
local function httpGet(file, tries)
	local err
	for i = 1, tries do
		local ok, body = pcall(HttpService.GetAsync, HttpService, UPDATE_URL .. "/" .. file, true)
		if ok then
			return body
		end
		err = body
		if i < tries then
			task.wait(i)
		end
	end
	return nil, err
end

local unloading = false
local checking = false -- one check at a time
local ready -- a downloaded release, waiting to go in
local kept = {} -- [path] = { sum, src }: what an unfinished download got, so the next try only fetches the rest
local offered = {} -- [build] = true once the running plugin has asked about it
local broken = {} -- [build] = true for a release that wouldn't start: not tried again this session

local function apply(code)
	if unloading or code.build <= current.build then
		return
	end
	ready = nil
	if start(code, true) then
		current = code
		kept = {}
		plugin:SetSetting(SAVED_KEY, storable(code))
		plugin:SetSetting("SmartScatter_lastBuild", code.build)
		watch(writeMirror(current))
		setUpdate("current")
	else
		broken[code.build] = true
		start(current, false) -- a release that won't start: keep the version that works
		setUpdate("failed", { detail = "start", version = code.version })
	end
end
applyReady = function()
	if ready then
		apply(ready)
	end
end

-- asked: the user pressed "check now" (the settings then show what was found, with its own button). Otherwise a newer
-- release goes straight in while the panel is closed (nothing is under way); with the panel open the plugin asks
-- first, once (a swap mid-stroke would lose it).
checkForUpdate = function(asked)
	if not ONLINE or checking or unloading then
		return
	end
	checking = true
	if update.status ~= "ready" then
		setUpdate("checking")
	end
	local body, err = httpGet("release.json", 1) -- (no retries: the next check is the retry)
	local ok, m = pcall(HttpService.JSONDecode, HttpService, body or "")
	if not (ok and type(m) == "table" and type(m.build) == "number" and type(m.modules) == "table") then
		if ready then -- (what's already downloaded is still good)
			setUpdate("ready", { version = ready.version })
		else
			setUpdate("failed", { detail = "reach", error = body and "unreadable release" or tostring(err) })
		end
	elseif broken[m.build] then
		setUpdate("failed", { detail = "start", version = tostring(m.version or m.build) })
	elseif m.build <= current.build then
		ready = nil
		setUpdate("current")
	else
		local version = tostring(m.version or m.build)
		local got = gatherRelease(m, current.modules, kept, function(file)
			return (httpGet(file, 3))
		end, function(nth, of)
			setUpdate("downloading", { version = version, done = nth - 1, of = of })
		end)
		ready = got and normalize(got)
		if ready then
			setUpdate("ready", { version = ready.version })
		else
			setUpdate("failed", { detail = "download", version = version })
		end
	end
	checking = false
	if not ready or unloading then
		return
	end
	local ask = widget.Enabled and running and running.offerUpdate
	if not ask then
		applyReady()
	elseif not asked and not offered[ready.build] then
		offered[ready.build] = true
		pcall(ask, ready.version, applyReady)
	end
end

--------------------------------------------------------------------------------
-- Boot: the newest of bundled / saved / live copy
--------------------------------------------------------------------------------
local existing = readMirror(ServerStorage:FindFirstChild(MIRROR))
if existing and existing.build > current.build then
	current = existing
end
local lastBuild = plugin:GetSetting("SmartScatter_lastBuild")
if not start(current, lastBuild ~= nil and current.build ~= lastBuild) then -- "Updated" only after a real update
	-- a version that won't start: fall back to the other good copy (bundled, or the last saved update)
	local other = current ~= bundled and bundled or saved
	if other and start(other, false) then
		current = other
	end
end
plugin:SetSetting("SmartScatter_lastBuild", current.build)
if current ~= bundled then
	plugin:SetSetting(SAVED_KEY, storable(current))
end
watch(writeMirror(current))

-- then look for a newer release now and every five minutes (a minute after a download that didn't finish), without
-- holding up the start
task.spawn(function()
	while not unloading do
		checkForUpdate(false)
		task.wait(update.status == "failed" and update.detail == "download" and 60 or 300)
	end
end)

-- if the live copy is deleted, put it back so updates keep working
local removedConn = ServerStorage.ChildRemoved:Connect(function(c)
	if c.Name == MIRROR and not unloading and not ServerStorage:FindFirstChild(MIRROR) then
		task.defer(function()
			if not unloading then
				watch(writeMirror(current))
			end
		end)
	end
end)

plugin.Unloading:Connect(function()
	unloading = true
	removedConn:Disconnect()
	if cleanup then
		pcall(cleanup)
	end
	if watchConn then
		watchConn:Disconnect()
	end
	local f = ServerStorage:FindFirstChild(MIRROR)
	if f and f:GetAttribute("Token") == token then
		keepTests(f)
		f:Destroy()
	end
end)
