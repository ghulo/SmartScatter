"""Prints a Studio snippet that checks the loader's module-tree code for real: the loader's own normalize /
buildTree / readTree, the real App and Engine entries (init.lua), and a stand-in for every module they list. It
builds the tree, requires both entries, checks every module ran once in ORDER with E / I / App passed along, reads
the tree back, and removes it. Returns "loader tree ok" or what went wrong."""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import tree as T  # noqa: E402

loader = T.read(T.ROOT / "Loader.lua")
fns = [T.loader_function(loader, name) for name in ("normalize", "buildTree", "readTree")]
t = T.tree()
mods = {"App": t["App"], "Engine": t["Engine"]}
for entry, arg in (("App", "App"), ("Engine", "E, I")):
    for path in T.order(t[entry]):
        # each stand-in notes that it ran, in which order, and with what
        mods[entry + "/" + path] = (
            "return function(%s)\n\t_G.SS_ran = _G.SS_ran or {}\n\ttable.insert(_G.SS_ran, \"%s/%s\")\n" % (arg, entry, path)
            + ("\tI.seen = (I.seen or 0) + 1\n\tE[\"%s\"] = true\n" % path if entry == "Engine" else "\tApp[\"%s\"] = true\n" % path)
            + ("\treturn function() _G.SS_cleaned = true end\n" if entry == "App" and path == T.order(t["App"])[-1] else "")
            + "end\n"
        )
expected = ["Engine/" + p for p in T.order(t["Engine"])] + ["App/" + p for p in T.order(t["App"])]
body = "\n".join("\t[\"%s\"] = [======[%s]======]," % (k, v) for k, v in mods.items())
assert "]======]" not in "".join(mods.values())
print('local ENTRIES = { App = true, Engine = true, Main = true }')
print("\n".join(fns))
print("local MODULES = {\n%s\n}" % body)
print("local EXPECTED = { %s }" % ", ".join('"%s"' % e for e in expected))
print('''local code = normalize({ build = 1, version = "test", modules = MODULES })
if not code or code.app ~= "App" then return "normalize refused the tree" end
local holder = Instance.new("Folder")
holder.Name = "SS_LoaderTest"
holder.Archivable = false
local made = buildTree(code.modules, holder, false)
holder.Parent = game:GetService("ServerStorage")
_G.SS_ran, _G.SS_cleaned = {}, nil
local ok, err = pcall(function()
	local E = require(made.Engine)
	local cleanup = require(made[code.app])({ Engine = E })
	if E.TAG ~= "SmartScatter" then error("engine constants missing") end
	cleanup()
end)
local problem = not ok and ("failed: " .. tostring(err)) or nil
if not problem then
	if #_G.SS_ran ~= #EXPECTED then problem = "ran " .. #_G.SS_ran .. " modules, expected " .. #EXPECTED end
	for k = 1, #EXPECTED do
		if not problem and _G.SS_ran[k] ~= EXPECTED[k] then problem = "order: " .. tostring(_G.SS_ran[k]) .. " where " .. EXPECTED[k] .. " belongs" end
	end
	if not problem and not _G.SS_cleaned then problem = "the last module's cleanup was not handed back" end
end
if not problem then
	local back = readTree(holder)
	for path, src in MODULES do
		if back[path] ~= src then problem = "read back differently: " .. path break end
	end
	for path in back do
		if not MODULES[path] then problem = "read back an extra module: " .. path break end
	end
end
if not problem and normalize({ build = 1, Engine = "return {}", Main = "return 1", Parts = { Main_2 = "return {}" } }).app ~= "Main" then
	problem = "a flattened (older) release is no longer accepted"
end
holder:Destroy()
_G.SS_ran, _G.SS_cleaned = nil, nil
return problem or ("loader tree ok: " .. #EXPECTED .. " modules in order, read back intact")''')
