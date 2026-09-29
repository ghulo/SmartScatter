--[[
	Smart Scatter — Zone tab (a zone or a keep-clear zone): the ground itself. What's painted and the overlay's colours;
	then, for a zone, the look of the whole zone (pattern, colour zones, edges and wind); under More options, which
	surfaces painting sticks to and tidying the painted edge.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	App.registerTab({
		id = "zone",
		icon = "area",
		title = "Zone",
		order = 30,
		kinds = { Zone = true, Clear = true },
		build = function(page)
			local clear = App.kindOf(App.area) == "Clear"
			local cs = App.cards(page, "zone")
			if clear then
				cs.add({
					id = "clearzone",
					title = "Keep-clear zone",
					icon = "clear",
					sub = "Nothing from any area goes here: spawns, doorways, a quest NPC's spot",
					build = function(b)
						App.explain(b, "Paint where nothing may go with the ground tools in the viewport's strip. Every area keeps off it.")
					end,
				})
			end
			local card = cs.add({
				id = "ground",
				title = "Ground",
				icon = "brush",
				sub = clear and "Where nothing may go" or "What's painted, and what the colours mean",
				keys = "paint ground brush lasso box polygon fill erase all delete size shape reach selected parts overlay colours",
				build = App.buildGround,
			})
			App.ui.step1Card = card
			if not clear then
				cs.add({
					id = "pattern",
					title = "Pattern",
					sub = "Where everything thickens and thins together",
					keys = "groves natural islands veins spots bands strength noise patches",
					build = App.buildPattern,
				})
				cs.add({
					id = "zones",
					title = "Colour zones",
					sub = "Tint objects by the pattern: autumn, dry, lush, frost",
					keys = "color mood autumn dry lush frost tint season",
					more = true,
					build = App.buildZones,
				})
				cs.add({
					id = "edges",
					title = "Edges and wind",
					sub = "Fade into the surroundings, and which way things lean",
					keys = "soft edges border fade wind direction lean",
					more = true,
					build = function(b)
						App.buildEdges(b)
						App.buildWind(b)
					end,
				})
			end
			cs.add({
				id = "paintfilter",
				title = "Paint only on",
				sub = "Painting and erasing stick to these surfaces",
				keys = "filter surfaces grass road rock sand snow",
				more = true,
				build = App.buildPaintFilter,
			})
			cs.add({
				id = "tidy",
				title = "Tidy the edge",
				sub = "Fill holes, smooth, grow or shrink what's painted",
				keys = "fill holes smooth grow shrink cleanup",
				more = true,
				build = App.buildTidy,
			})
		end,
	})
end
