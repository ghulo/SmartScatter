--[[
	Smart Scatter — Map tab: the shapes on the map. The path (drawing it, its curve and its road), and telling the
	scan what the parts of the map are.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	App.buildMapTab = function(page)
		local a = App.area
		local cs = App.cards(page, "map")
		local kind = a and App.kindOf(a)
		local drawn = App.hasPath()
		if kind ~= "Clear" then
			local isPath = kind == "Path"
			local card = cs.add({
				id = "path",
				title = isPath and "Draw the path" or "Path through this area",
				icon = "spline",
				tag = not isPath and "Optional" or nil,
				sub = drawn and (isPath and "Click to add more points, or drag one to move it" or "Objects set to follow it line it")
					or (isPath and "Click in the viewport to place points" or "A road, fence or row of lamps along a curve you draw"),
				keys = "draw path spline points corner branch loop clear",
				build = App.buildDrawTools,
			})
			if isPath then
				App.ui.step1Card = card
			end
			if drawn then
				cs.add({
					id = "curve",
					title = "Curve",
					sub = "The strip beside it, and what it sticks to",
					keys = "strip width snap surfaces walls closed loop",
					build = App.buildCurve,
				})
				cs.add({
					id = "road",
					title = "Road",
					sub = "A solid road or path down the middle",
					keys = "road asphalt dirt style width thickness",
					build = App.buildRoad,
				})
			end
		end
		cs.add({
			id = "scanfix",
			title = "Fix what the scan sees",
			keys = "mark road path building water rescan",
			more = kind ~= "Clear",
			build = App.buildScanFix,
		})
	end
end
