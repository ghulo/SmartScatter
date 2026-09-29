--[[
	Smart Scatter — Curve and Road tabs: a path's own settings, for a Path or a zone that has one drawn. Curve: the
	path itself (length, points, Subdivide, Clear, the selected point), its strip and what it sticks to. Road: a solid
	road or dirt path down the middle.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	-- a Path always; a zone once a path is drawn through it
	local function hasCurve(thing)
		return thing.kind == "Path" or App.hasPath()
	end

	App.registerTab({
		id = "curve",
		icon = "spline",
		title = "Curve",
		order = 5,
		kinds = { Path = true, Zone = true },
		when = hasCurve,
		build = function(page)
			local cs = App.cards(page, "curve")
			local card = cs.add({
				id = "path",
				title = "Path",
				icon = "spline",
				sub = "Its points, branches and loops",
				keys = "draw path spline points vertex corner branch loop clear shape preset subdivide",
				build = App.buildPathInfo,
			})
			if App.kindOf(App.area) == "Path" then
				App.ui.step1Card = card
			end
			if App.hasPath() then
				cs.add({
					id = "curve",
					title = "Curve",
					sub = "The strip beside it, and what it sticks to",
					keys = "strip width snap surfaces walls closed loop",
					build = App.buildCurve,
				})
			end
		end,
	})

	App.registerTab({
		id = "road",
		icon = "road",
		title = "Road",
		order = 6,
		kinds = { Path = true, Zone = true },
		when = function(thing)
			return App.hasPath() and hasCurve(thing)
		end,
		build = function(page)
			App.cards(page, "road").add({
				id = "road",
				title = "Road",
				sub = "A solid road or path down the middle",
				keys = "road asphalt dirt style width thickness",
				build = App.buildRoad,
			})
		end,
	})
end
