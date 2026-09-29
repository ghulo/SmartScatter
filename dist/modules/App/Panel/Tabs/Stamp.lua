--[[
	Smart Scatter — Stamps: the one outliner entry for everything stamped (Workspace › Stamps, plain models no area
	owns), and its Stamp tab: what the stamp puts down and how (Panel/StampTools). The tool itself is the strip's.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	App.registerKind({
		kind = "Stamps",
		icon = "stamp",
		title = "Stamps",
		order = 40,
		list = function()
			return { App.stampsThing() }
		end,
		count = function(thing)
			return thing.folder and #thing.folder:GetChildren() or 0
		end,
	})
	App.registerTab({
		id = "stamp",
		icon = "stamp",
		title = "Stamp",
		order = 10,
		kinds = { Stamps = true },
		build = function(page)
			App.cards(page, "stamp").add({
				id = "stamp",
				title = "Stamp",
				icon = "stamp",
				sub = "One model, exactly where you click: no area needed",
				keys = "stamp single one copy model place put rotate turn size anywhere",
				build = App.buildStampCard,
			})
		end,
	})
end
