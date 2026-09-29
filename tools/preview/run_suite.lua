--[[
	A dev run of the Studio suite against what's on disk (not the installed plugin's live copy): builds the module tree
	from tools/preview/server.py (/tree.json) as the loader would, points the suite at it (_G.SS_SuiteSource) and runs
	tests/suite.lua (served as /suite.lua). HttpService must be on for the call. Returns the suite's report.
]]
local HS = game:GetService("HttpService")
local URL = "http://127.0.0.1:8766/"
local modules = HS:JSONDecode(HS:GetAsync(URL .. "tree.json", true))
local holder = Instance.new("Folder")
holder.Name = "SS_SuiteCode"
holder:SetAttribute("Version", "disk")
local paths = {}
for path in modules do
	table.insert(paths, path)
end
table.sort(paths) -- (parents before their children)
for _, path in paths do
	local cur, sofar = holder, ""
	for part in string.gmatch(path, "[^/]+") do
		sofar = sofar == "" and part or (sofar .. "/" .. part)
		local nxt = cur:FindFirstChild(part)
		if not nxt then
			nxt = Instance.new(modules[sofar] and "ModuleScript" or "Folder")
			nxt.Name = part
			nxt.Parent = cur
		end
		cur = nxt
	end
	cur.Source = modules[path]
end
_G.SS_SuiteSource = holder
local ok, res = pcall(function()
	return assert(loadstring(HS:GetAsync(URL .. "suite.lua", true)))()
end)
_G.SS_SuiteSource = nil
holder:Destroy()
return ok and res or ("suite failed to run: " .. tostring(res))
