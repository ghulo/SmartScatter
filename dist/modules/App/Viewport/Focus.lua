--[[
	Smart Scatter — Focus: while a tool of the plugin is on in the viewport (painting, erasing, drawing the path,
	brushing one object, removing copies), the world steps back a touch so the tool stands out: it loses a little
	colour (a colour correction on the camera, never saved with the place). Settings › Viewport can turn it off.
	What the tool is doing is said in one place, the viewport's header (Viewport/Toolbar); App.focusState tells it
	whether the tool takes things away (its name is red then).
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local G, tween, MED = App.G, App.tween, App.MED
	local new = App.new
	local LAYER_MODES = App.LAYER_MODES

	local LOOK = { Saturation = -0.18, Brightness = -0.03, Contrast = 0 } -- how far the world steps back
	local cc -- the camera's colour correction while focused

	-- what the tool is doing now: its name, what it works on, and whether it takes things away
	local function describe()
		local m = App.mode
		local shift = App.shiftHeld and App.shiftHeld()
		local area = App.area and App.area.folder.Name or nil
		local function on(...)
			local bits = {}
			for _, b in { ... } do
				if b then
					table.insert(bits, b)
				end
			end
			return table.concat(bits, "  ·  ")
		end
		if m == "Paint" or m == "Erase" then
			local erase = (m == "Erase") ~= (shift == true)
			return erase and "Erase" or "Paint", on(area, G.tool), erase
		elseif m == "Spline" and App.shapeTool then
			return App.shapeTool, on(area, App.shapeTool == "Rectangle" and "drag corner to corner" or "drag from the centre"), false
		elseif m == "Spline" then
			return "Draw path", on(area), false
		elseif m == "Stamp" then
			local inst = App.stamp and App.stamp.models[App.stamp.vi]
			return "Stamp", inst and inst.Name or nil, false
		elseif m == "Remove" then
			return "Remove copies", on(area, "click one"), true
		elseif m == "Select" then
			return "Select", "click a zone, a path or a copy", false
		elseif m == "Array" then
			return "Array", "drag along where the copies go", false
		elseif LAYER_MODES[m] then
			local act = shift and App.LAYER_OPPOSITE[m] or m
			local name = App.paintLayer and App.paintLayer.inst.Name or nil
			return App.LAYER_LABEL[act], (area and name) and (area .. "  ›  " .. name) or on(area, name), act == "None" or act == "Less"
		end
		return nil, nil, false
	end

	local shown = false
	App.focusState = describe
	-- takes the focus on or off (called whenever the mode, the tool or Shift changes)
	App.refreshFocus = function()
		local what = describe()
		local on = G.focus ~= false and what ~= nil
		if on then
			local cam = workspace.CurrentCamera
			if cam and not (cc and cc.Parent == cam) then
				cc = new(
					"ColorCorrectionEffect",
					{ Name = "SmartScatterFocus", Archivable = false, Saturation = 0, Brightness = 0, Contrast = 0, Parent = cam }
				)
			end
			if not shown and cc then
				tween(cc, MED, LOOK)
			end
			shown = true
		elseif shown then
			shown = false
			if cc then
				local gone = cc
				cc = nil
				tween(gone, MED, { Saturation = 0, Brightness = 0, Contrast = 0 })
				task.delay(0.3, function()
					gone:Destroy()
				end)
			end
		end
	end

	-- gone for good (the plugin unloads or updates)
	App.clearFocus = function()
		shown = false
		if cc then
			cc:Destroy()
			cc = nil
		end
	end
	-- (one left by an earlier load of the plugin; the panel preview leaves the real plugin's alone)
	local cam = workspace.CurrentCamera
	local old = cam and not App.ctx.preview and cam:FindFirstChild("SmartScatterFocus")
	if old then
		old:Destroy()
	end
	pcall(function()
		if App.ctx.preview then -- (the panel preview leaves the real plugin's alone)
			return
		end
		local g = game:GetService("CoreGui"):FindFirstChild("SmartScatterFocus")
		if g then
			g:Destroy()
		end
	end)
end
