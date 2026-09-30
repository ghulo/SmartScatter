--[[
	Loader tests that run without Studio (tools/offline.py, part of tools/check.sh): what an online update downloads.
	LOADER holds the loader's own checksum, normalize and gatherRelease, cut out of Loader.lua by the runner, and a
	sample text with the checksum the release's side (tools/tree.py) gives it.
]]

local passed, failed = 0, {}
local function check(name, ok, detail)
	if ok then
		passed += 1
	else
		table.insert(failed, name .. (detail and ("  |  " .. detail) or ""))
	end
end
local checksum, normalize, gatherRelease = LOADER.checksum, LOADER.normalize, LOADER.gatherRelease

check("the loader and the release agree on a checksum", checksum(LOADER.sample) == LOADER.sampleSum)
check("an empty text has a checksum", checksum("") == 0)

-- a release of four modules, its files, and a site that counts what's asked of it
local SRC = { App = "return 1", ["App/Core/State"] = "return 2", ["App/Panel/New"] = "return 3", Engine = "return {}" }
local function release(build, srcs)
	local m = { build = build, version = "9." .. build, modules = {} }
	for path, src in srcs do
		m.modules[path] = { path = "modules/" .. path .. ".lua", sum = checksum(src) }
	end
	return m
end
local function site(srcs, broken)
	local asked = {}
	return function(file)
		table.insert(asked, file)
		local path = string.match(file, "^modules/(.+)%.lua$")
		if broken and broken[path] ~= nil then
			return broken[path] or nil
		end
		return srcs[path]
	end,
		asked
end
local function quiet() end

do -- a first install has nothing: every module comes down, and what's made runs as code
	local get, asked = site(SRC)
	local steps = {}
	local code = gatherRelease(release(2, SRC), {}, {}, get, function(nth, of)
		table.insert(steps, nth .. "/" .. of)
	end)
	check("with nothing to reuse, everything is downloaded", code ~= nil and #asked == 4, tostring(#asked))
	check("progress counts the downloads", table.concat(steps, " ") == "1/4 2/4 3/4 4/4", table.concat(steps, " "))
	local ok = true
	for path, src in SRC do
		ok = ok and code ~= nil and code.modules[path] == src
	end
	check("the release comes out whole", ok)
	local n = code and normalize(code)
	check("what comes out is code the loader runs", n ~= nil and n.app == "App" and n.build == 2 and n.version == "9.2")
end

do -- an update that changed one module and added one: only those two are fetched
	local new = table.clone(SRC)
	new["App/Core/State"] = "return 22"
	new["App/Panel/Extra"] = "return 5"
	local have = table.clone(SRC)
	have["App/Old"] = "return 0" -- a module the new release dropped
	local get, asked = site(new)
	local code = gatherRelease(release(3, new), have, {}, get, quiet)
	table.sort(asked)
	check(
		"only what changed is downloaded",
		table.concat(asked, " ") == "modules/App/Core/State.lua modules/App/Panel/Extra.lua",
		table.concat(asked, " ")
	)
	check("the changed module is the new one", code ~= nil and code.modules["App/Core/State"] == "return 22")
	check("an unchanged module is the one already here", code ~= nil and code.modules.Engine == have.Engine)
	check("a module the release dropped is gone", code ~= nil and code.modules["App/Old"] == nil)
end

do -- a download that fails part-way: nothing comes out, and the next try only fetches what's missing
	local kept = {}
	local get, asked = site(SRC, { ["App/Panel/New"] = false })
	local code, bad = gatherRelease(release(2, SRC), {}, kept, get, quiet)
	check("a module that can't be had stops the update", code == nil and bad == "App/Panel/New", tostring(bad))
	check("the modules before it were asked for once", #asked == 3, tostring(#asked))
	local get2, asked2 = site(SRC)
	local code2 = gatherRelease(release(2, SRC), {}, kept, get2, quiet)
	check("the next try fetches only the rest", code2 ~= nil and #asked2 <= 2 and #asked + #asked2 == 5, #asked .. " then " .. #asked2)
	check("and then the release is whole", code2 ~= nil and code2.modules["App/Panel/New"] == SRC["App/Panel/New"])
end

do -- a cut-off or stale file never gets in, and is never kept for later
	local kept = {}
	local get = site(SRC, { Engine = "return {" })
	local code, bad = gatherRelease(release(2, SRC), {}, kept, get, quiet)
	check("a file with the wrong checksum stops the update", code == nil and bad == "Engine", tostring(bad))
	check("and isn't kept", kept.Engine == nil)
	-- what was kept belongs to the release it came from: a later release with another checksum fetches again
	local newer = table.clone(SRC)
	newer.App = "return 11"
	local get2, asked2 = site(newer)
	local code2 = gatherRelease(release(3, newer), {}, kept, get2, quiet)
	table.sort(asked2)
	check(
		"a kept module of an older release isn't reused for a newer one",
		code2 ~= nil and code2.modules.App == "return 11" and table.find(asked2, "modules/App.lua") ~= nil
	)
end

do -- a release that isn't what it should be is refused before anything is asked for
	local get, asked = site(SRC)
	local m = release(2, SRC)
	m.modules.Engine = "modules/Engine.lua"
	check("a malformed release is refused", gatherRelease(m, {}, {}, get, quiet) == nil and #asked == 0)
end

if #failed > 0 then
	print(table.concat(failed, "\n"))
	error(string.format("offline loader tests: %d failed, %d passed", #failed, passed), 0)
end
print(string.format("offline loader tests: %d passed", passed))
