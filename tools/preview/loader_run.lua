--[[
	Loader run (a dev tool): runs Loader.lua itself in the open place against the stand-in update site of
	tools/preview/server.py, and checks what its online updates do: only changed modules are downloaded, an unfinished
	download is picked up where it stopped, a cut-off file or a release that won't start never replaces the version
	that works, the plugin is asked first while its panel is open, and ctx.updates says how it went.
	The stand-ins: a plugin (settings in a table), its toolbar, button and dock widget, and a tiny App that notes its
	starts in _G.SS_LoaderRun. The loader checks every second here, and uses its own mirror folder: the installed
	plugin is left alone. Run with HttpService on for the call; returns a report. Nothing it makes stays.
]]
local HS = game:GetService("HttpService")
local URL = "http://127.0.0.1:8766/"
local function site(path)
	return HS:GetAsync(URL .. path, true)
end

local report, failed = {}, 0
local function check(name, ok, detail)
	if not ok then
		failed += 1
	end
	table.insert(report, (ok and "ok    " or "FAIL  ") .. name .. ((detail and not ok) and ("  |  " .. tostring(detail)) or ""))
end
local function waitFor(cond, seconds)
	local t = os.clock()
	while not cond() and os.clock() - t < (seconds or 8) do
		task.wait(0.1)
	end
	return cond()
end

local function signal()
	local fns = {}
	return {
		Connect = function(_, fn)
			table.insert(fns, fn)
			return { Disconnect = function() end, Connected = true }
		end,
		fire = function(...)
			for _, fn in fns do
				fn(...)
			end
		end,
	}
end

-- the loader's `script`: a folder holding the bundled trees (build 1)
local bundled = HS:JSONDecode(site("release/bundled.json"))
local scriptFolder = Instance.new("Folder")
scriptFolder.Name = "SS_LoaderRun"
scriptFolder.Archivable = false
local paths = {}
for path in bundled do
	table.insert(paths, path)
end
table.sort(paths) -- (parents before their children)
for _, path in paths do
	local parent = scriptFolder
	for part in string.gmatch(path, "[^/]+") do
		local nxt = parent:FindFirstChild(part)
		if not nxt then
			nxt = Instance.new("ModuleScript")
			nxt.Name = part
			nxt.Parent = parent
		end
		parent = nxt
	end
	parent.Source = bundled[path]
end
local run = Instance.new("ModuleScript")
run.Name = "SS_LoaderRunCode"
run.Archivable = false
run.Source = "return function(plugin, script)\n" .. site("loader.lua") .. "\nend\n"
scriptFolder.Parent = game:GetService("ServerStorage")

local store = {}
local unloading = signal()
local widget = { Enabled = false, GetPropertyChangedSignal = signal }
local plugin = {
	CreateToolbar = function()
		return {
			CreateButton = function()
				return {}
			end,
		}
	end,
	CreateDockWidgetPluginGui = function()
		return widget
	end,
	GetSetting = function(_, k)
		return store[k]
	end,
	SetSetting = function(_, k, v)
		store[k] = v
	end,
	Unloading = unloading,
}

local R = { starts = {}, stops = {} }
_G.SS_LoaderRun = R
local function status()
	local s = R.ctx and R.ctx.updates and R.ctx.updates.state() or {}
	return tostring(s.status) .. (s.detail and ("/" .. s.detail) or ""), s
end
local function asked()
	local list = string.split(site("release/asked"), "\n")
	table.sort(list)
	return table.concat(list, " ")
end
local function publish(build, how)
	site("release/set/" .. build .. "/" .. how)
end

