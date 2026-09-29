--[[
	Smart Scatter — Objects tab (a zone or a path): what it places. The list (click one to open it in the Object tab),
	adding models from the Explorer, how much and how big everything is; a biome, presets and the cost report under
	More options, and bringing back copies taken out one by one.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	App.registerTab({
		id = "objects",
		icon = "layers",
		title = "Objects",
		order = 10,
		kinds = { Zone = true, Path = true },
		build = function(page)
			local a = App.area
			local cs = App.cards(page, "objects")
			local empty = #a.layers == 0
			cs.add({
				id = "objects",
				title = "Objects",
				icon = "layers",
				sub = App.kindOf(a) == "Path" and "What lines the path, and how much of everything"
					or "The models that fill this zone, and how much of everything",
				keys = "add models amount size everything list lost",
				build = function(b)
					App.objectList(b)
					App.ui.step2Card = b.Parent
				end,
			})
			cs.add({
				id = "biomes",
				title = "Start from a biome",
				sub = "A ready mix of objects made from your models",
				keys = "forest meadow desert town sample models",
				more = not empty,
				build = App.buildBiomes,
			})
			cs.add({ id = "presets", title = "Presets", keys = "save share code import reuse", more = true, build = App.presetsBox })
			cs.add({
				id = "performance",
				title = "Performance",
				sub = "Which objects cost the most parts",
				keys = "report parts meshes heavy lag simplify",
				more = true,
				build = App.buildReport,
			})
			cs.add({
				id = "removecopies",
				title = "Copies taken out",
				icon = "close",
				sub = "Single copies removed with the strip's Remove copies tool stay out",
				keys = "remove delete copy copies bring back",
				more = true,
				build = App.removeCopiesBox,
			})
		end,
	})
end
