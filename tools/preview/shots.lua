--[[
	Panel preview (a dev tool): loads the panel (panel.lua) and dumps it in each state _G.SS_Shots lists, in turn:
	{ { name, fn(App) }, … }. HttpService must be on for the call; server.py saves each as out/<name>.json.
]]
local HS = game:GetService("HttpService")
local URL = "http://127.0.0.1:8766/"
local panel = assert(loadstring(HS:GetAsync(URL .. "panel.lua", true)))()
local dumpSrc = HS:GetAsync(URL .. "dump.lua", true)
local App = _G.SS_Preview.app
local out = { panel }
for _, shot in _G.SS_Shots or {} do
	local ok, err = pcall(shot[2], App)
	task.wait(0.1)
	_G.SS_DumpName = shot[1]
	table.insert(out, shot[1] .. ": " .. (ok and assert(loadstring(dumpSrc))() or ("ERROR " .. tostring(err))))
end
return table.concat(out, "\n")
