--[[
	Smart Scatter — World tab (always there, whatever is selected): the finished map as a whole. Scanning it for
	repeated models and keeping the originals, swapping models, re-spacing a layout, seasons; and telling the scan
	what a part is when it guesses wrong.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	App.registerTab({
		id = "world",
		icon = "search",
		title = "World",
		order = 90,
		kinds = "all",
		build = function(page)
			local cs = App.cards(page, "world")
			cs.add({
				id = "mapscan",
				title = "Map scan",
				icon = "search",
				sub = "Every repeated model in a finished map, grouped by shape",
				keys = "scan kinds copies find repeated models select duplicates",
				build = App.buildMapScan,
			})
			cs.add({
				id = "swap",
				title = "Swap models",
				sub = "Replace every copy of a kind with another model or a mix",
				keys = "swap replace model mix kind copies preview try",
				build = App.buildSwap,
			})
			cs.add({
				id = "layout",
				title = "Improve layout",
				sub = "Re-space crowded and empty spots, by the placement rules",
				keys = "layout spacing crowded empty holes gaps respace even tidy hand placed",
				build = App.buildImproveLayout,
			})
			cs.add({
				id = "seasons",
				title = "Seasons",
				sub = "Snowy, autumn or dry, fully or in patches",
				keys = "season snow winter autumn fall dry summer colour color terrain",
				build = App.buildSeasons,
			})
			cs.add({
				id = "snapshot",
				title = "Snapshot",
				sub = "Keep the originals, and put them back with one click",
				keys = "save keep originals restore backup revert",
				build = App.buildSnapshot,
			})
			if App.area then
				cs.add({
					id = "scanfix",
					title = "Fix what the scan sees",
					keys = "mark road path building water rescan",
					more = true,
					build = App.buildScanFix,
				})
			end
		end,
	})
end