local ok, err = pcall(function()
	publish(1, "ok")
	require(run)(plugin, scriptFolder)
	check("the bundled code starts", R.starts[1] == "t1" and R.ctx ~= nil, table.concat(R.starts, " "))
	check("the running code is handed ctx.updates", type(R.ctx.updates) == "table" and R.ctx.updates.host == "127.0.0.1:8766")
	check("nothing newer: up to date, nothing downloaded", waitFor(function()
		return status() == "current"
	end) and asked() == "", status())

	-- a newer release with the panel closed: goes straight in, only what changed comes down
	publish(2, "ok")
	check("panel closed: the update goes straight in", waitFor(function()
		return R.ctx.version == "t2"
	end) and R.ctx.reloaded == true, table.concat(R.starts, " "))
	check("only the two changed modules were downloaded", asked() == "App App/B", asked())
	check("the old version was stopped first", R.stops[1] == "t1", table.concat(R.stops, " "))
	check("the update is saved for the next start", type(store.SmartScatter_code) == "table" and store.SmartScatter_code.build == 2)
	check("then it's up to date again", status() == "current", status())

	-- panel open: the plugin is asked, once, and nothing changes until it says yes
	widget.Enabled = true
	local offers, yes = {}, nil
	R.ctx.offerUpdate = function(version, apply)
		table.insert(offers, version)
		yes = apply
	end
	publish(3, "ok")
	check("panel open: the plugin is asked", waitFor(function()
		return #offers > 0
	end) and offers[1] == "t3", table.concat(offers, " "))
	task.wait(2.5) -- (two more checks go by)
	local st, s = status()
	check("asked once, not at every check", #offers == 1, #offers)
	check("until a yes, the old version keeps running and the new one waits", R.ctx.version == "t2" and st == "ready" and s.version == "t3", st)
	asked()
	yes()
	check(
		"a yes swaps it in",
		waitFor(function()
			return R.ctx.version == "t3"
		end),
		table.concat(R.starts, " ")
	)
	check("with nothing downloaded again", asked() == "", asked())

	-- "check now" in the settings: what's found waits for the settings' own button
	widget.Enabled = true
	offers = {}
	R.ctx.offerUpdate = function(version)
		table.insert(offers, version)
	end
	publish(4, "down")
	check(
		"a site that can't be reached says so",
		waitFor(function()
			return status() == "failed/reach"
		end),
		status()
	)

	-- a module that can't be had: nothing changes, and the next try fetches only the rest
	publish(4, "fail")
	check(
		"a download that fails part-way says so",
		waitFor(function()
			return status() == "failed/download"
		end, 12),
		status()
	)
	check("and the version that works keeps running", R.ctx.version == "t3" and #offers == 0)
	widget.Enabled = false
	publish(4, "ok")
	check(
		"the next try finishes the update",
		waitFor(function()
			return R.ctx.version == "t4"
		end, 12),
		status()
	)
	check("fetching only the module that was missing", asked() == "App/B", asked())

	-- a file that arrives cut off is never run
	publish(5, "cut")
	check("a cut-off file stops the update", waitFor(function()
		return status() == "failed/download"
	end, 12) and R.ctx.version == "t4", status())

	-- a release that won't start: the one that works comes back, and it isn't tried again
	publish(6, "bad")
	check(
		"a release that won't start is given up",
		waitFor(function()
			return status() == "failed/start"
		end, 12),
		status()
	)
	check("and the version that works runs again", R.ctx.version == "t4", tostring(R.ctx.version))
	local starts = #R.starts
	task.wait(2.5)
	check("it isn't tried again at the next checks", #R.starts == starts, #R.starts - starts)
	check("what's saved is still the version that works", store.SmartScatter_code.build == 4, store.SmartScatter_code.build)

	-- the fixed release after it goes in as usual
	publish(7, "ok")
	check(
		"the release after the broken one goes in",
		waitFor(function()
			return R.ctx.version == "t7"
		end, 12),
		status()
	)
end)
check("no errors", ok, err)

-- the loader stops with its plugin
unloading.fire()
task.wait(0.2)
check("unloading stops the running code", R.stops[#R.stops] == (R.ctx and R.ctx.version))
check("and removes its mirror", game:GetService("ServerStorage"):FindFirstChild("SS_LoaderRunMirror") == nil)
scriptFolder:Destroy()
run:Destroy()
_G.SS_LoaderRun = nil
return string.format("loader run: %d failed, %d checks\n", failed, #report) .. table.concat(report, "\n")
