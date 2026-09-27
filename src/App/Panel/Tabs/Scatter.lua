--[[
	Smart Scatter — Scatter tab: what fills the area. The objects and how much of everything, or one object's rules
	when it's open; then the look of the whole area (pattern, colour zones, edges, wind), biomes, presets and the
	performance report under More options.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local vlist, col = App.vlist, App.col

	-- one object open: a way back, then its settings
	local function buildObject(page)
		App.pageHead(page, "All objects", nil, function()
			App.showObject(nil)
		end)
		App.objectInspector(col({ Parent = page }, { vlist(10) }))
	end

	App.buildScatterTab = function(page)
		local a = App.area
		if a and App.expanded and not App.searching() then
			buildObject(page)
			return
		end
		local cs = App.cards(page, "scatter")
		local kind = a and App.kindOf(a)
		if kind == "Clear" then
			cs.add({
				id = "clearzone",
				title = "Keep-clear zone",
				icon = "clear",
				sub = "Nothing from any area goes here: spawns, doorways, a quest NPC's spot",
				build = function(b)
					App.goNote(b, "This zone holds no objects. Paint where to keep clear on the Brush tab.", "Paint the zone", "Brush")
				end,
			})
			return
		end
		local shaped = a and ((a.count or 0) > 0 or App.hasPath())
		cs.add({
			id = "objects",
			title = "Objects",
			icon = "layers",
			sub = "The models that fill this area, and how much of everything",
			keys = "add models amount size everything list lost",
			build = function(b)
				if a and not shaped then
					if kind == "Path" then
						App.goNote(b, "Draw the path first, on the Map tab. Then add what lines it.", "Draw the path", "Map")
					else
						App.goNote(b, "Paint the ground first, on the Brush tab. Then add what fills it.", "Paint the area", "Brush")
					end
				end
				if a then
					App.objectList(b)
				else
					App.emptyState(b, "No area yet", "Make a scatter area or a path first: the + next to the area picker.")
				end
				App.ui.step2Card = b.Parent
			end,
		})
		if not a then
			return
		end
		local empty = #a.layers == 0
		cs.add({
			id = "biomes",
			title = "Start from a biome",
			sub = "A ready mix of objects made from your models",
			keys = "forest meadow desert town sample models",
			more = not empty,
			build = App.buildBiomes,
		})
		cs.add({
			id = "pattern",
			title = "Pattern",
			sub = "Where everything thickens and thins together",
			keys = "groves natural islands veins spots bands strength noise patches",
			more = true,
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
		cs.add({
			id = "presets",
			title = "Presets",
			keys = "save share code import reuse",
			more = true,
			build = App.presetsBox,
		})
		cs.add({
			id = "performance",
			title = "Performance",
			sub = "Which objects cost the most parts",
			keys = "report parts meshes heavy lag simplify",
			more = true,
			build = App.buildReport,
		})
		if App.searching() then -- every object's rules too, under its name
			for i, l in a.layers do
				local holder = col({ LayoutOrder = 200000 + i, Parent = page }, { vlist(10) })
				App.label(l.inst.Name, 13, App.P.text, App.SANS_B, { Parent = holder })
				local before = App.cardCount
				App.objectRules(l, holder)
				if App.cardCount == before then
					holder:Destroy()
				end
			end
		end
	end
end
