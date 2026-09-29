--[[
	A dev push of what's on disk into the installed plugin: rebuilds the live copy's module tree
	(ServerStorage.SmartScatterSource, App and Engine; the suite beside them stays) from tools/preview/server.py
	(/tree.json), then sets its Version and Build, and the loader hot-swaps to it. Modules added or removed on disk are
	added or removed here too. _G.SS_PushVersion = "9.88", _G.SS_PushBuild = 151.5: a plain version (as releases
	show it) and a build above the running one but below the next release's, so that release still wins.
	HttpService must be on for the call.
]]
local HS = game:GetService("HttpService")
local f = game:GetService("ServerStorage"):FindFirstChild("SmartScatterSource")
assert(f, "no live copy: is the plugin running?")
assert(_G.SS_PushVersion and _G.SS_PushBuild, "set _G.SS_PushVersion and _G.SS_PushBuild first")
local modules = HS:JSONDecode(HS:GetAsync("http://127.0.0.1:8766/tree.json", true))
for path, src in modules do
	local fn, err = loadstring(src)
	assert(fn, "doesn't compile: " .. path .. ": " .. tostring(err))
end
for _, c in f:GetChildren() do
	if c.Name == "App" or c.Name == "Engine" then
		c:Destroy()
	end
end
local paths = {}
for path in modules do
	table.insert(paths, path)
end
table.sort(paths) -- (parents before their children)
for _, path in paths do
	local cur, sofar = f, ""
	for part in string.gmatch(path, "[^/]+") do
		sofar = sofar == "" and part or (sofar .. "/" .. part)
		local nxt = cur:FindFirstChild(part)
		if not nxt then
			nxt = Instance.new(modules[sofar] and "ModuleScript" or "Folder")
			nxt.Name = part
			nxt.Archivable = false
			nxt.Parent = cur
		end
		cur = nxt
	end
	cur.Source = modules[path]
end
f:SetAttribute("Version", _G.SS_PushVersion)
f:SetAttribute("Build", _G.SS_PushBuild)
return string.format("pushed %d modules as %s (build %s)", #paths, _G.SS_PushVersion, tostring(_G.SS_PushBuild))
